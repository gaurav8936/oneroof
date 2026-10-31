# One Roof help: Loops

**Status:** LIVE · **Date:** 2026-10-31

> **One line:** A loop repeats work until a check passes, or runs every night at a time you choose. One Roof runs the check and decides whether another round starts; the agent does the work in the loop's own worktree, never in your checkout.

## Make a loop

Open **View › Loops** (or type "Loops" in the command palette) and press **+ New loop**. The quickest way: write what you want under **Describe the loop** ("every night at 3 fix one bug per round until `bash tools/check.sh` passes") and press **Draft it**. An agent fills the form (without one, One Roof reads your words by rules); check each field, open **Preview the first run** to see exactly what would happen, then save. You can also **Start from an example** (grouped by kind: auditor, reporter, fixer …) or right-click a session and choose **Make This a Loop…** (its repo, objective and opening message become the draft). Each field says what it is for, with an example; Goal, Check and Round prompt are multi-line and grow when you drag their bottom edge, and the sheet keeps the size you give it. Set:

- **Name and goal**: what done looks like, in a sentence.
- **Repo**: a git repo inside your projects folder.
- **Agent** and model.
- **Check**: a shell command that exits 0 when the goal is met, for example `npm test`. Press **Test the check** to see it pass or fail now.
- **When it runs**: **Until done** (after Run now; optionally wait some minutes between rounds), **Nightly** at a time, **When quiet** (once none of your own sessions has been working or waiting on you for 15 minutes, optionally only between two hours, at most once a night; the card says *waiting for quiet*), or **On an event** (`linear.issue.created`, `woodpecker.pipeline.failed`, `git.push`, `oneroof.release`: `ae loops fire <event>` records it and roofd starts the loop within 30 s, once per event).
- **Limits**: rounds (default 8), time (default 3 hours), and stop when the same failure repeats (default twice).

## How a run goes

1. One Roof runs the check first. If it already passes, no agent is needed.
2. Otherwise it starts round 1: a session in the loop's worktree (`<repo>/.worktrees/loop-<id>`, branch `loop/<id>`), opening with the goal, the check and the check's last output. One Roof makes the worktree before the first check; if it cannot, the loop stops and says why, and no round starts. (A loop whose id already starts with `loop-` is not doubled: `loop-smoke` works in `.worktrees/loop-smoke` on `loop/smoke`.)
3. When the agent finishes, One Roof runs the check again.
4. It stops when the check passes (**Done**) or at a limit (**Stopped at a limit**: too many rounds, too long, or the same failure twice in a row). Every round, and why it stopped, is listed under **Rounds**.

When round 2 starts, round 1's session closes unless you are attached to it or it is asking something.

## Safety

- Loops never push, merge or deploy, and never touch your checkout. The work stays on branch `loop/<id>` for you to review.
- A round that needs permission shows on its loop as **Needs you**. Loop rounds are not sessions: they never appear in the session list, its counts, the session catalog or the Needs you place. The Loops page lists them under **Runs**; **Open ↗** shows a round's terminal (1.9.34, LAB-1933).

## Today: what loops staged for you

Loops never act on their own. What a run produces (commits on its branch, a staged PR, an issue, a proposal, a report) is written to the outcome ledger as *staged*, and shows in **Needs you** under **Loops · Today**, oldest first, grouped by loop, with its action right there:

- **Approve → open PR** (commits, a staged PR): One Roof records your approval, runs the gate (the loop's check on its branch, then an LLM judge on the diff), and only if both pass pushes `loop/<id>` and opens the PR. A failed gate keeps it in Today with the reason. Nothing is merged.
- **Approve** (proposal, issue) · **Apply** (a data update) · **Open** (the commit in Review changes, the PR or report link, the file) · **Dismiss** (with your reason).

A loop that stopped at a limit, or whose round asks something, is in Needs you too, as a loop item (never a session): **Run again**, **Open loop**, **Mark seen**. Loop items count in the Needs you badge.

On the Loops page each loop lists its **Outcomes** (approve or reject from the row), and the Outcomes card opens a loop. **Gallery** shows every kind of loop, what it produces, where its output goes, and a real sample from its runs.

## Your ae loops

Loops made with `ae loops new` (`<name>.loop.yaml` in the same folder) show here as **Mine**. `ae` owns the file and its schedule (`ae loops on`); One Roof shows it, runs it on **Run now** and opens the file to edit, but never starts it on its own.

## Controls

**Run now** · **Pause** / **Resume** · **Stop** (ends the run, leaves the round's session open) · **Pause all** · **Pin** (keeps a loop at the top) · **Delete** (removes the loop's files; keeps its worktree and branch).

## Where it lives

- `<shared folder>/loops/<id>/loop.json`: the loop's definition, written only when you edit it (fit for git). `state.json` (run state), `rounds.jsonl`, `ledger.sqlite` (outcomes) and `.events/`: written by runs, never committed. A loop.json from before 1.9.34 is split on first read and kept as `loop.json.pre-split.bak`.
- Loops run in roofd, checked every 30 seconds, with One Roof open or closed, while the Mac is awake. A missed nightly time is skipped until the next night.
