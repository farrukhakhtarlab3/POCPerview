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

function Get-IrmCertificate {
    <#  .SYNOPSIS Find the IRM certificate (separate app registration). #>
    $certs = @(Get-ChildItem Cert:\CurrentUser\My |
        Where-Object { $_.Subject -eq $script:IrmCertSubject } |
        Sort-Object NotBefore -Descending)
    if ($certs.Count -eq 0) {
        throw "No certificate found with subject '$($script:IrmCertSubject)'. Run 10-New-IrmCertificate.ps1 first."
    }
    if ($certs.Count -gt 1) {
        Write-Warn2 "$($certs.Count) certificates match '$($script:IrmCertSubject)'. Using the newest."
    }
    return $certs[0]
}

function Connect-Irm {
    <#
        .SYNOPSIS Connect to Microsoft Graph as the IRM application.
        .DESCRIPTION
            A different app registration, a different certificate and a different
            API from the quarantine side. Nothing is shared between them.
    #>
    [CmdletBinding()]
    param([switch]$Quiet)

    if (-not $script:IrmAppId) {
        throw 'IrmAppId is not set in config.ps1. Add the client ID supplied by the tenant admin.'
    }
    if (-not (Get-Module -ListAvailable Microsoft.Graph.Authentication)) {
        throw 'Microsoft.Graph.Authentication is not installed. Run 00-Install-Prereqs.ps1 first.'
    }
    Import-Module Microsoft.Graph.Authentication -ErrorAction Stop

    $existing = $null
    try { $existing = Get-MgContext } catch { }
    if ($existing -and $existing.ClientId -eq $script:IrmAppId) {
        if (-not $Quiet) { Write-Info 'Reusing existing Graph session.' }
        return
    }

    $cert = Get-IrmCertificate
    if (-not $Quiet) {
        Write-Info "AppId      : $script:IrmAppId"
        Write-Info "Tenant     : $script:IrmTenantId"
        Write-Info "Thumbprint : $($cert.Thumbprint)"
    }

    Connect-MgGraph -ClientId $script:IrmAppId `
        -TenantId $script:IrmTenantId `
        -Certificate $cert `
        -NoWelcome -ErrorAction Stop
}

function Invoke-GraphGet {
    <#  .SYNOPSIS GET from Graph, following @odata.nextLink. #>
    param([Parameter(Mandatory=$true)][string]$Uri, [int]$MaxItems = 500)

    $all = New-Object System.Collections.Generic.List[object]
    $pages = 0
    while ($Uri -and $all.Count -lt $MaxItems -and $pages -lt 50) {
        $r = Invoke-MgGraphRequest -Method GET -Uri $Uri -OutputType PSObject -ErrorAction Stop
        $v = $r.PSObject.Properties['value']
        if ($v -and $v.Value) { foreach ($i in $v.Value) { [void]$all.Add($i) } }
        $n = $r.PSObject.Properties['@odata.nextLink']
        $Uri = if ($n) { $n.Value } else { $null }
        $pages++
    }
    return $all
}

function Get-Prop {
    param($Object, [string]$Name)
    if ($null -eq $Object) { return $null }
    $p = $Object.PSObject.Properties[$Name]
    if ($null -eq $p) { return $null }
    return $p.Value
}

function Get-AttachmentsFromEml {
    <#
        .SYNOPSIS Identify attachments in a raw .eml.
        .DESCRIPTION
            Regex over the MIME headers rather than a parser library or CDO COM
            objects, so it runs on a locked-down VDI with no dependencies.

            Only matches filename= on a Content-Disposition line. An earlier
            version also matched bare name= anywhere, which produced false
            positives from sensitivity-label headers - reporting values like
            "Internal" and "General" as if they were files.

            Also detects TNEF. When Outlook sends in RTF format every real
            attachment is bundled into a single opaque winmail.dat, so the
            filenames and content inside it are NOT visible here. That matters:
            a message can look like one attachment while carrying several.
    #>
    param([Parameter(Mandatory = $true)][string]$EmlText)

    $names = @()

    # Content-Disposition lines only. Tolerates a fold before filename=.
    $dispPattern = 'Content-Disposition:[^\r\n]*(?:\r?\n[ \t][^\r\n]*)*'
    foreach ($d in [regex]::Matches($EmlText, $dispPattern, 'IgnoreCase')) {
        $fn = [regex]::Match($d.Value, 'filename\*?=(?:"([^"]+)"|([^;\r\n]+))', 'IgnoreCase')
        if ($fn.Success) {
            $v = if ($fn.Groups[1].Success) { $fn.Groups[1].Value } else { $fn.Groups[2].Value }
            $v = $v.Trim().Trim('"')
            if ($v) { $names += $v }
        }
    }

    $types = @()
    foreach ($m in [regex]::Matches($EmlText, 'Content-Type:\s*([^;\r\n]+)', 'IgnoreCase')) {
        $types += $m.Groups[1].Value.Trim()
    }

    $unique = @($names | Select-Object -Unique)
    $uTypes = @($types | Select-Object -Unique)

    $isTnef = ($uTypes -match 'ms-tnef') -or ($unique -contains 'winmail.dat')

    [pscustomobject]@{
        FileNames    = $unique
        ContentTypes = $uTypes
        Count        = $unique.Count
        IsTnef       = [bool]$isTnef
        # True only when we can actually enumerate the real attachments.
        ContentVisible = (-not $isTnef)
    }
}
