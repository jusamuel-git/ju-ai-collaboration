@echo off
rem JU-0A SQL test DB validation (test DBs only; real DB read-only dump)
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0ai_ju0a_db.ps1"
echo.
echo Done.
pause
