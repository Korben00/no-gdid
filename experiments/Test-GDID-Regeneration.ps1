<#
.SYNOPSIS
    Test-GDID-Regeneration.ps1 - DESTRUCTIVE PROBE. Removes the local LID (GDID),
    restarts wlidsvc, and checks whether the SAME value comes back.

.DESCRIPTION
    Goal: prove whether the GDID is anchored to the Microsoft Account (comes back
    identical) or to the local install (comes back new / empty).

    Safety:
      - Refuses to run without -IHaveASnapshot (take a VMware snapshot first).
      - Backs up HKCU\...\IdentityCRL\ExtendedProperties to a .reg file before deleting.
      - Only removes the LID *value*, not the whole key.

    Reverting: restore the VMware snapshot, or re-import the .reg backup, or just
    sign into any Microsoft app (Store/Settings) to force wlidsvc to re-mint.

.PARAMETER IHaveASnapshot
    Explicit confirmation that a VMware snapshot exists. Required.

.NOTES
    Run ELEVATED. ASCII-only.
#>

param(
    [switch]$IHaveASnapshot
)

$ErrorActionPreference = 'Stop'
$extProps = 'HKCU:\SOFTWARE\Microsoft\IdentityCRL\ExtendedProperties'
$regPath  = 'HKCU\SOFTWARE\Microsoft\IdentityCRL\ExtendedProperties'

function Read-GDID {
    $lid = (Get-ItemProperty -Path $extProps -ErrorAction SilentlyContinue).LID
    if ($lid) {
        try { return @{ Hex = $lid; G = ("g:{0}" -f [Convert]::ToUInt64($lid,16)) } }
        catch { return @{ Hex = $lid; G = "(bad format)" } }
    }
    return $null
}

if (-not $IHaveASnapshot) {
    Write-Host "REFUSED: take a VMware snapshot first, then re-run with -IHaveASnapshot" -ForegroundColor Red
    Write-Host "  Example: .\Test-GDID-Regeneration.ps1 -IHaveASnapshot" -ForegroundColor Gray
    exit 1
}

Write-Host "== BEFORE ==" -ForegroundColor Cyan
$before = Read-GDID
if (-not $before) { Write-Host "No LID present - nothing to test."; exit 0 }
Write-Host ("LID={0}  ->  {1}" -f $before.Hex, $before.G) -ForegroundColor Yellow

# Backup the whole key
$backup = Join-Path $PSScriptRoot ("ExtendedProperties-backup-{0}.reg" -f (Get-Date -Format 'yyyyMMdd-HHmmss'))
reg export $regPath $backup /y | Out-Null
Write-Host ("Backup written: {0}" -f $backup) -ForegroundColor Green

# Remove only the LID value
Write-Host "Removing LID value..." -ForegroundColor Cyan
Remove-ItemProperty -Path $extProps -Name 'LID' -ErrorAction SilentlyContinue

Write-Host "Restarting wlidsvc..." -ForegroundColor Cyan
Restart-Service wlidsvc -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 5

Write-Host "== AFTER restart ==" -ForegroundColor Cyan
$after = Read-GDID
if (-not $after) {
    Write-Host "LID still empty after restart." -ForegroundColor Yellow
    Write-Host "wlidsvc re-mints on demand: open Settings > Accounts (or the Store) to" -ForegroundColor Gray
    Write-Host "trigger an MSA token refresh, then re-run Get-GDID-Audit.ps1 to read again." -ForegroundColor Gray
    exit 0
}

Write-Host ("LID={0}  ->  {1}" -f $after.Hex, $after.G) -ForegroundColor Yellow
Write-Host ""
if ($after.G -eq $before.G) {
    Write-Host "RESULT: IDENTICAL. The GDID is anchored to the Microsoft Account, not the" -ForegroundColor Red
    Write-Host "        local install. Deleting it locally is cosmetic - it comes straight back." -ForegroundColor Red
} else {
    Write-Host "RESULT: CHANGED. Local rotation produced a new value - worth documenting how." -ForegroundColor Green
}
