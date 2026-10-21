# Run sheet

Copy-paste sequence for the VDI. One command at a time — multi-line pastes get
mangled in the PowerShell console.

Background and troubleshooting are in [README.md](README.md).

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

Copy an `Identity` value. Format is `guid1\guid2`.

### 8. Look inside a message

```powershell
.\04-Inspect-Message.ps1 -Identity "<guid1\guid2>"
```

Lists the attachments it can see. This is what proves the classifier can tell a
payslip on its own from a payslip with something else attached.

### 9. Release test — dry run first

Sends nothing:

```powershell
.\05-Test-Release.ps1 -Identity "<guid1\guid2>"
```

Then for real — asks you to type `RELEASE`:

```powershell
.\05-Test-Release.ps1 -Identity "<guid1\guid2>" -Execute
```

Pick the message deliberately. Ideally one a reviewer had already decided should
be released, so the outcome is what would have happened anyway and only the
trigger differs.

---

## Two things to keep in mind

**Steps 6 to 8 change nothing.** Re-run them freely. Step 9 is the only one that
does anything irreversible.

**This repository is public.** `out/`, `*.eml` and certificate files are
gitignored. Everything the scripts export stays local — don't force-add anything
from `out/`.

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
