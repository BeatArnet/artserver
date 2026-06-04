@echo off
setlocal
cd /d "%~dp0"

call "%~dp0scripts\start-admin-gui-local.cmd" %*
exit /b %errorlevel%
