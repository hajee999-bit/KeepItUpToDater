# Test stand-in for an uninstaller (1.4.7 RemoveOlder): removes its uninstall entry (a test key under HKCU)
# and its line from the winget stand-in's state file, and records how it was called.
param([string]$Key, [string]$State, [string]$Line, [int]$Delay = 0, [switch]$q, [switch]$KeepKey, [string]$Folder = '', [int]$FolderDelay = 0)
Add-Content -Path (Join-Path (Split-Path $State) 'uninstalls.log') -Value ("$Line" + $(if ($q) { ' -q' } else { ' (no -q)' }))
if ($Delay) { Start-Sleep -Seconds $Delay }
if (-not $KeepKey) {
    Remove-Item -LiteralPath $Key -Recurse -Force -ErrorAction SilentlyContinue
    $rest = @(Get-Content $State | Where-Object { $_ -and $_ -ne $Line })
    Set-Content -Path $State -Value $rest
}
# Like install4j: a copy of the uninstaller goes on deleting the folder after this process has ended
if ($Folder -and $FolderDelay -ge 0) {
    Start-Process powershell.exe -WindowStyle Hidden -ArgumentList '-NoProfile', '-Command', "Start-Sleep -Seconds $FolderDelay; Remove-Item -LiteralPath '$Folder' -Recurse -Force"
}
exit 0
