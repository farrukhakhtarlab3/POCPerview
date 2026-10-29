<#
    STEP 14 - Diagnostic. What can this identity actually see, and is a given
    alert present at all?

    Written after 12-Get-IrmAlerts.ps1 returned 7 alerts over 30 days and zero
    over 180. A wider window returning fewer results is impossible unless the
    retrieval itself is at fault, and it was: alerts_v2 caps at 100 records,
    returns no continuation link to follow, and orders results OLDEST FIRST.
    One query over a wide window therefore returns old records and hides
    everything newer, with no error to notice.

    What this does:

      1. Window probe  - query several date windows and show the OLDEST record
                         each returns. Every row showing exactly 100 is the cap,
                         not the answer.

      2. Raw shape     - print the top-level properties of a response, to show
                         whether a continuation link is present at all.

      3. -Find <text>  - sweep the range in time slices, splitting any slice
                         that comes back full, then search every field of every
                         alert found. The only form that can give a trustworthy
                         "not present" answer.

    Entirely read-only.

    Examples:
      .\14-Probe-AlertWindow.ps1
      .\14-Probe-AlertWindow.ps1 -Find "da9ffdde"
      .\14-Probe-AlertWindow.ps1 -Find "da9ffdde" -Days 365
#>
[CmdletBinding()]
param(
    # Substring to hunt for across every field of every alert found.
    [string]$Find,

    # How far back the -Find sweep reaches.
    [int]$Days = 180,

    # Ceiling on requests during the sweep. Raise for a busy tenant.
    [int]$MaxCalls = 400
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
        $note = 'EMPTY'
        if ($items.Count -gt 0) {
            $dates = $items | ForEach-Object { Get-Prop $_ 'createdDateTime' } | Where-Object { $_ } | Sort-Object
            if ($dates) { $note = "oldest $($dates[0])" }
        }
        Write-Host ('  {0,6}  {1,8}  {2}' -f $d, $items.Count, $note) -ForegroundColor Gray
    }
    catch {
        Write-Host ('  {0,6}  {1,8}  {2}' -f $d, 'ERROR', $_.Exception.Message) -ForegroundColor Red
    }
}

Write-Host ''
Write-Info 'Read the Oldest column, not the count. Every row showing exactly 100'
Write-Info 'is the page cap. The dates then show results arrive OLDEST FIRST, so'
Write-Info 'a capped query silently drops the most RECENT alerts - the opposite'
Write-Info 'of what almost any caller expects.'

# ------------------------------------------------------------- 2. raw shape
Write-Step 'Response shape'
Write-Info 'Top-level properties of one response. If no continuation link appears'
Write-Info 'here, there is nothing to page with and slicing is the only option.'
try {
    $r = Invoke-MgGraphRequest -Method GET -Uri ('{0}?$top=5' -f $base) -OutputType PSObject -ErrorAction Stop
    $names = @()
    if ($r -is [System.Collections.IDictionary]) { $names = @($r.Keys | ForEach-Object { "$_" }) }
    else { $names = @($r.PSObject.Properties | ForEach-Object { $_.Name }) }
    foreach ($n in $names) { Write-Host "    $n" }
    if (-not ($names | Where-Object { $_ -like '*nextLink*' })) {
        Write-Host ''
        Write-Warn2 'No continuation link present. Confirms the cap cannot be paged past.'
    }
}
catch { Write-Bad $_.Exception.Message }

# ------------------------------------------------------------------ 3. find
if ($Find) {
    Write-Step "Sweeping $Days days in slices"
    Write-Info 'Splitting any slice that comes back full, so nothing hides behind'
    Write-Info 'the 100-record cap. One request per slice, so this takes a moment.'
    Write-Host ''

    try {
        $all = @(Get-AlertsSliced -Days $Days -MaxCalls $MaxCalls -ShowProgress)
    }
    catch {
        Write-Bad $_.Exception.Message
        return
    }

    Write-Host ''
    Write-Ok "$($all.Count) distinct alert(s) found."

    if ($all.Count -gt 0) {
        $dates = $all | ForEach-Object { Get-Prop $_ 'createdDateTime' } | Where-Object { $_ } | Sort-Object
        Write-Info "Oldest : $($dates[0])"
        Write-Info "Newest : $($dates[-1])"
    }

    Write-Step "Searching for '$Find'"
    $hits = @($all | Where-Object {
        ($_ | ConvertTo-Json -Depth 6 -Compress) -match [regex]::Escape($Find)
    })

    if ($hits.Count -eq 0) {
        Write-Host ''
        Write-Bad "'$Find' is not in any of the $($all.Count) alert(s) swept."
        Write-Info ''
        Write-Info 'This sweep splits slices that fill up, so unlike a single capped'
        Write-Info 'query it does cover the range. Treat it as a real answer, with'
        Write-Info "the one caveat that it only looked back $Days days."
        Write-Info ''
        Write-Info 'Most likely meaning: the alert is in Purview but has not reached'
        Write-Info 'Defender XDR. The usual cause is the IRM data sharing setting,'
        Write-Info '"Share user risk details with other security solutions", being'
        Write-Info 'off - without it insider risk alerts never cross over.'
        Write-Info ''
        Write-Info 'Worth asking whoever nominated the alert to confirm they can see'
        Write-Info 'it in the Defender portal themselves. That separates a tenant'
        Write-Info 'configuration gap from anything to do with these scripts.'
        Write-Info ''
        Write-Info 'Try a wider window first, with -Days 365.'
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
            @{n='ServiceSource';e={Get-Prop $_ 'serviceSource'}},
            @{n='Title';e={Get-Prop $_ 'title'}} |
            Format-List | Out-String | Write-Host

        Write-Info 'Copy the Id, then dry-run the update - changes nothing:'
        Write-Info '  .\13-Update-IrmAlert.ps1 -Id "<id>" -AssignTo "<upn>" -NewStatus inProgress'
    }

    # ------------------------------------------------- what the sweep saw
    Write-Step 'Service source values across the sweep'
    $all | ForEach-Object { Get-Prop $_ 'serviceSource' } | Where-Object { $_ } |
        Group-Object | Sort-Object Count -Descending |
        ForEach-Object { Write-Host ('  {0,-34} {1}' -f $_.Name, $_.Count) }

    Write-Step 'Insider risk alerts found'
    $irm = @($all | Where-Object {
        "$(Get-Prop $_ 'title')" -match 'Insider Risk|Purview IRM'
    })
    Write-Ok "$($irm.Count) alert(s) look like Insider Risk by title."
    if ($irm.Count -gt 0) {
        $irm | Sort-Object { Get-Prop $_ 'createdDateTime' } -Descending |
            Select-Object -First 25 `
                @{n='Created';e={Get-Prop $_ 'createdDateTime'}},
                @{n='Status';e={Get-Prop $_ 'status'}},
                @{n='Title';e={Get-Prop $_ 'title'}},
                @{n='Id';e={Get-Prop $_ 'id'}} |
            Format-Table -AutoSize -Wrap | Out-String | Write-Host
    }

    $out = Initialize-OutDir
    $path = Join-Path $out ("alert-sweep-{0}.csv" -f (Get-Date -Format 'yyyyMMdd-HHmmss'))
    $all | Select-Object `
        @{n='Created';e={Get-Prop $_ 'createdDateTime'}},
        @{n='Severity';e={Get-Prop $_ 'severity'}},
        @{n='Status';e={Get-Prop $_ 'status'}},
        @{n='AssignedTo';e={Get-Prop $_ 'assignedTo'}},
        @{n='ServiceSource';e={Get-Prop $_ 'serviceSource'}},
        @{n='Title';e={Get-Prop $_ 'title'}},
        @{n='Id';e={Get-Prop $_ 'id'}} |
        Export-Csv -Path $path -NoTypeInformation -Encoding UTF8
    Write-Step 'Saved'
    Write-Ok $path
    Write-Info 'Real alert data. out\ is gitignored - keep it local.'
}
else {
    Write-Step 'Looking for a specific alert?'
    Write-Info 'Re-run with -Find to sweep the whole range and search every field:'
    Write-Info '  .\14-Probe-AlertWindow.ps1 -Find "da9ffdde"'
}
