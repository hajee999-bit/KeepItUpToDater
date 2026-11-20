# Keep It Up To Dater 1.5.0, security review F-01: folder hardening, run ELEVATED on a test PC.
# Works only in test folders under C:\ProgramData\KIUTD-F01Test (removed at the end); the tool's own
# folders are not touched. Uses Set-LockedAcl and Test-LockedAcl from the installer next to this script.
$ErrorActionPreference = 'Continue'
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { 'Run this as administrator.'; exit 1 }
$tok = $null; $err = $null
$ast = [Management.Automation.Language.Parser]::ParseFile((Join-Path $PSScriptRoot 'Install-KeepItUpToDater.ps1'), [ref]$tok, [ref]$err)
foreach ($fn in 'Set-LockedAcl', 'Test-LockedAcl') { . ([scriptblock]::Create(($ast.FindAll({ param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq $fn }, $true) | Select-Object -First 1).Extent.Text)) }
$IcaclsExe = Join-Path $env:SystemRoot 'System32\icacls.exe'
$root = 'C:\ProgramData\KIUTD-F01Test'
if (Test-Path $root) { cmd /c rmdir /s /q $root }
New-Item -ItemType Directory $root -Force | Out-Null
function Show([string]$p) { & $IcaclsExe $p | Where-Object { $_ -match '\S' -and $_ -notmatch '^Successfully' } | ForEach-Object { "      $_" } }

'--- A1 folder as a standard user could leave it: Users may change it, a file with Everyone full control, a file owned by Users'
$a = Join-Path $root 'A'; New-Item -ItemType Directory "$a\sub" -Force | Out-Null
Set-Content "$a\runner.ps1" 'x'; Set-Content "$a\sub\config.json" '{}'
& $IcaclsExe $a /grant '*S-1-5-32-545:(OI)(CI)M' | Out-Null
& $IcaclsExe "$a\runner.ps1" /grant '*S-1-1-0:F' | Out-Null
& $IcaclsExe "$a\sub\config.json" /setowner '*S-1-5-32-545' | Out-Null
"   before: $(Test-LockedAcl $a)"
try { Set-LockedAcl $a; '   Set-LockedAcl: done' } catch { "   Set-LockedAcl: REFUSED: $($_.Exception.Message)" }
"   after: $(if (Test-LockedAcl $a) { Test-LockedAcl $a } else { 'only SYSTEM and Administrators can change it, owner Administrators' })"
'   folder:'; Show $a
'   runner.ps1:'; Show "$a\runner.ps1"
'   sub\config.json:'; Show "$a\sub\config.json"

'--- A2 the folder itself is a junction to another folder: refused, nothing changed there'
$t = Join-Path $root 'Target'; New-Item -ItemType Directory $t -Force | Out-Null
cmd /c mklink /J "$root\B" "$t" | Out-Null
try { Set-LockedAcl "$root\B"; '   Set-LockedAcl: done (WRONG)' } catch { "   Set-LockedAcl: REFUSED: $($_.Exception.Message)" }

'--- A3 a junction inside the folder: refused'
$c = Join-Path $root 'C'; New-Item -ItemType Directory $c -Force | Out-Null
cmd /c mklink /J "$c\link" "$t" | Out-Null
try { Set-LockedAcl $c; '   Set-LockedAcl: done (WRONG)' } catch { "   Set-LockedAcl: REFUSED: $($_.Exception.Message)" }

cmd /c rmdir "$root\B"; cmd /c rmdir "$c\link"; cmd /c rmdir /s /q $root
'--- test folders removed'
