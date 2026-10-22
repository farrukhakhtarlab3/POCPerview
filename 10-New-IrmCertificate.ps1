<#
    STEP 10 - Certificate for the IRM application registration.

    A SEPARATE certificate from the quarantine one, because IRM uses a separate
    app registration. Run this once, send the .cer to the tenant admin, and wait
    for them to upload it.

    Same CSP-not-CNG constraint applies.
#>
[CmdletBinding()]
param([switch]$Force, [int]$ValidYears = 1)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Common.ps1')

Write-Step 'Checking for an existing IRM certificate'
$existing = @(Get-ChildItem Cert:\CurrentUser\My |
    Where-Object { $_.Subject -eq $script:IrmCertSubject } |
    Sort-Object NotBefore -Descending)

if ($existing.Count -gt 0 -and -not $Force) {
    Write-Ok "Found $($existing.Count) already."
    foreach ($c in $existing) { Write-Info "Thumbprint : $($c.Thumbprint)   expires $($c.NotAfter)" }
    Write-Warn2 'Not creating another. Only the uploaded one authenticates.'
    return
}

if ($Force -and $existing.Count -gt 0) {
    Write-Warn2 "Removing $($existing.Count) existing certificate(s)."
    $existing | Remove-Item
}

Write-Step 'Creating certificate'
# -KeySpec KeyExchange forces a CSP provider. CNG is the Windows default and is
# not supported for this style of app-only authentication.
$cert = New-SelfSignedCertificate `
    -Subject $script:IrmCertSubject `
    -CertStoreLocation 'Cert:\CurrentUser\My' `
    -KeySpec KeyExchange `
    -NotAfter (Get-Date).AddYears($ValidYears)

Write-Ok "Created. Thumbprint: $($cert.Thumbprint)"

Write-Step 'Verifying CSP'
if ($cert.PrivateKey) { Write-Ok 'CSP confirmed.' }
else { Write-Bad 'CNG key - will not authenticate. Delete and re-run with -Force.'; return }

Write-Step 'Exporting public key'
$desktop = [Environment]::GetFolderPath('Desktop')
if (-not $desktop -or -not (Test-Path $desktop)) { $desktop = $env:USERPROFILE }
$cerPath = Join-Path $desktop 'IrmAgentPOC.cer'
$cert | Export-Certificate -FilePath $cerPath | Out-Null
Write-Ok $cerPath

Write-Step 'Send to the tenant admin'
Write-Host ''
Write-Host "  File       : $cerPath"
Write-Host "  Thumbprint : $($cert.Thumbprint)"
Write-Host ''
Write-Info 'Ask them to upload it to the IRM app registration, and to confirm'
Write-Info 'Microsoft Graph -> SecurityAlert.ReadWrite.All is granted with admin consent.'
Write-Info 'Then put the client ID into config.ps1 as $script:IrmAppId.'
