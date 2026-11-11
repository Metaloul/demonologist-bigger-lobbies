@echo off
title Demonologist - uninstall Big Lobbies
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0files\install.ps1" -Uninstall
echo.
pause
