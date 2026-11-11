@echo off
rem read-only: application control diagnosis
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0ai_c5c_appctl.ps1"
echo.
echo Done. You can close this window.
pause
