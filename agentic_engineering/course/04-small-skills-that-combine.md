---
title: Small skills that combine
summary: Why many short, single-purpose skills beat one large instruction file, and how they chain into a workflow.
---

# Small skills that combine

## What a skill is

A skill is a short instruction file an agent loads when a task calls for it. It says what the skill is for, when to
use it, the steps, and what a good result looks like. Agents read the description first and open the full file only
when it fits, so keeping skills short keeps them cheap.

## One job each

A skill that does one thing well is easy to test, easy to fix and easy to reuse. "Open a session", "close a session",
"review someone else's change" and "plan an objective" are separate skills, not chapters of one manual. When one
breaks you fix one small file.

## Chaining

Small skills combine into a workflow. A day might go: where-are-we to get oriented, plan-objective to break the goal
into steps, test-first for each step, second-opinion before merging, ship-domain to release, and last-call to close.
Each skill hands a clear result to the next.

## Write skills from what you repeat

The best skills come from things you have explained to an agent three times. When you catch yourself typing the same
instructions again, turn them into a skill. Keep the language plain, include one example, and say what the agent must
never do.

## Skills for this lesson

Browse the skills folder in Learn. Every skill in this package is under a page long on purpose.
