#Requires -Version 5.1
<#
.SYNOPSIS
    Keep It Up To Dater: weekly unattended app updates with winget, for devices
    where users are not local admins.

.DESCRIPTION
    Uses only built-in Windows components: Windows PowerShell 5.1, Task Scheduler and winget
    (App Installer, included in Windows 10 1809+ and Windows 11). Nothing is downloaded or
    installed apart from the updater script itself and, only when it is missing or too old, the
    Microsoft Visual C++ v14 runtime that winget needs to run as SYSTEM (see -NoVCRuntime).

    Deploy with a GPO computer startup script (runs as SYSTEM at every boot, re-running is
    harmless), or run once as administrator. It creates two scheduled tasks in the
    \KeepItUpToDater\ folder of Task Scheduler:

      System  Runs as SYSTEM and updates apps installed for all users (winget --scope machine).
              Users need no admin rights and get no UAC prompts.
      User    Runs as each signed-in user, without elevation, and updates apps installed in
              that user's own profile (winget --scope user), for example VS Code (User).

    Both tasks run weekly and also at startup / logon. Each task runs once per week: a start is
    skipped when a run already finished in the current week, which begins two days before the
    scheduled day and time. Devices that were off at the scheduled time still update once a week,
    without updating on every boot.

    Exclusions: list the winget IDs that must never be updated in config.json next to this
    installer (for a GPO rollout: in the NETLOGON folder). The installer checks that file and
    copies the list on every run, so computers pick up a change at their next restart.
    Exclusions for one computer only: list them per computer name under ComputerExcludeIds in
    the same config.json, or add them on that computer with -AddLocalExclusion.

    Silent by default. With -ShowResults, or "ShowResults": true in config.json, the signed-in
    users get a Windows message when updating starts and, when it is done, which apps were
    updated and which could not be updated. The SYSTEM task shows these messages itself, so they
    also work where AppLocker blocks PowerShell for users.

    Where AppLocker (or another policy) blocks PowerShell for standard users, the User task cannot
    run: turn it off with "UserTask": false in config.json or -NoUserTask. Status.cmd shows such
    blocks.

    Files and logs:
      C:\Program Files\KeepItUpToDater\Invoke-KeepItUpToDater.ps1   updater (only admins can change it)
      C:\Program Files\KeepItUpToDater\config.json               settings written by the installer (only admins can change it)
      C:\ProgramData\KeepItUpToDater\system.log                  SYSTEM task log
      C:\ProgramData\KeepItUpToDater\install.log                 installer transcript
      C:\ProgramData\KeepItUpToDater\local-config.json           exclusions for this computer only (-AddLocalExclusion)
      %LOCALAPPDATA%\KeepItUpToDater\user.log                    per-user task log
      Application event log, source "KeepItUpToDater"            one summary event per run

.PARAMETER DayOfWeek
    Day of the weekly run. Default Wednesday.

.PARAMETER Time
    Local start time of the weekly run, HH:mm. Default 12:00.

.PARAMETER RandomDelayMinutes
    Random start delay so devices don't all download at the same moment. Default 60, 0 disables.

.PARAMETER MinIntervalDays
    Extra minimum number of days between two runs, on top of the once-per-week rule, for a slower
    cadence (13 gives about one run every two weeks). Default 0: off.

.PARAMETER InstallTimeoutMinutes
    When winget logs nothing for this many minutes while an installer it started is running, the
    updater stops that installer. winget then reports that app as failed and continues with the
    next one, and the run summary names the app. Default 60, 0 turns it off. Some installers run
    long without any output (Visual Studio Build Tools: 15 minutes on a test device), so keep it
    at 30 or more.

.PARAMETER ConfigFile
    Config file with the exclusions for all computers (ExcludeIds), optional exclusions per computer
    name (ComputerExcludeIds, for example "ComputerExcludeIds": { "PC024": [ "Mobatek.MobaXterm" ] })
    and optional replace rules (Replace), for example
    "Replace": { "OpenJS.NodeJS.*": "OpenJS.NodeJS.LTS" } moves every end-of-life Node.js major
    (a package of its own in winget, which winget never moves to a newer major) to the current LTS.
    Replacing is done by the System task, for machine-wide apps. Default: config.json next to this installer.
    A name without a folder is looked up next to this installer, so an OU with its own list can
    use for example -ConfigFile config-finance.json. When the file is on a network path (NETLOGON),
    both scheduled tasks read it again at every run, so a changed list needs no restart. When the default config.json is missing, the
    exclusions already installed on the computer are kept. A missing -ConfigFile file, invalid
    JSON, an invalid ID or an invalid computer name stops the installer with exit code 2 before
    anything is changed.

.PARAMETER IncludeUnknown
    Also upgrade packages whose installed version winget cannot determine. Off by default,
    because those packages can end up being reinstalled on every run.

.PARAMETER NoUserTask
    Install only the SYSTEM task (machine-wide apps), and no User task. Same as "UserTask": false
    in config.json. Use it where AppLocker or another policy blocks PowerShell for standard users:
    the User task runs PowerShell as the signed-in user and cannot start there.

.PARAMETER NoVCRuntime
    Do not let the SYSTEM task install the Microsoft Visual C++ v14 runtime when it is missing.
    By default it downloads https://aka.ms/vc14/vc_redist.x64.exe, checks the Microsoft
    signature and installs it silently, because winget cannot start as SYSTEM without it.
    Use this switch when the runtime is deployed by other tooling.

.PARAMETER RunNow
    Start the SYSTEM task right after installing. That run ignores the once-per-week rule and
    MinIntervalDays, so it also runs when the last run was recent.

.PARAMETER ShowResults
    Show the signed-in users a Windows message when the first app starts updating, and one when the
    run is done (updated, could not be updated, restart needed). Without it the tool stays silent,
    unless config.json says "ShowResults": true, or lists this computer: "ShowResults": [ "PC024" ].
    A config.json on NETLOGON is read at every run, so the messages can be turned on or off
    centrally. The SYSTEM task shows the messages itself (Windows message service, as msg.exe), so
    nothing runs in the user's account; who signs in later gets the last result at sign-in, within
    12 hours (Notify task).

.PARAMETER TestSchedule
    Test the scheduling: both tasks start by themselves through Task Scheduler this many minutes
    after installing (1 to 1440), once, and that run ignores the once-per-week rule. Do not combine
    with -RunNow: a run that is still busy makes Task Scheduler skip the test start. TestSchedule.cmd
    uses 5 minutes. The next install (at the next startup with a GPO) removes the test trigger.

.PARAMETER AddLocalExclusion
    Exclude one or more winget IDs on this computer only, on top of the exclusions in config.json
    (separate several IDs with commas). For computers managed from NETLOGON, ComputerExcludeIds in
    config.json does the same centrally. Stored in C:\ProgramData\KeepItUpToDater\local-config.json,
    which only administrators can change. Both tasks use the list from their next run; nothing is
    reinstalled. The file is kept when the tool is installed again or removed.

.PARAMETER RemoveLocalExclusion
    Remove one or more winget IDs from this computer's local exclusions. An exclusion in
    config.json (ExcludeIds or ComputerExcludeIds) cannot be lifted this way.

.PARAMETER Uninstall
    Remove the tasks, program folder and event source. Logs are kept.

.PARAMETER Status
    Show whether the tool is installed, the state and last result of both tasks, the exclusions
    and the end of each log, then stop. Changes nothing and works without the Task Scheduler
    console (which Group Policy can block). Without admin rights the System task is not visible.
    Status.cmd runs this.

.PARAMETER ExportRunner
    Write Invoke-KeepItUpToDater.ps1 to this folder, then stop. Needs no admin
    rights. Use it for code signing: put the signed Invoke-KeepItUpToDater.ps1 next to this
    installer and it is deployed instead of the built-in copy.

.EXAMPLE
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Install-KeepItUpToDater.ps1

.EXAMPLE
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Install-KeepItUpToDater.ps1 -DayOfWeek Tuesday -Time 10:00

.EXAMPLE
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Install-KeepItUpToDater.ps1 -ConfigFile config-finance.json

.EXAMPLE
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Install-KeepItUpToDater.ps1 -AddLocalExclusion Oracle.VirtualBox

.EXAMPLE
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Install-KeepItUpToDater.ps1 -Uninstall

.NOTES
    Version   1.4.4
    Exit codes (installer): 0 OK, 1 not elevated, 2 install failed or config file missing/invalid.
    Scheduled tasks:        System, User (not with -NoUserTask or "UserTask": false), and Notify
                            (as SYSTEM at each sign-in: shows the last result of the System task
                            to who signs in; only does something with ShowResults on).
    Event IDs (updater):    1000 run OK, 1001 run finished with failed packages, an unexpected
                            winget result or after a previous run that did not finish, 1002 run
                            could not start (winget missing/broken, its
                            catalogue was damaged and could not be repaired, or local-config.json
                            is invalid).
    Installed when:         file "C:\Program Files\KeepItUpToDater\Invoke-KeepItUpToDater.ps1" exists.
    GPO rollout:            see Deployment-Commands.txt.
    Check a device by hand (no admin needed, changes nothing):
      powershell -ExecutionPolicy Bypass -File "C:\Program Files\KeepItUpToDater\Invoke-KeepItUpToDater.ps1" -Mode User -ListOnly
#>
[CmdletBinding()]
param(
    [ValidateSet('Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday')]
    [string]$DayOfWeek = 'Wednesday',

    [ValidatePattern('^([01]\d|2[0-3]):[0-5]\d$')]
    [string]$Time = '12:00',

    [ValidateRange(0, 720)]
    [int]$RandomDelayMinutes = 60,

    [ValidateRange(0, 30)]
    [int]$MinIntervalDays = 0,

    [ValidateRange(0, 120)]
    [int]$InstallTimeoutMinutes = 60,

    [string]$ConfigFile,

    [switch]$IncludeUnknown,
    [switch]$NoUserTask,
    [switch]$NoVCRuntime,
    [switch]$RunNow,
    [switch]$ShowResults,
    [ValidateRange(0, 1440)]
    [int]$TestSchedule = 0,
    [string[]]$AddLocalExclusion,
    [string[]]$RemoveLocalExclusion,
    [switch]$Uninstall,
    [string]$ExportRunner,
    [switch]$Status
)

$ErrorActionPreference = 'Stop'
$ToolVersion  = '1.4.4'
$Name         = 'KeepItUpToDater'
$DisplayName  = 'Keep It Up To Dater'
$Organization = 'contoso.local'
$RunnerName  = 'Invoke-KeepItUpToDater.ps1'
$TaskPath    = "\$Name\"
# 64-bit Program Files, also when started from a 32-bit host (some deployment tools do that)
$ProgramFilesDir = if ($env:ProgramW6432) { $env:ProgramW6432 } else { $env:ProgramFiles }
$InstallDir  = Join-Path $ProgramFilesDir $Name
$DataDir     = Join-Path $env:ProgramData $Name

$ExcludeIds  = @()   # filled from the config file by Read-Exclusions
# winget package ID format (Publisher.Package, 2 to 8 parts); commas and semicolons are not allowed
$IdRegex = '^[^.\s\\/:*?"<>|,;\x01-\x1f]{1,32}(\.[^.\s\\/:*?"<>|,;\x01-\x1f]{1,32}){1,7}$'
# Computer name as %COMPUTERNAME% shows it (NetBIOS name, at most 15 characters)
$NameRegex = '^[A-Za-z0-9][A-Za-z0-9_-]{0,14}$'
$ReplaceRules = [ordered]@{}   # "From" = "To" package IDs, filled by Read-Exclusions
$ComputerExcludeIds = [ordered]@{}   # "COMPUTER" = winget IDs for that computer only, filled by Read-Exclusions
$ExclusionsSource = ''   # network path the scheduled tasks re-read at every run (NETLOGON)
$ShowResultsCfg = $null   # "ShowResults" from config.json: true, false or a list of computer names
$UserTaskCfg = $null      # "UserTask" from config.json: true or false (false: no User task)

#region Updater (written to Program Files, started by the scheduled tasks)
$RunnerCode = @'
<#
    Invoke-KeepItUpToDater.ps1 - part of Keep It Up To Dater.
    Started by the scheduled tasks in \KeepItUpToDater\. Settings: config.json in this folder.
    Exclusions for this computer only: ComputerExcludeIds in config.json, and
    C:\ProgramData\KeepItUpToDater\local-config.json.

    -Mode System    machine-wide apps, must run as SYSTEM (scheduled task)
    -Mode User      apps in the current user's profile, no admin rights needed
    -ListOnly       show available updates and change nothing
    -Force          run even when this week's run already finished (and ignore MinIntervalDays)
    -Mode Notify    message to the signed-in users about the last System run (-For System, the
                    Notify task at sign-in) or about this user's run (-For User); changes nothing else
#>
[CmdletBinding()]
param(
    [ValidateSet('System', 'User', 'Notify')]
    [string]$Mode = 'User',
    [ValidateSet('System', 'User')]
    [string]$For = 'System',
    [switch]$Force,
    [switch]$ListOnly
)

$ErrorActionPreference = 'Continue'
$Name = 'KeepItUpToDater'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
try { [Console]::OutputEncoding = [Text.Encoding]::UTF8 } catch { }

# Settings
$cfg = $null
$cfgFile = Join-Path $here 'config.json'
if (Test-Path $cfgFile) { try { $cfg = Get-Content $cfgFile -Raw | ConvertFrom-Json } catch { } }
$excludeIds      = @($cfg.ExcludeIds | Where-Object { $_ })
$includeUnknown  = [bool]$cfg.IncludeUnknown
$installVCRuntime = if ($null -eq $cfg.InstallVCRuntime) { $true } else { [bool]$cfg.InstallVCRuntime }
$minIntervalDays = if ($null -ne $cfg.MinIntervalDays) { [int]$cfg.MinIntervalDays } else { 0 }
$scheduleDay     = "$($cfg.ScheduleDay)"    # day and time of the weekly run, written by the installer
$scheduleTime    = "$($cfg.ScheduleTime)"
$installTimeoutMinutes = if ($null -ne $cfg.InstallTimeoutMinutes) { [double]$cfg.InstallTimeoutMinutes } else { 60 }
$inv = [Globalization.CultureInfo]::InvariantCulture
# Result messages: the installer's -ShowResults, or "ShowResults" in config.json (true, false, or
# a list of computer names). Silent by default.
function Get-ShowResults($Value) {
    if ($null -eq $Value) { return @{ On = $false; Problem = $null } }
    if ($Value -is [bool]) { return @{ On = $Value; Problem = $null } }
    $names = @(@($Value) | ForEach-Object { "$_".Trim() } | Where-Object { $_ })
    if (($Value -isnot [array]) -or @($names | Where-Object { $_ -notmatch '^[A-Za-z0-9][A-Za-z0-9_-]{0,14}$' }).Count) {
        return @{ On = $false; Problem = 'ShowResults must be true, false or a list of computer names' }
    }
    return @{ On = (@($names | Where-Object { $_ -eq $env:COMPUTERNAME }).Count -gt 0); Problem = $null }
}
$showResultsSwitch = [bool]$cfg.ShowResultsSwitch
$sr0 = Get-ShowResults $cfg.ShowResults
$showResults = $showResultsSwitch -or $sr0.On

# Log and state locations
if ($Mode -eq 'System' -or ($Mode -eq 'Notify' -and $For -eq 'System')) { $dataDir = Join-Path $env:ProgramData $Name }
else                    { $dataDir = Join-Path $env:LOCALAPPDATA $Name }
if (-not (Test-Path $dataDir)) { New-Item -ItemType Directory -Path $dataDir -Force | Out-Null }
$log     = Join-Path $dataDir ($Mode.ToLower() + '.log')
$stamp   = Join-Path $dataDir ($Mode.ToLower() + '.lastrun')
$pinFile = Join-Path $dataDir ($Mode.ToLower() + '.pins')
if ((Test-Path $log) -and ((Get-Item $log).Length -gt 1MB)) { Move-Item $log "$log.old" -Force }

function Write-Log([string]$Message) {
    $line = '{0}  {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Message
    $line | Out-File -FilePath $log -Append -Encoding utf8
    Write-Host $line
}
function Write-Summary([int]$Id, [string]$Type, [string]$Message) {
    try { Write-EventLog -LogName Application -Source $Name -EventId $Id -EntryType $Type -Message "[$Mode] $Message" -ErrorAction Stop } catch { }
}

# ---- Result messages (ShowResults). The runs write <mode>.status.json and show the signed-in
# users a Windows message box: a short notice when the first app starts updating, and the result
# when the run is done. The System run uses Windows' own message service (WTSSendMessage, as
# msg.exe does), so nothing is started in the user's account: policies that block PowerShell or
# scripts for users (AppLocker) do not matter, and the box only has an OK button.
$sysDir   = Join-Path $env:ProgramData $Name
$sentFile = Join-Path $sysDir 'notify.sent'   # which users got which message of the last System run
function Get-RunMessage([string]$Kind, $St, [string]$For) {
    $time = { param($v) $s = ''; try { $s = ([datetime]::Parse("$v", $inv)).ToString('HH:mm') } catch { }; $s }
    $logFile = if ($For -eq 'System') { Join-Path $sysDir 'system.log' } else { Join-Path (Join-Path $env:LOCALAPPDATA $Name) 'user.log' }
    if ($Kind -eq 'start') {
        $n = [int]$St.Total
        $count = if ($n -gt 1) { " ($n apps)" } elseif ($n -eq 1) { ' (1 app)' } else { '' }
        $what = if ($For -eq 'System') { "Updating apps for all users of this PC$count." } else { "Updating your own apps$count." }
        $text = "$what`r`n`r`nYou can keep working. An app can close for a moment while it updates. You get a message here when it is done."
        return @{ Text = $text; Timeout = 300; Icon = 0x40 }
    }
    $who = if ($For -eq 'System') { 'apps for all users of this PC' } else { 'your own apps' }
    # At most 15 names per list, so the message fits on the screen
    $list = { param([string]$Title, $Items) $i = @($Items | Where-Object { $_ }); if (-not $i.Count) { return @() }
              $o = @("${Title} ($($i.Count)):") + @($i | Select-Object -First 15 | ForEach-Object { "    $_" })
              if ($i.Count -gt 15) { $o += "    and $($i.Count - 15) more (see the log)" }; $o }
    $err = "$($St.Error)"
    $upd = @($St.Updated | Where-Object { $_ }); $rep = @($St.Replaced | Where-Object { $_ }); $not = @($St.NotUpdated | Where-Object { $_ })
    $rst = @($St.Restart | Where-Object { $_ }); $reo = @($St.Reopen | Where-Object { $_ })
    $lines = @()
    if ($err) {
        if ($err.Length -gt 300) { $err = $err.Substring(0, 297) + '...' }
        $lines += 'The run stopped before it was done. Nothing is needed from you; IT can see the reason in the log.'; $lines += "Reason: $err"; $lines += ''
    }
    $lines += & $list 'Restart the PC to finish' $rst
    $lines += & $list 'Close the app and start it again to finish' $reo
    if ($not.Count) { $lines += & $list 'Could not be updated' $not; $lines += '    Nothing to do for you; IT can see these in the log.' }
    $lines += & $list 'Updated' $upd
    $lines += & $list 'Replaced by a newer version' $rep
    $quiet = -not $lines.Count
    if ($quiet -and $For -ne 'System') { return $null }   # the User run says nothing when nothing needed an update
    $count = @()
    if ($upd.Count + $rep.Count) { $count += "$($upd.Count + $rep.Count) updated" }
    if ($rst.Count) { $count += "$($rst.Count) need$(if ($rst.Count -eq 1) { 's' }) a restart" }
    if ($not.Count) { $count += "$($not.Count) could not be updated" }
    $head = if ($err) { "Updating $who did not finish." } else { "Updating $who is done." }
    $detail = "Started $(& $time $St.Started), $(if ($err) { 'stopped' } else { 'finished' }) $(& $time $St.Ended)." + $(if ($count.Count) { ' ' + ($count -join ', ') + '.' } else { '' })
    if ($quiet) { $lines = @('All apps are up to date: nothing needed an update. This message closes by itself.') }
    while ($lines.Count -and -not $lines[-1]) { $lines = @($lines | Select-Object -SkipLast 1) }   # no empty line before the log line
    $text = (@($head, $detail, '') + $lines + @('', "Log for IT: $logFile")) -join "`r`n"
    return @{ Text = $text; Timeout = $(if ($quiet) { 60 } else { 0 }); Icon = $(if ($err) { 0x30 } else { 0x40 }) }
}
function Read-RunState([string]$Path) {
    try { return (Get-Content -LiteralPath $Path -Raw -Encoding UTF8 -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop) } catch { return $null }
}
function Get-UserSessions {
    # The User run (and -For User) only reaches its own session. The System run reaches every
    # signed-in user: one explorer.exe per session, which works in any display language.
    if ($Mode -eq 'User' -or $For -eq 'User') {
        return @([pscustomobject]@{ Id = [Diagnostics.Process]::GetCurrentProcess().SessionId; User = "$env:USERDOMAIN\$env:USERNAME" })
    }
    $found = [ordered]@{}
    try {
        foreach ($p in @(Get-Process -Name explorer -IncludeUserName -ErrorAction Stop)) {
            if ($p.SessionId -gt 0 -and $p.UserName -and -not $found.Contains([string]$p.SessionId)) { $found[[string]$p.SessionId] = [pscustomobject]@{ Id = [int]$p.SessionId; User = "$($p.UserName)" } }
        }
    } catch { Write-Log "Signed-in users could not be listed: $($_.Exception.Message)" }
    return @($found.Values)
}
function Send-SessionMessage([int]$SessionId, [string]$Text, [int]$Timeout, [int]$Icon) {
    $title = 'Keep It Up To Dater'
    if ($null -eq $script:wtsApi) {
        $script:wtsApi = $false
        try {
            $script:wtsApi = Add-Type -Namespace KeepItUpToDater -Name Wts -PassThru -ErrorAction Stop -MemberDefinition '[DllImport("wtsapi32.dll", SetLastError = true, CharSet = CharSet.Unicode)] public static extern bool WTSSendMessageW(IntPtr hServer, int SessionId, string pTitle, int TitleLength, string pMessage, int MessageLength, int Style, int Timeout, out int pResponse, bool bWait);'
        } catch { Write-Log "Windows message service not available to this script ($($_.Exception.Message)); using msg.exe." }
    }
    $api = $script:wtsApi
    if ($api) {
        $resp = 0
        # 0x50000: in front and on top. bWait false: returns at once, the box stays by itself.
        if ($api::WTSSendMessageW([IntPtr]::Zero, $SessionId, $title, $title.Length * 2, $Text, $Text.Length * 2, ($Icon -bor 0x50000), $Timeout, [ref]$resp, $false)) { return $true }
        Write-Log "Windows message service: no message in session $SessionId (error $([Runtime.InteropServices.Marshal]::GetLastWin32Error())); trying msg.exe."
    }
    $msgExe = Join-Path $env:WINDIR 'System32\msg.exe'
    if (-not (Test-Path -LiteralPath $msgExe)) { Write-Log 'msg.exe is not on this PC; no message shown.'; return $false }
    $a = @("$SessionId"); if ($Timeout -gt 0) { $a += "/TIME:$Timeout" }
    $out = $Text | & $msgExe @a 2>&1
    if ($LASTEXITCODE -eq 0) { return $true }
    Write-Log "msg.exe: no message in session $SessionId (exit $LASTEXITCODE) $("$out".Trim())"
    return $false
}
function Send-RunMessage([string]$Kind, $St) {
    # Kind: start or end. Each signed-in user gets each message of a run once.
    if (-not $showResults -or $ListOnly) { return }
    if ($Kind -eq 'start') { $script:startSent = $true }
    $target = if ($Mode -eq 'User' -or $For -eq 'User') { 'User' } else { 'System' }
    $m = Get-RunMessage $Kind $St $target
    if (-not $m) { return }
    $label = if ($Kind -eq 'start') { 'Start message' } else { 'Result message' }
    $sessions = @(Get-UserSessions)
    if (-not $sessions.Count) {
        Write-Log ("${label}: nobody is signed in." + $(if ($target -eq 'System') { ' Who signs in within 12 hours gets it then.' } else { '' }))
        return
    }
    $run = "$($St.Run)"
    $sent = @()
    if ($target -eq 'System' -and (Test-Path -LiteralPath $sentFile)) { $sent = @(Get-Content -LiteralPath $sentFile -Encoding UTF8 -ErrorAction SilentlyContinue | Where-Object { "$_".StartsWith("$run|") }) }
    $shown = @(); $failed = @(); $new = @()
    foreach ($u in @($sessions | Group-Object -Property User)) {
        if ($sent -contains "$run|$Kind|$($u.Name)") { continue }
        $ok = $false
        foreach ($s in $u.Group) {
            if (Send-SessionMessage $s.Id $m.Text $m.Timeout $m.Icon) { $ok = $true; $shown += "$($u.Name) (session $($s.Id))" } else { $failed += "$($u.Name) (session $($s.Id))" }
        }
        if ($ok) { $new += "$run|$Kind|$($u.Name)" }
    }
    if ($target -eq 'System' -and $new.Count) {
        try { Set-Content -LiteralPath $sentFile -Value @($sent + $new) -Encoding UTF8 -ErrorAction Stop } catch { }
    }
    if ($shown.Count) { Write-Log "$label shown to $($shown -join ', ')." }
    if ($failed.Count) { Write-Log "$label could not be shown to $($failed -join ', ')." }
}
if ($Mode -eq 'Notify') {
    # Started by the Notify task (as SYSTEM) one minute after each sign-in: a System run that is
    # busy, or that finished less than 12 hours ago, and that this user has not had a message
    # about. -For User does the same for this user's own run. Changes nothing else.
    if (-not $showResults) { exit 0 }
    $statusPath = if ($For -eq 'System') { Join-Path $sysDir 'system.status.json' } else { Join-Path $dataDir 'user.status.json' }
    $markerPath = if ($For -eq 'System') { Join-Path $sysDir 'system.running' } else { Join-Path $dataDir 'user.running' }
    $st = Read-RunState $statusPath
    if (-not $st) { exit 0 }
    $kind = ''
    if ("$($st.Phase)" -eq 'done') {
        $ended = [datetime]::MinValue
        try { $ended = [datetime]::Parse("$($st.Ended)", $inv) } catch { }
        if (((Get-Date) - $ended).TotalHours -le 12) { $kind = 'end' }
    } elseif (Test-Path -LiteralPath $markerPath) {
        # Still busy only when the running marker belongs to this run (a stopped run leaves an old status)
        $mk = @("$(Get-Content -LiteralPath $markerPath -Raw -ErrorAction SilentlyContinue)".Trim() -split '\|')
        if ($mk[0] -eq "$($st.Run)") { $kind = 'start' }
    }
    if ($kind) { Send-RunMessage $kind $st }
    exit 0
}
function Get-WingetPath {
    # Signed-in users have the winget alias. SYSTEM does not, so use the App Installer package folder.
    if ($Mode -eq 'User') {
        $alias = Join-Path $env:LOCALAPPDATA 'Microsoft\WindowsApps\winget.exe'
        if (Test-Path $alias) { return $alias }
    }
    $arch = if ($env:PROCESSOR_ARCHITECTURE -eq 'ARM64') { 'arm64' } else { 'x64' }
    $root = Join-Path $env:ProgramFiles 'WindowsApps'
    $dirs = @(Get-ChildItem -Path $root -Directory -Filter "Microsoft.DesktopAppInstaller_*_$($arch)__8wekyb3d8bbwe" -ErrorAction SilentlyContinue |
        Where-Object { Test-Path (Join-Path $_.FullName 'winget.exe') } |
        Sort-Object { try { [version]($_.Name.Split('_')[1]) } catch { [version]'0.0' } } -Descending)
    if ($dirs.Count -gt 0) { return (Join-Path $dirs[0].FullName 'winget.exe') }
    return $null
}

# The installer's -RunNow leaves this file for one run that ignores the once-per-week rule. It is in the
# data folder of the System task, which only SYSTEM and administrators can change.
$runNowFlag = Join-Path $dataDir 'system.runnow'
$runNowNote = ''
if ($Mode -eq 'System' -and -not $ListOnly -and (Test-Path -LiteralPath $runNowFlag)) {
    Remove-Item -LiteralPath $runNowFlag -Force -ErrorAction SilentlyContinue
    if (-not $Force) { $Force = $true; $runNowNote = 'Started by the installer with -RunNow: runs even if a run already finished this week.' }
}

# The installer's -TestSchedule leaves this file with the time of a one-time start. A run that
# starts within 2 minutes before to 2 hours after it ignores the once-per-week rule, once per task
# (and per user for the User task). The file is in the System task's data folder (admins only).
$testFlag = Join-Path (Join-Path $env:ProgramData $Name) 'testrun'
$testNote = ''
if (-not $ListOnly -and (Test-Path -LiteralPath $testFlag)) {
    try {
        $tAt = [datetime]::Parse("$(Get-Content -LiteralPath $testFlag -Raw)".Trim(), $inv)
        $tNow = Get-Date
        $tDone = Join-Path $dataDir ($Mode.ToLower() + '.testrun')
        $tPrev = if (Test-Path -LiteralPath $tDone) { "$(Get-Content -LiteralPath $tDone -Raw)".Trim() } else { '' }
        if ($tNow -ge $tAt.AddMinutes(-2) -and $tNow -le $tAt.AddHours(2) -and $tPrev -ne $tAt.ToString('o')) {
            $tAt.ToString('o') | Set-Content -LiteralPath $tDone -Encoding ascii
            if (-not $Force) { $Force = $true; $testNote = "Started by the test schedule ($($tAt.ToString('yyyy-MM-dd HH:mm'))): runs even if a run already finished this week." }
        }
    } catch { }
}

# One run per week. The week begins two days before the scheduled day and time, so:
# - the weekly start runs, unless a run finished in the two days before it (a manual run on the
#   Monday or Tuesday before a Wednesday schedule counts for that week);
# - a catch-up run later in the week (device off on the scheduled day) never makes next week's
#   weekly start skip;
# - startup and logon starts are skipped once this week's run has finished.
function Get-RunWeek([datetime]$Now) {
    try {
        $day = [DayOfWeek]$scheduleDay
        $at  = [datetime]::ParseExact($scheduleTime, 'HH:mm', $inv)
    } catch { return $null }
    $slot = $Now.Date.AddHours($at.Hour).AddMinutes($at.Minute)
    while ($slot.DayOfWeek -ne $day -or $slot -gt $Now) { $slot = $slot.AddDays(-1) }
    return @{ Start = $slot.AddDays(-2); Next = $slot.AddDays(7) }
}
if (-not $Force -and -not $ListOnly -and (Test-Path $stamp)) {
    try {
        $last = [datetime]::Parse((Get-Content $stamp -Raw).Trim(), $inv)
        $now  = Get-Date
        $lastText = $last.ToString('yyyy-MM-dd HH:mm')
        $skip = ''
        if ($last -gt $now.AddHours(1)) {
            Write-Log "The last completed run time ($lastText) is in the future, so the clock was changed; it is ignored."
        } else {
            $week = Get-RunWeek $now
            if ($week) {
                if ($last -ge $week.Start) {
                    $skip = "this week's run already finished on $lastText (the week began $($week.Start.ToString('ddd yyyy-MM-dd HH:mm', $inv))). Next weekly start: $($week.Next.ToString('ddd yyyy-MM-dd HH:mm', $inv))"
                }
            } elseif (($now - $last).TotalDays -lt 6) {
                $skip = "the last completed run was $lastText, less than 6 days ago (config.json has no schedule)"
            }
            if (-not $skip -and $minIntervalDays -gt 0 -and ($now - $last).TotalDays -lt $minIntervalDays) {
                $skip = "the last completed run was $lastText, less than $minIntervalDays days ago (MinIntervalDays)"
            }
        }
        if ($skip) {
            Write-Log "Start skipped: $skip. To run anyway, delete $stamp or start the updater with -Force."
            exit 0
        }
    } catch { }
}

# <mode>.running exists while a run is busy. A run stopped before its summary (by the task's 3-hour
# limit, a restart or a shutdown) leaves the file behind, and the next run reports it.
$runMarker = $null
$unfinishedNote = ''
if (-not $ListOnly) {
    $runMarker = Join-Path $dataDir ($Mode.ToLower() + '.running')
    if (Test-Path -LiteralPath $runMarker) {
        $prev = @("$(Get-Content -LiteralPath $runMarker -Raw -ErrorAction SilentlyContinue)".Trim() -split '\|')
        $prevStart = $null
        try { $prevStart = [datetime]::Parse($prev[0], $inv) } catch { }
        $prevPid = 0
        if ($prev.Count -ge 2) { [void][int]::TryParse($prev[1], [ref]$prevPid) }
        $prevPkg = if ($prev.Count -ge 3) { $prev[2].Trim() } else { '' }
        $prevBusy = $false
        if ($prevStart -and $prevPid -and $prevPid -ne $PID) {
            # Same process ID and started before that run: still the same run (IDs are reused after a restart)
            $proc = Get-Process -Id $prevPid -ErrorAction SilentlyContinue
            if ($proc) { try { $prevBusy = ($proc.StartTime -le $prevStart) } catch { } }
        }
        $prevWhen = if ($prevStart) { $prevStart.ToString('yyyy-MM-dd HH:mm') } else { 'at an unknown time' }
        if ($prevBusy) {
            Write-Log "Start skipped: the run started $prevWhen (process $prevPid) is still busy."
            exit 0
        }
        $unfinishedNote = "The previous run, started $prevWhen, did not finish" + $(if ($prevPkg) { " (it was busy with $prevPkg)" } else { '' }) + ': it was stopped by the task''s 3-hour limit, a restart or a shutdown.'
    }
}

Write-Log "===== $Mode run started (Keep It Up To Dater $($cfg.Version), account $env:USERNAME) ====="
if ($runNowNote) { Write-Log $runNowNote }
if ($testNote) { Write-Log $testNote }
$runStart = Get-Date
if ($unfinishedNote) { Write-Log "WARNING: $unfinishedNote" }
if ($sr0.Problem) { Write-Log "WARNING: installed config.json: $($sr0.Problem); no result messages from it." }
function Set-RunMarker([string]$Package) {
    if ($runMarker) { try { "$($runStart.ToString('o'))|$PID|$Package" | Set-Content -LiteralPath $runMarker -Encoding ascii -ErrorAction Stop } catch { } }
}
# State for the result messages, only written when ShowResults is on
$statusFile = Join-Path $dataDir ($Mode.ToLower() + '.status.json')
$runState = [ordered]@{ Run = $runStart.ToString('o'); Mode = $Mode; Phase = 'running'; Started = $runStart.ToString('o'); Ended = '';
                        Current = ''; Index = 0; Total = 0; Handled = @(); Updated = @(); Replaced = @(); NotUpdated = @(); Restart = @(); Reopen = @(); Error = '' }
$startSent = $false
function Save-RunState {
    if (-not $showResults -or $ListOnly) { return }
    try {
        $tmp = "$statusFile.tmp"
        $runState | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $tmp -Encoding UTF8 -ErrorAction Stop
        Move-Item -LiteralPath $tmp -Destination $statusFile -Force -ErrorAction Stop
    } catch { }
}
function Exit-Run([int]$Code, [string]$Problem) {
    if ($Problem -and "$($runState.Phase)" -ne 'done') {
        $runState.Phase = 'done'; $runState.Ended = (Get-Date).ToString('o'); $runState.Error = $Problem
        Save-RunState; Send-RunMessage 'end' $runState
    }
    if ($runMarker) { Remove-Item -LiteralPath $runMarker -Force -ErrorAction SilentlyContinue }
    exit $Code
}
Set-RunMarker ''

$winget = Get-WingetPath
if (-not $winget) {
    $msg = 'winget not found: App Installer is missing or not registered on this device yet.'
    Write-Log "ERROR: $msg"; Write-Summary 1002 'Error' $msg; Exit-Run 1 $msg
}
# winget.exe started directly (as SYSTEM) needs the Visual C++ v14 runtime in System32. Signed-in
# users get it from a framework package, so only the System task needs it.
# The x64 package also contains the ARM64 binaries, so one download covers both.
$VCRedistUrl = 'https://aka.ms/vc14/vc_redist.x64.exe'
$vcNote = ''
function Test-VCRuntime {
    (Test-Path (Join-Path $env:WINDIR 'System32\vcruntime140.dll')) -and (Test-Path (Join-Path $env:WINDIR 'System32\msvcp140.dll'))
}
function Install-VCRuntime {
    # Downloaded into the data folder (SYSTEM and Administrators only), so no user can swap the file
    # between the signature check and the install
    $file = Join-Path $dataDir 'vc_redist.x64.exe'
    $ProgressPreference = 'SilentlyContinue'
    try {
        Remove-Item -Path $file -Force -ErrorAction SilentlyContinue
        [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
        Write-Log "Downloading the Visual C++ runtime from $VCRedistUrl"
        Invoke-WebRequest -Uri $VCRedistUrl -OutFile $file -UseBasicParsing -TimeoutSec 900 -ErrorAction Stop
        $sig = Get-AuthenticodeSignature -FilePath $file
        if ($sig.Status -ne 'Valid' -or "$($sig.SignerCertificate.Subject)" -notmatch 'O=Microsoft Corporation') {
            throw "signature check failed ($($sig.Status), $($sig.SignerCertificate.Subject)); the file was not run"
        }
        $ver = (Get-Item $file).VersionInfo.FileVersion
        $p = Start-Process -FilePath $file -ArgumentList '/install', '/quiet', '/norestart' -Wait -PassThru -WindowStyle Hidden
        switch ($p.ExitCode) {
            0       { $script:vcNote = "Visual C++ runtime $ver installed." }
            1638    { $script:vcNote = 'Visual C++ runtime: the same or a newer version is already installed.' }
            { $_ -in 1641, 3010 } { $script:vcNote = "Visual C++ runtime $ver installed; a restart completes it." }
            default { $script:vcNote = "Visual C++ runtime installer failed with exit code $($p.ExitCode)." }
        }
    } catch {
        $script:vcNote = 'Installing the Visual C++ runtime failed: ' + $_.Exception.Message
    } finally {
        Remove-Item -Path $file -Force -ErrorAction SilentlyContinue
    }
    Write-Log $script:vcNote
}
function Get-WingetVersion {
    $script:wgExit = -1
    try {
        $out = & $winget --version 2>&1
        $script:wgExit = $LASTEXITCODE
        $v = "$($out | Select-Object -First 1)".Trim()
        if ($script:wgExit -eq 0 -and $v) { return $v }
    } catch { }
    return $null
}

$vcTried = $false
if ($Mode -eq 'System' -and -not (Test-VCRuntime)) {
    if ($installVCRuntime) {
        Write-Log 'Visual C++ v14 runtime not found; winget needs it to start as SYSTEM. Installing it.'
        Install-VCRuntime; $vcTried = $true
    } else {
        Write-Log 'WARNING: Visual C++ v14 runtime not found and automatic install is off (-NoVCRuntime); winget may fail to start as SYSTEM.'
    }
}
$wgVersion = Get-WingetVersion
# 0xC0000135 DLL not found, 0xC0000139 entry point not found: runtime missing or too old
$vcExitCodes = @(-1073741515, -1073741511)
if (-not $wgVersion -and $Mode -eq 'System' -and $installVCRuntime -and -not $vcTried -and ($vcExitCodes -contains $wgExit)) {
    Write-Log ('winget did not start (0x{0:X8}): the Visual C++ runtime is missing or too old. Installing it.' -f $wgExit)
    Install-VCRuntime; $vcTried = $true
    $wgVersion = Get-WingetVersion
}
if (-not $wgVersion) {
    $msg = 'winget did not start ({0}, exit code 0x{1:X8}).' -f $winget, $wgExit
    if ($Mode -eq 'System' -and ($vcExitCodes -contains $wgExit)) { $msg += ' The Visual C++ v14 runtime is missing, too old or waiting for a restart.' }
    if ($vcNote) { $msg += " $vcNote" }
    Write-Log "ERROR: $msg"; Write-Summary 1002 'Error' $msg; Exit-Run 1 $msg
}
Write-Log "winget $wgVersion at $winget"

# Exclusions are maintained centrally in config.json on NETLOGON. Read the newest version at every
# run, so a change takes effect at the next run instead of the next restart. The installed copy is
# the fallback (laptop off the network, file invalid). Only the System task updates that copy.
$exclNote = ''
$IdPattern = '^[^.\s\\/:*?"<>|,;\x01-\x1f]{1,32}(\.[^.\s\\/:*?"<>|,;\x01-\x1f]{1,32}){1,7}$'
# A replace rule's From may end in .* (Publisher.Package.*), never broader than Publisher.Package
$WildIdPattern = '^[^.\s\\/:*?"<>|,;\x01-\x1f]{1,32}(\.[^.\s\\/:*?"<>|,;\x01-\x1f]{1,32}){1,6}\.\*$'
function ConvertTo-ReplaceRules($Value) {
    $rules = @()
    if ($null -eq $Value) { return @{ Rules = $rules; Problem = $null } }
    if ($Value -isnot [Management.Automation.PSCustomObject]) { return @{ Rules = @(); Problem = 'Replace is not a list of "From": "To" pairs' } }
    foreach ($p in $Value.PSObject.Properties) {
        $from = "$($p.Name)".Trim(); $to = "$($p.Value)".Trim()
        if ((($from -notmatch $IdPattern) -and ($from -notmatch $WildIdPattern)) -or ($to -notmatch $IdPattern) -or ($from -eq $to)) {
            return @{ Rules = @(); Problem = "invalid Replace rule `"$from`": `"$to`"" }
        }
        $rules += [pscustomobject]@{ From = $from; To = $to }
    }
    return @{ Rules = $rules; Problem = $null }
}
function Format-ReplaceRules($Rules) {
    if (-not @($Rules).Count) { return 'none' }
    return (@($Rules | ForEach-Object { "$($_.From) -> $($_.To)" }) -join ', ')
}
$replaceRules = @()
$rr0 = ConvertTo-ReplaceRules $cfg.Replace
if ($rr0.Problem) { Write-Log "WARNING: config.json: $($rr0.Problem); no packages will be replaced." } else { $replaceRules = @($rr0.Rules) }
# Exclusions for single computers, kept centrally in config.json:
#   "ComputerExcludeIds": { "PC024": [ "Mobatek.MobaXterm" ] }
# Every entry is checked; only the one for this computer's name (%COMPUTERNAME%) is used.
$NamePattern = '^[A-Za-z0-9][A-Za-z0-9_-]{0,14}$'
function ConvertTo-ComputerExclusions($Value) {
    if ($null -eq $Value) { return @{ Ids = @(); Problem = $null } }
    if ($Value -isnot [Management.Automation.PSCustomObject]) { return @{ Ids = @(); Problem = 'ComputerExcludeIds is not a list of "COMPUTER": [ IDs ] pairs' } }
    $mine = @()
    foreach ($p in $Value.PSObject.Properties) {
        $pc = "$($p.Name)".Trim()
        if ($pc -notmatch $NamePattern) { return @{ Ids = @(); Problem = "invalid computer name `"$pc`" in ComputerExcludeIds" } }
        $ids = @(@($p.Value) | ForEach-Object { "$_".Trim() } | Where-Object { $_ })
        $bad = @($ids | Where-Object { $_ -notmatch $IdPattern })
        if ($bad.Count -gt 0) { return @{ Ids = @(); Problem = "invalid winget IDs for ${pc}: " + ($bad -join ' | ') } }
        if ($pc -eq $env:COMPUTERNAME) { $mine += $ids }   # -eq ignores case
    }
    $seen = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    return @{ Ids = @($mine | Where-Object { $seen.Add($_) }); Problem = $null }
}
$computerIds = @()
$computerWarn = ''
$ce0 = ConvertTo-ComputerExclusions $cfg.ComputerExcludeIds
if ($ce0.Problem) { $computerWarn = "Installed config.json: $($ce0.Problem); no exclusions for this computer from it."; Write-Log "WARNING: $computerWarn" } else { $computerIds = @($ce0.Ids) }
function Update-ExclusionsFromSource {
    $src = "$($cfg.ExclusionsSource)"
    if (-not $src) { return }
    if (-not (Test-Path -LiteralPath $src -PathType Leaf)) {
        Write-Log "Exclusions source not reachable ($src); using the installed list."
        return
    }
    $problem = $null
    try { $json = Get-Content -LiteralPath $src -Raw -Encoding UTF8 -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop } catch { $problem = 'invalid JSON' }
    if (-not $problem -and (($json -isnot [Management.Automation.PSCustomObject]) -or (@($json.PSObject.Properties.Name) -notcontains 'ExcludeIds'))) { $problem = 'no ExcludeIds list' }
    if (-not $problem) {
        $ids = @($json.ExcludeIds | ForEach-Object { "$_".Trim() } | Where-Object { $_ })
        $bad = @($ids | Where-Object { $_ -notmatch $IdPattern })
        if ($bad.Count -gt 0) { $problem = 'invalid winget IDs: ' + ($bad -join ' | ') }
    }
    if (-not $problem) {
        $rr = ConvertTo-ReplaceRules $json.Replace
        $problem = $rr.Problem
    }
    if (-not $problem) {
        $ce = ConvertTo-ComputerExclusions $json.ComputerExcludeIds
        $problem = $ce.Problem
    }
    if (-not $problem) {
        $sr = Get-ShowResults $json.ShowResults
        $problem = $sr.Problem
    }
    if ($problem) {
        $script:exclNote = "Exclusions file ${src}: $problem; the installed list was used."
        Write-Log "WARNING: $script:exclNote"
        return
    }
    $seen = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    $ids = @($ids | Where-Object { $seen.Add($_) })
    $script:computerWarn = ''   # the file on NETLOGON is valid and decides
    $notes = @()
    $before = (@($script:excludeIds | ForEach-Object { "$_".ToLowerInvariant() } | Sort-Object) -join ';')
    $after  = (@($ids | ForEach-Object { "$_".ToLowerInvariant() } | Sort-Object) -join ';')
    if ($before -ne $after) {
        Write-Log ("Exclusions updated from ${src}: " + $(if ($ids) { $ids -join ', ' } else { 'none' }) + ' (were: ' + $(if ($script:excludeIds) { $script:excludeIds -join ', ' } else { 'none' }) + ')')
        $script:excludeIds = $ids
        $notes += 'Exclusions updated from NETLOGON.'
    }
    $oldRules = Format-ReplaceRules $script:replaceRules
    $newRules = Format-ReplaceRules $rr.Rules
    if ($oldRules.ToLowerInvariant() -ne $newRules.ToLowerInvariant()) {
        Write-Log "Replace rules updated from ${src}: $newRules (were: $oldRules)"
        $script:replaceRules = @($rr.Rules)
        $notes += 'Replace rules updated from NETLOGON.'
    }
    $oldMine = (@($script:computerIds | ForEach-Object { "$_".ToLowerInvariant() } | Sort-Object) -join ';')
    $newMine = (@($ce.Ids | ForEach-Object { "$_".ToLowerInvariant() } | Sort-Object) -join ';')
    if ($oldMine -ne $newMine) {
        Write-Log ("Exclusions for $env:COMPUTERNAME updated from ${src}: " + $(if ($ce.Ids) { $ce.Ids -join ', ' } else { 'none' }) + ' (were: ' + $(if ($script:computerIds) { $script:computerIds -join ', ' } else { 'none' }) + ')')
        $script:computerIds = @($ce.Ids)
        $notes += "Exclusions for $env:COMPUTERNAME updated from NETLOGON."
    }
    $newShow = $script:showResultsSwitch -or $sr.On
    if ($newShow -ne $script:showResults) {
        Write-Log ("Result messages turned " + $(if ($newShow) { 'on' } else { 'off' }) + " for $env:COMPUTERNAME by ${src}.")
        $script:showResults = $newShow
        $notes += 'Result messages turned ' + $(if ($newShow) { 'on' } else { 'off' }) + ' from NETLOGON.'
    }
    $showChanged = ((ConvertTo-Json -InputObject $cfg.ShowResults -Compress) -ne (ConvertTo-Json -InputObject $json.ShowResults -Compress))
    if (-not $notes.Count -and -not $showChanged) { return }
    if ($notes.Count) { $script:exclNote = $notes -join ' ' }
    if ($Mode -eq 'System' -and -not $ListOnly) {
        # Keep the installed copy current for runs without network
        try {
            $cfg.ExcludeIds = @($script:excludeIds)
            $map = [ordered]@{}
            foreach ($x in @($script:replaceRules)) { $map[$x.From] = $x.To }
            $cfg | Add-Member -NotePropertyName Replace -NotePropertyValue $map -Force
            $cfg | Add-Member -NotePropertyName ComputerExcludeIds -NotePropertyValue $json.ComputerExcludeIds -Force
            $cfg | Add-Member -NotePropertyName ShowResults -NotePropertyValue $json.ShowResults -Force
            $cfg | ConvertTo-Json -Depth 5 | Set-Content -Path $cfgFile -Encoding UTF8 -ErrorAction Stop
        } catch { Write-Log "WARNING: could not update $cfgFile : $($_.Exception.Message)" }
    }
}
Update-ExclusionsFromSource
if ($computerIds.Count) { Write-Log ("Exclusions for this computer ($env:COMPUTERNAME) in config.json: " + ($computerIds -join ', ')) }

# Exclusions for this computer only, written by the installer (-AddLocalExclusion). They add to the
# global list for this run and are never copied into config.json. Both tasks read the same file.
# Only a file owned by SYSTEM or Administrators is used, so a standard user cannot add one.
$localCfgFile = Join-Path (Join-Path $env:ProgramData $Name) 'local-config.json'
$trustedOwners = @('S-1-5-18', 'S-1-5-32-544')
$localExcludeIds = @()
$localWarn = ''
if (Test-Path -LiteralPath $localCfgFile -PathType Leaf) {
    $problem = $null
    $owner = ''
    try { $owner = (Get-Acl -LiteralPath $localCfgFile -ErrorAction Stop).GetOwner([Security.Principal.SecurityIdentifier]).Value } catch { }
    if ($trustedOwners -notcontains $owner) {
        $localWarn = "Local exclusions ignored: $localCfgFile is not owned by SYSTEM or Administrators (owner: $(if ($owner) { $owner } else { 'unknown' })). Add them again with the installer's -AddLocalExclusion."
        Write-Log "WARNING: $localWarn"
    } else {
        $raw = $null
        try { $raw = Get-Content -LiteralPath $localCfgFile -Raw -Encoding UTF8 -ErrorAction Stop } catch { $problem = "cannot be read ($($_.Exception.Message))" }
        if (-not $problem -and -not "$raw".Trim()) { $problem = 'is empty' }
        if (-not $problem) { try { $lj = $raw | ConvertFrom-Json -ErrorAction Stop } catch { $problem = 'is not valid JSON' } }
        if (-not $problem -and (($lj -isnot [Management.Automation.PSCustomObject]) -or (@($lj.PSObject.Properties.Name) -notcontains 'ExcludeIds'))) { $problem = 'has no ExcludeIds list' }
        if (-not $problem) {
            $localExcludeIds = @($lj.ExcludeIds | ForEach-Object { "$_".Trim() } | Where-Object { $_ })
            $bad = @($localExcludeIds | Where-Object { $_ -notmatch $IdPattern })
            if ($bad.Count -gt 0) { $problem = 'contains invalid winget IDs: ' + ($bad -join ' | ') }
        }
        if ($problem) {
            # Updating without the local list could update an app that must stay as it is on this computer
            $msg = "Run stopped: $localCfgFile $problem. Nothing was updated. Correct the file, or delete it and add the exclusions again with the installer's -AddLocalExclusion."
            Write-Log "ERROR: $msg"; Write-Summary 1002 'Error' $msg; Exit-Run 1 $msg
        }
        $seen = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
        $localExcludeIds = @($localExcludeIds | Where-Object { $seen.Add($_) })
        Write-Log ('Local exclusions (this computer only): ' + $(if ($localExcludeIds) { $localExcludeIds -join ', ' } else { 'none' }))
    }
}
# Both lists for this computer add to the list for all computers, and the run summary names them
$onlyHere = @(@($computerIds | ForEach-Object { "$_ (config.json)" }) + @($localExcludeIds | ForEach-Object { "$_ (local-config.json)" }))
$localNote = if ($onlyHere.Count) { "Excluded on this computer only: $($onlyHere -join ', ')." } else { '' }
$seen = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
$excludeIds = @(@($excludeIds) + @($computerIds) + @($localExcludeIds) | Where-Object { $seen.Add("$_") })

# Result messages: the signed-in users get a message when the first app starts updating and one
# when the run is done
if ($showResults -and -not $ListOnly) {
    Write-Log 'Result messages are on: signed-in users get a message when updating starts and when it is done.'
    Save-RunState
}

# As SYSTEM, winget's default way of unpacking zip installers (Windows Shell API) fails with
# "Failed to extract the contents of the archive" (seen with TeamViewer). tar.exe, part of Windows,
# works there, so the System task sets archiveExtractionMethod to tar in SYSTEM's own winget settings.
function Set-ArchiveExtractionTar {
    $file = ''
    try { $file = "$((& $winget settings export 2>$null | Out-String | ConvertFrom-Json).userSettingsFile)" } catch { }
    if (-not $file) {
        Write-Log 'WARNING: winget did not report its settings file; zip-based installers may fail to unpack.'
        return
    }
    $s = $null
    if (Test-Path -LiteralPath $file) {
        $raw = Get-Content -LiteralPath $file -Raw -ErrorAction SilentlyContinue
        if ("$raw".Trim()) {
            try { $s = $raw | ConvertFrom-Json -ErrorAction Stop }
            catch { Write-Log "WARNING: $file is not plain JSON; the archive setting was not changed."; return }
        }
    }
    if (-not $s) { $s = New-Object PSObject -Property @{ '$schema' = 'https://aka.ms/winget-settings.schema.json' } }
    if (-not $s.installBehavior) { $s | Add-Member -NotePropertyName installBehavior -NotePropertyValue (New-Object PSObject) -Force }
    if ("$($s.installBehavior.archiveExtractionMethod)" -eq 'tar') { return }
    $s.installBehavior | Add-Member -NotePropertyName archiveExtractionMethod -NotePropertyValue 'tar' -Force
    try {
        New-Item -ItemType Directory -Path (Split-Path -Parent $file) -Force | Out-Null
        # UTF-8 without BOM, as winget expects
        [IO.File]::WriteAllText($file, ($s | ConvertTo-Json -Depth 10), (New-Object Text.UTF8Encoding $false))
        Write-Log "winget set to unpack zip installers with tar.exe ($file)."
    } catch {
        Write-Log "WARNING: could not write $file : $($_.Exception.Message)"
    }
}
if ($Mode -eq 'System' -and -not $ListOnly) { Set-ArchiveExtractionTar }

$scope = if ($Mode -eq 'System') { 'machine' } else { 'user' }

# winget cannot replace itself halfway through --all, so in User mode App Installer (winget)
# is held back with a pin and updated on its own at the end of the run
$selfId = 'Microsoft.AppInstaller'
$updateSelfLast = ($Mode -eq 'User') -and ($excludeIds -notcontains $selfId)
$pinIds = @($excludeIds)
if ($updateSelfLast) { $pinIds += $selfId }

# Exclusions are enforced with winget pins, so no locale-dependent output parsing is needed
function Set-Exclusions {
    if ($Mode -eq 'System') {
        # SYSTEM's pin list belongs to this tool: config.json is the only source of truth
        & $winget pin reset --force --disable-interactivity *> $null
    } elseif (Test-Path $pinFile) {
        # User mode: only remove pins this tool added earlier, never the user's own pins
        foreach ($old in @(Get-Content $pinFile | Where-Object { $_ -and ($pinIds -notcontains $_) })) {
            & $winget pin remove --id $old --exact --disable-interactivity *> $null
            Write-Log "Exclusion lifted: $old"
        }
    }
    foreach ($id in $pinIds) {
        & $winget pin add --id $id --exact --source winget --force --accept-source-agreements --disable-interactivity *> $null
        if ($LASTEXITCODE -eq 0 -and $id -ne $selfId) { Write-Log "Excluded: $id" }
    }
    if ($pinIds.Count -gt 0) { Set-Content -Path $pinFile -Value $pinIds -Encoding ascii }
    elseif (Test-Path $pinFile) { Remove-Item -Path $pinFile -Force }
}

# Run winget and keep the log readable: drop empty lines, progress bars and spinner characters
# winget output worth logging: no progress bars, no spinner frames, no empty lines
function Test-LogLine([string]$Line) {
    return [bool]($Line.Trim() -and $Line -notmatch '[\u2580-\u259F]' -and $Line.Trim() -notmatch '^[-\\|/]+$')
}

# An installer that waits for input nobody can give (a dialog or an app it starts, invisible to
# SYSTEM) would hold the run until the task's 3-hour limit. Stop the processes winget started, so
# winget reports that app as failed and continues with the next one.
$stalledApps = New-Object System.Collections.Generic.List[string]
$restartApps = New-Object System.Collections.Generic.List[string]   # installers that asked for a restart of the PC
$reopenApps  = New-Object System.Collections.Generic.List[string]   # apps that finish updating when they are started again
$listedUpdates = [System.Collections.Specialized.OrderedDictionary]::new([StringComparer]::OrdinalIgnoreCase)   # Id = version winget listed as available
$foundUpdates  = [System.Collections.Specialized.OrderedDictionary]::new([StringComparer]::OrdinalIgnoreCase)   # Id = version winget went on to install ("Found <name> [<Id>] Version <version>"), in run order
$foundNames    = @{}   # Id = app name, from the "Found" lines and the tables, for the result message
function Stop-StalledInstaller([int]$WingetId, [datetime]$Since, [string]$Package) {
    $all  = @(Get-CimInstance -ClassName Win32_Process -ErrorAction SilentlyContinue)
    $tree = @()
    $parents = @($WingetId)
    while ($parents.Count) {
        $kids = @($all | Where-Object { ($parents -contains [int]$_.ParentProcessId) -and ($_.CreationDate -ge $Since) -and
                                        ($_.Name -ne 'conhost.exe') -and (@($tree | ForEach-Object { $_.ProcessId }) -notcontains $_.ProcessId) })
        $tree += $kids
        $parents = @($kids | ForEach-Object { [int]$_.ProcessId })
    }
    $what = if ($Package) { $Package } else { 'an app' }
    if ($tree.Count -eq 0) {
        Write-Log "No progress for $installTimeoutMinutes minutes while handling ${what}, but no installer is running; still waiting."
        return
    }
    $stopped = @()
    for ($i = $tree.Count - 1; $i -ge 0; $i--) {   # deepest first
        $t = $tree[$i]
        try { Stop-Process -Id $t.ProcessId -Force -ErrorAction Stop; $stopped += "$($t.Name) ($($t.ProcessId))" }
        catch { $stopped += "$($t.Name) ($($t.ProcessId), could not stop it)" }
    }
    Write-Log "No progress for $installTimeoutMinutes minutes while installing ${what}: stopped $($stopped -join ', '). winget reports it as failed and continues."
    $stalledApps.Add($what)
}

# winget prints the available updates as a table: a header line, a line of dashes and one row per
# package. The columns are taken from the header, so this works in any display language.
function Get-TableColumns([string]$Header) {
    $starts = @([regex]::Matches($Header, '\S+') | ForEach-Object { $_.Index })
    if ($starts.Count -lt 4) { return $null }
    return @{ Id = $starts[1]; Available = $starts[3] }
}
function ConvertFrom-TableRow([string]$Row, $Columns) {
    $tokens = @([regex]::Matches($Row, '\S+'))
    $idTok = @($tokens | Where-Object { [math]::Abs($_.Index - $Columns.Id) -le 2 } | Select-Object -First 1)
    if (-not $idTok.Count) { return $null }
    $id = $idTok[0].Value
    # a shortened ID ends in an ellipsis and cannot be matched
    if ($id -notmatch '^[A-Za-z0-9][^\s.]*(\.[^\s.]+)+$' -or $id.Contains([string][char]0x2026)) { return $null }
    $avTok = @($tokens | Where-Object { [math]::Abs($_.Index - $Columns.Available) -le 2 } | Select-Object -First 1)
    $nm = $Row.Substring(0, [math]::Min($idTok[0].Index, $Row.Length)).Trim()
    return @{ Id = $id; Available = $(if ($avTok.Count) { $avTok[0].Value } else { '' }); Name = $nm }
}

function Invoke-Winget([string[]]$Arguments) {
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName  = $winget
    $psi.Arguments = (@($Arguments) | ForEach-Object { if ($_ -match '[\s"]') { '"' + ($_ -replace '"', '\"') + '"' } else { $_ } }) -join ' '
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow  = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError  = $true
    $psi.StandardOutputEncoding = [Text.Encoding]::UTF8
    $psi.StandardErrorEncoding  = [Text.Encoding]::UTF8
    try { $p = [Diagnostics.Process]::Start($psi) }
    catch { Write-Log "winget could not be started: $($_.Exception.Message)"; return -1 }
    $since    = try { $p.StartTime.AddSeconds(-1) } catch { (Get-Date).AddSeconds(-5) }
    $errText  = $p.StandardError.ReadToEndAsync()
    $lastLine = Get-Date
    $package  = ''
    $columns  = $null   # columns of the table winget is printing
    $header   = ''
    $read = $p.StandardOutput.ReadLineAsync()
    while ($true) {
        if ($read.Wait(5000)) {
            $line = $read.Result
            if ($null -eq $line) { break }
            $read = $p.StandardOutput.ReadLineAsync()
            if ($columns) {
                $row = ConvertFrom-TableRow $line $columns
                if ($row) {
                    if (-not $listedUpdates.Contains($row.Id)) { $listedUpdates[$row.Id] = $row.Available }
                    if ($row.Name -and -not $foundNames.ContainsKey($row.Id)) { $foundNames[$row.Id] = $row.Name }
                }
                else { $columns = $null }
            }
            if ($line -match '^-{8,}\s*$' -and $header) { $columns = Get-TableColumns $header }
            if ($line.Trim()) { $header = $line }
            if (Test-LogLine $line) {
                Write-Log $line
                $lastLine = Get-Date
                # "(1/11) Found <name> [<Id>] Version <version>", in any display language
                if ($line -match '\[([A-Za-z0-9][^\]\s]*\.[^\]\s]+)\]') {
                    $package = $Matches[1]
                    if ($line -match '\]\s+\S+\s+(\S+)\s*$') { $foundUpdates[$package] = $Matches[1] }
                    if ($line -match '^\s*\((\d+)/(\d+)\)\s+\S+\s+(.+?)\s+\[') {
                        $foundNames[$package] = $Matches[3].Trim(); $runState.Index = [int]$Matches[1]; $runState.Total = [int]$Matches[2]
                    } elseif ($line -match '^\s*\S+\s+(.+?)\s+\[') { $foundNames[$package] = $Matches[1].Trim() }
                    if ("$($runState.Current)") { $runState.Handled += "$($runState.Current)" }
                    $runState.Current = if ($foundNames[$package]) { $foundNames[$package] } else { $package }
                    Set-RunMarker $package
                    Save-RunState
                    if (-not $script:startSent) { Send-RunMessage 'start' $runState }
                }
                # English winget output, as SYSTEM uses it
                if ($line -match 'Restart your PC') {
                    $what = if ($package) { $package } else { 'an app' }
                    if (-not $restartApps.Contains($what)) { $restartApps.Add($what) }
                }
                if ($line -match 'Restart the application') {
                    $what = if ($package) { $package } else { 'an app' }
                    if (-not $reopenApps.Contains($what)) { $reopenApps.Add($what) }
                }
            }
        } elseif ($p.HasExited) {
            break   # an app started by an installer can keep winget's output open after winget has ended
        }
        # Checked on every pass: winget's spinner keeps sending frames while an installer hangs
        if ($installTimeoutMinutes -gt 0 -and ((Get-Date) - $lastLine).TotalMinutes -ge $installTimeoutMinutes) {
            Stop-StalledInstaller $p.Id $since $package
            $lastLine = Get-Date
        }
    }
    $p.WaitForExit()
    if ($errText.Wait(5000)) { foreach ($e in ("$($errText.Result)" -split "`r?`n")) { if (Test-LogLine $e) { Write-Log $e } } }
    return $p.ExitCode
}

# 0x8A15000F "Data required by the source is missing": winget cannot read its catalogue.
# For a signed-in user, winget keeps the catalogue in the Microsoft.Winget.Source app package and
# installs that package itself. When that install fails, "source reset" does not help, so the user
# repair installs the package directly. SYSTEM keeps its own copy, which "source reset --force"
# (admin rights) clears.
$SourceDataMissing = -1978335217
$SourcePackageUrl  = 'https://cdn.winget.microsoft.com/cache/source2.msix'
function Install-SourcePackage {
    # The same file winget downloads. Windows checks its Microsoft signature before installing it.
    $file = Join-Path $env:TEMP 'KeepItUpToDater-source2.msix'
    $ProgressPreference = 'SilentlyContinue'
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
        Invoke-WebRequest -Uri $SourcePackageUrl -OutFile $file -UseBasicParsing -TimeoutSec 600 -ErrorAction Stop
        Add-AppxPackage -Path $file -ErrorAction Stop
        Write-Log 'Catalogue package Microsoft.Winget.Source installed directly.'
    } catch {
        Write-Log ('Installing the catalogue package directly failed: ' + $_.Exception.Message)
    } finally {
        Remove-Item -Path $file -Force -ErrorAction SilentlyContinue
    }
}
function Repair-WingetSource([int]$Step) {
    if ($Step -eq 1) {
        Write-Log 'winget catalogue data is missing or damaged (0x8A15000F). Repair step 1: refresh the sources.'
        if ($Mode -eq 'System') {
            $rc = Invoke-Winget @('source', 'reset', '--force', '--disable-interactivity')
            Write-Log ('winget source reset --force: exit 0x{0:X8}' -f $rc)
        }
        $rc = Invoke-Winget @('source', 'update', '--disable-interactivity')
        Write-Log ('winget source update: exit 0x{0:X8}' -f $rc)
    } else {
        Write-Log 'Catalogue still missing. Repair step 2: install the catalogue package directly.'
        Install-SourcePackage
    }
}
function Get-SourceDiagnosis {
    # Tells a blocked download (proxy, firewall, SSL inspection) apart from a blocked package install
    try {
        $r = Invoke-WebRequest -Uri $SourcePackageUrl -Method Head -UseBasicParsing -TimeoutSec 60 -ErrorAction Stop
        $diag = 'Download location reachable (HTTP {0}).' -f [int]$r.StatusCode
    } catch {
        $resp = $_.Exception.Response
        if ($resp -and [int]$resp.StatusCode -eq 407) { $diag = 'Download location NOT reachable: the proxy requires authentication (HTTP 407).' }
        elseif ($resp) { $diag = 'Download location reachable (HTTP {0}).' -f [int]$resp.StatusCode }
        else { $diag = "Download location NOT reachable ($SourcePackageUrl): $($_.Exception.Message)" }
    }
    Write-Log $diag
    # The error lines from winget's own log of this run usually name the exact cause
    $dirs = @((Join-Path $env:LOCALAPPDATA 'Packages\Microsoft.DesktopAppInstaller_8wekyb3d8bbwe\LocalState\DiagOutputDir'),
              (Join-Path $env:LOCALAPPDATA 'Microsoft\WinGet'),
              (Join-Path $env:TEMP 'WinGet')) | Where-Object { Test-Path $_ }
    $errors = @()
    if ($dirs) {
        $errors = @(Get-ChildItem -Path $dirs -Filter 'WinGet-*.log' -Recurse -ErrorAction SilentlyContinue |
            Where-Object { $_.LastWriteTime -ge $runStart } | Sort-Object LastWriteTime |
            Select-String -Pattern '<E>' -SimpleMatch | Select-Object -Last 5)
    }
    foreach ($e in $errors) { Write-Log ('winget log: ' + $e.Line.Trim()) }
    if ($errors.Count -eq 0) { Write-Log 'No error lines found in winget''s own log for this run.' }
    return $diag
}

# Replace rules (config.json "Replace"): winget keeps every end-of-life Node.js major as a package of
# its own (OpenJS.NodeJS.20) and only ever updates it within that major. A rule moves such a package
# to another one (OpenJS.NodeJS.LTS). System task only: these are machine-wide installs.
$replaced      = New-Object System.Collections.Generic.List[string]
$replaceFailed = New-Object System.Collections.Generic.List[string]
function Test-WingetInstalled([string]$Id) {
    & $winget list --id $Id --exact --source winget --accept-source-agreements --disable-interactivity *> $null
    return ($LASTEXITCODE -eq 0)
}
# winget export: every installed package winget can match, with its version. $null when it fails.
function Get-InstalledPackages {
    $file = Join-Path $dataDir 'installed-packages.json'
    Remove-Item -LiteralPath $file -Force -ErrorAction SilentlyContinue
    & $winget export --output $file --source winget --include-versions --accept-source-agreements --disable-interactivity *> $null
    $list = @()
    try { $list = @((Get-Content -LiteralPath $file -Raw -ErrorAction Stop | ConvertFrom-Json).Sources | ForEach-Object { $_.Packages } | Where-Object { $_.PackageIdentifier }) } catch { }
    Remove-Item -LiteralPath $file -Force -ErrorAction SilentlyContinue
    if ($list.Count -eq 0) { return $null }
    return ,$list
}
function Test-ReplaceMatch([string]$Id, $Rule) {
    if ($Rule.From.EndsWith('.*')) { return $Id.StartsWith($Rule.From.Substring(0, $Rule.From.Length - 1), [StringComparison]::OrdinalIgnoreCase) }
    return ($Id -eq $Rule.From)
}
# The installed packages a rule is about: the target and everything the rule moves away from
function Get-RulePackages($List, $Rule) {
    return ,@(@($List) | Where-Object { $_ -and (("$($_.PackageIdentifier)" -eq $Rule.To) -or (Test-ReplaceMatch "$($_.PackageIdentifier)" $Rule)) })
}
function Invoke-Replacements {
    # Returns $false when winget could not list the installed packages (for example a missing catalogue)
    $installed = Get-InstalledPackages
    if ($null -eq $installed) { return $false }
    $okInstall = @(0, -1978335189, -1978335135)   # 0x8A15002B and 0x8A150061: the target is already installed
    $instArgs = @('--exact', '--source', 'winget', '--scope', 'machine', '--silent', '--accept-package-agreements', '--accept-source-agreements', '--disable-interactivity')
    foreach ($pkg in @($installed)) {
        $id = "$($pkg.PackageIdentifier)"; $ver = "$($pkg.Version)"
        foreach ($rule in $replaceRules) {
            if (-not (Test-ReplaceMatch $id $rule) -or ($id -eq $rule.To)) { continue }
            $to = $rule.To
            if (($excludeIds -contains $id) -or ($excludeIds -contains $to)) { Write-Log "Not replacing $id with ${to}: excluded (config.json or local exclusions)."; break }
            if ($ListOnly) { Write-Log "Would replace $id $ver with $to."; break }
            Write-Log "Replacing $id $ver with $to (config.json Replace)."
            $rc = Invoke-Winget (@('install', '--id', $to) + $instArgs)
            if ($okInstall -notcontains $rc) {
                Write-Log ("Replacing $id failed: installing $to ended with 0x{0:X8}; $id was left as it is." -f $rc)
                $replaceFailed.Add($id); break
            }
            # winget can show one installation under more than one ID (Node.js: all versions share one
            # MSI upgrade code), so "winget list --id $id" is no proof that the old version is still there.
            # Decide from the installed versions: remove $id only when version $ver is still installed
            # next to the new one, and remove only that version.
            $now = Get-InstalledPackages
            if ($null -eq $now) {
                Write-Log "Replacing ${id}: $to was installed, but the installed packages could not be listed afterwards, so $id $ver was not removed."
                $replaceFailed.Add($id); break
            }
            $mine = Get-RulePackages $now $rule
            $oldLeft = @($mine | Where-Object { "$($_.Version)" -eq $ver })
            if ($mine.Count -le 1 -and $rc -ne 0 -and $oldLeft.Count -eq 1) {
                # Nothing was installed and the one installation is unchanged: winget lists it as both IDs
                Write-Log "Not replacing $id ${ver}: winget lists this installation under $to as well, and $to has no newer version."
                break
            }
            $removed = $false
            if ($oldLeft.Count -gt 0 -and $oldLeft.Count -lt $mine.Count) {
                $removed = $true
                foreach ($o in $oldLeft) {
                    $null = Invoke-Winget @('uninstall', '--id', "$($o.PackageIdentifier)", '--exact', '--version', $ver, '--source', 'winget', '--silent', '--accept-source-agreements', '--disable-interactivity')
                }
                $now = Get-InstalledPackages
                if ($null -ne $now) { $mine = Get-RulePackages $now $rule }
                if (($null -ne $now) -and @($mine | Where-Object { "$($_.Version)" -eq $ver }).Count) {
                    Write-Log "Replacing ${id}: $to is installed, but $id $ver could not be removed."
                    $replaceFailed.Add($id); break
                }
            }
            # Check the result: something other than version $ver must still be installed
            $targetOk = if ($null -eq $now) { Test-WingetInstalled $to }
                        elseif ($removed) { @($mine | Where-Object { "$($_.Version)" -ne $ver }).Count -gt 0 }
                        else { $mine.Count -gt 0 }
            if (-not $targetOk) {
                Write-Log "WARNING: after replacing $id $ver no $to was left installed; installing $to again."
                $rc = Invoke-Winget (@('install', '--id', $to) + $instArgs)
                if ($okInstall -notcontains $rc) {
                    Write-Log ("Replacing $id failed: $to is not installed (installing it again ended with 0x{0:X8})." -f $rc)
                    $replaceFailed.Add($id); break
                }
            }
            Write-Log "Replaced $id $ver with $to."
            $replaced.Add("$id with $to")
            break
        }
    }
    return $true
}

if (-not $ListOnly) { Set-Exclusions }

$replaceListed = $true
if ($Mode -eq 'System' -and $replaceRules.Count) {
    Write-Log "Replace rules: $(Format-ReplaceRules $replaceRules)"
    $replaceListed = Invoke-Replacements
    if (-not $replaceListed) { Write-Log 'Could not list the installed packages; the replace rules are tried again after the update pass.' }
}

$wgArgs = @('upgrade', '--scope', $scope, '--source', 'winget', '--accept-source-agreements', '--disable-interactivity')
if ($ListOnly) {
    Write-Log 'List only: showing available updates, nothing will be changed.'
    $wgArgs += '--include-pinned'
} else {
    $wgArgs += @('--all', '--silent', '--accept-package-agreements')
    if ($includeUnknown) { $wgArgs += '--include-unknown' }
}
Write-Log ('Running: winget ' + ($wgArgs -join ' '))
$listedUpdates.Clear(); $foundUpdates.Clear()
$code = Invoke-Winget $wgArgs

# Repair the catalogue and retry after each step. SYSTEM: reset + update. User: update, then
# install the catalogue package directly.
$repairSteps = if ($Mode -eq 'User') { 2 } else { 1 }
for ($step = 1; ($code -eq $SourceDataMissing) -and ($step -le $repairSteps); $step++) {
    Repair-WingetSource $step
    # Pins need a working catalogue too: set the exclusions again before anything is upgraded
    if (-not $ListOnly) { Set-Exclusions }
    Write-Log ('Retrying: winget ' + ($wgArgs -join ' '))
    $listedUpdates.Clear(); $foundUpdates.Clear()
    $code = Invoke-Winget $wgArgs
}
# Updates winget listed but did not install, or installed in another version than it listed. A
# newer version can lack an installer for this scope, or use another installer type.
$listedNote = ''
if (-not $ListOnly -and $code -ne $SourceDataMissing) {
    $notTried = @(); $otherVer = @()
    foreach ($lid in @($listedUpdates.Keys)) {
        $av = "$($listedUpdates[$lid])"
        if (-not $foundUpdates.Contains($lid)) { $notTried += "$lid $av".Trim() }
        elseif ($av -and "$($foundUpdates[$lid])" -ne $av) { $otherVer += "$lid $($foundUpdates[$lid]) ($av listed)" }
    }
    if ($notTried.Count) { $listedNote = "Listed by winget but not updated: $($notTried -join ', ')." }
    if ($otherVer.Count) { $listedNote = ("$listedNote Updated to another version than listed: $($otherVer -join ', ').").Trim() }
    if ($listedNote) { Write-Log "$listedNote See chapter 11 of the manual to find out why, or exclude the app." }
}
$diagnosis = ''
if ($code -eq $SourceDataMissing) { $diagnosis = Get-SourceDiagnosis }
$hex = '0x{0:X8}' -f $code
if (-not $replaceListed -and $code -ne $SourceDataMissing) {
    if (-not (Invoke-Replacements)) { Write-Log 'WARNING: could not list the installed packages; nothing was replaced.' }
}

if ($ListOnly) {
    if ($code -eq $SourceDataMissing) { Write-Log 'winget catalogue is still missing. The lines above show why; see chapter 11 of the manual.' }
    Write-Log "List finished (winget exit code $hex)."
    exit 0
}

if ($updateSelfLast -and $code -ne $SourceDataMissing) {
    Write-Log "Updating $selfId (winget itself) last."
    $null = Invoke-Winget @('upgrade', '--id', $selfId, '--exact', '--include-pinned', '--source', 'winget', '--silent', '--accept-package-agreements', '--accept-source-agreements', '--disable-interactivity')
}

# Result message: what was updated and what is still waiting, read from winget itself after the
# run (works in any display language). Not run without ShowResults.
$stillListed = $null
if ($showResults -and $code -ne $SourceDataMissing) {
    $mainListed = [System.Collections.Specialized.OrderedDictionary]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($k in @($listedUpdates.Keys)) { $mainListed[$k] = $listedUpdates[$k] }
    Write-Log 'Checking which updates are still waiting (for the result message).'
    $listedUpdates.Clear()
    $null = Invoke-Winget @('upgrade', '--scope', $scope, '--source', 'winget', '--accept-source-agreements', '--disable-interactivity')
    $stillListed = $listedUpdates
    $nameOf = { param($i) $v = $foundNames[$i]; if ($v) { $v } else { $i } }
    foreach ($i in @($foundUpdates.Keys)) {
        if ($restartApps.Contains($i)) { continue }
        if ($stillListed.Contains($i)) { $runState.NotUpdated += "$(& $nameOf $i) ($($stillListed[$i]) available)" }
        else { $runState.Updated += "$(& $nameOf $i) $($foundUpdates[$i])" }
    }
    foreach ($i in @($mainListed.Keys)) {
        if (-not $foundUpdates.Contains($i) -and $stillListed.Contains($i)) { $runState.NotUpdated += "$(& $nameOf $i) ($($stillListed[$i]) available)" }
    }
    $runState.Replaced = @($replaced | ForEach-Object { "$_" -replace ' with ', ' replaced by ' })
    $runState.Restart  = @($restartApps | ForEach-Object { & $nameOf $_ })
    $runState.Reopen   = @($reopenApps | ForEach-Object { & $nameOf $_ })
}

$completed = $true
switch ($code) {
    0           { $evt = 1000; $type = 'Information'; $msg = 'Finished: all applicable updates installed.' }
    -1978335189 { $evt = 1000; $type = 'Information'; $msg = 'Finished: no applicable updates.' }                          # 0x8A15002B
    -1978335188 { $evt = 1001; $type = 'Warning';     $msg = "Finished: one or more packages failed to update. See $log" }  # 0x8A15002C
    -1978335217 { $evt = 1002; $type = 'Error';       $msg = "winget catalogue data is missing or damaged (0x8A15000F) and the automatic repair did not help. $diagnosis Details in $log. Will retry at the next trigger."; $completed = $false }
    default     { $evt = 1001; $type = 'Warning';     $msg = "winget ended with exit code $hex; will retry at the next trigger. See $log"; $completed = $false }
}
$stallNote = ''
if ($stalledApps.Count) {
    $stallNote = "Installer stopped after $installTimeoutMinutes minutes without progress: $($stalledApps -join ', ')."
    if ($evt -eq 1000) { $evt = 1001; $type = 'Warning' }
}
$replaceNote = ''
if ($replaced.Count) { $replaceNote = "Replaced: $($replaced -join '; ')." }
if ($replaceFailed.Count) {
    $replaceNote = ("$replaceNote Replacing failed for: $($replaceFailed -join ', ').").Trim()
    if ($evt -eq 1000) { $evt = 1001; $type = 'Warning' }
}
$restartNote = ''
if ($restartApps.Count) { $restartNote = "Restart the PC to finish installing: $($restartApps -join ', ')." }
$reopenNote = ''
if ($reopenApps.Count) { $reopenNote = "Close and start again to finish updating: $($reopenApps -join ', ')." }
if (($localWarn -or $computerWarn -or $unfinishedNote) -and $evt -eq 1000) { $evt = 1001; $type = 'Warning' }
foreach ($n in @($unfinishedNote, $replaceNote, $stallNote, $restartNote, $reopenNote, $listedNote, $vcNote, $exclNote, $computerWarn, $localNote, $localWarn)) { if ($n) { $msg += " $n" } }
Write-Log $msg
Write-Summary $evt $type $msg
if ($completed) { (Get-Date).ToString('o') | Set-Content -Path $stamp -Encoding ascii }
if ($showResults) {
    if (-not $completed) { $runState.Error = $msg }
    $runState.Phase = 'done'; $runState.Ended = (Get-Date).ToString('o'); $runState.Current = ''; $runState.Handled = @()
    Save-RunState; Send-RunMessage 'end' $runState
}
Exit-Run 0
'@
#endregion

function Test-Admin {
    $principal = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Save-Runner([string]$Folder) {
    $target = Join-Path $Folder $RunnerName
    $signed = if ($PSScriptRoot) { Join-Path $PSScriptRoot $RunnerName } else { $null }
    if ($signed -and (Test-Path $signed) -and ((Resolve-Path $signed).Path -ne $target)) {
        Copy-Item -Path $signed -Destination $target -Force   # byte copy keeps a code signature valid
        Write-Output "Deployed $RunnerName from $PSScriptRoot"
    } else {
        Set-Content -Path $target -Value $RunnerCode -Encoding UTF8
    }
}

function Write-ComputerExclusions([string]$Kept) {
    $all = @($script:ComputerExcludeIds.Keys | ForEach-Object { "$_ ($(@($script:ComputerExcludeIds[$_]).Count))" })
    $mine = @(foreach ($k in @($script:ComputerExcludeIds.Keys)) { if ($k -eq $env:COMPUTERNAME) { $script:ComputerExcludeIds[$k] } })
    Write-Output ("Exclusions per computer $($Kept)".Trim() + ': ' + $(if ($all.Count) { $all -join ', ' } else { 'none' }) +
                  "; this computer ($env:COMPUTERNAME): " + $(if ($mine.Count) { $mine -join ', ' } else { 'none' }))
}

function Write-UserTaskSetting {
    Write-Output ("User task: " + $(if ($NoUserTask) { 'off (-NoUserTask)' } elseif ($script:UserTaskCfg -eq $false) { 'off (config.json)' } else { 'on' }))
}

function Read-Exclusions {
    # Read and check the config file before anything is changed, so a typo or a missing file
    # never removes exclusions that are already in place.
    $useDefault = -not $ConfigFile
    $path = if ($useDefault) { 'config.json' } else { $ConfigFile }
    if (-not [IO.Path]::IsPathRooted($path)) {
        if (-not $PSScriptRoot) { throw 'Cannot determine the installer folder. Use -ConfigFile with a full path.' }
        $path = Join-Path $PSScriptRoot $path
    }
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        if (-not $useDefault) { throw "Config file not found: $path" }
        $installed = Join-Path $InstallDir 'config.json'
        $kept = @()
        if (Test-Path -LiteralPath $installed) {
            try {
                $prev = Get-Content -LiteralPath $installed -Raw -Encoding UTF8 | ConvertFrom-Json
                $kept = @($prev.ExcludeIds | Where-Object { $_ })
                $script:ExclusionsSource = "$($prev.ExclusionsSource)"
                if ($prev.Replace -is [Management.Automation.PSCustomObject]) {
                    foreach ($p in $prev.Replace.PSObject.Properties) { $script:ReplaceRules[$p.Name] = "$($p.Value)" }
                }
                if ($prev.ComputerExcludeIds -is [Management.Automation.PSCustomObject]) {
                    foreach ($p in $prev.ComputerExcludeIds.PSObject.Properties) { $script:ComputerExcludeIds[$p.Name] = @(@($p.Value) | Where-Object { $_ }) }
                }
                $script:ShowResultsCfg = $prev.ShowResults
                if ($prev.UserTaskConfig -is [bool]) { $script:UserTaskCfg = $prev.UserTaskConfig }
            } catch { }
        }
        $script:ExcludeIds = $kept
        Write-Warning "No config.json found next to the installer ($path). Keeping the current exclusions: $(if ($kept) { $kept -join ', ' } else { 'none' })"
        Write-Output "Replace rules (kept): $(if ($script:ReplaceRules.Count) { @($script:ReplaceRules.Keys | ForEach-Object { "$_ -> $($script:ReplaceRules[$_])" }) -join ', ' } else { 'none' })"
        Write-ComputerExclusions '(kept)'
        Write-UserTaskSetting
        return
    }
    try { $json = Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json }
    catch { throw "$path is not valid JSON: $($_.Exception.Message)" }
    if (($json -isnot [Management.Automation.PSCustomObject]) -or (@($json.PSObject.Properties.Name) -notcontains 'ExcludeIds')) {
        throw "$path has no ExcludeIds list. Expected: { `"ExcludeIds`": [ `"Publisher.App`" ] }"
    }
    $ids = @($json.ExcludeIds | ForEach-Object { "$_".Trim() } | Where-Object { $_ })
    # winget package ID format (Publisher.Package, 2 to 8 parts); commas and semicolons are not allowed
    $bad = @($ids | Where-Object { $_ -notmatch '^[^.\s\\/:*?"<>|,;\x01-\x1f]{1,32}(\.[^.\s\\/:*?"<>|,;\x01-\x1f]{1,32}){1,7}$' })
    if ($bad.Count -gt 0) {
        throw "$path contains invalid winget IDs: $($bad -join ' | '). Put each ID in its own quotes and use the Id column of 'winget list'."
    }
    $seen = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    $script:ExcludeIds = @($ids | Where-Object { $seen.Add($_) })   # drop duplicates, keep order and spelling
    Write-Output "Exclusions from ${path}: $(if ($script:ExcludeIds) { $script:ExcludeIds -join ', ' } else { 'none' })"
    # Optional replace rules: "From": "To". From may end in .* to cover every package below that name.
    $script:ReplaceRules = [ordered]@{}
    if ((@($json.PSObject.Properties.Name) -contains 'Replace') -and ($null -ne $json.Replace)) {
        $example = '"Replace": { "OpenJS.NodeJS.*": "OpenJS.NodeJS.LTS" }'
        if ($json.Replace -isnot [Management.Automation.PSCustomObject]) {
            throw "${path}: Replace must be a list of `"From`": `"To`" pairs, for example $example"
        }
        $idRx   = '^[^.\s\\/:*?"<>|,;\x01-\x1f]{1,32}(\.[^.\s\\/:*?"<>|,;\x01-\x1f]{1,32}){1,7}$'
        $wildRx = '^[^.\s\\/:*?"<>|,;\x01-\x1f]{1,32}(\.[^.\s\\/:*?"<>|,;\x01-\x1f]{1,32}){1,6}\.\*$'
        foreach ($p in $json.Replace.PSObject.Properties) {
            $from = "$($p.Name)".Trim(); $to = "$($p.Value)".Trim()
            if ((($from -notmatch $idRx) -and ($from -notmatch $wildRx)) -or ($to -notmatch $idRx) -or ($from -eq $to)) {
                throw "$path contains an invalid Replace rule `"$from`": `"$to`". Use winget IDs; From may end in .* (Publisher.Package.*), for example $example"
            }
            $script:ReplaceRules[$from] = $to
        }
    }
    Write-Output "Replace rules: $(if ($script:ReplaceRules.Count) { @($script:ReplaceRules.Keys | ForEach-Object { "$_ -> $($script:ReplaceRules[$_])" }) -join ', ' } else { 'none' })"
    # Optional exclusions per computer name: "ComputerExcludeIds": { "PC024": [ "Mobatek.MobaXterm" ] }
    $script:ComputerExcludeIds = [ordered]@{}
    if ((@($json.PSObject.Properties.Name) -contains 'ComputerExcludeIds') -and ($null -ne $json.ComputerExcludeIds)) {
        $example = '"ComputerExcludeIds": { "PC024": [ "Mobatek.MobaXterm" ] }'
        if ($json.ComputerExcludeIds -isnot [Management.Automation.PSCustomObject]) {
            throw "${path}: ComputerExcludeIds must be a list of `"COMPUTER`": [ IDs ] pairs, for example $example"
        }
        foreach ($p in $json.ComputerExcludeIds.PSObject.Properties) {
            $pc = "$($p.Name)".Trim()
            if ($pc -notmatch $NameRegex) {
                throw "$path contains an invalid computer name `"$pc`" in ComputerExcludeIds. Use the name the computer shows in %COMPUTERNAME% (at most 15 characters), for example $example"
            }
            $ids = @(@($p.Value) | ForEach-Object { "$_".Trim() } | Where-Object { $_ })
            $bad = @($ids | Where-Object { $_ -notmatch $IdRegex })
            if ($bad.Count -gt 0) {
                throw "$path contains invalid winget IDs for ${pc}: $($bad -join ' | '). Put each ID in its own quotes and use the Id column of 'winget list'."
            }
            $seen = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
            $script:ComputerExcludeIds[$pc] = @($ids | Where-Object { $seen.Add($_) })
        }
    }
    Write-ComputerExclusions ''
    # Optional result window: "ShowResults": true, false, or a list of computer names
    $script:ShowResultsCfg = $null
    if ((@($json.PSObject.Properties.Name) -contains 'ShowResults') -and ($null -ne $json.ShowResults)) {
        $v = $json.ShowResults
        if ($v -is [bool]) { $script:ShowResultsCfg = $v }
        else {
            $names = @(@($v) | ForEach-Object { "$_".Trim() } | Where-Object { $_ })
            $bad = @($names | Where-Object { $_ -notmatch $NameRegex })
            if (($v -isnot [array]) -or $bad.Count) {
                throw "${path}: ShowResults must be true, false or a list of computer names as %COMPUTERNAME% shows them, for example `"ShowResults`": [ `"PC024`" ]"
            }
            $script:ShowResultsCfg = @($names)
        }
    }
    Write-Output ("Result messages: " + $(if ($ShowResults) { 'on (-ShowResults)' } elseif ($script:ShowResultsCfg -is [bool]) { $(if ($script:ShowResultsCfg) { 'on (config.json)' } else { 'off (config.json)' }) } elseif ($null -ne $script:ShowResultsCfg) { "on for $(@($script:ShowResultsCfg) -join ', ') (config.json)" } else { 'off' }))
    # Optional: "UserTask": false where AppLocker or another policy blocks PowerShell for users
    $script:UserTaskCfg = $null
    if ((@($json.PSObject.Properties.Name) -contains 'UserTask') -and ($null -ne $json.UserTask)) {
        if ($json.UserTask -isnot [bool]) { throw "${path}: UserTask must be true or false (false: no User task, for PCs where users cannot run PowerShell)" }
        $script:UserTaskCfg = $json.UserTask
    }
    Write-UserTaskSetting
    # Only a network path (NETLOGON) is re-read by the scheduled tasks. A local folder could be
    # writable by standard users, who must not be able to switch off updates.
    $full = [IO.Path]::GetFullPath($path)
    if (([uri]$full).IsUnc) {
        $script:ExclusionsSource = $full
        Write-Output "The scheduled tasks read the newest exclusions from $full at every run."
    } else {
        $script:ExclusionsSource = ''
    }
}

function Save-Config([string]$Folder) {
    [ordered]@{
        Product         = $DisplayName
        Organization    = $Organization
        Version         = $ToolVersion
        ExcludeIds      = @($ExcludeIds)
        ExclusionsSource = $ExclusionsSource
        IncludeUnknown  = [bool]$IncludeUnknown
        InstallVCRuntime = -not [bool]$NoVCRuntime
        MinIntervalDays = $MinIntervalDays
        ScheduleDay     = $DayOfWeek
        ScheduleTime    = $Time
        InstallTimeoutMinutes = $InstallTimeoutMinutes
        Replace         = $ReplaceRules
        ComputerExcludeIds = $ComputerExcludeIds
        ShowResults     = $ShowResultsCfg
        ShowResultsSwitch = [bool]$ShowResults
        UserTask        = (-not [bool]$NoUserTask) -and ($UserTaskCfg -ne $false)
        UserTaskConfig  = $UserTaskCfg
    } | ConvertTo-Json -Depth 5 | Set-Content -Path (Join-Path $Folder 'config.json') -Encoding UTF8
}

function Set-LockedAcl([string]$Path) {
    # SIDs instead of names so this works on any display language:
    # SYSTEM and Administrators full control, Users read and execute
    & icacls.exe $Path /inheritance:r /grant:r '*S-1-5-18:(OI)(CI)F' '*S-1-5-32-544:(OI)(CI)F' '*S-1-5-32-545:(OI)(CI)RX' | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "icacls failed on $Path (exit $LASTEXITCODE)" }
}

# Exclusions for this computer only. In the data folder (Users can read, only SYSTEM and
# Administrators can change), so both tasks can read it and the file survives reinstall and uninstall.
$LocalConfigFile = Join-Path $DataDir 'local-config.json'
function Get-LocalExclusions {
    $r = @{ Exists = $false; Ids = @(); Problem = $null }
    if (-not (Test-Path -LiteralPath $LocalConfigFile -PathType Leaf)) { return $r }
    $r.Exists = $true
    try { $raw = Get-Content -LiteralPath $LocalConfigFile -Raw -Encoding UTF8 -ErrorAction Stop } catch { $r.Problem = "cannot be read ($($_.Exception.Message))"; return $r }
    if (-not "$raw".Trim()) { $r.Problem = 'is empty'; return $r }
    try { $j = $raw | ConvertFrom-Json -ErrorAction Stop } catch { $r.Problem = 'is not valid JSON'; return $r }
    if (($j -isnot [Management.Automation.PSCustomObject]) -or (@($j.PSObject.Properties.Name) -notcontains 'ExcludeIds')) { $r.Problem = 'has no ExcludeIds list'; return $r }
    $ids = @($j.ExcludeIds | ForEach-Object { "$_".Trim() } | Where-Object { $_ })
    $bad = @($ids | Where-Object { $_ -notmatch $IdRegex })
    if ($bad.Count) { $r.Problem = 'contains invalid winget IDs: ' + ($bad -join ' | '); return $r }
    $seen = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    $r.Ids = @($ids | Where-Object { $seen.Add($_) })
    return $r
}

function Set-LocalExclusions {
    $current = Get-LocalExclusions
    if ($current.Problem) { throw "$LocalConfigFile $($current.Problem). Correct it, or delete it and add the exclusions again." }
    # -File passes "A.B,C.D" as one string, so split on commas as well
    $split = { param($v) @($v | ForEach-Object { "$_" -split '[,;\s]+' } | ForEach-Object { $_.Trim() } | Where-Object { $_ }) }
    $add    = & $split $AddLocalExclusion
    $remove = & $split $RemoveLocalExclusion
    $bad = @(@($add) + @($remove) | Where-Object { $_ -notmatch $IdRegex })
    if ($bad.Count) { throw "Invalid winget IDs: $($bad -join ' | '). Use the Id column of 'winget list'." }
    $list = New-Object System.Collections.Generic.List[string]
    foreach ($id in $current.Ids) { $list.Add($id) }
    foreach ($id in $remove) {
        $hit = @($list | Where-Object { $_ -eq $id })   # -eq ignores case, like winget
        if ($hit.Count) { foreach ($h in $hit) { [void]$list.Remove($h) }; Write-Output "Local exclusion removed: $($hit[0])" }
        else { Write-Output "Not in the local exclusions of this computer: $id" }
    }
    foreach ($id in $add) {
        if (@($list | Where-Object { $_ -eq $id }).Count) { Write-Output "Already excluded on this computer: $id" }
        else { $list.Add($id); Write-Output "Local exclusion added: $id" }
    }
    New-Item -ItemType Directory -Path $DataDir -Force | Out-Null
    Set-LockedAcl $DataDir
    if ($list.Count) {
        [ordered]@{
            Comment    = "Exclusions for $env:COMPUTERNAME only, on top of config.json. Change them with Install-KeepItUpToDater.ps1 -AddLocalExclusion / -RemoveLocalExclusion."
            ExcludeIds = @($list)
        } | ConvertTo-Json | Set-Content -LiteralPath $LocalConfigFile -Encoding UTF8
        # The updater only uses this file when SYSTEM or Administrators own it
        & icacls.exe $LocalConfigFile /setowner '*S-1-5-32-544' | Out-Null
        if ($LASTEXITCODE -ne 0) { throw "icacls could not set the owner of $LocalConfigFile (exit $LASTEXITCODE)" }
        Write-Output "Local exclusions on ${env:COMPUTERNAME}: $($list -join ', ')"
    } else {
        Remove-Item -LiteralPath $LocalConfigFile -Force -ErrorAction SilentlyContinue
        Write-Output "No local exclusions left on $env:COMPUTERNAME; $LocalConfigFile removed."
    }
    Write-Output 'Both scheduled tasks use this from their next run. Nothing else was changed.'
}

function Write-LocalStatus {
    $local = Get-LocalExclusions
    if ($local.Problem) { Write-Output "            this computer, local-config.json: ERROR, $LocalConfigFile $($local.Problem); the updater stops until this is fixed" }
    elseif ($local.Ids.Count) { Write-Output ("            this computer, local-config.json: " + ($local.Ids -join ', ') + " ($LocalConfigFile)") }
    else { Write-Output '            this computer, local-config.json: none' }
}

function Get-PolicyBlocks {
    # AppLocker blocks of PowerShell or of this tool in the last 14 days (events 8004 and 8007).
    # The path in the event text is the same in every display language. Needs admin rights.
    $r = @()
    foreach ($logName in @('Microsoft-Windows-AppLocker/EXE and DLL', 'Microsoft-Windows-AppLocker/MSI and Script')) {
        try {
            $r += @(Get-WinEvent -FilterHashtable @{ LogName = $logName; Id = 8004, 8007; StartTime = (Get-Date).AddDays(-14) } -MaxEvents 500 -ErrorAction Stop |
                    Where-Object { "$($_.Message)" -match 'powershell\.exe|KeepItUpToDater' })
        } catch { }
    }
    return $r
}

function Write-PolicyBlocks([bool]$UserTaskOn) {
    $b = @(Get-PolicyBlocks)
    if (-not $b.Count) { return }
    $lastBlock = ($b | Sort-Object TimeCreated -Descending | Select-Object -First 1).TimeCreated.ToString('yyyy-MM-dd HH:mm')
    $who = @($b | ForEach-Object { $sid = $_.UserId; try { $sid.Translate([Security.Principal.NTAccount]).Value } catch { "$sid" } } | Sort-Object -Unique)
    Write-Output "Policy      AppLocker blocked PowerShell or this tool $($b.Count) times in the last 14 days (last $lastBlock; for $($who -join ', '))."
    if ($UserTaskOn) {
        Write-Output '            The User task cannot run for those users: turn it off with "UserTask": false in config.json (or -NoUserTask).'
    }
    Write-Output '            The result messages do not need this: the System task shows them.'
}

function Show-Status {
    # Read-only overview that does not need the Task Scheduler console (it can be blocked by policy)
    $isAdmin = Test-Admin
    $taskNames = if ($script:StatusTaskNames) { $script:StatusTaskNames } else { @('System', 'User', 'Notify') }
    Write-Output "$DisplayName status on $env:COMPUTERNAME, $(Get-Date -Format 'yyyy-MM-dd HH:mm') ($(if ($isAdmin) { 'administrator' } else { "user $env:USERNAME, not elevated" }))"
    Write-Output ''
    $runner = Join-Path $InstallDir $RunnerName
    if (-not (Test-Path -LiteralPath $runner)) {
        Write-Output "Not installed: $runner not found."
        Write-Output "Install log, if an install was attempted: $(Join-Path $DataDir 'install.log')"
        if (Test-Path -LiteralPath $LocalConfigFile) { Write-Output 'Kept for a new install:'; Write-LocalStatus }
        return
    }
    $cfg = $null
    try { $cfg = Get-Content -LiteralPath (Join-Path $InstallDir 'config.json') -Raw | ConvertFrom-Json } catch { }
    $ids = @($cfg.ExcludeIds | Where-Object { $_ })
    Write-Output "Installed   $InstallDir (version $($cfg.Version))"
    Write-Output ("Exclusions  all computers: " + $(if ($ids.Count) { $ids -join ', ' } else { 'none' }))
    $mine = @()
    if ($cfg.ComputerExcludeIds -is [Management.Automation.PSCustomObject]) {
        $mine = @($cfg.ComputerExcludeIds.PSObject.Properties | Where-Object { $_.Name -eq $env:COMPUTERNAME } | ForEach-Object { @($_.Value) } | Where-Object { $_ })
    }
    Write-Output ("            this computer, config.json: " + $(if ($mine.Count) { $mine -join ', ' } else { 'none' }))
    Write-LocalStatus
    if ($cfg.Replace -is [Management.Automation.PSCustomObject] -and @($cfg.Replace.PSObject.Properties).Count) {
        Write-Output ("Replace     " + (@($cfg.Replace.PSObject.Properties | ForEach-Object { "$($_.Name) -> $($_.Value)" }) -join ', '))
    }
    if ($cfg.ExclusionsSource) { Write-Output "            read at every run from $($cfg.ExclusionsSource)" }
    $sr = $cfg.ShowResults
    $srText = if ($cfg.ShowResultsSwitch) { 'on (installer -ShowResults)' }
              elseif ($sr -is [bool]) { $(if ($sr) { 'on (config.json)' } else { 'off (config.json)' }) }
              elseif ($null -ne $sr) { $(if (@($sr | Where-Object { "$_" -eq $env:COMPUTERNAME }).Count) { "on for this computer (config.json: $(@($sr) -join ', '))" } else { "off for this computer (config.json: $(@($sr) -join ', '))" }) }
              else { 'off (silent)' }
    Write-Output "Messages    $srText"
    $tf = Join-Path $DataDir 'testrun'
    if (Test-Path -LiteralPath $tf) {
        $ta = "$(Get-Content -LiteralPath $tf -Raw -ErrorAction SilentlyContinue)".Trim()
        try { $ta = ([datetime]::Parse($ta, [Globalization.CultureInfo]::InvariantCulture)).ToString('yyyy-MM-dd HH:mm') } catch { }
        Write-Output ("Test start  " + $(if ($cfg.UserTask -eq $false) { 'System task' } else { 'both tasks' }) + " at $ta (-TestSchedule); compare with the last run below")
    }
    Write-Output ''
    Write-Output "Scheduled tasks (Task Scheduler folder $TaskPath, not the root folder):"
    # Task Scheduler result codes, plus the updater's own exit code 1
    $meaning = @{ '0x00000000' = 'completed'; '0x00041300' = 'ready'; '0x00041301' = 'running now'; '0x00041303' = 'has not run yet';
                  '0x00041306' = 'stopped before it finished'; '0x8004131F' = 'an instance was already running';
                  '0x00000001' = 'run stopped early, see the log';
                  '0x800704EC' = 'blocked by policy, see Policy below'; '0x000004EC' = 'blocked by policy, see Policy below' }
    foreach ($t in $taskNames) {
        $task = Get-ScheduledTask -TaskPath $TaskPath -TaskName $t -ErrorAction SilentlyContinue
        if (-not $task -and $t -eq 'User' -and $cfg.UserTask -eq $false) {
            Write-Output ("  {0,-7} off (`"UserTask`": false or -NoUserTask): apps in a user's own profile are not updated" -f $t)
            continue
        }
        if (-not $task) {
            if (-not $isAdmin) { Write-Output ("  {0,-7} not visible to this account; run Status.cmd as administrator" -f $t) }
            else { Write-Output ("  {0,-7} NOT FOUND: run the installer again" -f $t) }
            continue
        }
        $info = $task | Get-ScheduledTaskInfo -ErrorAction SilentlyContinue
        $last = if ($info -and $info.LastRunTime -and $info.LastRunTime.Year -gt 2000) { $info.LastRunTime.ToString('yyyy-MM-dd HH:mm') } else { 'never' }
        $next = if ($info -and $info.NextRunTime) { $info.NextRunTime.ToString('yyyy-MM-dd HH:mm') } else { 'at the next startup or sign-in' }
        $hex = '0x{0:X8}' -f $(if ($info) { [uint32]$info.LastTaskResult } else { [uint32]0 })
        $text = if ($meaning.ContainsKey($hex)) { $meaning[$hex] } else { 'see the log' }
        Write-Output ("  {0,-7} {1,-8} last run {2}, result {3} ({4}); next weekly run {5}" -f $t, $task.State, $last, $hex, $text, $next)
    }
    if ($isAdmin) { Write-PolicyBlocks ($cfg.UserTask -ne $false) }
    # A run in progress, or one that was stopped before its summary
    $markers = [ordered]@{ System = (Join-Path $DataDir 'system.running'); User = (Join-Path (Join-Path $env:LOCALAPPDATA $Name) 'user.running') }
    foreach ($k in $markers.Keys) {
        if (-not (Test-Path -LiteralPath $markers[$k])) { continue }
        $m = @("$(Get-Content -LiteralPath $markers[$k] -Raw -ErrorAction SilentlyContinue)".Trim() -split '\|')
        $when = $m[0]
        try { $when = ([datetime]::Parse($m[0], [Globalization.CultureInfo]::InvariantCulture)).ToString('yyyy-MM-dd HH:mm') } catch { }
        $busy = if ($m.Count -ge 3 -and $m[2]) { ", last busy with $($m[2])" } else { '' }
        Write-Output "  $k run started $when$busy has no summary yet: it is running now, or it was stopped (the next run reports that)."
    }
    Write-Output ''
    Write-Output 'Logs (last line):'
    $logs = [ordered]@{ 'install.log' = (Join-Path $DataDir 'install.log'); 'system.log' = (Join-Path $DataDir 'system.log');
                        'notify.log' = (Join-Path $DataDir 'notify.log'); 'user.log' = (Join-Path $env:LOCALAPPDATA "$Name\user.log") }
    foreach ($k in $logs.Keys) {
        $f = $logs[$k]
        if (Test-Path -LiteralPath $f) {
            $tail = Get-Content -LiteralPath $f -Tail 1 -ErrorAction SilentlyContinue
            Write-Output ("  {0,-11} {1}" -f $k, $f)
            Write-Output ("              {0}" -f "$tail".Trim())
        } else {
            Write-Output ("  {0,-11} {1} (not there yet)" -f $k, $f)
        }
    }
    # Get-WinEvent throws a terminating error when the event source is not registered on this PC
    $events = @()
    try { $events = @(Get-WinEvent -FilterHashtable @{ LogName = 'Application'; ProviderName = $Name } -MaxEvents 3 -ErrorAction Stop) } catch { }
    if ($events.Count) {
        Write-Output ''
        Write-Output 'Latest run summaries (Application event log):'
        foreach ($e in $events) { Write-Output ("  {0}  {1}  {2}" -f $e.TimeCreated.ToString('yyyy-MM-dd HH:mm'), $e.Id, ("$($e.Message)" -replace '\s+', ' ')) }
    }
    Write-Output ''
    Write-Output 'Start a run without the Task Scheduler console:'
    Write-Output '  System task (as administrator):  schtasks /run /tn "\KeepItUpToDater\System"'
    if ($cfg.UserTask -ne $false) { Write-Output "  User task (as the signed-in user): powershell -ExecutionPolicy Bypass -File `"$runner`" -Mode User -Force" }
    if ($cfg.ScheduleDay -and $cfg.ScheduleTime) {
        Write-Output "  A System start is skipped when a run already finished this week (from two days before $($cfg.ScheduleDay) $($cfg.ScheduleTime))."
    } else {
        Write-Output '  A System start is skipped when the last completed run is under 6 days old (config.json has no schedule).'
    }
    if ([int]$cfg.MinIntervalDays -gt 0) { Write-Output "  MinIntervalDays: at least $([int]$cfg.MinIntervalDays) days between two runs." }
    Write-Output "  To run it anyway: run the installer with -RunNow, or delete $(Join-Path $DataDir 'system.lastrun') first (as administrator)."
}

function Invoke-Uninstall {
    Get-ScheduledTask -TaskPath $TaskPath -ErrorAction SilentlyContinue | Unregister-ScheduledTask -Confirm:$false
    try {
        $svc = New-Object -ComObject Schedule.Service
        $svc.Connect()
        $svc.GetFolder('\').DeleteFolder($Name, 0)
    } catch { }
    if (Test-Path $InstallDir) { Remove-Item -Path $InstallDir -Recurse -Force }
    if ([Diagnostics.EventLog]::SourceExists($Name)) { Remove-EventLog -Source $Name }
    Write-Output "$DisplayName removed. Logs kept in $DataDir"
    if (Test-Path -LiteralPath $LocalConfigFile) { Write-Output "Local exclusions kept in $LocalConfigFile; they apply again after a new install." }
}

function Invoke-Install {
    New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null
    Set-LockedAcl $InstallDir
    Set-LockedAcl $DataDir
    Save-Runner $InstallDir
    Save-Config $InstallDir

    if (-not [Diagnostics.EventLog]::SourceExists($Name)) { New-EventLog -LogName Application -Source $Name }

    $runner = Join-Path $InstallDir $RunnerName
    # Stored as text in the task, so System32 is right even from a 32-bit host
    $psExe  = Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $psArgs = "-NoProfile -NonInteractive -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$runner`""

    $settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
        -RunOnlyIfNetworkAvailable -MultipleInstances IgnoreNew -ExecutionTimeLimit (New-TimeSpan -Hours 3)

    $weekly = New-ScheduledTaskTrigger -Weekly -DaysOfWeek $DayOfWeek -At $Time
    if ($RandomDelayMinutes -gt 0) { $weekly.RandomDelay = 'PT{0}M' -f $RandomDelayMinutes }
    # -TestSchedule: one extra start of both tasks through Task Scheduler, a few minutes from now
    $testTriggers = @()
    $testFile = Join-Path $DataDir 'testrun'
    if ($TestSchedule -gt 0) {
        $testAt = (Get-Date).AddMinutes($TestSchedule)
        $testAt = $testAt.AddSeconds(-$testAt.Second).AddMilliseconds(-$testAt.Millisecond)
        $testTriggers = @(New-ScheduledTaskTrigger -Once -At $testAt)
        Set-Content -LiteralPath $testFile -Value $testAt.ToString('o') -Encoding ascii
    } else {
        Remove-Item -LiteralPath $testFile -Force -ErrorAction SilentlyContinue
    }

    # SYSTEM task: machine-wide apps
    $boot = New-ScheduledTaskTrigger -AtStartup
    $boot.Delay = 'PT15M'
    Register-ScheduledTask -TaskPath $TaskPath -TaskName 'System' -Force `
        -Description "${Organization} ${DisplayName}: updates machine-wide apps with winget. Weekly, plus after startup when a run was missed." `
        -Action (New-ScheduledTaskAction -Execute $psExe -Argument "$psArgs -Mode System") `
        -Trigger @(@($weekly, $boot) + $testTriggers) `
        -Principal (New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Highest) `
        -Settings $settings | Out-Null
    Write-Output "Task $($TaskPath)System registered: $DayOfWeek $Time (+ up to $RandomDelayMinutes min random delay), and 15 min after startup if missed."

    # User task: apps in each user's profile, runs without elevation. Not where PowerShell is
    # blocked for users ("UserTask": false or -NoUserTask): it could not start there.
    $userTaskOn = (-not $NoUserTask) -and ($UserTaskCfg -ne $false)
    if (-not $userTaskOn) {
        Get-ScheduledTask -TaskPath $TaskPath -TaskName 'User' -ErrorAction SilentlyContinue | Unregister-ScheduledTask -Confirm:$false
        Write-Output ("Task $($TaskPath)User not registered (" + $(if ($NoUserTask) { '-NoUserTask' } else { '"UserTask": false in config.json' }) + "): apps in a user's own profile are not updated.")
    } else {
        $logon = New-ScheduledTaskTrigger -AtLogOn
        $logon.Delay = 'PT15M'
        if ([Environment]::OSVersion.Version.Build -ge 19041) {
            # conhost --headless runs PowerShell without flashing a console window at the user
            $userAction = New-ScheduledTaskAction -Execute (Join-Path $env:WINDIR 'System32\conhost.exe') -Argument "--headless `"$psExe`" $psArgs -Mode User"
        } else {
            $userAction = New-ScheduledTaskAction -Execute $psExe -Argument "$psArgs -Mode User"
        }
        Register-ScheduledTask -TaskPath $TaskPath -TaskName 'User' -Force `
            -Description "${Organization} ${DisplayName}: updates apps installed in the signed-in user's profile. Runs without admin rights." `
            -Action $userAction `
            -Trigger @(@($weekly, $logon) + $testTriggers) `
            -Principal (New-ScheduledTaskPrincipal -GroupId 'S-1-5-11' -RunLevel Limited) `
            -Settings $settings | Out-Null
        Write-Output "Task $($TaskPath)User registered: same weekly schedule, and 15 min after logon if missed."
    }

    # Notify task: as SYSTEM, one minute after each sign-in. Gives who signs in the message about a
    # System run that is busy or that finished less than 12 hours ago, if they did not get it yet.
    # SYSTEM shows it through the Windows message service, so nothing runs in the user's account.
    $signIn = New-ScheduledTaskTrigger -AtLogOn
    $signIn.Delay = 'PT1M'
    Register-ScheduledTask -TaskPath $TaskPath -TaskName 'Notify' -Force `
        -Description "${Organization} ${DisplayName}: at sign-in, shows the user the last result of the System task (only with ShowResults on)." `
        -Action (New-ScheduledTaskAction -Execute $psExe -Argument "$psArgs -Mode Notify -For System") -Trigger @($signIn) `
        -Principal (New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Highest) `
        -Settings (New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -MultipleInstances Queue -ExecutionTimeLimit (New-TimeSpan -Minutes 10)) | Out-Null
    $messagesOn = $ShowResults -or ($ShowResultsCfg -eq $true) -or (@($ShowResultsCfg | Where-Object { "$_" -eq $env:COMPUTERNAME }).Count -gt 0)
    Write-Output ("Task $($TaskPath)Notify registered: at sign-in, the last result for who signs in (" + $(if ($messagesOn) { 'messages on for this computer' } else { 'messages off; turn them on with -ShowResults or "ShowResults" in config.json' }) + ').')
    if ($TestSchedule -gt 0) {
        $which = if ($userTaskOn) { 'both tasks start by themselves' } else { 'the System task starts by itself' }
        Write-Output "Test schedule: $which at $($testAt.ToString('HH:mm')) (in $TestSchedule minutes); that run ignores the once-per-week rule."
        Write-Output ("  Check it afterwards with Status.cmd (last run) or in system.log" + $(if ($userTaskOn) { ' and user.log' } else { '' }) + ": `"Started by the test schedule`".")
        if ($RunNow) { Write-Warning 'With -RunNow, the System run that starts now can still be busy at the test time; Task Scheduler then skips the test start.' }
    }

    if ($userTaskOn) {
        # AppLocker blocked PowerShell for users recently: the User task cannot start for them
        $pb = @(Write-PolicyBlocks $true)
        if ($pb.Count) { foreach ($l in $pb) { Write-Warning "$l".Trim() } }
    }
    if ($RunNow) {
        # A running instance keeps running after the task is registered again, and a new start is ignored
        $sysTask = Get-ScheduledTask -TaskPath $TaskPath -TaskName 'System' -ErrorAction SilentlyContinue
        if ($sysTask -and "$($sysTask.State)" -eq 'Running') {
            Write-Output "SYSTEM task is still running from an earlier start, so it was not started again. To end that run: schtasks /end /tn `"$($TaskPath)System`""
        } else {
            # The updater deletes this file and skips the once-per-week check once, so -RunNow always runs
            Set-Content -LiteralPath (Join-Path $DataDir 'system.runnow') -Value (Get-Date).ToString('o') -Encoding ascii
            Start-ScheduledTask -TaskPath $TaskPath -TaskName 'System'
            Write-Output "SYSTEM task started (runs even if this week's run already finished). Log: $(Join-Path $DataDir 'system.log')"
        }
    }
    Write-Output "Logs in $DataDir. Status of both tasks without the Task Scheduler console: Status.cmd (as administrator)."
    Write-Output "$DisplayName $ToolVersion installed in $InstallDir"
}

# ---- Main -------------------------------------------------------------------------------

if ($ExportRunner) {
    New-Item -ItemType Directory -Path $ExportRunner -Force | Out-Null
    Save-Runner $ExportRunner
    Write-Output "Exported $RunnerName to $ExportRunner"
    exit 0
}

if ($Status) {
    Show-Status
    exit 0
}

if (-not (Test-Admin)) {
    Write-Warning 'Run this installer as administrator or as SYSTEM.'
    exit 1
}

New-Item -ItemType Directory -Path $DataDir -Force | Out-Null
$transcript = $false
try { Start-Transcript -Path (Join-Path $DataDir 'install.log') -Append | Out-Null; $transcript = $true } catch { }

$exitCode = 0
try {
    if ($AddLocalExclusion -or $RemoveLocalExclusion) { Set-LocalExclusions }
    elseif ($Uninstall) { Invoke-Uninstall }
    else { Read-Exclusions; Invoke-Install }
} catch {
    Write-Warning "$DisplayName install failed: $($_.Exception.Message)"
    $exitCode = 2
} finally {
    if ($transcript) { Stop-Transcript | Out-Null }
}
exit $exitCode
