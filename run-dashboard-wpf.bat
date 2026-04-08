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

REM Run the PowerShell script
echo Starting AFOTRA Dashboard...
powershell -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT_DIR%dashboard-wpf.ps1"

if errorlevel 1 (
    echo.
    echo An error occurred while running the dashboard.
    pause
)

exit /b %errorlevel%