@echo off
rem C5d real-device regression: GTEC on COM3. Follow on-screen prompts to unplug/replug the USB cable.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0ai_c5d_probe.ps1"
echo.
echo Done. You can close this window.
pause
