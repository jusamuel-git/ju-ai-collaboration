@echo off
rem C5e step 5 diagnosis (read-only)
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0ai_c5e_diag5.ps1"
echo.
echo Done. You can close this window.
pause
