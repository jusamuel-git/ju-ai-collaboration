@echo off
rem C5c: server validation, sync response, data-map. build + regression, local commit only (no push, real DB unchanged)
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0ai_c5c.ps1"
echo.
echo Done. You can close this window.
pause
