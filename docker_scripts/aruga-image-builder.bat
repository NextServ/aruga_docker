@echo off
setlocal enabledelayedexpansion
title ARUGA Image Builder
color 0A

echo ========================================
echo  ARUGA Image Builder
echo  Version v0.0.6
echo ========================================
echo.

:: -----------------------------------------
:: 1. Check Docker
:: -----------------------------------------
echo [1/4] Checking Docker Desktop...
docker --version >nul 2>&1
if errorlevel 1 (
    echo ERROR: Docker Desktop is not installed or not running!
    echo Please start Docker Desktop and try again.
    echo Download from: https://www.docker.com/products/docker-desktop/
    pause
    exit /b 1
)
echo OK: Docker detected.
echo.

:: -----------------------------------------
:: 2. Check Git
:: -----------------------------------------
echo [2/4] Checking Git...
git --version >nul 2>&1
if errorlevel 1 (
    echo ERROR: Git is not installed!
    echo Download from: https://git-scm.com/downloads
    pause
    exit /b 1
)
echo OK: Git detected.
echo.

:: -----------------------------------------
:: 3. Clone or Update Repo
:: -----------------------------------------
echo [3/4] Downloading ARUGA source files...
if exist aruga_docker (
    echo Existing folder found. Removing old version...
    rmdir /s /q aruga_docker
)
git clone https://github.com/NextServ/aruga_docker.git -b aruga_acct_payroll
if errorlevel 1 (
    echo ERROR: Failed to clone repository!
    echo Please check your internet connection and try again.
    pause
    exit /b 1
)
echo OK: Source files ready.
echo.
cd aruga_docker

:: -----------------------------------------
:: 4. Build Docker Image
:: -----------------------------------------
echo [4/4] Building ARUGA Docker Image...
echo This may take 10-20 minutes depending on your internet speed.
echo Please do not close this window.
echo.
docker build --no-cache ^
 --build-arg FRAPPE_PATH=https://github.com/frappe/frappe ^
 --build-arg FRAPPE_BRANCH=version-15 ^
 --build-arg APPS_JSON_BASE64=WwogICAgewogICAgICAgICJ1cmwiOiAiaHR0cHM6Ly9naXRodWIuY29tL2ZyYXBwZS9ocm1zIiwKICAgICAgICAiYnJhbmNoIjogInZlcnNpb24tMTUiCiAgICB9LAogICAgewogICAgICAgICJ1cmwiOiAiaHR0cHM6Ly9naXRodWIuY29tL2ZyYXBwZS9lcnBuZXh0IiwKICAgICAgICAiYnJhbmNoIjogInZlcnNpb24tMTUiCiAgICB9LAogICAgewogICAgICAgICJ1cmwiOiAiaHR0cHM6Ly9naXRodWIuY29tL05leHRTZXJ2L2FydWdhX2FjY3QiLAogICAgICAgICJicmFuY2giOiAibWFpbiIKICAgIH0sCiAgICB7CiAgICAgICAgInVybCI6ICJodHRwczovL2dpdGh1Yi5jb20vTmV4dFNlcnYvYXJ1Z2FfcGF5IiwKICAgICAgICAiYnJhbmNoIjogInZlcnNpb24tMTUiCiAgICB9LAogICAgewogICAgICAgICJ1cmwiOiAiaHR0cHM6Ly9naXRodWIuY29tL21va3VrZW4vYXJ1Z2FfbWFpbiIsCiAgICAgICAgImJyYW5jaCI6ICJtYWluIgogICAgfQpd ^
 --tag serviodocker/aruga_acct_payroll:v0.0.6 ^
 --file Dockerfile .
if errorlevel 1 (
    echo.
    echo ERROR: Docker image build failed!
    echo Check the error above and try again.
    pause
    exit /b 1
)

echo.
echo ========================================
echo  IMAGE BUILD COMPLETE!
echo ========================================
echo.
echo Image: serviodocker/aruga_acct_payroll:v0.0.6
echo.
echo You can now run the installer script to
echo set up and start the ARUGA system.
echo.
cd ..
pause