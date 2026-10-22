<#
    STEP 0 - Install the one module this POC needs.
    Safe to re-run. No admin rights required.
#>
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Common.ps1')

Write-Step 'PowerShell version'
Write-Info $PSVersionTable.PSVersion.ToString()

Write-Step 'ExchangeOnlineManagement module'
$mod = Get-Module -ListAvailable ExchangeOnlineManagement |
       Sort-Object Version -Descending | Select-Object -First 1

if ($mod -and $mod.Version -ge [version]'3.0.0') {
    Write-Ok "Already installed: $($mod.Version)"
}
else {
    if ($mod) { Write-Warn2 "Found $($mod.Version) - need 3.0.0 or later. Updating." }
    else      { Write-Info 'Not installed. Installing now.' }

    # PowerShell 5.1 can negotiate TLS 1.0 against PSGallery and fail.
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

    # -AllowClobber is required: PackageManagement wants to override
    # Find-Package / Install-Package / Uninstall-Package and is blocked without it.
    Install-Module ExchangeOnlineManagement -Scope CurrentUser -Force -AllowClobber

    $mod = Get-Module -ListAvailable ExchangeOnlineManagement |
           Sort-Object Version -Descending | Select-Object -First 1
    if ($mod) { Write-Ok "Installed: $($mod.Version)" }
    else      { Write-Bad 'Install appears to have failed.'; return }
}

Write-Step 'Microsoft.Graph.Authentication module'
# Needed only for the Insider Risk scripts (10-13), which use Graph rather than
# Exchange PowerShell. Just this one sub-module, not the full Graph SDK - the
# scripts call Graph REST directly through Invoke-MgGraphRequest.
$g = Get-Module -ListAvailable Microsoft.Graph.Authentication |
     Sort-Object Version -Descending | Select-Object -First 1

if ($g) {
    Write-Ok "Already installed: $($g.Version)"
}
else {
    Write-Info 'Not installed. Installing now.'
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    try {
        Install-Module Microsoft.Graph.Authentication -Scope CurrentUser -Force -AllowClobber -ErrorAction Stop
        $g = Get-Module -ListAvailable Microsoft.Graph.Authentication |
             Sort-Object Version -Descending | Select-Object -First 1
        Write-Ok "Installed: $($g.Version)"
    }
    catch {
        Write-Warn2 "Could not install: $($_.Exception.Message)"
        Write-Info  'Only affects the Insider Risk scripts (10-13).'
        Write-Info  'The quarantine scripts (01-05) work without it.'
    }
}

Write-Step 'Output folder'
$out = Initialize-OutDir
Write-Ok $out
Write-Info 'Excluded from git. Nothing exported from the tenant is ever committed.'

Write-Step 'Next'
Write-Info 'Quarantine   : .\01-New-Certificate.ps1   (skip if the cert already exists)'
Write-Info 'Insider risk : .\10-New-IrmCertificate.ps1 (needs the second app registration)'
