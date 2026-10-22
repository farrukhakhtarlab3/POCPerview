<#
    STEP 12 - List Insider Risk alerts.

    Run 11-Discover-AlertSources.ps1 first to find out what serviceSource value
    this tenant actually uses, then pass it here. The default is a guess and may
    well be wrong - Microsoft does not publish one for Insider Risk.

    Read-only. Writes a CSV to out\.
#>
[CmdletBinding()]
param(
    # From step 11. Leave blank to pull everything and filter by name instead.
    [string]$ServiceSource,

    [int]$Days = 30,
    [int]$MaxAlerts = 500,

    [ValidateSet('new','inProgress','resolved')]
    [string]$Status
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Common.ps1')

Connect-Irm -Quiet

$since = (Get-Date).ToUniversalTime().AddDays(-$Days).ToString('yyyy-MM-ddTHH:mm:ssZ')
$parts = @("createdDateTime ge $since")
if ($ServiceSource) { $parts += "serviceSource eq '$ServiceSource'" }
if ($Status)        { $parts += "status eq '$Status'" }

$filter = [uri]::EscapeDataString(($parts -join ' and '))
$uri = '{0}/security/alerts_v2?$filter={1}&$top=100' -f 'https://graph.microsoft.com/v1.0', $filter

Write-Step ("Reading alerts" + $(if($ServiceSource){" - serviceSource '$ServiceSource'"}else{" - all sources"}))
try {
    $alerts = @(Invoke-GraphGet -Uri $uri -MaxItems $MaxAlerts)
}
catch {
    Write-Bad $_.Exception.Message
    if ($ServiceSource) {
        Write-Info "If this is an invalid-filter error, '$ServiceSource' is not a valid"
        Write-Info 'serviceSource value. Run 11-Discover-AlertSources.ps1 to see the real ones.'
    }
    return
}

# Without a server-side filter, narrow by name locally.
if (-not $ServiceSource) {
    $alerts = @($alerts | Where-Object {
        (("$(Get-Prop $_ 'serviceSource') $(Get-Prop $_ 'detectionSource') " +
          "$(Get-Prop $_ 'productName') $(Get-Prop $_ 'category')") -match 'insider|irm|risk')
    })
    Write-Info 'No -ServiceSource given, so results were filtered locally by name.'
}

Write-Ok "$($alerts.Count) alert(s)."
if ($alerts.Count -eq 0) {
    Write-Warn2 'Nothing matched. Run 11-Discover-AlertSources.ps1 to see what is present.'
    return
}

$view = $alerts | ForEach-Object {
    [pscustomobject]@{
        Created    = Get-Prop $_ 'createdDateTime'
        Severity   = Get-Prop $_ 'severity'
        Status     = Get-Prop $_ 'status'
        AssignedTo = Get-Prop $_ 'assignedTo'
        Title      = Get-Prop $_ 'title'
        Source     = Get-Prop $_ 'serviceSource'
        Id         = Get-Prop $_ 'id'
    }
} | Sort-Object Created -Descending

Write-Step 'Alerts'
$view | Select-Object -First 25 | Format-Table -AutoSize -Wrap | Out-String | Write-Host

Write-Step 'By status'
$view | Group-Object Status | ForEach-Object { Write-Host ("  {0,-14} {1}" -f $_.Name, $_.Count) }

$out = Initialize-OutDir
$csv = Join-Path $out ("irm-alerts-{0}.csv" -f (Get-Date -Format 'yyyyMMdd-HHmmss'))
$view | Export-Csv -Path $csv -NoTypeInformation -Encoding UTF8
Write-Ok "Written to $csv"
Write-Info 'Contains real alert data. out\ is gitignored.'

Write-Step 'Next'
Write-Info 'Copy an Id, then:'
Write-Info '  .\13-Update-IrmAlert.ps1 -Id "<id>" -AssignTo "analyst@domain" -NewStatus inProgress'
