---
name: bounded-loops
description: Make any repeated or self-paced agent work safe — a written goal, a machine-checkable stop condition, a cap on attempts and time, a report after every round, and a clean way to interrupt.
runtime: [shared]
triggers: [loop, keep trying, retry until, run until done, recurring task]
---

# bounded-loops — every loop knows how it ends

Before starting any loop (retry until green, poll a deploy, work through a list, a nightly job), write these five
lines at the top of the session or the job file:

```
GOAL:        what is true when we are done
CHECK:       the command or observation that proves it (exit 0, a count, a page)
LIMIT:       at most N rounds or T minutes, whichever comes first
EACH ROUND:  one line — round n, what changed, check result
ON LIMIT:    stop, list what was tried, ask (never "try something bigger")
```

## Rules

- **The check runs every round.** No round ends on "I think it works now".
- **Change one thing per round** so a result can be explained.
- **Same failure twice → change approach**, don't repeat the same attempt.
- **Never widen scope to escape a loop**: no deleting tests, loosening checks or skipping steps.
- **Waiting is not polling.** When waiting on something slow (a CI run, a deploy), check at the pace it changes, not
  every few seconds.
- **Interruptible.** A person can stop the loop at any round; the round log says exactly where it was.
