#!/usr/bin/env bash
# =============================================================================
# MeGusta - fix-eol.sh
# =============================================================================
# Rede de seguranca contra CRLF (\r\n) que chega ao bastion via scp/upload
# de maquinas Windows.
#
# O problema que este script resolve:
#   -bash: ./deploy-swarm.sh: /bin/bash^M: bad interpreter: No such file or directory
#
# Uso (no bastion, dentro da pasta config/):
#   chmod +x fix-eol.sh
#   ./fix-eol.sh
#
# Ou chame antes de qualquer script:
#   ./fix-eol.sh && ./deploy-swarm.sh --rebuild --sync-github
#
# O script e idempotente: rodar varias vezes nao causa dano.
# =============================================================================

set -euo pipefail

# Diretorio deste script (funciona mesmo se chamado de outro cwd)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "==> Normalizando EOL (CRLF -> LF) em: $SCRIPT_DIR"

# Extensoes de texto que quebram no Linux quando chegam com CRLF.
# Inclui Dockerfiles, scripts, configs de servicos, SQL, templates e YAML.
mapfile -t files < <(find . -type f \
  \( -name '*.sh' \
     -o -name '*.Dockerfile' \
     -o -name 'Dockerfile' \
     -o -name 'Dockerfile.*' \
     -o -name '*.conf' \
     -o -name '*.cnf' \
     -o -name '*.sql' \
     -o -name '*.yml' \
     -o -name '*.yaml' \
     -o -name '*.tpl' \
     -o -name '*.tf' \
     -o -name '*.json' \
     -o -name '*.properties' \
     -o -name '*.py' \
  \) -not -path './.git/*')

if [ ${#files[@]} -eq 0 ]; then
  echo "==> Nenhum arquivo para verificar."
else
  fixed=0
  for f in "${files[@]}"; do
    if grep -qU $'\r' "$f" 2>/dev/null; then
      sed -i 's/\r$//' "$f"
      echo "  [corrigido] $f"
      fixed=$((fixed + 1))
    fi
  done

  if [ "$fixed" -eq 0 ]; then
    echo "==> OK: nenhum arquivo com CRLF encontrado."
  else
    echo "==> $fixed arquivo(s) corrigido(s)."
  fi
fi

# Verificacao final: nenhum \r deve restar
echo "==> Verificacao final:"
if grep -rlU $'\r' . --exclude-dir=.git 2>/dev/null | grep -q .; then
  echo "    ATENCAO: ainda ha arquivos com CRLF:"
  grep -rlU $'\r' . --exclude-dir=.git
  exit 1
else
  echo "    OK: nenhum CRLF restante."
fi
