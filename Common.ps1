<#
    Shared helpers. Dot-sourced by the numbered scripts; not run directly.
#>

. (Join-Path $PSScriptRoot 'config.ps1')

function Write-Step { param([string]$Text) Write-Host "`n== $Text" -ForegroundColor Cyan }
function Write-Ok   { param([string]$Text) Write-Host "  PASS  $Text" -ForegroundColor Green }
function Write-Bad  { param([string]$Text) Write-Host "  FAIL  $Text" -ForegroundColor Red }
function Write-Warn2{ param([string]$Text) Write-Host "  WARN  $Text" -ForegroundColor Yellow }
function Write-Info { param([string]$Text) Write-Host "        $Text" -ForegroundColor DarkGray }

function Initialize-OutDir {
    if (-not (Test-Path $script:OutDir)) {
        New-Item -ItemType Directory -Path $script:OutDir | Out-Null
    }
    return $script:OutDir
}

function Get-PocCertificate {
    <#
        .SYNOPSIS Find the POC certificate in the current user's store.
        .DESCRIPTION
            Located by subject rather than thumbprint so the scripts keep working
            if the certificate is regenerated. Picks the newest if several exist.
    #>
    $certs = @(Get-ChildItem Cert:\CurrentUser\My |
        Where-Object { $_.Subject -eq $script:CertSubject } |
        Sort-Object NotBefore -Descending)

    if ($certs.Count -eq 0) {
        throw "No certificate found with subject '$($script:CertSubject)'. Run 01-New-Certificate.ps1 first."
    }
    if ($certs.Count -gt 1) {
        Write-Warn2 "$($certs.Count) certificates match '$($script:CertSubject)'. Using the newest."
        Write-Info  "Only the one uploaded to the app registration will actually authenticate."
    }
    return $certs[0]
}

function Connect-Quarantine {
    <#  .SYNOPSIS Connect to Exchange Online as the application. #>
    [CmdletBinding()]
    param([switch]$Quiet)

    if (-not (Get-Module -ListAvailable ExchangeOnlineManagement)) {
        throw 'ExchangeOnlineManagement is not installed. Run 00-Install-Prereqs.ps1 first.'
    }
    Import-Module ExchangeOnlineManagement -ErrorAction Stop

    # Reuse an existing session rather than stacking connections.
    $existing = $null
    try { $existing = Get-ConnectionInformation -ErrorAction SilentlyContinue } catch { }
    if ($existing) {
        if (-not $Quiet) { Write-Info "Reusing existing Exchange Online session." }
        return
    }

    $cert = Get-PocCertificate
    if (-not $Quiet) {
        Write-Info "AppId        : $script:AppId"
        Write-Info "Organization : $script:Organization"
        Write-Info "Thumbprint   : $($cert.Thumbprint)"
    }

    Connect-ExchangeOnline `
        -AppId $script:AppId `
        -CertificateThumbprint $cert.Thumbprint `
        -Organization $script:Organization `
        -ShowBanner:$false `
        -ErrorAction Stop
}

function Disconnect-Quarantine {
    try { Disconnect-ExchangeOnline -Confirm:$false -ErrorAction SilentlyContinue | Out-Null } catch { }
}

function Get-AttachmentsFromEml {
    <#
        .SYNOPSIS Pull attachment filenames and types out of a raw .eml.
        .DESCRIPTION
            Deliberately regex-based over the MIME headers rather than using a
            parser library or CDO COM objects, so it runs on a locked-down VDI
            with no extra dependencies. Good enough to answer the question that
            matters: what is attached, and how many.
    #>
    param([Parameter(Mandatory = $true)][string]$EmlText)

    $results = @()

    # filename= / filename*= on Content-Disposition, and name= on Content-Type
    $patterns = @(
        'filename\*?=(?:"([^"]+)"|([^;\r\n]+))',
        '[^a-zA-Z]name\*?=(?:"([^"]+)"|([^;\r\n]+))'
    )
    foreach ($p in $patterns) {
        foreach ($m in [regex]::Matches($EmlText, $p, 'IgnoreCase')) {
            $v = if ($m.Groups[1].Success) { $m.Groups[1].Value } else { $m.Groups[2].Value }
            $v = $v.Trim().Trim('"')
            if ($v) { $results += $v }
        }
    }

    $types = @()
    foreach ($m in [regex]::Matches($EmlText, 'Content-Type:\s*([^;\r\n]+)', 'IgnoreCase')) {
        $types += $m.Groups[1].Value.Trim()
    }

    [pscustomobject]@{
        FileNames    = ($results | Select-Object -Unique)
        ContentTypes = ($types | Select-Object -Unique)
        Count        = @($results | Select-Object -Unique).Count
    }
}
