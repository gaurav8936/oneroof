---
name: plan-objective
description: Turn an objective into a visible, editable step plan for One Roof — steps, agent and model per step, dependencies, done-when checks and expected cost — written as Markdown plus a oneroof-plan JSON block.
runtime: [shared]
dependencies: [agent-routing]
triggers: [plan-objective, plan this objective, write a one roof plan]
---

# plan-objective — a plan you can read before anything runs

One Roof starts a **visible planner session** with this skill when you type an objective. The planner writes the
plan; you read and edit it in One Roof, approve it, and One Roof runs each step as its own agent session. Nothing runs
before approval, so plan honestly and keep it small.

## Inputs (in the opening message)

- **Objective**, **done when**, repo(s), workstream (optional), urgency (today · this week · whenever), budget
  (light = cheapest agents first · normal · max), notes.
- **PLAN FILE**: the absolute path to write. **RUN DIR**: where each step drops its done marker.

## Steps

1. **Read what every agent reads first**: the shared `READ-FIRST.md`, the repo's README and docs, the newest handoff
   for this work, recent `git log`, and any gotchas that match. Plan from the shared record, not from scratch.
2. **Size it.** One or two steps for a small objective, about eight at most for a large one. If it needs more, say
   so under questions and suggest splitting the objective.
3. **Pick an agent per step** with `agent-routing` (its `routing.json`): research and reading → a fast reading agent;
   hard code and design → the strongest model; routine code → a mid-size model; review → a *different* agent from
   the one that wrote the code; docs → a fast writer. Respect the budget.
4. **Write each step's prompt** as the full opening message that step's agent will get: what to do, which files, the
   done-when check, the commit format if it commits, and the marker rule below.
5. **Write the plan file** and stop. Reply with one line: `PLAN READY <path>`.

## The marker rule (every step prompt includes it)

> When the step is finished and its done-when check passes, write a short summary (what changed, how it was checked,
> what the next step must know) to `<RUN DIR>/<step id>.done`. If it cannot be done, write the reason to
> `<RUN DIR>/<step id>.failed`. Do not start other steps.

## Plan file format

````markdown
# Plan: <objective title>

**Status:** PROPOSAL · **Date:** <YYYY-MM-DD> · **Workstream:** <id or none>

> **One line:** <the objective and how it will be done>

## Steps
| # | Step | Agent · model | Depends on | Done when | Cost |
|---|---|---|---|---|---|
| s1 | … | kimi · default | — | … | low |

## Risks and questions
- …

```oneroof-plan
{"objective": "...", "done_when": "...",
 "steps": [{"id": "s1", "title": "...", "kind": "research", "agent": "kimi", "account": null, "model": null,
            "depends": [], "done_when": "...", "cost": "low", "skill": null, "repo": "/abs/path/to/repo",
            "prompt": "full opening message, including the marker rule with the RUN DIR"}],
 "risks": ["..."], "questions": ["..."]}
```
````

- `kind`: research · design · code · review · test · docs · chore
- `agent`: claude · codex · kimi · agy · gemini; `account`: a Claude seat name (e.g. "Claude1") or null
- `model`: e.g. "opus", "sonnet", "haiku", or null for the agent's default
- `cost`: low · medium · high, as a share of the seat's usage window, not dollars
- `repo`: an absolute path inside your workspace

## Never

- Never do the work yourself beyond reading: the plan is the whole job.
- Never invent repos, files or ticket keys; check they exist.
- Never put secrets in a plan.
