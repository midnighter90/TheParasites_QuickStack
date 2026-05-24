@echo off
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\Uninstall_QuickStack.ps1" %*
echo.
pause
