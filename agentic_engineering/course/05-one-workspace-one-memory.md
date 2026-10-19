---
title: One workspace, one memory
summary: Several agents stay consistent only when they start in the same place and read the same rules and notes.
---

# One workspace, one memory

## The quiet failure

Most coding agents find their instructions and their memory from the folder they start in. Start one session in your
home folder and another in your projects folder, and they read different rules and keep different notes. Nothing
warns you. The work just slowly drifts apart.

## One launch folder

Pick one workspace folder and start every agent there. One Roof and its kit enforce this with simple layers: the
shell moves new terminals into the workspace, wrappers move you before an agent starts, and a hook stops a session
that is running somewhere else.

## One rulebook

Keep a single shared rules file that every agent's entry file points to, plus a short must-read list. When you learn
a rule, it goes in that one place. Any agent, from any vendor, reads the same thing.

## Notes that live in git

Private agent memory is useful, but only that agent can see it. Anything another agent needs, such as handoffs,
decisions and gotchas, belongs in plain files in a shared docs folder under git. Then a different agent, on a
different account, tomorrow, can pick up exactly where the last one stopped.

## Skills for this lesson

where-are-we reads the shared notes at the start. next-session-handoff writes them at the end. repo-map keeps a map of
each repository that every agent can read.
