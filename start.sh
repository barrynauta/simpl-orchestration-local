#!/usr/bin/env bash
# =============================================================================
# Simpl Orchestration Platform — Local Evaluation Launcher
#
# Usage:
#   ./start.sh                    # Clone repos and start the stack
#   ./start.sh --run-tests        # Clone repos, start stack, run Bruno smoke tests
#   ./start.sh --help             # Show this help
#
# Requirements:
#   - Docker Desktop or OrbStack running
#   - git
# =============================================================================
set -euo pipefail

# --- Resolve script location --------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# --- Colours ------------------------------------------------------------------
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
info()    { echo -e "${BLUE}[INFO]${NC}  $*"; }
success() { echo -e "${GREEN}[OK]${NC}    $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error()   { echo -e "${RED}[ERROR]${NC} $*"; exit 1; }

# --- Config -------------------------------------------------------------------
GITLAB_HOST="code.europa.eu"
REPO_BASE="simpl/simpl-open/development/orchestration-platform"
REPOS=(
  "asset-orchestrator"
  "dagster-dev-local"
)
PIPELINE_BASE="simpl/simpl-open/development/data-services"
PIPELINE_REPOS=(
  "dataframe-level-anonymisation"
  "field-level-pseudo-anonymisation"
)
REPOS_DIR="$SCRIPT_DIR/repos"
RUN_TESTS=false

# --- Argument parsing ---------------------------------------------------------
for arg in "$@"; do
  case $arg in
    --run-tests) RUN_TESTS=true ;;
    --help|-h)
      grep '^#' "$0" | grep -v '#!/' | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *) warn "Unknown argument: $arg" ;;
  esac
done

# --- Banner -------------------------------------------------------------------
echo ""
echo -e "${BLUE}╔══════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║   Simpl Orchestration Platform — Local Launcher      ║${NC}"
echo -e "${BLUE}╚══════════════════════════════════════════════════════╝${NC}"
echo ""

# --- Ensure .env.local exists -------------------------------------------------
if [[ ! -f "$SCRIPT_DIR/.env.local" ]]; then
  if [[ -f "$SCRIPT_DIR/.env.local.example" ]]; then
    info ".env.local not found — generating from .env.local.example ..."
    cp "$SCRIPT_DIR/.env.local.example" "$SCRIPT_DIR/.env.local"
    success ".env.local created."
  else
    error ".env.local and .env.local.example both missing. Cannot start."
  fi
fi

# --- Check prerequisites ------------------------------------------------------
info "Checking prerequisites..."
command -v docker >/dev/null 2>&1 || error "Docker is not installed or not on PATH."
command -v git    >/dev/null 2>&1 || error "git is not installed or not on PATH."
docker info >/dev/null 2>&1 || error "Docker daemon is not running. Start Docker Desktop or OrbStack first."
success "Docker and git found."

# --- Clone orchestration repositories -----------------------------------------
echo ""
info "Cloning orchestration repositories into $REPOS_DIR ..."
mkdir -p "$REPOS_DIR"

for repo in "${REPOS[@]}"; do
  target="$REPOS_DIR/$repo"
  url="https://${GITLAB_HOST}/${REPO_BASE}/${repo}.git"
  if [[ -d "$target/.git" ]]; then
    info "  $repo — already cloned, pulling latest..."
    git -C "$target" pull --quiet || warn "  Could not pull $repo — continuing with existing version."
  else
    info "  Cloning $repo ..."
    git clone --quiet "$url" "$target" || error "Failed to clone $repo. Check your network connection."
    success "  $repo cloned."
  fi
done

# --- Clone data-services pipeline repos ---------------------------------------
info "Cloning data-services pipeline repositories..."
mkdir -p "$REPOS_DIR/data-services"

for repo in "${PIPELINE_REPOS[@]}"; do
  target="$REPOS_DIR/data-services/$repo"
  url="https://${GITLAB_HOST}/${PIPELINE_BASE}/${repo}.git"
  if [[ -d "$target/.git" ]]; then
    info "  $repo — already cloned, pulling latest..."
    git -C "$target" pull --quiet || warn "  Could not pull $repo — continuing with existing version."
  else
    info "  Cloning $repo ..."
    git clone --quiet "$url" "$target" || error "Failed to clone $repo. Check your network connection."
    success "  $repo cloned."
  fi
done

success "All repositories ready."

# --- Validate Dockerfiles -----------------------------------------------------
[[ -f "$REPOS_DIR/asset-orchestrator/Dockerfile" ]] \
  || error "Dockerfile not found in repos/asset-orchestrator."
for repo in "${PIPELINE_REPOS[@]}"; do
  [[ -f "$REPOS_DIR/data-services/$repo/Dockerfile" ]] \
    || error "Dockerfile not found in repos/data-services/$repo."
done

# --- Launch the stack ---------------------------------------------------------
echo ""
info "Changing to $SCRIPT_DIR ..."
cd "$SCRIPT_DIR"

export DOCKER_BUILDKIT=1
export COMPOSE_DOCKER_CLI_BUILD=1

info "Building and starting the full stack (detached)..."
echo ""
if [[ "$RUN_TESTS" == true ]]; then
  docker compose --profile tests up --build -d
else
  docker compose up --build -d
fi

# --- Wait for Dagster webserver to be healthy ---------------------------------
echo ""
info "Waiting for Dagster webserver to become healthy..."
MAX_WAIT=120
WAITED=0
until docker inspect simpl-dagster-webserver --format '{{.State.Health.Status}}' 2>/dev/null | grep -q "healthy"; do
  if [[ $WAITED -ge $MAX_WAIT ]]; then
    warn "Dagster webserver did not become healthy within ${MAX_WAIT}s — continuing anyway."
    break
  fi
  sleep 5
  WAITED=$((WAITED + 5))
  info "  Still waiting... (${WAITED}s)"
done
success "Dagster webserver is healthy."

# --- Restart webserver to ensure volume-mounted workspace.yaml is active -----
info "Reloading Dagster webserver with updated workspace..."
docker compose restart docker_dagster_webserver
sleep 5
success "Dagster webserver reloaded."

# --- Verify workspace loaded correctly ----------------------------------------
WORKSPACE_CHECK=$(docker exec simpl-dagster-webserver cat /opt/dagster/dagster_home/workspace.yaml 2>/dev/null)
if echo "$WORKSPACE_CHECK" | grep -q "dagster-anonymisation"; then
  success "Workspace verified — code locations registered."
else
  warn "Workspace may not have loaded correctly. Check http://localhost:3001/deployment"
fi

# --- Done ---------------------------------------------------------------------
echo ""
echo -e "${GREEN}╔══════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║   Stack is up! Service URLs:                         ║${NC}"
echo -e "${GREEN}║                                                      ║${NC}"
echo -e "${GREEN}║   Asset Orchestrator  http://localhost:8080/v1/      ║${NC}"
echo -e "${GREEN}║   Swagger UI          http://localhost:8080/v1/      ║${NC}"
echo -e "${GREEN}║                         swagger-ui.html              ║${NC}"
echo -e "${GREEN}║   Dagster UI          http://localhost:3001          ║${NC}"
echo -e "${GREEN}║   Kafka UI            http://localhost:9081          ║${NC}"
echo -e "${GREEN}║   Mailpit             http://localhost:8027          ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════════════════╝${NC}"
echo ""

if [[ "$RUN_TESTS" == true ]]; then
  echo ""
  info "Waiting for Bruno smoke tests to complete..."
  echo ""

  docker compose logs -f bruno-smoke-test &
  TAIL_PID=$!

  WAITED=0
  MAX_WAIT=180
  until [[ "$(docker inspect simpl-bruno-tests --format '{{.State.Status}}' 2>/dev/null)" == "exited" ]]; do
    if [[ $WAITED -ge $MAX_WAIT ]]; then
      warn "Bruno tests did not complete within ${MAX_WAIT}s."
      break
    fi
    sleep 3
    WAITED=$((WAITED + 3))
  done

  kill $TAIL_PID 2>/dev/null || true
  wait $TAIL_PID 2>/dev/null || true

  BRUNO_EXIT=$(docker inspect simpl-bruno-tests --format '{{.State.ExitCode}}' 2>/dev/null || echo "1")

  echo ""
  if [[ "$BRUNO_EXIT" == "0" ]]; then
    echo -e "${GREEN}╔══════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║   ✅  All smoke tests passed.                         ║${NC}"
    echo -e "${GREEN}╚══════════════════════════════════════════════════════╝${NC}"
  else
    echo -e "${RED}╔══════════════════════════════════════════════════════╗${NC}"
    echo -e "${RED}║   ❌  One or more smoke tests failed.                 ║${NC}"
    echo -e "${RED}╚══════════════════════════════════════════════════════╝${NC}"
  fi
  echo ""
  info "Stack remains running. To stop: docker compose down"
else
  info "To follow all logs: docker compose logs -f"
  info "To stop:            docker compose down"
  info "To stop + wipe:     docker compose down -v"
fi
