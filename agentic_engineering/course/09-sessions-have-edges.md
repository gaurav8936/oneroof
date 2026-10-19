---
title: Sessions have a beginning and an end
summary: Open every session with a verified picture of where things stand, and close it so the next one can start cold.
---

# Sessions have a beginning and an end

## The cost of a cold start

A new session knows nothing about yesterday. Without help it re-reads files, guesses at what was done, and sometimes
redoes finished work or undoes it. A few minutes of structure at each end of a session saves far more than it costs.

## Open with a verified picture

At the start, read the newest handoff, then check it against reality: what does git say about each repository, what
is uncommitted, what is ahead of the remote? When the handoff and git disagree, git wins, and the difference is worth
mentioning.

## Close with nothing left loose

At the end, commit or clearly park every change, move any rule you learned into the shared docs, and write a handoff.
Then count a short checklist instead of guessing whether you are done.

## What a good handoff holds

The single next action first. Then the state of every repository in plain facts, what was finished and how to check
it, what is blocked on a person, what was left alone on purpose, and the commands that get a new session going.

## Skills for this lesson

where-are-we opens a session, last-call closes it, and next-session-handoff writes the bridge between them.
