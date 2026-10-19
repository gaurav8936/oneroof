---
name: fan-out-or-not
description: Decide whether a job should be split across several parallel agents or sub-agents, or done inline in one session — using independence, size, review cost and file overlap as the tests.
runtime: [shared]
triggers: [should we parallelize, fan out, spawn agents, split this up, sub-agents]
---

# fan-out-or-not — parallel only when it pays

Parallel agents save time only when the pieces are independent. Otherwise they cost more in merging and review than
they save. Answer these five questions before splitting.

| # | Question | Fan out if… |
|---|---|---|
| 1 | Can each piece be done without the others' results? | yes |
| 2 | Do the pieces touch different files? | yes, no overlap at all |
| 3 | Is each piece big enough (roughly 15+ minutes of agent work)? | yes |
| 4 | Can each piece be reviewed and tested on its own? | yes |
| 5 | Is there capacity for every agent at once? | yes |

**All five yes:** fan out, with `parallel-worktrees`. **Any no:** do it inline, in order, in one session.

## Sub-agents inside one session

A sub-agent is worth it for a wide, read-only search ("find every caller of this function across the repo") where
you only need the conclusion. It is not worth it for a one-file lookup or for edits; do those directly.

## Say the decision

Before starting, write one line: "Fanning out into 3 tasks (claims: a → src/api, b → src/ui, c → docs)" or
"Inline: steps depend on each other". It makes the choice reviewable.
