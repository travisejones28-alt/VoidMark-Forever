@echo off
setlocal
title Install VoidMark Automatic Kill Sync
cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Install_VoidMark_AutoSync.ps1"
echo.
pause
