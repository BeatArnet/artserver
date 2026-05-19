@echo off
setlocal
cd /d "%~dp0"

where pwsh >nul 2>nul
if %errorlevel%==0 (
  pwsh -NoLogo -ExecutionPolicy Bypass -File "%~dp0scripts\publish-admin-gui.ps1" %*
  exit /b %errorlevel%
)

powershell -NoLogo -ExecutionPolicy Bypass -File "%~dp0scripts\publish-admin-gui.ps1" %*
exit /b %errorlevel%
