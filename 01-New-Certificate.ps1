<#
    STEP 1 - Create the authentication certificate.

    SKIP THIS if your certificate is already created and uploaded to the app
    registration. Running it again makes a NEW certificate that Entra does not
    know about, and authentication will then fail.

    Use -Force only when you genuinely need to start over.
#>
[CmdletBinding()]
param(
    [switch]$Force,
    [int]$ValidYears = 1
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Common.ps1')

Write-Step 'Checking for an existing certificate'
$existing = @(Get-ChildItem Cert:\CurrentUser\My |
    Where-Object { $_.Subject -eq $script:CertSubject } |
    Sort-Object NotBefore -Descending)

if ($existing.Count -gt 0 -and -not $Force) {
    Write-Ok "Found $($existing.Count) certificate(s) already."
    foreach ($c in $existing) {
        Write-Info "Thumbprint : $($c.Thumbprint)"
        Write-Info "Expires    : $($c.NotAfter)"
    }
    Write-Host ''
    Write-Warn2 'Not creating a new one. The uploaded certificate is the only one that works.'
    Write-Info  'Re-run with -Force only if you intend to replace it and re-upload.'
    Write-Step 'Next'
    Write-Info 'Run  .\02-Test-Connection.ps1'
    return
}

if ($Force -and $existing.Count -gt 0) {
    Write-Warn2 "Removing $($existing.Count) existing certificate(s)."
    $existing | Remove-Item
}

Write-Step 'Creating certificate'
# -KeySpec KeyExchange forces a legacy CSP provider. Modern Windows defaults to
# CNG, which Exchange app-only authentication does NOT support - and the failure
# surfaces much later with an error that never mentions certificates.
$cert = New-SelfSignedCertificate `
    -Subject $script:CertSubject `
    -CertStoreLocation 'Cert:\CurrentUser\My' `
    -KeySpec KeyExchange `
    -NotAfter (Get-Date).AddYears($ValidYears)

Write-Ok "Created. Thumbprint: $($cert.Thumbprint)"

Write-Step 'Verifying it is CSP, not CNG'
if ($cert.PrivateKey) {
    Write-Ok 'CSP confirmed - compatible with Connect-ExchangeOnline.'
}
else {
    Write-Bad 'Private key is not a CSP key. This certificate will NOT authenticate.'
    Write-Info 'Delete it and re-run with -Force.'
    return
}

Write-Step 'Exporting the public key'
# Desktop is frequently redirected to OneDrive on a managed VDI, so resolve it
# properly rather than assuming $env:USERPROFILE\Desktop exists.
$desktop = [Environment]::GetFolderPath('Desktop')
if (-not $desktop -or -not (Test-Path $desktop)) {
    $desktop = $env:USERPROFILE
    Write-Warn2 "Desktop not resolvable. Using $desktop instead."
}
$cerPath = Join-Path $desktop 'QuarantineAgentPOC.cer'
$cert | Export-Certificate -FilePath $cerPath | Out-Null
Write-Ok $cerPath
Write-Info 'Public key only. The private key stays in your certificate store.'

Write-Step 'Send to the tenant administrator'
Write-Host ''
Write-Host "  File       : $cerPath"
Write-Host "  Thumbprint : $($cert.Thumbprint)"
Write-Host ''
Write-Info 'Ask them to upload the .cer to the app registration, then run 02-Test-Connection.ps1'
