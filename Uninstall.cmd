@echo off
rem Keep It Up To Dater - remove from this device.
rem Right-click this file and choose "Run as administrator". Logs and local-config.json are kept.

rem 1.5.0: Windows tools by full path, never from the current folder or the search path
"%SystemRoot%\System32\net.exe" session >nul 2>&1
if errorlevel 1 (
    echo This needs administrator rights.
    echo Right-click Uninstall.cmd and choose "Run as administrator".
    echo.
    pause
    exit /b 1
)

"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File "%~dp0Install-KeepItUpToDater.ps1" -Uninstall
set "RC=%errorlevel%"
echo.
if "%RC%"=="0" (
    echo Removed. Logs are still in %ProgramData%\KeepItUpToDater and %LOCALAPPDATA%\KeepItUpToDater
    if exist "%ProgramData%\KeepItUpToDater\local-config.json" echo Exclusions for this computer ^(local-config.json^) are kept and apply again after a new install.
) else (
    echo Uninstall failed with exit code %RC%.
)
echo.
pause
exit /b %RC%
