<#
    STEP 11 - Connect to Graph and find out how Insider Risk alerts are actually
    identified in this tenant.

    This exists because of a real gap. Microsoft's published serviceSource enum
    lists dataLossPrevention but has NO value for Insider Risk Management. The
    Defender portal filters by it, so the alerts are there - but how to select
    them through the API is undocumented.

    Rather than guess a filter value, this enumerates everything the identity can
    see and reports the distinct serviceSource, detectionSource, productName and
    category values present. Whatever carries the IRM alerts will be visible in
    that breakdown.

    Entirely read-only.
#>
[CmdletBinding()]
param(
    [int]$Days = 30,
    [int]$MaxAlerts = 500
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Common.ps1')

Write-Step 'Connecting to Microsoft Graph'
try {
    Connect-Irm
    Write-Ok 'Connected.'
}
catch {
    Write-Bad $_.Exception.Message
    Write-Host ''
    Write-Info 'Common causes:'
    Write-Info '  IrmAppId blank            -> add the client ID to config.ps1'
    Write-Info '  certificate not found     -> run 10-New-IrmCertificate.ps1'
    Write-Info '  AADSTS700027 / cert error -> CNG certificate; re-run 10 with -Force'
    Write-Info '  Insufficient privileges   -> SecurityAlert.ReadWrite.All not consented'
    Write-Info '  just uploaded the cert?   -> wait a few minutes and retry'
    return
}

$ctx = Get-MgContext
Write-Info "Tenant : $($ctx.TenantId)"
Write-Info "App    : $($ctx.ClientId)"
Write-Info "Scopes : $($ctx.Scopes -join ', ')"

$since = (Get-Date).ToUniversalTime().AddDays(-$Days).ToString('yyyy-MM-ddTHH:mm:ssZ')
$filter = [uri]::EscapeDataString("createdDateTime ge $since")
$uri = '{0}/security/alerts_v2?$filter={1}&$top=100' -f 'https://graph.microsoft.com/v1.0', $filter

Write-Step "Reading alerts from the last $Days days"
try {
    $alerts = @(Invoke-GraphGet -Uri $uri -MaxItems $MaxAlerts)
    Write-Ok "$($alerts.Count) alert(s) returned."
}
catch {
    Write-Bad $_.Exception.Message
    Write-Info 'A 403 here means the permission is granted but not admin-consented,'
    Write-Info 'or consent has not propagated yet.'
    return
}

if ($alerts.Count -eq 0) {
    Write-Warn2 'No alerts at all in the window.'
    Write-Info 'Either nothing has fired, or this identity cannot see them.'
    Write-Info 'Compare against the Defender portal alert queue before concluding.'
    return
}

function Show-Breakdown {
    param([string]$Field)
    Write-Step "Distinct $Field values"
    $groups = $alerts | ForEach-Object { Get-Prop $_ $Field } |
              Where-Object { $_ } | Group-Object | Sort-Object Count -Descending
    if (-not $groups) { Write-Warn2 "No $Field values present."; return }
    foreach ($g in $groups) { Write-Host ("  {0,-42} {1}" -f $g.Name, $g.Count) }
}

Show-Breakdown 'serviceSource'
Show-Breakdown 'detectionSource'
Show-Breakdown 'productName'

Write-Step 'Candidates that look like Insider Risk'
$needle = 'insider|irm|risk'
$cand = $alerts | Where-Object {
    (("$(Get-Prop $_ 'serviceSource') $(Get-Prop $_ 'detectionSource') " +
      "$(Get-Prop $_ 'productName') $(Get-Prop $_ 'category') $(Get-Prop $_ 'title')") -match $needle)
}

if ($cand) {
    Write-Ok "$(@($cand).Count) alert(s) matched."
    $cand | Select-Object -First 10 |
        Select-Object @{n='serviceSource';e={Get-Prop $_ 'serviceSource'}},
                      @{n='detectionSource';e={Get-Prop $_ 'detectionSource'}},
                      @{n='title';e={Get-Prop $_ 'title'}},
                      @{n='status';e={Get-Prop $_ 'status'}} |
        Format-Table -AutoSize -Wrap | Out-String | Write-Host
    Write-Info 'Use the serviceSource value shown above as the filter in 12-Get-IrmAlerts.ps1.'
}
else {
    Write-Warn2 'Nothing matched on name. Either no IRM alerts exist in the window,'
    Write-Warn2 'or they are identified by something not covered by these fields.'
    Write-Info  'The full dump below will show what is actually present.'
}

Write-Step 'Saving a full dump for inspection'
$out = Initialize-OutDir
$path = Join-Path $out ("alert-sources-{0}.json" -f (Get-Date -Format 'yyyyMMdd-HHmmss'))
$alerts | Select-Object -First 50 | ConvertTo-Json -Depth 8 | Set-Content -Path $path -Encoding UTF8
Write-Ok $path
Write-Info 'Contains real alert data. out\ is gitignored - keep it local.'
