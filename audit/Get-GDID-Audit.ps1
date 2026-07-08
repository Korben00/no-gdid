<#
.SYNOPSIS
    Get-GDID-Audit.ps1 — Lit le Global Device Identifier (GDID) local et audite
    la chaine de provisioning/reporting Microsoft. LECTURE SEULE, ne modifie rien.

.DESCRIPTION
    Basé sur le reverse engineering public (SmtimesIWndr/gdid-reversal) et la
    plainte fédérale United States v. Peter Stokes (N.D. Ill., 2026-07).

    Le GDID est un PUID (Passport Unique ID) 64-bit assigné par login.live.com,
    stocké en clair dans la ruche utilisateur, enregistré côté serveur par CDP,
    puis remonté par Delivery Optimization sous UCDOStatus.GlobalDeviceId.

    Ce script NE FAIT AUCUNE MODIFICATION. Il sert à établir la baseline avant
    toute mitigation.

.NOTES
    À exécuter dans une VM Windows 11. Aucune donnée n'est envoyée nulle part.
#>

$ErrorActionPreference = 'SilentlyContinue'

function Write-Section($title) {
    Write-Host ""
    Write-Host "==== $title ====" -ForegroundColor Cyan
}

Write-Host "GDID Audit — lecture seule" -ForegroundColor Green
Write-Host "Build Windows : $((Get-CimInstance Win32_OperatingSystem).Caption) $([System.Environment]::OSVersion.Version)"

# ---------------------------------------------------------------------------
# 1. PUID / GDID depuis la ruche identité (accès utilisateur, pas d'admin)
# ---------------------------------------------------------------------------
Write-Section "1. PUID / GDID (registre identité HKCU)"

$extProps = 'HKCU:\SOFTWARE\Microsoft\IdentityCRL\ExtendedProperties'
$lid = (Get-ItemProperty -Path $extProps).LID

if ($lid) {
    Write-Host "LID (hex)      : $lid"
    try {
        $decimal = [Convert]::ToUInt64($lid, 16)
        Write-Host "GDID (serveur) : g:$decimal" -ForegroundColor Yellow
    } catch {
        Write-Host "  (conversion hex->decimal impossible : format inattendu '$lid')" -ForegroundColor Red
    }
} else {
    Write-Host "ExtendedProperties\LID vide — fallback sur Immersive Token..." -ForegroundColor DarkGray
    $tokens = Get-ItemProperty 'HKCU:\SOFTWARE\Microsoft\IdentityCRL\Immersive\production\Token\*'
    $devId  = $tokens | Select-Object -ExpandProperty DeviceId -First 1
    if ($devId) {
        Write-Host "DeviceId (Immersive) : $devId" -ForegroundColor Yellow
    } else {
        Write-Host "Aucun PUID trouvé dans la ruche utilisateur (pas de MSA provisionné ?)." -ForegroundColor DarkGray
    }
}

# ---------------------------------------------------------------------------
# 2. Cache d'identité HKLM (nécessite SYSTEM/admin pour tout voir)
# ---------------------------------------------------------------------------
Write-Section "2. Cache identité machine (HKLM — partiel sans admin)"

$negCache = 'HKLM:\SOFTWARE\Microsoft\IdentityCRL\NegativeCache'
if (Test-Path $negCache) {
    Get-ChildItem $negCache | ForEach-Object {
        Write-Host "NegativeCache : $($_.PSChildName)"
    }
} else {
    Write-Host "NegativeCache absent ou non lisible (droits insuffisants)." -ForegroundColor DarkGray
}

# ---------------------------------------------------------------------------
# 3. État des services de la chaîne
# ---------------------------------------------------------------------------
Write-Section "3. Chaîne de services (mint -> register -> report)"

$chain = [ordered]@{
    'wlidsvc'    = 'Mint — provisionne le PUID auprès de login.live.com'
    'CDPSvc'     = 'Register — enregistre auprès du Device Directory Service'
    'CDPUserSvc' = 'Register — variante utilisateur (nom suffixé par session)'
    'DoSvc'      = 'Report — remonte UCDOStatus.GlobalDeviceId'
    'DiagTrack'  = 'Télémétrie générale (Connected User Experiences)'
}

foreach ($name in $chain.Keys) {
    $svc = Get-Service | Where-Object { $_.Name -like "$name*" } | Select-Object -First 1
    if ($svc) {
        $color = if ($svc.Status -eq 'Running') { 'Red' } else { 'Green' }
        Write-Host ("{0,-12} {1,-10} — {2}" -f $svc.Name, $svc.Status, $chain[$name]) -ForegroundColor $color
    } else {
        Write-Host ("{0,-12} {1,-10} — {2}" -f $name, 'ABSENT', $chain[$name]) -ForegroundColor DarkGray
    }
}

# ---------------------------------------------------------------------------
# 4. Sonde Delivery Optimization (best-effort — à valider sur la VM)
# ---------------------------------------------------------------------------
Write-Section "4. Delivery Optimization (sonde exploratoire)"

if (Get-Command Get-DeliveryOptimizationStatus -ErrorAction SilentlyContinue) {
    $do = Get-DeliveryOptimizationStatus
    if ($do) {
        # Le champ GlobalDeviceId vit surtout côté Azure Monitor (UCDOStatus).
        # On dumpe toutes les propriétés pour voir ce que la machine expose en local.
        $do | Get-Member -MemberType Property | Select-Object -ExpandProperty Name | ForEach-Object {
            Write-Host ("  {0}" -f $_)
        }
    } else {
        Write-Host "Get-DeliveryOptimizationStatus n'a rien retourné." -ForegroundColor DarkGray
    }
} else {
    Write-Host "Cmdlet Get-DeliveryOptimizationStatus indisponible sur cette édition." -ForegroundColor DarkGray
}

# ---------------------------------------------------------------------------
# 5. Endpoints DDS/CDP (résolution DNS seulement, aucune connexion)
# ---------------------------------------------------------------------------
Write-Section "5. Endpoints Device Directory Service (résolution DNS)"

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
        Write-Host ("{0,-30} -> (non résolu / bloqué)" -f $ep) -ForegroundColor Green
    }
}

Write-Host ""
Write-Host "Audit terminé — aucune modification effectuée." -ForegroundColor Green
