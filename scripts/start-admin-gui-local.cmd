@echo off
setlocal

set "SCRIPT_DIR=%~dp0"
for %%I in ("%SCRIPT_DIR%..") do set "APP_DIR=%%~fI"
set "PYTHON_EXE=C:\Users\beata\AppData\Local\Programs\Python\Python312\python.exe"
set "APP_URL=http://127.0.0.1:18110/"

powershell -NoLogo -NoProfile -ExecutionPolicy Bypass -Command ^
  "$ErrorActionPreference = 'Stop';" ^
  "$appDir = '%APP_DIR%';" ^
  "$python = '%PYTHON_EXE%';" ^
  "$url = '%APP_URL%';" ^
  "$logDir = Join-Path $appDir 'logs\admin';" ^
  "New-Item -ItemType Directory -Force -Path $logDir | Out-Null;" ^
  "$listener = Get-NetTCPConnection -LocalAddress 127.0.0.1 -LocalPort 18110 -State Listen -ErrorAction SilentlyContinue;" ^
  "if (-not $listener) {" ^
  "  Start-Process -FilePath $python -ArgumentList @('admin-gui\app.py','--host','127.0.0.1','--port','18110') -WorkingDirectory $appDir -WindowStyle Hidden -RedirectStandardOutput (Join-Path $logDir 'local-dashboard.out.log') -RedirectStandardError (Join-Path $logDir 'local-dashboard.err.log');" ^
  "}" ^
  "for ($i = 0; $i -lt 30; $i++) {" ^
  "  $listener = Get-NetTCPConnection -LocalAddress 127.0.0.1 -LocalPort 18110 -State Listen -ErrorAction SilentlyContinue;" ^
  "  if ($listener) { break }" ^
  "  Start-Sleep -Milliseconds 250;" ^
  "}" ^
  "Start-Process $url;"

if errorlevel 1 (
  echo.
  echo Lokales Arkons Admin Dashboard konnte nicht gestartet werden.
  echo Details stehen hier:
  echo %APP_DIR%\logs\admin\local-dashboard.err.log
  echo.
  pause
)
