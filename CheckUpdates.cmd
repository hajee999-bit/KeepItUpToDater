@echo off
rem Keep It Up To Dater - lists the apps with an update available. Changes no apps.
rem If winget reports 0x8A15000F (catalogue missing or damaged) it repairs the catalogue first:
rem   step 1: winget source update (as administrator also: winget source reset --force)
rem   step 2: install the catalogue package Microsoft.Winget.Source directly (no admin rights needed)
rem Start it normally, as the signed-in user. The catalogue is per user account: "Run as
rem administrator" with another admin account repairs that account, not the signed-in user.
setlocal
rem 1.5.0: Windows tools by full path; winget from this user's own App Installer alias
set "PS=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
set "WINGET=%LOCALAPPDATA%\Microsoft\WindowsApps\winget.exe"
set "SOURCE_MISSING=-1978335217"
set "SOURCE_URL=https://cdn.winget.microsoft.com/cache/source2.msix"
echo Apps with an update available on this device:
echo.
call :list
if "%RC%"=="%SOURCE_MISSING%" goto repair
goto end

:repair
echo.
echo winget's catalogue is missing or damaged (0x8A15000F).
echo Repair step 1: refresh the sources...
"%SystemRoot%\System32\net.exe" session >nul 2>&1
if not errorlevel 1 "%WINGET%" source reset --force --disable-interactivity
"%WINGET%" source update --disable-interactivity
echo.
echo Checking again:
echo.
call :list
if not "%RC%"=="%SOURCE_MISSING%" goto end
echo.
echo Repair step 2: install the catalogue package directly...
"%PS%" -NoProfile -ExecutionPolicy Bypass -Command "$ProgressPreference='SilentlyContinue'; $f=Join-Path $env:TEMP 'KeepItUpToDater-source2.msix'; try { [Net.ServicePointManager]::SecurityProtocol=[Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12; Invoke-WebRequest -Uri $env:SOURCE_URL -OutFile $f -UseBasicParsing -ErrorAction Stop; Add-AppxPackage -Path $f -ErrorAction Stop; 'Catalogue package installed.' } catch { 'Could not install the catalogue package: ' + $_.Exception.Message } finally { Remove-Item $f -ErrorAction SilentlyContinue }"
echo.
echo Checking again:
echo.
call :list
if not "%RC%"=="%SOURCE_MISSING%" goto end
echo.
echo Still missing. Details for IT:
"%PS%" -NoProfile -ExecutionPolicy Bypass -Command "try { $r=Invoke-WebRequest -Uri $env:SOURCE_URL -Method Head -UseBasicParsing -TimeoutSec 60 -ErrorAction Stop; 'Download location reachable (HTTP ' + [int]$r.StatusCode + ').' } catch { $p=$_.Exception.Response; if ($p -and [int]$p.StatusCode -eq 407) { 'Download location NOT reachable: the proxy requires authentication (HTTP 407).' } elseif ($p) { 'Download location reachable (HTTP ' + [int]$p.StatusCode + ').' } else { 'Download location NOT reachable: ' + $_.Exception.Message } }; $d=Join-Path $env:LOCALAPPDATA 'Packages\Microsoft.DesktopAppInstaller_8wekyb3d8bbwe\LocalState\DiagOutputDir'; Get-ChildItem $d -Filter 'WinGet-*.log' -ErrorAction SilentlyContinue | Sort-Object LastWriteTime | Select-Object -Last 6 | Select-String -Pattern '<E>' -SimpleMatch | Select-Object -Last 5 | ForEach-Object { 'winget log: ' + $_.Line.Trim() }"
echo.
echo Started with "Run as administrator"? Start it again normally, as the signed-in user.
echo Otherwise send a screenshot of this window to IT (manual chapter 11).
goto end

:list
if not exist "%WINGET%" (
    echo winget is not available for this user. App Installer may still need to be registered.
    set "RC=9009"
    exit /b 0
)
"%WINGET%" upgrade --source winget --include-pinned --accept-source-agreements --disable-interactivity
set "RC=%errorlevel%"
if "%RC%"=="9009" echo winget is not available for this user. App Installer may still need to be registered.
exit /b 0

:end
echo.
pause
