<#
    STEP 13 - Assign an alert to someone and change its status.

    This is the IRM equivalent of the quarantine release test: proving the
    application identity can WRITE, not just read.

    Much lower risk than releasing a message. Nothing is sent and nothing leaves
    the tenant - these are fields on the alert record. But it is still a change
    in a production system, so it is gated behind -Execute.

    Note the status models differ between portals. Defender's new and inProgress
    both show as "Needs review" in Purview. Resolved maps by classification, and
    without one it defaults to Dismissed. Changes sync both ways within about
    30 minutes.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$Id,

    # UPN of the reviewer. Pass an empty string to clear the assignment.
    [string]$AssignTo,

    [ValidateSet('new','inProgress','resolved')]
    [string]$NewStatus,

    [ValidateSet('unknown','falsePositive','truePositive','informationalExpectedActivity')]
    [string]$Classification,

    [switch]$Execute
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Common.ps1')

if (-not $AssignTo -and -not $NewStatus -and -not $Classification) {
    Write-Bad 'Nothing to change. Pass -AssignTo, -NewStatus and/or -Classification.'
    return
}

Connect-Irm -Quiet
$base = 'https://graph.microsoft.com/v1.0/security/alerts_v2'

Write-Step 'Current state'
try {
    $a = Invoke-MgGraphRequest -Method GET -Uri "$base/$Id" -OutputType PSObject -ErrorAction Stop
}
catch {
    Write-Bad $_.Exception.Message
    Write-Info 'Check the Id matches one from 12-Get-IrmAlerts.ps1.'
    return
}

$before = [ordered]@{
    Title          = Get-Prop $a 'title'
    Status         = Get-Prop $a 'status'
    AssignedTo     = Get-Prop $a 'assignedTo'
    Classification = Get-Prop $a 'classification'
    Severity       = Get-Prop $a 'severity'
    ServiceSource  = Get-Prop $a 'serviceSource'
}
foreach ($k in $before.Keys) { Write-Info ("{0,-15}: {1}" -f $k, $before[$k]) }

$body = @{}
if ($PSBoundParameters.ContainsKey('AssignTo')) { $body['assignedTo']     = $AssignTo }
if ($NewStatus)                                 { $body['status']         = $NewStatus }
if ($Classification)                            { $body['classification'] = $Classification }

Write-Step 'Proposed change'
foreach ($k in $body.Keys) {
    $old = $before[($k -replace 'assignedTo','AssignedTo' -replace 'status','Status' -replace 'classification','Classification')]
    Write-Host ("  {0,-15}: {1}  ->  {2}" -f $k, $old, $body[$k])
}

if (-not $Execute) {
    Write-Step 'DRY RUN - nothing changed'
    Write-Info 'Re-run with -Execute to apply.'
    return
}

Write-Step 'Applying'
$result = [ordered]@{
    Id = $Id; Before = $before; Change = $body
    AttemptAt = (Get-Date).ToString('u'); Outcome = $null; Error = $null
}

try {
    Invoke-MgGraphRequest -Method PATCH -Uri "$base/$Id" `
        -Body ($body | ConvertTo-Json -Depth 5) `
        -ContentType 'application/json' -ErrorAction Stop | Out-Null
    $result.Outcome = 'SUCCESS'
    Write-Ok 'Update accepted.'
}
catch {
    $result.Outcome = 'FAILED'
    $result.Error = $_.Exception.Message
    Write-Bad $_.Exception.Message

    if ("$($_.Exception.Message)" -match '403|Forbidden|Authorization') {
        Write-Host ''
        Write-Info 'This is the EXPECTED result with the current grant.'
        Write-Info ''
        Write-Info 'The app holds SecurityAlert.Read.All, not ReadWrite. Write access was'
        Write-Info 'deliberately withheld: there is no Purview-native API for modifying IRM'
        Write-Info 'alerts, so the only write path is Defender XDR alerts_v2 - which syncs'
        Write-Info 'back to Purview but also writes into the Defender incident queue used'
        Write-Info 'by the Cyber Defence Centre.'
        Write-Info ''
        Write-Info 'That answers the HLD spike "Test whether any supported interface can'
        Write-Info 'update the IRM alert/case; document fallback if not."'
        Write-Info ''
        Write-Info 'Fallback, per the HLD: do not write back. Record the recommendation and'
        Write-Info 'the analyst decision in the case store, and link back to Purview so the'
        Write-Info 'analyst applies it there.'
    }
}

if ($result.Outcome -eq 'SUCCESS') {
    Write-Step 'Verifying'
    Start-Sleep -Seconds 3
    try {
        $after = Invoke-MgGraphRequest -Method GET -Uri "$base/$Id" -OutputType PSObject -ErrorAction Stop
        $ok = $true
        foreach ($k in $body.Keys) {
            $now = Get-Prop $after $k
            if ("$now" -eq "$($body[$k])") { Write-Ok ("{0} = {1}" -f $k, $now) }
            else { Write-Bad ("{0} is '{1}', expected '{2}'" -f $k, $now, $body[$k]); $ok = $false }
        }
        if ($ok) {
            Write-Host ''
            Write-Host '  Write-back under the application identity confirmed.' -ForegroundColor Green
            Write-Info 'Allow up to 30 minutes before it appears in the Purview portal.'
        }
    }
    catch { Write-Warn2 "Could not re-read: $($_.Exception.Message)" }
}

$out = Initialize-OutDir
$log = Join-Path $out ("irm-update-{0}.json" -f (Get-Date -Format 'yyyyMMdd-HHmmss'))
$result | ConvertTo-Json -Depth 6 | Set-Content -Path $log -Encoding UTF8
Write-Step 'Logged'
Write-Ok $log
