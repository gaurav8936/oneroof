---
name: where-are-we
description: Session-open orientation — read the latest handoff, the shared READ-FIRST and every repo's recent git state, then say in one screen which thread to pick up and the first command.
runtime: [shared]
pair: last-call
triggers: [where are we, orient me, what's open, session start]
---

# where-are-we — open with a verified picture

The pair of `last-call`: it closes a session, this opens one. **Read-only**: it never commits, pushes or edits.

## Inputs (in this order)

1. `<shared>/docs/READ-FIRST.md` and the must-read list it names (find `<shared>` with `roof status`).
2. The newest file in `<shared>/docs/next-session-handoff/`: the authoritative "what's open".
3. Every repo in the workspace: branch, last commit subject and date, dirty count, ahead/behind its upstream:
   ```bash
   for r in $(find "$ROOF_WORKSPACE" -maxdepth 3 -name .git -type d -prune | xargs -n1 dirname); do
     printf '%s\t%s\t%s\t%s dirty\n' "${r#$ROOF_WORKSPACE/}" "$(git -C "$r" branch --show-current)" \
       "$(git -C "$r" log -1 --format='%cs %s' 2>/dev/null)" "$(git -C "$r" status --porcelain | wc -l | tr -d ' ')"
   done
   ```
4. `roof doctor` (one line: are the guard, memory pin and rulebook intact?).

## Output (one screen; if it can't be read in 30 seconds, cut it)

| Repo | Branch | State | Last work | Open / next |
|---|---|---|---|---|

Then at most five lines: **hot repos** (dirty, local-only, most recent) · **recommended pick-up** with its first
command · **blocked on you** · anything the handoff claims that git contradicts (flag it, don't fix it here).

If the user names a repo, go deep on that repo instead: its full handoff, its `README`/`CLAUDE.md`/`AGENTS.md`, its
folder layout with one line per folder, and the last 10 commits reconciled against the handoff.
