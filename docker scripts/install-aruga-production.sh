#!/bin/bash
# =============================================================================
# ARUGA PRODUCTION — Install Script
# =============================================================================
# PURPOSE : Sets up the production environment on the same server as sandbox
# TRAEFIK : This stack reuses the sandbox Traefik — sandbox MUST be running
#           before executing this script.
#
# HOW TO USE:
#   1. Make sure sandbox stack is running first:
#      docker compose -f ~/aruga_docker/compose/compose.sandbox.yaml ps
#   2. Update the variables below marked [CHANGE THIS]
#   3. Make sure compose.production.yaml is configured with your domain
#   4. chmod +x scripts/install-aruga-production.sh
#   5. cd ~/aruga_docker && ./scripts/install-aruga-production.sh
#
# TO RE-RUN (e.g. after server reboot):
#   Just run cd ~/aruga_docker && ./scripts/install-aruga-production.sh again — it detects existing sites
#   and runs migrate + clear-cache instead of reinstalling from scratch.
# =============================================================================

set -e

# -----------------------------------------------------------------------------
# [CHANGE THIS] Configuration — update these for each new deployment
# -----------------------------------------------------------------------------

# Your production domain (must match FRAPPE_SITE_NAME_HEADER in compose.production.yaml)
SITE_NAME="playlab.serviotech.com"

# Admin password for the ARUGA web interface
ADMIN_PASSWORD="servio_aruga"

# MariaDB root password (must match MYSQL_ROOT_PASSWORD in compose.production.yaml)
DB_ROOT_PASSWORD="frappe"

# Path to the install directory
INSTALL_DIR="$HOME/aruga_docker"

# Path to the production compose file
COMPOSE_FILE="$INSTALL_DIR/compose/compose.production.yaml"

# Path to the sandbox compose file — used to verify Traefik is running
SANDBOX_COMPOSE="$INSTALL_DIR/compose/compose.sandbox.yaml"

# [CHANGE THIS] Sandbox Traefik container name
# Pattern: <sandbox-stack-name>-traefik-1
# Default sandbox stack is aruga_sandbox → aruga_sandbox-traefik-1
TRAEFIK_CONTAINER="aruga_sandbox-traefik-1"

# [CHANGE THIS] Sandbox Docker network name
# Pattern: <sandbox-stack-name>_default
TRAEFIK_NETWORK="aruga_sandbox_default"

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
echo " ARUGA Production Installer"
echo " Version  : v0.0.1"
echo " Site     : $SITE_NAME"
echo " Compose  : $COMPOSE_FILE"
echo -e "========================================${NC}"
echo ""

# -----------------------------------------------------------------------------
# [1/7] Check Docker
# -----------------------------------------------------------------------------
print_step "[1/7] Checking Docker..."
command -v docker &>/dev/null          || print_error "Docker not installed."
docker info &>/dev/null                || print_error "Docker daemon not running."
docker compose version &>/dev/null     || print_error "Docker Compose plugin missing."
print_ok "Docker $(docker --version)"
print_ok "$(docker compose version)"

# -----------------------------------------------------------------------------
# [2/7] Check sandbox Traefik is running
# NOTE: Production relies on sandbox's Traefik for SSL and routing.
#       If Traefik is down, production won't be reachable via HTTPS.
# -----------------------------------------------------------------------------
print_step "[2/7] Checking sandbox Traefik is running..."
if ! docker ps --format '{{.Names}}' | grep -q "$TRAEFIK_CONTAINER"; then
    print_error "Sandbox Traefik ($TRAEFIK_CONTAINER) is not running!
    Start the sandbox stack first:
      docker compose -f $SANDBOX_COMPOSE up -d"
fi
print_ok "Traefik is running ($TRAEFIK_CONTAINER)"

# -----------------------------------------------------------------------------
# [3/7] Check Traefik network exists
# Production frontend needs to join this network so Traefik can route to it.
# -----------------------------------------------------------------------------
print_step "[3/7] Checking shared Traefik network..."
if ! docker network ls --format '{{.Name}}' | grep -q "^${TRAEFIK_NETWORK}$"; then
    print_error "Network '$TRAEFIK_NETWORK' not found.
    Is the sandbox stack up and healthy?
      docker compose -f $SANDBOX_COMPOSE ps"
fi
print_ok "Network '$TRAEFIK_NETWORK' found"

# -----------------------------------------------------------------------------
# [4/7] Check compose file exists
# -----------------------------------------------------------------------------
print_step "[4/7] Checking compose file..."
[ -f "$COMPOSE_FILE" ] || print_error "Compose file not found: $COMPOSE_FILE
    Make sure compose.production.yaml is in $INSTALL_DIR/compose/"
print_ok "Compose file found"

# -----------------------------------------------------------------------------
# [5/7] Start production containers
# -----------------------------------------------------------------------------
print_step "[5/7] Starting production services..."
docker compose -f "$COMPOSE_FILE" up -d
print_ok "Production services started"

# -----------------------------------------------------------------------------
# [6/7] Wait for database
# -----------------------------------------------------------------------------
print_step "[6/7] Waiting for production database to be ready..."
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
# [7/7] Create or update site
# -----------------------------------------------------------------------------
print_step "[7/7] Checking if production site exists..."

if ! docker compose -f "$COMPOSE_FILE" exec -T backend bench --site "$SITE_NAME" list-apps >/dev/null 2>&1; then

    print_warn "Site not found. Creating new production site..."
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
echo " PRODUCTION INSTALL COMPLETE"
echo "========================================"
echo ""
echo "  Sandbox    : https://playlab-sandbox.serviotech.com"
echo "  Production : https://$SITE_NAME"
echo ""
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
