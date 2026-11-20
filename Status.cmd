@echo off
rem Keep It Up To Dater - status of the tool and its two scheduled tasks.
rem Changes nothing. Works where Group Policy blocks the Task Scheduler console.
rem Right-click > Run as administrator to also see the System task.
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File "%~dp0Install-KeepItUpToDater.ps1" -Status
echo.
pause
