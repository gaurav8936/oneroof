---
name: show-the-evidence
description: Back every claim in a report with something the reader can open — a file and line, a commit, a command with its output, a screenshot — and label anything unverified as a guess.
runtime: [shared]
triggers: [show the evidence, cite it, prove it, receipts]
---

# show-the-evidence — every claim points somewhere

A report is only as trustworthy as its weakest unsupported sentence. This skill applies to any summary an agent writes:
a finished task, a bug analysis, a review, a status update.

## The rule

Each factual claim carries one of:

| Evidence | Looks like |
|---|---|
| File and line | `src/cart.ts:42` |
| Commit | `a1b2c3d` (with subject) |
| Command and result | `npm test` → `48 passed, 0 failed` |
| Artifact | a screenshot path, a log file, a URL |

A claim you could not check is written as **Guess:** … with the reason it could not be checked.

## Steps

1. Draft the report.
2. Go sentence by sentence. For each claim, attach evidence you actually looked at *in this session*. Re-run a command
   rather than quote an old result.
3. Downgrade anything you cannot support to **Guess:**, or remove it.
4. Put the most important finding first, with its evidence.

## Never

- Never cite a file or line you did not open.
- Never write "all tests pass", "works" or "fixed" without the command and its output.
- Never paste secrets into evidence; redact them.
