@echo off
rem Run ai_local_build.ps1 (build only: no deploy, no DB, no git changes)
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0ai_local_build.ps1"
echo.
echo Done. You can close this window.
pause
