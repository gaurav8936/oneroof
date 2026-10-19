---
name: next-session-handoff
description: Write a paste-ready next-session handoff into the shared docs (git), so any agent — Claude, Codex, Kimi, Hermes — can resume cold from that one file.
runtime: [shared]
triggers: [handoff, write the handoff, next-session message, save state for next session]
---

# next-session-handoff — the session bridge

**One job:** a fresh session (a different agent, another account, you tomorrow) can act correctly from this file
alone. If it would have to re-derive what happened, the handoff isn't done.

## Where it goes

`<shared>/docs/next-session-handoff/YYYY-MM-DD_HHMM_<topic>.txt` (find `<shared>` with `roof status`; default
`~/Projects/_common`). Plain text, newest file = current. It lives in git, not in any agent's private memory: that is
what makes it readable by every agent. If the work centred on one repo, also commit a byte-identical copy to that
repo's `docs/next-session-handoff/` and check with `diff -q`.

## Structure (BLUF first; keep sections, write "none" when empty)

1. **WHERE WE ARE / NEXT ACTION** (first two lines): the single most important state and the one next step.
2. **Context**: one paragraph: what this work is and the constraints that frame it.
3. **Repo / branch state, derived from live git, never from memory:** per repo `branch · HEAD sha · ahead/behind
   the integration branch · dirty? · pushed?`. Say plainly which commits are LOCAL-only, PUSHED, or MERGED.
4. **Done**: each item with its artifact (sha, path, URL) and **how to verify it**.
5. **Pick up here**: numbered, priority-ordered, each with its first concrete command.
6. **Blocked on the owner**: decisions an agent must not make alone.
7. **Not done on purpose**: what was left alone and why (prevents rework and over-reach).
8. **Verify before acting**: the hard-won checks from this session.
9. **Resume commands**: copy-paste commands that re-establish and confirm state.
10. **Risks and rollback**: what is reversible and how.

```bash
# derive section 3 — per repo touched
git -C <repo> fetch -q origin
git -C <repo> branch --show-current; git -C <repo> rev-parse --short HEAD
git -C <repo> rev-list --count origin/main..HEAD      # ahead of the integration branch
git -C <repo> status --porcelain | wc -l               # dirty files
git -C <repo> ls-remote --heads origin "$(git -C <repo> branch --show-current)" | wc -l   # 1 = pushed
```

## Rules

- Dense and grounded: real shas, paths and commands; no "we made progress".
- Link to standards and gotchas in the shared docs instead of restating them.
- A rule you learned this session that another agent needs goes into `<shared>/docs/standards/` (or `gotchas/`), and
  the handoff links to it. The handoff is not the only copy of a rule.
