@echo off
rem C6c real device: check server DEV_CONFIG, start Terminal and Client (login is typed by the user)
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0ai_c6c_app.ps1"
timeout /t 5
