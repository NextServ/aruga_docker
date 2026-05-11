#!/bin/bash
# ========================================
# ARUGA Accounting and Payroll Installer
# Version v0.0.8 - DigitalOcean / Linux
# Domain: playlab-sandbox.serviotech.com
# ========================================

set -e

SITE_NAME="playlab-sandbox.serviotech.com"
ADMIN_PASSWORD="servio_aruga"
DB_ROOT_PASSWORD="frappe"
INSTALL_DIR="$HOME/aruga_docker"
COMPOSE_FILE="$INSTALL_DIR/compose_custom_local.yaml"
REPO_URL="https://github.com/NextServ/aruga_docker.git"
REPO_BRANCH="aruga_acct_payroll"

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

print_ok()    { echo -e "${GREEN}OK: $1${NC}"; }
print_error() { echo -e "${RED}ERROR: $1${NC}"; }
print_warn()  { echo -e "${YELLOW}WARN: $1${NC}"; }
print_step()  { echo -e "\n${GREEN}$1${NC}"; }

echo "========================================"
echo " ARUGA Installation Wizard"
echo " Version v0.0.8"
echo " Target: $SITE_NAME"
echo "========================================"
echo ""

# -----------------------------------------
# 1. Check Docker
# -----------------------------------------
print_step "[1/6] Checking Docker..."
if ! command -v docker &>/dev/null; then
    print_error "Docker is not installed."
    echo "Install it with: curl -fsSL https://get.docker.com | sh"
    exit 1
fi
if ! docker info &>/dev/null; then
    print_error "Docker daemon is not running. Try: systemctl start docker"
    exit 1
fi
print_ok "Docker detected: $(docker --version)"

# Check Docker Compose
if ! docker compose version &>/dev/null; then
    print_error "Docker Compose plugin not found."
    echo "Install it with: apt install docker-compose-plugin -y"
    exit 1
fi
print_ok "Docker Compose detected: $(docker compose version)"
echo ""

# -----------------------------------------
# 2. Check Git
# -----------------------------------------
print_step "[2/6] Checking Git..."
if ! command -v git &>/dev/null; then
    print_error "Git is not installed."
    echo "Install it with: apt install git -y"
    exit 1
fi
print_ok "Git detected: $(git --version)"
echo ""

# -----------------------------------------
# 3. Prepare Installation Directory
# -----------------------------------------
print_step "[3/6] Preparing ARUGA files..."
if [ -d "$INSTALL_DIR" ]; then
    echo "Existing installation found. Updating..."
    cd "$INSTALL_DIR"
    git reset --hard >/dev/null 2>&1 || true
    if ! git pull; then
        print_warn "Git pull failed. Reinstalling from scratch..."
        cd "$HOME"
        rm -rf "$INSTALL_DIR"
        git clone "$REPO_URL" -b "$REPO_BRANCH" "$INSTALL_DIR"
    fi
else
    echo "Cloning ARUGA repository..."
    git clone "$REPO_URL" -b "$REPO_BRANCH" "$INSTALL_DIR"
fi
cd "$INSTALL_DIR"
print_ok "Files ready at $INSTALL_DIR"
echo ""

# -----------------------------------------
# 4. Start Containers
# -----------------------------------------
print_step "[4/6] Starting ARUGA services..."
docker compose -f "$COMPOSE_FILE" up -d
print_ok "Services started."
echo ""

# -----------------------------------------
# 5. Wait for Database
# -----------------------------------------
print_step "[5/6] Waiting for database to be ready..."
MAX_TRIES=30
TRIES=0
until docker compose -f "$COMPOSE_FILE" exec db mysqladmin ping -uroot -p"$DB_ROOT_PASSWORD" --silent >/dev/null 2>&1; do
    TRIES=$((TRIES + 1))
    if [ "$TRIES" -ge "$MAX_TRIES" ]; then
        print_error "Database did not become ready in time. Check logs with:"
        echo "  docker compose -f $COMPOSE_FILE logs db"
        exit 1
    fi
    echo "  Waiting for DB... ($TRIES/$MAX_TRIES)"
    sleep 5
done
print_ok "Database is ready."
echo ""

# Wait a bit more for configurator to finish
echo "Waiting for configurator to complete..."
sleep 20

# -----------------------------------------
# 6. Create / Update Site
# -----------------------------------------
print_step "[6/6] Checking if ARUGA site exists..."
if ! docker compose -f "$COMPOSE_FILE" exec -T backend bench --site "$SITE_NAME" list-apps >/dev/null 2>&1; then

    echo "Site not found. Creating new ARUGA system..."
    echo "This will take 4-7 minutes. Please wait..."
    echo ""

    echo "--- Step 1: Creating site..."
    docker compose -f "$COMPOSE_FILE" exec -T backend bench new-site "$SITE_NAME" \
      --mariadb-root-password "$DB_ROOT_PASSWORD" \
      --admin-password "$ADMIN_PASSWORD" \
      --mariadb-user-host-login-scope='%' \
      --install-app frappe

    echo "--- Step 2: Installing ERPNext..."
    docker compose -f "$COMPOSE_FILE" exec -T backend bench --site "$SITE_NAME" install-app erpnext

    echo "--- Step 3: Installing HRMS..."
    docker compose -f "$COMPOSE_FILE" exec -T backend bench --site "$SITE_NAME" install-app hrms

    echo "--- Step 4: Installing ARUGA Accounting..."
    docker compose -f "$COMPOSE_FILE" exec -T backend bench --site "$SITE_NAME" install-app aruga_acct

    echo "--- Step 5: Installing ARUGA Payroll..."
    docker compose -f "$COMPOSE_FILE" exec -T backend bench --site "$SITE_NAME" install-app aruga_pay

    echo "--- Step 6: Installing ARUGA Main..."
    docker compose -f "$COMPOSE_FILE" exec -T backend bench --site "$SITE_NAME" install-app aruga_main

    echo "--- Step 7: Running migrations..."
    docker compose -f "$COMPOSE_FILE" exec -T backend bench --site "$SITE_NAME" migrate

    echo "--- Step 8: Running ARUGA Payroll setup..."
    sleep 8
    docker compose -f "$COMPOSE_FILE" exec -T backend bench --site "$SITE_NAME" execute aruga_pay.install.after_install

    echo "--- Step 9: Clearing cache..."
    sleep 5
    docker compose -f "$COMPOSE_FILE" exec -T backend bench --site "$SITE_NAME" clear-cache

else
    echo "Existing site detected. Running update..."

    echo "--- Migrating..."
    docker compose -f "$COMPOSE_FILE" exec -T backend bench --site "$SITE_NAME" migrate

    echo "--- Running ARUGA Payroll setup..."
    docker compose -f "$COMPOSE_FILE" exec -T backend bench --site "$SITE_NAME" execute aruga_pay.install.after_install

    echo "--- Clearing cache..."
    docker compose -f "$COMPOSE_FILE" exec -T backend bench --site "$SITE_NAME" clear-cache
fi

# -----------------------------------------
# Done
# -----------------------------------------
echo ""
echo "========================================"
echo " INSTALLATION COMPLETE"
echo "========================================"
echo ""
echo "  Access ARUGA → https://$SITE_NAME"
echo "  Username      : Administrator"
echo "  Password      : $ADMIN_PASSWORD"
echo ""
echo "  NOTE: SSL certificate may take 1-2 minutes"
echo "  to provision on first access."
echo ""
echo "  To check Traefik SSL logs:"
echo "  docker compose -f $COMPOSE_FILE logs traefik"
echo ""
echo "Installation completed successfully!"
