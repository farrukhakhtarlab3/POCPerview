<#
    STEP 14 - Diagnostic. How far back can we actually see, and is a specific
    alert visible at all?

    Written because 12-Get-IrmAlerts.ps1 returned 7 alerts over 30 days but ZERO
    over 180 - a wider window returning fewer results, which should be
    impossible. Something other than the IRM name filter is at work.

    Three things it checks:

      1. Window probe   - query several date windows and count what comes back.
                          If the wide ones return zero, alerts_v2 is silently
                          refusing to look that far back rather than erroring.

      2. No-filter probe - ask for alerts with no date filter at all, to see
                          what the service returns by default.

      3. -Find <text>   - pull everything visible and search every field for a
                          string. Use this to answer "does this alert exist in
                          Defender at all", rather than inferring from a filter
                          that might be the problem itself.

    Entirely read-only. Changes nothing.

    Examples:
      .\14-Probe-AlertWindow.ps1
      .\14-Probe-AlertWindow.ps1 -Find "da9ffdde"
#>
[CmdletBinding()]
param(
    # Substring to hunt for across every field of every visible alert.
    [string]$Find,

    # Cap for the -Find sweep. Raise if the tenant is busy.
    [int]$MaxAlerts = 2000
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Common.ps1')

Connect-Irm -Quiet
$base = 'https://graph.microsoft.com/v1.0/security/alerts_v2'

$ctx = Get-MgContext
Write-Step 'Identity'
Write-Info "Tenant : $($ctx.TenantId)"
Write-Info "App    : $($ctx.ClientId)"

# --------------------------------------------------------------- 1. windows
Write-Step 'Window probe'
Write-Info 'Each row asks for up to 100 alerts created since N days ago.'
Write-Host ''
Write-Host ('  {0,6}  {1,8}  {2}' -f 'Days', 'Returned', 'Oldest / note')
Write-Host ('  {0,6}  {1,8}  {2}' -f '------', '--------', '-------------')

foreach ($d in 7, 14, 30, 45, 60, 90, 180, 365) {
    $since = (Get-Date).ToUniversalTime().AddDays(-$d).ToString('yyyy-MM-ddTHH:mm:ssZ')
    $f = [uri]::EscapeDataString("createdDateTime ge $since")
    $uri = '{0}?$filter={1}&$top=100' -f $base, $f
    try {
        $r = Invoke-MgGraphRequest -Method GET -Uri $uri -OutputType PSObject -ErrorAction Stop
        $items = @($r.value)
        $note = ''
        if ($items.Count -gt 0) {
            $dates = $items | ForEach-Object { Get-Prop $_ 'createdDateTime' } | Where-Object { $_ } | Sort-Object
            if ($dates) { $note = "oldest $($dates[0])" }
        }
        else { $note = 'EMPTY' }
        $colour = if ($items.Count -eq 0) { 'Yellow' } else { 'Gray' }
        Write-Host ('  {0,6}  {1,8}  {2}' -f $d, $items.Count, $note) -ForegroundColor $colour
    }
    catch {
        Write-Host ('  {0,6}  {1,8}  {2}' -f $d, 'ERROR', $_.Exception.Message) -ForegroundColor Red
    }
}

Write-Host ''
Write-Info 'If the wide windows return 0 while narrow ones return results, the'
Write-Info 'service is refusing to look that far back and reporting it as an'
Write-Info 'empty set rather than an error. That is a finding worth recording -'
Write-Info 'it silently caps how much history an agent can reason over.'

# ------------------------------------------------------------- 2. no filter
Write-Step 'No date filter'
try {
    $r = Invoke-MgGraphRequest -Method GET -Uri ('{0}?$top=100' -f $base) -OutputType PSObject -ErrorAction Stop
    $items = @($r.value)
    Write-Ok "$($items.Count) returned with no filter at all."
    if ($items.Count -gt 0) {
        $dates = $items | ForEach-Object { Get-Prop $_ 'createdDateTime' } | Where-Object { $_ } | Sort-Object
        Write-Info "Oldest : $($dates[0])"
        Write-Info "Newest : $($dates[-1])"
    }
}
catch { Write-Bad $_.Exception.Message }

# ------------------------------------------------------------------ 3. find
if ($Find) {
    Write-Step "Searching every visible alert for '$Find'"
    Write-Info "Pulling up to $MaxAlerts alerts with no date filter, then matching"
    Write-Info 'against the whole record - title, id, policy fields, everything.'

    try {
        $all = @(Invoke-GraphGet -Uri ('{0}?$top=100' -f $base) -MaxItems $MaxAlerts)
    }
    catch {
        Write-Bad $_.Exception.Message
        return
    }
    Write-Ok "$($all.Count) alert(s) pulled."

    $hits = @($all | Where-Object {
        ($_ | ConvertTo-Json -Depth 6 -Compress) -match [regex]::Escape($Find)
    })

    if ($hits.Count -eq 0) {
        Write-Host ''
        Write-Bad "'$Find' does not appear in any alert this identity can see."
        Write-Info ''
        Write-Info 'That is a result, not a failure. It means the alert exists in'
        Write-Info 'Purview but has not reached Defender XDR. Most likely cause is'
        Write-Info 'the IRM data sharing setting - "Share user risk details with'
        Write-Info 'other security solutions" - being off, or the alert predating'
        Write-Info 'whatever history the service will return.'
        Write-Info ''
        Write-Info 'Worth asking whoever nominated it to confirm they can see it in'
        Write-Info 'the Defender portal themselves.'
    }
    else {
        Write-Ok "$($hits.Count) match(es)."
        Write-Host ''
        $hits | Select-Object `
            @{n='Id';e={Get-Prop $_ 'id'}},
            @{n='Created';e={Get-Prop $_ 'createdDateTime'}},
            @{n='Status';e={Get-Prop $_ 'status'}},
            @{n='AssignedTo';e={Get-Prop $_ 'assignedTo'}},
            @{n='Classification';e={Get-Prop $_ 'classification'}},
            @{n='Title';e={Get-Prop $_ 'title'}} |
            Format-List | Out-String | Write-Host

        Write-Info 'Copy the Id, then dry-run the update (changes nothing):'
        Write-Info '  .\13-Update-IrmAlert.ps1 -Id "<id>" -AssignTo "<upn>" -NewStatus inProgress'
    }
}
else {
    Write-Step 'Looking for a specific alert?'
    Write-Info 'Re-run with -Find to search every field of every visible alert:'
    Write-Info '  .\14-Probe-AlertWindow.ps1 -Find "da9ffdde"'
}

# --------------------------------------------------------------- what we saw
Write-Step 'Service source values present'
try {
    $sample = @(Invoke-GraphGet -Uri ('{0}?$top=100' -f $base) -MaxItems 500)
    $sample | ForEach-Object { Get-Prop $_ 'serviceSource' } | Where-Object { $_ } |
        Group-Object | Sort-Object Count -Descending |
        ForEach-Object { Write-Host ('  {0,-34} {1}' -f $_.Name, $_.Count) }
    Write-Host ''
    Write-Info 'Insider Risk alerts report serviceSource as unknownFutureValue -'
    Write-Info 'Graph has no enum value for them yet. That means they cannot be'
    Write-Info 'filtered server-side, and that any code matching on that value will'
    Write-Info 'break the day Microsoft assigns a real one.'
}
catch { Write-Warn2 $_.Exception.Message }
