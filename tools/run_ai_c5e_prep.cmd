@echo off
rem C5e prep: regex fix commit on collect-c5d, push c5b/c5c/c5d (no main), real DB read-only precheck + backup/restore rehearsal on a copy
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0ai_c5e_prep.ps1"
echo.
echo Done. You can close this window.
pause
