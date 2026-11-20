$ErrorActionPreference = 'Continue'
$d = $PSScriptRoot
$tok = $null; $err = $null
$ast = [Management.Automation.Language.Parser]::ParseFile("$d\Install-KeepItUpToDater.ps1", [ref]$tok, [ref]$err); "installer parse errors: $($err.Count)"
function Fn([string]$name) { ($ast.FindAll({ param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq $name }, $true) | Select-Object -First 1).Extent.Text }

''; '######## Part C: config.json check by the installer'
$cdir = Join-Path $d 'cfg'; New-Item -ItemType Directory $cdir -Force | Out-Null
$inst = Join-Path $cdir 'installed'; New-Item -ItemType Directory $inst -Force | Out-Null
$idRx = ($ast.FindAll({ param($n) $n -is [Management.Automation.Language.AssignmentStatementAst] -and "$($n.Left)" -eq '$IdRegex' }, $true) | Select-Object -First 1).Extent.Text
$nameRx = ($ast.FindAll({ param($n) $n -is [Management.Automation.Language.AssignmentStatementAst] -and "$($n.Left)" -eq '$NameRegex' }, $true) | Select-Object -First 1).Extent.Text
$h = "param([string]`$ConfigFile)`r`n`$DisplayName = 'Keep It Up To Dater'; `$Organization = 'contoso.local'; `$ToolVersion = '1.4.6-test'; `$InstallDir = '$inst'`r`n" +
     "`$ExcludeIds = @(); `$ReplaceRules = [ordered]@{}; `$RemoveOlderRules = [ordered]@{}; `$ExclusionsSource = ''; `$IncludeUnknown = `$false; `$NoVCRuntime = `$false; `$MinIntervalDays = 0; `$DayOfWeek = 'Wednesday'; `$Time = '12:00'; `$ShowResults = (`$env:KIUTD_SWITCH -eq '1'); `$ShowResultsCfg = `$null; `$InstallTimeoutMinutes = 60; `$ComputerExcludeIds = [ordered]@{}; `$NoUserTask = (`$env:KIUTD_NOUSER -eq '1'); `$UserTaskCfg = `$null; `$UseProxy = (`$env:KIUTD_USEPROXY -eq '1'); `$ProxyCfg = `$null; `$ProxyBypassCfg = `$null; `$UseProxyCfg = `$null; `$MaxRunHours = `$(if (`$env:KIUTD_MRH) { [int]`$env:KIUTD_MRH } else { -1 }); `$MaxRunHoursCfg = `$null`r`n" +
     $idRx + "`r`n" + $nameRx + "`r`n" + (Fn 'Write-ComputerExclusions') + "`r`n" + (Fn 'Write-UserTaskSetting') + "`r`n" + (Fn 'Write-ProxySetting') + "`r`n" + (Fn 'Get-RunLimitChoice') + "`r`n" + (Fn 'Format-RunHours') + "`r`n" + (Fn 'Write-RunLimitSetting') + "`r`n" + (Fn 'Format-RemoveOlderRules') + "`r`n" + (Fn 'Read-Exclusions') + "`r`n" + (Fn 'Save-Config') + "`r`n" +
     "try { Read-Exclusions; if (`$env:KIUTD_SAVE -eq '1') { Save-Config '$cdir'; 'saved: ' + ((Get-Content '$cdir\config.json' -Raw) -replace '\s+', ' ') } } catch { 'REFUSED: ' + `$_.Exception.Message }"
Set-Content "$cdir\h.ps1" $h -Encoding UTF8
function CCase([string]$title, [string]$json, [string]$file = 'c.json', [switch]$Save) {
    "--- $title"
    if ($json) { Set-Content "$cdir\$file" $json -Encoding UTF8 }
    $env:KIUTD_SAVE = if ($Save) { '1' } else { '0' }
    $cfArg = if ($file -eq 'config.json') { @() } else { @('-ConfigFile', $file) }
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$cdir\h.ps1" @cfArg 2>&1 | ForEach-Object { "   $_" }
}
Copy-Item "$d\config.json" "$cdir\config.json"
CCase 'C1 shipped config.json (Node.js rule), saved to the installed copy' '' 'config.json' -Save
CCase 'C2 no Replace key' '{ "ExcludeIds": ["Git.Git"] }'
CCase 'C3 empty Replace' '{ "ExcludeIds": [], "Replace": {} }'
CCase 'C4 Replace as a list' '{ "ExcludeIds": [], "Replace": ["OpenJS.NodeJS.20"] }'
CCase 'C5 rule broader than Publisher.Package' '{ "ExcludeIds": [], "Replace": { "OpenJS.*": "OpenJS.NodeJS.LTS" } }'
CCase 'C6 rule with From equal to To' '{ "ExcludeIds": [], "Replace": { "OpenJS.NodeJS.LTS": "OpenJS.NodeJS.LTS" } }'
CCase 'C7 wildcard in To' '{ "ExcludeIds": [], "Replace": { "OpenJS.NodeJS.20": "OpenJS.NodeJS.*" } }'
CCase 'C8 bare wildcard' '{ "ExcludeIds": [], "Replace": { "*": "OpenJS.NodeJS.LTS" } }'
CCase 'C9 two rules, exact and wildcard' '{ "ExcludeIds": [], "Replace": { "OpenJS.NodeJS.*": "OpenJS.NodeJS.LTS", "Contoso.OldTool": "Contoso.NewTool" } }'
Copy-Item "$cdir\config.json" "$inst\config.json"; Remove-Item "$cdir\config.json"
CCase 'C10 config.json missing: installed rules kept' '' 'config.json' -Save
$pc = $env:COMPUTERNAME
CCase 'C11 ComputerExcludeIds for this computer and another, saved' ('{ "ExcludeIds": ["Git.Git"], "ComputerExcludeIds": { "' + $pc.ToLower() + '": ["Oracle.VirtualBox", "oracle.virtualbox"], "PC024": ["Mobatek.MobaXterm", "PuTTY.PuTTY"] } }') -Save
Copy-Item "$cdir\config.json" "$inst\config.json"; Remove-Item "$cdir\config.json"
CCase 'C12 config.json missing: installed per-computer lists kept' '' 'config.json'
CCase 'C13 ComputerExcludeIds as a list' '{ "ExcludeIds": [], "ComputerExcludeIds": ["PC024"] }'
CCase 'C14 computer name with a domain (PC024.contoso.local)' '{ "ExcludeIds": [], "ComputerExcludeIds": { "PC024.contoso.local": ["Mobatek.MobaXterm"] } }'
CCase 'C15 computer name longer than 15 characters' '{ "ExcludeIds": [], "ComputerExcludeIds": { "WORKSTATION-LONGNAME1": ["Mobatek.MobaXterm"] } }'
CCase 'C16 app name instead of an ID for a computer' '{ "ExcludeIds": [], "ComputerExcludeIds": { "PC024": ["MobaXterm"] } }'
CCase 'C17 one ID as text instead of a list, and an empty list' '{ "ExcludeIds": [], "ComputerExcludeIds": { "PC024": "Mobatek.MobaXterm", "PC-002": [] } }' -Save
CCase 'C18 empty ComputerExcludeIds' '{ "ExcludeIds": [], "ComputerExcludeIds": {} }'
CCase 'C19 ShowResults true, saved' '{ "ExcludeIds": [], "ShowResults": true }' -Save
CCase 'C20 ShowResults as a list of computer names, saved' ('{ "ExcludeIds": [], "ShowResults": [ "PC024", "' + $pc.ToLower() + '" ] }') -Save
CCase 'C21 ShowResults "yes"' '{ "ExcludeIds": [], "ShowResults": "yes" }'
CCase 'C22 ShowResults list with a full domain name' '{ "ExcludeIds": [], "ShowResults": [ "PC024.contoso.local" ] }'
CCase 'C23 ShowResults false' '{ "ExcludeIds": [], "ShowResults": false }'
$env:KIUTD_SWITCH = '1'
CCase 'C24 no ShowResults in config.json, installer -ShowResults, saved' '{ "ExcludeIds": [] }' -Save
$env:KIUTD_SWITCH = '0'
CCase 'C25 "UserTask": false, saved' '{ "ExcludeIds": [], "UserTask": false }' -Save
Copy-Item "$cdir\config.json" "$inst\config.json"; Remove-Item "$cdir\config.json"
CCase 'C26 config.json missing: installed "UserTask": false kept, saved' '' 'config.json' -Save
Remove-Item "$cdir\config.json"
CCase 'C27 "UserTask": "no"' '{ "ExcludeIds": [], "UserTask": "no" }'
$env:KIUTD_NOUSER = '1'
CCase 'C28 "UserTask": true and installer -NoUserTask, saved' '{ "ExcludeIds": [], "UserTask": true }' -Save
$env:KIUTD_NOUSER = '0'
Copy-Item "$d\config.json" "$cdir\config.json"
CCase 'C29 shipped pilot config.json 1.4.4 (ShowResults true, UserTask false), saved' '' 'config.json' -Save
Remove-Item "$cdir\config.json"

$pxj = '"Proxy": "http://192.0.2.163:8080", "ProxyBypass": "<local>;*.contoso.local"'
CCase 'C30 Proxy, ProxyBypass and "UseProxy": true, saved' ('{ "ExcludeIds": [], ' + $pxj + ', "UseProxy": true }') -Save
Copy-Item "$cdir\config.json" "$inst\config.json"; Remove-Item "$cdir\config.json"
CCase 'C31 config.json missing: installed proxy settings kept' '' 'config.json'
CCase 'C32 "UseProxy": [ "VM-*" ], this computer not in it' ('{ "ExcludeIds": [], ' + $pxj + ', "UseProxy": [ "VM-*" ] }')
CCase 'C33 "UseProxy" with a pattern that matches this computer' ('{ "ExcludeIds": [], ' + $pxj + ', "UseProxy": [ "VM-*", "' + $pc.Substring(0, 3).ToLower() + '*" ] }')
CCase 'C34 "UseProxy": true without "Proxy"' '{ "ExcludeIds": [], "UseProxy": true }'
CCase 'C35 "Proxy" without http://' '{ "ExcludeIds": [], "Proxy": "192.0.2.163:8080", "UseProxy": true }'
CCase 'C36 "UseProxy": "yes"' ('{ "ExcludeIds": [], ' + $pxj + ', "UseProxy": "yes" }')
CCase 'C37 "ProxyBypass" with a space' '{ "ExcludeIds": [], "Proxy": "http://192.0.2.163:8080", "ProxyBypass": "<local>; *.contoso.local" }'
$env:KIUTD_USEPROXY = '1'
CCase 'C38 installer -UseProxy, "UseProxy" not set, saved' ('{ "ExcludeIds": [], ' + $pxj + ' }') -Save
CCase 'C39 installer -UseProxy without "Proxy"' '{ "ExcludeIds": [] }'
$env:KIUTD_USEPROXY = '0'
Copy-Item "$d\config.json" "$cdir\config.json"
CCase 'C40 shipped pilot config.json 1.4.5 (proxy address, UseProxy false), saved' '' 'config.json' -Save
Remove-Item "$cdir\config.json"

CCase 'C41 "MaxRunHours": 8, saved' '{ "ExcludeIds": [], "MaxRunHours": 8 }' -Save
CCase 'C42 "MaxRunHours": 0 (no limit), saved' '{ "ExcludeIds": [], "MaxRunHours": 0 }' -Save
Copy-Item "$cdir\config.json" "$inst\config.json"; Remove-Item "$cdir\config.json"
CCase 'C43 config.json missing: installed "MaxRunHours": 0 kept, saved' '' 'config.json' -Save
Remove-Item "$cdir\config.json"; Remove-Item "$inst\config.json"
CCase 'C44 "MaxRunHours": 100' '{ "ExcludeIds": [], "MaxRunHours": 100 }'
CCase 'C45 "MaxRunHours": "8" (text)' '{ "ExcludeIds": [], "MaxRunHours": "8" }'
CCase 'C46 "MaxRunHours": 1.5' '{ "ExcludeIds": [], "MaxRunHours": 1.5 }'
CCase 'C47 "MaxRunHours": true' '{ "ExcludeIds": [], "MaxRunHours": true }'
$env:KIUTD_MRH = '0'
CCase 'C48 installer -MaxRunHours 0 with "MaxRunHours": 8, saved' '{ "ExcludeIds": [], "MaxRunHours": 8 }' -Save
$env:KIUTD_MRH = ''
CCase 'C49 no MaxRunHours: default 3 hours, saved' '{ "ExcludeIds": [] }' -Save
Copy-Item "$d\config.json" "$cdir\config.json"
CCase 'C50 shipped pilot config.json 1.4.6 (MaxRunHours 3), saved' '' 'config.json' -Save
Remove-Item "$cdir\config.json"

''; '######## Part TK, 1.4.6: the time limit as Task Scheduler gets it (New-ScheduledTaskSettingsSet, no task registered)'
foreach ($hrs in 0, 1, 3, 8, 24, 72) {
    $x = (New-ScheduledTaskSettingsSet -ExecutionTimeLimit ([TimeSpan]::FromHours($hrs))).ExecutionTimeLimit
    $back = [Xml.XmlConvert]::ToTimeSpan($x)
    "--- TK$hrs MaxRunHours $hrs" + ': task setting ' + $x + ', read back ' + $back + ', as set by the run: ' + [Xml.XmlConvert]::ToString([TimeSpan]::FromHours($hrs)) + $(if ($back -eq [TimeSpan]::FromHours($hrs)) { ' (same)' } else { ' (DIFFERENT)' })
}


''; '######## Part PB, 1.4.4: AppLocker blocks in Status.cmd and the installer (sample events instead of Get-WinEvent)'
. ([scriptblock]::Create((Fn 'Get-PolicyBlocks') + "`r`n" + (Fn 'Write-PolicyBlocks')))
function Get-WinEvent { param($FilterHashtable, $MaxEvents, $ErrorAction)
    if ($env:KIUTD_PB -eq 'none') { throw 'No events were found that match the specified selection criteria.' }
    $sid = [Security.Principal.WindowsIdentity]::GetCurrent().User
    if ($FilterHashtable.LogName -like '*EXE and DLL') {
        @([pscustomobject]@{ TimeCreated = (Get-Date '2026-11-05 10:30:52'); UserId = $sid; Message = '%SYSTEM32%\WINDOWSPOWERSHELL\V1.0\POWERSHELL.EXE was prevented from running.' },
          [pscustomobject]@{ TimeCreated = (Get-Date '2026-11-05 10:31:40'); UserId = $sid; Message = '%SYSTEM32%\WINDOWSPOWERSHELL\V1.0\POWERSHELL.EXE was prevented from running.' },
          [pscustomobject]@{ TimeCreated = (Get-Date '2026-11-04 09:00:00'); UserId = $sid; Message = '%OSDRIVE%\USERS\X\DOWNLOADS\TOOL.EXE was prevented from running.' })
    } else {
        @([pscustomobject]@{ TimeCreated = (Get-Date '2026-11-05 10:29:00'); UserId = $sid; Message = '%OSDRIVE%\USERS\X\DOWNLOADS\KEEPITUPTODATER-V1.4.3\STATUS.CMD was prevented from running.' })
    }
}
'--- PB1 PowerShell blocked twice, Status.cmd once, another app once; User task on'; $env:KIUTD_PB = ''; Write-PolicyBlocks $true | ForEach-Object { "   $_" }
'--- PB2 same, User task off'; Write-PolicyBlocks $false | ForEach-Object { "   $_" }
'--- PB3 no AppLocker events (or AppLocker not used)'; $env:KIUTD_PB = 'none'; $o = @(Write-PolicyBlocks $true); "   lines: $($o.Count)"
Remove-Item function:Get-WinEvent

''; '######## Part L: local exclusions in the installer (-AddLocalExclusion / -RemoveLocalExclusion)'
$ldir = Join-Path $d 'ldata'; if (Test-Path $ldir) { Remove-Item $ldir -Recurse -Force }; New-Item -ItemType Directory $ldir -Force | Out-Null
$idRx = ($ast.FindAll({ param($n) $n -is [Management.Automation.Language.AssignmentStatementAst] -and "$($n.Left)" -eq '$IdRegex' }, $true) | Select-Object -First 1).Extent.Text
$h2 = "param([string[]]`$AddLocalExclusion, [string[]]`$RemoveLocalExclusion)`r`n`$DataDir = '$ldir'`r`n`$LocalConfigFile = Join-Path `$DataDir 'local-config.json'`r`n$idRx`r`n" +
      "`$IcaclsExe = 'icacls.exe'`r`nfunction Set-LockedAcl([string]`$Path) { }`r`nfunction icacls.exe { `$global:LASTEXITCODE = 0; `"icacls `$args`" | Out-File '$ldir\icacls.log' -Append }`r`n" +
      (Fn 'Get-LocalExclusions') + "`r`n" + (Fn 'Set-LocalExclusions') + "`r`n" +
      "try { Set-LocalExclusions } catch { 'REFUSED: ' + `$_.Exception.Message }"
Set-Content "$ldir\h2.ps1" $h2 -Encoding UTF8
function LCase([string]$title, [string[]]$hArgs, [string]$preset) {
    "--- $title"
    if ($preset) { Set-Content "$ldir\local-config.json" $preset -Encoding UTF8 }
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$ldir\h2.ps1" @hArgs 2>&1 | ForEach-Object { "   $_" }
    if (Test-Path "$ldir\local-config.json") { '   file: ' + ((Get-Content "$ldir\local-config.json" -Raw) -replace '\s+', ' ') } else { '   file: (none)' }
}
LCase 'L1 add one ID, no file yet' @('-AddLocalExclusion', 'Oracle.VirtualBox')
LCase 'L2 add two IDs in one string, one of them already there in other case' @('-AddLocalExclusion', 'Mobatek.MobaXterm,oracle.virtualbox')
LCase 'L3 remove one present and one absent ID' @('-RemoveLocalExclusion', 'ORACLE.VirtualBox;Git.Git')
LCase 'L4 invalid ID refused, file unchanged' @('-AddLocalExclusion', 'MobaXterm')
LCase 'L5 add and remove in one call' @('-AddLocalExclusion', 'Git.Git', '-RemoveLocalExclusion', 'Mobatek.MobaXterm')
LCase 'L6 remove the last ID: file removed' @('-RemoveLocalExclusion', 'Git.Git')
LCase 'L7 existing file is not valid JSON: refused, file unchanged' @('-AddLocalExclusion', 'Git.Git') '{ "ExcludeIds": [ "Git.Git" '
Remove-Item "$ldir\local-config.json"
LCase 'L8 existing file with an invalid ID: refused' @('-AddLocalExclusion', 'Git.Git') '{ "ExcludeIds": [ "Git" ] }'
Remove-Item "$ldir\local-config.json"
'   icacls calls: ' + (@(Get-Content "$ldir\icacls.log" -ErrorAction SilentlyContinue) -join ' | ')

''; '######## Part S: updater with the winget stand-in (System task unless stated)'
$data = Join-Path $d 'data'
$localDir = Join-Path $d 'local'
$me = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
function New-TestRunner([string]$installer, [string]$dir, [switch]$Strict) {
    New-Item -ItemType Directory $dir -Force | Out-Null
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $installer -ExportRunner $dir | Out-Null
    $tok = $null; $err = $null
    [void][Management.Automation.Language.Parser]::ParseFile("$dir\Invoke-KeepItUpToDater.ps1", [ref]$tok, [ref]$err); "exported runner parse errors: $($err.Count)"
    $r = Get-Content "$dir\Invoke-KeepItUpToDater.ps1" -Raw
    $argLine = '$psi.Arguments = (@($Arguments) | ForEach-Object { if ($_ -match ''[\s"]'') { ''"'' + ($_ -replace ''"'', ''\"'') + ''"'' } else { $_ } }) -join '' '''
    $patches = @(
        @('$winget = Get-WingetPath', "`$winget = '$d\stub.ps1'"),
        @('$psi.FileName  = $winget', '$psi.FileName  = ''powershell.exe'''),
        @($argLine, ($argLine + "`r`n    `$psi.Arguments = '-NoProfile -ExecutionPolicy Bypass -File `"' + `$winget + '`" ' + `$psi.Arguments")),
        @('else                    { $dataDir = Join-Path $env:LOCALAPPDATA $Name }', "else                    { `$dataDir = '$data' }"),
        @('Write-Summary $evt $type $msg', 'Write-Log "EVENT $evt $type"; Write-Summary $evt $type $msg')
    )
    # 1.4.0 only: local exclusions file in the test folder; the test account counts as a trusted owner unless -Strict
    $optional = @(,@('$localCfgFile = Join-Path (Join-Path $env:ProgramData $Name) ''local-config.json''', "`$localCfgFile = '$localDir\local-config.json'"))
    # data folder: 1.4.3 and older, and 1.4.4 (also for -Mode Notify -For System)
    $optional += ,@('if ($Mode -eq ''System'') { $dataDir = Join-Path $env:ProgramData $Name }', "if (`$Mode -eq 'System') { `$dataDir = '$data' }")
    $optional += ,@('if ($Mode -eq ''System'' -or ($Mode -eq ''Notify'' -and $For -eq ''System'')) { $dataDir = Join-Path $env:ProgramData $Name }', "if (`$Mode -eq 'System' -or (`$Mode -eq 'Notify' -and `$For -eq 'System')) { `$dataDir = '$data' }")
    # 1.4.4: messages. Signed-in users from KIUTD_SESSIONS ("1=DOMAIN\user;2=..." or "none"); messages written to
    # messages.txt instead of shown, unless KIUTD_REALMSG=1; KIUTD_MSGFAIL=1 makes sending fail
    $optional += ,@('$sysDir   = Join-Path $env:ProgramData $Name', "`$sysDir   = '$data'")
    $optional += ,@('function Get-UserSessions {', ("function Get-UserSessions {`r`n    if (`$env:KIUTD_SESSIONS) { return @(`$env:KIUTD_SESSIONS -split ';' | Where-Object { `$_ -and `$_ -ne 'none' } | ForEach-Object { `$p = `$_ -split '=', 2; [pscustomobject]@{ Id = [int]`$p[0]; User = `$p[1] } }) }"))
    $optional += ,@('function Send-SessionMessage([int]$SessionId, [string]$Text, [int]$Timeout, [int]$Icon) {', ("function Send-SessionMessage([int]`$SessionId, [string]`$Text, [int]`$Timeout, [int]`$Icon) {`r`n    if (`$env:KIUTD_REALMSG -ne '1') { Write-Log `"MESSAGE session `$SessionId, timeout `$Timeout, icon `$Icon`"; Add-Content -LiteralPath '$data\messages.txt' -Value `"=== session `$SessionId, timeout `$Timeout, icon `$Icon`r`n`$Text`" -Encoding UTF8; return (`$env:KIUTD_MSGFAIL -ne '1') }"))
    # 1.4.5: proxy settings of the computer simulated in the JSON file KIUTD_PX (Winget, WinHttp, SystemIe); KIUTD_PXFAIL=<part> fails that part
    # 1.5.0: a part is an address (text) or { Address, Bypass, Auto, Known }
    $optional += ,@('function Get-MachineProxy {', ("function Get-MachineProxy {`r`n    if (`$env:KIUTD_PX -like '*.json') { `$f = Get-Content `$env:KIUTD_PX -Raw | ConvertFrom-Json; `$o = @{}; foreach (`$k in 'Winget', 'WinHttp', 'SystemIe') { `$v = `$f.`$k; if (`$null -eq `$v -or `$v -is [string]) { `$o[`$k] = @{ Known = `$true; Auto = `$false; Address = `"`$v`"; Bypass = '' } } else { `$o[`$k] = @{ Known = (`$v.Known -ne `$false); Auto = [bool]`$v.Auto; Address = `"`$(`$v.Address)`"; Bypass = `"`$(`$v.Bypass)`" } } }; return `$o }"))
    $optional += ,@('function Test-ProxyPolicy {', ("function Test-ProxyPolicy {`r`n    if (`$env:KIUTD_PX -like '*.json') { return (`$env:KIUTD_PXPOLICY -eq '1') }"))
    $optional += ,@('function Set-MachineProxyPart([string]$Part, $P) {', ("function Set-MachineProxyPart([string]`$Part, `$P) {`r`n    if (`$env:KIUTD_PX -like '*.json') { if (`$env:KIUTD_PXFAIL -eq `$Part) { Write-Log `"  `$Part (exit 1): fake failure`"; return `$false }; `$f = Get-Content `$env:KIUTD_PX -Raw | ConvertFrom-Json; `$f.`$Part = [pscustomobject]@{ Address = `$P.Address; Bypass = `$(if (`$Part -eq 'Winget') { '' } else { `"`$(`$P.Bypass)`" }) }; `$f | ConvertTo-Json | Set-Content `$env:KIUTD_PX; Write-Log `"PROXYCALL set `$Part `$(`$P.Address) bypass `$(`$P.Bypass)`"; return `$true }"))
    $optional += ,@('function Clear-MachineProxyPart([string]$Part) {', ("function Clear-MachineProxyPart([string]`$Part) {`r`n    if (`$env:KIUTD_PX -like '*.json') { `$f = Get-Content `$env:KIUTD_PX -Raw | ConvertFrom-Json; `$f.`$Part = ''; `$f | ConvertTo-Json | Set-Content `$env:KIUTD_PX; Write-Log `"PROXYCALL reset `$Part`"; return `$true }"))
    # 1.4.6: time limits of the tasks simulated in the JSON file KIUTD_TL (System, User: PT3H, PT0S, ...; empty: no task); KIUTD_TLFAIL=<task> fails that change
    $optional += ,@('function Get-TaskTimeLimit([string]$Task) {', ("function Get-TaskTimeLimit([string]`$Task) {`r`n    if (`$env:KIUTD_TL -like '*.json') { `$f = Get-Content `$env:KIUTD_TL -Raw | ConvertFrom-Json; `$v = `"`$(`$f.`$Task)`"; if (-not `$v) { return `$null }; return [Xml.XmlConvert]::ToTimeSpan(`$v) }"))
    $optional += ,@('function Set-TaskTimeLimit([string]$Task, [int]$Hours) {', ("function Set-TaskTimeLimit([string]`$Task, [int]`$Hours) {`r`n    if (`$env:KIUTD_TL -like '*.json') { if (`$env:KIUTD_TLFAIL -eq `$Task) { Write-Log `"WARNING: could not change the time limit of the `$Task task: fake failure. It changes at the next install.`"; return `$false }; `$f = Get-Content `$env:KIUTD_TL -Raw | ConvertFrom-Json; `$f.`$Task = [Xml.XmlConvert]::ToString([TimeSpan]::FromHours(`$Hours)); `$f | ConvertTo-Json | Set-Content `$env:KIUTD_TL; Write-Log `"TLCALL set `$Task `$(`$f.`$Task)`"; return `$true }"))
    # 1.5.0: winget's pin list read back from the stand-in's own process; KIUTD_NOVC=1: Visual C++ runtime missing
    $optional += ,@('function Get-PinList { @(& $winget pin list', 'function Get-PinList { @(& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $winget pin list')
    $optional += ,@('function Test-VCRuntime {', "function Test-VCRuntime {`r`n    if (`$env:KIUTD_NOVC -eq '1') { return `$false }")
    if (-not $Strict) { $optional += ,@('$trustedOwners = @(''S-1-5-18'', ''S-1-5-32-544'')', "`$trustedOwners = @('S-1-5-18', 'S-1-5-32-544', '$me')") }
    # 1.4.3: result window and test schedule in the test folder; window starts and the window itself only logged
    $optional += ,@('Start-ScheduledTask -TaskPath "\$Name\" -TaskName ''Notify'' -ErrorAction Stop', 'Write-Log ''NOTIFY START System''')
    $optional += ,@('Start-Process -FilePath $ps -WindowStyle Hidden -ArgumentList "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$PSCommandPath`" -Mode Notify -For User" -ErrorAction Stop | Out-Null', 'Write-Log ''NOTIFY START User''')
    $optional += ,@('$testFlag = Join-Path (Join-Path $env:ProgramData $Name) ''testrun''', "`$testFlag = '$data\testrun'")
    $optional += ,@('$statusPath = if ($For -eq ''System'') { Join-Path (Join-Path $env:ProgramData $Name) ''system.status.json'' }', "`$statusPath = if (`$For -eq 'System') { '$data\system.status.json' }")
    $optional += ,@('    Show-RunWindow $statusPath $seenPath $logPath $For $st', '    Write-Log "WINDOW SHOWN $($st.Phase)"; if ("$($st.Phase)" -eq ''done'') { "$($st.Run)" | Set-Content -LiteralPath $seenPath -Encoding ascii }')
    $n = 0; foreach ($pt in $patches) { if ($r.Contains($pt[0])) { $r = $r.Replace($pt[0], $pt[1]); $n++ } else { "PATCH NOT FOUND: $($pt[0])" } }
    $o = 0; foreach ($pt in $optional) { if ($r.Contains($pt[0])) { $r = $r.Replace($pt[0], $pt[1]); $o++ } }
    "patches applied: $n of $($patches.Count), optional patches: $o of $($optional.Count)"
    Set-Content "$dir\run.ps1" $r -Encoding UTF8
}
New-TestRunner "$d\Install-KeepItUpToDater.ps1" "$d\export"
New-TestRunner "$d\Install-KeepItUpToDater.ps1" "$d\export-strict" -Strict
New-TestRunner "$d\Install-143.ps1" "$d\export-143"
New-TestRunner "$d\Install-144.ps1" "$d\export-144"
$script:runDir = "$d\export"
$env:KIUTD_STATE = Join-Path $data 'state.txt'
$rule = '"Replace": { "OpenJS.NodeJS.*": "OpenJS.NodeJS.LTS" }'
function SCase([string]$title, [string[]]$installed, [string]$cfgBody, [string]$mode = 'System', [string[]]$extra = @(), [hashtable]$envs = @{},
               [string]$local, [switch]$NoForce, [switch]$Flag, [switch]$Recent, [object]$Last, [switch]$KeepData, [string]$Marker, [object]$TestAt) {
    ''; "--- $title"
    if (-not $KeepData) {
        if (Test-Path $data) { Remove-Item $data -Recurse -Force }
        New-Item -ItemType Directory $data -Force | Out-Null
    } else { Remove-Item "$data\calls.log", "$data\messages.txt" -ErrorAction SilentlyContinue }
    if ($Last) { ([datetime]$Last).ToString('o') | Set-Content "$data\$($mode.ToLower()).lastrun" -Encoding ascii }
    if ($Marker) { Set-Content "$data\$($mode.ToLower()).running" $Marker -Encoding ascii }
    if ($TestAt) { ([datetime]$TestAt).ToString('o') | Set-Content "$data\testrun" -Encoding ascii }
    if (Test-Path $localDir) { Remove-Item $localDir -Recurse -Force }
    New-Item -ItemType Directory $localDir -Force | Out-Null
    if ($local) { Set-Content "$localDir\local-config.json" $local -Encoding UTF8 }
    if ($Recent) { (Get-Date).AddDays(-1).ToString('o') | Set-Content "$data\$($mode.ToLower()).lastrun" -Encoding ascii }
    if ($Flag) { (Get-Date).ToString('o') | Set-Content "$data\system.runnow" -Encoding ascii }
    Set-Content $env:KIUTD_STATE $installed
    Set-Content "$script:runDir\config.json" ('{ "Version": "1.4.6-test", ' + $cfgBody + ' }') -Encoding UTF8
    foreach ($k in 'KIUTD_EXPORT_FAIL', 'KIUTD_INSTALL_FAIL', 'KIUTD_SIDE_BY_SIDE', 'KIUTD_ALIAS', 'KIUTD_UNINSTALL_ALL', 'KIUTD_UPGRADES', 'KIUTD_RESTART',
                 'KIUTD_REOPEN', 'KIUTD_NOTTRIED', 'KIUTD_EXPLICIT', 'KIUTD_OLDER', 'KIUTD_LANG', 'KIUTD_LT', 'KIUTD_LONGNAME', 'KIUTD_REPLAY',
                 'KIUTD_REPLAY_AFTER', 'KIUTD_LISTMODE', 'KIUTD_FAIL', 'KIUTD_REALMSG', 'KIUTD_MSGFAIL', 'KIUTD_MANY') { Set-Item "env:$k" '0' }
    $env:KIUTD_SESSIONS = '1=CONTOSO\j.doe'
    $env:KIUTD_PX = ''; $env:KIUTD_PXFAIL = ''; $env:KIUTD_TL = ''; $env:KIUTD_TLFAIL = ''
    foreach ($k in $envs.Keys) { Set-Item "env:$k" $envs[$k] }
    $fArg = @(if (-not $NoForce) { '-Force' })
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$script:runDir\run.ps1" -Mode $mode @fArg @extra 2>&1 | ForEach-Object { "$_" } |
        Where-Object { $_ -match 'Replac|replace|Would|Excluded|excluded|Exclusions|exclusions|Finished|List finished|Found|Successfully|failed|WARNING|ERROR|Could not|Restart|skipped|RunNow|EVENT|run started|lifted|Listed|in the future|still busy|NOTIFY|Result window|WINDOW|test schedule|result window|failed with|MESSAGE|[Mm]essage|signed-in|nobody|Proxy|PROXYCALL|Time limit|TLCALL' -and $_ -notmatch 'settings file' } |
        ForEach-Object { '   ' + ($_ -replace '^\d{4}-\d\d-\d\d \d\d:\d\d:\d\d  ', '') }
    '   winget calls: ' + (@(Get-Content "$data\calls.log" -ErrorAction SilentlyContinue | Where-Object { $_ -match '^(export|install|uninstall|list|upgrade)' } | ForEach-Object { $w = $_ -split ' '; if ($w[0] -eq 'uninstall' -and $w -contains '--version') { "$($w[0..2] -join ' ') --version $($w[[array]::IndexOf($w, '--version') + 1])" } else { $w[0..2] -join ' ' } }) -join ' | ')
    '   installed after: ' + (@(Get-Content $env:KIUTD_STATE | Where-Object { $_ }) -join ', ')
    '   pins after: ' + $(if (Test-Path "$env:KIUTD_STATE.pins") { @(Get-Content "$env:KIUTD_STATE.pins" | Where-Object { $_ }) -join ', ' } else { 'none' }) +
        '; runnow flag: ' + $(if (Test-Path "$data\system.runnow") { 'still there' } else { 'gone' }) +
        '; running marker: ' + $(if (Test-Path "$data\$($mode.ToLower()).running") { 'still there' } else { 'gone' }) +
        '; lastrun: ' + $(if (Test-Path "$data\$($mode.ToLower()).lastrun") { ([datetime]::Parse((Get-Content "$data\$($mode.ToLower()).lastrun" -Raw).Trim())).ToString('yyyy-MM-dd HH:mm') } else { 'none' })
    foreach ($sf in 'system.status.json', 'user.status.json') {
        if ($mode -eq 'Notify') { continue }
        if (Test-Path "$data\$sf") {
            $j = Get-Content "$data\$sf" -Raw | ConvertFrom-Json
            "   $sf phase $($j.Phase), $($j.Index)/$($j.Total); updated: " + (@($j.Updated) -join '; ') + ' | not updated: ' + (@($j.NotUpdated) -join '; ') +
                ' | restart: ' + (@($j.Restart) -join '; ') + ' | reopen: ' + (@($j.Reopen) -join '; ') + ' | replaced: ' + (@($j.Replaced) -join '; ') + ' | error: ' + $j.Error
        }
    }
    if (Test-Path "$data\messages.txt") { '   messages: ' + ((@([regex]::Matches((Get-Content "$data\messages.txt" -Raw), '(?m)^=== (.+?)\r?$') | ForEach-Object { $_.Groups[1].Value })) -join ' | ') }
    if (Test-Path "$data\notify.sent") { '   sent: ' + (@(Get-Content "$data\notify.sent" | Where-Object { $_ } | ForEach-Object { ($_ -split '\|', 2)[1] }) -join ', ') }
    if ((Test-Path "$data\system.testrun") -or (Test-Path "$data\user.testrun")) { '   test start used by: ' + (@('system', 'user' | Where-Object { Test-Path "$data\$_.testrun" }) -join ', ') }
}
SCase 'S1 Node.js 20 installed, new major removes the old one' @('OpenJS.NodeJS.20|20.18.0', 'Git.Git|2.40.0') ('"ExcludeIds": [], ' + $rule)
SCase 'S2 Node.js 16, target installs side by side: old one removed after' @('OpenJS.NodeJS.16|16.20.2') ('"ExcludeIds": [], ' + $rule) -envs @{ KIUTD_SIDE_BY_SIDE = '1' }
SCase 'S3 install of the target fails' @('OpenJS.NodeJS.18|18.20.8') ('"ExcludeIds": [], ' + $rule) -envs @{ KIUTD_INSTALL_FAIL = '1' }
SCase 'S4 old package excluded' @('OpenJS.NodeJS.22|22.23.4') ('"ExcludeIds": ["OpenJS.NodeJS.22"], ' + $rule)
SCase 'S5 Node.js LTS already installed' @('OpenJS.NodeJS.LTS|24.22.1') ('"ExcludeIds": [], ' + $rule)
SCase 'S6 Node.js Current (OpenJS.NodeJS) installed' @('OpenJS.NodeJS|26.12.1') ('"ExcludeIds": [], ' + $rule)
SCase 'S7 listing fails before the update pass, works after it' @('OpenJS.NodeJS.20|20.18.0') ('"ExcludeIds": [], ' + $rule) -envs @{ KIUTD_EXPORT_FAIL = '1' }
SCase 'S8 list only (System)' @('OpenJS.NodeJS.20|20.18.0') ('"ExcludeIds": [], ' + $rule) -extra @('-ListOnly')
SCase 'S9 User task' @('OpenJS.NodeJS.20|20.18.0') ('"ExcludeIds": [], ' + $rule) -mode 'User'
SCase 'S10 invalid rule in the installed config' @('OpenJS.NodeJS.20|20.18.0') '"ExcludeIds": [], "Replace": { "OpenJS.*": "OpenJS.NodeJS.LTS" }'
SCase 'S11 two rules: exact (side by side) and wildcard' @('Contoso.OldTool|1.0', 'OpenJS.NodeJS.14|14.21.3') ('"ExcludeIds": [], "Replace": { "Contoso.OldTool": "Contoso.NewTool", "OpenJS.NodeJS.*": "OpenJS.NodeJS.LTS" }')
$net = Join-Path $d 'netlogon'; New-Item -ItemType Directory $net -Force | Out-Null
$netCfg = '"ExclusionsSource": "' + ($net -replace '\\', '\\') + '\\config.json"'
Set-Content "$net\config.json" ('{ "ExcludeIds": [], ' + $rule + ' }') -Encoding UTF8
SCase 'S12 rule added on NETLOGON, installed copy has none' @('OpenJS.NodeJS.12|12.22.12') ('"ExcludeIds": [], ' + $netCfg)
'   installed config.json now: ' + ((Get-Content "$d\export\config.json" -Raw | ConvertFrom-Json).Replace | ConvertTo-Json -Compress)
SCase 'S13 Node.js 20, winget lists the upgraded install under the old ID (real case 4 Nov)' @('OpenJS.NodeJS.20|20.20.2') ('"ExcludeIds": [], ' + $rule) -envs @{ KIUTD_ALIAS = '1' }
SCase 'S14 the week after S13: OpenJS.NodeJS.20 now shows 26.13.0' @('OpenJS.NodeJS.20|26.13.0') ('"ExcludeIds": [], ' + $rule) -envs @{ KIUTD_ALIAS = '1' }
SCase 'S15 side by side, the old uninstaller removes every Node.js' @('OpenJS.NodeJS.16|16.20.2') ('"ExcludeIds": [], ' + $rule) -envs @{ KIUTD_SIDE_BY_SIDE = '1'; KIUTD_UNINSTALL_ALL = '1' }

''; '######## Part S, 1.4.0: local exclusions, -RunNow, restart notice'
$apps = @('Git.Git|2.40.0', 'Oracle.VirtualBox|7.2.20', 'PuTTY.PuTTY|0.84.0.0')
$ups = @{ KIUTD_UPGRADES = 'Git.Git,Oracle.VirtualBox,PuTTY.PuTTY' }
$localVB = '{ "Comment": "test", "ExcludeIds": [ "Oracle.VirtualBox" ] }'
SCase 'S16 global Git.Git plus local Oracle.VirtualBox (System)' $apps '"ExcludeIds": ["Git.Git"]' -envs $ups -local $localVB
SCase 'S17 same as S16 in the User task' $apps '"ExcludeIds": ["Git.Git"]' -mode 'User' -envs $ups -local $localVB
SCase 'S18 local exclusion of an old Node.js blocks its Replace rule' @('OpenJS.NodeJS.20|20.18.0') ('"ExcludeIds": [], ' + $rule) -local '{ "ExcludeIds": [ "OpenJS.NodeJS.20" ] }'
SCase 'S19 local file is not valid JSON: run stopped, nothing updated' $apps '"ExcludeIds": []' -envs $ups -local '{ "ExcludeIds": [ "Oracle.VirtualBox" '
SCase 'S20 local file with an invalid ID: run stopped' $apps '"ExcludeIds": []' -envs $ups -local '{ "ExcludeIds": [ "VirtualBox" ] }'
SCase 'S21 local file with an empty list' $apps '"ExcludeIds": []' -envs $ups -local '{ "ExcludeIds": [] }'
Set-Content "$net\config.json" '{ "ExcludeIds": ["Git.Git"] }' -Encoding UTF8
SCase 'S22 NETLOGON adds Git.Git, local Oracle.VirtualBox: installed config.json gets only the global list' $apps ('"ExcludeIds": [], ' + $netCfg) -envs $ups -local $localVB
'   installed config.json ExcludeIds now: ' + ((Get-Content "$d\export\config.json" -Raw | ConvertFrom-Json).ExcludeIds -join ', ')
$script:runDir = "$d\export-strict"
SCase 'S23 local file owned by a standard user (owner check as shipped): ignored, warning' $apps '"ExcludeIds": []' -envs $ups -local $localVB
$script:runDir = "$d\export"
SCase 'S24 run yesterday, no -RunNow flag: skipped (control)' $apps '"ExcludeIds": []' -envs $ups -NoForce -Recent
SCase 'S25 run yesterday, -RunNow flag present: runs once, flag removed' $apps '"ExcludeIds": []' -envs $ups -NoForce -Recent -Flag
SCase 'S26 -RunNow flag present, list only: flag kept' $apps '"ExcludeIds": []' -envs $ups -NoForce -Recent -Flag -extra @('-ListOnly')
SCase 'S27 -RunNow flag present, User task: flag ignored and kept' $apps '"ExcludeIds": []' -mode 'User' -envs $ups -NoForce -Recent -Flag
SCase 'S28 two installers ask for a restart (as Visual Studio Build Tools on PC024)' $apps '"ExcludeIds": []' -envs @{ KIUTD_UPGRADES = 'Git.Git,Oracle.VirtualBox,PuTTY.PuTTY'; KIUTD_RESTART = 'Oracle.VirtualBox,PuTTY.PuTTY' }

''; '######## Part S, 1.4.1: exclusions per computer in config.json'
$pc = $env:COMPUTERNAME
$perPc = '"ComputerExcludeIds": { "' + $pc.ToLower() + '": ["Oracle.VirtualBox"], "PC024": ["PuTTY.PuTTY"] }'
SCase 'S29 global Git.Git, this computer Oracle.VirtualBox (name in lower case), PC024 PuTTY' $apps ('"ExcludeIds": ["Git.Git"], ' + $perPc) -envs $ups
SCase 'S30 this computer in config.json (Oracle.VirtualBox) and in local-config.json (PuTTY)' $apps ('"ExcludeIds": [], ' + $perPc) -envs $ups -local '{ "ExcludeIds": [ "PuTTY.PuTTY" ] }'
SCase 'S31 same in the User task' $apps ('"ExcludeIds": [], ' + $perPc) -mode 'User' -envs $ups
SCase 'S32 per-computer exclusion of an old Node.js blocks its Replace rule' @('OpenJS.NodeJS.20|20.18.0') ('"ExcludeIds": [], ' + $rule + ', "ComputerExcludeIds": { "' + $pc + '": ["OpenJS.NodeJS.20"] }')
Set-Content "$net\config.json" ('{ "ExcludeIds": ["Git.Git"], "ComputerExcludeIds": { "' + $pc + '": ["Oracle.VirtualBox"] } }') -Encoding UTF8
SCase 'S33 NETLOGON adds an exclusion for this computer; installed copy has none' $apps ('"ExcludeIds": [], ' + $netCfg) -envs $ups
'   installed config.json now: ExcludeIds ' + ((Get-Content "$d\export\config.json" -Raw | ConvertFrom-Json).ExcludeIds -join ', ') + '; ComputerExcludeIds ' + ((Get-Content "$d\export\config.json" -Raw | ConvertFrom-Json).ComputerExcludeIds | ConvertTo-Json -Compress)
SCase 'S34 run again with the same NETLOGON file: no change reported' $apps ('"ExcludeIds": ["Git.Git"], "ComputerExcludeIds": { "' + $pc + '": ["Oracle.VirtualBox"] }, ' + $netCfg) -envs $ups
Set-Content "$net\config.json" '{ "ExcludeIds": [], "ComputerExcludeIds": { "PC024.contoso.local": ["Mobatek.MobaXterm"] } }' -Encoding UTF8
SCase 'S35 NETLOGON file with an invalid computer name: installed lists used' $apps ('"ExcludeIds": ["Git.Git"], ' + $perPc + ', ' + $netCfg) -envs $ups
SCase 'S36 installed config.json with an invalid ComputerExcludeIds (edited by hand)' $apps '"ExcludeIds": [], "ComputerExcludeIds": ["Oracle.VirtualBox"]' -envs $ups


''; '######## Part W, 1.4.2: once per week, counted from two days before the scheduled day and time'
function Sched([datetime]$slot) { '"ScheduleDay": "' + $slot.DayOfWeek + '", "ScheduleTime": "' + $slot.ToString('HH:mm') + '"' }
$now = Get-Date
$slotNow = $now.AddHours(-1)   # the weekly start was one hour ago: this start is the weekly run
$wk = Sched $slotNow
$one = @('Git.Git|2.40.0'); $upOne = @{ KIUTD_UPGRADES = 'Git.Git' }
"   now $($now.ToString('ddd yyyy-MM-dd HH:mm')), weekly start in W1-W4 and W8-W11: $($slotNow.ToString('ddd HH:mm'))"
SCase 'W1 weekly start, last run at last week''s weekly start: runs' $one ('"ExcludeIds": [], ' + $wk) -envs $upOne -NoForce -Last $slotNow.AddDays(-7).AddMinutes(30)
SCase 'W2 weekly start, last run a catch-up 5 days 21 hours earlier (like a Friday catch-up): runs' $one ('"ExcludeIds": [], ' + $wk) -envs $upOne -NoForce -Last $slotNow.AddDays(-6).AddHours(3)
SCase 'W3 weekly start, manual run the day before (PC024, 3 and 4 Nov): skipped' $one ('"ExcludeIds": [], ' + $wk) -envs $upOne -NoForce -Last $slotNow.AddDays(-1)
SCase 'W4 weekly start, last run just before the week began: runs' $one ('"ExcludeIds": [], ' + $wk) -envs $upOne -NoForce -Last $slotNow.AddDays(-2).AddHours(-1)
$slot2 = $now.AddDays(-2)
SCase 'W5 startup two days after this week''s weekly run: skipped' $one ('"ExcludeIds": [], ' + (Sched $slot2)) -envs $upOne -NoForce -Last $slot2.AddMinutes(30)
$slot3 = $now.AddDays(-3)
SCase 'W6 startup three days after a missed weekly start, last run the week before: runs' $one ('"ExcludeIds": [], ' + (Sched $slot3)) -envs $upOne -NoForce -Last $slot3.AddDays(-7).AddHours(1)
$slot6 = $now.AddDays(-6)
SCase 'W7 startup the day before the next weekly start, this week''s run done: skipped, next start tomorrow' $one ('"ExcludeIds": [], ' + (Sched $slot6)) -envs $upOne -NoForce -Last $slot6.AddMinutes(20)
SCase 'W8 no schedule in config.json, last run 3 days ago: skipped (6-day rule)' $one '"ExcludeIds": []' -envs $upOne -NoForce -Last $now.AddDays(-3)
SCase 'W9 MinIntervalDays 13, last run at last week''s weekly start: skipped' $one ('"ExcludeIds": [], "MinIntervalDays": 13, ' + $wk) -envs $upOne -NoForce -Last $slotNow.AddDays(-7).AddMinutes(30)
SCase 'W10 last run time in the future (clock changed): ignored, runs' $one ('"ExcludeIds": [], ' + $wk) -envs $upOne -NoForce -Last $now.AddDays(2)
SCase 'W11 same as W3 in the User task: skipped' $one ('"ExcludeIds": [], ' + $wk) -mode 'User' -envs $upOne -NoForce -Last $slotNow.AddDays(-1)
SCase 'W12 schedule day not valid (Woensdag): 6-day rule, last run 3 days ago: skipped' $one '"ExcludeIds": [], "ScheduleDay": "Woensdag", "ScheduleTime": "12:00"' -envs $upOne -NoForce -Last $now.AddDays(-3)
SCase 'W13 -RunNow flag with W3: runs, flag removed' $one ('"ExcludeIds": [], ' + $wk) -envs $upOne -NoForce -Last $slotNow.AddDays(-1) -Flag

''; '######## Part M, 1.4.2: a run that did not finish'
$deadPid = 99990; while (Get-Process -Id $deadPid -ErrorAction SilentlyContinue) { $deadPid-- }
$myStart = (Get-Process -Id $PID).StartTime
$stale = '2026-11-02T10:31:41.0000000+01:00|' + $deadPid + '|Oracle.VirtualBox'
SCase 'M1 marker left by a stopped run (process gone), it was busy with Oracle.VirtualBox' $apps '"ExcludeIds": []' -envs $ups -Marker $stale
SCase 'M2 marker of a run that is still busy (this test process): skipped, marker kept' $apps '"ExcludeIds": []' -envs $ups -Marker ((Get-Date).ToString('o') + '|' + $PID + '|Git.Git')
SCase 'M3 marker with a reused process ID (process started after that run): reported as not finished' $apps '"ExcludeIds": []' -envs $ups -Marker ($myStart.AddMinutes(-5).ToString('o') + '|' + $PID + '|')
SCase 'M4 marker present, list only: nothing reported, marker kept' $apps '"ExcludeIds": []' -envs $ups -Marker $stale -extra @('-ListOnly')
SCase 'M5 run stopped by an invalid local-config.json: marker removed' $apps '"ExcludeIds": []' -envs $ups -local '{ "ExcludeIds": [ "VirtualBox" ] }'
SCase 'M6 User task with a stale marker' $apps '"ExcludeIds": []' -mode 'User' -envs $ups -Marker ('2026-11-02T10:31:41.0000000+01:00|' + $deadPid + '|')
''; '--- M7 PC024 2 Nov output replayed: the run hangs at Oracle.VirtualBox and is stopped'
if (Test-Path $data) { Remove-Item $data -Recurse -Force }; New-Item -ItemType Directory $data -Force | Out-Null
Set-Content $env:KIUTD_STATE $apps
Set-Content "$script:runDir\config.json" '{ "Version": "1.4.2-test", "ExcludeIds": [] }' -Encoding UTF8
$env:KIUTD_REPLAY = "$d\replay-1102.txt"
$rp = Start-Process powershell.exe -ArgumentList ('-NoProfile -ExecutionPolicy Bypass -File "' + "$script:runDir\run.ps1" + '" -Mode System -Force') -PassThru -WindowStyle Hidden
$deadline = (Get-Date).AddSeconds(120)
while ((Get-Date) -lt $deadline -and -not ((Test-Path "$data\system.running") -and ("$(Get-Content "$data\system.running" -Raw)" -match 'VirtualBox'))) { Start-Sleep -Milliseconds 500 }
Start-Sleep -Seconds 3
'   marker while busy: ' + "$(Get-Content "$data\system.running" -Raw)".Trim()
& taskkill.exe /PID $rp.Id /T /F | Out-Null
Start-Sleep -Seconds 2
'   last log line after the stop: ' + ((Get-Content "$data\system.log" | Select-Object -Last 1) -replace '^\d{4}-\d\d-\d\d \d\d:\d\d:\d\d  ', '')
$env:KIUTD_REPLAY = '0'
SCase 'M7b next run' $apps '"ExcludeIds": []' -envs $ups -KeepData

''; '######## Part T, 1.4.2: updates listed but not installed, another version, apps to start again'
$apps2 = @('Git.Git|2.40.0', 'Oracle.VirtualBox|7.2.20', 'GnuPG.GnuPG|2.5.17', 'Mobatek.MobaXterm|25.3.0.5384', 'Microsoft.Outlook|1.2025.1121.100', 'Python.Launcher|3.14.6')
SCase 'T1 two apps listed but not installed (GnuPG, MobaXterm as on PC024 3 Nov)' $apps2 '"ExcludeIds": []' -envs @{ KIUTD_UPGRADES = 'Git.Git,Oracle.VirtualBox'; KIUTD_NOTTRIED = 'GnuPG.GnuPG,Mobatek.MobaXterm' }
SCase 'T2 GnuPG updated to 2.5.19 while 9.9.9 was listed (as on PC024 2 Nov)' $apps2 '"ExcludeIds": []' -envs @{ KIUTD_UPGRADES = 'Git.Git,GnuPG.GnuPG'; KIUTD_OLDER = 'GnuPG.GnuPG=2.5.19' }
SCase 'T3 MobaXterm excluded: not listed, so not reported' $apps2 '"ExcludeIds": ["Mobatek.MobaXterm"]' -envs @{ KIUTD_UPGRADES = 'Git.Git'; KIUTD_NOTTRIED = 'GnuPG.GnuPG,Mobatek.MobaXterm' }
SCase 'T4 MobaXterm only in the explicit-targeting table' $apps2 '"ExcludeIds": []' -envs @{ KIUTD_UPGRADES = 'Git.Git'; KIUTD_EXPLICIT = 'Mobatek.MobaXterm' }
SCase 'T5 shortened name right before the ID, "< version"' $apps2 '"ExcludeIds": []' -envs @{ KIUTD_UPGRADES = 'Python.Launcher,Git.Git'; KIUTD_LT = 'Python.Launcher'; KIUTD_LONGNAME = 'Python.Launcher' }
SCase 'T6 Outlook asks to restart the app, VirtualBox the PC' $apps2 '"ExcludeIds": []' -envs @{ KIUTD_UPGRADES = 'Git.Git,Oracle.VirtualBox,Microsoft.Outlook'; KIUTD_RESTART = 'Oracle.VirtualBox'; KIUTD_REOPEN = 'Microsoft.Outlook' }
SCase 'T7 User task, Dutch winget output with a Source column' $apps2 '"ExcludeIds": []' -mode 'User' -envs @{ KIUTD_UPGRADES = 'Git.Git'; KIUTD_NOTTRIED = 'Mobatek.MobaXterm'; KIUTD_OLDER = 'Git.Git=2.41.0'; KIUTD_LANG = 'nl' }
SCase 'T8 everything listed is installed: no note' $apps2 '"ExcludeIds": []' -envs @{ KIUTD_UPGRADES = 'Git.Git,GnuPG.GnuPG' }

''; '######## Part P, 1.4.2: real winget output from PC024 replayed'
SCase 'P1 PC024 3 Nov output (1.2.3 run): 13 listed, 11 installed' $apps '"ExcludeIds": []' -envs @{ KIUTD_REPLAY = "$d\replay-1103.txt" }


''; '######## Part N, 1.4.3 and 1.4.4: result messages and status file (messages written to a file, not shown)'
function ShowMsgs { if (Test-Path "$data\messages.txt") { Get-Content "$data\messages.txt" | ForEach-Object { "   | $_" } } }
$apps3 = @('Git.Git|2.40.0', 'Oracle.VirtualBox|7.2.20', 'Microsoft.Outlook|1.2025.1121.100', 'PuTTY.PuTTY|0.84.0.0', 'GnuPG.GnuPG|2.5.17')
$mix = @{ KIUTD_UPGRADES = 'Git.Git,Oracle.VirtualBox,Microsoft.Outlook,PuTTY.PuTTY'; KIUTD_NOTTRIED = 'GnuPG.GnuPG'; KIUTD_RESTART = 'Oracle.VirtualBox'; KIUTD_REOPEN = 'Microsoft.Outlook'; KIUTD_FAIL = 'PuTTY.PuTTY'; KIUTD_LISTMODE = '1' }
SCase 'N1 no ShowResults: silent, no status file, no messages' $apps3 '"ExcludeIds": []' -envs $mix
SCase 'N2 ShowResults true: updated, failed, restart, start again, listed but not updated' $apps3 '"ExcludeIds": [], "ShowResults": true' -envs $mix
ShowMsgs
SCase 'N3 ShowResults lists another computer only: silent' $apps3 '"ExcludeIds": [], "ShowResults": [ "OTHERPC" ]' -envs $mix
SCase 'N4 ShowResults lists this computer (lower case)' $apps3 ('"ExcludeIds": [], "ShowResults": [ "OTHERPC", "' + $pc.ToLower() + '" ]') -envs $mix
SCase 'N5 installer -ShowResults, config.json says false' $apps3 '"ExcludeIds": [], "ShowResults": false, "ShowResultsSwitch": true' -envs $mix
Set-Content "$net\config.json" '{ "ExcludeIds": [], "ShowResults": true }' -Encoding UTF8
SCase 'N6 NETLOGON turns the messages on, installed copy has none' $apps3 ('"ExcludeIds": [], ' + $netCfg) -envs $mix
'   installed config.json ShowResults now: ' + ((Get-Content "$d\export\config.json" -Raw | ConvertFrom-Json).ShowResults | ConvertTo-Json -Compress)
Set-Content "$net\config.json" '{ "ExcludeIds": [], "ShowResults": "yes" }' -Encoding UTF8
SCase 'N7 NETLOGON file with ShowResults "yes": file refused, installed setting used' $apps3 ('"ExcludeIds": [], ' + $netCfg) -envs $mix
SCase 'N8 User task with ShowResults' $apps3 '"ExcludeIds": [], "ShowResults": true' -mode 'User' -envs $mix
SCase 'N9 run stopped by an invalid local-config.json, ShowResults on' $apps3 '"ExcludeIds": [], "ShowResults": true' -envs $mix -local '{ "ExcludeIds": [ "VirtualBox" ] }'
SCase 'N10 Node.js 20 replaced, ShowResults on' @('OpenJS.NodeJS.20|20.18.0') ('"ExcludeIds": [], "ShowResults": true, ' + $rule) -envs @{ KIUTD_LISTMODE = '1' }
SCase 'N11 PC024 3 Nov output replayed, ShowResults on, then GnuPG and MobaXterm still listed' $apps '"ExcludeIds": [], "ShowResults": true' -envs @{ KIUTD_REPLAY = "$d\replay-1103.txt"; KIUTD_REPLAY_AFTER = "$d\replay-1103-after.txt" }
ShowMsgs
SCase 'N12 installed config.json with ShowResults "yes" (edited by hand): warning, silent' $apps3 '"ExcludeIds": [], "ShowResults": "yes"' -envs $mix
SCase 'N13 nothing to update, ShowResults on' @('Git.Git|2.40.0') '"ExcludeIds": [], "ShowResults": true' -envs @{ KIUTD_LISTMODE = '1' }
ShowMsgs
SCase 'N14 list only with ShowResults: no messages' $apps3 '"ExcludeIds": [], "ShowResults": true' -envs $mix -extra @('-ListOnly')
SCase 'N15 skipped start (this week done) with ShowResults: no messages' $one ('"ExcludeIds": [], "ShowResults": true, ' + $wk) -envs $upOne -NoForce -Last $slotNow.AddDays(-1)

''; '######## Part MS, 1.4.4: who gets which message (signed-in users from KIUTD_SESSIONS)'
$two = '1=CONTOSO\j.doe;2=CONTOSO\piet.test;3=CONTOSO\j.doe'
SCase 'MS1 two users, one of them in two sessions: each session gets both messages, each user is recorded once' $apps3 '"ExcludeIds": [], "ShowResults": true' -envs ($mix + @{ KIUTD_SESSIONS = $two })
SCase 'MS2 nobody signed in: no messages, nothing recorded' $apps3 '"ExcludeIds": [], "ShowResults": true' -envs ($mix + @{ KIUTD_SESSIONS = 'none' })
SCase 'MS3 the message service fails: logged, not recorded as sent' $apps3 '"ExcludeIds": [], "ShowResults": true' -envs ($mix + @{ KIUTD_MSGFAIL = '1' })
SCase 'MS4 User run with updates: own session only, nothing recorded in notify.sent' $apps3 '"ExcludeIds": [], "ShowResults": true' -mode 'User' -envs ($mix + @{ KIUTD_SESSIONS = '' })
SCase 'MS5 User run with nothing to update: no message' @('Git.Git|2.40.0') '"ExcludeIds": [], "ShowResults": true' -mode 'User' -envs @{ KIUTD_LISTMODE = '1'; KIUTD_SESSIONS = '' }
$many = @(1..18 | ForEach-Object { "Contoso.App$_|1.0" })
SCase 'MS6 18 apps updated: list cut at 15 names' $many '"ExcludeIds": [], "ShowResults": true' -envs @{ KIUTD_UPGRADES = (@(1..18 | ForEach-Object { "Contoso.App$_" }) -join ','); KIUTD_LISTMODE = '1' }
ShowMsgs
SCase 'MS7 run stopped by an invalid local-config.json: warning icon and the reason' $apps3 '"ExcludeIds": [], "ShowResults": true' -envs $mix -local '{ "ExcludeIds": [ "VirtualBox" ] }'
ShowMsgs

''; '######## Part D, 1.4.4: Notify task at sign-in (-Mode Notify, as SYSTEM in the real task)'
function Write-Status([string]$file, [string]$phase, [datetime]$ended, [switch]$Marker, [int]$MarkerPid = 4242) {
    $o = [ordered]@{ Run = $ended.AddMinutes(-17).ToString('o'); Mode = 'System'; Phase = $phase; Started = $ended.AddMinutes(-17).ToString('o'); Ended = $(if ($phase -eq 'done') { $ended.ToString('o') } else { '' });
                     Current = 'Visual Studio Build Tools 2026'; Index = 5; Total = 11; Handled = @(); Updated = @('Node.js (LTS) 26.13.0'); Replaced = @(); NotUpdated = @(); Restart = @(); Reopen = @(); Error = '' }
    $o | ConvertTo-Json | Set-Content "$data\$file" -Encoding UTF8
    $mk = $(if ($file -like 'user*') { 'user.running' } else { 'system.running' })
    if ($Marker) { "$($o.Run)|$MarkerPid|Microsoft.VisualStudio.BuildTools" | Set-Content "$data\$mk" -Encoding ascii } else { Remove-Item "$data\$mk" -ErrorAction SilentlyContinue }
    return $o.Run
}
$on = '"ExcludeIds": [], "ShowResults": true'
if (Test-Path $data) { Remove-Item $data -Recurse -Force }; New-Item -ItemType Directory $data -Force | Out-Null
# busy run: the marker names a process that runs (this test) and started before the run
$null = Write-Status 'system.status.json' 'running' (Get-Date).AddMinutes(17) -Marker -MarkerPid $PID
SCase 'D1 System run busy: start message for who signs in' $apps $on -mode 'Notify' -extra @('-For', 'System') -KeepData
SCase 'D2 same user signs in again while it is busy: nothing' $apps $on -mode 'Notify' -extra @('-For', 'System') -KeepData
$null = Write-Status 'system.status.json' 'running' (Get-Date)
SCase 'D3 status says busy but the run marker is gone (run was stopped): nothing' $apps $on -mode 'Notify' -extra @('-For', 'System') -KeepData
$null = Write-Status 'system.status.json' 'done' (Get-Date).AddHours(-1)
SCase 'D4 System run done an hour ago: result message, recorded' $apps $on -mode 'Notify' -extra @('-For', 'System') -KeepData
SCase 'D5 same user again: nothing' $apps $on -mode 'Notify' -extra @('-For', 'System') -KeepData
SCase 'D6 a second user signs in: only that user gets it' $apps $on -mode 'Notify' -extra @('-For', 'System') -KeepData -envs @{ KIUTD_SESSIONS = '1=CONTOSO\j.doe;2=CONTOSO\piet.test' }
$null = Write-Status 'system.status.json' 'done' (Get-Date).AddHours(-13)
SCase 'D7 run done 13 hours ago: nothing' $apps $on -mode 'Notify' -extra @('-For', 'System') -KeepData
Remove-Item "$data\system.status.json"
SCase 'D8 no run to show: nothing' $apps $on -mode 'Notify' -extra @('-For', 'System') -KeepData
$null = Write-Status 'system.status.json' 'done' (Get-Date).AddMinutes(-5)
SCase 'D9 ShowResults off: nothing' $apps '"ExcludeIds": []' -mode 'Notify' -extra @('-For', 'System') -KeepData
$null = Write-Status 'user.status.json' 'done' (Get-Date).AddMinutes(-1)
SCase 'D10 -For User: own run, own session' $apps $on -mode 'Notify' -extra @('-For', 'User') -KeepData -envs @{ KIUTD_SESSIONS = '' }
'   notify.log lines: ' + @(Get-Content "$data\notify.log" -ErrorAction SilentlyContinue).Count
Remove-Item "$data\notify.sent", "$data\notify.log" -ErrorAction SilentlyContinue
$null = Write-Status 'system.status.json' 'running' (Get-Date).AddMinutes(17) -Marker -MarkerPid $deadPid
SCase 'D11 status busy, marker of this run, its process gone (stopped by a restart, as on VM-PROXY01 6 Nov 14:47): nothing' $apps $on -mode 'Notify' -extra @('-For', 'System') -KeepData
$null = Write-Status 'system.status.json' 'running' (Get-Date) -Marker -MarkerPid $PID
SCase 'D12 status busy, marker of this run, its process ID now used by a process started after the run: nothing' $apps $on -mode 'Notify' -extra @('-For', 'System') -KeepData
'   notify.log lines: ' + @(Get-Content "$data\notify.log" -ErrorAction SilentlyContinue).Count

''; '######## Part MT, 1.4.4: message texts (Get-RunMessage)'
$inv = [Globalization.CultureInfo]::InvariantCulture
$rtok = $null; $rerr = $null
$rast = [Management.Automation.Language.Parser]::ParseFile("$d\export\Invoke-KeepItUpToDater.ps1", [ref]$rtok, [ref]$rerr)
function RFn([string]$fn) { ($rast.FindAll({ param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq $fn }, $true) | Select-Object -First 1).Extent.Text }
$Name = 'KeepItUpToDater'; $sysDir = Join-Path $env:ProgramData $Name
foreach ($fn in 'Get-RunMessage', 'Send-SessionMessage') { . ([scriptblock]::Create((RFn $fn))) }
function Write-Log([string]$m) { "   log: $m" }
$t0 = Get-Date '2026-11-05 10:30:48'
$states = [ordered]@{
    'MT1-start' = @{ Kind = 'start'; For = 'System'; St = [pscustomobject]@{ Run = 'r'; Phase = 'running'; Started = $t0.ToString('o'); Index = 1; Total = 11 } }
    'MT2-start-user' = @{ Kind = 'start'; For = 'User'; St = [pscustomobject]@{ Run = 'r'; Phase = 'running'; Started = $t0.ToString('o'); Index = 1; Total = 1 } }
    'MT3-done' = @{ Kind = 'end'; For = 'System'; St = [pscustomobject]@{ Run = 'r'; Phase = 'done'; Started = $t0.ToString('o'); Ended = $t0.AddMinutes(1).ToString('o');
                    Updated = @('Visual Studio BuildTools 2026 18.11.3'); Replaced = @(); NotUpdated = @('GNU Privacy Guard (2.5.24 available)', 'MobaXterm (26.6.0.5560 available)'); Restart = @(); Reopen = @(); Error = '' } }
    'MT4-done-big' = @{ Kind = 'end'; For = 'System'; St = [pscustomobject]@{ Run = 'r'; Phase = 'done'; Started = $t0.ToString('o'); Ended = $t0.AddMinutes(17).ToString('o');
                    Updated = @('TeamViewer 15.83.5', 'Node.js (LTS) 26.13.0', 'AD Info 1.8.2', 'PuTTY 0.85.0.0', 'AXIS IP Utility 5.3.1.0', 'Microsoft Visual C++ v14 Redistributable (x86) 14.51.36247.0', 'Python Launcher 3.14.7', 'Microsoft Visual C++ v14 Redistributable (x64) 14.51.36247.0', 'Outlook for Windows 1.2026.812.100', 'Windows Subsystem for Linux 2.7.14');
                    Replaced = @(); NotUpdated = @('GNU Privacy Guard (2.5.24 available)', 'MobaXterm (26.6.0.5560 available)'); Restart = @('Visual Studio BuildTools 2026'); Reopen = @('Outlook for Windows', 'Windows Subsystem for Linux'); Error = '' } }
    'MT5-quiet' = @{ Kind = 'end'; For = 'System'; St = [pscustomobject]@{ Run = 'r'; Phase = 'done'; Started = $t0.ToString('o'); Ended = $t0.AddMinutes(1).ToString('o'); Updated = @(); Replaced = @(); NotUpdated = @(); Restart = @(); Reopen = @(); Error = '' } }
    'MT6-quiet-user' = @{ Kind = 'end'; For = 'User'; St = [pscustomobject]@{ Run = 'r'; Phase = 'done'; Started = $t0.ToString('o'); Ended = $t0.AddMinutes(1).ToString('o'); Updated = @(); Replaced = @(); NotUpdated = @(); Restart = @(); Reopen = @(); Error = '' } }
    'MT7-error' = @{ Kind = 'end'; For = 'System'; St = [pscustomobject]@{ Run = 'r'; Phase = 'done'; Started = $t0.ToString('o'); Ended = $t0.AddMinutes(1).ToString('o'); Updated = @(); Replaced = @(); NotUpdated = @(); Restart = @(); Reopen = @();
                    Error = 'winget did not start (exit code 0xC0000135). The Visual C++ v14 runtime is missing, too old or waiting for a restart.' } }
}
foreach ($k in $states.Keys) {
    "--- $k"
    $m = Get-RunMessage $states[$k].Kind $states[$k].St $states[$k].For
    if (-not $m) { '   no message'; continue }
    "   timeout $($m.Timeout), icon 0x{0:X2}" -f $m.Icon
    foreach ($ln in ("$($m.Text)" -split "`r`n")) { "   | $ln" }
}

''; '######## Part MR, 1.4.4: real message in this session (Windows message service and msg.exe), screenshots'
Add-Type -AssemblyName System.Windows.Forms, System.Drawing
$shots = Join-Path $env:USERPROFILE 'KIUTD-Test'
function Shot([string]$file) {
    $bnd = [Windows.Forms.SystemInformation]::VirtualScreen
    $bmp = New-Object Drawing.Bitmap($bnd.Width, $bnd.Height)
    $g = [Drawing.Graphics]::FromImage($bmp); $g.CopyFromScreen($bnd.Left, $bnd.Top, 0, 0, $bmp.Size); $g.Dispose()
    $bmp.Save((Join-Path $shots $file), [Drawing.Imaging.ImageFormat]::Png); $bmp.Dispose(); "   screenshot: $file"
}
$mySession = [Diagnostics.Process]::GetCurrentProcess().SessionId
$script:wtsApi = $null
foreach ($k in 'MT1-start', 'MT4-done-big', 'MT7-error') {
    "--- MR $k (message service)"
    $m = Get-RunMessage $states[$k].Kind $states[$k].St $states[$k].For
    $sw = [Diagnostics.Stopwatch]::StartNew()
    "   sent: $(Send-SessionMessage $mySession $m.Text 20 $m.Icon), returned after $($sw.ElapsedMilliseconds) ms (does not wait for OK)"
    Start-Sleep -Seconds 2; Shot "msg-$k.png"
    Start-Sleep -Seconds 19
}
"--- MR MT3-done (msg.exe, as when the message service is not available)"
$m = Get-RunMessage 'end' $states['MT3-done'].St 'System'
$script:wtsApi = $false
"   sent: $(Send-SessionMessage $mySession $m.Text 20 $m.Icon)"
Start-Sleep -Seconds 2; Shot 'msg-MT3-msgexe.png'
Start-Sleep -Seconds 19


''; '######## Part PF, 1.4.5: proxy functions (Get-ProxyChoice, Get-ConnectionProxy, Set-ProcessProxy, Get-SourceDiagnosis)'
foreach ($fn in 'Get-ProxyChoice', 'Set-ProcessProxy', 'ConvertTo-ProxyHost', 'Get-ConnectionProxy', 'Get-SourceDiagnosis') { . ([scriptblock]::Create((RFn $fn))) }
$ProxyPattern  = '^https?://[A-Za-z0-9][A-Za-z0-9.-]{0,252}:[0-9]{1,5}/?$'
$BypassPattern = '^[A-Za-z0-9.*?<>;_-]{0,512}$'
function PC([string]$title, [string]$json, [bool]$sw = $false) {
    $c = Get-ProxyChoice ($json | ConvertFrom-Json) $sw
    "--- $title"; "   on: $($c.On); address: $($c.Address); direct: $($c.Bypass); source: $($c.Source); problem: $($c.Problem)"
}
$pre = $env:COMPUTERNAME.Substring(0, 3)
PC 'PF1 nothing set' '{}'
PC 'PF2 "UseProxy": true, Proxy with a slash at the end' '{ "Proxy": "http://192.0.2.163:8080/", "UseProxy": true }'
PC 'PF3 list, pattern with *' ('{ "Proxy": "http://192.0.2.163:8080", "UseProxy": [ "VM-*", "' + $pre.ToLower() + '*" ] }')
PC 'PF4 list, pattern with ?' ('{ "Proxy": "http://192.0.2.163:8080", "UseProxy": [ "' + ('?' * $env:COMPUTERNAME.Length) + '" ] }')
PC 'PF5 list without this computer' '{ "Proxy": "http://192.0.2.163:8080", "UseProxy": [ "VM-*", "PC024" ] }'
PC 'PF6 "UseProxy": false, installer -UseProxy' '{ "Proxy": "http://proxy.contoso.local:3128", "UseProxy": false }' $true
PC 'PF7 on without an address' '{ "UseProxy": true }'
PC 'PF8 address with a path' '{ "Proxy": "http://192.0.2.163:8080/proxy.pac", "UseProxy": true }'
PC 'PF9 "UseProxy": "VM-*" (text, not a list)' '{ "Proxy": "http://192.0.2.163:8080", "UseProxy": "VM-*" }'
PC 'PF10 an address but off' '{ "Proxy": "http://192.0.2.163:8080" }'
'--- PF11 Get-ConnectionProxy on WinHTTP-style values (test key in HKCU)'
$tk = 'HKCU:\Software\KIUTD-Test'; New-Item $tk -Force | Out-Null
function Blob([int]$flags, [string]$proxy, [string]$bypass) {
    $b = New-Object System.Collections.Generic.List[byte]
    $b.AddRange([BitConverter]::GetBytes([int]0x28)); $b.AddRange([BitConverter]::GetBytes([int]0)); $b.AddRange([BitConverter]::GetBytes($flags))
    $b.AddRange([BitConverter]::GetBytes([int]$proxy.Length)); $b.AddRange([Text.Encoding]::ASCII.GetBytes($proxy))
    $b.AddRange([BitConverter]::GetBytes([int]$bypass.Length)); $b.AddRange([Text.Encoding]::ASCII.GetBytes($bypass))
    return ,$b.ToArray()
}
Set-ItemProperty $tk -Name Direct -Value (Blob 1 '' '') -Type Binary
Set-ItemProperty $tk -Name Proxy -Value (Blob 3 'http://192.0.2.163:8080' '<local>;*.contoso.local') -Type Binary
Set-ItemProperty $tk -Name Short -Value ([byte[]](1, 2, 3)) -Type Binary
foreach ($v in 'Direct', 'Proxy', 'Short', 'Missing') { "   $v -> '$(Get-ConnectionProxy $tk $v)'" }
Remove-Item $tk -Recurse -Force
'--- PF12 Set-ProcessProxy: the run''s own downloads go through the proxy (closed port 127.0.0.1:9), and direct again when off'
$url = 'https://cdn.winget.microsoft.com/cache/source2.msix'
Set-ProcessProxy @{ On = $true; Address = 'http://127.0.0.1:9'; Bypass = '<local>' }
try { $x = Invoke-WebRequest $url -Method Head -UseBasicParsing -TimeoutSec 20; "   with proxy: HTTP $([int]$x.StatusCode)" } catch { "   with proxy: $($_.Exception.Message)" }
'   DefaultWebProxy for ' + $url + ': ' + [Net.WebRequest]::DefaultWebProxy.GetProxy($url)
'   DefaultWebProxy for http://dc01.contoso.local: ' + [Net.WebRequest]::DefaultWebProxy.GetProxy('http://dc01.contoso.local')
Set-ProcessProxy @{ On = $true; Address = 'http://127.0.0.1:9'; Bypass = '<local>;*.contoso.local' }
'   with *.contoso.local direct, for http://dc01.contoso.local: ' + [Net.WebRequest]::DefaultWebProxy.GetProxy('http://dc01.contoso.local')
Set-ProcessProxy @{ On = $false }
try { $x = Invoke-WebRequest $url -Method Head -UseBasicParsing -TimeoutSec 20; "   proxy off: HTTP $([int]$x.StatusCode)" } catch { "   proxy off: $($_.Exception.Message)" }
'--- PF13 download location not reachable, proxy off: the message names the proxy setting'
$SourcePackageUrl = 'https://127.0.0.1:9/source2.msix'; $runStart = Get-Date
$proxy = @{ On = $false }
"   diagnosis: $(@(Get-SourceDiagnosis)[-1])"
'--- PF14 the same with the proxy on'
$proxy = @{ On = $true; Address = 'http://192.0.2.163:8080' }
"   diagnosis: $(@(Get-SourceDiagnosis)[-1])"

''; '######## Part TS, 1.4.3: -TestSchedule start (once per week rule set aside once)'
$tsCfg = '"ExcludeIds": [], ' + $wk
SCase 'TS1 test start 1 minute ago, this week''s run done: runs, start used' $one $tsCfg -envs $upOne -NoForce -Last $slotNow.AddDays(-1) -TestAt (Get-Date).AddMinutes(-1)
SCase 'TS2 a second start right after (same test time): skipped' $one $tsCfg -envs $upOne -NoForce -Last $slotNow.AddDays(-1) -KeepData
SCase 'TS3 test time in 30 minutes: skipped' $one $tsCfg -envs $upOne -NoForce -Last $slotNow.AddDays(-1) -TestAt (Get-Date).AddMinutes(30)
SCase 'TS4 test time 3 hours ago: skipped' $one $tsCfg -envs $upOne -NoForce -Last $slotNow.AddDays(-1) -TestAt (Get-Date).AddHours(-3)
SCase 'TS5 User task, test start 1 minute ago: runs, start used' $one $tsCfg -mode 'User' -envs $upOne -NoForce -Last $slotNow.AddDays(-1) -TestAt (Get-Date).AddMinutes(-1)
SCase 'TS6 test start and ShowResults: the test run sends the messages' $one ('"ExcludeIds": [], "ShowResults": true, ' + $wk) -envs @{ KIUTD_UPGRADES = 'Git.Git'; KIUTD_LISTMODE = '1' } -NoForce -Last $slotNow.AddDays(-1) -TestAt (Get-Date).AddMinutes(-1)


''; '######## Part PX, 1.4.5: the System task sets and removes the proxy (computer settings simulated in a file)'
$script:runDir = "$d\export"
$pxf = Join-Path $d 'pxstate.json'
$addr = 'http://192.0.2.163:8080'
$pxOn = '"Proxy": "' + $addr + '", "ProxyBypass": "<local>;*.contoso.local", "UseProxy": true'
function PXSet([string]$wg = '', [string]$wh = '', [string]$ie = '') { [ordered]@{ Winget = $wg; WinHttp = $wh; SystemIe = $ie } | ConvertTo-Json | Set-Content $pxf -Encoding UTF8 }
function PXShow {
    $f = Get-Content $pxf -Raw | ConvertFrom-Json
    "   computer now: winget '$($f.Winget)', WinHTTP '$($f.WinHttp)', SYSTEM '$($f.SystemIe)'"
    '   proxy.json: ' + $(if (Test-Path "$data\proxy.json") { ((Get-Content "$data\proxy.json" -Raw) -replace '\s+', ' ').Trim() } else { 'none' })
}
$pxe = @{ KIUTD_PX = $pxf }
$git = @('Git.Git|2.40.0')
PXSet; SCase 'PX1 no proxy in config.json' $git '"ExcludeIds": []' -envs $pxe; PXShow
PXSet; SCase 'PX2 "UseProxy": true with Proxy and ProxyBypass: all three set' $git ('"ExcludeIds": [], ' + $pxOn) -envs $pxe; PXShow
SCase 'PX3 next run, same settings: nothing changed' $git ('"ExcludeIds": [], ' + $pxOn) -envs $pxe -KeepData; PXShow
SCase 'PX4 next run with "UseProxy": false: the three removed' $git ('"ExcludeIds": [], "Proxy": "' + $addr + '", "UseProxy": false') -envs $pxe -KeepData; PXShow
PXSet; SCase 'PX5 "UseProxy": [ "VM-*" ], this computer not in it' $git ('"ExcludeIds": [], "Proxy": "' + $addr + '", "UseProxy": [ "VM-*" ]') -envs $pxe; PXShow
PXSet; SCase 'PX6 "UseProxy" pattern that matches this computer' $git ('"ExcludeIds": [], "Proxy": "' + $addr + '", "UseProxy": [ "VM-*", "' + $pre + '*" ]') -envs $pxe; PXShow
PXSet; SCase 'PX7 "UseProxy": false and installer -UseProxy' $git ('"ExcludeIds": [], "Proxy": "' + $addr + '", "UseProxy": false, "UseProxySwitch": true') -envs $pxe; PXShow
PXSet; SCase 'PX8 installed "UseProxy": true without Proxy' $git '"ExcludeIds": [], "UseProxy": true' -envs $pxe; PXShow
PXSet '' 'http://10.1.1.1:3128' ''; SCase 'PX9 WinHTTP already set to another proxy: left as it is' $git ('"ExcludeIds": [], ' + $pxOn) -envs $pxe; PXShow
PXSet $addr $addr '192.0.2.163:8080'; SCase 'PX10 all three set by hand to the same proxy: nothing changed, not recorded' $git ('"ExcludeIds": [], ' + $pxOn) -envs $pxe; PXShow
SCase 'PX11 then "UseProxy": false: the settings made by hand stay' $git ('"ExcludeIds": [], "Proxy": "' + $addr + '", "UseProxy": false') -envs $pxe -KeepData; PXShow
PXSet; SCase 'PX12a on' $git ('"ExcludeIds": [], ' + $pxOn) -envs $pxe
SCase 'PX12 then a new address in config.json' $git '"ExcludeIds": [], "Proxy": "http://10.0.0.5:3128", "UseProxy": true' -envs $pxe -KeepData; PXShow
PXSet; SCase 'PX13a on' $git ('"ExcludeIds": [], ' + $pxOn) -envs $pxe
$f = Get-Content $pxf -Raw | ConvertFrom-Json; $f.WinHttp = 'http://10.1.1.1:3128'; $f | ConvertTo-Json | Set-Content $pxf
SCase 'PX13 someone changed WinHTTP, then "UseProxy": false: WinHTTP left, the rest removed' $git ('"ExcludeIds": [], "Proxy": "' + $addr + '", "UseProxy": false') -envs $pxe -KeepData; PXShow
Set-Content "$net\config.json" ('{ "ExcludeIds": [], ' + $pxOn + ' }') -Encoding UTF8
PXSet; SCase 'PX14 NETLOGON turns the proxy on' $git ('"ExcludeIds": [], ' + $netCfg) -envs $pxe; PXShow
'   installed config.json now: ' + ((Get-Content "$script:runDir\config.json" -Raw | ConvertFrom-Json | Select-Object Proxy, ProxyBypass, UseProxy | ConvertTo-Json -Compress))
Set-Content "$net\config.json" '{ "ExcludeIds": [], "Proxy": "192.0.2.163:8080", "UseProxy": true }' -Encoding UTF8
PXSet; SCase 'PX15 NETLOGON with an invalid Proxy: refused, installed copy used' $git ('"ExcludeIds": [], ' + $netCfg) -envs $pxe; PXShow
Set-Content "$net\config.json" ('{ "ExcludeIds": [], ' + $rule + ' }') -Encoding UTF8
PXSet; SCase 'PX16 list only with "UseProxy": true: nothing set' $git ('"ExcludeIds": [], ' + $pxOn) -envs $pxe -extra @('-ListOnly'); PXShow
PXSet; SCase 'PX17 User task with "UseProxy": true: nothing set (System task only)' $git ('"ExcludeIds": [], ' + $pxOn) -mode 'User' -envs $pxe; PXShow
PXSet; SCase 'PX18 setting WinHTTP fails' $git ('"ExcludeIds": [], ' + $pxOn) -envs @{ KIUTD_PX = $pxf; KIUTD_PXFAIL = 'WinHttp' }; PXShow
SCase 'PX19 next run: WinHTTP set this time' $git ('"ExcludeIds": [], ' + $pxOn) -envs $pxe -KeepData; PXShow
PXSet; SCase 'PX20a on' $git ('"ExcludeIds": [], ' + $pxOn) -envs $pxe
$nb = @(Get-Content "$data\system.log" | Where-Object { $_ -match 'run started' }).Count
SCase 'PX20 -ClearProxy (used by the installer''s -Uninstall)' $git ('"ExcludeIds": [], ' + $pxOn) -envs $pxe -KeepData -extra @('-ClearProxy'); PXShow
'   run headers in system.log: before ' + $nb + ', after ' + @(Get-Content "$data\system.log" | Where-Object { $_ -match 'run started' }).Count
PXSet; SCase 'PX21a on' $git ('"ExcludeIds": [], ' + $pxOn) -envs $pxe
$f = Get-Content $pxf -Raw | ConvertFrom-Json; $f.Winget = ''; $f | ConvertTo-Json | Set-Content $pxf
SCase 'PX21 winget does not show DefaultProxy, then "UseProxy": false: removed anyway' $git ('"ExcludeIds": [], "Proxy": "' + $addr + '", "UseProxy": false') -envs $pxe -KeepData; PXShow

''; '######## Part TL, 1.4.6: time limit per run (task settings simulated in a file)'
$script:runDir = "$d\export"
$tlf = Join-Path $d 'tlstate.json'
$tle = @{ KIUTD_TL = $tlf }
function TLSet([string]$sys = 'PT3H', [string]$usr = 'PT3H') { [ordered]@{ System = $sys; User = $usr } | ConvertTo-Json | Set-Content $tlf -Encoding UTF8 }
function TLShow { $f = Get-Content $tlf -Raw | ConvertFrom-Json; "   tasks now: System '$($f.System)', User '$($f.User)'" }
TLSet; SCase 'TL1 no MaxRunHours, tasks at 3 hours: nothing changed' $git '"ExcludeIds": []' -envs $tle; TLShow
TLSet; SCase 'TL2 "MaxRunHours": 0: both tasks set to no limit' $git '"ExcludeIds": [], "MaxRunHours": 0' -envs $tle; TLShow
SCase 'TL3 next run, same setting: nothing changed' $git '"ExcludeIds": [], "MaxRunHours": 0' -envs $tle -KeepData; TLShow
TLSet 'PT3H' ''; SCase 'TL4 "MaxRunHours": 8, no User task: only System set' $git '"ExcludeIds": [], "MaxRunHours": 8' -envs $tle; TLShow
TLSet; SCase 'TL5 installer -MaxRunHours 0 and "MaxRunHours": 8: no limit' $git '"ExcludeIds": [], "MaxRunHours": 8, "MaxRunHoursSwitch": 0' -envs $tle; TLShow
TLSet 'P3D' 'P3D'; SCase 'TL6 "MaxRunHours": 72, tasks already at 72 hours (P3D): nothing changed' $git '"ExcludeIds": [], "MaxRunHours": 72' -envs $tle; TLShow
TLSet; SCase 'TL7 installed "MaxRunHours": 99: warning, 3 hours kept' $git '"ExcludeIds": [], "MaxRunHours": 99' -envs $tle; TLShow
Set-Content "$net\config.json" '{ "ExcludeIds": [], "MaxRunHours": 12 }' -Encoding UTF8
TLSet; SCase 'TL8 NETLOGON "MaxRunHours": 12, installed copy has none' $git ('"ExcludeIds": [], ' + $netCfg) -envs $tle; TLShow
'   installed config.json now: ' + ((Get-Content "$script:runDir\config.json" -Raw | ConvertFrom-Json | Select-Object MaxRunHours, MaxRunHoursSwitch | ConvertTo-Json -Compress))
TLSet; SCase 'TL9 NETLOGON "MaxRunHours": 12, installer -MaxRunHours 0: the switch wins, no limit' $git ('"ExcludeIds": [], "MaxRunHoursSwitch": 0, ' + $netCfg) -envs $tle; TLShow
Set-Content "$net\config.json" '{ "ExcludeIds": [], "MaxRunHours": "lots" }' -Encoding UTF8
TLSet; SCase 'TL10 NETLOGON "MaxRunHours": "lots": refused, installed copy used' $git ('"ExcludeIds": [], "MaxRunHours": 8, ' + $netCfg) -envs $tle; TLShow
Set-Content "$net\config.json" ('{ "ExcludeIds": [], ' + $rule + ' }') -Encoding UTF8
TLSet; SCase 'TL11 changing the System task fails: warning, User task still set' $git '"ExcludeIds": [], "MaxRunHours": 0' -envs @{ KIUTD_TL = $tlf; KIUTD_TLFAIL = 'System' }; TLShow
SCase 'TL12 next run: System task set' $git '"ExcludeIds": [], "MaxRunHours": 0' -envs $tle -KeepData; TLShow
TLSet; SCase 'TL13 list only: nothing changed' $git '"ExcludeIds": [], "MaxRunHours": 0' -envs $tle -extra @('-ListOnly'); TLShow
TLSet; SCase 'TL14 User task: nothing changed' $git '"ExcludeIds": [], "MaxRunHours": 0' -mode 'User' -envs $tle; TLShow
SCase 'TL15 run that did not finish, MaxRunHours 8: the note names 8 hours' $apps '"ExcludeIds": [], "MaxRunHours": 8' -envs $ups -Marker $stale
SCase 'TL16 run that did not finish, no limit: the note leaves the limit out' $apps '"ExcludeIds": [], "MaxRunHours": 0' -envs $ups -Marker $stale

''; '######## Part V, 1.4.5: real winget output from the pilot VM of 6 November replayed (22 listed, one ID shortened by winget)'
$script:runDir = "$d\export"
$vmApps = @('Git.Git|2.51.0')
SCase 'VR1 VM output of 6 Nov: ZAP and Edge named as listed but not updated, Visual Studio (shortened ID) matched' $vmApps '"ExcludeIds": []' -envs @{ KIUTD_REPLAY = "$d\replay-1106.txt" }
SCase 'VR2 the same with ShowResults on, then Office, ZAP and Edge still listed' $vmApps '"ExcludeIds": [], "ShowResults": true' -envs @{ KIUTD_REPLAY = "$d\replay-1106.txt"; KIUTD_REPLAY_AFTER = "$d\replay-1106-after.txt" }
ShowMsgs

''; '######## Part R: control with the 1.4.3 updater (expected: the Notify task started for a window)'
$script:runDir = "$d\export-143"
SCase 'R-N2 N2 on 1.4.3' $apps3 '"ExcludeIds": [], "ShowResults": true' -envs $mix
$script:runDir = "$d\export-144"
SCase 'R-VR2 VR2 on 1.4.4 (expected: Edge missing, the table stopped at the shortened ID)' $vmApps '"ExcludeIds": [], "ShowResults": true' -envs @{ KIUTD_REPLAY = "$d\replay-1106.txt"; KIUTD_REPLAY_AFTER = "$d\replay-1106-after.txt" }
ShowMsgs
