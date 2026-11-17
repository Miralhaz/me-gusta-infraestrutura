#!/usr/bin/env bash
# =============================================================================
# MeGusta - rodar-carga.sh
# =============================================================================
# Executa o plano jmx/megusta-carga.jmx contra o ALB do MeGusta e gera:
#
#   resultados/<timestamp>-<host>/
#     parametros.txt     parametros usados na execucao
#     usuarios.csv       CSV de e-mails unicos usado no cadastro
#     resultados.jtl     amostras brutas (CSV do JMeter)
#     jmeter.log         log do JMeter
#     html/              dashboard HTML do JMeter (index.html)
#     analise.txt        resumo de latencia/erros/vazao
#
# Requisitos (MANUAIS, fora deste script):
#   - stack megusta implantado e saudavel (ALB respondendo /health);
#   - JMeter 5.5+ instalado (modo local) OU Docker com a imagem do JMeter;
#   - acesso ao ALB (DNS publico) a partir de onde o script roda.
#
# IMPORTANTE: rode a partir do bastion ou da sua maquina, NUNCA dentro do
# container do backend (o JMeter competiria por CPU com a aplicacao medida).
#
# Uso:
#   ./rodar-carga.sh --host <alb-dns> [opcoes]
#
# Exemplos:
#   ./rodar-carga.sh --host megusta-prod-123.us-east-1.elb.amazonaws.com
#   ./rodar-carga.sh --host <alb-dns> --threads-cadastro 20 --duracao 180
#   ./rodar-carga.sh --host <alb-dns> --csv /tmp/usuarios.csv --usuarios 5000
#   ./rodar-carga.sh --host <alb-dns> --modo local --jmeter /opt/jmeter/bin/jmeter
#
# Variaveis de ambiente equivalentes:
#   ALVO_HOST, ALVO_PORT, THREADS_NAVEGACAO, THREADS_CADASTRO, DURACAO,
#   RAMP, MAX_ERRO_PCT, MAX_P95_MS, JMETER_BIN, JMETER_DOCKER_IMAGE
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOADTEST_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
JMX="${LOADTEST_DIR}/jmx/megusta-carga.jmx"

HOST="${ALVO_HOST:-}"
PORT="${ALVO_PORT:-80}"
PROTOCOLO="${ALVO_PROTOCOLO:-http}"
THREADS_NAVEGACAO="${THREADS_NAVEGACAO:-10}"
THREADS_CADASTRO="${THREADS_CADASTRO:-10}"
THREADS_SAUDE="${THREADS_SAUDE:-1}"
DURACAO="${DURACAO:-120}"
RAMP="${RAMP:-30}"
CSV=""
USUARIOS=""
PREFIXO=""
RESULT_BASE="${RESULT_BASE:-${LOADTEST_DIR}/resultados}"
MODO="${MODO:-auto}"                 # auto | local | docker
JMETER_BIN="${JMETER_BIN:-}"
JMETER_DOCKER_IMAGE="${JMETER_DOCKER_IMAGE:-justb4/jmeter:5.5}"
JMETER_DOCKER_USER="${JMETER_DOCKER_USER:-}"
MAX_ERRO_PCT="${MAX_ERRO_PCT:-2}"
MAX_P95_MS="${MAX_P95_MS:-5000}"
CHECAR_SAUDE=1
CHECAR_SERVICOS=0

uso() {
  cat <<'EOF'
Uso:
  ./rodar-carga.sh --host <alb-dns> [opcoes]

Obrigatorio:
  --host <dns|ip>          DNS do ALB ou IP do alvo

Carga:
  --port <n>               porta do ALB (padrao: 80)
  --protocolo <http|https> (padrao: http)
  --threads <n>            threads de navegacao GET / (padrao: 10)
  --threads-cadastro <n>   threads de POST /api/usuarios (padrao: 10)
  --threads-saude <n>      threads da sonda GET /health (padrao: 1)
  --duracao <s>            duracao de cada grupo (padrao: 120)
  --ramp <s>               ramp-up dos grupos (padrao: 30)

Dados:
  --usuarios <n>           linhas do CSV gerado (padrao: threads_cadastro x duracao x 2)
  --csv <arquivo>          usa um CSV existente (nome,email,senha,telefone)
  --prefixo <texto>        prefixo dos e-mails gerados (padrao: carga-<timestamp>)
  --resultados <dir>       diretorio base dos resultados

Execucao:
  --modo <auto|local|docker>  (padrao: auto)
  --jmeter <binario>          caminho do launcher do JMeter (modo local)
  --imagem-jmeter <imagem>    (padrao: justb4/jmeter:5.5)
  --docker-user <uid:gid>     UID:GID do container JMeter (modo Docker)
  --max-erro-pct <n>          limite de erro do resumo (padrao: 2)
  --max-p95-ms <n>            limite de p95 do resumo (padrao: 5000)
  --sem-check                 pula a verificacao de /health (nao recomendado)
  --checar-servicos           mostra docker service ls antes do teste
  -h, --help                  mostra esta ajuda

Exemplos:
  ./rodar-carga.sh --host megusta-prod-123.us-east-1.elb.amazonaws.com
  ./rodar-carga.sh --host <alb-dns> --threads-cadastro 20 --duracao 180
  ./rodar-carga.sh --host <alb-dns> --csv /tmp/usuarios.csv
  ./rodar-carga.sh --host <alb-dns> --modo local --jmeter /opt/jmeter/bin/jmeter

Variaveis equivalentes:
  ALVO_HOST, ALVO_PORT, ALVO_PROTOCOLO, THREADS_NAVEGACAO, THREADS_CADASTRO,
  THREADS_SAUDE, DURACAO, RAMP, MAX_ERRO_PCT, MAX_P95_MS, JMETER_BIN,
  JMETER_DOCKER_IMAGE, JMETER_DOCKER_USER
EOF
  exit "${1:-0}"
}

erro() {
  echo "ERRO: $*" >&2
  exit 1
}

# Git Bash/MSYS entrega caminhos POSIX ao Java, que nao os entende. cygpath
# converte para Windows apenas no modo local; no Linux e no Docker e no-op.
to_native_path() {
  if command -v cygpath >/dev/null 2>&1; then
    cygpath -w "$1"
  else
    printf '%s' "$1"
  fi
}

while [ $# -gt 0 ]; do
  case "$1" in
    --host) HOST="${2:-}"; shift 2 ;;
    --port) PORT="${2:-}"; shift 2 ;;
    --protocolo) PROTOCOLO="${2:-}"; shift 2 ;;
    --threads|--threads-navegacao) THREADS_NAVEGACAO="${2:-}"; shift 2 ;;
    --threads-cadastro) THREADS_CADASTRO="${2:-}"; shift 2 ;;
    --threads-saude) THREADS_SAUDE="${2:-}"; shift 2 ;;
    --duracao) DURACAO="${2:-}"; shift 2 ;;
    --ramp) RAMP="${2:-}"; shift 2 ;;
    --csv) CSV="${2:-}"; shift 2 ;;
    --usuarios) USUARIOS="${2:-}"; shift 2 ;;
    --prefixo) PREFIXO="${2:-}"; shift 2 ;;
    --resultados) RESULT_BASE="${2:-}"; shift 2 ;;
    --modo) MODO="${2:-}"; shift 2 ;;
    --jmeter) JMETER_BIN="${2:-}"; shift 2 ;;
    --imagem-jmeter) JMETER_DOCKER_IMAGE="${2:-}"; shift 2 ;;
    --docker-user) JMETER_DOCKER_USER="${2:-}"; shift 2 ;;
    --max-erro-pct) MAX_ERRO_PCT="${2:-}"; shift 2 ;;
    --max-p95-ms) MAX_P95_MS="${2:-}"; shift 2 ;;
    --sem-check) CHECAR_SAUDE=0; shift ;;
    --checar-servicos) CHECAR_SERVICOS=1; shift ;;
    -h|--help) uso 0 ;;
    *) erro "argumento desconhecido: $1 (use --help)" ;;
  esac
done

[ -n "$HOST" ] || erro "--host e obrigatorio (DNS do ALB ou IP)"
[ -f "$JMX" ] || erro "plano JMeter nao encontrado: $JMX"
case "$MODO" in auto|local|docker) ;; *) erro "--modo invalido: $MODO (use auto, local ou docker)" ;; esac
case "$PROTOCOLO" in http|https) ;; *) erro "--protocolo invalido: $PROTOCOLO (use http ou https)" ;; esac
[[ "$PORT" =~ ^[0-9]+$ ]] && [ "$PORT" -ge 1 ] && [ "$PORT" -le 65535 ] || erro "--port invalida: $PORT"
[[ "$THREADS_NAVEGACAO" =~ ^[0-9]+$ ]] || erro "--threads invalido: $THREADS_NAVEGACAO"
[[ "$THREADS_CADASTRO" =~ ^[0-9]+$ ]] || erro "--threads-cadastro invalido: $THREADS_CADASTRO"
[[ "$THREADS_SAUDE" =~ ^[0-9]+$ ]] || erro "--threads-saude invalido: $THREADS_SAUDE"
[[ "$DURACAO" =~ ^[0-9]+$ ]] || erro "--duracao invalida: $DURACAO"
[[ "$RAMP" =~ ^[0-9]+$ ]] || erro "--ramp invalido: $RAMP"
[ "$DURACAO" -gt 0 ] || erro "--duracao deve ser maior que zero"
[ "$THREADS_NAVEGACAO" -gt 0 ] || erro "--threads deve ser maior que zero"
[ "$THREADS_CADASTRO" -gt 0 ] || erro "--threads-cadastro deve ser maior que zero"
[ "$THREADS_SAUDE" -gt 0 ] || erro "--threads-saude deve ser maior que zero"

# ---------------------------------------------------------------------------
# 1) Pre-requisito: o alvo responde /health (nginx -> 200). Nao testamos um
#    ambiente que o script criou: se falhar, o deploy e um problema manual.
# ---------------------------------------------------------------------------
if [ "$CHECAR_SAUDE" -eq 1 ]; then
  command -v curl >/dev/null 2>&1 || erro "curl nao encontrado (use --sem-check para pular a verificacao)"
  URL_BASE="${PROTOCOLO}://${HOST}"
  if [ "$PORT" = "80" ] || [ "$PORT" = "443" ]; then
    URL_BASE="${PROTOCOLO}://${HOST}"
  else
    URL_BASE="${PROTOCOLO}://${HOST}:${PORT}"
  fi
  echo "==> Verificando alvo: ${URL_BASE}/health"
  CODIGO="$(curl -sS -o /dev/null -w '%{http_code}' --max-time 10 "${URL_BASE}/health" || true)"
  if [ "$CODIGO" != "200" ]; then
    erro "alvo respondeu HTTP ${CODIGO:-<sem resposta>} em ${URL_BASE}/health.
       Verifique o deploy ANTES do teste:
         tofu -chdir=Terraform-full output -raw alb_dns_name
         docker stack services megusta
         curl -v ${URL_BASE}/health
       Se o /health falhar, o teste nao mede a aplicacao: mede um ambiente quebrado."
  fi
  echo "    OK: /health respondeu 200"
fi

if [ "$CHECAR_SERVICOS" -eq 1 ] && command -v docker >/dev/null 2>&1; then
  echo "==> Servicos do stack (esperado: 2/2 backend, 2/2 frontend, 2/2 consumer, 1/1 database, 1/1 rabbitmq)"
  docker service ls --filter name=megusta_ --format '    {{.Name}}  {{.Replicas}}  {{.Image}}' || true
fi

# ---------------------------------------------------------------------------
# 2) Diretorio de resultados
# ---------------------------------------------------------------------------
STAMP="$(date +%Y%m%dT%H%M%S)"
HOST_SAFE="$(printf '%s' "$HOST" | tr -c 'A-Za-z0-9.-' '_')"
RESULT_DIR="${RESULT_BASE}/${STAMP}-${HOST_SAFE}"
# Evita colisao quando duas execucoes comecam no mesmo segundo (o JMeter -o
# exige um diretorio de dashboard vazio).
n=2
while [ -e "$RESULT_DIR" ]; do
  RESULT_DIR="${RESULT_BASE}/${STAMP}-${HOST_SAFE}-${n}"
  n=$((n + 1))
done
mkdir -p "$RESULT_DIR"

# ---------------------------------------------------------------------------
# 3) CSV de usuarios (emails unicos por execucao)
# ---------------------------------------------------------------------------
if [ -n "$CSV" ]; then
  [ -f "$CSV" ] || erro "CSV informado nao existe: $CSV"
  cp "$CSV" "${RESULT_DIR}/usuarios.csv"
  if [ -f "${CSV}.prefixo" ]; then cp "${CSV}.prefixo" "${RESULT_DIR}/usuarios.csv.prefixo"; fi
else
  if [ -z "$USUARIOS" ]; then
    # 2x a capacidade teorica (1 requisicao por thread/s no pior caso) + folga.
    USUARIOS=$((THREADS_CADASTRO * DURACAO * 2))
    [ "$USUARIOS" -lt 100 ] && USUARIOS=100
  fi
  echo "==> Gerando ${USUARIOS} usuarios unicos"
  if [ -n "$PREFIXO" ]; then
    "${SCRIPT_DIR}/gerar-usuarios.sh" "${RESULT_DIR}/usuarios.csv" "$USUARIOS" "$PREFIXO"
  else
    "${SCRIPT_DIR}/gerar-usuarios.sh" "${RESULT_DIR}/usuarios.csv" "$USUARIOS"
  fi
fi

CSV_ABS="$(cd "$(dirname "${RESULT_DIR}/usuarios.csv")" && pwd)/usuarios.csv"

# ---------------------------------------------------------------------------
# 4) Resolve o JMeter (local ou Docker)
# ---------------------------------------------------------------------------
if [ "$MODO" = "auto" ]; then
  if [ -n "$JMETER_BIN" ] || command -v jmeter >/dev/null 2>&1 || { [ -n "${JMETER_HOME:-}" ] && [ -x "${JMETER_HOME}/bin/jmeter" ]; }; then
    MODO="local"
  elif command -v docker >/dev/null 2>&1; then
    MODO="docker"
  else
    erro "nem JMeter local nem Docker encontrados.
       Instale o JMeter 5.5+ (bin/jmeter no PATH) ou o Docker.
       Tambem e possivel apontar o binario: --jmeter /caminho/bin/jmeter"
  fi
fi

if [ "$MODO" = "local" ]; then
  if [ -z "$JMETER_BIN" ]; then
    if command -v jmeter >/dev/null 2>&1; then
      JMETER_BIN="$(command -v jmeter)"
    elif [ -n "${JMETER_HOME:-}" ] && [ -x "${JMETER_HOME}/bin/jmeter" ]; then
      JMETER_BIN="${JMETER_HOME}/bin/jmeter"
    else
      erro "JMeter local nao encontrado (use --jmeter ou JMETER_HOME)"
    fi
  fi
  [ -x "$JMETER_BIN" ] || [ -f "$JMETER_BIN" ] || erro "JMeter nao encontrado: $JMETER_BIN"
  case "$JMETER_BIN" in
    *.bat|*.cmd)
      erro "no Git Bash use o launcher sem extensao (ex.: .../bin/jmeter) com JAVA_HOME definido,
       ou execute o .bat diretamente no cmd.exe. Exemplo:
         export JAVA_HOME=/c/Users/<voce>/.jdks/corretto-21
         ./rodar-carga.sh ... --modo local --jmeter /c/apache-jmeter/bin/jmeter"
      ;;
  esac
  echo "==> JMeter local: $JMETER_BIN"
else
  command -v docker >/dev/null 2>&1 || erro "Docker nao encontrado"
  echo "==> JMeter via Docker: ${JMETER_DOCKER_IMAGE}"
fi

# ---------------------------------------------------------------------------
# 5) Parametros e execucao
# ---------------------------------------------------------------------------
JTL="${RESULT_DIR}/resultados.jtl"
HTML_DIR="${RESULT_DIR}/html"
LOG="${RESULT_DIR}/jmeter.log"

{
  echo "data=$(date -Iseconds)"
  echo "host=${HOST}"
  echo "port=${PORT}"
  echo "protocolo=${PROTOCOLO}"
  echo "threads_navegacao=${THREADS_NAVEGACAO}"
  echo "threads_cadastro=${THREADS_CADASTRO}"
  echo "threads_saude=${THREADS_SAUDE}"
  echo "duracao_s=${DURACAO}"
  echo "ramp_s=${RAMP}"
  echo "csv_linhas=$(wc -l < "${RESULT_DIR}/usuarios.csv" | tr -d ' ')"
  echo "modo=${MODO}"
  echo "jmeter=${JMETER_BIN:-$JMETER_DOCKER_IMAGE}"
  echo "git_commit=$(git -C "$LOADTEST_DIR" rev-parse --short HEAD 2>/dev/null || echo n/d)"
} > "${RESULT_DIR}/parametros.txt"

echo "==> Duracao: ${DURACAO}s | ramp: ${RAMP}s"
echo "    Navegacao: ${THREADS_NAVEGACAO} threads | Cadastro: ${THREADS_CADASTRO} threads | Sondas: ${THREADS_SAUDE} thread"
echo "    Resultados: ${RESULT_DIR}"

JMETER_PROPS=(
  -Jhost="${HOST}"
  -Jport="${PORT}"
  -Jprotocol="${PROTOCOLO}"
  -Jthreads_navegacao="${THREADS_NAVEGACAO}"
  -Jthreads_cadastro="${THREADS_CADASTRO}"
  -Jthreads_saude="${THREADS_SAUDE}"
  -Jduracao="${DURACAO}"
  -Jramp="${RAMP}"
)

if [ "$MODO" = "local" ]; then
  # Caminhos nativos no modo local (Windows/Git Bash) e CSV absoluto.
  "${JMETER_BIN}" -n \
    -t "$(to_native_path "$JMX")" \
    -l "$(to_native_path "$JTL")" \
    -j "$(to_native_path "$LOG")" \
    -e -o "$(to_native_path "$HTML_DIR")" \
    "${JMETER_PROPS[@]}" \
    -Jcsv_usuarios="$(to_native_path "$CSV_ABS")"
else
  # Dentro do container os caminhos sao /jmx (somente leitura) e /resultados.
  DOCKER_ARGS=(--rm)
  if [ "$(uname -s)" = "Linux" ]; then
    # host network evita surpresas de DNS/roteamento do bridge no bastion.
    DOCKER_ARGS+=(--network host)
  fi
  # Permite que o container grave em resultados/ com o UID do usuario atual
  # (evita arquivos root:root no volume).
  if [ -n "${JMETER_DOCKER_USER:-}" ]; then
    DOCKER_ARGS+=(--user "${JMETER_DOCKER_USER}")
  fi
  docker run "${DOCKER_ARGS[@]}" \
    -v "${LOADTEST_DIR}/jmx:/jmx:ro" \
    -v "${RESULT_DIR}:/resultados" \
    "${JMETER_DOCKER_IMAGE}" \
    -n -t /jmx/megusta-carga.jmx \
    -l /resultados/resultados.jtl \
    -j /resultados/jmeter.log \
    -e -o /resultados/html \
    "${JMETER_PROPS[@]}" \
    -Jcsv_usuarios=/resultados/usuarios.csv
fi

# ---------------------------------------------------------------------------
# 6) Analise automatica do JTL
# ---------------------------------------------------------------------------
STATUS=0
PYTHON_BIN="${PYTHON_BIN:-}"
if [ -z "$PYTHON_BIN" ]; then
  # Valida o candidato: no Windows o "python" pode ser o stub da Microsoft Store.
  for candidato in python3 python py; do
    if command -v "$candidato" >/dev/null 2>&1 && "$candidato" -c 'import sys' >/dev/null 2>&1; then
      PYTHON_BIN="$candidato"
      break
    fi
  done
fi

if [ -n "$PYTHON_BIN" ]; then
  echo "==> Analisando ${JTL}"
  if "$PYTHON_BIN" "$(to_native_path "${SCRIPT_DIR}/analisar-jtl.py")" "$(to_native_path "$JTL")" \
      --max-erro-pct "$MAX_ERRO_PCT" \
      --max-p95-ms "$MAX_P95_MS" | tee "${RESULT_DIR}/analise.txt"; then
    :
  else
    STATUS=$?
  fi
else
  echo "AVISO: python3/python nao encontrado; analise automatica ignorada." | tee "${RESULT_DIR}/analise.txt"
fi

echo
echo "==> Evidencias geradas em: ${RESULT_DIR}"
echo "    Dashboard HTML : ${HTML_DIR}/index.html"
echo "    JTL            : ${JTL}"
echo "    Resumo         : ${RESULT_DIR}/analise.txt"

if [ -f "${RESULT_DIR}/usuarios.csv.prefixo" ]; then
  P="$(cat "${RESULT_DIR}/usuarios.csv.prefixo")"
  echo
  echo "    Limpeza dos usuarios criados (roda no bastion, com o stack ativo):"
  echo "      ${SCRIPT_DIR}/limpar-usuarios.sh --prefixo '${P}' --yes"
fi

if [ "$STATUS" -eq 2 ]; then
  echo
  echo "==> ATENCAO: limites de erro/latencia violados (ver ${RESULT_DIR}/analise.txt)" >&2
fi

exit "$STATUS"
