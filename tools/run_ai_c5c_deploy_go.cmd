@echo off
rem C5c deploy step 1: backup + main fast-forward push
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0ai_c5c_deploy_go.ps1"
echo.
echo Done. You can close this window.
pause
