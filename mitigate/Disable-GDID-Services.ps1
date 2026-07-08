<#
.SYNOPSIS
    Disable-GDID-Services.ps1 - Disables the CDP register/report services so nothing
    locally registers the device into the Microsoft Device Directory Service graph.

.DESCRIPTION
    Preview by default. Pass -Apply to change service state. Records original startup
    types to service-state.json for Revert-GDID.ps1.

    Handles the SCM-protected DoSvc: Set-Service returns "Access denied" even elevated,
    so DoSvc (and the per-user CDPUserSvc template) are disabled via the registry
    Start value (4 = Disabled). Verified on Windows 11 Pro 26200.

    Side effects: breaks Delivery Optimization peer caching, Phone Link / cross-device
    "Continue on PC", and nearby sharing. wlidsvc (MSA sign-in) is left running.

.NOTES
    Run ELEVATED. ASCII-only.
#>

param([switch]$Apply)

$ErrorActionPreference = 'Continue'
$stateFile = Join-Path $PSScriptRoot 'service-state.json'

$elevated = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $elevated) { Write-Host "Run this elevated (admin)." -ForegroundColor Red; exit 1 }

$scmService  = 'CDPSvc'                    # disableable via SCM
$regServices = @('DoSvc','CDPUserSvc')     # SCM-protected or per-user template -> registry

if (-not $Apply) {
    Write-Host "PREVIEW (no changes). Pass -Apply to disable. Would affect:" -ForegroundColor Yellow
    Write-Host "  CDPSvc      -> Disabled (via Set-Service)"
    Write-Host "  DoSvc       -> Disabled (via registry Start=4; SCM denies Set-Service)"
    Write-Host "  CDPUserSvc  -> Disabled (per-user template, registry Start=4)"
    Write-Host "  wlidsvc     -> left running (keeps MSA sign-in)" -ForegroundColor DarkGray
    exit 0
}

# Preload any previously-saved original state so a second -Apply never clobbers the
# true pre-mitigation values (idempotency).
$saved = @{}
if (Test-Path $stateFile) {
    try {
        (Get-Content $stateFile -Raw | ConvertFrom-Json).psobject.Properties |
            ForEach-Object { $saved[$_.Name] = $_.Value }
    } catch { }
}

# Record a service's ORIGINAL start value once; never overwrite it, and never record
# an already-disabled state as the "original" (would make revert restore Disabled).
function Save-Original($key, $current, $disabled) {
    if (-not $saved.ContainsKey($key) -and "$current" -ne "$disabled") { $saved[$key] = $current }
}

# CDPSvc via SCM (StartMode is 'Auto' / 'Manual' / 'Disabled')
$cdpMode = (Get-CimInstance Win32_Service -Filter "Name='CDPSvc'").StartMode
Save-Original 'CDPSvc' $cdpMode 'Disabled'
try {
    Stop-Service CDPSvc -Force -ErrorAction Stop
    Set-Service CDPSvc -StartupType Disabled -ErrorAction Stop
    Write-Host ("  CDPSvc: stopped + disabled (was {0})" -f $cdpMode) -ForegroundColor Green
} catch {
    Write-Host ("  CDPSvc: FAILED ({0})" -f $_.Exception.Message) -ForegroundColor Red
}

# DoSvc + CDPUserSvc via registry (Start 4 = Disabled)
foreach ($s in $regServices) {
    $reg = "HKLM:\SYSTEM\CurrentControlSet\Services\$s"
    if (Test-Path $reg) {
        $cur = (Get-ItemProperty $reg).Start
        Save-Original $s $cur 4
        try {
            Set-ItemProperty -Path $reg -Name Start -Value 4 -ErrorAction Stop
            Get-Service | Where-Object { $_.Name -like "$s*" } | ForEach-Object { Stop-Service $_.Name -Force -ErrorAction SilentlyContinue }
            Write-Host ("  {0}: registry Start=4 (was {1}) + stopped" -f $s, $cur) -ForegroundColor Green
        } catch {
            Write-Host ("  {0}: FAILED ({1})" -f $s, $_.Exception.Message) -ForegroundColor Red
        }
    }
}

$saved | ConvertTo-Json | Set-Content -Path $stateFile -Encoding ASCII
Write-Host ("State saved: {0}" -f $stateFile) -ForegroundColor DarkGray
Write-Host "Done. Verify with audit/Get-GDID-Traffic.ps1. Undo with mitigate/Revert-GDID.ps1." -ForegroundColor Green
