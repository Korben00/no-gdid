<#
.SYNOPSIS
    Get-GDID-Traffic.ps1 - Maps the real outbound endpoints of the GDID chain
    (wlidsvc / CDPSvc / CDPUserSvc / DoSvc). READ ONLY.

.DESCRIPTION
    The documented endpoint list (dds.microsoft.com, ...) did not resolve on the
    baseline VM, so we observe what the services actually talk to instead of trusting
    a possibly-internal list. This is the input for any network-level mitigation.

    Run ELEVATED (admin) so process->service PID mapping and connection ownership
    are fully visible. Still makes NO modifications.

.NOTES
    ASCII-only. If connections are empty at rest, use the pktmon hint at the end.
#>

$ErrorActionPreference = 'SilentlyContinue'

function Write-Section($t) { Write-Host ""; Write-Host "==== $t ====" -ForegroundColor Cyan }

Write-Host "GDID Traffic map - read only" -ForegroundColor Green
$elevated = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
Write-Host ("Elevated: {0}" -f $elevated)
if (-not $elevated) { Write-Host "WARNING: run as admin for full PID/connection visibility." -ForegroundColor Yellow }

# ---------------------------------------------------------------------------
# 0. DNS control - prove resolution works at all, then test the doc endpoints
# ---------------------------------------------------------------------------
Write-Section "0. DNS control + documented endpoints (with CNAME chain)"

$controls = @('login.live.com','www.microsoft.com')
$targets  = @('dds.microsoft.com','fd.dds.microsoft.com','aad.cs.dds.microsoft.com',
              'cdpcs.access.microsoft.com','geo.prod.do.dsp.mp.microsoft.com')

foreach ($h in ($controls + $targets)) {
    $ans = Resolve-DnsName $h -ErrorAction SilentlyContinue
    if ($ans) {
        $chain = ($ans | ForEach-Object {
            if ($_.NameHost) { "CNAME->$($_.NameHost)" }
            elseif ($_.IPAddress) { $_.IPAddress }
        }) -join ', '
        Write-Host ("{0,-34} {1}" -f $h, $chain)
    } else {
        Write-Host ("{0,-34} (no record)" -f $h) -ForegroundColor DarkGray
    }
}

# ---------------------------------------------------------------------------
# 1. PID of each chain service
# ---------------------------------------------------------------------------
Write-Section "1. Service -> PID mapping"

$svcNames = @('wlidsvc','CDPSvc','DoSvc')
$pidMap = @{}
Get-CimInstance Win32_Service | Where-Object {
    $n = $_.Name
    ($svcNames -contains $n) -or ($n -like 'CDPUserSvc*')
} | ForEach-Object {
    Write-Host ("{0,-16} PID={1,-8} State={2}" -f $_.Name, $_.ProcessId, $_.State)
    if ($_.ProcessId -gt 0) { $pidMap[$_.ProcessId] = $_.Name }
}

# ---------------------------------------------------------------------------
# 2. Live TCP connections owned by those PIDs
# ---------------------------------------------------------------------------
Write-Section "2. Live TCP connections of the chain (remote endpoints)"

$found = $false
Get-NetTCPConnection -ErrorAction SilentlyContinue |
    Where-Object { $pidMap.ContainsKey($_.OwningProcess) -and $_.RemoteAddress -notin @('0.0.0.0','::','127.0.0.1','::1') } |
    ForEach-Object {
        $found = $true
        $remoteHost = try { (Resolve-DnsName $_.RemoteAddress -ErrorAction SilentlyContinue | Select-Object -First 1).NameHost } catch { $null }
        Write-Host ("{0,-16} {1,-22}:{2,-5} {3,-12} {4}" -f $pidMap[$_.OwningProcess], $_.RemoteAddress, $_.RemotePort, $_.State, $remoteHost)
    }
if (-not $found) { Write-Host "No active remote connection right now (services register periodically)." -ForegroundColor DarkGray }

# ---------------------------------------------------------------------------
# 3. DNS client cache - what these services recently resolved
# ---------------------------------------------------------------------------
Write-Section "3. DNS client cache (microsoft/live/dds/cdp/dsp)"

$hits = Get-DnsClientCache -ErrorAction SilentlyContinue |
    Where-Object { $_.Entry -match '(?i)microsoft|live|dds|cdp|dsp|\.do\.' } |
    Select-Object Entry, Data -Unique
if ($hits) {
    $hits | ForEach-Object { Write-Host ("{0,-40} {1}" -f $_.Entry, $_.Data) }
} else {
    Write-Host "Nothing relevant in the DNS cache (may have expired)." -ForegroundColor DarkGray
}

Write-Host ""
Write-Host "If connections/cache are empty, capture live traffic for ~60s with:" -ForegroundColor Yellow
Write-Host '  pktmon start --capture --pkt-size 0 --file-name gdid.etl' -ForegroundColor Gray
Write-Host '  (wait, or run: Get-DeliveryOptimizationStatus | Out-Null ; Restart-Service CDPSvc)' -ForegroundColor Gray
Write-Host '  pktmon stop ; pktmon etl2txt gdid.etl' -ForegroundColor Gray
Write-Host "Traffic map done - no changes made." -ForegroundColor Green
