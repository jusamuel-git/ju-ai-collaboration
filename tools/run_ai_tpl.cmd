@echo off
rem Local DB standard template: branch, generate template from code, build copy, build 5, tests, app check, commit and push
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0ai_tpl.ps1"
echo.
echo Done. You can close this window.
pause
