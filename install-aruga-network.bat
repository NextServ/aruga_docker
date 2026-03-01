@echo off
setlocal enabledelayedexpansion
title ARUGA Accounting and Payroll Installer
color 0A

echo ========================================
echo ARUGA Installation Wizard
echo Version v0.0.3 - Network Access
echo ========================================
echo.

:: -----------------------------------------
:: 1. Check Docker
:: -----------------------------------------
echo Checking Docker Desktop...
docker --version >nul 2>&1
if errorlevel 1 (
    echo ERROR: Docker Desktop is not running.
    pause
    exit /b 1
)
echo OK: Docker detected.
echo.

:: -----------------------------------------
:: 2. Prepare Installation Directory
:: -----------------------------------------
set INSTALL_DIR=%USERPROFILE%\aruga_docker

echo Preparing ARUGA files...
if exist "%INSTALL_DIR%" (
    echo Updating existing installation...
    cd "%INSTALL_DIR%"
    git pull
) else (
    echo Cloning ARUGA repository...
    cd "%USERPROFILE%"
    git clone https://github.com/NextServ/aruga_docker.git -b aruga_acct_payroll
    cd "%INSTALL_DIR%"
)
echo OK: Files ready.
echo.

:: -----------------------------------------
:: 3. Start Containers
:: -----------------------------------------
echo Starting ARUGA services...
docker compose -f compose/compose.custom_local.yaml up -d
if errorlevel 1 (
    echo ERROR: Failed to start services.
    pause
    exit /b 1
)
echo Services started.
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
:: 5. Create Site (Only If Not Exists)
:: -----------------------------------------
echo Checking if ARUGA site already exists...

docker compose -f compose/compose.custom_local.yaml exec -T backend bench --site localhost list-apps >nul 2>&1

if errorlevel 1 (
    echo Site not found. Creating ARUGA system...

    docker compose -f compose/compose.custom_local.yaml exec -T backend bench new-site aruga.local ^
      --mariadb-root-password frappe ^
      --admin-password servio_aruga ^
      --mariadb-user-host-login-scope="%%" ^
      --install-app frappe

    if errorlevel 1 (
        echo ERROR: Site creation failed.
        pause
        exit /b 1
    )

    echo Installing applications...

docker compose -f compose/compose.custom_local.yaml exec -T backend bench --site aruga.local install-app erpnext
docker compose -f compose/compose.custom_local.yaml exec -T backend bench --site aruga.local install-app hrms
docker compose -f compose/compose.custom_local.yaml exec -T backend bench --site aruga.local install-app aruga_acct
docker compose -f compose/compose.custom_local.yaml exec -T backend bench --site aruga.local install-app aruga_pay
docker compose -f compose/compose.custom_local.yaml exec -T backend bench --site aruga.local install-app aruga_main


) else (
    echo Existing ARUGA site detected. Skipping creation.
)


:: -----------------------------------------
:: 6. Finish
:: -----------------------------------------
echo.
echo ========================================
echo INSTALLATION COMPLETE
echo ========================================
echo.
echo Installation Location:
echo %INSTALL_DIR%
echo.
echo Open your browser:
echo http://localhost:8080
echo.
echo Login Details:
echo Username: Administrator
echo Password: servio_aruga
echo.
echo Aruga User Guide:
echo %INSTALL_DIR%\README.md
echo.
echo IMPORTANT:
echo This is a LOCAL installation.
echo Change your password after login.
echo.

:: Open ARUGA
start http://localhost:8080

:: Open README
echo Opening ARUGA User Guide...
timeout /t 3 >nul
start "" "%INSTALL_DIR%\README.md"

pause
