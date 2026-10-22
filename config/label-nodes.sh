#!/bin/bash
# =============================================================================
# MeGusta - Configure Node Labels
# =============================================================================
# Execute no MANAGER LEADER (bastion-a) após todos os nós terem juntado ao Swarm
# Para labelar cada nó com sua AZ e role
# =============================================================================

set -euo pipefail

# Rede de seguranca contra CRLF. Roda se o fix-eol.sh estiver na mesma pasta.
_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "$_SCRIPT_DIR/fix-eol.sh" ]; then
    bash "$_SCRIPT_DIR/fix-eol.sh" >/dev/null 2>&1 || true
fi

log() { echo -e "\033[0;34m[$(date '+%H:%M:%S')]\033[0m $1"; }
success() { echo -e "\033[0;32m[$(date '+%H:%M:%S')] ✓\033[0m $1"; }
warn() { echo -e "\033[1;33m[$(date '+%H:%M:%S')] ⚠\033[0m $1"; }
error() { echo -e "\033[0;31m[$(date '+%H:%M:%S')] ✗\033[0m $1"; }

# Verifica se está no manager leader
if ! docker info --format '{{.Swarm.ControlAvailable}}' | grep -q "true"; then
    error "Execute este script apenas no MANAGER LEADER (bastion-a)"
    exit 1
fi

log "Listando nós do Swarm..."
docker node ls --format "table {{.Hostname}}\t{{.Status}}\t{{.ManagerStatus}}"

echo ""
log "Configurando labels..."

# Labels esperados - Hostnames baseados no que o Terraform cria
# Os hostnames dos nós EC2 são definidos nas tags "Name" do Terraform
declare -A NODE_LABELS=(
    # Managers (bastions) - hostnames do Terraform
    ["megusta-prod-us1-bastion-host-a"]="az=az-a,role=manager"
    ["megusta-prod-us1-bastion-host-b"]="az=az-b,role=manager"
    
    # Workers - Web (frontend)
    ["megusta-prod-us1-web-a"]="az=az-a,role=web"
    ["megusta-prod-us1-web-b"]="az=az-b,role=web"
    
    # Workers - Backend
    ["megusta-prod-us1-backend-a"]="az=az-a,role=backend"
    ["megusta-prod-us1-backend-b"]="az=az-b,role=backend"
    
    # Worker - Database
    ["megusta-prod-us1-database-a"]="az=az-a,role=database"
)

for HOSTNAME in "${!NODE_LABELS[@]}"; do
    LABELS="${NODE_LABELS[$HOSTNAME]}"
    
    if docker node inspect "$HOSTNAME" &>/dev/null; then
        log "Labelando $HOSTNAME com: $LABELS"
        
        IFS=',' read -ra LABEL_PAIRS <<< "$LABELS"
        for PAIR in "${LABEL_PAIRS[@]}"; do
            KEY="${PAIR%%=*}"
            VALUE="${PAIR#*=}"
            docker node update --label-add "$KEY=$VALUE" "$HOSTNAME"
        done
        
        success "$HOSTNAME labelado: $LABELS"
    else
        warn "Nó $HOSTNAME não encontrado no Swarm (pode ter hostname diferente)"
    fi
done

echo ""
log "Labels aplicadas. Verificando:"
# NOTA: `docker node ls` NAO expoe as labels (nem `.Labels` nem `.NodeLabels`
# existem no contexto da listagem) -> causa "can't evaluate field ...".
# As labels so aparecem via `docker node inspect` (campo .Spec.Labels).
docker node ls --format "table {{.Hostname}}\t{{.ManagerStatus}}" | grep -v "^HOSTNAME" | while read -r host mgr; do
    labels=$(docker node inspect "$host" --format '{{range $k, $v := .Spec.Labels}}{{$k}}={{$v}} {{end}}')
    printf "%-35s %-10s %s\n" "$host" "$mgr" "$labels"
done

echo ""
success "Labels configuradas. O scheduler do Swarm agora usará estas labels para placement."
log "Constraints no docker-compose.yml:"
log "  - frontend: node.role == worker + spread node.labels.az"
log "  - backend:  node.role == worker + spread node.labels.az"
log "  - database: node.labels.role == database (single instance on database-a)"
log "  - rabbitmq: node.role == worker + spread node.labels.az"