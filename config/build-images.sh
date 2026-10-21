#!/bin/bash
# =============================================================================
# MeGusta - Build Images from GitHub (for CI/CD)
# =============================================================================
# Este script apenas clona do GitHub e faz build das imagens.
# Útil para CI/CD (GitHub Actions, GitLab CI, Jenkins, etc.)
#
# Uso: ./build-images.sh [--push] [--registry REGISTRY] [--tag TAG]
# =============================================================================

set -euo pipefail

# Configurações (podem vir de env vars)
GITHUB_FRONTEND_REPO="${GITHUB_FRONTEND_REPO:-https://github.com/Miralhaz/me-gusta-frontend.git}"
GITHUB_BACKEND_REPO="${GITHUB_BACKEND_REPO:-https://github.com/Miralhaz/me-gusta-backend.git}"
GITHUB_DATABASE_REPO="${GITHUB_DATABASE_REPO:-https://github.com/Miralhaz/me-gusta-database.git}"
GITHUB_BRANCH="${GITHUB_BRANCH:-main}"
PUSH_TO_REGISTRY="${PUSH_TO_REGISTRY:-false}"
REGISTRY="${REGISTRY:-}"
IMAGE_TAG="${IMAGE_TAG:-latest}"

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

# Parse args
while [[ $# -gt 0 ]]; do
    case $1 in
        --push)
            PUSH_TO_REGISTRY=true
            shift
            ;;
        --registry)
            REGISTRY="$2"
            shift 2
            ;;
        --tag)
            IMAGE_TAG="$2"
            shift 2
            ;;
        --help)
            echo "Uso: $0 [--push] [--registry REGISTRY] [--tag TAG]"
            exit 0
            ;;
        *)
            error "Opção desconhecida: $1"
            exit 1
            ;;
    esac
done

# Diretórios
SRC_DIR="/opt/megusta/src"
FRONTEND_SRC_DIR="$SRC_DIR/me-gusta-frontend"
BACKEND_SRC_DIR="$SRC_DIR/me-gusta-backend"
DATABASE_SRC_DIR="$SRC_DIR/me-gusta-database"

# Diretórios de build (o código fica em subpastas dos repos clonados)
#   - frontend: <repo>/me-gusta-frontend
#   - backend:  <repo>/megusta
#   - database: <repo> (raiz; recebe o Dockerfile + config/ da infra)
FRONTEND_BUILD_DIR="$FRONTEND_SRC_DIR/me-gusta-frontend"
BACKEND_BUILD_DIR="$BACKEND_SRC_DIR/megusta"
DATABASE_BUILD_DIR="$DATABASE_SRC_DIR"

# Salva diretório original
ORIGINAL_DIR=$(pwd)
# Diretório deste script (repo de infraestrutura)
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Função para determinar nome da imagem
get_image_name() {
    local base_name="$1"
    if [[ -n "$REGISTRY" ]]; then
        echo "$REGISTRY/$base_name:$IMAGE_TAG"
    else
        echo "$base_name:$IMAGE_TAG"
    fi
}

FRONTEND_IMAGE=$(get_image_name "megusta-frontend")
BACKEND_IMAGE=$(get_image_name "megusta-backend")
DATABASE_IMAGE=$(get_image_name "megusta-database")
RABBITMQ_IMAGE=$(get_image_name "megusta-rabbitmq")

log "=== MeGusta Build Images ==="
log "Frontend: $FRONTEND_IMAGE"
log "Backend:  $BACKEND_IMAGE"
log "Database: $DATABASE_IMAGE"
log "RabbitMQ: $RABBITMQ_IMAGE"
log "Branch:   $GITHUB_BRANCH"
log "Push:     $PUSH_TO_REGISTRY"
[[ -n "$REGISTRY" ]] && log "Registry: $REGISTRY"

# Instala git se necessário
if ! command -v git &> /dev/null; then
    log "Instalando git..."
    apt-get update -qq && apt-get install -y -qq git
fi

# =============================================================================
# SYNC GITHUB
# =============================================================================

mkdir -p "$SRC_DIR"

sync_repo() {
    local repo_url="$1"
    local dest_dir="$2"
    local name="$3"
    
    log "Sincronizando $name..."
    if [[ -d "$dest_dir/.git" ]]; then
        cd "$dest_dir"
        git fetch origin
        git reset --hard "origin/$GITHUB_BRANCH"
        git clean -fd
    else
        git clone --branch "$GITHUB_BRANCH" "$repo_url" "$dest_dir"
    fi
    success "$name sincronizado em $dest_dir"
}

sync_repo "$GITHUB_FRONTEND_REPO" "$FRONTEND_SRC_DIR" "Frontend"
sync_repo "$GITHUB_BACKEND_REPO" "$BACKEND_SRC_DIR" "Backend"
sync_repo "$GITHUB_DATABASE_REPO" "$DATABASE_SRC_DIR" "Database"

# Volta ao diretório original
cd "$ORIGINAL_DIR"

# =============================================================================
# BUILD IMAGES
# =============================================================================

build_image() {
    local context_dir="$1"
    local dockerfile="$2"
    local image_name="$3"
    local build_args="${4:-}"
    
    log "Building $image_name..."
    
    if [[ -n "$dockerfile" && -f "$dockerfile" ]]; then
        docker build $build_args -t "$image_name" -f "$dockerfile" "$context_dir"
    elif [[ -n "$dockerfile" && -f "$context_dir/$dockerfile" ]]; then
        docker build $build_args -t "$image_name" -f "$context_dir/$dockerfile" "$context_dir"
    else
        docker build $build_args -t "$image_name" "$context_dir"
    fi
    
    success "$image_name built"
}

ensure_dockerfiles() {
    local infra_dir="$(cd "$(dirname "$0")" && pwd)"
    # Copy Dockerfiles + assets from infra to the actual build dirs (subpastas)
    cp "$infra_dir/docker/frontend.Dockerfile" "$FRONTEND_BUILD_DIR/Dockerfile" 2>/dev/null || cp "$infra_dir/frontend.Dockerfile" "$FRONTEND_BUILD_DIR/Dockerfile" 2>/dev/null || true
    cp "$infra_dir/docker/nginx.conf" "$FRONTEND_BUILD_DIR/nginx.conf" 2>/dev/null || true
    cp "$infra_dir/docker/backend.Dockerfile" "$BACKEND_BUILD_DIR/Dockerfile" 2>/dev/null || cp "$infra_dir/backend.Dockerfile" "$BACKEND_BUILD_DIR/Dockerfile" 2>/dev/null || true
    cp "$infra_dir/docker/Dockerfile.database" "$DATABASE_BUILD_DIR/Dockerfile" 2>/dev/null || true
    mkdir -p "$DATABASE_BUILD_DIR/config/docker/config/mysql" "$DATABASE_BUILD_DIR/config/docker/init-scripts" "$DATABASE_BUILD_DIR/config/docker/scripts" 2>/dev/null || true
    cp "$infra_dir/docker/config/mysql/custom.cnf" "$DATABASE_BUILD_DIR/config/docker/config/mysql/custom.cnf" 2>/dev/null || true
    cp "$infra_dir/docker/init-scripts/01-schema.sql" "$DATABASE_BUILD_DIR/config/docker/init-scripts/01-schema.sql" 2>/dev/null || true
    cp "$infra_dir/docker/init-scripts/02-seed-data.sql" "$DATABASE_BUILD_DIR/config/docker/init-scripts/02-seed-data.sql" 2>/dev/null || true
    cp "$infra_dir/docker/scripts/healthcheck.sh" "$DATABASE_BUILD_DIR/config/docker/scripts/healthcheck.sh" 2>/dev/null || true
}

ensure_dockerfiles

# Frontend (multi-stage: Node build -> Nginx) - contexto: <repo>/me-gusta-frontend
log "Building Frontend..."
build_image "$FRONTEND_BUILD_DIR" "$FRONTEND_BUILD_DIR/Dockerfile" "$FRONTEND_IMAGE" "--build-arg VITE_API_URL=/api"

# Backend (Maven -> JRE) - contexto: <repo>/megusta
log "Building Backend..."
build_image "$BACKEND_BUILD_DIR" "$BACKEND_BUILD_DIR/Dockerfile" "$BACKEND_IMAGE"

# Database (MySQL custom) - contexto: <repo> (raiz)
log "Building Database..."
build_image "$DATABASE_BUILD_DIR" "$DATABASE_BUILD_DIR/Dockerfile" "$DATABASE_IMAGE"

# RabbitMQ (config embutida) - contexto: config/docker/rabbitmq
log "Building RabbitMQ..."
build_image "$SCRIPT_DIR/docker/rabbitmq" "$SCRIPT_DIR/docker/rabbitmq/Dockerfile" "$RABBITMQ_IMAGE"

# =============================================================================
# PUSH TO REGISTRY (se solicitado)
# =============================================================================

if [[ "$PUSH_TO_REGISTRY" == true ]]; then
    if [[ -z "$REGISTRY" ]]; then
        error "--push requer --registry"
        exit 1
    fi
    
    log "Fazendo login no registry..."
    # Assume que docker login já foi feito (ex: aws ecr get-login-password)
    
    for img in "$FRONTEND_IMAGE" "$BACKEND_IMAGE" "$DATABASE_IMAGE" "$RABBITMQ_IMAGE"; do
        log "Pushing $img..."
        docker push "$img"
        success "$img pushed"
    done
fi

success "Build concluído com sucesso!"
echo ""
echo "Imagens criadas:"
echo "  $FRONTEND_IMAGE"
echo "  $BACKEND_IMAGE"
echo "  $DATABASE_IMAGE"
echo "  $RABBITMQ_IMAGE"

if [[ "$PUSH_TO_REGISTRY" == true ]]; then
    echo ""
    echo "Para deploy no Swarm, atualize o docker-compose.yml com as novas tags:"
    echo "  image: $FRONTEND_IMAGE"
    echo "  image: $BACKEND_IMAGE"
    echo "  image: $DATABASE_IMAGE"
    echo "  image: $RABBITMQ_IMAGE"
fi