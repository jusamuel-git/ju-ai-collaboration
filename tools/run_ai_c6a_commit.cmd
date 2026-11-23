@echo off
rem C6a recheck, commit, push, create feature/c6b-client
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0ai_c6a_commit.ps1"
echo.
echo Done. You can close this window.
pause
