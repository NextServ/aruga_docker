@echo off
title Test Network Access
color 0B

echo ========================================
echo ARUGA Network Access Test
echo ========================================
echo.

echo Your IP address:
ipconfig | findstr IPv4
echo.

echo Testing firewall rule...
netsh advfirewall firewall show rule name="ARUGA ERPNext" >nul 2>&1
if errorlevel 1 (
    echo ❌ Firewall rule not found
    echo Run this as Administrator:
    echo netsh advfirewall firewall add rule name="ARUGA ERPNext" dir=in action=allow protocol=TCP localport=8080
) else (
    echo ✅ Firewall rule exists
)
echo.

echo Testing Docker services...
cd C:\Users\Carl\aruga_docker
docker compose -f compose/compose.custom_local.yaml ps | findstr "Up"
echo.

echo Testing localhost access...
curl -s http://localhost:8080 >nul 2>&1
if errorlevel 1 (
    echo ❌ localhost:8080 not accessible
    echo Make sure Docker is running
) else (
    echo ✅ localhost:8080 accessible
)
echo.

echo ========================================
echo Next Steps:
echo 1. Note your IP address above
echo 2. Try accessing from another device:
echo    http://YOUR_IP:8080
echo ========================================
pause