@echo off
setlocal

set "SCRIPT_DIR=%~dp0"
for %%I in ("%SCRIPT_DIR%..") do set "APP_DIR=%%~fI"
set "PYTHON_EXE=C:\Users\beata\AppData\Local\Programs\Python\Python312\python.exe"

powershell -NoLogo -NoProfile -ExecutionPolicy Bypass -Command ^
  "$ErrorActionPreference = 'Stop';" ^
  "$appDir = '%APP_DIR%';" ^
  "$python = '%PYTHON_EXE%';" ^
  "$logDir = Join-Path $appDir 'logs\admin';" ^
  "New-Item -ItemType Directory -Force -Path $logDir | Out-Null;" ^
  "$port = $null;" ^
  "foreach ($candidate in 18110..18120) {" ^
  "  $listener = Get-NetTCPConnection -LocalAddress 127.0.0.1 -LocalPort $candidate -State Listen -ErrorAction SilentlyContinue;" ^
  "  if ($listener) { $port = $candidate; break }" ^
  "}" ^
  "$started = $false;" ^
  "if (-not $port) {" ^
  "  foreach ($candidate in 18110..18120) {" ^
  "    $listener = Get-NetTCPConnection -LocalAddress 127.0.0.1 -LocalPort $candidate -State Listen -ErrorAction SilentlyContinue;" ^
  "    if (-not $listener) { $port = $candidate; break }" ^
  "  }" ^
  "  if (-not $port) { throw 'Kein freier Port zwischen 18110 und 18120 gefunden.' }" ^
  "  Start-Process -FilePath $python -ArgumentList @('admin-gui\app.py','--host','127.0.0.1','--port',[string]$port) -WorkingDirectory $appDir -WindowStyle Hidden -RedirectStandardOutput (Join-Path $logDir 'local-dashboard.out.log') -RedirectStandardError (Join-Path $logDir 'local-dashboard.err.log');" ^
  "  $started = $true;" ^
  "}" ^
  "if ($started) {" ^
  "  for ($i = 0; $i -lt 40; $i++) {" ^
  "    $listener = Get-NetTCPConnection -LocalAddress 127.0.0.1 -LocalPort $port -State Listen -ErrorAction SilentlyContinue;" ^
  "    if ($listener) { break }" ^
  "    Start-Sleep -Milliseconds 250;" ^
  "  }" ^
  "}" ^
  "$url = 'http://127.0.0.1:' + $port + '/';" ^
  "Write-Host ('Admin-GUI lokal: ' + $url);" ^
  "Start-Process $url;"

if errorlevel 1 (
  echo.
  echo Lokales Arkons Admin Dashboard konnte nicht gestartet werden.
  echo Details stehen hier:
  echo %APP_DIR%\logs\admin\local-dashboard.err.log
  echo.
  pause
)
