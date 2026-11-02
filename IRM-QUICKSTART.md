# IRM quickstart

Minimal copy-paste sheet for the Insider Risk side. One command per block —
multi-line pastes get mangled in the PowerShell console.

Full run sheet: [STEPS.md](STEPS.md). Background: [README.md](README.md).

Everything here is **read-only** except step 5, which is gated behind
`-Execute`. Confirm the target alert with the DLP team before running that one.

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

## 4. Find a specific alert

`alerts_v2` will not help you look one up. It caps every query at 100 records,
returns no continuation link to page past that, orders results **oldest first**,
reports insider risk alerts with `serviceSource: unknownFutureValue` so they
cannot be filtered server-side, and rejects `startswith()` and `contains()`.
This tenant produces roughly 7,000 alerts a day. None of that is documented.

So you cannot enumerate the queue. You need either the full alert id, or a
creation date to sweep around.

**Insider risk ids are predictable**: `ir` + the short code in the title + a
GUID. Title `Purview IRM ('da9ffdde') ...` → id `irda9ffdde-...`.

Read an alert directly, if you have the id:

```powershell
.\15-Find-Alert.ps1 -Id "irda9ffdde-326d-4cdd-bef1-968c8faac3cb"
```

Hunt for one by its short code and a known creation date — sweeps the window in
time slices, splitting any slice that comes back full:

```powershell
.\15-Find-Alert.ps1 -Code "da9ffdde" -Date "2026-10-30 00:00" -HoursEitherSide 24 -MaxCalls 800
```

Ask for the creation date before sweeping. Guessing costs hundreds of requests
per attempt — the alert above was created 29 Oct, not the 12 Oct first activity
nor the 30 Oct last update, so two windows missed it.

---

## 5. Write test

`SecurityAlert.ReadWrite.All` is granted (Application, admin consent), so the
PATCH now goes through.

**Confirm which alert before writing to anything.** The DLP team asked to be
told first. `da9ffdde` is the agreed test case; nothing else is approved.

Its state before the test — all three at their defaults, so the restore is
exact:

```
status: new    assignedTo: (empty)    classification: (empty)
```

Dry run first — reads the alert, prints what it would send, changes nothing:

```powershell
.\13-Update-IrmAlert.ps1 -Id "irda9ffdde-326d-4cdd-bef1-968c8faac3cb" -AssignTo "PRADIP.SILWAL@woodside.com" -NewStatus inProgress
```

Then the real write:

```powershell
.\13-Update-IrmAlert.ps1 -Id "irda9ffdde-326d-4cdd-bef1-968c8faac3cb" -AssignTo "PRADIP.SILWAL@woodside.com" -NewStatus inProgress -Execute
```

Restore — run this once the Purview side has been observed, not immediately:

```powershell
.\13-Update-IrmAlert.ps1 -Id "irda9ffdde-326d-4cdd-bef1-968c8faac3cb" -AssignTo "" -NewStatus new -Execute
```

Every attempt is journalled to `out\irm-update-*.json` with the before state.

**Use `inProgress`, never `resolved`.** Resolving without a classification maps
to **Dismissed** in Purview — see the mapping tables below. This is a live alert
concerning a named employee.

Two things to watch between the write and the restore, both currently unproven:

- Does the change reach **Purview**? Allow 30 minutes. Note that `new` and
  `inProgress` both display as *Needs review* there, so the **assignment** is
  the visible difference, not the status. Whether `assignedTo` syncs at all is
  not in Microsoft's documented field list — worth settling either way.
- Does the **parent incident** change? Alerts and incidents are separate
  objects with separate permissions, so it should not. Confirming that is the
  direct answer to the Cyber Defence Centre's concern about their queue.

---

## 6. Close test — the only change Purview can show

Observed on 2 Nov: after setting the alert to `inProgress`, Purview still read
**Needs review**. That is correct and documented — `new` and `inProgress` both
map to *Needs review*, so the status column cannot move for that write. It is
not evidence the sync failed, and it is not evidence it worked.

The only write that produces a visible status change in Purview is **resolved
plus a classification**:

| Command | Purview result |
|---|---|
| `-NewStatus resolved -Classification truePositive` | **Confirmed** |
| `-NewStatus resolved -Classification informationalExpectedActivity` | **Dismissed** |
| `-NewStatus resolved -Classification falsePositive` | **Dismissed** |
| `-NewStatus resolved` with no classification | **Dismissed** — silently |

**Get the alert owner's explicit agreement before running this.** It writes a
real disposition on a real alert about a named user and takes it out of the
review queue. It is not a cosmetic change, and reverting it is unproven.

Use `informationalExpectedActivity` for a test. Microsoft's own description of
that value is *"includes security testing, confirmed activity"*, which is
exactly what this is. Never use `truePositive` for a test — that records a
confirmed insider risk finding against a named employee.

```powershell
.\13-Update-IrmAlert.ps1 -Id "irda9ffdde-326d-4cdd-bef1-968c8faac3cb" -NewStatus resolved -Classification informationalExpectedActivity -Execute
```

Then wait 30 minutes and have the alert owner check Purview. Expect
**Needs review → Dismissed**.

### Attempted revert

```powershell
.\13-Update-IrmAlert.ps1 -Id "irda9ffdde-326d-4cdd-bef1-968c8faac3cb" -AssignTo "" -NewStatus new -Classification unknown -Execute
```

Expect this to be imperfect. Graph lists `unknown` in the classification enum,
but enums are frequently read-only for that value and reject it on write.
Microsoft documents the Defender → Purview mapping and says nothing about
undoing it, so the classification may stick in Purview even if Defender accepts
the reset.

If it does not revert cleanly, record that rather than working around it. **An
agent that can classify but cannot un-classify is a one-way door**, and that is
a real constraint on how much autonomy the production design can be given. It
belongs in the HLD.

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
| `SecurityAlert.Read.All` | — | Read | Superseded |
| `SecurityAlert.ReadWrite.All` | — | Read/Write | **Yes** |
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

Purview's own status filter offers four values — Needs review, Confirmed,
Dismissed and **Resolved** — but no Defender value maps to *Resolved*. It does
not appear anywhere in Microsoft's mapping tables. So an agent writing through
the Defender API can produce Needs review, Confirmed or Dismissed, and never
Resolved. If the organisation's IRM process ends in Resolved, that last step
stays a human action in the Purview portal. Worth raising early — it is a
ceiling on what the agent can close out, not a bug to engineer around.

`assignedTo` is not in Microsoft's synced-field list either. The page does not
mention assignment in either direction, so whether it reaches Purview is
undocumented.
