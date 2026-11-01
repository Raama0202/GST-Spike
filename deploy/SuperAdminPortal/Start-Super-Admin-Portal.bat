@echo off
setlocal
title GST Expense - Super Admin Portal
cd /d "%~dp0"

where powershell >nul 2>nul
if errorlevel 1 (
  echo Windows PowerShell was not found. It ships with Windows 7 SP1 and later.
  pause
  exit /b 1
)

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0portal-server.ps1" %*
if errorlevel 1 (
  echo.
  echo The portal stopped with an error. See the messages above.
  pause
)
endlocal
