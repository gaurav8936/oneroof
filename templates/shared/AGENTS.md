# Shared rulebook (every agent: Claude Code, Codex, Kimi, Hermes, …)

This file is the entry point to the rules every agent in this workspace follows. `CLAUDE.md` next to it is a symlink to
this file, so Claude and the `AGENTS.md` readers see the same text. **Read `docs/READ-FIRST.md` before you do anything
that deploys, deletes, or runs agents in parallel.**

## Standing rules

1. **Start inside `{{WORKSPACE}}`, nowhere else.** The launch folder decides which rules and which memory a session
   sees. Sessions started elsewhere are blocked (oneroof guard). Don't work around it.
2. **Durable facts go in `{{SHARED}}/docs/`.** If another agent would need it (a rule, a decision, a gotcha, the state
   of a piece of work), write it here, in the folder for its type. Private agent memory is a cache: it holds pointers
   and working notes, never the only copy of a rule.
3. **One copy of shared content.** Write shared material once, here, and link to it. Never paste a copy into a repo.
4. **Handoffs go in git.** End a session with the `handoff` skill; it writes into
   `{{SHARED}}/docs/next-session-handoff/`, where any agent can resume from it.
5. **Parallel work gets fences.** One git worktree per parallel worker; each shared file (schema, lockfile, shared
   types) has exactly one owner; fan-out is bounded (see `docs/standards/parallel-agents.md`).

## Where things are

```
{{SHARED}}/
  AGENTS.md  CLAUDE.md → AGENTS.md      this file
  docs/
    READ-FIRST.md                        the must-read list (keep it short)
    standards/                           rules that always apply
    decisions/                           why we chose X (dated; superseded, never edited)
    architecture/                        how things work
    runbooks/                            repeatable procedures
    references/                          pointers, glossaries, access notes (no secrets)
    gotchas/                             one failure mode per file: YYYYMMDD_<symptom>.md
    next-session-handoff/                session bridge files (newest = current)
```
