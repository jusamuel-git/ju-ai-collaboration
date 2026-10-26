@echo off
rem JU-0A real DB backup + 04 + verify + local commit, JU-0B change + smoke + build (no push)
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0ai_ju0b.ps1"
echo.
echo Done.
pause
