@echo off
rem Keep It Up To Dater - open the logs and show the latest run summaries.

set "SYSLOG=%ProgramData%\KeepItUpToDater\system.log"
set "USRLOG=%LOCALAPPDATA%\KeepItUpToDater\user.log"

if exist "%SYSLOG%" (start "" "%SystemRoot%\System32\notepad.exe" "%SYSLOG%") else (echo No SYSTEM log yet: %SYSLOG%)
if exist "%USRLOG%" (start "" "%SystemRoot%\System32\notepad.exe" "%USRLOG%") else (echo No user log yet: %USRLOG%)
echo.
echo Latest run summaries from the Application event log:
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -Command "try { Get-WinEvent -FilterHashtable @{LogName='Application'; ProviderName='KeepItUpToDater'} -MaxEvents 10 -ErrorAction Stop | Format-Table TimeCreated, Id, LevelDisplayName, Message -AutoSize -Wrap } catch { 'No events yet.' }"
echo.
pause
