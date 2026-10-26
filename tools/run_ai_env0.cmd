@echo off
rem ENV-0: branch + check + build (no commit/push, no DB, no deploy)
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0ai_env0.ps1"
echo.
echo Done. You can close this window.
pause
