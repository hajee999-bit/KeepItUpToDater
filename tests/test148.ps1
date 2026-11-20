# Keep It Up To Dater 1.4.8: older copies ("RemoveOlder"), 1.4.7 cases plus the "*" rule for every package listed twice.
# Runs as a standard user next to the installer, stub.ps1, fake-un.ps1 and test.ps1 (for New-TestRunner).
$ErrorActionPreference = 'Continue'
$d = $PSScriptRoot
$tok = $null; $err = $null
$ast = [Management.Automation.Language.Parser]::ParseFile("$d\Install-KeepItUpToDater.ps1", [ref]$tok, [ref]$err); "installer parse errors: $($err.Count)"
function Fn([string]$name) { ($ast.FindAll({ param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq $name }, $true) | Select-Object -First 1).Extent.Text }
$tast = [Management.Automation.Language.Parser]::ParseFile("$d\test.ps1", [ref]$tok, [ref]$err)
function TFn([string]$name) { ($tast.FindAll({ param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq $name }, $true) | Select-Object -First 1).Extent.Text }

''; '######## Part RC: "RemoveOlder" in config.json, checked by the installer'
$cdir = Join-Path $d 'cfg148'; if (Test-Path $cdir) { Remove-Item $cdir -Recurse -Force }; New-Item -ItemType Directory $cdir -Force | Out-Null
$inst = Join-Path $cdir 'installed'; New-Item -ItemType Directory $inst -Force | Out-Null
$idRx = ($ast.FindAll({ param($n) $n -is [Management.Automation.Language.AssignmentStatementAst] -and "$($n.Left)" -eq '$IdRegex' }, $true) | Select-Object -First 1).Extent.Text
$nameRx = ($ast.FindAll({ param($n) $n -is [Management.Automation.Language.AssignmentStatementAst] -and "$($n.Left)" -eq '$NameRegex' }, $true) | Select-Object -First 1).Extent.Text
$h = "param([string]`$ConfigFile)`r`n`$DisplayName = 'Keep It Up To Dater'; `$Organization = 'contoso.local'; `$ToolVersion = '1.4.7-test'; `$InstallDir = '$inst'`r`n" +
     "`$ExcludeIds = @(); `$ReplaceRules = [ordered]@{}; `$RemoveOlderRules = [ordered]@{}; `$ExclusionsSource = ''; `$IncludeUnknown = `$false; `$NoVCRuntime = `$false; `$MinIntervalDays = 0; `$DayOfWeek = 'Wednesday'; `$Time = '12:00'; `$ShowResults = `$false; `$ShowResultsCfg = `$null; `$InstallTimeoutMinutes = 60; `$ComputerExcludeIds = [ordered]@{}; `$NoUserTask = `$false; `$UserTaskCfg = `$null; `$UseProxy = `$false; `$ProxyCfg = `$null; `$ProxyBypassCfg = `$null; `$UseProxyCfg = `$null; `$MaxRunHours = -1; `$MaxRunHoursCfg = `$null`r`n" +
     $idRx + "`r`n" + $nameRx + "`r`n" + (Fn 'Write-ComputerExclusions') + "`r`n" + (Fn 'Write-UserTaskSetting') + "`r`n" + (Fn 'Write-ProxySetting') + "`r`n" + (Fn 'Get-RunLimitChoice') + "`r`n" + (Fn 'Format-RunHours') + "`r`n" + (Fn 'Write-RunLimitSetting') + "`r`n" + (Fn 'Format-RemoveOlderRules') + "`r`n" + (Fn 'ConvertTo-ScheduleCfg') + "`r`n" + (Fn 'Get-ScheduleSlot') + "`r`n" + (Fn 'Resolve-Schedule') + "`r`n" + (Fn 'Read-Exclusions') + "`r`n" + (Fn 'Save-Config') + "`r`n" +
     "try { Read-Exclusions | Where-Object { `$_ -match 'Remove older|Replace rules' }; if (`$env:KIUTD_SAVE -eq '1') { Save-Config '$cdir'; 'saved RemoveOlder: ' + ((Get-Content '$cdir\config.json' -Raw | ConvertFrom-Json).RemoveOlder | ConvertTo-Json -Compress) } } catch { 'REFUSED: ' + `$_.Exception.Message }"
Set-Content "$cdir\h.ps1" $h -Encoding UTF8
function RC([string]$title, [string]$json, [string]$file = 'c.json', [switch]$Save) {
    "--- $title"
    if ($json) { Set-Content "$cdir\$file" $json -Encoding UTF8 }
    $env:KIUTD_SAVE = if ($Save) { '1' } else { '0' }
    $cfArg = if ($file -eq 'config.json') { @() } else { @('-ConfigFile', $file) }
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$cdir\h.ps1" @cfArg 2>&1 | ForEach-Object { "   $_" }
}
RC 'RC1 SoapUI with -q, saved' '{ "ExcludeIds": [], "RemoveOlder": { "SmartBear.SoapUI": "-q" } }' -Save
RC 'RC2 empty switches and null: quiet uninstall command only, saved' '{ "ExcludeIds": [], "RemoveOlder": { "SmartBear.SoapUI": "", "Contoso.Tool": null } }' -Save
RC 'RC3 no RemoveOlder key' '{ "ExcludeIds": [] }' -Save
RC 'RC4 empty RemoveOlder' '{ "ExcludeIds": [], "RemoveOlder": {} }'
RC 'RC5 RemoveOlder as a list' '{ "ExcludeIds": [], "RemoveOlder": [ "SmartBear.SoapUI" ] }'
RC 'RC6 app name instead of an ID' '{ "ExcludeIds": [], "RemoveOlder": { "SoapUI": "-q" } }'
RC 'RC7 wildcard ID' '{ "ExcludeIds": [], "RemoveOlder": { "SmartBear.*": "-q" } }'
RC 'RC8 switches with a command separator' '{ "ExcludeIds": [], "RemoveOlder": { "SmartBear.SoapUI": "-q & del C:\\x" } }'
RC 'RC9 switches with quotes' '{ "ExcludeIds": [], "RemoveOlder": { "SmartBear.SoapUI": "-q \"x\"" } }'
RC 'RC10 switches as a number' '{ "ExcludeIds": [], "RemoveOlder": { "SmartBear.SoapUI": 1 } }'
RC 'RC11 switches longer than 100 characters' ('{ "ExcludeIds": [], "RemoveOlder": { "SmartBear.SoapUI": "' + ('-q ' * 34) + '" } }')
RC 'RC12 two rules, MSI style and /S, saved' '{ "ExcludeIds": [], "RemoveOlder": { "SmartBear.SoapUI": "-q", "Contoso.Msi": "/qn /norestart", "Contoso.Nsis": "/S" } }' -Save
Copy-Item "$cdir\config.json" "$inst\config.json"; Remove-Item "$cdir\config.json"
RC 'RC13 config.json missing: installed rules kept, saved' '' 'config.json' -Save
RC 'RC14 "*" with an empty value and SoapUI, saved' '{ "ExcludeIds": [], "RemoveOlder": { "*": "", "SmartBear.SoapUI": "-q" } }' -Save
RC 'RC15 "*" with switches: refused' '{ "ExcludeIds": [], "RemoveOlder": { "*": "/S" } }'
RC 'RC16 "keep" for one ID, saved' '{ "ExcludeIds": [], "RemoveOlder": { "*": "", "Notepad++.Notepad++": "keep" } }' -Save
RC 'RC17 "**" is not an ID: refused' '{ "ExcludeIds": [], "RemoveOlder": { "**": "" } }'

''; '######## Part RU: functions of the updater'
$data = Join-Path $d 'data148'; $localDir = Join-Path $d 'local148'
$me = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
foreach ($x in $data, $localDir) { if (Test-Path $x) { Remove-Item $x -Recurse -Force }; New-Item -ItemType Directory $x -Force | Out-Null }
. ([scriptblock]::Create((TFn 'New-TestRunner')))
New-TestRunner "$d\Install-KeepItUpToDater.ps1" "$d\export148"
$run = Get-Content "$d\export148\run.ps1" -Raw
# The winget stand-in is a script: output that is read must come from its own process
$p147 = @(
    @('$out = @(& $winget list --id $Id', '$out = @(& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $winget list --id $Id'),
    @('$out = @(& $winget list --source winget --scope machine', '$out = @(& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $winget list --source winget --scope machine'),
    @('$list = @(& $winget pin list', '$list = @(& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $winget pin list'),
    @('function Get-UninstallEntries {', "function Get-UninstallEntries {`r`n    if (`$env:KIUTD_ARP -like '*.json') { return @(@((Get-Content `$env:KIUTD_ARP -Raw | ConvertFrom-Json)) | Where-Object { Test-Path -LiteralPath `$_.Path }) }")
)
foreach ($pt in $p147) { if ($run.Contains($pt[0])) { $run = $run.Replace($pt[0], $pt[1]) } else { "PATCH NOT FOUND: $($pt[0])" } }
Set-Content "$d\export148\run.ps1" $run -Encoding UTF8
$rast = [Management.Automation.Language.Parser]::ParseFile("$d\export148\Invoke-KeepItUpToDater.ps1", [ref]$tok, [ref]$err)
function RFn([string]$fn) { ($rast.FindAll({ param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq $fn }, $true) | Select-Object -First 1).Extent.Text }
. ([scriptblock]::Create((($rast.FindAll({ param($n) $n -is [Management.Automation.Language.AssignmentStatementAst] -and "$($n.Left)" -eq '$IdPattern' }, $true) | Select-Object -First 1).Extent.Text)))
foreach ($fn in 'ConvertTo-RemoveOlder', 'Format-RemoveOlder', 'Compare-AppVersion', 'Get-RunMessage') { . ([scriptblock]::Create((RFn $fn))) }
'--- RU1 Compare-AppVersion'
foreach ($c in @(@('5.10.0', '5.9.1'), @('4.6.4', '5.4.0'), @('5.7.1', '5.7.1'), @('1.2', '1.2.0'), @('2.0.0.1', '2.0.0'), @('26276.513.5241.9675', '26288.2004.5269.3420'), @('1.0b', '1.0a'), @('02.09.01.70', '2.8.2.61'))) {
    "   $($c[0]) vs $($c[1]): $(Compare-AppVersion $c[0] $c[1])"
}
'--- RU2 ConvertTo-RemoveOlder (the updater checks config.json again at every run)'
foreach ($j in '{ "SmartBear.SoapUI": "-q" }', '{ "SmartBear.SoapUI": null, "Contoso.Msi": "/qn /norestart" }', '[ "SmartBear.SoapUI" ]', '{ "SoapUI": "-q" }', '{ "SmartBear.SoapUI": "-q | x" }', '{ "SmartBear.SoapUI": 5 }', '{}', '{ "*": "" }', '{ "*": null, "Contoso.App": "keep" }', '{ "*": "-q" }') {
    $r = ConvertTo-RemoveOlder ($j | ConvertFrom-Json)
    "   $j -> " + $(if ($r.Problem) { "PROBLEM: $($r.Problem)" } else { Format-RemoveOlder $r.Rules })
}
''; '######## Part RG: folder, same-folder check and silent uninstall detection (1.4.8)'
foreach ($fn in 'Get-EntryFolder', 'Test-SameFolder', 'Test-FileText', 'Get-SilentUninstall') { . ([scriptblock]::Create((RFn $fn))) }
$tg = Join-Path $d 'rg148'; if (Test-Path $tg) { Remove-Item $tg -Recurse -Force }
foreach ($x in 'inno', 'i4j\.install4j', 'nsis', 'plain') { New-Item -ItemType Directory "$tg\$x" -Force | Out-Null }
[IO.File]::WriteAllText("$tg\inno\unins000.exe", 'MZ inno')
[IO.File]::WriteAllText("$tg\i4j\uninstall.exe", 'MZ install4j')
[IO.File]::WriteAllText("$tg\nsis\uninstall.exe", 'MZ....Nullsoft Install System v3.08....')
[IO.File]::WriteAllText("$tg\plain\uninstall.exe", 'MZ nothing to see')
'--- RG1 Get-EntryFolder'
foreach ($e in @(
    @{ Location = 'C:\Program Files\Notepad++\'; Uninstall = '"C:\Program Files\Notepad++\uninstall.exe"' },
    @{ Location = ''; Uninstall = '"C:\Program Files\Notepad++\uninstall.exe"' },
    @{ Location = ''; Uninstall = 'C:\totalcmd\tcunin64.exe /F' },
    @{ Location = ''; Uninstall = 'MsiExec.exe /X{11111111-2222-3333-4444-555555555555}' },
    @{ Location = ''; Uninstall = '"C:\ProgramData\Package Cache\{x}\setup.exe" /uninstall' },
    @{ Location = ''; Uninstall = '' })) { "   loc '$($e.Location)' un '$($e.Uninstall)' -> '$(Get-EntryFolder ([pscustomobject]$e))'" }
'--- RG2 Test-SameFolder'
foreach ($c in @(@('C:\Program Files\Notepad++', 'c:\program files\notepad++\'), @('C:\totalcmd', 'C:\totalcmd\64'), @('C:\Program Files\SoapUI-5.9.1', 'C:\Program Files\SoapUI-5.10.0'), @('C:\App', 'C:\App2'), @('', 'C:\x'))) { "   '$($c[0])' / '$($c[1])': $(Test-SameFolder $c[0] $c[1])" }
'--- RG3 Get-SilentUninstall'
foreach ($e in @(
    @{ T = 'quiet command'; Key = 'X'; Quiet = '"C:\x\un.exe" /quiet'; Uninstall = '"C:\x\un.exe"'; Sw = '' },
    @{ T = 'rule switches'; Key = 'X'; Quiet = ''; Uninstall = '"C:\x\un.exe"'; Sw = '-q' },
    @{ T = 'MSI by key'; Key = '{11111111-2222-3333-4444-555555555555}'; Quiet = ''; Uninstall = 'MsiExec.exe /I{11111111-2222-3333-4444-555555555555}'; Sw = '' },
    @{ T = 'MSI by command'; Key = 'Contoso'; Quiet = ''; Uninstall = 'MsiExec.exe /X{AAAAAAAA-2222-3333-4444-555555555555}'; Sw = '' },
    @{ T = 'Inno'; Key = 'X_is1'; Quiet = ''; Uninstall = "`"$tg\inno\unins000.exe`""; Sw = '' },
    @{ T = 'install4j'; Key = 'X'; Quiet = ''; Uninstall = "`"$tg\i4j\uninstall.exe`""; Sw = '' },
    @{ T = 'NSIS'; Key = 'X'; Quiet = ''; Uninstall = "`"$tg\nsis\uninstall.exe`""; Sw = '' },
    @{ T = 'unknown type'; Key = 'X'; Quiet = ''; Uninstall = "`"$tg\plain\uninstall.exe`""; Sw = '' },
    @{ T = 'uninstaller missing'; Key = 'X'; Quiet = ''; Uninstall = "`"$tg\gone\uninstall.exe`""; Sw = '' })) {
    $u = Get-SilentUninstall ([pscustomobject]$e) $e.Sw
    "   $($e.T): " + $(if ($u) { "$($u.How) -> $($u.Cmd -replace [regex]::Escape($tg), '<tg>')" } else { 'none' })
}
'--- RU3 result message with older copies removed'
$t0 = Get-Date '2026-11-11 10:30:48'
$st = [pscustomobject]@{ Run = 'r'; Phase = 'done'; Started = $t0.ToString('o'); Ended = $t0.AddMinutes(2).ToString('o'); Updated = @('SoapUI 5.10.0'); Replaced = @(); Removed = @('SoapUI 4.6.4', 'SoapUI 5.5.0', 'SoapUI 5.9.1'); NotUpdated = @(); Restart = @(); Reopen = @(); Error = '' }
$Name = 'KeepItUpToDater'; $sysDir = Join-Path $env:ProgramData $Name; $inv = [Globalization.CultureInfo]::InvariantCulture
(Get-RunMessage 'end' $st 'System').Text -split "`r`n" | ForEach-Object { "   | $_" }
'--- RU4 result message, only older copies removed (nothing updated)'
$st.Updated = @(); $st.Removed = @('SoapUI 5.9.1')
(Get-RunMessage 'end' $st 'System').Text -split "`r`n" | ForEach-Object { "   | $_" }
'--- RU5 status file of 1.4.6 (no Removed): message as before'
$st = [pscustomobject]@{ Run = 'r'; Phase = 'done'; Started = $t0.ToString('o'); Ended = $t0.AddMinutes(2).ToString('o'); Updated = @('SoapUI 5.10.0'); Replaced = @(); NotUpdated = @(); Restart = @(); Reopen = @(); Error = '' }
(Get-RunMessage 'end' $st 'System').Text -split "`r`n" | ForEach-Object { "   | $_" }

''; '######## Part RE: older copies removed by the System run (winget stand-in, test uninstall entries under HKCU)'
$env:KIUTD_STATE = Join-Path $data 'state.txt'
$arpRoot = 'HKCU:\Software\KIUTD-Test148'
$arpFile = Join-Path $data 'arp.json'
function New-Arp([object[]]$entries) {
    if (Test-Path $arpRoot) { Remove-Item $arpRoot -Recurse -Force }
    $out = @()
    $n = 0
    foreach ($e in $entries) {
        $n++
        $key = "$arpRoot\E$n"
        New-Item -Path $key -Force | Out-Null
        $cmd = '"' + (Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe') + '" -NoProfile -ExecutionPolicy Bypass -File "' + "$d\fake-un.ps1" + '" -Key "' + "Registry::HKEY_CURRENT_USER\Software\KIUTD-Test148\E$n" + '" -State "' + $env:KIUTD_STATE + '" -Line "' + $e.Line + '"' + $(if ($e.Extra) { ' ' + $e.Extra } else { '' })
        $out += [ordered]@{ Path = "Registry::HKEY_CURRENT_USER\Software\KIUTD-Test148\E$n"; Key = "E$n"; Name = $e.Name; Version = $e.Version; Location = $(if ($e.ContainsKey('Location')) { $e.Location } else { "C:\Program Files\SmartBear\SoapUI-$($e.Version)" })
                            Uninstall = $(if ($e.Quiet) { '' } elseif ($e.Bad) { $e.Bad } else { $cmd }); Quiet = $(if ($e.Quiet) { $cmd } else { '' }) }
    }
    ConvertTo-Json -InputObject @($out) -Depth 3 | Set-Content $arpFile -Encoding UTF8
}
function ECase([string]$title, [string[]]$installed, [string]$cfgBody, [object[]]$arp, [string]$mode = 'System', [string[]]$extra = @(), [hashtable]$envs = @{}) {
    ''; "--- $title"
    Remove-Item "$data\*" -Recurse -Force -ErrorAction SilentlyContinue
    Set-Content $env:KIUTD_STATE $installed
    New-Arp $arp
    Set-Content "$d\export148\config.json" ('{ "Version": "1.4.7-test", ' + $cfgBody + ' }') -Encoding UTF8
    foreach ($k in 'KIUTD_UPGRADES', 'KIUTD_FAIL', 'KIUTD_LANG', 'KIUTD_PINFAIL', 'KIUTD_SESSIONS') { Set-Item "env:$k" '' }
    $env:KIUTD_ARP = $arpFile
    $env:KIUTD_NAMES = 'SmartBear.SoapUI|4.6.4=SoapUI 4.6.4 4.6.4;SmartBear.SoapUI|5.5.0=SoapUI 5.5.0;SmartBear.SoapUI|5.9.1=SoapUI 5.9.1;SmartBear.SoapUI|5.10.0=SoapUI 5.10.0'
    foreach ($k in $envs.Keys) { Set-Item "env:$k" $envs[$k] }
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$d\export148\run.ps1" -Mode $mode -Force @extra 2>&1 | ForEach-Object { "$_" } |
        Where-Object { $_ -match 'older|Older|Remove|remove|Running:|Would|EVENT|Finished|WARNING|Folder|installed \d|installed more|lifted|pins' } |
        ForEach-Object { '   ' + ($_ -replace '^\d{4}-\d\d-\d\d \d\d:\d\d:\d\d  ', '') }
    '   installed after: ' + (@(Get-Content $env:KIUTD_STATE | Where-Object { $_ }) -join ', ')
    '   uninstall entries left: ' + (@(Get-ChildItem $arpRoot -ErrorAction SilentlyContinue | ForEach-Object { $_.PSChildName }) -join ', ')
    '   uninstallers run: ' + (@(Get-Content "$data\uninstalls.log" -ErrorAction SilentlyContinue) -join ' | ')
    $bk = @(Get-ChildItem "$data\removed-entry-*.reg" -ErrorAction SilentlyContinue); if ($bk.Count) { '   entry backups: ' + (@($bk | ForEach-Object { ($_.Name -replace '-\d{14}', '') + ' ' + $(if ((Get-Content $_.FullName -Raw) -match 'DisplayName') { '(has DisplayName)' } else { '(EMPTY)' }) }) -join ', ') }
    if (Test-Path "$data\system.status.json") { $j = Get-Content "$data\system.status.json" -Raw | ConvertFrom-Json; "   status: removed: $(@($j.Removed) -join '; ')" }
    if (Test-Path "$data\messages.txt") { Get-Content "$data\messages.txt" | Where-Object { $_ -match 'Older copies|^    SoapUI|is done' } | ForEach-Object { "   msg | $_" } }
}
$soap4 = @('SmartBear.SoapUI|4.6.4', 'SmartBear.SoapUI|5.5.0', 'SmartBear.SoapUI|5.9.1', 'SmartBear.SoapUI|5.10.0')
$arp4 = @(
    @{ Line = 'SmartBear.SoapUI|4.6.4'; Name = 'SoapUI 4.6.4 4.6.4'; Version = '4.6.4' },
    @{ Line = 'SmartBear.SoapUI|5.5.0'; Name = 'SoapUI 5.5.0'; Version = '5.5.0' },
    @{ Line = 'SmartBear.SoapUI|5.9.1'; Name = 'SoapUI 5.9.1'; Version = '5.9.1' },
    @{ Line = 'SmartBear.SoapUI|5.10.0'; Name = 'SoapUI 5.10.0'; Version = '5.10.0' })
$ro = '"RemoveOlder": { "SmartBear.SoapUI": "-q" }'
ECase 'RE1 SoapUI 4.6.4, 5.5.0, 5.9.1 and 5.10.0 side by side: the three older ones removed with -q' $soap4 ('"ExcludeIds": [], ' + $ro) $arp4
ECase 'RE2 same, result messages on' $soap4 ('"ExcludeIds": [], "ShowResults": true, ' + $ro) $arp4 -envs @{ KIUTD_SESSIONS = '1=CONTOSO\j.doe' }
ECase 'RE3 no RemoveOlder rule: nothing removed' $soap4 '"ExcludeIds": []' $arp4
ECase 'RE4 SoapUI excluded: nothing removed' $soap4 ('"ExcludeIds": ["SmartBear.SoapUI"], ' + $ro) $arp4
ECase 'RE5 list only: what would be removed' $soap4 ('"ExcludeIds": [], ' + $ro) $arp4 -extra @('-ListOnly')
ECase 'RE6 one copy installed: nothing to remove' @('SmartBear.SoapUI|5.10.0') ('"ExcludeIds": [], ' + $ro) @($arp4[3])
ECase 'RE7 not installed at all' @('Git.Git|2.40.0') ('"ExcludeIds": [], ' + $ro) @()
ECase 'RE8 5.5.0 has no uninstall entry with that name: it is reported, the others are removed' $soap4 ('"ExcludeIds": [], ' + $ro) @($arp4[0], @{ Line = 'SmartBear.SoapUI|5.5.0'; Name = 'Something else'; Version = '5.5.0' }, $arp4[2], $arp4[3])
ECase 'RE9 the uninstaller of 5.9.1 cannot be started: reported, run ends with a warning' $soap4 ('"ExcludeIds": [], ' + $ro) @($arp4[0], $arp4[1], @{ Line = 'SmartBear.SoapUI|5.9.1'; Name = 'SoapUI 5.9.1'; Version = '5.9.1'; Bad = 'C:\Program Files\SmartBear\SoapUI-5.9.1\nope.exe' }, $arp4[3])
ECase 'RE10 entries with their own quiet command and an empty rule: quiet command used, no -q added' $soap4 ('"ExcludeIds": [], "RemoveOlder": { "SmartBear.SoapUI": "" }') @(@{ Line = 'SmartBear.SoapUI|4.6.4'; Name = 'SoapUI 4.6.4 4.6.4'; Version = '4.6.4'; Quiet = $true }, @{ Line = 'SmartBear.SoapUI|5.5.0'; Name = 'SoapUI 5.5.0'; Version = '5.5.0'; Quiet = $true }, $arp4[2], $arp4[3])
ECase 'RE11 two copies of the same version: nothing removed' @('SmartBear.SoapUI|5.10.0', 'SmartBear.SoapUI|5.10.0') ('"ExcludeIds": [], ' + $ro) @($arp4[3])
ECase 'RE12 Dutch winget output' $soap4 ('"ExcludeIds": [], ' + $ro) $arp4 -envs @{ KIUTD_LANG = 'nl' }
ECase 'RE13 User task: rule not used (machine-wide apps only)' $soap4 ('"ExcludeIds": [], ' + $ro) $arp4 -mode 'User'
ECase 'RE14 invalid rule in the installed config: warning, nothing removed' $soap4 ('"ExcludeIds": [], "RemoveOlder": { "SoapUI": "-q" }') $arp4
$net = Join-Path $d 'netlogon147'; New-Item -ItemType Directory $net -Force | Out-Null
$netCfg = '"ExclusionsSource": "' + ($net -replace '\\', '\\') + '\\config.json"'
Set-Content "$net\config.json" ('{ "ExcludeIds": [], ' + $ro + ' }') -Encoding UTF8
ECase 'RE15 NETLOGON adds the rule, installed copy has none' $soap4 ('"ExcludeIds": [], ' + $netCfg) $arp4
'   installed config.json now: ' + ((Get-Content "$d\export148\config.json" -Raw | ConvertFrom-Json).RemoveOlder | ConvertTo-Json -Compress)
Set-Content "$net\config.json" '{ "ExcludeIds": [], "RemoveOlder": [ "SmartBear.SoapUI" ] }' -Encoding UTF8
ECase 'RE16 NETLOGON file with an invalid RemoveOlder: installed rule used' $soap4 ('"ExcludeIds": [], ' + $ro + ', ' + $netCfg) $arp4
ECase 'RE17 slow uninstaller (20 s) with InstallTimeoutMinutes 0.1: stopped and reported' @('SmartBear.SoapUI|5.9.1', 'SmartBear.SoapUI|5.10.0') ('"ExcludeIds": [], "InstallTimeoutMinutes": 0.1, ' + $ro) @(@{ Line = 'SmartBear.SoapUI|5.9.1'; Name = 'SoapUI 5.9.1'; Version = '5.9.1'; Extra = '-Delay 20' }, $arp4[3])
$fold = Join-Path $d 'folder147'
New-Item -ItemType Directory "$fold\SoapUI-5.9.1\bin" -Force | Out-Null; Set-Content "$fold\SoapUI-5.9.1\bin\soapui-5.9.1.jar" 'x'
ECase 'RE18 the uninstaller hands over and its copy deletes the folder 10 s later: no "still there" line' @('SmartBear.SoapUI|5.9.1', 'SmartBear.SoapUI|5.10.0') ('"ExcludeIds": [], ' + $ro) @(@{ Line = 'SmartBear.SoapUI|5.9.1'; Name = 'SoapUI 5.9.1'; Version = '5.9.1'; Location = "$fold\SoapUI-5.9.1"; Extra = "-Folder `"$fold\SoapUI-5.9.1`" -FolderDelay 10" }, $arp4[3])
'   folder now: ' + $(if (Test-Path "$fold\SoapUI-5.9.1") { 'still there' } else { 'gone' })
New-Item -ItemType Directory "$fold\SoapUI-5.9.1\bin" -Force | Out-Null; Set-Content "$fold\SoapUI-5.9.1\bin\soapui-5.9.1.jar" 'x'
ECase 'RE19 the folder stays (files left): named in the log after a minute' @('SmartBear.SoapUI|5.9.1', 'SmartBear.SoapUI|5.10.0') ('"ExcludeIds": [], ' + $ro) @(@{ Line = 'SmartBear.SoapUI|5.9.1'; Name = 'SoapUI 5.9.1'; Version = '5.9.1'; Location = "$fold\SoapUI-5.9.1" }, $arp4[3])
'   folder now: ' + $(if (Test-Path "$fold\SoapUI-5.9.1") { 'still there' } else { 'gone' })
Remove-Item $fold -Recurse -Force -ErrorAction SilentlyContinue
if (Test-Path $arpRoot) { Remove-Item $arpRoot -Recurse -Force }

''; '######## Part RP: -ClearPins (the installer -Uninstall runs it as SYSTEM)'
function PCase([string]$title, [string[]]$sysPins, [string[]]$wingetPins, [string]$fail = '') {
    ''; "--- $title"
    Remove-Item "$data\*" -Recurse -Force -ErrorAction SilentlyContinue
    Set-Content $env:KIUTD_STATE @('Git.Git|2.40.0')
    if ($sysPins) { Set-Content "$data\system.pins" $sysPins -Encoding ascii }
    if ($wingetPins) { Set-Content "$env:KIUTD_STATE.pins" $wingetPins } else { Remove-Item "$env:KIUTD_STATE.pins" -ErrorAction SilentlyContinue }
    $env:KIUTD_PINFAIL = $fail
    Set-Content "$d\export148\config.json" '{ "Version": "1.4.7-test", "ExcludeIds": [] }' -Encoding UTF8
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$d\export148\run.ps1" -Mode System -ClearPins 2>&1 | ForEach-Object { "   out: $_" }
    "   exit code: $LASTEXITCODE"
    Get-Content "$data\system.log" -ErrorAction SilentlyContinue | ForEach-Object { '   log: ' + ($_ -replace '^\d{4}-\d\d-\d\d \d\d:\d\d:\d\d  ', '') }
    '   system.pins now: ' + $(if (Test-Path "$data\system.pins") { (Get-Content "$data\system.pins") -join ', ' } else { 'gone' })
    '   winget pins now: ' + $(if (Test-Path "$env:KIUTD_STATE.pins") { @(Get-Content "$env:KIUTD_STATE.pins" | Where-Object { $_ }) -join ', ' } else { 'none' })
    '   winget calls: ' + (@(Get-Content "$data\calls.log" -ErrorAction SilentlyContinue | ForEach-Object { ($_ -split ' ')[0..3] -join ' ' }) -join ' | ')
}
PCase 'RP1 three exclusions set by the System task: all lifted, system.pins removed' @('Git.Git', 'Mobatek.MobaXterm', 'Oracle.VirtualBox') @('Git.Git', 'Mobatek.MobaXterm', 'Oracle.VirtualBox')
PCase 'RP2 one pin cannot be removed: kept in system.pins, exit 1' @('Git.Git', 'Mobatek.MobaXterm') @('Git.Git', 'Mobatek.MobaXterm') 'Mobatek.MobaXterm'
PCase 'RP3 a pin the admin set by hand stays (only the listed ones are lifted)' @('Git.Git') @('Git.Git', 'Contoso.ByHand')
PCase 'RP4 no system.pins: nothing done' @() @('Contoso.ByHand')
PCase 'RP5 system.pins lists a pin that is already gone' @('Git.Git', 'Oracle.VirtualBox') @('Git.Git')
$env:KIUTD_PINFAIL = ''

''; '######## Part RG2: the "*" rule (every package winget lists twice or more)'
$npNames = 'Notepad++.Notepad++|7.8.1=Notepad++ (64-bit x64);Notepad++.Notepad++|8.9.9=Notepad++ (x64);Ghisler.TotalCommander|9.51=Total Commander (Remove or Repair);Ghisler.TotalCommander|11.58.1=Total Commander 64-bit (Remove or Repair);Contoso.Tool|1.0=Contoso Tool 1.0;Contoso.Tool|2.0=Contoso Tool 2.0'
$wst = @('Notepad++.Notepad++|7.8.1', 'Notepad++.Notepad++|8.9.9', 'Ghisler.TotalCommander|9.51', 'Ghisler.TotalCommander|11.58.1', 'Git.Git|2.40.0')
$wstArp = @(
    @{ Line = 'Notepad++.Notepad++|7.8.1'; Name = 'Notepad++ (64-bit x64)'; Version = '7.8.1'; Location = 'C:\Program Files\Notepad++' },
    @{ Line = 'Notepad++.Notepad++|8.9.9'; Name = 'Notepad++ (x64)'; Version = '8.9.9'; Location = 'C:\Program Files\Notepad++\' },
    @{ Line = 'Ghisler.TotalCommander|9.51'; Name = 'Total Commander (Remove or Repair)'; Version = '9.51'; Location = 'C:\totalcmd' },
    @{ Line = 'Ghisler.TotalCommander|11.58.1'; Name = 'Total Commander 64-bit (Remove or Repair)'; Version = '11.58.1'; Location = 'C:\totalcmd' })
$star = '"ExcludeIds": [], "RemoveOlder": { "*": "", "SmartBear.SoapUI": "-q" }'
ECase 'RG2-1 PC380: Notepad++ and Total Commander old copies in the same folder: only their uninstall entries go, uninstallers not run' $wst $star $wstArp -envs @{ KIUTD_NAMES = $npNames }
ECase 'RG2-2 same, list only' $wst $star $wstArp -extra @('-ListOnly') -envs @{ KIUTD_NAMES = $npNames }
ECase 'RG2-3 same with SoapUI 4 copies: SoapUI by its rule (-q), the others entry only' (@($wst) + @($soap4)) $star (@($wstArp) + @($arp4)) -envs @{ KIUTD_NAMES = "$npNames;SmartBear.SoapUI|4.6.4=SoapUI 4.6.4 4.6.4;SmartBear.SoapUI|5.5.0=SoapUI 5.5.0;SmartBear.SoapUI|5.9.1=SoapUI 5.9.1;SmartBear.SoapUI|5.10.0=SoapUI 5.10.0" }
$tool = @('Contoso.Tool|1.0', 'Contoso.Tool|2.0')
ECase 'RG2-4 own folders, older has a quiet command: uninstalled with it' $tool $star @(@{ Line = 'Contoso.Tool|1.0'; Name = 'Contoso Tool 1.0'; Version = '1.0'; Location = 'C:\Contoso\Tool1'; Quiet = $true }, @{ Line = 'Contoso.Tool|2.0'; Name = 'Contoso Tool 2.0'; Version = '2.0'; Location = 'C:\Contoso\Tool2' }) -envs @{ KIUTD_NAMES = $npNames }
ECase 'RG2-5 own folders, no silent uninstall known: left and reported, no warning' $tool $star @(@{ Line = 'Contoso.Tool|1.0'; Name = 'Contoso Tool 1.0'; Version = '1.0'; Location = 'C:\Contoso\Tool1' }, @{ Line = 'Contoso.Tool|2.0'; Name = 'Contoso Tool 2.0'; Version = '2.0'; Location = 'C:\Contoso\Tool2' }) -envs @{ KIUTD_NAMES = $npNames }
ECase 'RG2-6 folder of the older copy unknown: left and reported' $tool $star @(@{ Line = 'Contoso.Tool|1.0'; Name = 'Contoso Tool 1.0'; Version = '1.0'; Location = ''; Quiet = $true }, @{ Line = 'Contoso.Tool|2.0'; Name = 'Contoso Tool 2.0'; Version = '2.0'; Location = 'C:\Contoso\Tool2' }) -envs @{ KIUTD_NAMES = $npNames }
ECase 'RG2-7 explicit rule, folder unknown: uninstalled as in 1.4.7' $tool '"ExcludeIds": [], "RemoveOlder": { "*": "", "Contoso.Tool": "" }' @(@{ Line = 'Contoso.Tool|1.0'; Name = 'Contoso Tool 1.0'; Version = '1.0'; Location = ''; Quiet = $true }, @{ Line = 'Contoso.Tool|2.0'; Name = 'Contoso Tool 2.0'; Version = '2.0'; Location = 'C:\Contoso\Tool2' }) -envs @{ KIUTD_NAMES = $npNames }
ECase 'RG2-8 "keep" for Notepad++: Notepad++ kept, Total Commander entry only' $wst '"ExcludeIds": [], "RemoveOlder": { "*": "", "Notepad++.Notepad++": "keep" }' $wstArp -envs @{ KIUTD_NAMES = $npNames }
ECase 'RG2-9 Total Commander excluded: not touched' $wst '"ExcludeIds": ["Ghisler.TotalCommander"], "RemoveOlder": { "*": "" }' $wstArp -envs @{ KIUTD_NAMES = $npNames }
ECase 'RG2-10 Notepad++ update failed in this run: its older copy kept' $wst $star $wstArp -envs @{ KIUTD_NAMES = $npNames; KIUTD_UPGRADES = 'Notepad++.Notepad++'; KIUTD_FAIL = 'Notepad++.Notepad++' }
ECase 'RG2-11 no "*" rule: Notepad++ and Total Commander not touched (1.4.7 behaviour)' $wst '"ExcludeIds": [], "RemoveOlder": { "SmartBear.SoapUI": "-q" }' $wstArp -envs @{ KIUTD_NAMES = $npNames }
ECase 'RG2-12 nothing installed twice' @('Git.Git|2.40.0', 'Contoso.Tool|2.0') $star @() -envs @{ KIUTD_NAMES = $npNames }
ECase 'RG2-13 User task: "*" not used' $wst $star $wstArp -mode 'User' -envs @{ KIUTD_NAMES = $npNames }
''; '######## done'
