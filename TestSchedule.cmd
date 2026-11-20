@echo off
rem Keep It Up To Dater - test the scheduling.
rem Right-click this file and choose "Run as administrator".
rem Installs (or reinstalls) the tool and lets Task Scheduler start the tasks by itself in
rem 5 minutes, once: the System task, and the User task when it is on. That run ignores the
rem once-per-week rule. With "ShowResults": true in config.json the signed-in user gets the
rem start message and the result message. Another number of minutes:
rem   TestSchedule.cmd 10

rem 1.5.0: Windows tools by full path, never from the current folder or the search path
"%SystemRoot%\System32\net.exe" session >nul 2>&1
if errorlevel 1 (
    echo This needs administrator rights.
    echo Right-click TestSchedule.cmd and choose "Run as administrator".
    echo.
    pause
    exit /b 1
)

set "MIN=%~1"
if "%MIN%"=="" set "MIN=5"
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File "%~dp0Install-KeepItUpToDater.ps1" -TestSchedule %MIN%
set "RC=%errorlevel%"
echo.
if "%RC%"=="0" (
    echo Done. The tasks start by themselves in %MIN% minutes. Afterwards, run Status.cmd as
    echo administrator: the last run of the System task shows the test time, and system.log
    echo names who got the messages.
) else (
    echo Install failed with exit code %RC%. See %ProgramData%\KeepItUpToDater\install.log
)
echo.
pause
exit /b %RC%
