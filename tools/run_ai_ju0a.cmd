@echo off
rem ENV-0 local commit + JU-0A branch/files + build (no push)
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0ai_ju0a.ps1"
echo.
echo Done.
pause
