@echo off
rem C5d final real-device check: GTEC COM3 with real 8081 server settings. Unplug/replug cable when asked.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0ai_c5d_realprobe.ps1"
echo.
echo Done. You can close this window.
pause
