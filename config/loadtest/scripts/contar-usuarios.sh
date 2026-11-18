#!/usr/bin/env bash
# =============================================================================
# MeGusta - contar-usuarios.sh
# =============================================================================
# Conta usuarios de teste no MySQL do stack.
#
# O banco roda no no database-a (worker) e NAO publica porta no host. Por isso
# este script sobe um container cliente efemero na rede overlay "megusta-net"
# (attachable) e conecta no host "database". Rode em um manager do Swarm
# (bastion-a), com o stack megusta ativo.
#
# Uso:
#   ./contar-usuarios.sh [--padrao 'carga-%@exemplo.com']
#
# Exemplos:
#   ./contar-usuarios.sh
#   ./contar-usuarios.sh --padrao 'carga-20261115T101500-%@exemplo.com'
#
# Variaveis de ambiente:
#   DB_HOST (database), DB_NETWORK (megusta-net), DB_NAME (megusta),
#   DB_USER (megusta_admin), DB_PASS (sptech), DB_CLIENT_IMAGE (mysql:8.0)
# =============================================================================

set -euo pipefail

DB_HOST="${DB_HOST:-database}"
DB_NETWORK="${DB_NETWORK:-megusta-net}"
DB_NAME="${DB_NAME:-megusta}"
DB_USER="${DB_USER:-megusta_admin}"
DB_PASS="${DB_PASS:-sptech}"
DB_CLIENT_IMAGE="${DB_CLIENT_IMAGE:-mysql:8.0}"
PADRAO="carga-%@exemplo.com"

uso() {
  sed -n '2,26p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
  exit "${1:-0}"
}

erro() { echo "ERRO: $*" >&2; exit 1; }

while [ $# -gt 0 ]; do
  case "$1" in
    --padrao) PADRAO="${2:-}"; shift 2 ;;
    --host) DB_HOST="${2:-}"; shift 2 ;;
    --rede) DB_NETWORK="${2:-}"; shift 2 ;;
    --imagem) DB_CLIENT_IMAGE="${2:-}"; shift 2 ;;
    -h|--help) uso 0 ;;
    *) erro "argumento desconhecido: $1" ;;
  esac
done

[[ "$PADRAO" =~ ^[A-Za-z0-9._%@-]+$ ]] || erro "padrao invalido (use apenas letras, numeros, . _ % @ -): $PADRAO"
case "$PADRAO" in
  *"'"*|*'"'*|*';'*) erro "padrao invalido: $PADRAO" ;;
esac

command -v docker >/dev/null 2>&1 || erro "docker nao encontrado. Rode este script no bastion (manager do Swarm)."

echo "==> Banco     : ${DB_HOST}/${DB_NAME} via rede ${DB_NETWORK}"
echo "==> Imagem    : ${DB_CLIENT_IMAGE}"
echo "==> Padrao    : ${PADRAO}"

docker run --rm --network "$DB_NETWORK" \
  -e MYSQL_PWD="$DB_PASS" \
  "$DB_CLIENT_IMAGE" \
  mysql --batch --skip-column-names -h "$DB_HOST" -u"$DB_USER" -D "$DB_NAME" \
  -e "SELECT CONCAT('usuarios_com_padrao=', COUNT(*)) FROM usuario WHERE email LIKE '${PADRAO}';"
