---
title: Every task is a loop
summary: Good agent work runs in loops with a goal, an action, a check and a stop rule — not one long prompt.
---

# Every task is a loop

## Act, check, adjust

A good agent task is not a single request. It is a loop. Try something, check the result against the goal, adjust,
and go again. A compiler error, a failing test or a rendered page are all signals the agent can read without you.

## Give the loop a real check

The loop is only as good as its check. "Looks right" is not a check. "The test suite passes", "the page shows three
rows" or "the command exits with zero" are. If the check can run without a person, the agent can loop many times
while you do something else.

## Give the loop a stop rule

Every loop needs a way to end that is not "it ran out of ideas". Set a limit on attempts or time, and say what to do
when the limit is reached: stop, write down what was tried, and ask. An unbounded loop burns time and money and often
digs the hole deeper.

## Close the outer loop too

Above each task sits a bigger loop: what did we learn, and what should change next time? Writing a short note after a
failure, and reading those notes before the next task, is how a team of agents gets better instead of repeating the
same mistakes.

## Skills for this lesson

bounded-loops sets limits and exit rules for repeated work. test-first gives a loop the check it needs.
