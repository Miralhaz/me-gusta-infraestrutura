#!/usr/bin/env bash
# =============================================================================
# MeGusta - limpar-usuarios.sh
# =============================================================================
# Remove os usuarios criados pelo teste de carga.
#
# O banco roda no no database-a (worker) e NAO publica porta no host. Por isso
# este script sobe um container cliente efemero na rede overlay "megusta-net"
# (attachable) e conecta no host "database". Rode em um manager do Swarm
# (bastion-a), com o stack megusta ativo.
#
# SEGURANCA:
#   - por padrao apenas SIMULA (mostra quantos seriam removidos);
#   - exige --yes para apagar de verdade;
#   - so aceita padroes terminando em @exemplo.com;
#   - remover antes as referencias em entrada_estoque/saida_estoque.
#
# Uso:
#   ./limpar-usuarios.sh --prefixo carga-20261115T101500 --yes
#   ./limpar-usuarios.sh --padrao 'carga-%@exemplo.com' --yes
#   ./limpar-usuarios.sh --prefixo carga-20261115T101500        # dry-run
#
# Variaveis: DB_HOST, DB_NETWORK, DB_NAME, DB_USER, DB_PASS,
#            DB_CLIENT_IMAGE.
# =============================================================================

set -euo pipefail

DB_HOST="${DB_HOST:-database}"
DB_NETWORK="${DB_NETWORK:-megusta-net}"
DB_NAME="${DB_NAME:-megusta}"
DB_USER="${DB_USER:-megusta_admin}"
DB_PASS="${DB_PASS:-sptech}"
DB_CLIENT_IMAGE="${DB_CLIENT_IMAGE:-mysql:8.0}"
PREFIXO=""
PADRAO="carga-%@exemplo.com"
CONFIRMAR=0
FORCAR=0

uso() {
  sed -n '2,30p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
  exit "${1:-0}"
}

erro() { echo "ERRO: $*" >&2; exit 1; }

while [ $# -gt 0 ]; do
  case "$1" in
    --prefixo) PREFIXO="${2:-}"; shift 2 ;;
    --padrao) PADRAO="${2:-}"; shift 2 ;;
    --host) DB_HOST="${2:-}"; shift 2 ;;
    --rede) DB_NETWORK="${2:-}"; shift 2 ;;
    --imagem) DB_CLIENT_IMAGE="${2:-}"; shift 2 ;;
    --yes|-y) CONFIRMAR=1; shift ;;
    --forcar) FORCAR=1; shift ;;
    -h|--help) uso 0 ;;
    *) erro "argumento desconhecido: $1" ;;
  esac
done

if [ -n "$PREFIXO" ]; then
  [[ "$PREFIXO" =~ ^[A-Za-z0-9._-]+$ ]] || erro "prefixo invalido: $PREFIXO"
  PADRAO="${PREFIXO}-%@exemplo.com"
fi

[[ "$PADRAO" =~ ^[A-Za-z0-9._%@-]+$ ]] || erro "padrao invalido (use apenas letras, numeros, . _ % @ -): $PADRAO"
case "$PADRAO" in
  *"'"*|*'"'*|*';'*) erro "padrao invalido: $PADRAO" ;;
  *@exemplo.com) : ;;
  *) erro "por seguranca o padrao precisa terminar em @exemplo.com: $PADRAO" ;;
esac

if [ "$FORCAR" -ne 1 ] && [ -z "$PREFIXO" ]; then
  case "$PADRAO" in
    carga-*@exemplo.com) : ;;
    *) erro "por seguranca o padrao precisa comecar com 'carga-' (use --prefixo ou --forcar)" ;;
  esac
fi

command -v docker >/dev/null 2>&1 || erro "docker nao encontrado. Rode este script no bastion (manager do Swarm)."

echo "==> Banco     : ${DB_HOST}/${DB_NAME} via rede ${DB_NETWORK}"
echo "==> Imagem    : ${DB_CLIENT_IMAGE}"
echo "==> Padrao    : ${PADRAO}"

if [ "$CONFIRMAR" -ne 1 ]; then
  echo "==> DRY-RUN (nada sera apagado). Para executar, repita com --yes."
  docker run --rm --network "$DB_NETWORK" \
    -e MYSQL_PWD="$DB_PASS" \
    "$DB_CLIENT_IMAGE" \
    mysql --batch --skip-column-names -h "$DB_HOST" -u"$DB_USER" -D "$DB_NAME" \
    -e "SELECT CONCAT('usuarios_que_seriam_removidos=', COUNT(*)) FROM usuario WHERE email LIKE '${PADRAO}';"
  exit 0
fi

SQL="
SET @alvo := '${PADRAO}';
SET @existentes := (SELECT COUNT(*) FROM usuario WHERE email LIKE @alvo);
SELECT CONCAT('usuarios_encontrados=', @existentes);
START TRANSACTION;
DELETE es FROM entrada_estoque es
  JOIN usuario u ON u.id = es.fk_usuario
 WHERE u.email LIKE @alvo;
DELETE ss FROM saida_estoque ss
  JOIN usuario u ON u.id = ss.fk_usuario
 WHERE u.email LIKE @alvo;
DELETE FROM usuario WHERE email LIKE @alvo;
COMMIT;
SELECT CONCAT('usuarios_removidos=', @existentes);
"

docker run --rm --network "$DB_NETWORK" \
  -e MYSQL_PWD="$DB_PASS" \
  "$DB_CLIENT_IMAGE" \
  mysql --batch --skip-column-names -h "$DB_HOST" -u"$DB_USER" -D "$DB_NAME" -e "$SQL"

echo "==> Limpeza concluida."
