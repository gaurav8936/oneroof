---
title: The right agent for the job
summary: Different agents and models have different strengths and limits; route each step on purpose and keep review independent.
---

# The right agent for the job

## Not all agents are the same

Agents differ in what they are good at, how fast they are, and how much of your plan they use up. A large model is
worth it for a hard design problem and wasteful for renaming a variable. Reading a long document is a different job
from writing tricky code.

## Route by the kind of work

Sort steps into kinds: research, design, code, review, test, docs and chores. For each kind keep a short, ordered list
of preferred agents. One Roof reads that list from a routing file in this package and suggests an agent for every step
of a plan. You can always override it.

## Respect capacity

Subscriptions have usage windows. When a seat is close to its limit, routing should skip it and use the next choice
rather than stall halfway through a task. One Roof watches each seat's remaining capacity and explains every
suggestion it makes.

## Review with a different agent

The agent that wrote a change is the worst one to review it. It shares the same blind spots. Send reviews to a
different agent, ideally from a different vendor, and ask it to point to specific lines rather than give general
impressions.

## Skills for this lesson

agent-routing holds the routing rules and roles One Roof uses. second-opinion runs an independent review.
