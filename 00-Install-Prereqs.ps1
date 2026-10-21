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

Write-Step 'Output folder'
$out = Initialize-OutDir
Write-Ok $out
Write-Info 'Excluded from git. Nothing exported from the tenant is ever committed.'

Write-Step 'Next'
Write-Info 'Run  .\01-New-Certificate.ps1   (skip if your certificate already exists)'
