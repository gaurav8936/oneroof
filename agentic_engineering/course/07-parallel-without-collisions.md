---
title: Parallel without collisions
summary: Running several agents at once works when each has its own working copy, its own files, and changes land one at a time.
---

# Parallel without collisions

## Why parallel is tempting

If one agent finishes a task in twenty minutes, four agents could finish four tasks in the same time. That is true
only when the tasks do not step on each other. Two agents editing the same file at once produce a mess that takes
longer to untangle than doing the work in order.

## Decide first: fan out or stay inline

Split work only when the pieces are truly independent and each is big enough to be worth the setup. A quick fix, or
anything where the next step depends on the last, is faster in a single session. The question to ask is: could each
piece be reviewed on its own?

## A separate working copy each

Git worktrees give every agent its own checkout of the same repository on its own branch. Agents cannot overwrite each
other's unsaved files, and you can throw a failed attempt away without touching anything else.

## Claim files, land one at a time

Before starting, give each task the list of files it may change, with no overlaps. When the tasks finish, merge them
one at a time, running the tests after each. If two pieces conflict, you find out at once and in one place.

## Skills for this lesson

fan-out-or-not helps decide whether to split. parallel-worktrees covers the mechanics, including the roof swarm
command in the kit.
