@echo off
rem porthole first-logon provisioning entry point.
rem dockur copies /oem into C:\OEM and runs this file once, after the
rem unattended Windows installation reaches its first desktop.
setlocal EnableExtensions
set "OEMDIR=%~dp0"
set "LOG=%OEMDIR%porthole.log"

echo ================================================== >> "%LOG%"
echo [%DATE% %TIME%] porthole provisioning start >> "%LOG%"
echo porthole: provisioning started

call :run_step "%OEMDIR%10-rdp.ps1"
if errorlevel 1 goto :failed

call :run_step "%OEMDIR%20-desktop.ps1"
if errorlevel 1 goto :failed

call :run_step "%OEMDIR%30-app.ps1"
if errorlevel 1 goto :failed

echo [%DATE% %TIME%] porthole provisioning complete >> "%LOG%"
echo porthole: provisioning complete
exit /b 0

:failed
echo [%DATE% %TIME%] porthole provisioning FAILED >> "%LOG%"
echo porthole: provisioning failed - see C:\OEM\porthole.log
exit /b 1

:run_step
echo [%DATE% %TIME%] running %~nx1 >> "%LOG%"
echo porthole: running %~nx1
powershell -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "%~1" >> "%LOG%" 2>&1
exit /b %ERRORLEVEL%
