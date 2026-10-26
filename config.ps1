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
# Permission granted: Microsoft Graph -> SecurityAlert.Read.All
#                      (Application, admin consent)
#
# READ-ONLY, deliberately. Woodside's DLP team work out of Purview, not the
# Defender XDR portal. There is no Purview-native API for modifying IRM alerts,
# so the only programmatic write path is Defender's alerts_v2 - which syncs back
# to Purview within 30 minutes but also writes into the Defender incident queue
# used by the Cyber Defence Centre. Write access was withheld to avoid that
# collision.
#
# This matches the MVP scope in the IRM HLD: "Initial scope is read-only against
# evidence sources. Any IRM case update requires explicit analyst approval and a
# supported interface." Autonomous closure is listed under Future Additions.
#
# 13-Update-IrmAlert.ps1 will therefore fail with 403 on PATCH. That is the
# expected result, not a fault - and it is the documented answer to the HLD
# spike "Test whether any supported interface can update the IRM alert/case".
# ---------------------------------------------------------------------------
$script:IrmAppId       = '69fe253b-d40d-40c5-92c2-f602a238831c'
$script:IrmCertSubject = 'CN=IrmAgentPOC'
$script:IrmTenantId    = 'woodsideenergy.onmicrosoft.com'

# Where exports and logs are written. Excluded from git - see .gitignore.
$script:OutDir = Join-Path $PSScriptRoot 'out'
