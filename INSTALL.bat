@echo off
title Demonologist - Big Lobbies
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0files\install.ps1" %*
echo.
pause
