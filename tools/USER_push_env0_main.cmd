@echo off
rem USER ONLY: push main of juprovider and juproject (ENV-0)
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0push_main.ps1"
pause
