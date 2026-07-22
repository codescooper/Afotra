@echo off
REM run-dashboard-wpf.bat - Launch AFOTRA Dashboard
REM This script runs the PowerShell WPF dashboard

setlocal enabledelayedexpansion

REM Get the directory of this batch file
set "SCRIPT_DIR=%~dp0"

REM Check if dashboard-wpf.ps1 exists
if not exist "%SCRIPT_DIR%dashboard-wpf.ps1" (
    echo Error: dashboard-wpf.ps1 not found!
    pause
    exit /b 1
)

REM Check if PowerShell is available
powershell -Command "Exit 0" >nul 2>&1
if errorlevel 1 (
    echo Error: PowerShell is not available!
    pause
    exit /b 1
)

REM Run the PowerShell script with a temporary process-scoped policy.
REM Avoid -ExecutionPolicy Bypass: project scripts should run under RemoteSigned.
echo Starting AFOTRA Dashboard...
powershell -NoProfile -Command "Set-ExecutionPolicy -Scope Process -ExecutionPolicy RemoteSigned -Force; & '%SCRIPT_DIR%dashboard-wpf.ps1'"
if not exist "%SCRIPT_DIR%logs" mkdir "%SCRIPT_DIR%logs"
set "DASHBOARD_LOG=%SCRIPT_DIR%logs\dashboard-launch.log"
echo [%date% %time%] Starting AFOTRA Dashboard > "%DASHBOARD_LOG%"
powershell -NoProfile -Sta -ExecutionPolicy Bypass -File "%SCRIPT_DIR%dashboard-wpf.ps1" >> "%DASHBOARD_LOG%" 2>&1
set "DASHBOARD_EXIT=%errorlevel%"

if not "%DASHBOARD_EXIT%"=="0" (
    echo.
    echo An error occurred while running the dashboard.
    echo Details were saved to:
    echo "%DASHBOARD_LOG%"
    pause
) else (
    echo [%date% %time%] Dashboard closed normally. >> "%DASHBOARD_LOG%"
)

exit /b %errorlevel%
