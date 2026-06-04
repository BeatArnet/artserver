@echo off
setlocal
cd /d "%~dp0"

echo Baue die Website...
python scripts\build.py
if errorlevel 1 (
  echo.
  echo Der Build ist fehlgeschlagen.
  pause
  exit /b 1
)

echo.
echo Starte die Website unter http://127.0.0.1:18005/
start "" "http://127.0.0.1:18005/"
python -m http.server 18005 --directory dist
