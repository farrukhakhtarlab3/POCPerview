<#
    STEP 5 - THE DECISIVE TEST.

    Can an application identity release a quarantined message?

    Microsoft documents app-only authentication for Exchange Online PowerShell,
    and does not list the quarantine cmdlets among the unsupported ones - but it
    never confirms them either. This script settles it.

    The answer determines the product:
      works      -> the agent can clear the queue autonomously
      fails      -> the agent recommends, a human clicks release

    THIS DELIVERS A REAL EMAIL AND CANNOT BE UNDONE.
    Nothing happens without -Execute and a typed confirmation.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$Identity,

    # Recipient to release to. Defaults to the message's own recipient.
    [string]$User,

    # Required. Without it this is a dry run.
    [switch]$Execute
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Common.ps1')

Connect-Quarantine -Quiet
$out = Initialize-OutDir

Write-Step 'Message to be released'
try {
    $m = Get-QuarantineMessage -Identity $Identity -ErrorAction Stop
}
catch {
    Write-Bad $_.Exception.Message
    return
}

Write-Info ("Subject    : {0}" -f $m.Subject)
Write-Info ("Sender     : {0}" -f $m.SenderAddress)
Write-Info ("Recipients : {0}" -f ($m.RecipientAddress -join '; '))
Write-Info ("Received   : {0}" -f $m.ReceivedTime)
Write-Info ("Status     : {0}" -f $m.ReleaseStatus)

if ($m.ReleaseStatus -eq 'Released') {
    Write-Warn2 'This message has already been released. Pick another.'
    return
}

if (-not $User) {
    $User = @($m.RecipientAddress)[0]
    Write-Info "No -User given. Defaulting to $User"
}

# ---------------------------------------------------------------- dry run
if (-not $Execute) {
    Write-Step 'DRY RUN - nothing sent'
    Write-Host ''
    Write-Host '  Would run:' -ForegroundColor Yellow
    Write-Host ("    Release-QuarantineMessage -Identity {0} -User '{1}'" -f $Identity, $User)
    Write-Host ''
    Write-Info 'Re-run with -Execute to actually release. Choose the message deliberately -'
    Write-Info 'ideally one a reviewer had already decided should go out.'
    return
}

# ---------------------------------------------------------------- confirm
Write-Step 'CONFIRM'
Write-Host ''
Write-Host "  This will DELIVER a real message to $User" -ForegroundColor Yellow
Write-Host '  It cannot be undone.' -ForegroundColor Yellow
Write-Host ''
$answer = Read-Host '  Type RELEASE to proceed'
if ($answer -ne 'RELEASE') {
    Write-Warn2 'Aborted.'
    return
}

# ---------------------------------------------------------------- release
Write-Step 'Releasing'
$result = [ordered]@{
    Identity  = $Identity
    User      = $User
    Subject   = $m.Subject
    Sender    = $m.SenderAddress
    AttemptAt = (Get-Date).ToString('u')
    Outcome   = $null
    Error     = $null
}

try {
    Release-QuarantineMessage -Identity $Identity -User $User -ErrorAction Stop
    $result.Outcome = 'SUCCESS'
    Write-Ok 'Release succeeded under the application identity.'
    Write-Host ''
    Write-Host '  The autonomous design holds. The agent can act, not just advise.' -ForegroundColor Green
}
catch {
    $result.Outcome = 'FAILED'
    $result.Error = $_.Exception.Message
    Write-Bad $_.Exception.Message
    Write-Host ''
    Write-Info 'If this is a permissions error, the role group has Get- but not'
    Write-Info 'Release-QuarantineMessage. Confirm with the tenant admin before'
    Write-Info 'concluding the API itself does not support app-only release.'
    Write-Info 'If it fails here but works interactively, the product becomes'
    Write-Info '"agent recommends, human clicks" - still useful, different pitch.'
}

# Journal the attempt either way - the result is the deliverable.
$log = Join-Path $out ("release-test-{0}.json" -f (Get-Date -Format 'yyyyMMdd-HHmmss'))
$result | ConvertTo-Json -Depth 4 | Set-Content -Path $log -Encoding UTF8
Write-Step 'Logged'
Write-Ok $log

Write-Step 'Verify'
Write-Info 'Re-read the message to confirm the status changed:'
Write-Info ("  Get-QuarantineMessage -Identity {0} | Select ReleaseStatus" -f $Identity)
Write-Info 'Then check the recipient mailbox actually received it.'
