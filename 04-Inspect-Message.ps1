<#
    STEP 4 - Can the automation see INSIDE a quarantined message?

    This is the question the classifier depends on. Metadata alone cannot tell a
    payslip on its own from a payslip with an extra confidential document
    attached - and that distinction is the whole reason for the project.

    Read-only. The message is not released or altered. It does write the .eml to
    out\, which is gitignored.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$Identity,

    # Skip writing the .eml to disk - metadata inspection only.
    [switch]$NoSave
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Common.ps1')

Connect-Quarantine -Quiet
$out = Initialize-OutDir

# ---------------------------------------------------------------- metadata
Write-Step 'Message detail'
try {
    $m = Get-QuarantineMessage -Identity $Identity -ErrorAction Stop
    Write-Ok 'Retrieved.'
}
catch {
    Write-Bad $_.Exception.Message
    Write-Info 'Check the Identity is exactly as shown by 03 - format is guid1\guid2.'
    return
}

Write-Info ("Subject     : {0}" -f $m.Subject)
Write-Info ("Sender      : {0}" -f $m.SenderAddress)
Write-Info ("Recipients  : {0}" -f ($m.RecipientAddress -join '; '))
Write-Info ("Received    : {0}" -f $m.ReceivedTime)
Write-Info ("Type        : {0}" -f $m.QuarantineTypes)
Write-Info ("Direction   : {0}" -f $m.Direction)
Write-Info ("Policy      : {0}" -f $m.PolicyName)
Write-Info ("Release     : {0}" -f $m.ReleaseStatus)

$ac = $m.PSObject.Properties['AttachmentsCount']
if ($ac) { Write-Info ("Attachments : {0}  (from metadata)" -f $ac.Value) }
else     { Write-Warn2 'No AttachmentsCount property exposed in metadata.' }

# ---------------------------------------------------------------- headers
Write-Step 'Message headers'
try {
    $h = Get-QuarantineMessageHeader -Identity $Identity -ErrorAction Stop
    Write-Ok 'Headers retrieved.'
    $auth = ($h.Header -split "`n") | Where-Object { $_ -match 'Authentication-Results|SPF|DKIM|DMARC' } |
            Select-Object -First 4
    foreach ($line in $auth) { Write-Info $line.Trim() }
}
catch {
    Write-Warn2 "Header retrieval failed: $($_.Exception.Message)"
}

# ---------------------------------------------------------------- content
Write-Step 'Exporting content (the decisive read test)'
try {
    $e = Export-QuarantineMessage -Identity $Identity `
            -ReasonForExport 'LAB3 quarantine triage POC - automated content inspection' `
            -ErrorAction Stop
    Write-Ok 'Export succeeded.'
}
catch {
    Write-Bad $_.Exception.Message
    Write-Host ''
    Write-Info 'If this fails but Get-QuarantineMessage works, the role group is missing'
    Write-Info 'Export-QuarantineMessage. Without it the classifier is blind to attachments.'
    return
}

if (-not $e.Eml) {
    Write-Bad 'Export returned no Eml content.'
    return
}

$bytes = [Convert]::FromBase64String($e.Eml)
Write-Ok ("Message size: {0:N0} bytes" -f $bytes.Length)

$text = [Text.Encoding]::ASCII.GetString($bytes)
$att = Get-AttachmentsFromEml -EmlText $text

Write-Step 'Attachments found in the message body'
if ($att.Count -gt 0) {
    foreach ($f in $att.FileNames) { Write-Ok $f }
    Write-Host ''
    Write-Info 'Content types present:'
    foreach ($t in ($att.ContentTypes | Select-Object -First 10)) { Write-Info "  $t" }
}
else {
    Write-Warn2 'No attachment filenames parsed. The message may have none,'
    Write-Warn2 'or they are encoded in a form this simple parser missed.'
}

if (-not $NoSave) {
    $safe = ($Identity -replace '[\\/:*?"<>|]', '_')
    $path = Join-Path $out "$safe.eml"
    [IO.File]::WriteAllBytes($path, $bytes)
    Write-Step 'Saved'
    Write-Ok $path
    Write-Info 'Openable in Outlook. out\ is gitignored - never commit this.'
}

Write-Step 'What this tells us'
if ($att.Count -gt 1) {
    Write-Ok "$($att.Count) attachments detected - the classifier CAN tell a lone payslip"
    Write-Ok 'from a payslip bundled with something else. That is the case that matters.'
}
elseif ($att.Count -eq 1) {
    Write-Ok 'Single attachment detected and named. Content inspection works.'
}
Write-Info 'Next: .\05-Test-Release.ps1 - the one that changes something.'
