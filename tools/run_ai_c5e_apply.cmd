@echo off
rem C5e: APPLY migration 06 -> 08 to the REAL DB (approved 11/12 21:27). Stops Tomcat, backs up, applies, verifies, starts Tomcat.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0ai_c5e_apply.ps1"
echo.
echo Done. You can close this window.
pause
