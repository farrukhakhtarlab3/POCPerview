<#
    Shared settings for the quarantine triage POC.

    None of these are secrets. The credential is the certificate, whose private
    key lives in the user certificate store on the VDI and never leaves it.
#>

# Entra application registration created by Woodside (Liam Tietjens, 20 Oct 2026)
$script:AppId = '9bce4be6-943d-4f0b-b284-4fdbd25a4dfa'

# Must be the .onmicrosoft.com domain, NOT woodside.com.
$script:Organization = 'woodsideenergy.onmicrosoft.com'

# The certificate is located by subject rather than a hard-coded thumbprint,
# so regenerating it doesn't mean editing scripts.
$script:CertSubject = 'CN=QuarantineAgentPOC'

# Where exports and logs are written. Excluded from git - see .gitignore.
$script:OutDir = Join-Path $PSScriptRoot 'out'
