@echo off
setlocal
title VoidMark Offline Kill Sync
cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0VoidMark_KillFileSync.ps1"
set ERR=%ERRORLEVEL%
echo.
if not "%ERR%"=="0" echo Sync exited with error code %ERR%.
pause
exit /b %ERR%
