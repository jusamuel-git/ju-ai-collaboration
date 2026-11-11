@echo off
rem C5c server regression + API only (test DB copy, real DB unchanged)
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0ai_c4srv.ps1" -C5c
echo.
echo Done. You can close this window.
pause
