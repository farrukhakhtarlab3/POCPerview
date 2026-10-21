<#
    UTILITY - Tidy up duplicate POC certificates.

    Several certificates with the same subject can accumulate across attempts.
    Only the one uploaded to the app registration authenticates, and the scripts
    pick the newest by date - so a stale duplicate can cause a confusing auth
    failure later.

    Dry run by default. Nothing is removed without -Execute.

    Find the thumbprint that works by running 02-Test-Connection.ps1 - it prints
    the one it used to connect successfully.
#>
[CmdletBinding()]
param(
    # The certificate to keep. Defaults to the newest.
    [string]$KeepThumbprint,

    [switch]$Execute
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Common.ps1')

Write-Step "Certificates matching '$script:CertSubject'"
$certs = @(Get-ChildItem Cert:\CurrentUser\My |
    Where-Object { $_.Subject -eq $script:CertSubject } |
    Sort-Object NotBefore -Descending)

if ($certs.Count -eq 0) {
    Write-Warn2 'None found. Nothing to do.'
    return
}

foreach ($c in $certs) {
    Write-Info ("{0}  created {1}  expires {2}" -f $c.Thumbprint, $c.NotBefore, $c.NotAfter)
}

if ($certs.Count -eq 1) {
    Write-Ok 'Only one certificate. Nothing to clean up.'
    return
}

Write-Warn2 "$($certs.Count) certificates share this subject."

if (-not $KeepThumbprint) {
    $KeepThumbprint = $certs[0].Thumbprint
    Write-Info "No -KeepThumbprint given. Defaulting to the newest: $KeepThumbprint"
    Write-Info 'If that is not the one uploaded to the app registration, pass the'
    Write-Info 'correct thumbprint explicitly - 02-Test-Connection.ps1 prints it.'
}

$keep = $certs | Where-Object { $_.Thumbprint -eq $KeepThumbprint }
if (-not $keep) {
    Write-Bad "No certificate here has thumbprint $KeepThumbprint."
    return
}

$remove = @($certs | Where-Object { $_.Thumbprint -ne $KeepThumbprint })

Write-Step 'Plan'
Write-Ok   "KEEP   $KeepThumbprint"
foreach ($c in $remove) { Write-Host "  REMOVE $($c.Thumbprint)" -ForegroundColor Red }

if (-not $Execute) {
    Write-Step 'DRY RUN - nothing removed'
    Write-Info 'Re-run with -Execute to apply.'
    return
}

Write-Step 'Removing'
foreach ($c in $remove) {
    try {
        $c | Remove-Item -ErrorAction Stop
        Write-Ok "Removed $($c.Thumbprint)"
    }
    catch {
        Write-Bad "Could not remove $($c.Thumbprint): $($_.Exception.Message)"
    }
}

Write-Step 'Verify'
Write-Info 'Re-run .\02-Test-Connection.ps1 to confirm authentication still works.'
