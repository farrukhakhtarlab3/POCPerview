# Quarantine Triage POC

Technical feasibility test for the email quarantine support agent.

**The question:** can a script read Microsoft Defender's outbound DLP quarantine,
see inside the messages, and release one — all under an *application* identity
with no human signed in?

The release half is the real unknown. Microsoft documents app-only auth for
Exchange Online PowerShell, and doesn't list the quarantine cmdlets among the
unsupported ones — but never confirms them either. The answer decides whether
this becomes **automated triage** or **an assistant that recommends and leaves
the action to a person**.

---

## ⚠️ This repository is public

Never commit anything exported from the tenant. `out/`, `*.eml` and all
certificate files are gitignored — leave it that way.

Everything the scripts export goes to `out/`, which stays local.

---

## Run these in order

Every script is safe to re-run. **Only step 5 changes anything.**

| Step | Script | Does | Changes anything? |
|---|---|---|---|
| 0 | `00-Install-Prereqs.ps1` | Installs the Exchange module | No |
| 1 | `01-New-Certificate.ps1` | Creates the auth certificate | Local only |
| 2 | `02-Test-Connection.ps1` | Proves auth + which cmdlets you have | No |
| 3 | `03-Get-QuarantineMessages.ps1` | Lists the queue | No |
| 4 | `04-Inspect-Message.ps1` | Reads inside one message | No |
| 5 | `05-Test-Release.ps1` | **Releases a message** | **Yes** |

---

## Step 0 — Get the code onto the VDI

Open **PowerShell** (Search → `powershell`). No admin needed.

```powershell
cd $env:USERPROFILE
git clone https://github.com/farrukhakhtarlab3/POCPerview.git
cd POCPerview
```

No git on the VDI? Download the ZIP from GitHub and extract it instead.

If scripts refuse to run:

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force
```

Process scope only — it resets when you close the window.

---

## Step 1 — Install the module

```powershell
.\00-Install-Prereqs.ps1
```

Expect `PASS Installed: 3.x.x`.

Uses `-AllowClobber`, which is required — `PackageManagement` wants to override
`Find-Package` / `Install-Package` and is blocked without it.

---

## Step 2 — Certificate

**If your certificate is already created and uploaded, skip this.**

```powershell
.\01-New-Certificate.ps1
```

It detects an existing certificate and stops rather than making a second one.
Only the certificate uploaded to the app registration can authenticate — making
a new one silently breaks things.

Starting over:

```powershell
.\01-New-Certificate.ps1 -Force
```

Then send the `.cer` to the tenant admin to upload, and wait for confirmation.

> **Why `-KeySpec KeyExchange`:** it forces a legacy CSP provider. Windows
> defaults to CNG, which Exchange app-only auth rejects — and the failure
> surfaces much later with an error that never mentions certificates.

---

## Step 3 — Prove the connection

```powershell
.\02-Test-Connection.ps1
```

Connects, then checks each cmdlet you should have:

```
PASS  Get-QuarantineMessage
PASS  Get-QuarantineMessageHeader
PASS  Preview-QuarantineMessage
PASS  Export-QuarantineMessage
PASS  Release-QuarantineMessage
PASS  Delete-QuarantineMessage correctly absent.
```

Anything missing means the role group needs it added — better to know now.

**If connection fails:**

| Error | Cause |
|---|---|
| certificate / `AADSTS700027` | CNG certificate — re-run step 2 with `-Force` |
| `AADSTS90002` tenant not found | Wrong domain — must be `.onmicrosoft.com` |
| `AADSTS700016` app not found | Wrong AppId in `config.ps1` |
| Insufficient privileges | Admin consent not granted |
| Worked a minute ago, now doesn't | Cert upload still propagating — wait and retry |

`Get-OrganizationConfig` failing is **not** necessarily a problem. If the role
group is correctly scoped to quarantine only, that cmdlet is outside it. The
script checks the quarantine cmdlets directly instead.

---

## Step 4 — Read the queue

```powershell
.\03-Get-QuarantineMessages.ps1
```

Lists outbound DLP quarantine from the last 16 days and writes a CSV to `out\`.

Wider window (service max is 30 days):

```powershell
.\03-Get-QuarantineMessages.ps1 -Days 30
```

**Nothing returned?** The script automatically checks whether *anything* is in
quarantine. If other types show up, read access works and there's simply no
outbound DLP quarantine — that's a finding about the tenant, not a fault.

Copy an `Identity` value for the next step. Format is `guid1\guid2`.

---

## Step 5 — Look inside a message

```powershell
.\04-Inspect-Message.ps1 -Identity "<guid1\guid2>"
```

This answers the question the classifier depends on. It pulls metadata, headers
and the full message via `Export-QuarantineMessage`, then lists the attachments
it can see.

Metadata alone can't distinguish a payslip on its own from a payslip bundled
with a confidential document — and that's the case the whole project exists to
catch. If this step shows attachment names, the classifier has what it needs.

The `.eml` is saved to `out\` and is openable in Outlook. Metadata only, no file
written:

```powershell
.\04-Inspect-Message.ps1 -Identity "<guid1\guid2>" -NoSave
```

---

## Step 6 — The decisive test

**This delivers a real email. It cannot be undone.**

Dry run first — shows what would happen, sends nothing:

```powershell
.\05-Test-Release.ps1 -Identity "<guid1\guid2>"
```

Then for real:

```powershell
.\05-Test-Release.ps1 -Identity "<guid1\guid2>" -Execute
```

You'll be asked to type `RELEASE` to confirm.

**Choose the message deliberately** — ideally one a reviewer had already decided
should be released. Then the outcome is identical to what would have happened
anyway, and only the trigger differs.

The attempt is journalled to `out\release-test-*.json` either way. The result is
the deliverable:

| Outcome | Means |
|---|---|
| Succeeds app-only | Autonomous design holds — the agent can act |
| Fails app-only, works interactively | Agent recommends, human clicks. Still useful, different pitch |
| Fails both ways | Likely a role problem, not an API limit — check with the tenant admin first |

---

## Files

```
config.ps1                      AppId, tenant domain, cert subject
Common.ps1                      Shared helpers (not run directly)
00-Install-Prereqs.ps1          Module install
01-New-Certificate.ps1          Certificate creation and export
02-Test-Connection.ps1          Auth + cmdlet availability
03-Get-QuarantineMessages.ps1   List the queue
04-Inspect-Message.ps1          Read inside one message
05-Test-Release.ps1             Release test (gated)
out/                            Exports and logs — gitignored
```

## Configuration

In `config.ps1`. None of it is secret — the credential is the certificate, whose
private key never leaves the machine that created it.

| Setting | Value |
|---|---|
| AppId | `9bce4be6-943d-4f0b-b284-4fdbd25a4dfa` |
| Organization | `woodsideenergy.onmicrosoft.com` |
| Certificate subject | `CN=QuarantineAgentPOC` |

The certificate is found by subject, not a hard-coded thumbprint — regenerating
it doesn't mean editing scripts.
