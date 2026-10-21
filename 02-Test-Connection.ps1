<#
    STEP 2 - Prove app-only authentication works, and that the custom role
    group actually attached.

    Read-only. Changes nothing. Safe to re-run as often as you like.
#>
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Common.ps1')

Write-Step 'Connecting as the application'
try {
    Connect-Quarantine
    Write-Ok 'Connected.'
}
catch {
    Write-Bad $_.Exception.Message
    Write-Host ''
    Write-Info 'Common causes:'
    Write-Info '  certificate / AADSTS700027  -> CNG certificate. Re-run 01 with -Force'
    Write-Info '  AADSTS90002 tenant not found -> wrong domain. Must be .onmicrosoft.com'
    Write-Info '  AADSTS700016 app not found   -> wrong AppId in config.ps1'
    Write-Info '  Insufficient privileges      -> admin consent not granted on Exchange.ManageAsApp'
    Write-Info '  just uploaded the cert?      -> wait a few minutes and retry'
    return
}

Write-Step 'Checking the role group attached'
try {
    $org = Get-OrganizationConfig -ErrorAction Stop
    Write-Ok "Role is working. Tenant: $($org.Name)"
}
catch {
    Write-Warn2 "Get-OrganizationConfig failed: $($_.Exception.Message)"
    Write-Info 'Expected if the custom role group is scoped to quarantine cmdlets only -'
    Write-Info 'that is correct least-privilege behaviour, not a fault. Checking directly.'
}

Write-Step 'Checking the quarantine cmdlets we were granted'
$needed = @(
    'Get-QuarantineMessage',
    'Get-QuarantineMessageHeader',
    'Preview-QuarantineMessage',
    'Export-QuarantineMessage',
    'Release-QuarantineMessage'
)
$missing = @()
foreach ($c in $needed) {
    if (Get-Command $c -ErrorAction SilentlyContinue) { Write-Ok $c }
    else { Write-Bad "$c  - NOT available"; $missing += $c }
}

# Should NOT be present - we explicitly asked for it to be excluded.
if (Get-Command 'Delete-QuarantineMessage' -ErrorAction SilentlyContinue) {
    Write-Warn2 'Delete-QuarantineMessage is available but was not requested.'
    Write-Info  'Worth mentioning to the tenant admin - we asked for it to be left out.'
}
else {
    Write-Ok 'Delete-QuarantineMessage correctly absent.'
}

Write-Step 'Result'
if ($missing.Count -eq 0) {
    Write-Ok 'All required cmdlets available. Proceed to 03-Get-QuarantineMessages.ps1'
}
else {
    Write-Bad "$($missing.Count) cmdlet(s) missing: $($missing -join ', ')"
    Write-Info 'The role group needs those added before the triage logic can work.'
}
