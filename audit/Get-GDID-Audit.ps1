<#
.SYNOPSIS
    Get-GDID-Audit.ps1 - Reads the local Global Device Identifier (GDID) and audits
    the Microsoft provisioning/reporting chain. READ ONLY, changes nothing.

.DESCRIPTION
    Based on public reverse engineering (SmtimesIWndr/gdid-reversal) and the federal
    complaint United States v. Peter Stokes (N.D. Ill., 2026-07).

    The GDID is a 64-bit PUID (Passport Unique ID) assigned by login.live.com, stored
    in cleartext in the user hive, registered server-side by CDP, then reported by
    Delivery Optimization as UCDOStatus.GlobalDeviceId.

    This script makes NO modifications. It establishes a baseline before any mitigation.

.NOTES
    Run inside a Windows 11 VM. Nothing is sent anywhere. ASCII-only on purpose so it
    parses under any codepage (Windows PowerShell 5.1 reads .ps1 as ANSI by default).
#>

$ErrorActionPreference = 'SilentlyContinue'

function Write-Section($title) {
    Write-Host ""
    Write-Host "==== $title ====" -ForegroundColor Cyan
}

Write-Host "GDID Audit - read only" -ForegroundColor Green
Write-Host ("Windows : {0} {1}" -f (Get-CimInstance Win32_OperatingSystem).Caption, [System.Environment]::OSVersion.Version)
Write-Host ("Edition : {0}" -f (Get-CimInstance Win32_OperatingSystem).OperatingSystemSKU)
Write-Host ("Elevated: {0}" -f ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator))

# ---------------------------------------------------------------------------
# 1. PUID / GDID from the identity hive (user access, no admin needed)
# ---------------------------------------------------------------------------
Write-Section "1. PUID / GDID (identity registry, HKCU)"

$extProps = 'HKCU:\SOFTWARE\Microsoft\IdentityCRL\ExtendedProperties'
$lid = (Get-ItemProperty -Path $extProps).LID

if ($lid) {
    Write-Host "LID (hex)      : $lid"
    try {
        $decimal = [Convert]::ToUInt64($lid, 16)
        Write-Host "GDID (server)  : g:$decimal" -ForegroundColor Yellow
    } catch {
        Write-Host "  (hex->decimal conversion failed, unexpected format '$lid')" -ForegroundColor Red
    }
} else {
    Write-Host "ExtendedProperties\LID empty - falling back to Immersive Token..." -ForegroundColor DarkGray
    $tokens = Get-ItemProperty 'HKCU:\SOFTWARE\Microsoft\IdentityCRL\Immersive\production\Token\*'
    $devId  = $tokens | Select-Object -ExpandProperty DeviceId -First 1
    if ($devId) {
        Write-Host "DeviceId (Immersive) : $devId" -ForegroundColor Yellow
    } else {
        Write-Host "No PUID found in the user hive (no MSA provisioned?)." -ForegroundColor DarkGray
    }
}

# ---------------------------------------------------------------------------
# 2. Machine identity cache (HKLM - needs admin/SYSTEM to see everything)
# ---------------------------------------------------------------------------
Write-Section "2. Machine identity cache (HKLM - partial without admin)"

$negCache = 'HKLM:\SOFTWARE\Microsoft\IdentityCRL\NegativeCache'
if (Test-Path $negCache) {
    Get-ChildItem $negCache | ForEach-Object {
        Write-Host "NegativeCache : $($_.PSChildName)"
    }
} else {
    Write-Host "NegativeCache absent or not readable (insufficient rights)." -ForegroundColor DarkGray
}

# ---------------------------------------------------------------------------
# 3. State of the chain services
# ---------------------------------------------------------------------------
Write-Section "3. Service chain (mint -> register -> report)"

$chain = [ordered]@{
    'wlidsvc'    = 'Mint - provisions the PUID from login.live.com'
    'CDPSvc'     = 'Register - registers with the Device Directory Service'
    'CDPUserSvc' = 'Register - per-user variant (name suffixed per session)'
    'DoSvc'      = 'Report - reports UCDOStatus.GlobalDeviceId'
    'DiagTrack'  = 'General telemetry (Connected User Experiences)'
}

foreach ($name in $chain.Keys) {
    $svc = Get-Service | Where-Object { $_.Name -like "$name*" } | Select-Object -First 1
    if ($svc) {
        $color = if ($svc.Status -eq 'Running') { 'Red' } else { 'Green' }
        Write-Host ("{0,-14} {1,-10} - {2}" -f $svc.Name, $svc.Status, $chain[$name]) -ForegroundColor $color
    } else {
        Write-Host ("{0,-14} {1,-10} - {2}" -f $name, 'ABSENT', $chain[$name]) -ForegroundColor DarkGray
    }
}

# ---------------------------------------------------------------------------
# 4. Delivery Optimization probe (best-effort - to confirm on the VM)
# ---------------------------------------------------------------------------
Write-Section "4. Delivery Optimization (exploratory probe)"

if (Get-Command Get-DeliveryOptimizationStatus -ErrorAction SilentlyContinue) {
    $do = Get-DeliveryOptimizationStatus
    if ($do) {
        # The GlobalDeviceId field lives mostly server-side (Azure Monitor UCDOStatus).
        # We dump every property to see what the machine exposes locally.
        $do | Get-Member -MemberType Property | Select-Object -ExpandProperty Name | ForEach-Object {
            Write-Host ("  {0}" -f $_)
        }
    } else {
        Write-Host "Get-DeliveryOptimizationStatus returned nothing." -ForegroundColor DarkGray
    }
} else {
    Write-Host "Get-DeliveryOptimizationStatus cmdlet not available on this edition." -ForegroundColor DarkGray
}

# ---------------------------------------------------------------------------
# 5. DDS/CDP endpoints (DNS resolution only, no connection)
# ---------------------------------------------------------------------------
Write-Section "5. Device Directory Service endpoints (DNS resolution)"

$endpoints = @(
    'dds.microsoft.com'
    'fd.dds.microsoft.com'
    'aad.cs.dds.microsoft.com'
    'cdpcs.access.microsoft.com'
)
foreach ($ep in $endpoints) {
    $resolved = (Resolve-DnsName $ep -ErrorAction SilentlyContinue | Select-Object -First 1).IPAddress
    if ($resolved) {
        Write-Host ("{0,-30} -> {1}" -f $ep, $resolved)
    } else {
        Write-Host ("{0,-30} -> (unresolved / blocked)" -f $ep) -ForegroundColor Green
    }
}

Write-Host ""
Write-Host "Audit done - no changes made." -ForegroundColor Green
