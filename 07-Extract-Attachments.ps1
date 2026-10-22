<#
    STEP 7 - Pull the actual attachment files out of a quarantined message.

    Step 4 proves we can see attachment NAMES. This proves we can get the FILES,
    which is what Content Understanding would need as input.

    Covers part of the HLD spike:
      "Run one attachment through Content Understanding and compare structured
       findings with analyst judgement."

    This script does the extraction half. It deliberately does NOT send anything
    to an Azure service - the HLD flags that as a decision requiring agreement on
    privacy, cost, latency and temporary-storage controls, and that decision has
    not been made.

    Files are written to out\, which is gitignored. They are real attachments
    from real messages: treat them accordingly and delete when finished.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$Identity,

    # List what is inside without writing any files.
    [switch]$ListOnly
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Common.ps1')

Connect-Quarantine -Quiet
$out = Initialize-OutDir

Write-Step 'Exporting the message'
try {
    $e = Export-QuarantineMessage -Identity $Identity -CompressOutput `
            -ReasonForExport 'LAB3 POC - attachment extraction spike' -ErrorAction Stop
}
catch {
    Write-Bad $_.Exception.Message
    return
}
if (-not $e.Eml) { Write-Bad 'Export returned no content.'; return }

$bytes = [Convert]::FromBase64String($e.Eml)
$tmpZip = Join-Path $env:TEMP ("x-{0}.zip" -f ([guid]::NewGuid().ToString('N')))
$tmpDir = Join-Path $env:TEMP ("x-{0}" -f ([guid]::NewGuid().ToString('N')))
[IO.File]::WriteAllBytes($tmpZip, $bytes)
Expand-Archive -Path $tmpZip -DestinationPath $tmpDir -Force
$eml = Get-ChildItem $tmpDir -Recurse -Filter *.eml | Select-Object -First 1
if (-not $eml) { Write-Bad 'No .eml inside the archive.'; return }
Write-Ok ("Recovered {0} ({1:N0} bytes)" -f $eml.Name, $eml.Length)

$raw = [IO.File]::ReadAllText($eml.FullName, [Text.Encoding]::ASCII)

# ---------------------------------------------------------------- TNEF check
$probe = Get-AttachmentsFromEml -EmlText $raw
if ($probe.IsTnef) {
    Write-Step 'TNEF'
    Write-Bad 'Attachments are bundled inside winmail.dat and cannot be extracted here.'
    Write-Info 'A TNEF decoder would be needed, or Exchange configured not to send'
    Write-Info 'TNEF to external recipients. Run 06 -Deep to see how common this is.'
    Remove-Item $tmpZip -Force -EA SilentlyContinue
    Remove-Item $tmpDir -Recurse -Force -EA SilentlyContinue
    return
}

# ---------------------------------------------------------------- MIME parts
# Walk the MIME parts far enough to pull base64 attachment bodies out. Enough
# for a spike; a production connector would use a real MIME parser.
Write-Step 'Parsing MIME parts'

$boundary = $null
$bm = [regex]::Match($raw, 'boundary="?([^";\r\n]+)"?', 'IgnoreCase')
if ($bm.Success) { $boundary = $bm.Groups[1].Value }
if (-not $boundary) {
    Write-Warn2 'No MIME boundary found. Message may have no attachments.'
    Remove-Item $tmpZip -Force -EA SilentlyContinue
    Remove-Item $tmpDir -Recurse -Force -EA SilentlyContinue
    return
}
Write-Info "Boundary: $boundary"

$parts = $raw -split [regex]::Escape('--' + $boundary)
Write-Info "$($parts.Count) part(s)"

$found = @()
foreach ($p in $parts) {
    $split = [regex]::Match($p, "(?s)^(.*?)\r?\n\r?\n(.*)$")
    if (-not $split.Success) { continue }
    $headers = $split.Groups[1].Value
    $content = $split.Groups[2].Value

    if ($headers -notmatch 'Content-Disposition:\s*attachment') { continue }

    $fn = [regex]::Match($headers, 'filename\*?=(?:"([^"]+)"|([^;\r\n]+))', 'IgnoreCase')
    if (-not $fn.Success) { continue }
    $name = if ($fn.Groups[1].Success) { $fn.Groups[1].Value } else { $fn.Groups[2].Value }
    $name = $name.Trim().Trim('"')

    $ct = [regex]::Match($headers, 'Content-Type:\s*([^;\r\n]+)', 'IgnoreCase')
    $type = if ($ct.Success) { $ct.Groups[1].Value.Trim() } else { 'unknown' }

    $enc = [regex]::Match($headers, 'Content-Transfer-Encoding:\s*([^\r\n]+)', 'IgnoreCase')
    $encoding = if ($enc.Success) { $enc.Groups[1].Value.Trim().ToLower() } else { '7bit' }

    $data = $null
    if ($encoding -eq 'base64') {
        $clean = ($content -replace '[^A-Za-z0-9+/=]', '')
        try { $data = [Convert]::FromBase64String($clean) } catch { }
    }

    $found += [pscustomobject]@{
        Name = $name; Type = $type; Encoding = $encoding
        Bytes = $(if ($data) { $data.Length } else { 0 })
        Data = $data
    }
}

Write-Step 'Attachments'
if ($found.Count -eq 0) {
    Write-Warn2 'No attachment parts recovered. The message may have none, or use'
    Write-Warn2 'an encoding this simple parser does not handle.'
    Remove-Item $tmpZip -Force -EA SilentlyContinue
    Remove-Item $tmpDir -Recurse -Force -EA SilentlyContinue
    return
}

foreach ($f in $found) {
    $status = if ($f.Data) { 'extractable' } else { "encoding '$($f.Encoding)' not decoded" }
    Write-Ok ("{0,-40} {1,-28} {2:N0} bytes  {3}" -f $f.Name, $f.Type, $f.Bytes, $status)
}

if ($ListOnly) {
    Write-Step 'List only'
    Write-Info 'No files written. Drop -ListOnly to extract them.'
}
else {
    $safe = ($Identity -replace '[\\/:*?"<>|]', '_')
    $dir = Join-Path $out "attachments\$safe"
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }

    Write-Step 'Writing files'
    foreach ($f in $found) {
        if (-not $f.Data) { Write-Warn2 "Skipped $($f.Name) - not decoded"; continue }
        $clean = ($f.Name -replace '[\\/:*?"<>|]', '_')
        $path = Join-Path $dir $clean
        [IO.File]::WriteAllBytes($path, $f.Data)
        Write-Ok $path
    }
    Write-Info 'Real attachments from a real message. out\ is gitignored.'
    Write-Info 'Delete them when the spike is finished.'
}

Remove-Item $tmpZip -Force -EA SilentlyContinue
Remove-Item $tmpDir -Recurse -Force -EA SilentlyContinue

Write-Step 'What this proves'
Write-Ok 'Attachment files are recoverable from quarantine under the app identity.'
Write-Info 'That is the input Content Understanding would need.'
Write-Info ''
Write-Info 'NOT done here, deliberately: sending a file to an Azure service. The HLD'
Write-Info 'lists that as needing agreement on privacy, cost, latency and temporary'
Write-Info 'storage. Worth confirming before anyone builds the classification step.'
