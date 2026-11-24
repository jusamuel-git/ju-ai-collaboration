@echo off
rem Local DB migration: branch, apply, build 5, tests, app checks (v1 rerun, new install, v0 copy, newer), commit and push
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0ai_mig.ps1"
echo.
echo Done. You can close this window.
pause
