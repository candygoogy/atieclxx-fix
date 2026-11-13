# Tests the decision logic of atieclxx-fix.ps1 without admin rights and without touching
# the real file: the parts that read the system or change permissions are replaced with fakes.
# Also runs the launcher's "zip not extracted" branch, which stops before asking for admin.
# Run: powershell -NoProfile -ExecutionPolicy Bypass -File tests\Test-Logic.ps1

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '..\atieclxx-fix.ps1')

# A stand-in for the copy, so Test-Path finds a file.
$Copy = Join-Path ([IO.Path]::GetTempPath()) 'atieclxx-fix-test-copy.exe'
Set-Content -LiteralPath $Copy -Value 'test'

$script:failures = 0
function New-State($gpu, $rates, [bool]$applied, [bool]$stale, [bool]$admin = $true) {
    $script:S = @{ Gpu = $gpu; Rates = [Collections.Queue]::new([double[]]$rates); Applied = $applied
                  Stale = $stale; Admin = $admin; Added = 0; Removed = 0 }
    $script:StatusShown = $false
}

# Fakes for everything that reads the system or changes permissions.
function Get-AmdGpus     { @($script:S.Gpu | ForEach-Object { [pscustomobject]@{ Name = $_; DriverVersion = 'test' } }) }
function Get-Utility     { [pscustomobject]@{ ProcessId = 1; CreationDate = (Get-Date).AddHours(-1); WriteTransferCount = 1MB; ExecutablePath = 'x' } }
function Test-Admin      { $script:S.Admin }
function Get-FilterState { 'test' }
function Test-FixApplied { $script:S.Applied }
function Test-CopyStale  { $script:S.Stale }
function Measure-Writes([int]$sec) { $script:S.Rates.Dequeue() }
function Add-Block       { $script:S.Added++;   $script:S.Applied = $true }
function Remove-Block    { $script:S.Removed++; $script:S.Applied = $false; $script:S.Stale = $false }

function Run([scriptblock]$action) { (& $action 6>&1 | Out-String) }

function Expect([string]$name, [string]$out, [string[]]$has, [string[]]$hasNot = @(), [hashtable]$counts = @{}) {
    $ok = $true
    foreach ($h in $has)    { if ($out -notlike "*$h*") { $ok = $false; Write-Host "    missing: $h" } }
    foreach ($h in $hasNot) { if ($out -like "*$h*")    { $ok = $false; Write-Host "    unexpected: $h" } }
    foreach ($k in $counts.Keys) { if ($script:S[$k] -ne $counts[$k]) { $ok = $false; Write-Host "    $k = $($script:S[$k]), expected $($counts[$k])" } }
    if ($ok) { Write-Host "PASS  $name" -ForegroundColor Green } else { Write-Host "FAIL  $name" -ForegroundColor Red; $script:failures++ }
}

$Polaris = 'Radeon RX 580 Series'
$Rdna4   = 'AMD Radeon RX 9070 XT'
$Bug     = 677KB

# GPU detection
foreach ($n in 'Radeon RX 580 Series','AMD Radeon RX 560','Radeon RX 570X','AMD Radeon RX 480','Radeon RX 640','Radeon RX Vega 64','AMD Radeon VII') {
    New-State $n @() $false $false; Expect "Polaris/Vega card: $n" (Get-GcnState) @('all')
}
foreach ($n in 'AMD Radeon RX 5700 XT','AMD Radeon RX 5500 XT','AMD Radeon RX 6600','AMD Radeon RX 7800 XT','AMD Radeon RX 9070 XT','AMD Radeon(TM) Graphics','AMD Radeon(TM) Vega 11 Graphics') {
    New-State $n @() $false $false; Expect "not a Polaris/Vega card: $n" (Get-GcnState) @('none')
}
New-State @('AMD Radeon(TM) Vega 11 Graphics', 'AMD Radeon RX 7800 XT') @() $false $false
Expect 'Vega iGPU + RX 7800 XT' (Get-GcnState) @('none')
New-State @('AMD Radeon(TM) Graphics', 'Radeon RX 580 Series') @() $false $false
Expect 'Ryzen iGPU + RX 580' (Get-GcnState) @('some')
New-State @() @() $false $false
Expect 'no AMD GPU found' (Get-GcnState) @('none')

# Check
New-State $Polaris @($Bug) $false $false
Expect 'Check, Polaris, affected' (Run { Invoke-Check }) @('AFFECTED', 'not fixed this for Polaris and Vega') @('26.11.1')

New-State $Rdna4 @($Bug) $false $false
Expect 'Check, RX 9070 XT, affected' (Run { Invoke-Check }) @('AFFECTED', 'fixed this in Adrenalin 26.11.1') @('Polaris')

New-State @('AMD Radeon(TM) Vega 11 Graphics', $Rdna4) @($Bug) $false $false
Expect 'Check, Vega iGPU + RX 9070 XT, affected' (Run { Invoke-Check }) @('AFFECTED', 'fixed this in Adrenalin 26.11.1') @('Polaris')

New-State @('AMD Radeon(TM) Graphics', $Polaris) @($Bug) $false $false
Expect 'Check, Ryzen iGPU + RX 580, affected' (Run { Invoke-Check }) @('AFFECTED', 'Polaris or Vega card', 'may not be enough') @('26.11.1')

New-State $Rdna4 @(0) $true $true
Expect 'Check, block on, driver changed' (Run { Invoke-Check }) @('OK:', 'Run Fix once')

New-State $Rdna4 @(0) $true $false
Expect 'Check, block on, same driver' (Run { Invoke-Check }) @('OK:', 'run Undo, then Check')

New-State $Rdna4 @(0) $false $false
Expect 'Check, not affected, no block' (Run { Invoke-Check }) @('OK:') @('Run Fix once', 'Undo')

New-State $Rdna4 @(0) $true $true $false
Expect 'Check, not admin, no fix hints' (Run { Invoke-Check }) @('OK:') @('Run Fix once', 'Undo')

# Fix
New-State $Rdna4 @(0) $true $true
Expect 'Fix after a driver update that fixed the bug' (Run { Invoke-Fix }) @('no longer has the bug', 'block was removed') @('Applied:', 'nothing was changed') @{ Removed = 1; Added = 0 }

New-State $Polaris @($Bug, 0) $true $true
Expect 'Fix after a driver update that still has the bug' (Run { Invoke-Fix }) @('Applied:', 'FIXED') @('no longer has the bug') @{ Removed = 1; Added = 1 }

New-State $Rdna4 @(0) $false $false
Expect 'Fix, not affected' (Run { Invoke-Fix }) @('nothing was changed') @('block was removed') @{ Removed = 0; Added = 0 }

New-State $Polaris @($Bug, 0) $false $false
Expect 'Fix, fresh apply' (Run { Invoke-Fix }) @('Applied:', 'FIXED') @() @{ Removed = 0; Added = 1 }

New-State $Rdna4 @($Bug, $Bug) $false $false
Expect 'Fix, other variant rolls back' (Run { Invoke-Fix }) @('Rolling back', 'Rolled back') @() @{ Removed = 1; Added = 1 }

Remove-Item -LiteralPath $Copy -ErrorAction SilentlyContinue

# Launcher: run from inside the zip, only the .cmd exists. It must say so, before asking for admin.
$lone = Join-Path ([IO.Path]::GetTempPath()) "atieclxx-fix-test-it's here"
New-Item -ItemType Directory -Path $lone -Force | Out-Null
Copy-Item -LiteralPath (Join-Path $PSScriptRoot '..\Fix-SSD-Writes.cmd') -Destination $lone
$launcherOut = ('' | & cmd.exe /d /c "`"$lone\Fix-SSD-Writes.cmd`"" 2>&1 | Out-String)
$launcherExit = $LASTEXITCODE
New-State $Rdna4 @() $false $false
Expect 'Launcher without the script next to it' $launcherOut @('Extract the whole zip first') @('administrator')
Expect 'Launcher exit code' ([string]$launcherExit) @('1')
Remove-Item -LiteralPath $lone -Recurse -Force -ErrorAction SilentlyContinue
Write-Host ''
if ($script:failures) { Write-Host "$($script:failures) test(s) failed" -ForegroundColor Red; exit 1 }
Write-Host 'All tests passed' -ForegroundColor Green
# The launcher test above leaves exit code 1 behind on purpose; report success explicitly.
exit 0
