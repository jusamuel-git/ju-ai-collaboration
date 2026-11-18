@echo off
rem Tomcat service-mode env rehearsal (separate base 18082, test DB, no service install)
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0ai_c5n_svc_rehearsal.ps1"
echo.
echo Done. You can close this window.
pause
