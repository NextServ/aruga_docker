#!/bin/bash
# =============================================================================
# ARUGA SANDBOX — Install Script
# =============================================================================
# PURPOSE : Sets up the sandbox/staging environment
# TRAEFIK : This script starts the MASTER Traefik instance.
#           Run this BEFORE install-aruga-production.sh
#
# HOW TO USE:
#   1. Update the variables below marked [CHANGE THIS]
#   2. Make sure compose.sandbox.yaml is configured with your domain
#   3. chmod +x scripts/install-aruga-sandbox.sh
#   4. cd ~/aruga_docker && ./scripts/install-aruga-sandbox.sh
#
# TO RE-RUN (e.g. after server reboot):
#   Just run cd ~/aruga_docker && ./scripts/install-aruga-sandbox.sh again — it detects existing sites
#   and runs migrate + clear-cache instead of reinstalling from scratch.
# =============================================================================

set -e

# -----------------------------------------------------------------------------
# [CHANGE THIS] Configuration — update these for each new deployment
# -----------------------------------------------------------------------------

# Your sandbox domain (must match FRAPPE_SITE_NAME_HEADER in compose.sandbox.yaml)
SITE_NAME="playlab-sandbox.serviotech.com"

# Admin password for the ARUGA web interface
ADMIN_PASSWORD="servio_aruga"

# MariaDB root password (must match MYSQL_ROOT_PASSWORD in compose.sandbox.yaml)
DB_ROOT_PASSWORD="frappe"

# Path to the install directory (where you cloned aruga_docker)
INSTALL_DIR="$HOME/aruga_docker"

# Path to the sandbox compose file
COMPOSE_FILE="$INSTALL_DIR/compose/compose.sandbox.yaml"
# NOTE: Script lives in scripts/ folder — paths are relative to INSTALL_DIR

# Git repo and branch
REPO_URL="https://github.com/NextServ/aruga_docker.git"
REPO_BRANCH="aruga_server_deployment"

# -----------------------------------------------------------------------------
# Color output helpers
# -----------------------------------------------------------------------------
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_ok()    { echo -e "${GREEN}  ✔ $1${NC}"; }
print_error() { echo -e "${RED}  ✘ ERROR: $1${NC}"; exit 1; }
print_warn()  { echo -e "${YELLOW}  ⚠ $1${NC}"; }
print_step()  { echo -e "\n${BLUE}▶ $1${NC}"; }
print_info()  { echo -e "  $1"; }

echo ""
echo -e "${GREEN}========================================"
echo " ARUGA Sandbox Installer"
echo " Version  : v0.0.8"
echo " Site     : $SITE_NAME"
echo " Compose  : $COMPOSE_FILE"
echo -e "========================================${NC}"
echo ""

# -----------------------------------------------------------------------------
# [1/6] Check Docker
# -----------------------------------------------------------------------------
print_step "[1/6] Checking Docker..."
command -v docker &>/dev/null          || print_error "Docker not installed. Run: curl -fsSL https://get.docker.com | sh"
docker info &>/dev/null                || print_error "Docker daemon not running. Run: systemctl start docker"
docker compose version &>/dev/null     || print_error "Docker Compose plugin missing. Run: apt install docker-compose-plugin -y"
print_ok "Docker $(docker --version)"
print_ok "$(docker compose version)"

# -----------------------------------------------------------------------------
# [2/6] Check Git
# -----------------------------------------------------------------------------
print_step "[2/6] Checking Git..."
command -v git &>/dev/null || print_error "Git not installed. Run: apt install git -y"
print_ok "$(git --version)"

# -----------------------------------------------------------------------------
# [3/6] Prepare files
# -----------------------------------------------------------------------------
print_step "[3/6] Preparing ARUGA files..."
if [ -d "$INSTALL_DIR" ]; then
    print_info "Existing installation found. Updating..."
    cd "$INSTALL_DIR"
    git reset --hard >/dev/null 2>&1 || true
    if ! git pull; then
        print_warn "Git pull failed. Reinstalling from scratch..."
        cd "$HOME"
        rm -rf "$INSTALL_DIR"
        git clone "$REPO_URL" -b "$REPO_BRANCH" "$INSTALL_DIR"
    fi
else
    print_info "Cloning ARUGA repository..."
    git clone "$REPO_URL" -b "$REPO_BRANCH" "$INSTALL_DIR"
fi

# Verify compose file exists
[ -f "$COMPOSE_FILE" ] || print_error "Compose file not found: $COMPOSE_FILE"

cd "$INSTALL_DIR"
print_ok "Files ready at $INSTALL_DIR"

# -----------------------------------------------------------------------------
# [4/6] Start containers
# -----------------------------------------------------------------------------
print_step "[4/6] Starting sandbox services..."
docker compose -f "$COMPOSE_FILE" up -d
print_ok "Sandbox services started"

# -----------------------------------------------------------------------------
# [5/6] Wait for database
# -----------------------------------------------------------------------------
print_step "[5/6] Waiting for database to be ready..."
MAX_TRIES=30
TRIES=0
until docker compose -f "$COMPOSE_FILE" exec db mysqladmin ping -uroot -p"$DB_ROOT_PASSWORD" --silent >/dev/null 2>&1; do
    TRIES=$((TRIES + 1))
    [ "$TRIES" -ge "$MAX_TRIES" ] && print_error "Database timed out. Check logs: docker compose -f $COMPOSE_FILE logs db"
    print_info "Waiting for DB... ($TRIES/$MAX_TRIES)"
    sleep 5
done
print_ok "Database is ready"

print_info "Waiting for configurator to complete setup..."
sleep 20

# -----------------------------------------------------------------------------
# [6/6] Create or update site
# -----------------------------------------------------------------------------
print_step "[6/6] Checking if sandbox site exists..."

if ! docker compose -f "$COMPOSE_FILE" exec -T backend bench --site "$SITE_NAME" list-apps >/dev/null 2>&1; then

    print_warn "Site not found. Creating new sandbox site..."
    print_info "This will take 10–20 minutes. Do NOT press Ctrl+C..."
    echo ""

    print_info "--- Step 1: Creating site..."
    docker compose -f "$COMPOSE_FILE" exec -T backend bench new-site "$SITE_NAME" \
      --mariadb-root-password "$DB_ROOT_PASSWORD" \
      --admin-password "$ADMIN_PASSWORD" \
      --mariadb-user-host-login-scope='%' \
      --install-app frappe

    print_info "--- Step 2: Installing ERPNext..."
    docker compose -f "$COMPOSE_FILE" exec -T backend bench --site "$SITE_NAME" install-app erpnext

    print_info "--- Step 3: Installing HRMS..."
    docker compose -f "$COMPOSE_FILE" exec -T backend bench --site "$SITE_NAME" install-app hrms

    print_info "--- Step 4: Installing ARUGA Accounting..."
    docker compose -f "$COMPOSE_FILE" exec -T backend bench --site "$SITE_NAME" install-app aruga_acct

    print_info "--- Step 5: Installing ARUGA Payroll..."
    docker compose -f "$COMPOSE_FILE" exec -T backend bench --site "$SITE_NAME" install-app aruga_pay

    print_info "--- Step 6: Installing ARUGA Main..."
    docker compose -f "$COMPOSE_FILE" exec -T backend bench --site "$SITE_NAME" install-app aruga_main

    print_info "--- Step 7: Running migrations..."
    docker compose -f "$COMPOSE_FILE" exec -T backend bench --site "$SITE_NAME" migrate

    print_info "--- Step 8: Running ARUGA Payroll setup..."
    sleep 8
    docker compose -f "$COMPOSE_FILE" exec -T backend bench --site "$SITE_NAME" execute aruga_pay.install.after_install

    print_info "--- Step 9: Clearing cache..."
    sleep 5
    docker compose -f "$COMPOSE_FILE" exec -T backend bench --site "$SITE_NAME" clear-cache

else
    print_warn "Existing site detected. Running update..."
    docker compose -f "$COMPOSE_FILE" exec -T backend bench --site "$SITE_NAME" migrate
    docker compose -f "$COMPOSE_FILE" exec -T backend bench --site "$SITE_NAME" execute aruga_pay.install.after_install
    docker compose -f "$COMPOSE_FILE" exec -T backend bench --site "$SITE_NAME" clear-cache
    print_ok "Site updated"
fi

# -----------------------------------------------------------------------------
# Done
# -----------------------------------------------------------------------------
echo ""
echo -e "${GREEN}========================================"
echo " SANDBOX INSTALL COMPLETE"
echo "========================================"
echo ""
echo "  URL      : https://$SITE_NAME"
echo "  Username : Administrator"
echo "  Password : $ADMIN_PASSWORD"
echo ""
echo "  ⚠  Change the admin password after first login!"
echo "  ⚠  SSL certificate may take 1–2 mins on first access."
echo ""
echo "  Useful commands:"
echo "  docker compose -f $COMPOSE_FILE ps"
echo "  docker compose -f $COMPOSE_FILE logs -f"
echo -e "========================================${NC}"
echo ""
