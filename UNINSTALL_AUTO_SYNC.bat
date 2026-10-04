@echo off
setlocal
title Uninstall VoidMark Automatic Kill Sync
cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Uninstall_VoidMark_AutoSync.ps1"
echo.
pause
