# Keep It Up To Dater 1.5.1: self-update from NETLOGON.
# Runs as a standard user next to the installer, stub.ps1 and test.ps1 (for New-TestRunner).
# A folder stands in for NETLOGON; a fake installer there records how it was called and sets the
# installed version, so nothing is installed on this computer.
$ErrorActionPreference = 'Continue'
$d = $PSScriptRoot
$tok = $null; $err = $null
$tast = [Management.Automation.Language.Parser]::ParseFile("$d\test.ps1", [ref]$tok, [ref]$err)
function TFn([string]$name) { ($tast.FindAll({ param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq $name }, $true) | Select-Object -First 1).Extent.Text }
''; '######## Setup: exported updater with the test patches'
$data = Join-Path $d 'data151'; $localDir = Join-Path $d 'local151'; $nl = Join-Path $d 'netlogon151'; $exp = Join-Path $d 'export151'
$me = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
foreach ($x in $data, $localDir, $nl) { if (Test-Path $x) { Remove-Item $x -Recurse -Force }; New-Item -ItemType Directory $x -Force | Out-Null }
. ([scriptblock]::Create((TFn 'New-TestRunner')))
New-TestRunner "$d\Install-KeepItUpToDater.ps1" $exp
$env:KIUTD_STATE = Join-Path $data 'state.txt'
$instLog = Join-Path $d 'fakeinst151.log'

function New-FakeInstaller([string]$Version, [int]$Exit = 0, [switch]$NoVersionChange, [switch]$NoVersionLine) {
    $verLine = if ($NoVersionLine) { '# no version here' } else { "`$ToolVersion  = '$Version'" }
    $body = @"
param([string]`$DayOfWeek, [string]`$Time, [string]`$ConfigFile, [int]`$MinIntervalDays, [int]`$InstallTimeoutMinutes, [int]`$RandomDelayMinutes,
      [switch]`$IncludeUnknown, [switch]`$NoVCRuntime, [switch]`$ShowResults, [switch]`$UseProxy, [int]`$MaxRunHours = -1, [switch]`$NoUserTask)
$verLine
`$a = @(foreach (`$k in `$PSBoundParameters.Keys) { if (`$PSBoundParameters[`$k] -is [switch]) { "-`$k" } else { "-`$k `$(`$PSBoundParameters[`$k])" } })
Add-Content -LiteralPath '$instLog' -Value ("FAKE INSTALLER $Version ran from `$PSScriptRoot with: " + (`$a -join ' '))
'Installing Keep It Up To Dater $Version (fake)'
if ($Exit -ne 0) { exit $Exit }
if ('$NoVersionChange' -ne 'True') {
    `$c = Get-Content '$exp\config.json' -Raw | ConvertFrom-Json
    `$c.Version = '$Version'
    `$c | ConvertTo-Json -Depth 5 | Set-Content '$exp\config.json' -Encoding UTF8
}
exit 0
"@
    Set-Content (Join-Path $nl 'Install-KeepItUpToDater.ps1') $body -Encoding UTF8
}

function UCase([string]$title, [string]$installed, [string]$nlCfg = '{ "ExcludeIds": [] }', [string[]]$extra = @('-Force'), [switch]$KeepData) {
    ''; "--- $title"
    if (-not $KeepData) { Remove-Item "$data\*" -Recurse -Force -ErrorAction SilentlyContinue }
    Remove-Item $instLog -ErrorAction SilentlyContinue
    Set-Content $env:KIUTD_STATE @('Git.Git|2.40.0')
    Set-Content "$exp\config.json" $installed -Encoding UTF8
    Set-Content "$nl\config.json" $nlCfg -Encoding UTF8
    foreach ($k in 'KIUTD_UPGRADES', 'KIUTD_FAIL', 'KIUTD_UPDATED_FROM') { Set-Item "env:$k" '' }
    $out = @(& powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$exp\run.ps1" -Mode System @extra 2>&1 | ForEach-Object { "$_" })
    $out | Where-Object { $_ -match 'Self-update|self-update|updated itself|installer:|run started|EVENT|Finished' } |
        ForEach-Object { '   ' + ($_ -replace '^\d{4}-\d\d-\d\d \d\d:\d\d:\d\d  ', '' -replace '\d{4}-\d\d-\d\d[ T][\d:.+]+', '<time>') }
    '   exit code: ' + $LASTEXITCODE
    '   installer calls: ' + $(if (Test-Path $instLog) { (@(Get-Content $instLog) -replace [regex]::Escape($d), '<test>') -join ' | ' } else { 'none' })
    '   installed version after: ' + (Get-Content "$exp\config.json" -Raw | ConvertFrom-Json).Version
    '   selfupdate.last: ' + $(if (Test-Path "$data\selfupdate.last") { ((Get-Content "$data\selfupdate.last" -Raw).Trim() -replace '\|.*$', '|<time>') } else { 'none' })
    '   staging folder left: ' + (Test-Path "$data\selfupdate")
}

$base = '"Version": "1.5.1-test", "ExcludeIds": [], "ScheduleDay": "Tuesday", "ScheduleTime": "10:00", "MinIntervalDays": 0, "InstallTimeoutMinutes": 60, "RandomDelayMinutes": 30'
$src = '"ExclusionsSource": "' + ("$nl\config.json" -replace '\\', '\\') + '"'

''; '######## Part SU: self-update from the NETLOGON folder'
New-FakeInstaller '1.5.9'
UCase 'SU1 newer version (1.5.9) next to config.json: installed with this computer''s settings, the run goes on with it, one installer call' "{ $base, $src }"
New-FakeInstaller '1.5.1'
UCase 'SU2 same version on NETLOGON: nothing happens' "{ $base, $src }"
New-FakeInstaller '1.4.8'
UCase 'SU3 older version on NETLOGON: nothing happens' "{ $base, $src }"
New-FakeInstaller '1.5.9' -Exit 2
UCase 'SU4 the new installer fails (exit code 2): warning, this run goes on with 1.5.1, event 1001, exit code 2' "{ $base, $src }"
UCase 'SU5 same day again after the failure: not tried again until tomorrow' "{ $base, $src }" -KeepData
New-FakeInstaller '1.5.9'
UCase 'SU6 "SelfUpdate": false in the NETLOGON config.json: off' "{ $base, $src }" '{ "ExcludeIds": [], "SelfUpdate": false }'
UCase 'SU7 signed mode (TrustedSigners): the unsigned new installer is refused' "{ $base, $src, `"TrustedSigners`": [ `"0123456789ABCDEF0123456789ABCDEF01234567`" ] }"
UCase 'SU8 -ListOnly: no self-update' "{ $base, $src }" -extra @('-ListOnly')
UCase 'SU9 no network config (ExclusionsSource empty): no self-update' "{ $base, `"ExclusionsSource`": `"`" }"
New-FakeInstaller '1.5.9' -NoVersionChange
UCase 'SU10 installer exits 0 but the installed version did not change: warning, run goes on with 1.5.1' "{ $base, $src }"
New-FakeInstaller '1.5.9' -NoVersionLine
UCase 'SU11 installer without a version line: not used' "{ $base, $src }"
New-FakeInstaller '1.5.9'
UCase 'SU12 installed with switches: -ShowResults -UseProxy -NoUserTask -MaxRunHours 0 -IncludeUnknown -NoVCRuntime passed on' "{ $base, $src, `"ShowResultsSwitch`": true, `"UseProxySwitch`": true, `"UserTask`": false, `"UserTaskConfig`": null, `"MaxRunHoursSwitch`": 0, `"IncludeUnknown`": true, `"InstallVCRuntime`": false }"
New-FakeInstaller '1.5.9'
UCase 'SU13 without -Force (weekly start, no run yet this week): the handed-over run is not forced' "{ $base, $src }" -extra @()

''; '######## Part SC: installer reads and saves the new settings'
$cdir = Join-Path $d 'cfg151'
if (Test-Path $cdir) { Remove-Item $cdir -Recurse -Force }; New-Item -ItemType Directory $cdir -Force | Out-Null
$iast = [Management.Automation.Language.Parser]::ParseFile("$d\Install-KeepItUpToDater.ps1", [ref]$tok, [ref]$err)
"installer parse errors: $($err.Count)"
function IFn([string]$name) { ($iast.FindAll({ param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq $name }, $true) | Select-Object -First 1).Extent.Text }
foreach ($a in $iast.EndBlock.Statements) { if ($a -is [Management.Automation.Language.AssignmentStatementAst] -and "$($a.Left)" -match '^\$(IdRegex|NameRegex|ExcludeIds|ReplaceRules|RemoveOlderRules|ComputerExcludeIds|ExclusionsSource|ShowResultsCfg|UserTaskCfg|ProxyCfg|ProxyBypassCfg|UseProxyCfg|MaxRunHoursCfg|SelfUpdateCfg|TrustedSigners|InstallDir|ProgramFilesDir|Name|DisplayName|Organization|ToolVersion)$') { . ([scriptblock]::Create($a.Extent.Text)) } }
foreach ($f in 'Read-Exclusions', 'Save-Config', 'Format-RemoveOlderRules', 'Write-ComputerExclusions', 'Write-UserTaskSetting', 'Get-RunLimitChoice', 'Format-RunHours', 'Write-RunLimitSetting', 'Write-ProxySetting', 'ConvertTo-ScheduleCfg', 'Get-ScheduleSlot', 'Resolve-Schedule') { $t = IFn $f; if ($t) { . ([scriptblock]::Create($t)) } }
$DayOfWeek = 'Tuesday'; $Time = '10:00'; $RandomDelayMinutes = 30; $MinIntervalDays = 0; $InstallTimeoutMinutes = 60; $MaxRunHours = -1
foreach ($c in @(
    @('SC1 "SelfUpdate": false accepted and saved', '{ "ExcludeIds": [], "SelfUpdate": false }'),
    @('SC2 "SelfUpdate": "no" refused', '{ "ExcludeIds": [], "SelfUpdate": "no" }'),
    @('SC3 no SelfUpdate: saved as null (on)', '{ "ExcludeIds": [], "TrustedSigners": [ "0123456789ABCDEF0123456789ABCDEF01234567" ] }'))) {
    ''; "--- $($c[0])"
    Set-Content "$cdir\c.json" $c[1] -Encoding UTF8
    $ConfigFile = "$cdir\c.json"
    try { Read-Exclusions | Out-Null; Save-Config $cdir; $j = Get-Content "$cdir\config.json" -Raw | ConvertFrom-Json
          "   saved: SelfUpdate=$(ConvertTo-Json -InputObject $j.SelfUpdate -Compress) RandomDelayMinutes=$($j.RandomDelayMinutes) TrustedSigners=$(ConvertTo-Json -InputObject @($j.TrustedSigners) -Compress) Version=$($j.Version)" }
    catch { "   REFUSED: $($_.Exception.Message -replace [regex]::Escape($d), '<test>')" }
}
