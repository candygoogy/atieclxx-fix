<#
.SYNOPSIS
    Stops the AMD External Events Utility (atieclxx.exe) from rewriting its own
    677 KB copy every second, which writes ~40 GB a day to the system SSD.

.DESCRIPTION
    atieclxx.exe copies itself from the DriverStore to
    C:\Windows\System32\config\systemprofile\AppData\Local\AMD\atieclxx.exe
    about once a second, forever. The bytes are identical every time, but
    Windows still flushes them to disk.

    The fix denies the SYSTEM account write/delete access to that one copy.
    The copy fails before any data is written, the existing copy (identical to
    the original) stays in place, and the service keeps running.

    Run with no switch for a menu. Needs admin for -Fix and -Undo.

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
$Copy        = Join-Path $env:SystemRoot 'System32\config\systemprofile\AppData\Local\AMD\atieclxx.exe'
$SystemSid   = 'S-1-5-18'
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

function Test-FixApplied {
    if (-not (Test-Path -LiteralPath $Copy)) { return $false }
    $acl = Get-Acl -LiteralPath $Copy
    foreach ($rule in $acl.Access) {
        if ($rule.AccessControlType -ne 'Deny') { continue }
        try { $sid = $rule.IdentityReference.Translate([Security.Principal.SecurityIdentifier]).Value } catch { continue }
        if ($sid -eq $SystemSid) { return $true }
    }
    return $false
}

function Show-Status {
    $admin = Test-Admin
    $proc  = Get-Utility
    $drv   = Get-CimInstance Win32_VideoController | Where-Object { $_.Name -match 'Radeon|AMD' } | Select-Object -First 1

    Write-Host ''
    Write-Host 'atieclxx-fix status' -ForegroundColor Cyan
    if ($drv) { Write-Host ("  GPU / driver:   {0} / {1}" -f $drv.Name, $drv.DriverVersion) }
    if ($proc) {
        $up = (Get-Date) - $proc.CreationDate
        Write-Host ("  atieclxx.exe:   running (PID {0}, up {1:N1} h)" -f $proc.ProcessId, $up.TotalHours)
        Write-Host ("  Written so far: {0} since it started" -f (Format-Bytes $proc.WriteTransferCount))
    } else {
        Write-Host '  atieclxx.exe:   not running (nothing to fix right now)'
    }
    if ($admin) {
        $state = if (-not (Test-Path -LiteralPath $Copy)) { 'target file not found' }
                 elseif (Test-FixApplied) { 'APPLIED' } else { 'not applied' }
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

function Invoke-Icacls([string[]]$icaclsArgs) {
    $out = & icacls.exe @icaclsArgs 2>&1
    if ($LASTEXITCODE -ne 0) { throw "icacls failed: $out" }
}

function Invoke-Fix {
    if (-not (Test-Admin)) { throw 'The fix needs administrator rights. Right-click and run as administrator.' }
    [void](Show-Status)
    if (-not (Get-Utility)) { Write-Host '  atieclxx.exe is not running. Nothing to fix.'; return }
    if (-not (Test-Path -LiteralPath $Copy)) {
        Write-Host ''
        Write-Host "  The file this fix protects doesn't exist on this PC:" -ForegroundColor Yellow
        Write-Host "  $Copy"
        Write-Host '  Your writes (if any) come from a different cause. Please open an issue with the output of -Check.'
        return
    }
    if (Test-FixApplied) { Write-Host '  Fix is already applied. Measuring to confirm...' }
    else {
        Write-Host ''
        Write-Host 'Before:' -ForegroundColor Cyan
        $before = Measure-Writes $Seconds
        if ($null -ne $before) { Write-Host ("  {0}/s" -f (Format-Bytes $before)) }

        Invoke-Icacls @($Copy, '/deny', "*${SystemSid}:(W,D)")
        Write-Host '  Applied: SYSTEM can no longer overwrite or delete the copy.' -ForegroundColor Green
    }

    Write-Host ''
    Write-Host 'After:' -ForegroundColor Cyan
    $after = Measure-Writes $Seconds
    if ($null -eq $after) { Write-Host '  atieclxx.exe restarted during the measurement. Run -Check in a minute.' -ForegroundColor Yellow; return }
    Write-Host ("  {0}/s" -f (Format-Bytes $after))
    Write-Host ''
    if ($after -lt $AffectedBytesPerSec) {
        Write-Host '  FIXED. The constant writes have stopped.' -ForegroundColor Green
        Write-Host '  The fix stays after a reboot. Run -Undo before you install a new AMD driver.'
    } else {
        Write-Host '  Still writing, so this PC has a different variant of the bug. Rolling back.' -ForegroundColor Yellow
        Invoke-Icacls @($Copy, '/remove:d', "*$SystemSid")
        Write-Host '  Rolled back. Please open an issue with the output of -Check.'
    }
}

function Invoke-Undo {
    if (-not (Test-Admin)) { throw 'Undo needs administrator rights. Right-click and run as administrator.' }
    if (-not (Test-Path -LiteralPath $Copy)) { Write-Host '  Target file not found. Nothing to undo.'; return }
    if (-not (Test-FixApplied)) { Write-Host '  Fix is not applied. Nothing to undo.'; return }
    Invoke-Icacls @($Copy, '/remove:d', "*$SystemSid")
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
        switch ((Read-Host '  Choose').Trim().ToUpper()) {
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
