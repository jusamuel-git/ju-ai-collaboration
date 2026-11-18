@echo off
rem [APPROVAL REQUIRED] admin temporary password reset (DB update). Type the temp password in this window.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0ai_admin_pw_reset.ps1"
echo.
echo Done. You can close this window.
pause
