@echo off
rem C6c device collection screen: check C6b, branch, apply, DEV_CONFIG, connections.json, build 5, tests, commit and push
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0ai_c6c.ps1"
echo.
echo Done. You can close this window.
pause
