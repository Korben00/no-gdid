<#
.SYNOPSIS
    Block-GDID-Endpoints.ps1 - Blackholes the CDP/DDS/Delivery-Optimization endpoints
    in the hosts file so the device graph cannot be reached. Keeps MSA sign-in working.

.DESCRIPTION
    Preview by default. Pass -Apply to actually edit the hosts file. Idempotent.
    Does NOT touch login.live.com (that would break Microsoft Account sign-in).
    On first -Apply the original hosts file is backed up to hosts.nogdid-backup
    (kept intact on later runs) as a manual recovery net.

    Verified on Windows 11 Pro 26200: after applying, the five hosts resolve to
    0.0.0.0 while login.live.com still resolves and wlidsvc stays connected.

    Undo with Revert-GDID.ps1.

.NOTES
    Run ELEVATED. ASCII-only.
#>

param([switch]$Apply)

$ErrorActionPreference = 'Stop'
$tag        = '# no-gdid'
$hostsFile   = "$env:WINDIR\System32\drivers\etc\hosts"
$hostsBackup = "$hostsFile.nogdid-backup"
$blockHosts = @(
    'dds.microsoft.com'
    'fd.dds.microsoft.com'
    'aad.cs.dds.microsoft.com'
    'cdpcs.access.microsoft.com'
    'geo.prod.do.dsp.mp.microsoft.com'
)

$elevated = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $elevated) { Write-Host "Run this elevated (admin)." -ForegroundColor Red; exit 1 }

$existing = Get-Content $hostsFile -ErrorAction SilentlyContinue

if (-not $Apply) {
    Write-Host "PREVIEW (no changes). Pass -Apply to write. Would blackhole:" -ForegroundColor Yellow
    foreach ($h in $blockHosts) {
        # Anchor on the full hostname as a whole token: 'dds.microsoft.com' must NOT
        # match inside 'fd.dds.microsoft.com' (substring false positive).
        $state = if ($existing -match "(^|\s)$([regex]::Escape($h))(\s|$)") { 'already present' } else { 'to add' }
        Write-Host ("  0.0.0.0 {0,-34} [{1}]" -f $h, $state)
    }
    Write-Host "login.live.com is intentionally left alone (keeps MSA working)." -ForegroundColor DarkGray
    exit 0
}

# One-time backup of the original hosts file (kept intact if it already exists).
if (-not (Test-Path $hostsBackup)) {
    Copy-Item -Path $hostsFile -Destination $hostsBackup -Force
    Write-Host ("Backup of hosts written: {0}" -f $hostsBackup) -ForegroundColor DarkGray
} else {
    Write-Host ("Backup already exists (kept): {0}" -f $hostsBackup) -ForegroundColor DarkGray
}

# Collect every missing entry first, then write ONCE. Writing line-by-line
# trips over the transient lock Defender/AV puts on hosts right after each
# write (IOException: file is being used by another process).
$toAdd = @()
foreach ($h in $blockHosts) {
    if ($existing -match "(^|\s)$([regex]::Escape($h))(\s|$)") {
        Write-Host ("  {0}: already present, skipped" -f $h) -ForegroundColor DarkGray
    } else {
        $toAdd += ("0.0.0.0 {0} {1}" -f $h, $tag)
    }
}
if ($toAdd.Count -gt 0) {
    $maxTries = 5
    for ($try = 1; $try -le $maxTries; $try++) {
        try {
            Add-Content -Path $hostsFile -Value $toAdd -Encoding ASCII
            break
        } catch [System.IO.IOException] {
            if ($try -eq $maxTries) {
                Write-Host "hosts file still locked after $maxTries attempts (AV or another process holding it). Re-run the script; already-written entries are skipped." -ForegroundColor Red
                throw
            }
            Start-Sleep -Milliseconds (400 * $try)
        }
    }
    foreach ($line in $toAdd) {
        Write-Host ("  {0}: blackholed" -f ($line -split '\s+')[1]) -ForegroundColor Green
    }
}
ipconfig /flushdns | Out-Null
Write-Host "Done. Verify with audit/Get-GDID-Traffic.ps1. Undo with mitigate/Revert-GDID.ps1." -ForegroundColor Green
