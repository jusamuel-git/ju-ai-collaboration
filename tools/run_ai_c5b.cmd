@echo off
rem C5b: migration 08 test DB verification + build + regression, local commit only (no push, real DB unchanged)
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0ai_c5b.ps1"
echo.
echo Done. You can close this window.
pause
