# Run sheet

Copy-paste sequence for the VDI. One command at a time — multi-line pastes get
mangled in the PowerShell console.

Background and troubleshooting are in [README.md](README.md).

> **The quarantine queue holds production mail.** Verified 21 Oct 2026 — real
> staff, real personal recipient addresses, real correspondence. Steps 1 to 8
> are read-only and safe. Step 9 releases a real message and needs explicit
> sign-off. Anything written to `out/` is real personal data: keep it on the
> VDI and delete it when finished.

---

### 1. Open PowerShell

Search → `powershell` → **Windows PowerShell**. No admin needed.

### 2. Get the code

**No git on the VDI?** Use this — downloads and extracts the ZIP, no git or
browser required.

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

The folder is `POCPerview-main` — GitHub appends the branch name to ZIP
downloads.

**If git is available**, this works too:

```powershell
cd $env:USERPROFILE
```
```powershell
git clone https://github.com/farrukhakhtarlab3/POCPerview.git
```
```powershell
cd POCPerview
```

### 3. Unblock and allow scripts to run

Files downloaded from the internet carry a "mark of the web" flag that blocks
execution even when the execution policy allows it. Skip this and the scripts
fail with a security warning.

```powershell
Get-ChildItem -Recurse | Unblock-File
```
```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force
```

Process scope only — resets when the window closes.

### 4. Install the module

```powershell
.\00-Install-Prereqs.ps1
```

### 5. Certificate — SKIP if yours is already uploaded

Only the certificate uploaded to the app registration can authenticate. Running
this again would create a second one and silently break auth, so the script
detects an existing certificate and stops.

```powershell
.\01-New-Certificate.ps1
```

Starting over (then send the new `.cer` to the tenant admin):

```powershell
.\01-New-Certificate.ps1 -Force
```

### 6. Test the connection

```powershell
.\02-Test-Connection.ps1
```

Expect a `PASS` for each of `Get-QuarantineMessage`,
`Get-QuarantineMessageHeader`, `Preview-QuarantineMessage`,
`Export-QuarantineMessage`, `Release-QuarantineMessage` — and
`Delete-QuarantineMessage` correctly **absent**.

### 7. Read the queue

```powershell
.\03-Get-QuarantineMessages.ps1
```

Wider window (service maximum is 30 days):

```powershell
.\03-Get-QuarantineMessages.ps1 -Days 30
```

#### Getting an Identity value

The table is wide and the `Identity` column often runs off the right of the
console. Use `Format-List` instead — nothing truncates:

```powershell
Get-QuarantineMessage -Direction Outbound -Type DataLossPrevention -PageSize 10 | Select-Object Subject, SenderAddress, Identity | Format-List
```

Or read it back from the CSV step 7 already wrote:

```powershell
Import-Csv (Get-ChildItem .\out\quarantine-*.csv | Select-Object -Last 1).FullName | Select-Object -First 10 Subject, Identity | Format-List
```

You want the whole value including the backslash:

```
Identity : c14401cf-aa9a-465b-cfd5-08d0f0ca37c5\4c2ca98e-94ea-db3a-7eb8-3b63657d4db7
```

**Choose an innocuous message.** Any message proves the same technical point,
so there is no reason to pull HR, medical or departure correspondence onto
disk. Pick something routine.

### 8. Look inside a message

```powershell
.\04-Inspect-Message.ps1 -Identity "<guid1\guid2>"
```

Lists the attachments it can see. This is what proves the classifier can tell a
payslip on its own from a payslip with something else attached.

### 9. Release test — dry run first

> ### ⚠️ The queue contains production mail
>
> Confirmed 21 Oct 2026: step 7 returned 100 messages from real staff to real
> personal addresses, including HR, medical and audit correspondence. This is
> **not** a sandbox with synthetic data.
>
> Releasing here delivers a genuine email to a real external recipient that a
> DLP policy deliberately held back. **Do not run this step without explicit
> sign-off from the tenant owner and a specific nominated message** — ideally
> one a reviewer had already approved for release, so the outcome is what would
> have happened anyway and only the trigger differs.
>
> Steps 1 to 8 are read-only and unaffected.

Sends nothing:

```powershell
.\05-Test-Release.ps1 -Identity "<guid1\guid2>"
```

Then for real — asks you to type `RELEASE`:

```powershell
.\05-Test-Release.ps1 -Identity "<guid1\guid2>" -Execute
```

---

## Two things to keep in mind

**Steps 6 to 8 change nothing.** Re-run them freely. Step 9 is the only one that
does anything irreversible.

**This repository is public.** `out/`, `*.eml` and certificate files are
gitignored. Everything the scripts export stays local — don't force-add anything
from `out/`.

---

# Use case 2 — Insider Risk alerts

Separate app registration, separate certificate, different API. Nothing is
shared with the quarantine side: that app has no Graph access, this one has no
Exchange access.

Needs **Microsoft Graph → `SecurityAlert.ReadWrite.All`** (Application, admin
consent) on its own registration.

### 10. Certificate for the IRM app

```powershell
.\10-New-IrmCertificate.ps1
```

Send the `.cer` to the tenant admin, then put the client ID into `config.ps1`
as `$script:IrmAppId`.

### 11. Connect and find out how IRM alerts are identified

```powershell
.\11-Discover-AlertSources.ps1
```

**Run this before anything else on the IRM side.** Microsoft's published
`serviceSource` enum lists `dataLossPrevention` but has **no value for Insider
Risk Management**. The Defender portal filters by it, so the alerts exist — how
to select them through the API is undocumented.

Rather than guessing a filter value, this enumerates every alert the identity
can see and reports the distinct `serviceSource`, `detectionSource` and
`productName` values present. Whatever carries the IRM alerts shows up there.

Read-only.

### 12. List the alerts

Using whatever step 11 told you:

```powershell
.\12-Get-IrmAlerts.ps1 -ServiceSource "<value from step 11>"
```

Or without a server-side filter, narrowing locally by name:

```powershell
.\12-Get-IrmAlerts.ps1
```

### 13. Assign and update

The IRM equivalent of the release test — proving the identity can write, not
just read. Far lower risk: nothing is sent and nothing leaves the tenant, these
are fields on the alert record.

Dry run:

```powershell
.\13-Update-IrmAlert.ps1 -Id "<id>" -AssignTo "analyst@woodside.com" -NewStatus inProgress
```

Apply:

```powershell
.\13-Update-IrmAlert.ps1 -Id "<id>" -AssignTo "analyst@woodside.com" -NewStatus inProgress -Execute
```

It re-reads the alert afterwards and confirms each field actually changed.

> Status models differ between portals. Defender's `new` and `inProgress` both
> appear as **Needs review** in Purview. `resolved` maps by classification, and
> without one it defaults to **Dismissed**. Changes sync both ways within about
> 30 minutes, so don't expect the Purview portal to update immediately.

---

## Useful commands

### Duplicate certificates

Several certificates with the same subject accumulate easily across attempts.
Only the one uploaded to the app registration authenticates, and the scripts
pick the newest — so a stale duplicate can cause a confusing failure later.

See what it would do — dry run, removes nothing:

```powershell
.\99-Cert-Cleanup.ps1
```

Apply it. Keeps the newest certificate, which is normally the one that works:

```powershell
.\99-Cert-Cleanup.ps1 -Execute
```

Only pass a thumbprint if the newest is *not* the one uploaded to the app
registration. `02-Test-Connection.ps1` prints whichever one it authenticated
with:

```powershell
.\99-Cert-Cleanup.ps1 -KeepThumbprint "<thumbprint from 02>" -Execute
```

### List your certificates by hand

```powershell
Get-ChildItem Cert:\CurrentUser\My | Where-Object { $_.Subject -eq 'CN=QuarantineAgentPOC' } | Select-Object Thumbprint, NotBefore, NotAfter
```

### Check a certificate is CSP and not CNG

Empty output means CNG, which Exchange app-only auth rejects.

```powershell
(Get-ChildItem Cert:\CurrentUser\My | Where-Object { $_.Subject -eq 'CN=QuarantineAgentPOC' } | Select-Object -First 1).PrivateKey
```

### Drop the Exchange session

Useful if a connection goes stale mid-session.

```powershell
Disconnect-ExchangeOnline -Confirm:$false
```

### Check the current connection

```powershell
Get-ConnectionInformation | Select-Object Organization, UserPrincipalName, State
```

### Confirm a release actually took effect

```powershell
Get-QuarantineMessage -Identity "<guid1\guid2>" | Select-Object Subject, ReleaseStatus
```

---

## If something fails

| Symptom | Cause |
|---|---|
| `Install-Module` fails with `CommandAlreadyAvailable` | Needs `-AllowClobber` — the script already passes it |
| certificate / `AADSTS700027` | CNG certificate. Re-run step 5 with `-Force` |
| `AADSTS90002` tenant not found | Wrong domain — must be `.onmicrosoft.com` |
| `AADSTS700016` app not found | Wrong AppId in `config.ps1` |
| Insufficient privileges | Admin consent not granted on `Exchange.ManageAsApp` |
| Worked before, fails now | Certificate upload still propagating. Wait a few minutes |
| `Get-OrganizationConfig` not recognised | Not necessarily wrong — a correctly scoped role group excludes it. Step 6 checks the quarantine cmdlets directly |
| Step 7 returns nothing | Script checks whether anything at all is quarantined, so you can tell "no outbound DLP yet" from "can't see the queue" |
| Export works, no attachments listed | Message may genuinely have none, or they're encoded in a form the simple parser missed. Open the `.eml` from `out\` in Outlook to check |
