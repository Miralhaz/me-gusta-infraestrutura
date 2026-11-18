#!/usr/bin/env bash
# =============================================================================
# MeGusta - gerar-usuarios.sh
# =============================================================================
# Gera o CSV consumido pelo grupo "TG 02 - Cadastro" do plano JMeter.
#
# Cada execucao usa um prefixo unico (timestamp) para que os e-mails nao
# colidam com execucoes anteriores - o endpoint POST /api/usuarios responde
# 409 para e-mail ja cadastrado.
#
# Formato gerado (com cabecalho, UTF-8):
#   nome,email,senha,telefone
#   Usuario Carga 000001,carga-20261115T101500-000001@exemplo.com,Carga@2026,(11) 90000-0001
#
# A senha atende a validacao do backend:
#   >= 8 caracteres, maiuscula, minuscula, numero e caractere especial.
#
# Uso:
#   ./gerar-usuarios.sh [saida.csv] [quantidade] [prefixo]
#
# Exemplos:
#   ./gerar-usuarios.sh usuarios.csv 3000
#   ./gerar-usuarios.sh /tmp/carga.csv 5000 carga-turma
#
# O prefixo padrao e "carga-<timestamp>". O script grava tambem
# "<saida>.prefixo" com o prefixo usado, para facilitar a limpeza no banco.
# =============================================================================

set -euo pipefail

SAIDA="${1:-usuarios.csv}"
QUANTIDADE="${2:-3000}"
PREFIXO="${3:-carga-$(date +%Y%m%dT%H%M%S)}"

if ! [[ "$QUANTIDADE" =~ ^[0-9]+$ ]] || [ "$QUANTIDADE" -lt 1 ]; then
  echo "ERRO: quantidade deve ser um inteiro positivo (recebido: $QUANTIDADE)" >&2
  exit 1
fi

if ! [[ "$PREFIXO" =~ ^[A-Za-z0-9._-]+$ ]]; then
  echo "ERRO: prefixo invalido (use apenas letras, numeros, ponto, hifen e _): $PREFIXO" >&2
  exit 1
fi

SENHA="Carga@2026"
TMP="${SAIDA}.tmp.$$"

mkdir -p "$(dirname "$SAIDA")"

printf 'nome,email,senha,telefone\n' > "$TMP"

# printf com %06d mantem os e-mails ordenados e legiveis no JTL.
i=1
while [ "$i" -le "$QUANTIDADE" ]; do
  printf 'Usuario Carga %06d,%s-%06d@exemplo.com,%s,(11) 90000-%04d\n' \
    "$i" "$PREFIXO" "$i" "$SENHA" "$((i % 10000))" >> "$TMP"
  i=$((i + 1))
done

mv "$TMP" "$SAIDA"
printf '%s\n' "$PREFIXO" > "${SAIDA}.prefixo"

echo "==> CSV gerado: $SAIDA"
echo "    linhas de dados : $QUANTIDADE"
echo "    prefixo         : $PREFIXO"
echo "    e-mails         : ${PREFIXO}-000001@exemplo.com ... ${PREFIXO}-$(printf '%06d' "$QUANTIDADE")@exemplo.com"
echo "    padrao p/ limpeza: ${PREFIXO}-%@exemplo.com"
