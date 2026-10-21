<#
    STEP 3 - Read the quarantine queue.

    Read-only. Changes nothing. Writes a CSV summary to out\ for reference.
#>
[CmdletBinding()]
param(
    [int]$Days = 16,          # service maximum is 30
    [int]$Top  = 50
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Common.ps1')

Connect-Quarantine -Quiet
$out = Initialize-OutDir
$start = (Get-Date).AddDays(-$Days)
$end   = Get-Date

Write-Step "Outbound DLP quarantine - last $Days days"
$dlp = @()
try {
    $dlp = @(Get-QuarantineMessage -StartReceivedDate $start -EndReceivedDate $end `
                -Direction Outbound -Type DataLossPrevention -PageSize 100 -ErrorAction Stop)
    Write-Ok "$($dlp.Count) message(s)"
}
catch {
    Write-Bad $_.Exception.Message
}

if ($dlp.Count -eq 0) {
    Write-Warn2 'Nothing in outbound DLP quarantine.'
    Write-Info  'Checking what IS in quarantine, to confirm we can see the queue at all.'

    Write-Step 'Everything visible to this identity'
    try {
        $all = @(Get-QuarantineMessage -StartReceivedDate $start -EndReceivedDate $end `
                    -PageSize 100 -ErrorAction Stop)
        Write-Ok "$($all.Count) message(s) total"
        if ($all.Count -gt 0) {
            $all | Group-Object QuarantineTypes | Sort-Object Count -Descending |
                ForEach-Object { Write-Info ("{0,-26} {1}" -f $_.Name, $_.Count) }
            Write-Host ''
            $all | Group-Object Direction |
                ForEach-Object { Write-Info ("{0,-26} {1}" -f $_.Name, $_.Count) }
            Write-Host ''
            Write-Info 'Read access works. There is simply no outbound DLP quarantine yet,'
            Write-Info 'which is a finding about the tenant, not a fault in the setup.'
        }
        else {
            Write-Warn2 'Quarantine is empty entirely. Either nothing is quarantined,'
            Write-Warn2 'or this identity cannot see it. Compare against the Defender portal.'
        }
    }
    catch {
        Write-Bad $_.Exception.Message
    }
    return
}

Write-Step 'Messages'
$view = $dlp | Select-Object `
    @{n='Received'; e={ $_.ReceivedTime }},
    @{n='Sender';   e={ $_.SenderAddress }},
    @{n='Recipients';e={ ($_.RecipientAddress -join '; ') }},
    @{n='Subject';  e={ $_.Subject }},
    @{n='Policy';   e={ $_.PolicyName }},
    @{n='Released'; e={ $_.ReleaseStatus }},
    @{n='Identity'; e={ $_.Identity }}

$view | Select-Object -First $Top | Format-Table -AutoSize -Wrap | Out-String | Write-Host

$csv = Join-Path $out ("quarantine-{0}.csv" -f (Get-Date -Format 'yyyyMMdd-HHmmss'))
$view | Export-Csv -Path $csv -NoTypeInformation -Encoding UTF8
Write-Ok "Written to $csv"
Write-Info 'out\ is gitignored - this never reaches the public repository.'

Write-Step 'Next'
Write-Info 'Copy an Identity value from above, then run:'
Write-Info '  .\04-Inspect-Message.ps1 -Identity "<guid1\guid2>"'
