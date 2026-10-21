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

# Export-QuarantineMessage has two overlapping parameter sets, and which one
# PowerShell resolves varies by module version. Supplying -Identity alone can be
# ambiguous, producing a confusing "missing mandatory parameters: CompressOutput"
# error that looks like a permissions problem but is not. Try each documented
# form until one works.
$reason = 'LAB3 quarantine triage POC - automated content inspection'
$e = $null
$usedForm = $null
$compressed = $false

$attempts = @(
    @{ Name = '-Identity';
       Run  = { Export-QuarantineMessage -Identity $Identity -ReasonForExport $reason -ErrorAction Stop } },

    @{ Name = '-Identities + -Identity 000';   # documented bulk form; Identity value is ignored
       Run  = { Export-QuarantineMessage -Identities $Identity -Identity '000' -ReasonForExport $reason -ErrorAction Stop } },

    @{ Name = '-Identity -CompressOutput';     # returns a .zip rather than raw .eml
       Run  = { Export-QuarantineMessage -Identity $Identity -CompressOutput -ReasonForExport $reason -ErrorAction Stop }
       Zip  = $true }
)

foreach ($a in $attempts) {
    try {
        $e = & $a.Run
        if ($e -and $e.Eml) {
            $usedForm = $a.Name
            $compressed = [bool]$a.Zip
            Write-Ok "Export succeeded using $usedForm"
            break
        }
        $e = $null
    }
    catch {
        Write-Info ("{0,-28} failed: {1}" -f $a.Name, $_.Exception.Message)
        $e = $null
    }
}

if (-not $e) {
    Write-Bad 'All export forms failed.'
    Write-Host ''
    Write-Info 'Step 02 confirmed the cmdlet is available, so this is a syntax or'
    Write-Info 'parameter-set problem rather than a missing permission. Check what'
    Write-Info 'your module version expects:'
    Write-Info '  (Get-Command Export-QuarantineMessage).ParameterSets | Format-List'
    return
}

$bytes = [Convert]::FromBase64String($e.Eml)
Write-Ok ("Payload: {0:N0} bytes" -f $bytes.Length)

if ($compressed) {
    Write-Info 'Output is a .zip - extracting the .eml inside it.'
    $tmpZip = Join-Path $env:TEMP ("qexport-{0}.zip" -f ([guid]::NewGuid().ToString('N')))
    $tmpDir = Join-Path $env:TEMP ("qexport-{0}" -f ([guid]::NewGuid().ToString('N')))
    try {
        [IO.File]::WriteAllBytes($tmpZip, $bytes)
        Expand-Archive -Path $tmpZip -DestinationPath $tmpDir -Force
        $inner = Get-ChildItem $tmpDir -Recurse -Filter *.eml | Select-Object -First 1
        if (-not $inner) { Write-Bad 'No .eml found inside the archive.'; return }
        $bytes = [IO.File]::ReadAllBytes($inner.FullName)
        Write-Ok ("Extracted {0} ({1:N0} bytes)" -f $inner.Name, $bytes.Length)
    }
    finally {
        Remove-Item $tmpZip -Force -ErrorAction SilentlyContinue
        Remove-Item $tmpDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}

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
    Write-Warn2 'No attachment filenames parsed. The message may have none.'
}

if ($att.IsTnef) {
    Write-Host ''
    Write-Bad 'TNEF encapsulation detected (winmail.dat / application/ms-tnef).'
    Write-Info 'Outlook sent this in RTF format, which bundles EVERY attachment'
    Write-Info 'into one opaque winmail.dat. The real filenames and content are'
    Write-Info 'inside that blob and are NOT visible here.'
    Write-Info ''
    Write-Info 'A message can therefore look like a single attachment while'
    Write-Info 'carrying several - exactly the case the classifier must catch.'
    Write-Info 'Decoding needs a TNEF parser, or Exchange can be configured not'
    Write-Info 'to send TNEF to external recipients.'
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
Write-Ok 'Export works - the message body is retrievable under the app identity.'

if ($att.IsTnef) {
    Write-Bad 'Attachment visibility NOT established for this message.'
    Write-Info 'winmail.dat is a container, not a document. We can see that something'
    Write-Info 'is attached, but not what or how many. Do not report this as proof'
    Write-Info 'that the classifier can distinguish bundled attachments.'
    Write-Info ''
    Write-Info 'Worth establishing how common TNEF is across the queue before'
    Write-Info 'designing around attachment inspection.'
}
elseif ($att.Count -gt 1) {
    Write-Ok "$($att.Count) distinct attachments named - the classifier can tell a lone"
    Write-Ok 'document from one bundled with others. That is the case that matters.'
}
elseif ($att.Count -eq 1) {
    Write-Ok 'One attachment, named and visible. Content inspection works for this message.'
}
else {
    Write-Info 'No attachments on this message. Try one that has some.'
}
