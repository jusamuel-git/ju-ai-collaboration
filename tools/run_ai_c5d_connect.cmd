@echo off
rem C5d connect: register PC-B Desktop client (admin login typed here), verify client key sync, prepare COM3 regression
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0ai_c5d_connect.ps1"
echo.
echo Done. You can close this window.
pause
