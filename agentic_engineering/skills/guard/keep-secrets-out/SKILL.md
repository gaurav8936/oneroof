---
name: keep-secrets-out
description: Keep API keys, tokens, passwords and private data out of code, commits, logs, plans and prompts — check before committing, and know what to do when one leaks.
runtime: [shared]
triggers: [secrets check, did I commit a key, leaked token, scan for secrets]
---

# keep-secrets-out — the mistake you cannot take back

A secret pushed to a public repository should be treated as stolen within minutes, even if you delete it. Prevention
is the only cheap fix.

## Before each commit

1. `git diff --cached` and read it. Look for keys, tokens, passwords, private URLs, `.env` content, real customer
   data.
2. Quick scan of what is staged:
   ```bash
   git diff --cached | grep -nE '(api[_-]?key|secret|token|passw(or)?d|BEGIN [A-Z ]*PRIVATE KEY|sk-[A-Za-z0-9]{20,})' || echo clean
   ```
   If a dedicated scanner such as `gitleaks` or `trufflehog` is installed, run it too.
3. Make sure `.env*`, key files and local data folders are in `.gitignore`.

## Where secrets belong

In environment variables or a secrets manager, read at runtime. Commit an `.env.example` with names and no values.
Never in prompts, plans, handoffs, screenshots or logs; redact them as `sk-…abcd`.

## If one leaks

1. **Rotate it first**: revoke the key at the provider and issue a new one. Deleting the commit is not enough.
2. Then clean history if the repository is shared (this rewrites history: ask first, see `ask-before-irreversible`).
3. Check the provider's logs for use you did not make.
4. Write a short gotcha note on how it happened (`capture-gotchas`).
