---
name: ask-before-irreversible
description: Sort every action into reversible or not, and pause for an explicit yes before anything that deletes data, rewrites shared history, deploys, spends money or reaches other people.
runtime: [shared]
triggers: [is this safe, before I delete, approval, confirm first]
---

# ask-before-irreversible — pause where undo is hard

## Two kinds of action

| Go ahead | Stop and ask first |
|---|---|
| Edit files, run tests, local commits | Delete files or branches you did not create |
| Create a branch or worktree | `git push --force`, `reset --hard` on a shared branch, rewriting history |
| Read logs, query read-only | Write to a production database, run migrations |
| Draft a message | Send email, Slack, issues or comments to other people |
| Build locally | Deploy, publish, release, change DNS or permissions |
| | Anything that spends money or changes billing |

## How to ask

One short message: **what** you want to do, **why**, **what it affects**, and **how to undo it** (or "cannot be
undone"). Then wait. A yes covers that action only; the next risky action gets its own question.

## Before deleting or overwriting

Look at the target first: list it, read it, check `git status`, and check whether anyone else (another session, a
teammate) has work there. If something unexpected is there, stop and report it rather than clear it.

## Never

- Never treat an earlier yes as permission for a different or bigger action.
- Never work around a block (a hook, a permission denial, a failing gate) by finding another route. Report it.
