@echo off
setlocal enabledelayedexpansion
title ARUGA Update Tool
color 0E

echo ========================================
echo ARUGA Update Tool
echo Version 1.1
echo ========================================
echo.

:: -----------------------------------------
:: 1. Check Installation
:: -----------------------------------------
set INSTALL_DIR=%USERPROFILE%\aruga_docker
if not exist "%INSTALL_DIR%" (
    echo ERROR: ARUGA installation not found.
    echo Expected location: %INSTALL_DIR%
    echo.
    echo Please install ARUGA first using install-aruga.bat
    pause
    exit /b 1
)

cd "%INSTALL_DIR%"
echo Installation found: %INSTALL_DIR%
echo.

set COMPOSE_FILE=compose/compose.custom_local.yaml

:: -----------------------------------------
:: 2. Show Current Version
:: -----------------------------------------
echo Detecting current version...
for /f "tokens=2 delims=:" %%a in ('findstr /C:"image: serviodocker/aruga_acct_payroll" %COMPOSE_FILE% ^| findstr /v "^#"') do (
    set CURRENT_IMAGE=%%a
    goto :found_version
)
:found_version
set CURRENT_VERSION=!CURRENT_IMAGE:~-7!
echo Current version: !CURRENT_VERSION!
echo.

:: -----------------------------------------
:: 3. Check Docker Running
:: -----------------------------------------
echo Checking Docker...
docker --version >nul 2>&1
if errorlevel 1 (
    echo ERROR: Docker Desktop is not running.
    echo Please start Docker Desktop and try again.
    pause
    exit /b 1
)
echo OK: Docker is running.
echo.

:: -----------------------------------------
:: 4. Get New Version
:: -----------------------------------------
set /p NEW_VERSION="Enter new version (e.g., v0.0.6): "

if "%NEW_VERSION%"=="" (
    echo ERROR: Version is required.
    pause
    exit /b 1
)

:: Validate version format
echo %NEW_VERSION% | findstr /R "^v[0-9]\.[0-9]\.[0-9]$" >nul
if errorlevel 1 (
    echo WARNING: Version format should be v0.0.6
    set /p CONTINUE="Continue anyway? (Y/N): "
    if /i not "!CONTINUE!"=="Y" (
        echo Update cancelled.
        pause
        exit /b 0
    )
)

echo.
echo ========================================
echo Update Summary
echo ========================================
echo Current version: !CURRENT_VERSION!
echo New version:     %NEW_VERSION%
echo.
echo IMPORTANT: This update will:
echo - Reset apps and python environment to match new image
echo - Keep your site data and database intact
echo - Remove any test apps installed via bench get-app
echo.
set /p CONFIRM="Proceed with update? (Y/N): "
if /i not "%CONFIRM%"=="Y" (
    echo Update cancelled.
    pause
    exit /b 0
)

:: -----------------------------------------
:: 5. Backup Current Compose File
:: -----------------------------------------
echo.
echo Creating backup...
copy %COMPOSE_FILE% %COMPOSE_FILE%.backup.%date:~10,4%%date:~4,2%%date:~7,2%_%time:~0,2%%time:~3,2%%time:~6,2%
echo Backup saved: %COMPOSE_FILE%.backup.*
echo.

:: -----------------------------------------
:: 6. Create Database Backup
:: -----------------------------------------
echo Creating database backup (recommended before updates)...
set /p DO_BACKUP="Create backup now? (Y/N): "
if /i "%DO_BACKUP%"=="Y" (
    echo Running backup...
    docker compose -f %COMPOSE_FILE% exec -T backend bench --site localhost backup
    if errorlevel 1 (
        echo WARNING: Backup failed, but continuing...
    ) else (
        echo Backup created successfully.
    )
)
echo.

:: -----------------------------------------
:: 7. Pull New Image
:: -----------------------------------------
echo [1/7] Pulling new image from Docker Hub...
docker pull serviodocker/aruga_acct_payroll:%NEW_VERSION%

if errorlevel 1 (
    echo ERROR: Failed to pull image.
    echo.
    echo Possible reasons:
    echo - Version %NEW_VERSION% does not exist on Docker Hub
    echo - Network connection issue
    echo - Docker Hub is down
    echo.
    echo Restoring backup...
    copy %COMPOSE_FILE%.backup.* %COMPOSE_FILE%
    pause
    exit /b 1
)
echo OK: Image downloaded.
echo.

:: -----------------------------------------
:: 8. Update Compose File
:: -----------------------------------------
echo [2/7] Updating compose configuration...
powershell -Command "(Get-Content %COMPOSE_FILE%) -replace 'serviodocker/aruga_acct_payroll:v[0-9.]+','serviodocker/aruga_acct_payroll:%NEW_VERSION%' | Set-Content %COMPOSE_FILE%"

if errorlevel 1 (
    echo ERROR: Failed to update compose file.
    echo Restoring backup...
    copy %COMPOSE_FILE%.backup.* %COMPOSE_FILE%
    pause
    exit /b 1
)
echo OK: Compose file updated.
echo.

:: -----------------------------------------
:: 9. Stop Containers
:: -----------------------------------------
echo [3/7] Stopping current containers...
docker compose -f %COMPOSE_FILE% down

if errorlevel 1 (
    echo WARNING: Error stopping containers, continuing...
)
echo OK: Containers stopped.
echo.

:: -----------------------------------------
:: 10. Reset Apps and Env Volumes
:: -----------------------------------------
echo [4/7] Resetting apps and environment volumes...
echo This ensures new app versions take effect.
docker volume rm aruga_docker_apps >nul 2>&1
docker volume rm aruga_docker_env >nul 2>&1
echo OK: Volumes reset.
echo.

:: -----------------------------------------
:: 11. Start Containers
:: -----------------------------------------
echo [5/7] Starting new containers...
docker compose -f %COMPOSE_FILE% up -d

if errorlevel 1 (
    echo ERROR: Failed to start containers.
    echo.
    echo Rolling back to previous version...
    copy %COMPOSE_FILE%.backup.* %COMPOSE_FILE%
    docker compose -f %COMPOSE_FILE% up -d
    pause
    exit /b 1
)
echo OK: Containers restarted.
echo.

echo Waiting for services to initialize (30 seconds)...
timeout /t 30 /nobreak >nul

:: -----------------------------------------
:: 12. Run Migrations
:: -----------------------------------------
echo [6/7] Running database migrations...
docker compose -f %COMPOSE_FILE% exec -T backend bench --site localhost migrate

if errorlevel 1 (
    echo WARNING: Migration had errors.
    echo This may or may not be a problem.
    echo Check logs: docker compose -f %COMPOSE_FILE% logs backend
    echo.
    set /p CONTINUE_AFTER_ERROR="Continue with update? (Y/N): "
    if /i not "!CONTINUE_AFTER_ERROR!"=="Y" (
        echo Rolling back...
        copy %COMPOSE_FILE%.backup.* %COMPOSE_FILE%
        docker compose -f %COMPOSE_FILE% down
        docker volume rm aruga_docker_apps >nul 2>&1
        docker volume rm aruga_docker_env >nul 2>&1
        docker compose -f %COMPOSE_FILE% up -d
        pause
        exit /b 1
    )
) else (
    echo OK: Migrations completed.
)
echo.

:: -----------------------------------------
:: 13. Clear Cache and Restart
:: -----------------------------------------
echo [7/7] Running payroll setup, clearing cache, and restarting backend...
docker compose -f %COMPOSE_FILE% exec -T backend bench --site localhost execute aruga_pay.install.after_install
if errorlevel 1 (
    echo WARNING: Payroll setup had errors, but continuing...
) else (
    echo OK: Payroll setup completed.
)
docker compose -f %COMPOSE_FILE% exec -T backend bench --site localhost clear-cache
docker compose -f %COMPOSE_FILE% restart backend
echo OK: Backend restarted.
echo.

:: -----------------------------------------
:: 14. Finish
:: -----------------------------------------
echo ========================================
echo UPDATE COMPLETE!
echo ========================================
echo.
echo Updated from: !CURRENT_VERSION!
echo Updated to:   %NEW_VERSION%
echo.
echo Backup location:
echo %COMPOSE_FILE%.backup.*
echo.
echo Access ARUGA:
echo http://localhost:8080
echo.
echo IMPORTANT:
echo - Test thoroughly before production use
echo - Site data and database are preserved
echo - Test apps installed via bench get-app were removed
echo   (reinstall them if needed)
echo - Check logs if you see any errors:
echo   docker compose -f %COMPOSE_FILE% logs
echo.
echo ========================================

:: Open ARUGA
start http://localhost:8080

pause