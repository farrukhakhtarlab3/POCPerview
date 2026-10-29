# IRM quickstart

Minimal copy-paste sheet for the Insider Risk side. One command per block —
multi-line pastes get mangled in the PowerShell console.

Full run sheet: [STEPS.md](STEPS.md). Background: [README.md](README.md).

Everything here is **read-only** except step 4, which is gated behind
`-Execute` and will currently fail with 403 (see below).

---

## 1. Get the current code

Scripts `10`–`13` were added after the first download, so an earlier copy of
the repo will not have them. This overwrites the scripts and leaves `out\`
alone.

```powershell
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
```
```powershell
Invoke-WebRequest -Uri "https://github.com/farrukhakhtarlab3/POCPerview/archive/refs/heads/main.zip" -OutFile "$env:USERPROFILE\POCPerview.zip"
```
```powershell
Expand-Archive -Path "$env:USERPROFILE\POCPerview.zip" -DestinationPath $env:USERPROFILE -Force
```
```powershell
cd "$env:USERPROFILE\POCPerview-main"
```
```powershell
Get-ChildItem -Recurse | Unblock-File
```
```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force
```

Confirm the IRM scripts are present:

```powershell
Get-ChildItem 1*.ps1 | Select-Object Name
```

Module install, if this is a fresh folder:

```powershell
.\00-Install-Prereqs.ps1
```

---

## 2. Certificate

The client ID is already in `config.ps1` — nothing to edit.

```powershell
.\10-New-IrmCertificate.ps1
```

Gives you two things:

```
File       : C:\Users\...\Desktop\IrmAgentPOC.cer
Thumbprint : <40 hex characters>
```

The `.cer` is the **public** key and is safe to email. The private key stays in
the user certificate store on this machine and never leaves it.

Send the `.cer` to the tenant admin for upload to app registration
`69fe253b-d40d-40c5-92c2-f602a238831c`.

Already created one and need the thumbprint again:

```powershell
Get-ChildItem Cert:\CurrentUser\My | Where-Object { $_.Subject -eq 'CN=IrmAgentPOC' } | Select-Object Thumbprint, NotBefore, NotAfter
```

Check it is CSP and not CNG — empty output means CNG, which will not
authenticate:

```powershell
(Get-ChildItem Cert:\CurrentUser\My | Where-Object { $_.Subject -eq 'CN=IrmAgentPOC' } | Select-Object -First 1).PrivateKey
```

Start over if needed, then send the new `.cer`:

```powershell
.\10-New-IrmCertificate.ps1 -Force
```

---

## 3. Once the certificate is uploaded

Allow a few minutes for propagation. If it fails immediately after upload,
wait and retry before changing anything.

### Find how IRM alerts are identified

```powershell
.\11-Discover-AlertSources.ps1
```

**Run this before anything else on the IRM side.** Microsoft publishes a
`serviceSource` value for `dataLossPrevention` but none for Insider Risk
Management. The Defender portal filters by it, so the alerts are there — how to
select them through the API is undocumented.

This enumerates every alert the identity can see and reports the distinct
`serviceSource`, `detectionSource` and `productName` values present. Whatever
carries the IRM alerts shows up in that breakdown.

### List them

```powershell
.\12-Get-IrmAlerts.ps1 -ServiceSource "<value from step 11>"
```

Without a server-side filter, narrowing locally by name instead:

```powershell
.\12-Get-IrmAlerts.ps1
```

---

## 4. Write test — expect 403 for now

Only `SecurityAlert.Read.All` is granted, so the PATCH will be refused. Run it
anyway: the refusal is the evidence, and it is the documented answer to the HLD
spike *"test whether any supported interface can update the IRM alert/case"*.

Dry run — changes nothing, shows what it would send:

```powershell
.\13-Update-IrmAlert.ps1 -Id "<id>" -AssignTo "analyst@woodside.com" -NewStatus inProgress
```

Attempt it:

```powershell
.\13-Update-IrmAlert.ps1 -Id "<id>" -AssignTo "analyst@woodside.com" -NewStatus inProgress -Execute
```

Either way the attempt is journalled to `out\irm-update-*.json`.

---

## If step 11 returns no IRM alerts

Check these in order before assuming a permissions problem.

**1. Is IRM data sharing with Defender turned on?** Insider risk alerts only
appear in Defender when **Share user risk details with other security
solutions** is enabled in Purview Insider Risk Management → data sharing
settings. If it is off, no permission will make the alerts appear. Worth asking
the tenant admin or the DLP team directly.

**2. Have any IRM alerts fired in the window?** Compare against the Purview IRM
alerts dashboard before concluding anything about API access.

**3. Does the window need widening?**

```powershell
.\11-Discover-AlertSources.ps1 -Days 90
```

---

## Permissions

| Permission | Incidents | Alerts | Granted? |
|---|---|---|---|
| `SecurityAlert.Read.All` | — | Read | **Yes** |
| `SecurityAlert.ReadWrite.All` | — | Read/Write | Not yet |
| `SecurityIncident.ReadWrite.All` | Read/Write | Read/Write | No — and not wanted |

Alerts and incidents are **separate objects with separate permissions**. The
scripts only ever touch `/security/alerts_v2` and only set `status`,
`assignedTo` and `classification` — all alert fields.

`SecurityAlert.ReadWrite.All` grants **no incident access at all**, so it cannot
modify the Defender XDR incident queue the Cyber Defence Centre works from.
`SecurityIncident.ReadWrite.All` could — it can write incident `customTags` and
incident severity, which is exactly what an automation rule downgrading
DLP-related incidents relies on. That permission is deliberately out of scope.

Source: [Investigate insider risk threats in the Microsoft Defender
portal](https://learn.microsoft.com/en-us/defender-xdr/irm-investigate-alerts-defender)
— permissions table under *Microsoft Graph API roles*.

---

## Portal differences worth knowing

Defender XDR and Purview use different status models, and Microsoft documents
the mapping:

| Defender alert status | Purview IRM alert status |
|---|---|
| New | Needs review |
| In progress | Needs review |
| Resolved | Depends on classification; **Dismissed** if none set |

| Defender classification | Purview IRM classification |
|---|---|
| True positive | Confirmed |
| Informational, expected activity | Dismissed |
| False positive | Dismissed |

Updates made in **either** portal are reflected in both, within about 30
minutes of the update. So don't expect the Purview portal to change
immediately after a write, and don't conclude the write failed because it
hasn't appeared yet — re-read the alert through the API instead, which
`13-Update-IrmAlert.ps1` does automatically.

Alert **notes** do not sync between the two. Retention differs too: the
Defender portal holds these for six months, the Purview dashboard for 30 days.
