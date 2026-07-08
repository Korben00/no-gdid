<#
.SYNOPSIS
    Revert-Mitigation-Block.ps1 - Undoes Test-Mitigation-Block.ps1.

.DESCRIPTION
    Removes the "# no-gdid" hosts entries and restores the services to the startup
    types recorded in mitigation-state.json (falls back to Windows defaults).

    Note: restoring the VMware snapshot is the guaranteed, complete revert. This
    script exists so the eventual mitigate/ version is self-contained.

.NOTES
    Run ELEVATED. ASCII-only.
#>

$ErrorActionPreference = 'Continue'
$tag       = '# no-gdid'
$hostsFile = "$env:WINDIR\System32\drivers\etc\hosts"
$stateFile = Join-Path $PSScriptRoot 'mitigation-state.json'

# Defaults if no state file
$defaults = @{ 'CDPSvc' = 'Automatic'; 'DoSvc' = 'Manual'; 'CDPUserSvc_Start' = 3 }

# --- 1. Restore services ---------------------------------------------------
Write-Host "== Restoring services ==" -ForegroundColor Cyan
$state = $null
if (Test-Path $stateFile) { $state = Get-Content $stateFile -Raw | ConvertFrom-Json }

function Resolve-StartType($name, $modeString) {
    switch ($modeString) {
        'Auto'     { 'Automatic' }
        'Manual'   { 'Manual' }
        'Disabled' { 'Manual' }   # never re-disable on revert
        default    { $defaults[$name] }
    }
}

foreach ($s in @('CDPSvc','DoSvc')) {
    $mode = if ($state -and $state.$s) { Resolve-StartType $s $state.$s } else { $defaults[$s] }
    try {
        Set-Service -Name $s -StartupType $mode -ErrorAction Stop
        Start-Service -Name $s -ErrorAction SilentlyContinue
        Write-Host ("  {0}: startup={1}, started" -f $s, $mode) -ForegroundColor Green
    } catch {
        Write-Host ("  {0}: FAILED ({1})" -f $s, $_.Exception.Message) -ForegroundColor Red
    }
}

$cdpUserReg = 'HKLM:\SYSTEM\CurrentControlSet\Services\CDPUserSvc'
if (Test-Path $cdpUserReg) {
    $val = if ($state -and $state.'CDPUserSvc_Start') { [int]$state.'CDPUserSvc_Start' } else { $defaults['CDPUserSvc_Start'] }
    try {
        Set-ItemProperty -Path $cdpUserReg -Name Start -Value $val -ErrorAction Stop
        Write-Host ("  CDPUserSvc (template): Start restored to {0}" -f $val) -ForegroundColor Green
    } catch {
        Write-Host ("  CDPUserSvc: could not restore Start ({0})" -f $_.Exception.Message) -ForegroundColor Yellow
    }
}

# --- 2. Clean hosts --------------------------------------------------------
Write-Host "== Cleaning hosts ==" -ForegroundColor Cyan
if (Test-Path $hostsFile) {
    $kept = Get-Content $hostsFile | Where-Object { $_ -notmatch [regex]::Escape($tag) }
    Set-Content -Path $hostsFile -Value $kept -Encoding ASCII
    Write-Host "  removed all '# no-gdid' entries" -ForegroundColor Green
}

ipconfig /flushdns | Out-Null
Write-Host "DNS cache flushed." -ForegroundColor DarkGray
Write-Host "Revert done. (Snapshot restore remains the guaranteed full rollback.)" -ForegroundColor Green
