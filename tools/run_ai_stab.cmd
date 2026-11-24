@echo off
rem C6 stabilization: branch, apply, build 5, tests, app checks, commit and push
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0ai_stab.ps1"
echo.
echo Done. You can close this window.
pause
