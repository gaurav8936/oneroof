# One Roof help: objectives

**Status:** LIVE · **Date:** 2026-10-20

> **One line:** an objective is a goal you type in; a planner agent you can watch writes a plan, you edit and approve it, and One Roof runs the steps as ordinary sessions, at most three at a time, in order.

## Goal

Bigger work should not need you to plan every session by hand, and nothing should run before you have read the plan. The planner is visible (a real terminal, not a hidden call), the plan is a file you can keep in git, and the running is plain and predictable: start the steps whose dependencies are done, read each step's "done" marker, start the next ones.

## 1. Write the objective

Press **⇧⌘O** (File › New Objective…), **+ New objective** on the Overview, or "New objective" in the command palette.

| Field | Example |
|---|---|
| Objective | Write a glossary for the docs site |
| Done when | `docs/glossary.md` defines session, objective, plan, sticker and project in one line each |
| Repo | docs-site |
| Project | `ENG-DOCS-03` (optional) |
| Urgency | Today · This week · Whenever |
| Budget | Light · Normal · Whatever it takes |
| Notes for the planner | anything it should know |

**Plan it** starts the planner now. **Save as draft** keeps it for later (Plan it is then on the objective's page).

## 2. Watch the planner

The planner is an ordinary Claude session named "Plan: " plus your title. It uses the `plan-objective` skill from your agentic engineering folder. It reads the repo, the newest handoff and the routing rules, writes a plan file and replies `PLAN READY`. It starts nothing.

- **Watch the planner** jumps to its terminal; answer it there if it asks something.
- The objective page fills in by itself when the plan file appears (checked every few seconds). **Check for the plan now** reads it at once.
- **Where the plan file goes:** in the project's docs folder (`docs/projects/<code>/` (older `docs/workstreams/<id>/` folders still work), in your shared folder, a `*-docs` repo or a repo's `docs/`), under `plans/<date>_<slug>.md`. Without a project it goes to `docs/plans/` in your shared folder. It is Markdown for people plus an `oneroof-plan` block for One Roof.

## 3. Read and edit the plan

The objective page shows a card per step: id, title, kind, cost, state, agent, account and model, what it waits for ("after s1"), its done-when and its prompt (the chevron shows the full prompt).

- **Change agent, account or model** on any card. **Suggest** on a card asks the router (rules plus each seat's remaining capacity) and shows its reason.
- **Route all steps** routes every step at once; a review step never goes to the same vendor family as the step that wrote the code.
- **Move** a step up or down, or **delete** it.
- **Risks** and **Questions for you** from the planner are listed under the steps.
- **Plan file** opens the Markdown in the viewer. In the ••• menu: **Re-plan (new planner session)**, **Reload plan from file** (after you edit the file by hand) and **Delete objective**.

Card edits change One Roof's copy of the plan, not the Markdown file. If you edit the file, use Reload plan from file.

## 4. Approve and follow the run

**Approve and run** starts every step whose dependencies are done, at most three at a time, each in its own session with the step's agent, seat, model and prompt. Each step agent writes a `.done` (or `.failed`) marker when its own done-when check passes, and the next steps start. Plans waiting for your approval are also listed in Decisions (⌘I).

- **Progress** shows as "2/5 done" with a bar; each card shows its session's live state and **Open session**.
- **Pause** stops new steps from starting (running ones keep going) and puts the plan back in review, so you can edit cards; **Approve and run** continues. **Resume** appears if a step failed.
- **Finished:** all steps done means the objective is done. Any failed step means the objective failed; read the marker, then Resume or Re-plan.
- **Red startup check:** running objectives pause with a message until the check is green.
- **Seat near its limit:** a step on a Claude or Codex seat that is nearly used up is asked to write a handoff at a safe point and continues on another agent ([Seats and routing](07_seats-router-and-on-device-model.md)).

## Worked example: a glossary

The objective "Write a glossary for the docs site" (budget Light) goes through the whole loop like this:

1. The planner writes `plans/<date>_write-a-glossary-for-the-docs-site.md`: one step, kind docs, Kimi (docs go to Kimi under the bundled routing rules), cost low, with a done-when check (`grep` finds the five terms).
2. The plan lists its risks (for example "the `docs/` folder does not exist yet") and any questions for you.
3. After you approve, Kimi writes `docs/glossary.md`, commits it, and writes the step's `.done` marker. The objective turns done.

## Steps without asking

The objective page has a switch, **Steps run without asking per command**. Off (the default), agents ask you before commands as usual. On, steps start in each agent's own auto mode: Claude auto mode, Codex approve-for-me, Kimi ask-when-needed, Gemini and Antigravity approve everything. It applies to steps started after you switch it.

## Good to know

- **Steps in the same repo run side by side** without separate worktrees, so keep parallel code steps on different files.
- **Objectives are on the Overview,** with "Plan ready · 3 steps" when a plan waits for your approval, or "2 of 3 steps" while it runs.
