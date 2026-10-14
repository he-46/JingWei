@echo off
setlocal
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\run.ps1" -Mode Editor %*
set "result=%errorlevel%"
if not "%result%"=="0" pause
exit /b %result%
