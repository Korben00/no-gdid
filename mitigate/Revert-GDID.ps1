<#
.SYNOPSIS
    Revert-GDID.ps1 - Undoes Block-GDID-Endpoints.ps1 and Disable-GDID-Services.ps1.

.DESCRIPTION
    Removes the "# no-gdid" hosts entries and restores the services. DoSvc and the
    CDPUserSvc template are restored via the registry (Set-Service is denied for DoSvc
    on the way back too). Falls back to Windows defaults if no service-state.json.

.NOTES
    Run ELEVATED. ASCII-only. On a VM, restoring the snapshot is the guaranteed rollback.
#>

$ErrorActionPreference = 'Continue'
$tag       = '# no-gdid'
$hostsFile = "$env:WINDIR\System32\drivers\etc\hosts"
$stateFile = Join-Path $PSScriptRoot 'service-state.json'

# Windows defaults (registry Start numbers): CDPSvc=Auto(2), DoSvc=Manual(3), CDPUserSvc=Auto(2)
$defaultStart = @{ 'CDPSvc' = 2; 'DoSvc' = 3; 'CDPUserSvc' = 2 }

$elevated = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $elevated) { Write-Host "Run this elevated (admin)." -ForegroundColor Red; exit 1 }

$state = $null
if (Test-Path $stateFile) { $state = Get-Content $stateFile -Raw | ConvertFrom-Json }

function Get-Start($name) {
    if ($state -and $state.$name) {
        $v = $state.$name
        if ($v -is [string]) { switch ($v) { 'Auto' {2} 'Manual' {3} default {$defaultStart[$name]} } }
        else { [int]$v }
    } else { $defaultStart[$name] }
}

Write-Host "== Restoring services (via registry Start) ==" -ForegroundColor Cyan
foreach ($s in @('CDPSvc','DoSvc','CDPUserSvc')) {
    $reg = "HKLM:\SYSTEM\CurrentControlSet\Services\$s"
    $val = Get-Start $s
    if ($val -eq 4) { $val = $defaultStart[$s] }   # never leave it disabled on revert
    if (Test-Path $reg) {
        try {
            Set-ItemProperty -Path $reg -Name Start -Value $val -ErrorAction Stop
            Write-Host ("  {0}: Start restored to {1}" -f $s, $val) -ForegroundColor Green
        } catch {
            Write-Host ("  {0}: FAILED ({1}) - use snapshot" -f $s, $_.Exception.Message) -ForegroundColor Yellow
        }
    }
}
# CDPSvc can be started now; DoSvc/CDPUserSvc start on demand
Start-Service CDPSvc -ErrorAction SilentlyContinue

Write-Host "== Cleaning hosts ==" -ForegroundColor Cyan
if (Test-Path $hostsFile) {
    $kept = Get-Content $hostsFile | Where-Object { $_ -notmatch [regex]::Escape($tag) }
    Set-Content -Path $hostsFile -Value $kept -Encoding ASCII
    Write-Host "  removed all '# no-gdid' entries" -ForegroundColor Green
}
ipconfig /flushdns | Out-Null
Write-Host "Revert done. A reboot fully re-initializes the CDP stack." -ForegroundColor Green
