@echo off
rem C5c deploy status (read-only)
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0ai_c5c_deploy_status.ps1"
echo.
echo Done. You can close this window.
pause
