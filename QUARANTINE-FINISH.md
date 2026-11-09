# Finishing the quarantine findings

Three items were never measured. Two need no new access and can be done in one
VDI session. The third needs a permission that has not been requested yet.

One command per block — multi-line pastes get mangled in the PowerShell console.

> **Read this first.** A bug was found on 9 Nov 2026 and fixed in this version.
> `03` and `06` each took a single page of 100 records and reported the count as
> if it were the total. **Every "100 messages in 16 days" figure quoted so far is
> the page size, not the volume.** The real number is unknown until step 2 below
> runs. Make sure you are on current code before doing anything else.

---

## 1. Get the current code

**If the repository is private now**, the ZIP URL below returns 404 and
`git clone` will prompt for credentials. Either sign in to git on the VDI, or
make the repo temporarily public, pull, and set it back.

Download:

```powershell
Invoke-WebRequest -Uri "https://github.com/farrukhakhtarlab3/POCPerview/archive/refs/heads/main.zip" -OutFile "$env:USERPROFILE\POCPerview.zip"
```

Extract over the top of what is there:

```powershell
Expand-Archive -Path "$env:USERPROFILE\POCPerview.zip" -DestinationPath $env:USERPROFILE -Force
```

Move into it:

```powershell
cd "$env:USERPROFILE\POCPerview-main"
```

Clear the mark-of-the-web flag, or the scripts refuse to run:

```powershell
Get-ChildItem -Recurse | Unblock-File
```

Allow scripts for this window only:

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force
```

Confirm the connection and the role still work:

```powershell
.\02-Test-Connection.ps1
```

Expect `PASS` on all five quarantine cmdlets and
`Delete-QuarantineMessage correctly absent`. `Get-OrganizationConfig` failing is
correct — the scoped role excludes it.

---

## 2. True queue volume — the paging fix

Run the profile without `-Deep` first. It is fast, and it tells you whether the
queue is 100 messages or 2,000.

```powershell
.\06-Analyse-Queue.ps1
```

Watch the `page 1 +1000 running total 1000` lines. If paging stops at page 1
with a short page, 100 really was the whole queue. If it keeps going, the
sizing case changes.

Then the full 30 days, which is the service maximum:

```powershell
.\06-Analyse-Queue.ps1 -Days 30
```

**What this answers.** Quarantine and policy types, policy names, the outbound
DLP share of the whole queue, volume per day, top senders, recipient domains,
and how many messages were previously released, denied or left untouched. That
last group is the case-store seed, and the recipient domains are the consumer
providers the exemption logic has to recognise.

Aggregate counts only are written to `out\queue-profile-*.json` — no addresses,
no subjects, no content.

---

## 3. TNEF prevalence

This is the one that could reshape the attachment pipeline. Right now it is a
sample of one message.

Sample size depends on what step 2 reported. Twenty-five is enough to tell
"rare" from "half the queue"; fifty is enough to quote a figure with a straight
face.

```powershell
.\06-Analyse-Queue.ps1 -Days 30 -Deep -SampleSize 50
```

It exports each sampled message, checks the encapsulation, and discards it. The
content goes to memory and a temp file that is deleted immediately — nothing
lands in `out\` except the aggregate counts.

Expect it to take a few minutes. One export per sampled message.

**Read the result like this:**

| Output | Means |
|---|---|
| `No TNEF in the sample` | Attachment inspection works broadly. Finding 06 closes. |
| `TNEF affects roughly N%` and N < 25 | A minority. Decoder optional, handle as an exception path. |
| `TNEF affects roughly N%` and N >= 25 | Reshapes the design. Needs a decoder, or Exchange configured not to send TNEF externally. |

It also prints **attachment formats seen** — `.pdf`, `.xlsx`, `.docx` and so on.
That list is the "attachment formats and document categories worth analysing"
input the HLD asks Woodside to supply. Running this supplies it.

---

## 4. Attachment file recovery

Proves the individual files come back out, which is what a classification step
would take as input.

Get some identities. The console table truncates, so force a list:

```powershell
Import-Csv (Get-ChildItem .\out\quarantine-*.csv | Select-Object -Last 1).FullName | Select-Object -First 10 Subject, Identity | Format-List
```

**Pick a routine one.** Any message proves the same point, so there is no reason
to pull HR, medical or departure correspondence onto disk.

List what is inside without writing anything:

```powershell
.\07-Extract-Attachments.ps1 -Identity "<guid1\guid2>" -ListOnly
```

Three possible outcomes:

- **A table of filenames, types and sizes, each marked `extractable`** — that is
  the result. Finding 07's extraction half is proven.
- **`Attachments are bundled inside winmail.dat`** — TNEF. Try another identity;
  this script exits cleanly and immediately, so it is a quick filter.
- **`No attachment parts recovered`** — the message has none. Try another.

If all four or five you try are TNEF, stop and tell me — that is step 3's answer
arriving the hard way, and it is a bigger finding than this step.

Once one lists cleanly, write the files out:

```powershell
.\07-Extract-Attachments.ps1 -Identity "<guid1\guid2>"
```

They go to `out\attachments\`. **These are real attachments from real mail.**
They stay on the VDI, `out\` is gitignored, and delete them when you are done:

```powershell
Remove-Item .\out\attachments -Recurse -Force
```

---

## 5. The DLP shared mailbox — blocked on access

This one cannot be done today. It is a **required** MVP integration in the HLD,
it supplies the enrichment step, and the HLD's own risk register says the hard
part is unproven: release-request emails may not contain a stable quarantine
identifier.

It needs a third permission ask, separate from both existing app registrations:

| Item | Detail |
|---|---|
| Permission | `Mail.Read` as an **Application** permission on Microsoft Graph |
| Scoping | Exchange Online Application RBAC, restricted to the one DLP shared mailbox — not tenant-wide |
| Also needed | The shared mailbox address, and examples of release-request wording |

Tenant-wide `Mail.Read` reads every mailbox in Woodside and will not be granted,
nor should it be asked for. Application RBAC is the mechanism that narrows it to
a single mailbox, and asking for it that way is the difference between a quick
yes and a long review.

**What to establish once it is granted:** whether a release request can be
matched to a quarantine item at all, and on what key — sender address, subject,
timestamp proximity, or a required request template. If nothing stable exists,
the HLD needs a template, and that is a process change rather than a code
change.

---

## 6. Out of scope for this spike

Two HLD spike items are deliberately not covered here, so nobody records them as
oversights:

**Managed identity from an Azure resource.** The HLD prefers it over a
certificate. It needs an Azure subscription and a hosted resource, neither of
which exists for the POC. The certificate proves the same permission model; the
managed identity decision belongs to build, not to the spike.

**Running an attachment through Content Understanding.** Blocked on the
content-residency decision, not on engineering. Step 4 produces the input it
would take. Sending real attachment content to an Azure service needs agreement
on privacy, cost, latency and temporary storage, and that agreement does not
exist yet.

---

## What to send back

From step 2 and 3, the console output is enough — or
`out\queue-profile-*.json`, which carries no personal data and is safe to share.

From step 4, the filename and type table only. **Not** the files, and not a
screenshot that shows subjects, senders or recipients.

Three numbers close out the findings:

1. True outbound DLP volume over 30 days
2. TNEF percentage, and the sample size it came from
3. Whether attachment files were recovered from a non-TNEF message — yes or no
