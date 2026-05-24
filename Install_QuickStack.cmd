@echo off
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\Install_QuickStack.ps1" %*
echo.
pause
