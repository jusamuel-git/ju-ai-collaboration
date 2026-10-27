@echo off
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0ai_pr2_branch_push.ps1"
echo.
echo Done.
pause
