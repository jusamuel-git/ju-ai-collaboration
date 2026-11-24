@echo off
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0ai_tpl_verify.ps1"
timeout /t 3
