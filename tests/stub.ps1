# Test stand-in for winget with a list of installed packages in $env:KIUTD_STATE (lines "Id|Version")
# KIUTD_ALIAS=1 copies real winget on 4 Nov 2026: all Node.js MSIs share one upgrade code, so "list" and
# "uninstall" for any OpenJS.NodeJS* ID find any installed Node.js, and an in-place upgrade stays
# listed under the old ID with the new version.
[Console]::OutputEncoding = [Text.Encoding]::UTF8
function Say([string]$t) { [Console]::Out.WriteLine($t); [Console]::Out.Flush() }
$state = $env:KIUTD_STATE
$a = @($args)
Add-Content -Path (Join-Path (Split-Path $state) 'calls.log') -Value ($a -join ' ')
function Get-State { if (Test-Path $state) { @(Get-Content $state | Where-Object { $_ }) } else { @() } }
function IdOf([string]$line) { ($line -split '\|')[0] }
function VerOf([string]$line) { ($line -split '\|')[1] }
function IsNode([string]$id) { $id -like 'OpenJS.NodeJS*' }
function Match([string]$line, [string]$id) {
    if ($env:KIUTD_ALIAS -eq '1' -and (IsNode $id) -and (IsNode (IdOf $line))) { return $true }
    return ((IdOf $line) -eq $id)
}
function Has([string]$id) { @(Get-State | Where-Object { Match $_ $id }).Count -gt 0 }
function Arg([string]$name) { $i = [array]::IndexOf($a, $name); if ($i -ge 0 -and $i + 1 -lt $a.Count) { $a[$i + 1] } }
switch ($a[0]) {
    '--version' { 'v1.29.380'; exit 0 }
    'export' {
        if ($env:KIUTD_EXPORT_FAIL -eq '1' -and -not (Test-Path "$state.exported")) { Set-Content "$state.exported" 'x'; exit -1978335217 }
        $pk = @(Get-State | ForEach-Object { [ordered]@{ PackageIdentifier = (IdOf $_); Version = (VerOf $_) } })
        ConvertTo-Json -Depth 5 -InputObject ([ordered]@{ Sources = @([ordered]@{ Packages = $pk; SourceDetails = @{ Name = 'winget' } }) }) | Set-Content -Path (Arg '--output') -Encoding UTF8
        exit 0
    }
    'list' {
        # 1.4.7 RemoveOlder lists every copy of one ID ("list --id X --exact ... --scope machine") as a table.
        # KIUTD_NAMES: "Id|Version=Name;..." names to show; KIUTD_LANG=nl: Dutch header. Spinner frames first, as winget does.
        if ($a -contains '--scope') {
            # 1.4.8: without --id, every machine-wide package (the "*" rule looks for IDs listed twice or more)
            $id = Arg '--id'
            $rows = @(Get-State | Where-Object { -not $id -or (IdOf $_) -eq $id })
            [Console]::Out.Write("   -`r   \`r"); [Console]::Out.Flush()
            if (-not $rows.Count) { Say 'No installed package found matching input criteria.'; exit -1978335212 }
            $names = @{}; foreach ($kv in @("$env:KIUTD_NAMES" -split ';' | Where-Object { $_ -match '=' })) { $k, $v = $kv -split '=', 2; $names[$k] = $v }
            $hdr = if ($env:KIUTD_LANG -eq 'nl') { @('Naam', 'Id', 'Versie', 'Bron') } else { @('Name', 'Id', 'Version', 'Source') }
            $cells = @(foreach ($r in $rows) { $n = $names[$r]; if (-not $n) { $n = ((IdOf $r) -split '\.')[-1] + ' ' + (VerOf $r) }; ,@($n, (IdOf $r), (VerOf $r), 'winget') })
            $w = @(for ($c = 0; $c -lt $hdr.Count; $c++) { [math]::Max($hdr[$c].Length, (@($cells | ForEach-Object { $_[$c].Length }) | Measure-Object -Maximum).Maximum) })
            $fmt = { param($x) (@(for ($c = 0; $c -lt $x.Count; $c++) { "$($x[$c])".PadRight($w[$c]) }) -join ' ').TrimEnd() }
            $h = & $fmt $hdr; Say $h; Say ('-' * ($h.Length + 2))
            foreach ($x in $cells) { Say (& $fmt $x) }
            exit 0
        }
        if (Has (Arg '--id')) { exit 0 } else { exit -1978335212 }
    }
    'install' {
        $id = Arg '--id'
        if ($env:KIUTD_INSTALL_FAIL -eq '1') { Say "Found $id [$id] Version 26.13.0"; Say 'Starting package install...'; Say 'Installer failed with exit code: 1603'; exit -1978335226 }
        if ($env:KIUTD_ALIAS -eq '1' -and (IsNode $id)) {
            $hit = @(Get-State | Where-Object { Match $_ $id })
            if ($hit.Count) {
                Say 'Found an existing package already installed. Trying to upgrade the installed package...'
                if ((VerOf $hit[0]) -eq '26.13.0') { Say 'No available upgrade found.'; exit -1978335189 }
                Say "Found $id [$id] Version 26.13.0"; Say 'Starting package install...'
                # in-place MSI upgrade: the entry keeps the old ID, with the new version
                Set-Content -Path $state -Value @(Get-State | ForEach-Object { if ($_ -eq $hit[0]) { "$(IdOf $_)|26.13.0" } else { $_ } })
                Say 'Successfully installed'; exit 0
            }
        }
        Say "Found $id [$id] Version 26.13.0"
        Say 'Starting package install...'
        if (@(Get-State | Where-Object { (IdOf $_) -eq $id }).Count) { Say 'A package version is already installed.'; exit -1978335135 }
        # Node.js MSI: a newer major removes the older one during its install (unless simulated side by side)
        if ($env:KIUTD_SIDE_BY_SIDE -ne '1') { Set-Content -Path $state -Value @(Get-State | Where-Object { -not ((IsNode (IdOf $_)) -and (IdOf $_) -ne $id) }) }
        Add-Content -Path $state -Value "$id|26.13.0"
        Say 'Successfully installed'; exit 0
    }
    'uninstall' {
        $id = Arg '--id'; $v = Arg '--version'
        $hit = @(Get-State | Where-Object { (Match $_ $id) -and (-not $v -or (VerOf $_) -eq $v) })
        if ($env:KIUTD_UNINSTALL_ALL -eq '1') { $hit = @(Get-State | Where-Object { IsNode (IdOf $_) }) }
        if (-not $hit.Count) { Say 'No installed package found matching input criteria.'; exit -1978335212 }
        Say "Found $id [$id]"
        Set-Content -Path $state -Value @(Get-State | Where-Object { $hit -notcontains $_ })
        Say 'Successfully uninstalled'; exit 0
    }
    'pin' {
        # pins kept in <state>.pins, one ID per line
        $pf = "$state.pins"
        $pins = if (Test-Path $pf) { @(Get-Content $pf | Where-Object { $_ }) } else { @() }
        switch ($a[1]) {
            'reset'  { Remove-Item $pf -ErrorAction SilentlyContinue }
            'add'    { if (("$env:KIUTD_PINADDFAIL" -split ',') -contains (Arg '--id')) { exit -1978335212 }; Set-Content $pf (@(@($pins) + (Arg '--id')) | Select-Object -Unique) }   # 1.5.0: KIUTD_PINADDFAIL
            'remove' { if (("$env:KIUTD_PINFAIL" -split ',') -contains (Arg '--id')) { exit -1978335212 }; Set-Content $pf @($pins | Where-Object { $_ -ne (Arg '--id') }) }
            'list'   { if ($pins.Count) { Say 'Name Id Version Source Pin type'; Say ('-' * 40); foreach ($x in $pins) { Say "App $x 1.0 winget Pinning" } } else { Say 'There are no pins configured.' } }
        }
        exit 0
    }
    'upgrade' {
        # KIUTD_UPGRADES: IDs with a newer version; KIUTD_RESTART: installer asks for a PC restart; KIUTD_REOPEN: app restart
        # KIUTD_NOTTRIED: listed but not installed; KIUTD_EXPLICIT: listed in the "explicit targeting" table
        # KIUTD_OLDER: Id=version installed instead of the listed 9.9.9; KIUTD_LANG=nl: Dutch output with a Source column
        # KIUTD_LT: IDs shown with "< version"; KIUTD_LONGNAME: ID whose name is shortened with an ellipsis
        # KIUTD_REPLAY: file with real winget output to print; a line <<HANG>> waits 10 minutes
        if ($a -contains '--id') { Say 'No available upgrade found.'; exit -1978335189 }
        $listMode = $a -notcontains '--all'
        if ($listMode -and $env:KIUTD_REPLAY_AFTER -and $env:KIUTD_REPLAY_AFTER -ne '0') {
            foreach ($l in (Get-Content $env:KIUTD_REPLAY_AFTER -Encoding UTF8)) { Say $l }
            exit 0
        }
        if ($listMode -and $env:KIUTD_LISTMODE -ne '1') { Say 'No available upgrade found.'; exit -1978335189 }
        if ($env:KIUTD_REPLAY -and $env:KIUTD_REPLAY -ne '0' -and -not $listMode) {
            foreach ($l in (Get-Content $env:KIUTD_REPLAY -Encoding UTF8)) { if ($l -eq '<<HANG>>') { Start-Sleep -Seconds 600 } else { Say $l } }
            exit 0
        }
        $pf = "$state.pins"
        $pins = if (Test-Path $pf) { @(Get-Content $pf | Where-Object { $_ }) } else { @() }
        function Pick([string]$list) { @("$list" -split ',' | Where-Object { $_ -and $_ -ne '0' -and (Has $_) -and ($pins -notcontains $_) }) }
        $todo = @(Pick $env:KIUTD_UPGRADES)
        $listed = @(@($todo) + @(Pick $env:KIUTD_NOTTRIED))
        $explicit = @(Pick $env:KIUTD_EXPLICIT)
        if ($listMode) {
            # KIUTD_LISTMODE=1: list what still has an update (not at 9.9.9 yet)
            $listed = @(foreach ($x in @(@(Pick $env:KIUTD_UPGRADES) + @(Pick $env:KIUTD_NOTTRIED) + @(Pick $env:KIUTD_EXPLICIT) | Select-Object -Unique)) { $cur = VerOf (@(Get-State | Where-Object { (IdOf $_) -eq $x })[0]); if ($cur -ne '9.9.9') { $x } })
            $todo = @(); $explicit = @()
        }
        if (-not $listed.Count -and -not $explicit.Count) { Say 'No available upgrade found.'; exit -1978335189 }
        $older = @{}
        foreach ($kv in @("$env:KIUTD_OLDER" -split ',' | Where-Object { $_ -match '=' })) { $k, $v = $kv -split '=', 2; $older[$k] = $v }
        $nl = $env:KIUTD_LANG -eq 'nl'
        function Show-Table([string[]]$ids) {
            $hdr = if ($nl) { @('Naam', 'Id', 'Versie', 'Beschikbaar', 'Bron') } else { @('Name', 'Id', 'Version', 'Available') }
            $rows = @(foreach ($id in $ids) {
                $cur = VerOf (@(Get-State | Where-Object { (IdOf $_) -eq $id })[0])
                if (("$env:KIUTD_LT" -split ',') -contains $id) { $cur = '< 9.9.9' }
                $name = if ($id -eq $env:KIUTD_LONGNAME) { 'A very long application name that winget shor' + [char]0x2026 } else { ($id -split '\.')[-1] + ' app' }
                $r = @($name, $id, $cur, '9.9.9'); if ($nl) { $r += 'winget' }
                ,$r
            })
            $w = @(for ($c = 0; $c -lt $hdr.Count; $c++) { [math]::Max($hdr[$c].Length, (@($rows | ForEach-Object { $_[$c].Length }) | Measure-Object -Maximum).Maximum) })
            $fmt = { param($cells) (@(for ($c = 0; $c -lt $cells.Count; $c++) { "$($cells[$c])".PadRight($w[$c]) }) -join ' ').TrimEnd() }
            $h = & $fmt $hdr
            Say $h; Say ('-' * ($h.Length + 4))
            foreach ($r in $rows) { Say (& $fmt $r) }
        }
        if ($listed.Count) { Show-Table $listed; Say ("$($listed.Count) upgrades " + $(if ($nl) { 'beschikbaar.' } else { 'available.' })) }
        if ($explicit.Count) { Say 'The following packages have an upgrade available, but require explicit targeting for upgrade:'; Show-Table $explicit }
        $i = 0
        $anyFail = $false
        foreach ($id in $todo) {
            $i++
            $v = if ($older.ContainsKey($id)) { $older[$id] } else { '9.9.9' }
            if ($nl) { Say "($i/$($todo.Count)) Gevonden $id [$id] Versie $v" } else { Say "($i/$($todo.Count)) Found $id [$id] Version $v" }
            Say 'Starting package install...'
            if (("$env:KIUTD_FAIL" -split ',') -contains $id) { Say 'Installer failed with exit code: 1603'; $anyFail = $true; continue }
            # 1.5.0: KIUTD_UPG_KEEPSTATE=1 leaves the installed list as it is (the newest copy was already updated in place)
            if ($env:KIUTD_UPG_KEEPSTATE -ne '1') { Set-Content -Path $state -Value @(Get-State | ForEach-Object { if ((IdOf $_) -eq $id) { "$id|$v" } else { $_ } }) }
            if (("$env:KIUTD_RESTART" -split ',') -contains $id) { Say 'Restart your PC to finish installation.' }
            elseif (("$env:KIUTD_REOPEN" -split ',') -contains $id) { Say 'Successfully installed. Restart the application to complete the upgrade.' }
            else { Say 'Successfully installed' }
        }
        if ($env:KIUTD_UPG_EXIT) { exit [int]$env:KIUTD_UPG_EXIT }   # 1.5.0: an unexpected winget result
        if ($anyFail) { exit -1978335188 }
        exit 0
    }
    default { exit 0 }
}
