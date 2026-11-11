@echo off
rem C5d: desktop server-first plan + data-map. build + tests + regression, local commit only (no push, real DB unchanged)
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0ai_c5d.ps1"
echo.
echo Done. You can close this window.
pause
