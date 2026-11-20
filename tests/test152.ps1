# Keep It Up To Dater 1.5.2: weekly start fixed or random per computer ("Schedule", -RandomSchedule).
# Runs as a standard user next to the installer; only the installer's own functions are loaded.
$ErrorActionPreference = 'Continue'
$d = $PSScriptRoot
$tok = $null; $err = $null
$iast = [Management.Automation.Language.Parser]::ParseFile("$d\Install-KeepItUpToDater.ps1", [ref]$tok, [ref]$err)
"installer parse errors: $($err.Count)"
function IFn([string]$name) { ($iast.FindAll({ param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq $name }, $true) | Select-Object -First 1).Extent.Text }
foreach ($a in $iast.EndBlock.Statements) { if ($a -is [Management.Automation.Language.AssignmentStatementAst] -and "$($a.Left)" -match '^\$(IdRegex|NameRegex|ExcludeIds|ReplaceRules|RemoveOlderRules|ComputerExcludeIds|ExclusionsSource|ShowResultsCfg|UserTaskCfg|ProxyCfg|ProxyBypassCfg|UseProxyCfg|MaxRunHoursCfg|SelfUpdateCfg|ScheduleCfg|TrustedSigners|InstallDir|ProgramFilesDir|Name|DisplayName|Organization|ToolVersion)$') { . ([scriptblock]::Create($a.Extent.Text)) } }
foreach ($f in 'Read-Exclusions', 'Save-Config', 'Format-RemoveOlderRules', 'Write-ComputerExclusions', 'Write-UserTaskSetting', 'Get-RunLimitChoice', 'Format-RunHours', 'Write-RunLimitSetting', 'Write-ProxySetting', 'ConvertTo-ScheduleCfg', 'Get-ScheduleSlot', 'Resolve-Schedule') { $t = IFn $f; if ($t) { . ([scriptblock]::Create($t)) } else { "MISSING function $f" } }
$cdir = Join-Path $d 'cfg152'
if (Test-Path $cdir) { Remove-Item $cdir -Recurse -Force }; New-Item -ItemType Directory $cdir -Force | Out-Null
$realName = $env:COMPUTERNAME

function SCase([string]$title, [string]$json, [string]$computer = 'PC042', [hashtable]$params = @{}) {
    ''; "--- $title"
    $script:DayOfWeek = 'Wednesday'; $script:Time = '12:00'; $script:RandomDelayMinutes = 60; $script:RandomDelayGiven = $false; $script:RandomSchedule = $false
    $script:MinIntervalDays = 0; $script:InstallTimeoutMinutes = 60; $script:MaxRunHours = -1
    foreach ($k in $params.Keys) { Set-Variable -Scope Script -Name $k -Value $params[$k] }
    $env:COMPUTERNAME = $computer
    Set-Content "$cdir\c.json" $json -Encoding UTF8
    $script:ConfigFile = "$cdir\c.json"
    try {
        Read-Exclusions | Where-Object { "$_" -match 'Weekly start' } | ForEach-Object { "   $_" }
        Save-Config $cdir
        $j = Get-Content "$cdir\config.json" -Raw | ConvertFrom-Json
        "   task: $($j.ScheduleDay) $($j.ScheduleTime), random delay $($j.RandomDelayMinutes) min; saved Schedule: $(if ($j.Schedule) { $j.Schedule | ConvertTo-Json -Compress } else { 'none' }); RandomScheduleSwitch: $($j.RandomScheduleSwitch)"
    } catch { "   REFUSED: $($_.Exception.Message -replace [regex]::Escape($d), '<test>')" }
    $env:COMPUTERNAME = $realName
}

$base = '"ExcludeIds": []'
''; '######## Part SR: fixed or random weekly start'
SCase 'SR1 no Schedule, no switch: the parameters stay (Wednesday 12:00, delay 60)' "{ $base }"
SCase 'SR2 Fixed in config.json: Tuesday 10:00, the delay of 60 min stays' "{ $base, `"Schedule`": { `"Mode`": `"Fixed`", `"Day`": `"Tuesday`", `"Time`": `"10:00`" } }"
SCase 'SR3 Fixed without Mode (Day and Time given)' "{ $base, `"Schedule`": { `"Day`": `"Friday`", `"Time`": `"09:30`" } }"
SCase 'SR4 Random weekdays 09:00-14:30 for PC042: slot from the name, delay 0' "{ $base, `"Schedule`": { `"Mode`": `"Random`", `"Days`": `"Weekdays`", `"From`": `"09:00`", `"To`": `"14:30`" } }"
SCase 'SR5 same config, same computer again: same slot' "{ $base, `"Schedule`": { `"Mode`": `"Random`", `"Days`": `"Weekdays`", `"From`": `"09:00`", `"To`": `"14:30`" } }"
SCase 'SR6 same config, other computer (PC025): other slot' "{ $base, `"Schedule`": { `"Mode`": `"Random`", `"Days`": `"Weekdays`", `"From`": `"09:00`", `"To`": `"14:30`" } }" 'PC025'
SCase 'SR7 Random without Mode, Days or times: Monday to Friday 09:00-14:30' "{ $base, `"Schedule`": { `"Mode`": `"Random`" } }"
SCase 'SR8 Random on Monday and Wednesday only' "{ $base, `"Schedule`": { `"Mode`": `"Random`", `"Days`": [ `"Wednesday`", `"Monday`" ], `"From`": `"10:00`", `"To`": `"11:00`" } }"
SCase 'SR9 -RandomSchedule without Schedule in config.json: weekdays 09:00-14:30' "{ $base }" 'PC042' @{ RandomSchedule = $true }
SCase 'SR10 -RandomSchedule and a Fixed Schedule in config.json: config.json wins' "{ $base, `"Schedule`": { `"Mode`": `"Fixed`", `"Day`": `"Thursday`", `"Time`": `"08:15`" } }" 'PC042' @{ RandomSchedule = $true }
SCase 'SR11 Random with -RandomDelayMinutes 60: slot chosen so the start stays before 14:30' "{ $base, `"Schedule`": { `"Mode`": `"Random`", `"From`": `"13:00`", `"To`": `"14:30`" } }" 'PC042' @{ RandomDelayMinutes = 60; RandomDelayGiven = $true }
SCase 'SR12 invalid Mode' "{ $base, `"Schedule`": { `"Mode`": `"Sometimes`" } }"
SCase 'SR13 invalid day' "{ $base, `"Schedule`": { `"Mode`": `"Random`", `"Days`": [ `"Funday`" ] } }"
SCase 'SR14 invalid time' "{ $base, `"Schedule`": { `"Mode`": `"Random`", `"From`": `"9:00`" } }"
SCase 'SR15 To before From' "{ $base, `"Schedule`": { `"Mode`": `"Random`", `"From`": `"14:30`", `"To`": `"09:00`" } }"
SCase 'SR16 window shorter than the random delay' "{ $base, `"Schedule`": { `"Mode`": `"Random`", `"From`": `"09:00`", `"To`": `"09:30`" } }" 'PC042' @{ RandomDelayMinutes = 60; RandomDelayGiven = $true }
SCase 'SR17 Fixed with a wrong time' "{ $base, `"Schedule`": { `"Mode`": `"Fixed`", `"Day`": `"Tuesday`", `"Time`": `"25:00`" } }"
SCase 'SR18 Schedule is not an object' "{ $base, `"Schedule`": `"Random`" }"

''; '######## Part SD: spread of 600 computer names over Monday to Friday 09:00-14:30'
$cfg = ConvertTo-ScheduleCfg ('{ "Mode": "Random" }' | ConvertFrom-Json) 'test'
$slots = foreach ($i in 1..600) { $n = 'PC{0:000}' -f $i; $s = Get-ScheduleSlot $cfg $n 0; [pscustomobject]@{ Name = $n; Day = $s.Day; Time = $s.Time } }
$byDay = $slots | Group-Object Day | Sort-Object { [int][DayOfWeek]$_.Name } | ForEach-Object { "$($_.Name) $($_.Count)" }
"   per day: $($byDay -join ', ')"
$times = $slots | ForEach-Object { [TimeSpan]::Parse($_.Time) }
"   earliest $(($times | Measure-Object -Minimum).Minimum.ToString('hh\:mm')), latest $(($times | Measure-Object -Maximum).Maximum.ToString('hh\:mm')) (window 09:00-14:30)"
$perHalfHour = $slots | Group-Object { $t = [TimeSpan]::Parse($_.Time); '{0:00}:{1:00}' -f $t.Hours, ([math]::Floor($t.Minutes / 30) * 30) } | Sort-Object Name | ForEach-Object { "$($_.Name)=$($_.Count)" }
"   per half hour (all days): $($perHalfHour -join ' ')"
$sameMinute = ($slots | Group-Object Day, Time | Measure-Object -Property Count -Maximum).Maximum
"   most computers starting in the same minute: $sameMinute"
$again = foreach ($i in 1..600) { $n = 'PC{0:000}' -f $i; (Get-ScheduleSlot $cfg $n 0).Time }
"   same slots on a second pass: $(@(Compare-Object ($slots.Time) $again -SyncWindow 0).Count -eq 0)"
"   lower-case name gives the same slot: $((Get-ScheduleSlot $cfg 'pc025' 0).Time -eq (Get-ScheduleSlot $cfg 'PC025' 0).Time)"
