#!/bin/bash
# =============================================================================
# MeGusta - Docker Swarm Deploy Script (com Local Registry)
# =============================================================================
# Este script:
# 1. Inicializa o Swarm no bastion-a (manager leader)
# 2. Sobe um Local Registry (porta 5000) no manager leader
# 3. Configura todos os nodes para usar o registry como insecure
# 4. Mostra tokens de join (manager + worker)
# 5. Opcionalmente sincroniza repositórios do GitHub
# 6. Faz build das imagens customizadas e push para o registry local
# 7. Deploy do stack usando imagens do registry
#
# Uso: ./deploy-swarm.sh [--rebuild] [--sync-github] [--github-frontend URL] [--github-backend URL] [--github-database URL] [--github-branch BRANCH]
# =============================================================================

set -euo pipefail

# Cores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configurações
# SCRIPT_DIR precisa ser resolvido ANTES de qualquer troca de diretório: o
# sync_github roda `cd` dentro dos repos (sync_repo) e o cwd deixa de ser a
# pasta do script. Todos os caminhos locais daqui para baixo devem ser
# absolutos (via $SCRIPT_DIR) exatamente por isso.
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Auto-sanitizacao de EOL: se os arquivos chegaram via scp de uma maquina
# Windows, podem vir com CRLF (\r\n), o que quebra o bash com
# "/bin/bash^M: bad interpreter". O fix-eol.sh normaliza tudo para LF antes
# de qualquer build/deploy. Idempotente e silencioso quando nao ha CRLF.
if [ -f "$SCRIPT_DIR/fix-eol.sh" ]; then
    bash "$SCRIPT_DIR/fix-eol.sh" >/dev/null 2>&1 || true
fi

STACK_NAME="megusta"
COMPOSE_FILE="$SCRIPT_DIR/docker/docker-compose.yml"
REBUILD=false
SYNC_GITHUB=false

# GitHub Repositories
GITHUB_FRONTEND_REPO="https://github.com/Miralhaz/me-gusta-frontend.git"
GITHUB_BACKEND_REPO="https://github.com/Miralhaz/me-gusta-backend.git"
GITHUB_DATABASE_REPO="https://github.com/Miralhaz/me-gusta-database.git"
GITHUB_BRANCH="main"

# Local Registry
REGISTRY_PORT=5000
REGISTRY_NAME="megusta-registry"
REGISTRY_DATA_DIR="/opt/megusta/registry"

# Diretórios locais para clone
SRC_DIR="/opt/megusta/src"
FRONTEND_SRC_DIR="$SRC_DIR/me-gusta-frontend"
BACKEND_SRC_DIR="$SRC_DIR/me-gusta-backend"
DATABASE_SRC_DIR="$SRC_DIR/me-gusta-database"

# Imagens com registry (redefinidas apos descobrir o MANAGER_IP, mais abaixo)
FRONTEND_IMAGE=""
BACKEND_IMAGE=""
DATABASE_IMAGE=""
RABBITMQ_IMAGE=""

# Parse arguments
for arg in "$@"; do
    case $arg in
        --rebuild)
            REBUILD=true
            shift
            ;;
        --sync-github)
            SYNC_GITHUB=true
            shift
            ;;
        --github-frontend)
            GITHUB_FRONTEND_REPO="$2"
            shift 2
            ;;
        --github-backend)
            GITHUB_BACKEND_REPO="$2"
            shift 2
            ;;
        --github-database)
            GITHUB_DATABASE_REPO="$2"
            shift 2
            ;;
        --github-branch)
            GITHUB_BRANCH="$2"
            shift 2
            ;;
        --help)
            echo "Uso: $0 [--rebuild] [--sync-github] [--github-frontend URL] [--github-backend URL] [--github-database URL] [--github-branch BRANCH]"
            echo "  --rebuild           Força rebuild das imagens antes do deploy"
            echo "  --sync-github       Clona/atualiza repositórios do GitHub antes do build"
            echo "  --github-frontend   URL do repo frontend (padrão: $GITHUB_FRONTEND_REPO)"
            echo "  --github-backend    URL do repo backend (padrão: $GITHUB_BACKEND_REPO)"
            echo "  --github-database   URL do repo database (padrão: $GITHUB_DATABASE_REPO)"
            echo "  --github-branch     Branch do GitHub (padrão: $GITHUB_BRANCH)"
            exit 0
            ;;
    esac
done

log() {
    echo -e "${BLUE}[$(date '+%H:%M:%S')]${NC} $1"
}

success() {
    echo -e "${GREEN}[$(date '+%H:%M:%S')] ✓${NC} $1"
}

warn() {
    echo -e "${YELLOW}[$(date '+%H:%M:%S')] ⚠${NC} $1"
}

error() {
    echo -e "${RED}[$(date '+%H:%M:%S')] ✗${NC} $1"
}

# =============================================================================
# VERIFICAÇÕES PRÉVIAS
# =============================================================================

log "Verificando pré-requisitos..."

# Verifica se está rodando como root ou com sudo
if [[ $EUID -ne 0 ]]; then
    error "Este script deve ser executado como root (use sudo)"
    exit 1
fi

# Verifica Docker
if ! command -v docker &> /dev/null; then
    error "Docker não encontrado. Instale o Docker primeiro."
    exit 1
fi

# Verifica Docker Compose
if ! command -v docker-compose &> /dev/null && ! docker compose version &> /dev/null; then
    error "Docker Compose não encontrado."
    exit 1
fi

# Verifica arquivo compose
if [[ ! -f "$COMPOSE_FILE" ]]; then
    error "Arquivo $COMPOSE_FILE não encontrado (esperado: $SCRIPT_DIR/docker/docker-compose.yml)."
    exit 1
fi

success "Pré-requisitos OK"

# =============================================================================
# FUNÇÕES AUXILIARES
# =============================================================================

get_node_role() {
    docker node inspect "$1" --format '{{.Spec.Role}}' 2>/dev/null || echo "unknown"
}

is_manager() {
    [[ "$(get_node_role "$1")" == "manager" ]]
}

is_worker() {
    [[ "$(get_node_role "$1")" == "worker" ]]
}

# Valida que a string é um IPv4 plausível (ex.: 10.0.0.4).
is_valid_ipv4() {
    [[ "${1:-}" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]
}

# Descobre o IP privado da própria instância (fallback robusto).
detect_private_ip() {
    local ip=""
    # 1) IP de origem da rota padrão (o mais correto)
    ip="$(ip route get 8.8.8.8 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="src"){print $(i+1); exit}}' || true)"
    # 2) primeiro IP global do host
    if [[ -z "$ip" ]]; then
        ip="$(hostname -I 2>/dev/null | awk '{print $1}' || true)"
    fi
    printf '%s' "$ip"
}

# Configura insecure registry no daemon.json do Docker
configure_insecure_registry() {
    local manager_ip="$1"

    # Nunca escrever um daemon.json inválido (ex.: [":5000"]): o dockerd não sobe
    # com 'insecure registry :5000 is not valid: invalid host ""' e o script aborta.
    if ! is_valid_ipv4 "$manager_ip"; then
        error "IP do manager inválido ('${manager_ip:-vazio}'); recusando escrever /etc/docker/daemon.json"
        exit 1
    fi

    log "Configurando insecure registry para $manager_ip:$REGISTRY_PORT..."
    
    mkdir -p /etc/docker
    cat > /etc/docker/daemon.json <<EOF
{
  "insecure-registries": ["$manager_ip:$REGISTRY_PORT", "localhost:$REGISTRY_PORT"],
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

    systemctl restart docker
    sleep 3
    success "Docker daemon configurado com insecure registry"
}

# =============================================================================
# SYNC DO GITHUB (se --sync-github)
# =============================================================================

sync_github() {
    if [[ "$SYNC_GITHUB" == true ]]; then
        log "Sincronizando repositórios do GitHub..."
        
        # Instala git se não tiver
        if ! command -v git &> /dev/null; then
            log "Instalando git..."
            apt-get update -qq && apt-get install -y -qq git
        fi
        
        # Cria diretório de sources
        mkdir -p "$SRC_DIR"
        
        # Função auxiliar para sync
        sync_repo() {
            local repo_url="$1"
            local dest_dir="$2"
            local name="$3"
            
            log "Sincronizando $name: $repo_url (branch: $GITHUB_BRANCH)"
            if [[ -d "$dest_dir/.git" ]]; then
                # Subshell: o `cd` fica confinado e o cwd do script é preservado.
                # Sem isso, o cwd vira o do último repo e os caminhos relativos
                # (ex.: assets da infra) passam a apontar para o lugar errado.
                (
                    cd "$dest_dir"
                    git fetch origin
                    git reset --hard "origin/$GITHUB_BRANCH"
                    git clean -fd
                )
            else
                git clone --branch "$GITHUB_BRANCH" "$repo_url" "$dest_dir"
            fi
            success "$name sincronizado em $dest_dir"
        }
        
        # Frontend
        sync_repo "$GITHUB_FRONTEND_REPO" "$FRONTEND_SRC_DIR" "Frontend"
        
        # Backend
        sync_repo "$GITHUB_BACKEND_REPO" "$BACKEND_SRC_DIR" "Backend"
        
        # Database
        sync_repo "$GITHUB_DATABASE_REPO" "$DATABASE_SRC_DIR" "Database"
        
        log "Todos os repositórios sincronizados em $SRC_DIR"
    fi
}

# =============================================================================
# INICIALIZAÇÃO DO SWARM
# =============================================================================

log "Verificando status do Swarm..."

SWARM_STATE="$(docker info --format '{{.Swarm.LocalNodeState}}' 2>/dev/null || true)"

if [[ "$SWARM_STATE" == "active" ]]; then
    success "Swarm já ativo neste nó"
    # Pega o IP do manager pelo próprio Swarm...
    MANAGER_IP="$(docker info --format '{{.Swarm.NodeAddr}}' 2>/dev/null || true)"
else
    MANAGER_IP=""
fi

# ...mas se o campo vier vazio/corrompido (isto já gerou um daemon.json inválido
# com [":5000"] e derrubou o Docker), cai para a detecção pela interface de rede.
if ! is_valid_ipv4 "$MANAGER_IP"; then
    warn "IP via Swarm indisponível ('${MANAGER_IP:-vazio}'); detectando pela interface..."
    MANAGER_IP="$(detect_private_ip)"
fi

if ! is_valid_ipv4 "$MANAGER_IP"; then
    error "Não foi possível determinar o IP privado do manager. Abortando."
    exit 1
fi

success "IP privado do manager: $MANAGER_IP"

if [[ "$SWARM_STATE" != "active" ]]; then
    log "Inicializando Swarm no manager leader (bastion-a)..."

    if docker swarm init --advertise-addr "$MANAGER_IP"; then
        success "Swarm inicializado com sucesso"
    else
        error "Falha ao inicializar Swarm"
        exit 1
    fi
fi

# =============================================================================
# NOMES DAS IMAGENS (usam o IP privado do manager)
# =============================================================================
# O registry roda apenas no manager. Se as imagens fossem tagueadas como
# "localhost:5000", os workers resolveriam "localhost" para si mesmos e
# falhariam ao puxar a imagem. Por isso usamos "$MANAGER_IP:5000", que já é
# configurado como insecure-registry nos workers pelo join-swarm.sh.
FRONTEND_IMAGE="${MANAGER_IP}:${REGISTRY_PORT}/megusta-frontend:latest"
BACKEND_IMAGE="${MANAGER_IP}:${REGISTRY_PORT}/megusta-backend:latest"
DATABASE_IMAGE="${MANAGER_IP}:${REGISTRY_PORT}/megusta-database:latest"
RABBITMQ_IMAGE="${MANAGER_IP}:${REGISTRY_PORT}/megusta-rabbitmq:latest"

# =============================================================================
# LOCAL REGISTRY - Sobe no manager leader ANTES do build/push
# =============================================================================

log "Configurando Local Registry em $MANAGER_IP:$REGISTRY_PORT..."

# Cria diretório de dados do registry
mkdir -p "$REGISTRY_DATA_DIR"

# Configura insecure registry LOCALMENTE (no manager)
configure_insecure_registry "$MANAGER_IP"

# Para registry anterior se existir
if docker ps -a --format '{{.Names}}' | grep -q "^${REGISTRY_NAME}$"; then
    log "Removendo registry anterior..."
    docker rm -f "$REGISTRY_NAME"
fi

# Sobe registry standalone (não como service, para estar disponível antes do stack)
log "Iniciando Local Registry..."
docker run -d \
    --name "$REGISTRY_NAME" \
    --restart=always \
    -p "$REGISTRY_PORT:5000" \
    -v "$REGISTRY_DATA_DIR:/var/lib/registry" \
    -e REGISTRY_HTTP_ADDR=0.0.0.0:5000 \
    registry:2

# Aguarda registry ficar saudável
log "Aguardando registry ficar pronto..."
for i in {1..30}; do
    if curl -sf "http://localhost:$REGISTRY_PORT/v2/" >/dev/null 2>&1; then
        success "Local Registry rodando em http://$MANAGER_IP:$REGISTRY_PORT"
        break
    fi
    sleep 1
done

# =============================================================================
# CONFIGURA INSECURE REGISTRY NOS OUTROS NODES (via join tokens)
# =============================================================================

# Pega tokens
MANAGER_TOKEN=$(docker swarm join-token -q manager)
WORKER_TOKEN=$(docker swarm join-token -q worker)

log "Tokens de join:"
log "  Manager: ${MANAGER_TOKEN:0:20}..."
log "  Worker:  ${WORKER_TOKEN:0:20}..."
log "  Manager IP (privado): $MANAGER_IP"
log "  Registry:  http://$MANAGER_IP:$REGISTRY_PORT"
echo ""
warn "IMPORTANTE: Em CADA worker (e manager secundário), execute ANTES do join:"
warn "  sudo mkdir -p /etc/docker"
warn "  sudo cat > /etc/docker/daemon.json <<EOF"
warn "  {"
warn "    \"insecure-registries\": [\"$MANAGER_IP:$REGISTRY_PORT\"]"
warn "  }"
warn "  EOF"
warn "  sudo systemctl restart docker"
warn "  # Depois faça o join com join-swarm.sh"
echo ""

# =============================================================================
# SYNC DO GITHUB (antes do build)
# =============================================================================

sync_github

# =============================================================================
# BUILD DAS IMAGENS + PUSH PARA REGISTRY LOCAL
# =============================================================================

# Determina diretórios de build
# IMPORTANTE: o codigo NAO esta na raiz dos repos:
#   - frontend: <repo>/me-gusta-frontend
#   - backend:  <repo>/megusta
#   - database: <repo> (raiz; recebe Dockerfile.database + config/ da infra)
if [[ "$SYNC_GITHUB" == true ]]; then
    FRONTEND_BUILD_DIR="$FRONTEND_SRC_DIR/me-gusta-frontend"
    BACKEND_BUILD_DIR="$BACKEND_SRC_DIR/megusta"
    DATABASE_BUILD_DIR="$DATABASE_SRC_DIR"
else
    FRONTEND_BUILD_DIR="../../me-gusta-frontend/me-gusta-frontend"
    BACKEND_BUILD_DIR="../../me-gusta-backend/megusta"
    DATABASE_BUILD_DIR="../../me-gusta-database"
fi

log "Diretórios de build:"
log "  Frontend: $FRONTEND_BUILD_DIR"
log "  Backend:  $BACKEND_BUILD_DIR"
log "  Database: $DATABASE_BUILD_DIR"

build_and_push() {
    local build_dir="$1"
    local dockerfile="$2"
    local image_name="$3"
    local build_args="${4:-}"
    
    log "Building $image_name..."
    
    if [[ -n "$dockerfile" && -f "$dockerfile" ]]; then
        docker build $build_args -t "$image_name" -f "$dockerfile" "$build_dir"
    elif [[ -n "$dockerfile" && -f "$build_dir/$dockerfile" ]]; then
        docker build $build_args -t "$image_name" -f "$build_dir/$dockerfile" "$build_dir"
    else
        docker build $build_args -t "$image_name" "$build_dir"
    fi
    
    success "$image_name built"
    
    log "Pushing $image_name to local registry..."
    docker push "$image_name"
    success "$image_name pushed to registry"
}

# Copia um asset da infra para o destino. Aborta se a origem não existir:
# antes, um `|| true` silenciava a falha e o build caía no Dockerfile próprio
# do repo (foi o que quebrou o build do frontend com "RUN npm ci").
copy_infra_asset() {
    local src="$1" dst="$2"
    if [[ ! -f "$src" ]]; then
        error "Asset da infra não encontrado: $src (confira se o config/ foi enviado por completo)"
        exit 1
    fi
    mkdir -p "$(dirname "$dst")"
    cp "$src" "$dst"
}

# Copia Dockerfiles/assets da infra para os diretórios de build (subpastas dos repos)
ensure_dockerfiles() {
    # Usa o SCRIPT_DIR resolvido no início (o cwd pode ter mudado após o sync).
    local infra_dir="$SCRIPT_DIR"
    # Copy Dockerfiles from infra to cloned repos
    copy_infra_asset "$infra_dir/docker/frontend.Dockerfile" "$FRONTEND_BUILD_DIR/Dockerfile"
    copy_infra_asset "$infra_dir/docker/nginx.conf" "$FRONTEND_BUILD_DIR/nginx.conf"
    copy_infra_asset "$infra_dir/docker/backend.Dockerfile" "$BACKEND_BUILD_DIR/Dockerfile"
    copy_infra_asset "$infra_dir/docker/Dockerfile.database" "$DATABASE_BUILD_DIR/Dockerfile"
    # Ensure assets exist in DB build context
    copy_infra_asset "$infra_dir/docker/config/mysql/custom.cnf" "$DATABASE_BUILD_DIR/config/docker/config/mysql/custom.cnf"
    copy_infra_asset "$infra_dir/docker/init-scripts/01-schema.sql" "$DATABASE_BUILD_DIR/config/docker/init-scripts/01-schema.sql"
    copy_infra_asset "$infra_dir/docker/init-scripts/02-seed-data.sql" "$DATABASE_BUILD_DIR/config/docker/init-scripts/02-seed-data.sql"
    copy_infra_asset "$infra_dir/docker/scripts/healthcheck.sh" "$DATABASE_BUILD_DIR/config/docker/scripts/healthcheck.sh"
}

ensure_dockerfiles

if [[ "$REBUILD" == true ]]; then
    log "Rebuild forçado das imagens..."
    
    build_and_push "$FRONTEND_BUILD_DIR" "$FRONTEND_BUILD_DIR/Dockerfile" "$FRONTEND_IMAGE" "--build-arg VITE_API_URL=/api"
    build_and_push "$BACKEND_BUILD_DIR" "$BACKEND_BUILD_DIR/Dockerfile" "$BACKEND_IMAGE"
    build_and_push "$DATABASE_BUILD_DIR" "$DATABASE_BUILD_DIR/Dockerfile" "$DATABASE_IMAGE"
    build_and_push "$SCRIPT_DIR/docker/rabbitmq" "$SCRIPT_DIR/docker/rabbitmq/Dockerfile" "$RABBITMQ_IMAGE"
    
    success "Todas as imagens rebuildadas e enviadas ao registry"
else
    # Verifica se as imagens existem no registry (tenta pull)
    for img in "$FRONTEND_IMAGE" "$BACKEND_IMAGE" "$DATABASE_IMAGE" "$RABBITMQ_IMAGE"; do
        if ! docker pull "$img" >/dev/null 2>&1; then
            warn "Imagem $img não encontrada no registry, fazendo build e push..."
            case $img in
                "$FRONTEND_IMAGE")
                    build_and_push "$FRONTEND_BUILD_DIR" "$FRONTEND_BUILD_DIR/Dockerfile" "$FRONTEND_IMAGE" "--build-arg VITE_API_URL=/api"
                    ;;
                "$BACKEND_IMAGE")
                    build_and_push "$BACKEND_BUILD_DIR" "$BACKEND_BUILD_DIR/Dockerfile" "$BACKEND_IMAGE"
                    ;;
                "$DATABASE_IMAGE")
                    build_and_push "$DATABASE_BUILD_DIR" "$DATABASE_BUILD_DIR/Dockerfile" "$DATABASE_IMAGE"
                    ;;
                "$RABBITMQ_IMAGE")
                    build_and_push "$SCRIPT_DIR/docker/rabbitmq" "$SCRIPT_DIR/docker/rabbitmq/Dockerfile" "$RABBITMQ_IMAGE"
                    ;;
            esac
        else
            success "Imagem $img já existe no registry"
        fi
    done
fi

# =============================================================================
# ATUALIZA COMPOSE FILE PARA USAR IMAGENS DO REGISTRY
# =============================================================================

log "Atualizando docker-compose.yml para usar imagens do registry..."

# Cria cópia temporária com imagens do registry
TEMP_COMPOSE="/tmp/docker-compose.registry.yml"
sed \
    -e "s|image: megusta-frontend:latest|image: $FRONTEND_IMAGE|" \
    -e "s|image: megusta-backend:latest|image: $BACKEND_IMAGE|" \
    -e "s|image: megusta-database:latest|image: $DATABASE_IMAGE|" \
    -e "s|image: megusta-rabbitmq:latest|image: $RABBITMQ_IMAGE|" \
    "$COMPOSE_FILE" > "$TEMP_COMPOSE"

# =============================================================================
# DEPLOY DO STACK
# =============================================================================

log "Fazendo deploy do stack '$STACK_NAME' usando imagens do registry..."

if docker stack deploy -c "$TEMP_COMPOSE" "$STACK_NAME"; then
    success "Stack deployado com sucesso!"
else
    error "Falha no deploy do stack"
    exit 1
fi

# =============================================================================
# AGUARDA SERVIÇOS FICAREM HEALTHY
# =============================================================================

log "Aguardando serviços ficarem healthy (timeout: 5min)..."

TIMEOUT=300
INTERVAL=10
ELAPSED=0

while [[ $ELAPSED -lt $TIMEOUT ]]; do
    # Conta serviços running vs desired
    RUNNING=$(docker stack services "$STACK_NAME" --format "{{.Replicas}}" | awk -F'/' '{sum+=$1} END {print sum}')
    DESIRED=$(docker stack services "$STACK_NAME" --format "{{.Replicas}}" | awk -F'/' '{sum+=$2} END {print sum}')
    
    if [[ -n "$RUNNING" && -n "$DESIRED" && "$RUNNING" -eq "$DESIRED" && "$DESIRED" -gt 0 ]]; then
        success "Todos os serviços estão running ($RUNNING/$DESIRED)"
        break
    fi
    
    log "Aguardando... ($RUNNING/$DESIRED replicas running)"
    sleep $INTERVAL
    ELAPSED=$((ELAPSED + INTERVAL))
done

if [[ $ELAPSED -ge $TIMEOUT ]]; then
    warn "Timeout aguardando serviços. Verifique com: docker stack services $STACK_NAME"
fi

# =============================================================================
# STATUS FINAL
# =============================================================================

echo ""
log "=========================================="
log "  DEPLOY CONCLUÍDO - MeGusta Stack"
log "=========================================="
echo ""

docker stack services "$STACK_NAME"

echo ""
log "Serviços disponíveis:"
log "  Frontend:  http://<ALB-DNS> (porta 80 via ALB)"
log "  Backend:   http://backend:8080 (interno)"
log "  Database:  mysql://database:3306 (interno)"
log "  RabbitMQ:  http://rabbitmq:15672 (admin/admin)"
log "  Registry:  http://$MANAGER_IP:$REGISTRY_PORT/v2/_catalog"

echo ""
log "Comandos úteis:"
log "  Ver logs:        docker service logs -f ${STACK_NAME}_<serviço>"
log "  Status:          docker stack services $STACK_NAME"
log "  Ps:              docker stack ps $STACK_NAME"
log "  Remover stack:   docker stack rm $STACK_NAME"
log "  Rebuild:         $0 --rebuild --sync-github"
log "  Ver registry:    curl http://$MANAGER_IP:$REGISTRY_PORT/v2/_catalog | jq"

echo ""
success "Deploy finalizado com sucesso!"