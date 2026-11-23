# Keep It Up To Dater 1.5.3: -DayOfWeek and -Time on the command line win over "Schedule" in config.json.
# Runs as a standard user next to the installer; only the installer's own functions are loaded.
$ErrorActionPreference = 'Continue'
$d = $PSScriptRoot
$tok = $null; $err = $null
$itext = [IO.File]::ReadAllText("$d\Install-KeepItUpToDater.ps1")
$iast = [Management.Automation.Language.Parser]::ParseFile("$d\Install-KeepItUpToDater.ps1", [ref]$tok, [ref]$err)
"installer parse errors: $($err.Count)"
function IFn([string]$name) { ($iast.FindAll({ param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq $name }, $true) | Select-Object -First 1).Extent.Text }
foreach ($a in $iast.EndBlock.Statements) { if ($a -is [Management.Automation.Language.AssignmentStatementAst] -and "$($a.Left)" -match '^\$(IdRegex|NameRegex|ExcludeIds|ReplaceRules|RemoveOlderRules|ComputerExcludeIds|ExclusionsSource|ShowResultsCfg|UserTaskCfg|ProxyCfg|ProxyBypassCfg|UseProxyCfg|MaxRunHoursCfg|SelfUpdateCfg|ScheduleCfg|TrustedSigners|ProgramFilesDir|Name|DisplayName|Organization|ToolVersion)$') { . ([scriptblock]::Create($a.Extent.Text)) } }
foreach ($f in 'Read-Exclusions', 'Save-Config', 'Format-RemoveOlderRules', 'Write-ComputerExclusions', 'Write-UserTaskSetting', 'Get-RunLimitChoice', 'Format-RunHours', 'Write-RunLimitSetting', 'Write-ProxySetting', 'ConvertTo-ScheduleCfg', 'Get-ScheduleSlot', 'Resolve-Schedule') { $t = IFn $f; if ($t) { . ([scriptblock]::Create($t)) } else { "MISSING function $f" } }
$root = Join-Path $d 'cfg153'
if (Test-Path $root) { Remove-Item $root -Recurse -Force }
$cdir = Join-Path $root 'cfg'; $DataDir = Join-Path $root 'data'; $InstallDir = Join-Path $root 'installed'
foreach ($x in $cdir, "$DataDir\selfupdate", $InstallDir, "$root\gpo") { New-Item -ItemType Directory $x -Force | Out-Null }
# Get-ScheduleGiven looks at the folder the installer runs from: written once into a GPO folder and
# once into the self-update staging folder, so $PSScriptRoot is what it would be in real use
$gfn = IFn 'Get-ScheduleGiven'
if (-not $gfn) { 'MISSING function Get-ScheduleGiven' }
Set-Content "$root\gpo\fn.ps1" $gfn -Encoding UTF8
Set-Content "$DataDir\selfupdate\fn.ps1" $gfn -Encoding UTF8
$realName = $env:COMPUTERNAME
$random = '"Schedule": { "Mode": "Random", "Days": "Weekdays", "From": "09:00", "To": "14:30" }'
$fixed = '"Schedule": { "Mode": "Fixed", "Day": "Thursday", "Time": "08:15" }'
$base = '"ExcludeIds": []'

function TCase([string]$title, [string]$json, [hashtable]$given = @{}, [string]$from = 'gpo', [string]$prev = $null, [string]$computer = 'PC042', [switch]$RandomSchedule) {
    ''; "--- $title"
    # the installer's defaults, then what the command line gave
    $script:DayOfWeek = 'Wednesday'; $script:Time = '12:00'; $script:RandomDelayMinutes = 60; $script:RandomDelayGiven = $false
    $script:RandomSchedule = [bool]$RandomSchedule; $script:MinIntervalDays = 0; $script:InstallTimeoutMinutes = 60; $script:MaxRunHours = -1
    foreach ($k in $given.Keys) { Set-Variable -Scope Script -Name $k -Value $given[$k] }
    $script:ScheduleGiven = $given.ContainsKey('DayOfWeek') -or $given.ContainsKey('Time')
    $script:ScheduleFromParams = $false
    . $(if ($from -eq 'selfupdate') { "$DataDir\selfupdate\fn.ps1" } else { "$root\gpo\fn.ps1" })
    Remove-Item "$InstallDir\config.json" -ErrorAction SilentlyContinue
    if ($null -ne $prev) { Set-Content "$InstallDir\config.json" $prev -Encoding UTF8 }
    $env:COMPUTERNAME = $computer
    Set-Content "$cdir\c.json" $json -Encoding UTF8
    $script:ConfigFile = "$cdir\c.json"
    try {
        Read-Exclusions | Where-Object { "$_" -match 'Weekly start' } | ForEach-Object { "   $_" }
        Save-Config $cdir
        $j = Get-Content "$cdir\config.json" -Raw | ConvertFrom-Json
        "   task: $($j.ScheduleDay) $($j.ScheduleTime), random delay $($j.RandomDelayMinutes) min; ScheduleParams: $($j.ScheduleParams); RandomScheduleSwitch: $($j.RandomScheduleSwitch)"
    } catch { "   REFUSED: $($_.Exception.Message -replace [regex]::Escape($d), '<test>')" }
    $env:COMPUTERNAME = $realName
}

''; '######## Part CL: command line from a GPO or by hand'
TCase 'CL1 -DayOfWeek Tuesday -Time 10:00 with Random in config.json: Tuesday 10:00, Schedule not used' "{ $base, $random }" @{ DayOfWeek = 'Tuesday'; Time = '10:00' }
TCase 'CL2 the same for another computer (PC025): also Tuesday 10:00' "{ $base, $random }" @{ DayOfWeek = 'Tuesday'; Time = '10:00' } -computer 'PC025'
TCase 'CL3 -DayOfWeek Tuesday -Time 10:00 with a Fixed Schedule (Thursday 08:15): Tuesday 10:00' "{ $base, $fixed }" @{ DayOfWeek = 'Tuesday'; Time = '10:00' }
TCase 'CL4 only -Time 10:00 with Random: day is the default (Wednesday), Schedule not used' "{ $base, $random }" @{ Time = '10:00' }
TCase 'CL5 only -DayOfWeek Friday with Random: time is the default (12:00)' "{ $base, $random }" @{ DayOfWeek = 'Friday' }
TCase 'CL6 -DayOfWeek Tuesday -Time 10:00 and -RandomSchedule, no Schedule: Tuesday 10:00' "{ $base }" @{ DayOfWeek = 'Tuesday'; Time = '10:00' } -RandomSchedule
TCase 'CL7 -DayOfWeek -Time with -RandomDelayMinutes 15 and Random: Tuesday 10:00, delay 15' "{ $base, $random }" @{ DayOfWeek = 'Tuesday'; Time = '10:00'; RandomDelayMinutes = 15; RandomDelayGiven = $true }
TCase 'CL8 -DayOfWeek Tuesday -Time 10:00 without Schedule: Tuesday 10:00, as in 1.5.1' "{ $base }" @{ DayOfWeek = 'Tuesday'; Time = '10:00' }
TCase 'CL9 no day or time given, Random in config.json: slot from the name (as 1.5.2)' "{ $base, $random }"
TCase 'CL10 no day or time given, Fixed in config.json: Thursday 08:15 (as 1.5.2)' "{ $base, $fixed }"
TCase 'CL11 no day or time given, -RandomSchedule: slot from the name (as 1.5.2)' "{ $base }" -RandomSchedule
TCase 'CL12 nothing given, no Schedule: Wednesday 12:00 defaults' "{ $base }"
TCase 'CL13 -DayOfWeek -Time given and a wrong Schedule in config.json: still refused (config.json is checked)' "{ $base, `"Schedule`": { `"Mode`": `"Sometimes`" } }" @{ DayOfWeek = 'Tuesday'; Time = '10:00' }

''; '######## Part SU: started by the self-update of an older version (it always passes the saved day and time)'
$p151 = '{ "Version": "1.5.1", "ExcludeIds": [], "ScheduleDay": "Tuesday", "ScheduleTime": "10:00" }'
$p151def = '{ "Version": "1.5.1", "ExcludeIds": [], "ScheduleDay": "Wednesday", "ScheduleTime": "12:00" }'
$p152cfg = '{ "Version": "1.5.2", "ExcludeIds": [], "ScheduleDay": "Monday", "ScheduleTime": "13:07", "Schedule": { "Mode": "Random", "Days": [ "Monday", "Tuesday", "Wednesday", "Thursday", "Friday" ], "From": "09:00", "To": "14:30" }, "RandomScheduleSwitch": false }'
$p152sw = '{ "Version": "1.5.2", "ExcludeIds": [], "ScheduleDay": "Monday", "ScheduleTime": "13:07", "Schedule": null, "RandomScheduleSwitch": true }'
$p152hand = '{ "Version": "1.5.2", "ExcludeIds": [], "ScheduleDay": "Tuesday", "ScheduleTime": "10:00", "Schedule": null, "RandomScheduleSwitch": false }'
$p153yes = '{ "Version": "1.5.3", "ExcludeIds": [], "ScheduleDay": "Tuesday", "ScheduleTime": "10:00", "ScheduleParams": true }'
$p153no = '{ "Version": "1.5.3", "ExcludeIds": [], "ScheduleDay": "Monday", "ScheduleTime": "13:07", "ScheduleParams": false }'
TCase 'SU1 1.5.1 VM installed with -DayOfWeek Tuesday -Time 10:00, Random on NETLOGON: stays Tuesday 10:00' "{ $base, $random }" @{ DayOfWeek = 'Tuesday'; Time = '10:00' } 'selfupdate' $p151
TCase 'SU2 1.5.1 PC installed with the defaults (Wednesday 12:00), Random on NETLOGON: follows Schedule' "{ $base, $random }" @{ DayOfWeek = 'Wednesday'; Time = '12:00' } 'selfupdate' $p151def
TCase 'SU3 1.5.2 PC whose slot came from Schedule: follows Schedule' "{ $base, $random }" @{ DayOfWeek = 'Monday'; Time = '13:07' } 'selfupdate' $p152cfg
TCase 'SU4 1.5.2 PC installed with -RandomSchedule (the old updater passes day, time and the switch): random' "{ $base }" @{ DayOfWeek = 'Monday'; Time = '13:07' } 'selfupdate' $p152sw -RandomSchedule
TCase 'SU5 1.5.2 PC installed with -DayOfWeek Tuesday -Time 10:00 and no Schedule then, Random now: Tuesday 10:00' "{ $base, $random }" @{ DayOfWeek = 'Tuesday'; Time = '10:00' } 'selfupdate' $p152hand
TCase 'SU6 1.5.3 PC with ScheduleParams true: day and time stay' "{ $base, $random }" @{ DayOfWeek = 'Tuesday'; Time = '10:00' } 'selfupdate' $p153yes
TCase 'SU7 1.5.3 PC with ScheduleParams false (day and time passed anyway): follows Schedule' "{ $base, $random }" @{ DayOfWeek = 'Monday'; Time = '13:07' } 'selfupdate' $p153no
TCase 'SU8 installed config.json unreadable: day and time not seen as given by hand, follows Schedule' "{ $base, $random }" @{ DayOfWeek = 'Tuesday'; Time = '10:00' } 'selfupdate' '{ broken'
TCase 'SU9 the same 1.5.1 settings from a GPO folder (not the staging folder): given by hand, Tuesday 10:00' "{ $base, $random }" @{ DayOfWeek = 'Tuesday'; Time = '10:00' } 'gpo' $p151def

''; '######## Part UA: what the 1.5.3 updater passes to a newer installer at its self-update'
$m = [regex]::Match($itext, "(?ms)^    \`$a = @\('-ConfigFile', \`$src\)\r?\n.*?^    if \(\`$cfg\.RandomScheduleSwitch -eq \`$true\) \{ \`$a \+= '-RandomSchedule' \}")
if (-not $m.Success) { 'MISSING: argument block in the updater' }
$argBlock = [scriptblock]::Create($m.Value + "`r`n" + '$a -join '' ''')
$src = '\\contoso.local\NETLOGON\KeepItUpToDater\config.json'
foreach ($c in @(
    @('UA1 installed with -DayOfWeek Tuesday -Time 10:00 (ScheduleParams true): day and time passed', $p153yes),
    @('UA2 day and time from Schedule (ScheduleParams false): not passed, Schedule decides', $p153no),
    @('UA3 installed with -RandomSchedule: only the switch', '{ "ScheduleDay": "Monday", "ScheduleTime": "13:07", "ScheduleParams": false, "RandomScheduleSwitch": true }'))) {
    ''; "--- $($c[0])"
    $cfg = $c[1] | ConvertFrom-Json
    '   arguments: ' + (& $argBlock)
}
