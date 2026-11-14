@echo off
rem C5c deploy precheck: no real WAR swap, no main merge, no real DB change
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0ai_c5c_deploy_pre.ps1"
echo.
echo Done. You can close this window.
pause
