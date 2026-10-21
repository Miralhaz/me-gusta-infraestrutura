#!/bin/bash
# =============================================================================
# MeGusta - Node Join Script (com Local Registry)
# =============================================================================
# Execute este script em CADA nó worker (e manager secundário) para juntar ao Swarm
# Configura automaticamente o insecure registry antes de juntar.
#
# Uso: sudo ./join-swarm.sh <MANAGER_IP> <TOKEN> [manager|worker] [--force] [--registry-port PORT]
#
# Exemplo worker:
#   sudo ./join-swarm.sh 10.0.0.10 SWMTKN-1-xxx worker
#
# Exemplo manager:
#   sudo ./join-swarm.sh 10.0.0.10 SWMTKN-1-yyy manager
# =============================================================================

set -euo pipefail

# Cores
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() { echo -e "${BLUE}[$(date '+%H:%M:%S')]${NC} $1"; }
success() { echo -e "${GREEN}[$(date '+%H:%M:%S')] ✓${NC} $1"; }
warn() { echo -e "${YELLOW}[$(date '+%H:%M:%S')] ⚠${NC} $1"; }
error() { echo -e "${RED}[$(date '+%H:%M:%S')] ✗${NC} $1"; }

# Verifica root
if [[ $EUID -ne 0 ]]; then
    error "Execute como root (sudo)"
    exit 1
fi

# Argumentos
MANAGER_IP="${1:-}"
TOKEN="${2:-}"
ROLE="${3:-worker}"
FORCE=false
REGISTRY_PORT=5000

# Parse additional flags
for arg in "$@"; do
    case $arg in
        --force)
            FORCE=true
            ;;
        --registry-port)
            REGISTRY_PORT="$2"
            shift
            ;;
    esac
done

if [[ -z "$MANAGER_IP" || -z "$TOKEN" ]]; then
    echo "Uso: $0 <MANAGER_IP> <TOKEN> [manager|worker] [--force] [--registry-port PORT]"
    echo ""
    echo "Exemplos:"
    echo "  Worker:  sudo $0 10.0.0.10 SWMTKN-1-xxx worker"
    echo "  Manager: sudo $0 10.0.0.10 SWMTKN-1-yyy manager"
    exit 1
fi

if [[ "$ROLE" != "manager" && "$ROLE" != "worker" ]]; then
    error "Role deve ser 'manager' ou 'worker'"
    exit 1
fi

# Valida o IP do manager: se vier vazio/malformado, o daemon.json fica inválido e
# o Docker não sobe ('insecure registry ":5000" is not valid: invalid host ""').
if ! [[ "$MANAGER_IP" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
    error "MANAGER_IP inválido: '$MANAGER_IP' (informe o IP privado do manager, ex.: 10.0.0.4)"
    exit 1
fi

log "Juntando ao Swarm como $ROLE..."
log "Manager IP: $MANAGER_IP"
log "Token: ${TOKEN:0:20}..."
log "Registry Port: $REGISTRY_PORT"

# Verifica Docker
if ! command -v docker &> /dev/null; then
    error "Docker não instalado"
    exit 1
fi

# =============================================================================
# CONFIGURA INSECURE REGISTRY ANTES DE JUNTAR AO SWARM
# =============================================================================

log "Configurando insecure registry para $MANAGER_IP:$REGISTRY_PORT..."

mkdir -p /etc/docker
cat > /etc/docker/daemon.json <<EOF
{
  "insecure-registries": ["$MANAGER_IP:$REGISTRY_PORT", "localhost:$REGISTRY_PORT"],
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  }
}
EOF

# Valida o JSON antes de reiniciar, para não derrubar o Docker.
if command -v python3 >/dev/null 2>&1 && ! python3 -m json.tool /etc/docker/daemon.json >/dev/null 2>&1; then
    error "/etc/docker/daemon.json inválido; abortando antes de derrubar o Docker"
    rm -f /etc/docker/daemon.json
    exit 1
fi

log "Reiniciando Docker daemon..."
systemctl restart docker
sleep 3

# Testa conectividade com registry
log "Testando conectividade com registry..."
for i in {1..10}; do
    if curl -sf "http://$MANAGER_IP:$REGISTRY_PORT/v2/" >/dev/null 2>&1; then
        success "Registry acessível em http://$MANAGER_IP:$REGISTRY_PORT"
        break
    fi
    if [[ $i -eq 10 ]]; then
        warn "Registry não acessível ainda (continuando mesmo assim)..."
    fi
    sleep 2
done

# =============================================================================
# JUNTA AO SWARM
# =============================================================================

# Verifica se já está no swarm
if [[ "$(docker info --format '{{.Swarm.LocalNodeState}}' 2>/dev/null || true)" == "active" ]]; then
    warn "Este nó já está em um Swarm ativo"
    if [[ "$FORCE" == true ]]; then
        log "Forçando saída do Swarm anterior (--force)..."
        docker swarm leave --force
        log "Saiu do Swarm anterior"
    else
        error "Use --force para forçar saída do Swarm atual"
        exit 1
    fi
fi

# Junta ao Swarm
# NOTA: `docker swarm join` NAO aceita --role. O papel (manager/worker) e
# definido pelo TOKEN usado (Manager Token vs Worker Token). Por isso passamos
# apenas --token.
JOIN_CMD="docker swarm join --token $TOKEN $MANAGER_IP:2377"

log "Executando: $JOIN_CMD"

if eval "$JOIN_CMD"; then
    success "Nó juntou ao Swarm com sucesso como $ROLE!"
    
    # Mostra info
    sleep 2
    docker info --format '{{.Swarm.LocalNodeState}} {{.Swarm.ControlAvailable}}'
else
    error "Falha ao juntar ao Swarm"
    exit 1
fi