@echo off
rem Keep It Up To Dater - installer.
rem Right-click this file and choose "Run as administrator".
rem Apps that must never be updated go in config.json in this folder.
rem Extra options can be added after the file name, for example:
rem   Install.cmd -DayOfWeek Tuesday -Time 10:00

rem 1.5.0: Windows tools by full path, never from the current folder or the search path
"%SystemRoot%\System32\net.exe" session >nul 2>&1
if errorlevel 1 (
    echo This needs administrator rights.
    echo Right-click Install.cmd and choose "Run as administrator".
    echo.
    pause
    exit /b 1
)

"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File "%~dp0Install-KeepItUpToDater.ps1" -RunNow %*
set "RC=%errorlevel%"
echo.
if "%RC%"=="0" (
    echo Done. The first SYSTEM update run has started. Use ShowLogs.cmd to follow it.
) else (
    echo Install failed with exit code %RC%. See %ProgramData%\KeepItUpToDater\install.log
)
echo.
pause
exit /b %RC%
