# Keep It Up To Dater 1.5.0: fixes from the security review of 19 Nov 2026 (F-01 to F-09)
# Runs as a standard user next to the installer, stub.ps1, fake-un.ps1 and test.ps1 (for New-TestRunner).
# Keep It Up To Dater 1.4.8: older copies ("RemoveOlder"), 1.4.7 cases plus the "*" rule for every package listed twice.
# Runs as a standard user next to the installer, stub.ps1, fake-un.ps1 and test.ps1 (for New-TestRunner).
$ErrorActionPreference = 'Continue'
$d = $PSScriptRoot
$tok = $null; $err = $null
$ast = [Management.Automation.Language.Parser]::ParseFile("$d\Install-KeepItUpToDater.ps1", [ref]$tok, [ref]$err); "installer parse errors: $($err.Count)"
function Fn([string]$name) { ($ast.FindAll({ param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq $name }, $true) | Select-Object -First 1).Extent.Text }
$tast = [Management.Automation.Language.Parser]::ParseFile("$d\test.ps1", [ref]$tok, [ref]$err)
function TFn([string]$name) { ($tast.FindAll({ param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq $name }, $true) | Select-Object -First 1).Extent.Text }
''; '######## Setup: exported updater with the test patches'
$data = Join-Path $d 'data150'; $localDir = Join-Path $d 'local150'
$me = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
foreach ($x in $data, $localDir) { if (Test-Path $x) { Remove-Item $x -Recurse -Force }; New-Item -ItemType Directory $x -Force | Out-Null }
. ([scriptblock]::Create((TFn 'New-TestRunner')))
New-TestRunner "$d\Install-KeepItUpToDater.ps1" "$d\export150"
$run = Get-Content "$d\export150\run.ps1" -Raw
# The winget stand-in is a script: output that is read must come from its own process
$p147 = @(
    @('$out = @(& $winget list --id $Id', '$out = @(& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $winget list --id $Id'),
    @('$out = @(& $winget list --source winget --scope machine', '$out = @(& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $winget list --source winget --scope machine'),
    @('$list = @(& $winget pin list', '$list = @(& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $winget pin list'),
    @('function Get-UninstallEntries {', "function Get-UninstallEntries {`r`n    if (`$env:KIUTD_ARP -like '*.json') { return @(@((Get-Content `$env:KIUTD_ARP -Raw | ConvertFrom-Json)) | Where-Object { Test-Path -LiteralPath `$_.Path }) }")
)
foreach ($pt in $p147) { if ($run.Contains($pt[0])) { $run = $run.Replace($pt[0], $pt[1]) } else { "PATCH NOT FOUND: $($pt[0])" } }
Set-Content "$d\export150\run.ps1" $run -Encoding UTF8
$rast = [Management.Automation.Language.Parser]::ParseFile("$d\export150\Invoke-KeepItUpToDater.ps1", [ref]$tok, [ref]$err)
function RFn([string]$fn) { ($rast.FindAll({ param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq $fn }, $true) | Select-Object -First 1).Extent.Text }
. ([scriptblock]::Create((($rast.FindAll({ param($n) $n -is [Management.Automation.Language.AssignmentStatementAst] -and "$($n.Left)" -eq '$IdPattern' }, $true) | Select-Object -First 1).Extent.Text)))

$env:KIUTD_STATE = Join-Path $data 'state.txt'
$arpRoot = 'HKCU:\Software\KIUTD-Test150'
$arpFile = Join-Path $data 'arp.json'
function New-Arp([object[]]$entries) {
    if (Test-Path $arpRoot) { Remove-Item $arpRoot -Recurse -Force }
    $out = @()
    $n = 0
    foreach ($e in $entries) {
        $n++
        $key = "$arpRoot\E$n"
        New-Item -Path $key -Force | Out-Null
        $cmd = '"' + (Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe') + '" -NoProfile -ExecutionPolicy Bypass -File "' + "$d\fake-un.ps1" + '" -Key "' + "Registry::HKEY_CURRENT_USER\Software\KIUTD-Test150\E$n" + '" -State "' + $env:KIUTD_STATE + '" -Line "' + $e.Line + '"' + $(if ($e.Extra) { ' ' + $e.Extra } else { '' })
        $out += [ordered]@{ Path = "Registry::HKEY_CURRENT_USER\Software\KIUTD-Test150\E$n"; Key = "E$n"; Name = $e.Name; Version = $e.Version; Location = $(if ($e.ContainsKey('Location')) { $e.Location } else { "C:\Program Files\SmartBear\SoapUI-$($e.Version)" })
                            Uninstall = $(if ($e.Quiet) { '' } elseif ($e.Bad) { $e.Bad } else { $cmd }); Quiet = $(if ($e.Quiet) { $cmd } else { '' }) }
    }
    ConvertTo-Json -InputObject @($out) -Depth 3 | Set-Content $arpFile -Encoding UTF8
}
function ECase([string]$title, [string[]]$installed, [string]$cfgBody, [object[]]$arp, [string]$mode = 'System', [string[]]$extra = @(), [hashtable]$envs = @{}) {
    ''; "--- $title"
    Remove-Item "$data\*" -Recurse -Force -ErrorAction SilentlyContinue
    Set-Content $env:KIUTD_STATE $installed
    New-Arp $arp
    Set-Content "$d\export150\config.json" ('{ "Version": "1.5.0-test", ' + $cfgBody + ' }') -Encoding UTF8
    foreach ($k in 'KIUTD_UPGRADES', 'KIUTD_FAIL', 'KIUTD_LANG', 'KIUTD_PINFAIL', 'KIUTD_SESSIONS') { Set-Item "env:$k" '' }
    $env:KIUTD_ARP = $arpFile
    $env:KIUTD_NAMES = 'SmartBear.SoapUI|4.6.4=SoapUI 4.6.4 4.6.4;SmartBear.SoapUI|5.5.0=SoapUI 5.5.0;SmartBear.SoapUI|5.9.1=SoapUI 5.9.1;SmartBear.SoapUI|5.10.0=SoapUI 5.10.0'
    foreach ($k in $envs.Keys) { Set-Item "env:$k" $envs[$k] }
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$d\export150\run.ps1" -Mode $mode -Force @extra 2>&1 | ForEach-Object { "$_" } |
        Where-Object { $_ -match 'older|Older|Remove|remove|Running:|Would|EVENT|Finished|WARNING|Folder|installed \d|installed more|lifted|pins' } |
        ForEach-Object { '   ' + ($_ -replace '^\d{4}-\d\d-\d\d \d\d:\d\d:\d\d  ', '') }
    '   installed after: ' + (@(Get-Content $env:KIUTD_STATE | Where-Object { $_ }) -join ', ')
    '   uninstall entries left: ' + (@(Get-ChildItem $arpRoot -ErrorAction SilentlyContinue | ForEach-Object { $_.PSChildName }) -join ', ')
    '   uninstallers run: ' + (@(Get-Content "$data\uninstalls.log" -ErrorAction SilentlyContinue) -join ' | ')
    $bk = @(Get-ChildItem "$data\removed-entry-*.reg" -ErrorAction SilentlyContinue); if ($bk.Count) { '   entry backups: ' + (@($bk | ForEach-Object { ($_.Name -replace '-\d{14}', '') + ' ' + $(if ((Get-Content $_.FullName -Raw) -match 'DisplayName') { '(has DisplayName)' } else { '(EMPTY)' }) }) -join ', ') }
    if (Test-Path "$data\system.status.json") { $j = Get-Content "$data\system.status.json" -Raw | ConvertFrom-Json; "   status: removed: $(@($j.Removed) -join '; ')" }
    if (Test-Path "$data\messages.txt") { Get-Content "$data\messages.txt" | Where-Object { $_ -match 'Older copies|^    SoapUI|is done' } | ForEach-Object { "   msg | $_" } }
}

# A run of the System task with full control over config.json, its last good copy, pins and the run stamp
function SRun([string]$title, [string[]]$installed, [object]$cfgRaw, [object]$goodRaw = $null, [hashtable]$envs = @{}, [string[]]$extra = @('-Force'),
              [string[]]$pins = @(), [string[]]$owned = $null, [object[]]$arp = @(), [switch]$KeepData, [string]$mode = 'System', [string]$show = '.') {
    ''; "--- $title"
    if (-not $KeepData) { Remove-Item "$data\*" -Recurse -Force -ErrorAction SilentlyContinue }
    else { Remove-Item "$data\calls.log" -ErrorAction SilentlyContinue }
    Set-Content $env:KIUTD_STATE $installed
    New-Arp $arp
    if (-not $KeepData) {
        if ($pins.Count) { Set-Content "$($env:KIUTD_STATE).pins" $pins } else { Remove-Item "$($env:KIUTD_STATE).pins" -ErrorAction SilentlyContinue }
        if ($null -ne $owned) { Set-Content "$data\$($mode.ToLower()).pins" $owned -Encoding ascii }
    }
    $cf = "$d\export150\config.json"; $gf = "$d\export150\config.lastgood.json"
    if ($null -eq $cfgRaw) { Remove-Item $cf -ErrorAction SilentlyContinue } else { [IO.File]::WriteAllText($cf, [string]$cfgRaw) }
    if ($null -eq $goodRaw) { Remove-Item $gf -ErrorAction SilentlyContinue } elseif ($goodRaw -ne 'keep') { [IO.File]::WriteAllText($gf, [string]$goodRaw) }
    foreach ($k in 'KIUTD_UPGRADES', 'KIUTD_FAIL', 'KIUTD_LANG', 'KIUTD_PINFAIL', 'KIUTD_PINADDFAIL', 'KIUTD_SESSIONS', 'KIUTD_NOVC', 'KIUTD_OLDER', 'KIUTD_UPG_KEEPSTATE', 'KIUTD_REPLAY', 'KIUTD_EXPORT_FAIL', 'KIUTD_UPG_EXIT', 'KIUTD_NAMES', 'KIUTD_PX', 'KIUTD_PXPOLICY') { Set-Item "env:$k" '' }
    $env:KIUTD_ARP = $arpFile
    foreach ($k in $envs.Keys) { Set-Item "env:$k" $envs[$k] }
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$d\export150\run.ps1" -Mode $mode @extra 2>&1 | ForEach-Object { "$_" } |
        Where-Object { $_ -match $show -and $_ -notmatch '^\s*$' } | ForEach-Object { '   ' + ($_ -replace '^\d{4}-\d\d-\d\d \d\d:\d\d:\d\d  ', '') }
    "   exit code: $LASTEXITCODE"
    $calls = @(Get-Content "$data\calls.log" -ErrorAction SilentlyContinue)
    '   winget calls: ' + (@($calls | ForEach-Object { ($_ -split ' ')[0..1] -join ' ' } | Select-Object -Unique) -join ', ') + $(if (@($calls | Where-Object { $_ -match '^upgrade .*--all' }).Count) { ' (upgrade --all: yes)' } else { ' (upgrade --all: no)' })
    $pp = "$($env:KIUTD_STATE).pins"; '   winget pins now: ' + $(if (Test-Path $pp) { (@(Get-Content $pp | Where-Object { $_ }) -join ', ') } else { 'none' })
    $op = "$data\$($mode.ToLower()).pins"; "   $($mode.ToLower()).pins: " + $(if (Test-Path $op) { (@(Get-Content $op | Where-Object { $_ }) -join ', ') } else { 'none' })
    '   last good copy: ' + $(if (Test-Path $gf) { 'yes, ' + $(if ((Test-Path $cf) -and ([IO.File]::ReadAllText($gf) -eq [IO.File]::ReadAllText($cf))) { 'same as config.json' } else { 'differs from config.json' }) } else { 'none' })
    if (Test-Path "$data\$($mode.ToLower()).retry") { "   retry file: $((Get-Content "$data\$($mode.ToLower()).retry" -Raw).Trim() -replace '\|.*$', '')" }
    '   installed after: ' + (@(Get-Content $env:KIUTD_STATE | Where-Object { $_ }) -join ', ')
}
$good = '{ "Version": "1.5.0-test", "ExcludeIds": ["Mobatek.MobaXterm"] }'
$apps = @('Git.Git|2.40.0', 'Mobatek.MobaXterm|23.0')
$key = 'Excluded|exclusion|ERROR|WARNING|Run stopped|EVENT|Finished|last good|Retry|retry|trying again|Start skipped'

''; '######## Part S1: config.json missing or damaged (F-02)'
SRun 'S1-1 valid config.json: exclusion set, updates run, last good copy written' $apps $good -envs @{ KIUTD_UPGRADES = 'Git.Git' } -show $key
SRun 'S1-2 config.json missing, no last good copy: stopped before anything changes' $apps $null -envs @{ KIUTD_UPGRADES = 'Git.Git' } -show $key
SRun 'S1-3 config.json empty, no last good copy' $apps '' -envs @{ KIUTD_UPGRADES = 'Git.Git' } -show $key
SRun 'S1-4 config.json cut off halfway, no last good copy' $apps '{ "Version": "1.5.0-test", "ExcludeIds": ["Mobatek.Mo' -envs @{ KIUTD_UPGRADES = 'Git.Git' } -show $key
SRun 'S1-5 config.json without ExcludeIds' $apps '{ "Version": "1.5.0-test" }' -envs @{ KIUTD_UPGRADES = 'Git.Git' } -show $key
SRun 'S1-6 ExcludeIds is text, not a list' $apps '{ "Version": "1.5.0-test", "ExcludeIds": "Mobatek.MobaXterm" }' -envs @{ KIUTD_UPGRADES = 'Git.Git' } -show $key
SRun 'S1-7 config.json cut off, last good copy present: last good copy used, warning, exclusion kept' $apps '{ "Version": "1.5.0-test", "ExcludeIds": ["Mob' $good -envs @{ KIUTD_UPGRADES = 'Git.Git,Mobatek.MobaXterm' } -show $key
SRun 'S1-8 both damaged: stopped' $apps '{' '{' -envs @{ KIUTD_UPGRADES = 'Git.Git' } -show $key
SRun 'S1-9 explicitly empty exclusions are valid' $apps '{ "Version": "1.5.0-test", "ExcludeIds": [] }' -envs @{ KIUTD_UPGRADES = 'Git.Git' } -show $key
SRun 'S1-10 User task with damaged config.json: stopped too, nothing written next to config.json' $apps '{' -envs @{ KIUTD_UPGRADES = 'Git.Git' } -mode 'User' -show $key
SRun 'S1-11 -ListOnly with valid config.json: last good copy not written' $apps $good -extra @('-ListOnly') -show $key
SRun 'S1-12 valid config.json changed since the last good copy: last good copy replaced' $apps '{ "Version": "1.5.0-test", "ExcludeIds": ["Mobatek.MobaXterm", "Git.Git"] }' $good -show $key

''; '######## Part S2: exclusions (winget pins) for SYSTEM (F-03)'
SRun 'S2-1 a pin someone else set stays; only the listed exclusion is added' $apps $good -pins @('Contoso.ByHand') -envs @{ KIUTD_UPGRADES = 'Git.Git' } -show $key
SRun 'S2-2 an exclusion this tool set earlier and no longer listed is lifted; the other pin stays' $apps $good -pins @('Contoso.ByHand', 'Oracle.VirtualBox') -owned @('Oracle.VirtualBox') -envs @{ KIUTD_UPGRADES = 'Git.Git' } -show $key
SRun 'S2-3 the exclusion cannot be set for an installed app: run stopped, nothing updated' $apps $good -envs @{ KIUTD_UPGRADES = 'Git.Git,Mobatek.MobaXterm'; KIUTD_PINADDFAIL = 'Mobatek.MobaXterm' } -show $key
SRun 'S2-4 the exclusion cannot be set for an app that is not installed: run goes on' @('Git.Git|2.40.0') $good -envs @{ KIUTD_UPGRADES = 'Git.Git'; KIUTD_PINADDFAIL = 'Mobatek.MobaXterm' } -show $key
SRun 'S2-5 an old exclusion cannot be lifted: kept in system.pins, run goes on with a warning in the log' $apps $good -pins @('Oracle.VirtualBox') -owned @('Oracle.VirtualBox') -envs @{ KIUTD_UPGRADES = 'Git.Git'; KIUTD_PINFAIL = 'Oracle.VirtualBox' } -show $key
SRun 'S2-6 User task: same rules' $apps $good -pins @('Contoso.UserOwn') -envs @{ KIUTD_UPGRADES = 'Git.Git' } -mode 'User' -show $key

''; '######## Part S3: task result and retry after failed updates (F-08)'
SRun 'S3-1 all updated: exit 0, no retry file' $apps $good -envs @{ KIUTD_UPGRADES = 'Git.Git' } -show 'EVENT|Finished|tried again'
SRun 'S3-2 one update failed: exit 2, retry file 0' $apps $good -envs @{ KIUTD_UPGRADES = 'Git.Git'; KIUTD_FAIL = 'Git.Git' } -show 'EVENT|Finished|tried again'
SRun 'S3-3 same day, weekly run done: start skipped (no retry the same day)' $apps $good 'keep' -envs @{ KIUTD_UPGRADES = 'Git.Git'; KIUTD_FAIL = 'Git.Git' } -extra @() -KeepData -show 'skipped|trying again|EVENT|Finished'
$y = (Get-Date).AddDays(-1).ToString('o')
Set-Content "$data\system.retry" "0|$y" -Encoding ascii
SRun 'S3-4 next day: retry 1 of 2 runs although the weekly run is done; fails again' $apps $good 'keep' -envs @{ KIUTD_UPGRADES = 'Git.Git'; KIUTD_FAIL = 'Git.Git' } -extra @() -KeepData -show 'skipped|trying again|EVENT|Finished'
Set-Content "$data\system.retry" "1|$y" -Encoding ascii
SRun 'S3-5 retry 2 of 2, fails again: no more retries this week' $apps $good 'keep' -envs @{ KIUTD_UPGRADES = 'Git.Git'; KIUTD_FAIL = 'Git.Git' } -extra @() -KeepData -show 'skipped|trying again|EVENT|Finished|tried again'
Set-Content "$data\system.retry" "2|$y" -Encoding ascii
SRun 'S3-6 after two retries: start skipped until the next weekly run' $apps $good 'keep' -envs @{ KIUTD_UPGRADES = 'Git.Git' } -extra @() -KeepData -show 'skipped|trying again|EVENT|Finished'
Set-Content "$data\system.retry" "0|$y" -Encoding ascii
SRun 'S3-7 retry that works: exit 0, retry file removed' $apps $good 'keep' -envs @{ KIUTD_UPGRADES = 'Git.Git' } -extra @() -KeepData -show 'skipped|trying again|EVENT|Finished'
SRun 'S3-8 unexpected winget result: exit 1, no run stamp, nothing removed' @('SmartBear.SoapUI|5.9.1', 'SmartBear.SoapUI|5.10.0') '{ "Version": "1.5.0-test", "ExcludeIds": [], "RemoveOlder": { "SmartBear.SoapUI": "-q" } }' -envs @{ KIUTD_UPGRADES = 'SmartBear.SoapUI'; KIUTD_OLDER = 'SmartBear.SoapUI=5.10.0'; KIUTD_UPG_KEEPSTATE = '1'; KIUTD_UPG_EXIT = '-1978335231' } -arp @(@{ Line = 'SmartBear.SoapUI|5.9.1'; Name = 'SoapUI 5.9.1'; Version = '5.9.1' }, @{ Line = 'SmartBear.SoapUI|5.10.0'; Name = 'SoapUI 5.10.0'; Version = '5.10.0' }) -show 'EVENT|Finished|older|Older|exit code'
"   run stamp written: $(Test-Path "$data\system.lastrun")"

''; '######## Part S4: -ListOnly changes nothing (F-09)'
SRun 'S4-1 Visual C++ runtime missing, -ListOnly: not installed, only reported' $apps $good -envs @{ KIUTD_NOVC = '1' } -extra @('-ListOnly') -show 'Visual C|runtime|List'
SRun 'S4-2 catalogue damaged, -ListOnly: no repair (no source reset or update)' $apps $good -envs @{ KIUTD_EXPORT_FAIL = '1'; KIUTD_REPLAY = "$d\replay-1102.txt" } -extra @('-ListOnly') -show 'catalogue|Repair|List|source'

''; '######## Part S5: older copies only after a successful update (F-07, D35)'
$npNames = 'Notepad++.Notepad++|7.8.1=Notepad++ (64-bit x64);Notepad++.Notepad++|8.9.9=Notepad++ (x64);Unity.Unity.2020|2018.3.7f1=Unity 2018.3.7f1;Unity.Unity.2020|2020.3.48f1=Unity 2020.3.48f1;Ghisler.TotalCommander|9.51=Total Commander (Remove or Repair);Ghisler.TotalCommander|11.58.1=Total Commander 64-bit (Remove or Repair)'
$np = @('Notepad++.Notepad++|7.8.1', 'Notepad++.Notepad++|8.9.9', 'Ghisler.TotalCommander|9.51', 'Ghisler.TotalCommander|11.58.1')
$npArp = @(
    @{ Line = 'Notepad++.Notepad++|7.8.1'; Name = 'Notepad++ (64-bit x64)'; Version = '7.8.1'; Location = 'C:\Program Files\Notepad++' },
    @{ Line = 'Notepad++.Notepad++|8.9.9'; Name = 'Notepad++ (x64)'; Version = '8.9.9'; Location = 'C:\Program Files\Notepad++\' },
    @{ Line = 'Ghisler.TotalCommander|9.51'; Name = 'Total Commander (Remove or Repair)'; Version = '9.51'; Location = 'C:\totalcmd' },
    @{ Line = 'Ghisler.TotalCommander|11.58.1'; Name = 'Total Commander 64-bit (Remove or Repair)'; Version = '11.58.1'; Location = 'C:\totalcmd' })
$star = '{ "Version": "1.5.0-test", "ExcludeIds": [], "RemoveOlder": { "*": "" } }'
$ro = 'older|Older|Remove|remove|Running:|installed \d|installed more|EVENT|Finished'
SRun 'S5-1 "*", nothing updated in this run: duplicates left alone' $np $star -arp $npArp -envs @{ KIUTD_NAMES = $npNames } -show $ro
SRun 'S5-2 "*", Notepad++ updated in this run: only its old uninstall entry goes; Total Commander left alone' $np $star -arp $npArp -envs @{ KIUTD_NAMES = $npNames; KIUTD_UPGRADES = 'Notepad++.Notepad++'; KIUTD_OLDER = 'Notepad++.Notepad++=8.9.9'; KIUTD_UPG_KEEPSTATE = '1' } -show $ro
$un = @('Unity.Unity.2020|2018.3.7f1', 'Unity.Unity.2020|2020.3.48f1')
$unArp = @(@{ Line = 'Unity.Unity.2020|2018.3.7f1'; Name = 'Unity 2018.3.7f1'; Version = '2018.3.7f1'; Location = 'C:\Program Files\Unity\Editor'; Quiet = $true },
           @{ Line = 'Unity.Unity.2020|2020.3.48f1'; Name = 'Unity 2020.3.48f1'; Version = '2020.3.48f1'; Location = 'C:\Program Files\Unity 2020.3.48f1\Editor' })
SRun 'S5-3 PC396: Unity 2020 installed next to Unity 2018: 2018 is kept and reported, not uninstalled' $un $star -arp $unArp -envs @{ KIUTD_NAMES = $npNames; KIUTD_UPGRADES = 'Unity.Unity.2020'; KIUTD_OLDER = 'Unity.Unity.2020=2020.3.48f1'; KIUTD_UPG_KEEPSTATE = '1' } -show $ro
SRun 'S5-4 same with a rule for Unity.Unity.2020: then it is uninstalled (explicit)' $un '{ "Version": "1.5.0-test", "ExcludeIds": [], "RemoveOlder": { "*": "", "Unity.Unity.2020": "" } }' -arp $unArp -envs @{ KIUTD_NAMES = $npNames; KIUTD_UPGRADES = 'Unity.Unity.2020'; KIUTD_OLDER = 'Unity.Unity.2020=2020.3.48f1'; KIUTD_UPG_KEEPSTATE = '1' } -show $ro
$soap2 = @('SmartBear.SoapUI|5.9.1', 'SmartBear.SoapUI|5.10.0')
SRun 'S5-5 SoapUI rule, newest copy (5.10.0) has no uninstall entry: nothing removed, reported' $soap2 '{ "Version": "1.5.0-test", "ExcludeIds": [], "RemoveOlder": { "SmartBear.SoapUI": "-q" } }' -arp @(@{ Line = 'SmartBear.SoapUI|5.9.1'; Name = 'SoapUI 5.9.1'; Version = '5.9.1' }) -show $ro
SRun 'S5-6 SoapUI rule, update of SoapUI failed in this run: nothing removed' $soap2 '{ "Version": "1.5.0-test", "ExcludeIds": [], "RemoveOlder": { "SmartBear.SoapUI": "-q" } }' -arp @(@{ Line = 'SmartBear.SoapUI|5.9.1'; Name = 'SoapUI 5.9.1'; Version = '5.9.1' }, @{ Line = 'SmartBear.SoapUI|5.10.0'; Name = 'SoapUI 5.10.0'; Version = '5.10.0' }) -envs @{ KIUTD_UPGRADES = 'SmartBear.SoapUI'; KIUTD_FAIL = 'SmartBear.SoapUI' } -show $ro
SRun 'S5-7 -ListOnly with "*": shows what it would do for every package installed twice' $np $star -arp $npArp -envs @{ KIUTD_NAMES = $npNames } -extra @('-ListOnly') -show $ro

''; '######## Part S6: proxy settings (F-06), simulated computer settings'
$pxf = Join-Path $data 'px.json'
$pxOn = '{ "Version": "1.5.0-test", "ExcludeIds": [], "Proxy": "http://proxy.contoso.local:8080", "ProxyBypass": "<local>;*.contoso.local", "UseProxy": true }'
$pxOff = '{ "Version": "1.5.0-test", "ExcludeIds": [], "Proxy": "http://proxy.contoso.local:8080", "UseProxy": false }'
function PX([string]$title, [string]$cfg, [string]$now, [string]$state, [hashtable]$envs = @{}) {
    Remove-Item "$data\*" -Recurse -Force -ErrorAction SilentlyContinue
    Set-Content $pxf $now
    if ($state) { Set-Content "$data\proxy.json" $state }
    $e = @{ KIUTD_PX = $pxf }; foreach ($k in $envs.Keys) { $e[$k] = $envs[$k] }
    SRun $title @('Git.Git|2.40.0') $cfg -envs $e -KeepData -show 'Proxy|PROXYCALL'
    '   settings now: ' + ((Get-Content $pxf -Raw) -replace '\s+', ' ')
    '   proxy.json: ' + $(if (Test-Path "$data\proxy.json") { (Get-Content "$data\proxy.json" -Raw) -replace '\s+', ' ' } else { 'none' })
}
PX 'S6-1 all direct, proxy on: all three set, bypass list kept in proxy.json' $pxOn '{ "Winget": "", "WinHttp": "", "SystemIe": "" }' ''
PX 'S6-2 SYSTEM uses a PAC script: its internet settings left as they are' $pxOn '{ "Winget": "", "WinHttp": "", "SystemIe": { "Auto": true } }' ''
PX 'S6-3 WinHTTP cannot be read: left as it is' $pxOn '{ "Winget": "", "WinHttp": { "Known": false }, "SystemIe": "" }' ''
PX 'S6-4 proxy settings from Group Policy: only winget''s own setting' $pxOn '{ "Winget": "", "WinHttp": "", "SystemIe": "" }' '' @{ KIUTD_PXPOLICY = '1' }
PX 'S6-5 proxy off, settings as this tool set them: removed' $pxOff '{ "Winget": "http://proxy.contoso.local:8080", "WinHttp": { "Address": "proxy.contoso.local:8080", "Bypass": "<local>;*.contoso.local" }, "SystemIe": { "Address": "proxy.contoso.local:8080", "Bypass": "<local>;*.contoso.local" } }' '{ "Winget": { "Address": "http://proxy.contoso.local:8080", "Bypass": "" }, "WinHttp": { "Address": "http://proxy.contoso.local:8080", "Bypass": "<local>;*.contoso.local" }, "SystemIe": { "Address": "http://proxy.contoso.local:8080", "Bypass": "<local>;*.contoso.local" } }'
PX 'S6-6 proxy off, someone changed the WinHTTP bypass list since: WinHTTP left as it is' $pxOff '{ "Winget": "", "WinHttp": { "Address": "proxy.contoso.local:8080", "Bypass": "<local>;*.other.nl" }, "SystemIe": "" }' '{ "WinHttp": { "Address": "http://proxy.contoso.local:8080", "Bypass": "<local>;*.contoso.local" } }'
PX 'S6-7 proxy off, WinHTTP already empty: nothing reset, only forgotten' $pxOff '{ "Winget": "", "WinHttp": "", "SystemIe": "" }' '{ "WinHttp": { "Address": "http://proxy.contoso.local:8080", "Bypass": "<local>" } }'
PX 'S6-8 proxy off, proxy.json from 1.4.x (address only): removed when the address matches' $pxOff '{ "Winget": "", "WinHttp": "proxy.contoso.local:8080", "SystemIe": "" }' '{ "WinHttp": "http://proxy.contoso.local:8080" }'
$env:KIUTD_PX = ''

''; '######## Part S7: reading the connection settings value (F-06), test values under HKCU'
. ([scriptblock]::Create((RFn 'Get-ConnectionProxy')))
$ck = 'HKCU:\Software\KIUTD-Test150\Conn'
if (Test-Path $ck) { Remove-Item $ck -Recurse -Force }; New-Item -Path $ck -Force | Out-Null
function ConnBytes([int]$flags, [string]$px, [string]$bp) {
    $b = New-Object System.Collections.Generic.List[byte]
    $b.AddRange([BitConverter]::GetBytes([int]70)); $b.AddRange([BitConverter]::GetBytes([int]1)); $b.AddRange([BitConverter]::GetBytes($flags))
    $b.AddRange([BitConverter]::GetBytes($px.Length)); $b.AddRange([Text.Encoding]::ASCII.GetBytes($px))
    $b.AddRange([BitConverter]::GetBytes($bp.Length)); $b.AddRange([Text.Encoding]::ASCII.GetBytes($bp))
    $b.AddRange([BitConverter]::GetBytes([int]0)); return ,$b.ToArray()
}
New-ItemProperty -Path $ck -Name Manual -PropertyType Binary -Value (ConnBytes 3 'proxy:8080' '<local>') | Out-Null
New-ItemProperty -Path $ck -Name Direct -PropertyType Binary -Value (ConnBytes 1 '' '') | Out-Null
New-ItemProperty -Path $ck -Name Pac -PropertyType Binary -Value (ConnBytes 5 '' '') | Out-Null
New-ItemProperty -Path $ck -Name Short -PropertyType Binary -Value ([byte[]](1, 2, 3)) | Out-Null
New-ItemProperty -Path $ck -Name Text -PropertyType String -Value 'proxy:8080' | Out-Null
New-ItemProperty -Path $ck -Name BadLen -PropertyType Binary -Value ([byte[]]((ConnBytes 3 'p:1' '')[0..11] + [BitConverter]::GetBytes([int]5000))) | Out-Null
foreach ($n in 'Manual', 'Direct', 'Pac', 'Short', 'Text', 'BadLen', 'Missing') { $r = Get-ConnectionProxy $ck $n; "   ${n}: known $($r.Known), auto $($r.Auto), address '$($r.Address)', bypass '$($r.Bypass)'" }
$r = Get-ConnectionProxy 'HKCU:\Software\KIUTD-Test150\NoSuchKey' 'X'; "   key missing: known $($r.Known), address '$($r.Address)'"
Remove-Item 'HKCU:\Software\KIUTD-Test150\Conn' -Recurse -Force

''; '######## Part S8: folder permissions check (F-01), test folders of this account'
$iast = $ast
foreach ($fn in 'Test-LockedAcl') { . ([scriptblock]::Create((Fn $fn))) }
$af = Join-Path $d 'acl150'; if (Test-Path $af) { cmd /c rmdir /s /q $af }; New-Item -ItemType Directory $af -Force | Out-Null
"   folder made by this (standard) account: $(Test-LockedAcl $af)"
New-Item -ItemType Junction -Path "$af\link" -Target $env:TEMP -ErrorAction SilentlyContinue | Out-Null
"   with a junction inside: $(Test-LockedAcl $af)"
cmd /c rmdir "$af\link"

''; '######## Part S9: signed updater next to the installer (F-04)'
$TrustedSigners = @()
foreach ($fn in 'Test-ApprovedSignature', 'Save-Runner') { . ([scriptblock]::Create((Fn $fn))) }
$sf = Join-Path $d 'sig150'; if (Test-Path $sf) { Remove-Item $sf -Recurse -Force }; New-Item -ItemType Directory "$sf\src", "$sf\dst" -Force | Out-Null
Set-Content "$sf\src\Invoke-KeepItUpToDater.ps1" "'not signed'" -Encoding UTF8
"   unsigned file: $(Test-ApprovedSignature "$sf\src\Invoke-KeepItUpToDater.ps1")"
$RunnerName = 'Invoke-KeepItUpToDater.ps1'; $RunnerCode = "'built in'"
$PSScriptRoot2 = "$sf\src"
$sr = (Fn 'Save-Runner').Replace('$PSScriptRoot', '$PSScriptRoot2'); . ([scriptblock]::Create($sr))
try { $x = Save-Runner "$sf\dst"; "   Save-Runner with an unsigned file next to the installer: used ($x)" } catch { "   Save-Runner with an unsigned file next to the installer: REFUSED: $($_.Exception.Message -replace [regex]::Escape($sf), '<sig>')" }
Remove-Item "$sf\src\Invoke-KeepItUpToDater.ps1"
$x = Save-Runner "$sf\dst"; "   Save-Runner with nothing next to the installer: built-in updater written (signed: $x), content: $(Get-Content "$sf\dst\Invoke-KeepItUpToDater.ps1" -Raw)".Trim()

''; '######## Part S10: Windows tools by full path in the .cmd files (F-05)'
foreach ($f in Get-ChildItem "$d\*.cmd") {
    # a command line (not rem or echo text) that starts a Windows tool by its bare name
    $bare = @(Get-Content $f.FullName | Where-Object { $_ -notmatch '^\s*(rem|echo)\b' } | ForEach-Object { $_ -replace '"[^"]*"', '""' } | Select-String -Pattern '(^|\(|&|\||\bnot errorlevel 1 |\bdo )\s*(start "" )?(net|winget|powershell|notepad|icacls|reg|netsh|bitsadmin)(\.exe)?\s' | ForEach-Object { $_.Line.Trim() })
    "   $($f.Name): " + $(if ($bare.Count) { 'BARE: ' + ($bare -join ' | ') } else { 'no tool called by bare name' })
}
'   (the same check on the 1.4.8 Install.cmd, for comparison:)'
$old = @('net session >nul 2>&1') | ForEach-Object { $_ -replace '"[^"]*"', '""' } | Select-String -Pattern '(^|\(|&|\||\bnot errorlevel 1 |\bdo )\s*(start "" )?(net|winget|powershell|notepad|icacls|reg|netsh|bitsadmin)(\.exe)?\s'
"   1.4.8 Install.cmd: BARE: $($old.Line)"
''; '######## done'
