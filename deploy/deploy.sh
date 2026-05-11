#!/usr/bin/env bash
# =============================================================================
# deploy.sh — Open Design Deploy Script
# =============================================================================
# Uso:
#   chmod +x deploy/deploy.sh
#   ./deploy/deploy.sh              # sobe Open Design
#   ./deploy/deploy.sh --build      # força rebuild da imagem
#   ./deploy/deploy.sh --help       # ajuda
# =============================================================================
# Requer um Traefik já rodando na rede 'opencode-net' (ou a que estiver em
# TRAEFIK_NETWORK). O Traefik fará SSL automático via Let's Encrypt.
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

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
  --build        Força rebuild da imagem Docker
  --help         Mostra esta ajuda

Variáveis de ambiente:
  OPEN_DESIGN_DOMAIN      Domínio (padrão: design.jarvispro.online)
  OPEN_DESIGN_PORT        Porta local (padrão: 7456)
  OPEN_DESIGN_MEM_LIMIT   Limite de memória (padrão: 384m)
  TRAEFIK_NETWORK         Rede do Traefik (padrão: opencode-net)
EOF
  exit 0
}

# ── Args ───────────────────────────────────────────────────────────────
REBUILD=false
for arg in "$@"; do
  case "$arg" in
    --build) REBUILD=true ;;
    --help)  show_help ;;
    *)       error "Argumento desconhecido: $arg. Use --help." ;;
  esac
done

# ── Pré-requisitos ─────────────────────────────────────────────────────
info "Verificando pré-requisitos..."
command -v docker &>/dev/null || error "Docker não encontrado."
docker compose version &>/dev/null || error "Docker Compose não encontrado."

# ── .env ───────────────────────────────────────────────────────────────
if [ ! -f "$PROJECT_ROOT/.env" ]; then
  if [ -f "$SCRIPT_DIR/.env.example" ]; then
    cp "$SCRIPT_DIR/.env.example" "$PROJECT_ROOT/.env"
    info "Arquivo .env criado a partir de .env.example. Edite se necessário."
  fi
fi

# ── Build ──────────────────────────────────────────────────────────────
if [ "$REBUILD" = true ]; then
  info "Fazendo rebuild da imagem..."
  docker compose -f "$SCRIPT_DIR/docker-compose.yml" build --no-cache
else
  IMAGE="${OPEN_DESIGN_IMAGE:-docker.io/vanjayak/open-design:latest}"
  if ! docker image inspect "$IMAGE" &>/dev/null 2>&1; then
    info "Imagem não encontrada. Fazendo build..."
    docker compose -f "$SCRIPT_DIR/docker-compose.yml" build
  fi
fi

# ── Deploy ─────────────────────────────────────────────────────────────
cd "$PROJECT_ROOT"
info "Subindo Open Design..."
docker compose -f "$SCRIPT_DIR/docker-compose.yml" up -d

# ── Status ─────────────────────────────────────────────────────────────
echo ""
info "=== Status ==="
docker compose -f "$SCRIPT_DIR/docker-compose.yml" ps

NET=$(grep -oP '^TRAEFIK_NETWORK=\K.*' "$PROJECT_ROOT/.env" 2>/dev/null || echo "opencode-net")
echo ""
info "Acesse: https://design.jarvispro.online"
info "Rede Traefik: $NET"
