#!/usr/bin/env bash
# =============================================================================
# deploy.sh — Open Design Deploy Script
# =============================================================================
# Uso:
#   chmod +x deploy/deploy.sh
#   ./deploy/deploy.sh                    # sobe Open Design + Traefik
#   ./deploy/deploy.sh --standalone       # só Open Design (porta 7456)
#   ./deploy/deploy.sh --build            # força rebuild da imagem
#   ./deploy/deploy.sh --help             # ajuda
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
DOMAIN="${OPEN_DESIGN_DOMAIN:-jarvispro.design.online}"

# Cores
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'

info()  { echo -e "${GREEN}[INFO]${NC} $1"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

# ── Help ──────────────────────────────────────────────────────────────
show_help() {
  cat <<EOF
Open Design Deploy Script

Uso: ./deploy/deploy.sh [opções]

Opções:
  --standalone   Apenas Open Design (porta 7456, sem Traefik)
  --build        Força rebuild da imagem Docker
  --help         Mostra esta ajuda

Variáveis de ambiente:
  OPEN_DESIGN_DOMAIN     Domínio (padrão: jarvispro.design.online)
  OPEN_DESIGN_PORT       Porta (padrão: 7456)
  OPEN_DESIGN_MEM_LIMIT  Limite de memória (padrão: 384m)
EOF
  exit 0
}

# ── Args ───────────────────────────────────────────────────────────────
STANDALONE=false
REBUILD=false

for arg in "$@"; do
  case "$arg" in
    --standalone) STANDALONE=true ;;
    --build)      REBUILD=true ;;
    --help)       show_help ;;
    *)            error "Argumento desconhecido: $arg. Use --help." ;;
  esac
done

# ── Pré-requisitos ─────────────────────────────────────────────────────
info "Verificando pré-requisitos..."

command -v docker &>/dev/null || error "Docker não encontrado. Instale: https://docs.docker.com/engine/install/"
docker compose version &>/dev/null || error "Docker Compose não encontrado."

# ── .env ───────────────────────────────────────────────────────────────
if [ ! -f "$PROJECT_ROOT/.env" ]; then
  if [ -f "$SCRIPT_DIR/.env.example" ]; then
    cp "$SCRIPT_DIR/.env.example" "$PROJECT_ROOT/.env"
    info "Arquivo .env criado a partir de .env.example. Edite se necessário."
  else
    warn "Nenhum .env ou .env.example encontrado. Usando valores padrão."
  fi
fi

# ── Rede Docker ────────────────────────────────────────────────────────
if [ "$STANDALONE" = false ]; then
  if ! docker network inspect open-design-net &>/dev/null; then
    docker network create open-design-net
    info "Rede 'open-design-net' criada."
  else
    info "Rede 'open-design-net' já existe."
  fi
fi

# ── Build ──────────────────────────────────────────────────────────────
if [ "$REBUILD" = true ]; then
  info "Fazendo rebuild da imagem..."
  docker compose -f "$SCRIPT_DIR/docker-compose.yml" build --no-cache
else
  # Verifica se a imagem já existe
  IMAGE="${OPEN_DESIGN_IMAGE:-docker.io/vanjayak/open-design:latest}"
  if ! docker image inspect "$IMAGE" &>/dev/null 2>&1; then
    info "Imagem não encontrada. Fazendo build..."
    docker compose -f "$SCRIPT_DIR/docker-compose.yml" build
  fi
fi

# ── Deploy ─────────────────────────────────────────────────────────────
cd "$PROJECT_ROOT"

if [ "$STANDALONE" = true ]; then
  info "Subindo Open Design (standalone) em http://0.0.0.0:${OPEN_DESIGN_PORT:-7456}"
  docker compose -f "$SCRIPT_DIR/docker-compose.yml" up -d
else
  # Verifica se Traefik já está rodando
  if ! docker ps --format '{{.Names}}' | grep -q 'open-design-traefik'; then
    info "Subindo Traefik primeiro..."
    docker compose -f "$SCRIPT_DIR/docker-compose.traefik.yml" up -d
  else
    info "Traefik já está rodando."
  fi

  info "Subindo Open Design em https://$DOMAIN"
  docker compose -f "$SCRIPT_DIR/docker-compose.yml" up -d
fi

# ── Status ─────────────────────────────────────────────────────────────
echo ""
info "=== Status ==="
docker compose -f "$SCRIPT_DIR/docker-compose.yml" ps

echo ""
if [ "$STANDALONE" = true ]; then
  info "Acesse: http://SEU_IP_VPS:${OPEN_DESIGN_PORT:-7456}"
else
  info "Acesse: https://$DOMAIN"
  info "Traefik Dashboard: https://traefik.$DOMAIN"
fi
