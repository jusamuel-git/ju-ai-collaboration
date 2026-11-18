@echo off
rem C6a terminal collection engine: apply files on feature/c6a-terminal, build 5, tests
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0ai_c6a.ps1"
echo.
echo Done. You can close this window.
pause
