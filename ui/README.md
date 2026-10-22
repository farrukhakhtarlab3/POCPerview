# Triage console prototype

Interface prototype for both use cases. Open `triage-console.html` in a
browser — no server, no build step, no dependencies beyond a web font.

Also published as a hosted page:
**https://claude.ai/artifact/N4fbgcYbRVX1pphWcqCJ3B**
(private — share it from the page's Share menu before sending it to anyone)

## What it shows

**Quarantine release** — the queue with an agent verdict on each message, the
reasoning behind it, and attachments with classified document types. Assign to
a reviewer, approve or override.

**Insider risk alerts** — the same shape for IRM. Risk score, contributing
activity, verdict, assignment.

**Capability status** — every capability marked Proven, Partial or Unproven,
with the evidence or the gap. This is the honest view of where the POC stands.

## Two examples that carry the argument

**Quarantine item 2** is the approved payslip sent *alongside* a commercial
contract and a pricing schedule. An allow-list keyed on the payslip alone
releases all three. This is the case per-message verification exists for.

**Alert `i2` correlates with quarantine item `q1`** — the same payslip seen
from both solutions. Triaging it once, with one verdict, is the argument for
doing these two use cases together rather than as separate projects.

## Data

All invented. No tenant data appears anywhere in this file. Names, addresses,
documents and alerts are fabricated for demonstration.

## Status

A prototype of the interface, not a working client. It does not call Graph or
Exchange — the verdicts and classifications are illustrative. The PowerShell
scripts in the parent folder are the part that talks to the tenant.
