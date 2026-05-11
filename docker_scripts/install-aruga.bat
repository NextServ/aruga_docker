@echo off
setlocal enabledelayedexpansion
title ARUGA Accounting and Payroll Installer
color 0A

echo ========================================
echo ARUGA Installation Wizard
echo Version v0.0.7
echo ========================================
echo.

:: -----------------------------------------
:: 1. Check Docker
:: -----------------------------------------
echo [1/6] Checking Docker Desktop...
docker --version >nul 2>&1
if errorlevel 1 (
    echo ERROR: Docker Desktop is not running.
    echo Please start Docker Desktop and try again.
    pause
    exit /b 1
)
echo OK: Docker detected.
echo.

:: -----------------------------------------
:: 2. Check Git
:: -----------------------------------------
echo [2/6] Checking Git...
git --version >nul 2>&1
if errorlevel 1 (
    echo ERROR: Git is not installed.
    echo Download from: https://git-scm.com/downloads
    pause
    exit /b 1
)
echo OK: Git detected.
echo.

:: -----------------------------------------
:: 3. Prepare Installation Directory
:: -----------------------------------------
set INSTALL_DIR=%USERPROFILE%\aruga_docker
echo [3/6] Preparing ARUGA files...
if exist "%INSTALL_DIR%" (
    echo Existing installation found. Updating...
    cd "%INSTALL_DIR%"
    git reset --hard >nul 2>&1
    git pull
    if errorlevel 1 (
        echo WARNING: Git update failed. Reinstalling...
        cd "%USERPROFILE%"
        rmdir /s /q "%INSTALL_DIR%"
        git clone https://github.com/NextServ/aruga_docker.git -b aruga_acct_payroll
    )
) else (
    echo Cloning ARUGA repository...
    cd "%USERPROFILE%"
    git clone https://github.com/NextServ/aruga_docker.git -b aruga_acct_payroll
)
cd "%INSTALL_DIR%"
echo OK: Files ready.
echo.

:: -----------------------------------------
:: 4. Start Containers
:: -----------------------------------------
echo [4/6] Starting ARUGA services...
docker compose -f compose/compose.custom_local.yaml up -d
if errorlevel 1 (
    echo ERROR: Failed to start services.
    pause
    exit /b 1
)
echo OK: Services started.
echo.
:: -----------------------------------------
:: 4. Wait for Database
:: -----------------------------------------
echo Waiting for database...
:wait_db
docker compose -f compose/compose.custom_local.yaml exec db mysqladmin ping -uroot -pfrappe --silent >nul 2>&1
if errorlevel 1 (
    timeout /t 5 >nul
    goto wait_db
)
echo Database ready.
echo.

timeout /t 15 >nul

:: -----------------------------------------
:: 6. Create / Update Site
:: -----------------------------------------
echo [6/6] Checking if ARUGA site exists...
docker compose -f compose/compose.custom_local.yaml exec -T backend bench --site localhost list-apps >nul 2>&1
if errorlevel 1 (
    echo Site not found. Creating new ARUGA system...
    echo This will take 4-7 minutes...
    echo.

    echo Step 1: Creating site...
    docker compose -f compose/compose.custom_local.yaml exec -T backend bench new-site localhost ^
      --mariadb-root-password frappe ^
      --admin-password servio_aruga ^
      --mariadb-user-host-login-scope="%%" ^
      --install-app frappe

    echo Step 2: Installing ERPNext + HRMS + ARUGA Apps...
    docker compose -f compose/compose.custom_local.yaml exec -T backend bench --site localhost install-app erpnext
    docker compose -f compose/compose.custom_local.yaml exec -T backend bench --site localhost install-app hrms
    docker compose -f compose/compose.custom_local.yaml exec -T backend bench --site localhost install-app aruga_acct
    docker compose -f compose/compose.custom_local.yaml exec -T backend bench --site localhost install-app aruga_pay
    docker compose -f compose/compose.custom_local.yaml exec -T backend bench --site localhost install-app aruga_main

    echo Step 3: Running ARUGA Payroll Setup...
    docker compose -f compose/compose.custom_local.yaml exec -T backend bench --site localhost migrate
    timeout /t 8 >nul
    docker compose -f compose/compose.custom_local.yaml exec -T backend bench --site localhost execute aruga_pay.install.after_install
    timeout /t 5 >nul
    docker compose -f compose/compose.custom_local.yaml exec -T backend bench --site localhost clear-cache

) else (
    echo Existing site detected. Updating...
    docker compose -f compose/compose.custom_local.yaml exec -T backend bench --site localhost migrate
    docker compose -f compose/compose.custom_local.yaml exec -T backend bench --site localhost execute aruga_pay.install.after_install
    docker compose -f compose/compose.custom_local.yaml exec -T backend bench --site localhost clear-cache
)

echo.
echo ========================================
echo INSTALLATION COMPLETE
echo ========================================
echo.
echo Access ARUGA → http://localhost:8080
echo Username: Administrator
echo Password: servio_aruga
echo.
echo Opening browser...
timeout /t 3 >nul
start http://localhost:8080

echo Installation completed successfully!
pause