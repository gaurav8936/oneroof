---
title: Trust comes from evidence
summary: Accept agent work on proof — tests, file and line references, command output — never on how confident it sounds.
---

# Trust comes from evidence

## Confidence is not evidence

Agents write fluently whether they are right or wrong. A summary that says "all tests pass" is a claim. The test
output is evidence. Build the habit of asking for the evidence, and of giving it when you report back yourself.

## Tests first

Writing the failing test before the code does two things. It pins down what "working" means before anyone is
attached to a solution, and it gives the agent a check it can run on its own. When the test turns green, you have
proof, not a promise.

## Point to the receipts

Every claim in a report should point to something you can open: a file and line, a commit, a command and its output,
a screenshot. If a claim cannot point to anything, mark it as a guess. This one rule removes most made-up answers.

## Gates before anything you cannot undo

Some actions are easy to reverse and some are not. Deleting data, rewriting shared history, deploying to users or
sending a message to other people need a pause and an explicit yes. Make the pause part of the process, not a matter
of luck.

## Skills for this lesson

test-first, show-the-evidence and ask-before-irreversible. keep-secrets-out covers the one kind of mistake that is
hardest to take back.
