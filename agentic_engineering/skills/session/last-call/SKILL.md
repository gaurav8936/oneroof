---
name: last-call
description: Session-close ritual — sweep loose ends, move durable facts into the shared docs, write the handoff, and score readiness by counting a checklist. Every step runs, every time.
runtime: [shared]
dependencies: [next-session-handoff]
triggers: [last call, close the session, end of session, wrap up]
---

# last-call — close on green, not on hope

**Contract:** nothing important is left unsaved, undocumented or unflagged. last-call **fixes** what it safely can
(uncommitted work, a missing handoff, a stale index) and only *surfaces* what needs a human: anything outward-facing
(push, merge, deploy, delete a branch) or destructive.

## Steps (all mandatory, in order; a step with nothing to do still gets a row: `none — <why>`)

| # | Step | Evidence in the report |
|---|---|---|
| 1 | List every repo touched this session; for each: branch, HEAD, dirty count, ahead/behind | state table |
| 2 | Commit or explicitly park every dirty change (never push here) | commit list |
| 3 | **Lift durable facts into the shared docs.** Any rule, decision or gotcha learned this session that another agent would need → `<shared>/docs/<type>/`. Private memory keeps a pointer only | file list |
| 4 | Memory hygiene: the memory index (e.g. Claude's `MEMORY.md`) ≤ 150 lines, pointers only | line count |
| 5 | Run the `next-session-handoff` skill (don't hand-write a look-alike) | handoff path |
| 6 | `roof doctor` (launch guard, memory pin, rulebook still intact) | its last line |
| 7 | Checklist: one row per item above, green/red | table |
| 8 | Score = green rows / total rows, **counted**, never estimated | `n/N` |
| 9 | Self-audit (below) | ticked list |

**No pushes inside last-call**, even if "push" was approved earlier in the session. List unpushed commits under
"Remaining" and ask.

```
LAST-CALL SELF-AUDIT
[ ] 1 state table built from live git
[ ] 2 dirty work committed or parked (nothing silently left)
[ ] 3 durable facts moved to shared docs (list: __)
[ ] 4 memory index ≤ 150 lines (__ lines)
[ ] 5 next-session-handoff skill invoked (path: __)
[ ] 6 roof doctor run (result: __)
[ ] 7 every checklist item scored (rows: __)
[ ] 8 score counted (__/__)
[ ] 9 nothing pushed without approval given in this request
```
