@echo off
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0ai_c5n_svc_cleanup.ps1"
echo.
echo Done. You can close this window.
pause
