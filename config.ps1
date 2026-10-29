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
# Permission currently granted: Microsoft Graph -> SecurityAlert.Read.All
#                                (Application, admin consent)
#
# Read-only for now, pending an access decision - not because no write path
# exists. There is no Purview-native API for modifying IRM alert instances
# (Set-ProtectionAlert edits alert POLICIES, not alerts), so the supported write
# path is Defender's alerts_v2. Microsoft documents that route for exactly this
# scenario and states that updates made in either portal are reflected in both
# within about 30 minutes.
#
# The concern raised was that writing through Defender would disturb the
# incident queue the Cyber Defence Centre works from. That applies to a
# different permission. Alerts and incidents are separate objects:
#
#   SecurityAlert.ReadWrite.All       alerts read/write, NO incident access
#   SecurityIncident.ReadWrite.All    incidents read/write, and alerts too
#
# These scripts only touch /security/alerts_v2 and only set status, assignedTo
# and classification - all alert fields. SecurityAlert.ReadWrite.All cannot
# modify an incident at all, so it cannot alter incident tags or severity.
# SecurityIncident.ReadWrite.All could, and is deliberately out of scope.
#
# Residual limitation, stated honestly: both permissions are tenant-wide and
# cannot be scoped to a single alert source. If that is too broad, the fallback
# is delegated access, where the write carries the signed-in analyst's identity
# and is bounded by their own role.
#
# Reference: https://learn.microsoft.com/en-us/defender-xdr/irm-investigate-alerts-defender
#            (permissions table under "Microsoft Graph API roles")
#
# Until ReadWrite is granted, 13-Update-IrmAlert.ps1 fails with 403 on PATCH.
# That is the expected result and is the documented answer to the HLD spike
# "test whether any supported interface can update the IRM alert/case".
# ---------------------------------------------------------------------------
$script:IrmAppId       = '69fe253b-d40d-40c5-92c2-f602a238831c'
$script:IrmCertSubject = 'CN=IrmAgentPOC'
$script:IrmTenantId    = 'woodsideenergy.onmicrosoft.com'

# Where exports and logs are written. Excluded from git - see .gitignore.
$script:OutDir = Join-Path $PSScriptRoot 'out'
