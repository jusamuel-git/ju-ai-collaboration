@echo off
rem C6b client plan sync: apply, build 5, tests, commit and push feature branch
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0ai_c6b.ps1"
echo.
echo Done. You can close this window.
pause
