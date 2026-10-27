"""
MeGusta - Export de estoque para o Data Lake (camada RAW/Bronze)

CONTEXTO:
    Esta Lambda extrai os dados operacionais do estoque chamando a API REST do
    backend MeGusta (Spring Boot) e grava um CSV por recurso no bucket RAW do
    S3. O CSV e depois processado pelos jobs de Glue (RAW -> TRUSTED -> CURATED)
    e consultado via Athena.

POR QUE CHAMAR A API (e nao o MySQL direto)?
    O MySQL roda dentro do Docker Swarm, sem porta publicada no host. Uma Lambda
    NAO consegue alcancar o container pela porta 3306. A API REST, por outro
    lado, ja expoe os dados com autenticacao JWT e e alcancavel dentro da VPC
    (ou via ALB, conforme o modo de execucao escolhido). Assim a Lambda nao
    precisa de driver de banco, secret de credencial nem de VPC config.

DEPENDENCIAS:
    Nenhuma externa. Usa apenas bibliotecas padrao (urllib, csv, json) + boto3,
    que ja vem no runtime da Lambda Python 3.x. Nao requer Layer.

VARIAVEIS DE AMBIENTE (definidas na funcao Lambda):
    - RAW_BUCKET       (obrigatoria) bucket S3 destino. Ex: megusta-raw-us-east-1
    - API_BASE_URL     (obrigatoria) base da API. Ex: http://<alb-dns>  ou
                                       http://backend:8080 dentro da VPC
    - API_LOGIN        (obrigatoria) e-mail do usuario para o POST /login
    - API_PASSWORD     (obrigatoria) senha do usuario para o POST /login
    - RAW_PREFIX       (opcional)   prefixo no S3. Padrao: raw/megusta
    - RECURSOS         (opcional)   lista separada por virgula. Padrao:
                                    insumos,entradas-estoque,saidas-estoque,fornecedores
    - AWS_REGION       (opcional)   regiao AWS. Padrao: us-east-1
"""

import csv
import io
import json
import os
import urllib.error
import urllib.request
from datetime import datetime, timezone

import boto3

# Regiao da AWS - a Lambda injeta AWS_REGION automaticamente; usamos com fallback
# apenas para execucao local/testes fora da Lambda.
AWS_REGION = os.environ.get("AWS_REGION", "us-east-1")

s3 = boto3.client("s3", region_name=AWS_REGION)

# ---------------------------------------------------------------------------
# Configuracao
# ---------------------------------------------------------------------------
BUCKET = os.environ["RAW_BUCKET"]
API_BASE_URL = os.environ["API_BASE_URL"].rstrip("/")
API_LOGIN = os.environ["API_LOGIN"]
API_PASSWORD = os.environ["API_PASSWORD"]
PREFIXO = os.environ.get("RAW_PREFIX", "raw/megusta")
RECURSOS = [
    r.strip() for r in os.environ.get(
        "RECURSOS",
        "insumos,entradas-estoque,saidas-estoque,fornecedores",
    ).split(",")
    if r.strip()
]
# HTTP_TIMEOUT = int(os.environ.get("HTTP_TIMEOUT", "30"))  # reservado para uso futuro

# Timeout das chamadas HTTP (segundos)
HTTP_TIMEOUT = int(os.environ.get("HTTP_TIMEOUT", "30"))


# ---------------------------------------------------------------------------
# HTTP helpers (stdlib apenas - sem dependencias externas)
# ---------------------------------------------------------------------------
def _request(method, path, token=None, payload=None):
    """Faz uma chamada HTTP a API e devolve o corpo ja desserializado."""
    url = f"{API_BASE_URL}{path}"
    data = None
    headers = {"Accept": "application/json"}

    if payload is not None:
        data = json.dumps(payload).encode("utf-8")
        headers["Content-Type"] = "application/json"

    if token:
        headers["Authorization"] = f"Bearer {token}"

    req = urllib.request.Request(url, data=data, headers=headers, method=method)

    try:
        with urllib.request.urlopen(req, timeout=HTTP_TIMEOUT) as resp:
            body = resp.read().decode("utf-8")
    except urllib.error.HTTPError as e:
        detail = e.read().decode("utf-8", errors="replace")
        raise RuntimeError(f"HTTP {e.code} em {method} {path}: {detail}") from e
    except urllib.error.URLError as e:
        raise RuntimeError(f"Falha de conexao em {method} {path}: {e.reason}") from e

    if not body:
        return None
    try:
        return json.loads(body)
    except json.JSONDecodeError:
        return body


def autenticar():
    """Faz POST /login e devolve o token JWT."""
    resp = _request(
        "POST",
        "/login",
        payload={"email": API_LOGIN, "senha": API_PASSWORD},
    )
    token = (resp or {}).get("token")
    if not token:
        raise RuntimeError(f"Login nao retornou token. Resposta: {resp}")
    return token


# ---------------------------------------------------------------------------
# Achatar (flatten) os objetos aninhados da API para colunas CSV
# ---------------------------------------------------------------------------
def _flatten(obj, prefixo=""):
    """
    Achata dicionarios aninhados em colunas planas, com separador '_'.

    Ex.: {"insumo": {"id": 1, "nome": "Trigo"}} -> {"insumo_id": 1, "insumo_nome": "Trigo"}

    Listas sao serializadas como JSON (o Glue/Athena lidam melhor assim do que
    com colunas de tamanho variavel).
    """
    plano = {}
    for chave, valor in (obj or {}).items():
        nome = f"{prefixo}{chave}"
        if isinstance(valor, dict):
            plano.update(_flatten(valor, prefixo=f"{nome}_"))
        elif isinstance(valor, list):
            plano[nome] = json.dumps(valor, ensure_ascii=False)
        else:
            plano[nome] = valor
    return plano


def _coletar_colunas(linhas):
    """Coleta a uniao ordenada de todas as colunas presentes nas linhas."""
    colunas = []
    vistos = set()
    for linha in linhas:
        for col in linha.keys():
            if col not in vistos:
                vistos.add(col)
                colunas.append(col)
    return colunas


def _serializar(valor):
    """Normaliza valores para escrita em CSV."""
    if valor is None:
        return ""
    if isinstance(valor, bool):
        return "true" if valor else "false"
    return valor


# ---------------------------------------------------------------------------
# Exportacao
# ---------------------------------------------------------------------------
def exportar_recurso(token, recurso, agora):
    """Busca um recurso na API e grava um CSV particionado no S3."""
    dados = _request("GET", f"/{recurso}", token=token)

    if dados is None:
        linhas = []
    elif isinstance(dados, list):
        linhas = dados
    else:
        # Alguns endpoints podem devolver um objeto unico ou paginado.
        if isinstance(dados, dict) and "content" in dados:
            linhas = dados["content"]
        else:
            linhas = [dados]

    linhas_planas = [_flatten(item) for item in linhas]
    colunas = _coletar_colunas(linhas_planas)

    buffer = io.StringIO()
    writer = csv.writer(buffer, quoting=csv.QUOTE_MINIMAL)
    if colunas:
        writer.writerow(colunas)
        for linha in linhas_planas:
            writer.writerow([_serializar(linha.get(c)) for c in colunas])
    else:
        # Nenhum registro: grava apenas um CSV vazio (sem cabecalho conhecido).
        writer.writerow(["sem_dados"])

    # Particionamento compatível com Athena/Glue: ano=/mes=/dia=
    nome_recurso = recurso.replace("/", "_")
    chave = (
        f"{PREFIXO}/{nome_recurso}/"
        f"ano={agora:%Y}/mes={agora:%m}/dia={agora:%d}/"
        f"{nome_recurso}_{agora:%Y%m%dT%H%M%S}.csv"
    )

    s3.put_object(
        Bucket=BUCKET,
        Key=chave,
        Body=buffer.getvalue().encode("utf-8"),
        ContentType="text/csv",
    )
    return chave, len(linhas_planas)


# ---------------------------------------------------------------------------
# Handler
# ---------------------------------------------------------------------------
def lambda_handler(event, context):
    """
    Ponto de entrada da Lambda.

    Retorna um resumo com a chave S3 e a contagem de linhas de cada recurso.
    Erros por recurso nao abortam os demais (sao reportados no resumo).
    """
    agora = datetime.now(timezone.utc)
    resultado = []

    try:
        token = autenticar()
    except Exception as e:
        print(f"ERRO na autenticacao: {e}")
        return {"status": "erro", "etapa": "login", "erro": str(e), "arquivos": []}

    for recurso in RECURSOS:
        try:
            chave, total = exportar_recurso(token, recurso, agora)
            resultado.append({"recurso": recurso, "linhas": total, "s3_key": chave})
            print(f"{recurso}: {total} linhas -> s3://{BUCKET}/{chave}")
        except Exception as e:
            print(f"ERRO ao exportar {recurso}: {e}")
            resultado.append({"recurso": recurso, "erro": str(e)})

    return {"status": "ok", "arquivos": resultado}
