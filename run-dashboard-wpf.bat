@echo off
REM run-dashboard-wpf.bat - Launch AFOTRA WPF Dashboard
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0dashboard-wpf.ps1"
pause