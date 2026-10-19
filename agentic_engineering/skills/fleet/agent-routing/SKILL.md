---
name: agent-routing
description: Choose the agent and model for a piece of work by its kind (research, design, code, review, test, docs, chore), the remaining capacity of each seat, and the rule that a reviewer is never the author. Holds the routing.json and roles.json One Roof reads.
runtime: [shared]
triggers: [which agent, route this, who should do this, pick an agent]
---

# agent-routing — the right agent, on purpose

## The files

- `routing.json` — for each kind of work, an ordered list of agents (and models) to try, plus the usage threshold
  above which a seat is skipped. One Roof suggests an agent for every plan step from this file.
- `roles.json` — ready-made roles (a skill plus the agent that runs it) offered when you start a session.

Edit both to match the agents you actually have. One Roof re-reads them; nothing is cached.

## How to route a step by hand

1. **Name the kind.** research · design · code · review · test · docs · chore. If a step is two kinds, split it.
2. **Walk the list** for that kind in `routing.json`, top to bottom.
3. **Skip full seats.** If a seat has used more than `skip_above` of its 5-hour or 7-day window, take the next one.
4. **Keep review independent.** A review never goes to the agent that wrote the code; pick the next one on the list.
5. **Mind the budget.** Light budget: push the largest models to the end. Max budget: put them first for design,
   code and review.
6. **Say why** in one line, e.g. "code → claude opus on Claude2 (31% of its window); Claude1 near its limit".

## Changing the rules

Change the order when you notice a pattern (an agent keeps doing better at a kind of work), not after one good run.
Keep each list to three entries; more just hides the decision.
