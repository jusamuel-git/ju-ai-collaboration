@echo off
rem C5c manual deploy (approved): c5d WAR to 8081, auto-restore on health fail
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0ai_c5c_deploy_manual.ps1"
echo.
echo Done. You can close this window.
pause
