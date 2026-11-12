@echo off
rem C5e step 5 check only (read-only): Tomcat 8081 health/log
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0ai_c5e_check5.ps1"
echo.
echo Done. You can close this window.
pause
