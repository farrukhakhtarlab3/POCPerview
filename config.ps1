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

# ---------------------------------------------------------------------------
# Use case 2 - Insider Risk Management alerts, via Microsoft Graph.
#
# Deliberately a SEPARATE application registration. Woodside's position is that
# separate use cases get separate apps, so neither carries permissions it does
# not need: this one has no Exchange access, and the quarantine app has no Graph
# access.
#
# Permission required: Microsoft Graph -> SecurityAlert.ReadWrite.All
#                      (Application, admin consent)
# ---------------------------------------------------------------------------
$script:IrmAppId       = ''                     # pending - supplied by the tenant admin
$script:IrmCertSubject = 'CN=IrmAgentPOC'
$script:IrmTenantId    = 'woodsideenergy.onmicrosoft.com'

# Where exports and logs are written. Excluded from git - see .gitignore.
$script:OutDir = Join-Path $PSScriptRoot 'out'
