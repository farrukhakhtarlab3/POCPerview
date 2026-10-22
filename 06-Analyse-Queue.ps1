<#
    STEP 6 - Profile the whole quarantine queue.

    Answers several validation items from the HLD at once, using access you
    already have:

      "Target DLP items are filterable"
          -> Inspect actual PolicyTypes, QuarantineTypes and policy names.
      "Required content is retrievable"
          -> Measure how often TNEF encapsulation blocks attachment inspection.
      Scope and sizing
          -> Volume per day, sender and recipient-domain spread, release history.

    Read-only. Exports nothing unless -Deep is used, which samples message
    bodies to measure TNEF prevalence.
#>
[CmdletBinding()]
param(
    [int]$Days = 16,

    # Export a sample of messages to measure TNEF prevalence. Slower, and pulls
    # real content into memory (not written to disk).
    [switch]$Deep,
    [int]$SampleSize = 20
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Common.ps1')

Connect-Quarantine -Quiet
$out = Initialize-OutDir
$start = (Get-Date).AddDays(-$Days)
$end = Get-Date

Write-Step "Reading quarantine - last $Days days"
$all = @(Get-QuarantineMessage -StartReceivedDate $start -EndReceivedDate $end -PageSize 100)
Write-Ok "$($all.Count) message(s) visible to this identity"

if ($all.Count -eq 0) { Write-Warn2 'Nothing to profile.'; return }

function Show-Dist {
    param([string]$Title, [string]$Field, $Items, [int]$Top = 15)
    Write-Step $Title
    $g = $Items | ForEach-Object { Get-Prop $_ $Field } | Where-Object { $_ } |
         Group-Object | Sort-Object Count -Descending
    if (-not $g) { Write-Warn2 "No values."; return }
    foreach ($x in ($g | Select-Object -First $Top)) {
        $pct = [math]::Round(($x.Count / $Items.Count) * 100, 1)
        Write-Host ("  {0,-44} {1,5}  {2,5}%" -f $x.Name, $x.Count, $pct)
    }
    if ($g.Count -gt $Top) { Write-Info "... and $($g.Count - $Top) more" }
}

# --- scoping: can we filter reliably to the right items? -------------------
Show-Dist 'Quarantine type' 'QuarantineTypes' $all
Show-Dist 'Policy type'     'PolicyTypes'     $all
Show-Dist 'Policy name'     'PolicyName'      $all
Show-Dist 'Direction'       'Direction'       $all
Show-Dist 'Release status'  'ReleaseStatus'   $all

# --- the subset the MVP actually targets -----------------------------------
$dlpOut = @($all | Where-Object {
    (Get-Prop $_ 'Direction') -eq 'Outbound' -and
    "$(Get-Prop $_ 'QuarantineTypes')" -match 'DataLossPrevention'
})
Write-Step 'MVP scope: outbound DLP'
Write-Ok "$($dlpOut.Count) of $($all.Count) messages ($([math]::Round(($dlpOut.Count/$all.Count)*100,1))%)"
if ($dlpOut.Count -eq 0) {
    Write-Warn2 'No outbound DLP items. The filter used by 03 would return nothing.'
    return
}

# --- volume ----------------------------------------------------------------
Write-Step 'Volume per day'
$byDay = $dlpOut | Group-Object { ([datetime](Get-Prop $_ 'ReceivedTime')).ToString('yyyy-MM-dd') } |
         Sort-Object Name
foreach ($d in $byDay) {
    $bar = '#' * [math]::Min(50, $d.Count)
    Write-Host ("  {0}  {1,4}  {2}" -f $d.Name, $d.Count, $bar)
}
$avg = [math]::Round($dlpOut.Count / [math]::Max(1, $byDay.Count), 1)
Write-Info "Average $avg per day across $($byDay.Count) days with activity."

# --- who and where ---------------------------------------------------------
Write-Step 'Top senders'
$dlpOut | Group-Object { Get-Prop $_ 'SenderAddress' } | Sort-Object Count -Descending |
    Select-Object -First 10 | ForEach-Object { Write-Host ("  {0,-46} {1}" -f $_.Name, $_.Count) }

Write-Step 'Recipient domains'
$domains = $dlpOut | ForEach-Object {
    foreach ($r in @(Get-Prop $_ 'RecipientAddress')) {
        if ($r -match '@(.+)$') { $Matches[1].ToLower() }
    }
}
$domains | Group-Object | Sort-Object Count -Descending | Select-Object -First 15 |
    ForEach-Object { Write-Host ("  {0,-40} {1}" -f $_.Name, $_.Count) }
Write-Info 'Consumer domains here are the exemption cases the MVP has to recognise.'

# --- release history: how often do analysts say yes? -----------------------
Write-Step 'Prior decisions'
$rel = @($dlpOut | Where-Object { (Get-Prop $_ 'ReleaseStatus') -match 'Released|Approved' })
$den = @($dlpOut | Where-Object { (Get-Prop $_ 'ReleaseStatus') -match 'Denied' })
Write-Host ("  Released / approved  {0,5}" -f $rel.Count)
Write-Host ("  Denied               {0,5}" -f $den.Count)
Write-Host ("  Untouched            {0,5}" -f ($dlpOut.Count - $rel.Count - $den.Count))
Write-Info 'Prior decisions are the HLD case-store seed. Note the service keeps'
Write-Info 'at most 30 days, so anything longer has to be journalled by us.'

# --- TNEF prevalence -------------------------------------------------------
if ($Deep) {
    Write-Step "TNEF prevalence - sampling $SampleSize messages"
    Write-Info 'Exports message bodies to check encapsulation. Nothing written to disk.'
    $sample = $dlpOut | Get-Random -Count ([math]::Min($SampleSize, $dlpOut.Count))
    $tnef = 0; $plain = 0; $failed = 0
    $fmts = @()
    $i = 0
    foreach ($m in $sample) {
        $i++
        Write-Progress -Activity 'Sampling' -Status "$i/$($sample.Count)" -PercentComplete (($i/$sample.Count)*100)
        try {
            $e = Export-QuarantineMessage -Identity (Get-Prop $m 'Identity') -CompressOutput `
                    -ReasonForExport 'LAB3 POC - queue profiling' -ErrorAction Stop
            $bytes = [Convert]::FromBase64String($e.Eml)
            $zipT = Join-Path $env:TEMP ("p-{0}.zip" -f ([guid]::NewGuid().ToString('N')))
            $dirT = Join-Path $env:TEMP ("p-{0}" -f ([guid]::NewGuid().ToString('N')))
            [IO.File]::WriteAllBytes($zipT, $bytes)
            Expand-Archive -Path $zipT -DestinationPath $dirT -Force
            $inner = Get-ChildItem $dirT -Recurse -Filter *.eml | Select-Object -First 1
            if ($inner) {
                $txt = [Text.Encoding]::ASCII.GetString([IO.File]::ReadAllBytes($inner.FullName))
                $att = Get-AttachmentsFromEml -EmlText $txt
                if ($att.IsTnef) { $tnef++ } else { $plain++ }
                foreach ($f in $att.FileNames) {
                    if ($f -match '\.([a-z0-9]{1,6})$') { $fmts += $Matches[1].ToLower() }
                }
            }
            Remove-Item $zipT -Force -EA SilentlyContinue
            Remove-Item $dirT -Recurse -Force -EA SilentlyContinue
        }
        catch { $failed++ }
    }
    Write-Progress -Activity 'Sampling' -Completed

    $ok = $tnef + $plain
    if ($ok -gt 0) {
        $pct = [math]::Round(($tnef / $ok) * 100, 1)
        Write-Host ''
        Write-Host ("  Inspectable (standard MIME)  {0,4}" -f $plain) -ForegroundColor Green
        Write-Host ("  TNEF - content hidden        {0,4}  ({1}%)" -f $tnef, $pct) -ForegroundColor $(if($pct -gt 20){'Red'}else{'Yellow'})
        if ($failed) { Write-Host ("  Export failed                {0,4}" -f $failed) -ForegroundColor Red }
        Write-Host ''
        if ($pct -ge 25) {
            Write-Bad "TNEF affects roughly $pct% of messages."
            Write-Info 'Attachment classification needs a TNEF decoder, or Exchange'
            Write-Info 'configured not to send TNEF to external recipients.'
        } elseif ($pct -gt 0) {
            Write-Warn2 "TNEF affects roughly $pct% - a minority, but not negligible."
        } else {
            Write-Ok 'No TNEF in the sample. Attachment inspection should work broadly.'
        }
    }

    if ($fmts.Count -gt 0) {
        Write-Step 'Attachment formats seen'
        $fmts | Group-Object | Sort-Object Count -Descending |
            ForEach-Object { Write-Host ("  .{0,-10} {1}" -f $_.Name, $_.Count) }
        Write-Info 'These are the formats Content Understanding would need to handle.'
    }
}
else {
    Write-Step 'TNEF prevalence'
    Write-Info 'Not measured. Re-run with -Deep to sample message bodies:'
    Write-Info '  .\06-Analyse-Queue.ps1 -Deep -SampleSize 25'
}

# --- summary ---------------------------------------------------------------
$summary = [ordered]@{
    GeneratedAt    = (Get-Date).ToString('u')
    WindowDays     = $Days
    TotalVisible   = $all.Count
    OutboundDlp    = $dlpOut.Count
    PerDayAverage  = $avg
    DistinctSenders= @($dlpOut | ForEach-Object { Get-Prop $_ 'SenderAddress' } | Select-Object -Unique).Count
    Released       = $rel.Count
    Denied         = $den.Count
    TnefSampled    = $(if($Deep){$tnef + $plain}else{$null})
    TnefCount      = $(if($Deep){$tnef}else{$null})
}
$path = Join-Path $out ("queue-profile-{0}.json" -f (Get-Date -Format 'yyyyMMdd-HHmmss'))
$summary | ConvertTo-Json -Depth 4 | Set-Content -Path $path -Encoding UTF8
Write-Step 'Summary written'
Write-Ok $path
Write-Info 'Aggregate counts only - no message content or addresses.'
