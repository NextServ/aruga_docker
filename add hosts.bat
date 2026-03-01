@echo off
:: Check if running as admin
openfiles >nul 2>&1
if %errorlevel% NEQ 0 (
    echo Requesting administrator privileges...
    powershell -Command "Start-Process '%~f0' -Verb runAs"
    exit /b
)

:: Define your ARUGA IP and hostname
set ARUGA_IP=192.168.1.22
set ARUGA_HOST=aruga.local

:: Backup hosts file
set HOSTS_FILE=%windir%\System32\drivers\etc\hosts
set BACKUP_FILE=%HOSTS_FILE%.backup_%date:~-4%%date:~4,2%%date:~7,2%
echo Backing up hosts file to %BACKUP_FILE%
copy "%HOSTS_FILE%" "%BACKUP_FILE%" >nul

:: Check if entry already exists
findstr /C:"%ARUGA_IP% %ARUGA_HOST%" "%HOSTS_FILE%" >nul
if %errorlevel% EQU 0 (
    echo Hosts entry already exists. No changes made.
) else (
    echo Adding ARUGA entry to hosts file...
    echo %ARUGA_IP% %ARUGA_HOST% >> "%HOSTS_FILE%"
    echo Done.
)

pause
