@echo off
rem 11/18 status check (read-only, starts Tomcat if down)
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0ai_1118_status.ps1"
echo.
echo Done. You can close this window.
pause
