<#
.SYNOPSIS
    Test-Mitigation-Block.ps1 - DESTRUCTIVE. Disables the CDP/DO reporting chain and
    blocks its endpoints via the hosts file, WITHOUT touching MSA sign-in.

.DESCRIPTION
    Goal: prove that the register/report layer (CDPSvc/CDPUserSvc/DoSvc + DDS/DO
    endpoints) can be silenced while the machine stays signed into the Microsoft
    Account. The GDID stays readable locally (cached) but is no longer reported.

    Does NOT block login.live.com (that would break MSA sign-in - not the goal).

    Safety:
      - Refuses without -IHaveASnapshot.
      - Records original service startup types to a JSON file for revert.
      - Tags hosts entries with "# no-gdid" for clean removal.
    The VMware snapshot remains the guaranteed restore path.

.NOTES
    Run ELEVATED. ASCII-only. After running, launch Get-GDID-Traffic.ps1 to observe.
#>

param([switch]$IHaveASnapshot)

$ErrorActionPreference = 'Continue'
$tag       = '# no-gdid'
$hostsFile = "$env:WINDIR\System32\drivers\etc\hosts"
$stateFile = Join-Path $PSScriptRoot 'mitigation-state.json'

# Endpoints to blackhole (NOT login.live.com)
$blockHosts = @(
    'dds.microsoft.com'
    'fd.dds.microsoft.com'
    'aad.cs.dds.microsoft.com'
    'cdpcs.access.microsoft.com'
    'geo.prod.do.dsp.mp.microsoft.com'
)
# Services to disable (register + report). wlidsvc left alone to keep MSA working.
$svcTargets = @('CDPSvc','DoSvc')

if (-not $IHaveASnapshot) {
    Write-Host "REFUSED: take a VMware snapshot, then re-run with -IHaveASnapshot" -ForegroundColor Red
    exit 1
}

# --- 1. Record + disable services -----------------------------------------
Write-Host "== Disabling reporting services ==" -ForegroundColor Cyan
$saved = @{}
foreach ($s in $svcTargets) {
    $svc = Get-Service -Name $s -ErrorAction SilentlyContinue
    if ($svc) {
        $startType = (Get-CimInstance Win32_Service -Filter "Name='$s'").StartMode
        $saved[$s] = $startType
        try {
            Stop-Service -Name $s -Force -ErrorAction Stop
            Set-Service -Name $s -StartupType Disabled -ErrorAction Stop
            Write-Host ("  {0}: stopped + disabled (was {1})" -f $s, $startType) -ForegroundColor Green
        } catch {
            Write-Host ("  {0}: FAILED ({1})" -f $s, $_.Exception.Message) -ForegroundColor Red
        }
    }
}

# CDPUserSvc is a per-user template service: disable via registry Start=4
$cdpUserReg = 'HKLM:\SYSTEM\CurrentControlSet\Services\CDPUserSvc'
if (Test-Path $cdpUserReg) {
    $saved['CDPUserSvc_Start'] = (Get-ItemProperty $cdpUserReg).Start
    try {
        Set-ItemProperty -Path $cdpUserReg -Name Start -Value 4 -ErrorAction Stop
        Get-Service | Where-Object { $_.Name -like 'CDPUserSvc*' } | ForEach-Object { Stop-Service $_.Name -Force -ErrorAction SilentlyContinue }
        Write-Host ("  CDPUserSvc (template): Start set to 4/disabled (was {0})" -f $saved['CDPUserSvc_Start']) -ForegroundColor Green
    } catch {
        Write-Host ("  CDPUserSvc: could not set Start ({0})" -f $_.Exception.Message) -ForegroundColor Yellow
    }
}

$saved | ConvertTo-Json | Set-Content -Path $stateFile -Encoding ASCII
Write-Host ("State saved: {0}" -f $stateFile) -ForegroundColor DarkGray

# --- 2. Blackhole endpoints via hosts -------------------------------------
Write-Host "== Blocking endpoints via hosts ==" -ForegroundColor Cyan
$existing = Get-Content $hostsFile -ErrorAction SilentlyContinue
foreach ($h in $blockHosts) {
    if ($existing -match [regex]::Escape($h)) {
        Write-Host ("  {0}: already present, skipped" -f $h) -ForegroundColor DarkGray
    } else {
        Add-Content -Path $hostsFile -Value ("0.0.0.0 {0} {1}" -f $h, $tag) -Encoding ASCII
        Write-Host ("  {0}: blackholed" -f $h) -ForegroundColor Green
    }
}

ipconfig /flushdns | Out-Null
Write-Host "DNS cache flushed." -ForegroundColor DarkGray

Write-Host ""
Write-Host "Applied. Now run Get-GDID-Traffic.ps1 (admin) to confirm:" -ForegroundColor Yellow
Write-Host "  - CDPSvc/DoSvc show Stopped, CDPUserSvc absent" -ForegroundColor Gray
Write-Host "  - the blocked hosts resolve to 0.0.0.0 (blocked)" -ForegroundColor Gray
Write-Host "  - login.live.com still resolves and wlidsvc still connects (MSA intact)" -ForegroundColor Gray
Write-Host "Then confirm the GDID is STILL readable locally with Get-GDID-Audit.ps1." -ForegroundColor Gray
