<#
.SYNOPSIS
    Stops the AMD External Events Utility (atieclxx.exe) from rewriting its own
    677 KB copy every second, which writes 40-55 GB a day to the system SSD.

.DESCRIPTION
    atieclxx.exe copies itself from the DriverStore to
    C:\Windows\System32\config\systemprofile\AppData\Local\AMD\atieclxx.exe
    about once a second, forever. The bytes are identical every time, but
    Windows still flushes them to disk.

    The fix denies the SYSTEM account write/delete access to that one copy.
    The copy fails before any data is written, the existing copy (identical to
    the original) stays in place, and the service keeps running.

    -Fix only blocks the copy when the writes are really happening, and after a
    driver update it lets the new driver refresh its copy before re-testing.

    Run with no switch for a menu. -Fix and -Undo need administrator rights.

.EXAMPLE
    .\atieclxx-fix.ps1 -Check
.EXAMPLE
    .\atieclxx-fix.ps1 -Fix
.EXAMPLE
    .\atieclxx-fix.ps1 -Undo
#>
[CmdletBinding()]
param(
    [switch]$Check,
    [switch]$Fix,
    [switch]$Undo,
    [ValidateRange(3, 600)][int]$Seconds = 15
)

$ErrorActionPreference = 'Stop'
$Version   = '1.0.2'
$Copy      = Join-Path $env:SystemRoot 'System32\config\systemprofile\AppData\Local\AMD\atieclxx.exe'
$SystemSid = 'S-1-5-18'
# Normal background writes from this utility are close to zero. The bug writes ~650 KB/s.
$AffectedBytesPerSec = 50KB

function Test-Admin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    (New-Object Security.Principal.WindowsPrincipal $id).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-Utility {
    Get-CimInstance Win32_Process -Filter "Name='atieclxx.exe'" -ErrorAction SilentlyContinue | Select-Object -First 1
}

function Format-Bytes([double]$b) {
    if ($b -ge 1GB) { return ('{0:N1} GB' -f ($b / 1GB)) }
    if ($b -ge 1MB) { return ('{0:N1} MB' -f ($b / 1MB)) }
    if ($b -ge 1KB) { return ('{0:N0} KB' -f ($b / 1KB)) }
    return ('{0:N0} B' -f $b)
}

# SHA-256 via .NET, so it works in every PowerShell without loading extra modules.
function Get-Sha256([string]$path) {
    $sha = [Security.Cryptography.SHA256]::Create()
    $fs = [IO.File]::Open($path, 'Open', 'Read', 'ReadWrite')
    try { return [BitConverter]::ToString($sha.ComputeHash($fs)) } finally { $fs.Dispose(); $sha.Dispose() }
}

# True when the copy no longer matches the running driver's atieclxx.exe (driver was updated).
# $null when it can't tell (not admin, or the utility isn't running).
function Test-CopyStale {
    $proc = Get-Utility
    if (-not $proc -or -not $proc.ExecutablePath -or -not (Test-Path -LiteralPath $Copy)) { return $null }
    return (Get-Sha256 $proc.ExecutablePath) -ne (Get-Sha256 $Copy)
}

# Bytes per second written by atieclxx.exe over $sec seconds, or $null if it isn't running.
function Measure-Writes([int]$sec) {
    $a = Get-Utility
    if (-not $a) { return $null }
    Write-Host ("  Measuring for {0} seconds..." -f $sec) -ForegroundColor DarkGray
    Start-Sleep -Seconds $sec
    $b = Get-Utility
    if (-not $b -or $b.ProcessId -ne $a.ProcessId) { return $null }
    return [double]($b.WriteTransferCount - $a.WriteTransferCount) / $sec
}

# The loop is the utility trying to install the amdkmpfd filter driver from three setup
# files. Read-only; printed so reports from different PCs can be compared.
function Get-FilterState {
    if (Test-Path -LiteralPath 'HKLM:\SYSTEM\CurrentControlSet\Services\amdkmpfd') { $driver = 'installed' } else { $driver = 'not installed' }
    $dir = Join-Path $env:SystemRoot 'System32\AMD\amdkmpfd'
    if (-not (Test-Path -LiteralPath $dir)) { return ('driver {0}, no setup folder' -f $driver) }
    $found = @(Get-ChildItem -LiteralPath $dir -ErrorAction SilentlyContinue | Where-Object { $_.Extension -match '^\.(itz|stz|ctz)$' }).Count
    return ('driver {0}, {1} of 3 setup files' -f $driver, $found)
}

function Test-FixApplied {
    if (-not (Test-Path -LiteralPath $Copy)) { return $false }
    # FileSecurity instead of Get-Acl: works in Windows PowerShell 5.1 and 7, even when
    # 5.1 is started from 7 with a PSModulePath it can't load the Security module from.
    $acl = New-Object System.Security.AccessControl.FileSecurity -ArgumentList $Copy, ([System.Security.AccessControl.AccessControlSections]::Access)
    $rules = $acl.GetAccessRules($true, $true, [System.Security.Principal.SecurityIdentifier])
    foreach ($rule in $rules) {
        if ($rule.AccessControlType -eq 'Deny' -and $rule.IdentityReference.Value -eq $SystemSid) { return $true }
    }
    return $false
}

function Invoke-Icacls([string[]]$icaclsArgs) {
    $out = & icacls.exe @icaclsArgs 2>&1
    if ($LASTEXITCODE -ne 0) { throw "icacls failed: $out" }
}

function Add-Block    { Invoke-Icacls @($Copy, '/deny', "*${SystemSid}:(W,D)") }
function Remove-Block { Invoke-Icacls @($Copy, '/remove:d', "*$SystemSid") }

function Show-Status {
    $proc = Get-Utility
    # The menu already printed the status; don't print it again for the chosen action.
    if ($script:StatusShown) { return $proc }
    $script:StatusShown = $true
    $admin = Test-Admin
    # List every AMD GPU: PCs with a Ryzen iGPU have two, and the first one isn't always the card.
    $gpus  = @(Get-CimInstance Win32_VideoController | Where-Object { $_.Name -match 'Radeon|AMD' })

    Write-Host ''
    Write-Host ("atieclxx-fix {0}" -f $Version) -ForegroundColor Cyan
    foreach ($g in $gpus) { Write-Host ("  GPU / driver:   {0} / {1}" -f $g.Name, $g.DriverVersion) }
    if ($proc) {
        $up = (Get-Date) - $proc.CreationDate
        Write-Host ("  atieclxx.exe:   running (PID {0}, up {1:N1} h)" -f $proc.ProcessId, $up.TotalHours)
        Write-Host ("  Written so far: {0} since it started" -f (Format-Bytes $proc.WriteTransferCount))
    } else {
        Write-Host '  atieclxx.exe:   not running (nothing to fix right now)'
    }
    Write-Host ("  amdkmpfd:       {0}" -f (Get-FilterState))
    if ($admin) {
        if (-not (Test-Path -LiteralPath $Copy)) { $state = 'not applied (the utility has made no copy on this PC)' }
        elseif (Test-FixApplied) {
            $state = 'APPLIED'
            if (Test-CopyStale) { $state = 'APPLIED, but the driver changed since (run Fix to refresh)' }
        } else { $state = 'not applied' }
        Write-Host ("  Fix:            {0}" -f $state)
    } else {
        Write-Host '  Fix:            unknown (run as administrator to see)'
    }
    return $proc
}

function Invoke-Check {
    $proc = Show-Status
    if (-not $proc) { return }
    $rate = Measure-Writes $Seconds
    if ($null -eq $rate) { Write-Host '  atieclxx.exe restarted during the measurement. Try again.' -ForegroundColor Yellow; return }
    Write-Host ("  Write rate now: {0}/s  (about {1} a day)" -f (Format-Bytes $rate), (Format-Bytes ($rate * 86400)))
    Write-Host ''
    if ($rate -ge $AffectedBytesPerSec) {
        Write-Host '  AFFECTED: the utility is constantly writing to your system drive.' -ForegroundColor Red
        Write-Host '  Run the fix (as administrator) to stop it.'
    } else {
        Write-Host '  OK: no constant writes from atieclxx.exe right now.' -ForegroundColor Green
    }
}

function Invoke-Fix {
    if (-not (Test-Admin)) { throw 'The fix needs administrator rights. Right-click and run as administrator.' }
    [void](Show-Status)
    if (-not (Get-Utility)) { Write-Host '  atieclxx.exe is not running. Nothing to fix.'; return }

    # After a driver update the blocked copy is the old version. Let the new driver
    # refresh it, then test the new driver from scratch.
    if ((Test-FixApplied) -and (Test-CopyStale)) {
        Write-Host ''
        Write-Host '  The AMD driver changed since the fix was applied. Letting it refresh its copy...'
        Remove-Block
        Start-Sleep -Seconds 5
        if (Test-CopyStale) { Write-Host '  (The copy has not refreshed yet. That is fine; testing anyway.)' -ForegroundColor DarkGray }
    }

    if (Test-FixApplied) {
        Write-Host ''
        Write-Host '  Fix is already applied. Measuring to confirm...'
    } else {
        Write-Host ''
        Write-Host 'Before:' -ForegroundColor Cyan
        $before = Measure-Writes $Seconds
        if ($null -eq $before) { Write-Host '  atieclxx.exe restarted during the measurement. Try again in a minute.' -ForegroundColor Yellow; return }
        Write-Host ("  {0}/s" -f (Format-Bytes $before))
        if ($before -lt $AffectedBytesPerSec) {
            Write-Host ''
            Write-Host '  Not affected: atieclxx.exe is not constantly writing, so nothing was changed.' -ForegroundColor Green
            return
        }
        if (-not (Test-Path -LiteralPath $Copy)) {
            Write-Host ''
            Write-Host '  atieclxx.exe is writing, but not to the file this fix protects:' -ForegroundColor Yellow
            Write-Host "  $Copy"
            Write-Host '  This PC has a different cause, so nothing was changed. Please open an issue with the output of Check.'
            return
        }
        Add-Block
        Write-Host '  Applied: SYSTEM can no longer overwrite or delete the copy.' -ForegroundColor Green
    }

    Write-Host ''
    Write-Host 'After:' -ForegroundColor Cyan
    $after = Measure-Writes $Seconds
    if ($null -eq $after) { Write-Host '  atieclxx.exe restarted during the measurement. Run Check in a minute.' -ForegroundColor Yellow; return }
    Write-Host ("  {0}/s" -f (Format-Bytes $after))
    Write-Host ''
    if ($after -lt $AffectedBytesPerSec) {
        Write-Host '  FIXED. The constant writes have stopped.' -ForegroundColor Green
        Write-Host '  It stays fixed after a reboot. After an AMD driver update, run Fix once more.'
    } else {
        Write-Host '  Still writing, so this PC has a different variant of the bug. Rolling back.' -ForegroundColor Yellow
        Remove-Block
        Write-Host '  Rolled back. Please open an issue with the output of Check.'
    }
}

function Invoke-Undo {
    if (-not (Test-Admin)) { throw 'Undo needs administrator rights. Right-click and run as administrator.' }
    if (-not (Test-Path -LiteralPath $Copy)) { Write-Host '  Target file not found. Nothing to undo.'; return }
    if (-not (Test-FixApplied)) { Write-Host '  Fix is not applied. Nothing to undo.'; return }
    Remove-Block
    Write-Host '  Undone. Permissions on the copy are back to normal.' -ForegroundColor Green
}

try {
    if ($Check) { Invoke-Check }
    elseif ($Fix) { Invoke-Fix }
    elseif ($Undo) { Invoke-Undo }
    else {
        [void](Show-Status)
        Write-Host ''
        Write-Host '  [C] Check   [F] Fix   [U] Undo   [Q] Quit'
        $choice = Read-Host '  Choose'
        if ($null -eq $choice) { $choice = '' }
        switch ($choice.Trim().ToUpper()) {
            'C' { Invoke-Check }
            'F' { Invoke-Fix }
            'U' { Invoke-Undo }
            default { }
        }
    }
} catch {
    Write-Host ''
    Write-Host ("  Error: {0}" -f $_.Exception.Message) -ForegroundColor Red
    exit 1
}
