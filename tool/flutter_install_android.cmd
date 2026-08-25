@echo off
REM Bypass PowerShell execution policy for local Mevora tooling.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0flutter_install_android.ps1" %*
exit /b %ERRORLEVEL%
