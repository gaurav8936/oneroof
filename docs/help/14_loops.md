# One Roof help: Loops

**Status:** LIVE · **Date:** 2026-10-23

> **One line:** A loop repeats work until a check passes, or runs every night at a time you choose. One Roof runs the check and decides whether another round starts; the agent does the work in the loop's own worktree, never in your checkout.

## Make a loop

Open **View › Loops** (or type "Loops" in the command palette) and press **+ New loop**, or start from a template (**Fix until green**, **Nightly tidy**). Set:

- **Name and goal**: what done looks like, in a sentence.
- **Repo**: a git repo inside your projects folder.
- **Agent** and model.
- **Check**: a shell command that exits 0 when the goal is met, for example `npm test`. Press **Test the check** to see it pass or fail now.
- **When it runs**: **Until done** (after Run now; optionally wait some minutes between rounds) or **Nightly** at a time.
- **Limits**: rounds (default 8), time (default 3 hours), and stop when the same failure repeats (default twice).

## How a run goes

1. One Roof runs the check first. If it already passes, no agent is needed.
2. Otherwise it starts round 1: a session in the loop's worktree (`<repo>/.worktrees/loop-<id>`, branch `loop/<id>`), opening with the goal, the check and the check's last output.
3. When the agent finishes, One Roof runs the check again.
4. It stops when the check passes (**Done**) or at a limit (**Stopped at a limit**: too many rounds, too long, or the same failure twice in a row). Every round, and why it stopped, is listed under **Rounds**.

When round 2 starts, round 1's session closes unless you are attached to it or it is asking something.

## Safety

- Loops never push, merge or deploy, and never touch your checkout. The work stays on branch `loop/<id>` for you to review.
- A round that needs permission waits for you in **Decisions**; the loop shows **Needs you**.

## Controls

**Run now** · **Pause** / **Resume** · **Stop** (ends the run, leaves the round's session open) · **Pause all** · **Pin** (keeps a loop at the top) · **Delete** (removes the loop's files; keeps its worktree and branch).

## Where it lives

- `<shared folder>/loops/<id>/loop.json` and `rounds.jsonl`: plain files any agent can read.
- Loops run in roofd, checked every 30 seconds, with One Roof open or closed, while the Mac is awake. A missed nightly time is skipped until the next night.
