<#
    STEP 15 - Find one specific alert without sweeping the whole tenant.

    Sweeping does not scale here. This tenant produces roughly 7,000 alerts a
    day, alerts_v2 returns at most 100 per query with no continuation link, and
    insider risk alerts cannot be filtered server-side because their
    serviceSource is reported as unknownFutureValue. 400 requests buys about a
    day and a half of history.

    So instead of scanning, this tries to make the service do the work.

    Insider risk alert ids follow a pattern: 'ir' then the short code shown in
    the alert title, then a GUID. For example the alert titled

        Purview IRM ('fcb44e69') Adaptive Protection policy for ...

    has id irfcb44e69-4224-4144-81e8-74e5acab07e9. So a short code is the start
    of an id, and if the service supports startswith() on id, one request finds
    the alert.

    Whether it does is undocumented, so this tries each approach in turn and
    reports which ones the service actually accepts. That result is worth
    recording either way: it determines whether a production integration can
    look up an alert directly or has to be handed ids from elsewhere.

    Falls back to a narrow date-window sweep when a date is known, which is
    tractable where a full sweep is not.

    Entirely read-only.

    Examples:
      .\15-Find-Alert.ps1 -Code "da9ffdde"
      .\15-Find-Alert.ps1 -Code "da9ffdde" -Date "2026-09-29" -HoursEitherSide 12
      .\15-Find-Alert.ps1 -Id "irfcb44e69-4224-4144-81e8-74e5acab07e9"
#>
[CmdletBinding()]
param(
    # The short code from the alert title, e.g. da9ffdde. No 'ir' prefix.
    [string]$Code,

    # A full alert id, if you have one - read it directly and skip the search.
    [string]$Id,

    # Known or suspected creation date, for the narrow-window fallback.
    [datetime]$Date,

    # Half-width of the fallback window.
    [int]$HoursEitherSide = 12,

    [int]$MaxCalls = 300
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Common.ps1')

if (-not $Code -and -not $Id) {
    Write-Bad 'Pass -Code (the short code in the alert title) or -Id (a full alert id).'
    return
}

Connect-Irm -Quiet
$base = 'https://graph.microsoft.com/v1.0/security/alerts_v2'

function Show-Alert {
    param($A)
    $A | Select-Object `
        @{n='Id';e={Get-Prop $_ 'id'}},
        @{n='Created';e={Get-Prop $_ 'createdDateTime'}},
        @{n='Status';e={Get-Prop $_ 'status'}},
        @{n='Severity';e={Get-Prop $_ 'severity'}},
        @{n='AssignedTo';e={Get-Prop $_ 'assignedTo'}},
        @{n='Classification';e={Get-Prop $_ 'classification'}},
        @{n='Determination';e={Get-Prop $_ 'determination'}},
        @{n='ServiceSource';e={Get-Prop $_ 'serviceSource'}},
        @{n='Title';e={Get-Prop $_ 'title'}} |
        Format-List | Out-String | Write-Host
}

# -------------------------------------------------------------- direct read
if ($Id) {
    Write-Step 'Reading the alert directly'
    try {
        $a = Invoke-MgGraphRequest -Method GET -Uri "$base/$Id" -OutputType PSObject -ErrorAction Stop
        Write-Ok 'Found.'
        Show-Alert $a
        Write-Info 'Dry-run an update against it - changes nothing:'
        Write-Info "  .\13-Update-IrmAlert.ps1 -Id `"$Id`" -AssignTo `"<upn>`" -NewStatus inProgress"
    }
    catch {
        Write-Bad $_.Exception.Message
        Write-Info 'A 404 means no alert with that id is visible to this identity.'
    }
    return
}

$guess = "ir$Code"
Write-Step "Looking for the alert behind code '$Code'"
Write-Info "Insider risk ids start with the code, so the id should begin '$guess'."

# ------------------------------------------------- server-side filter trials
Write-Step 'Trying server-side filters'
Write-Info 'Undocumented which of these alerts_v2 supports, so each is tried and'
Write-Info 'the outcome reported. Supported or not is itself a useful finding.'
Write-Host ''

$trials = @(
    @{ Name = "startswith(id,'$guess')";        Filter = "startswith(id,'$guess')" }
    @{ Name = "contains(title,'$Code')";        Filter = "contains(title,'$Code')" }
    @{ Name = "startswith(title,'Purview IRM')"; Filter = "startswith(title,'Purview IRM')" }
)

$found = $null
foreach ($t in $trials) {
    $uri = '{0}?$filter={1}&$top=50' -f $base, [uri]::EscapeDataString($t.Filter)
    try {
        $r = Invoke-MgGraphRequest -Method GET -Uri $uri -OutputType PSObject -ErrorAction Stop
        $items = @($r.value)
        Write-Host ('  {0,-34} SUPPORTED, {1} result(s)' -f $t.Name, $items.Count) -ForegroundColor Green
        if (-not $found) {
            $m = @($items | Where-Object { "$(Get-Prop $_ 'id')$(Get-Prop $_ 'title')" -match [regex]::Escape($Code) })
            if ($m.Count -gt 0) { $found = $m[0] }
        }
    }
    catch {
        $msg = "$($_.Exception.Message)"
        $short = if ($msg.Length -gt 60) { $msg.Substring(0, 60) + '...' } else { $msg }
        Write-Host ('  {0,-34} rejected: {1}' -f $t.Name, $short) -ForegroundColor DarkGray
    }
}

if ($found) {
    Write-Step 'Found it'
    Show-Alert $found
    $fid = Get-Prop $found 'id'
    Write-Info 'Dry-run an update against it - changes nothing:'
    Write-Info "  .\13-Update-IrmAlert.ps1 -Id `"$fid`" -AssignTo `"<upn>`" -NewStatus inProgress"
    return
}

Write-Host ''
Write-Warn2 'No server-side filter located it.'

# ------------------------------------------------------- narrow-window sweep
if (-not $PSBoundParameters.ContainsKey('Date')) {
    Write-Step 'Next step: supply a date'
    Write-Info 'A full sweep is not viable here - roughly 7,000 alerts a day means'
    Write-Info 'the request ceiling is reached after a day or so of history.'
    Write-Info ''
    Write-Info 'Ask whoever nominated the alert for its creation date, then:'
    Write-Info "  .\15-Find-Alert.ps1 -Code `"$Code`" -Date `"2026-09-29`""
    Write-Info ''
    Write-Info 'Better still, ask for the full alert id from the Defender portal URL:'
    Write-Info "  .\15-Find-Alert.ps1 -Id `"ir$Code-....`""
    return
}

$from = $Date.ToUniversalTime().AddHours(-$HoursEitherSide)
$to   = $Date.ToUniversalTime().AddHours( $HoursEitherSide)

Write-Step ("Sweeping {0:yyyy-MM-dd HH:mm} to {1:yyyy-MM-dd HH:mm} UTC" -f $from, $to)
Write-Info 'Narrow window, so this is tractable where a full sweep is not.'
Write-Host ''

$all = @(Get-AlertsSliced -From $from -To $to -MaxCalls $MaxCalls -ShowProgress)
Write-Host ''
Write-Ok "$($all.Count) alert(s) in the window."

$hits = @($all | Where-Object {
    ($_ | ConvertTo-Json -Depth 6 -Compress) -match [regex]::Escape($Code)
})

if ($hits.Count -gt 0) {
    Write-Step 'Found it'
    foreach ($h in $hits) { Show-Alert $h }
    $fid = Get-Prop $hits[0] 'id'
    Write-Info 'Dry-run an update against it - changes nothing:'
    Write-Info "  .\13-Update-IrmAlert.ps1 -Id `"$fid`" -AssignTo `"<upn>`" -NewStatus inProgress"
}
else {
    Write-Step 'Not in this window'
    if ($script:SweepTruncated) {
        Write-Bad 'The window sweep was truncated, so this is inconclusive.'
        Write-Info 'Narrow -HoursEitherSide, or raise -MaxCalls.'
    }
    else {
        Write-Warn2 "Window covered completely - '$Code' is genuinely not in it."
        Write-Info 'Widen with -HoursEitherSide, or check the date.'
    }

    $irm = @($all | Where-Object { "$(Get-Prop $_ 'title')" -match 'Purview IRM|Insider Risk' })
    if ($irm.Count -gt 0) {
        Write-Step "Insider risk alerts that ARE in this window ($($irm.Count))"
        $irm | Select-Object -First 20 `
            @{n='Created';e={Get-Prop $_ 'createdDateTime'}},
            @{n='Status';e={Get-Prop $_ 'status'}},
            @{n='Id';e={Get-Prop $_ 'id'}} |
            Format-Table -AutoSize | Out-String | Write-Host
        Write-Info 'If the one you want is here under a different code, use its id.'
    }
}
