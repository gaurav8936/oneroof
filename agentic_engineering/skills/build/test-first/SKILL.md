---
name: test-first
description: Write the failing test that proves the change is needed, watch it fail for the right reason, then write the smallest code that makes it pass, then tidy up with the tests green.
runtime: [shared]
triggers: [test first, write the test first, tdd, red green]
---

# test-first — red, green, tidy

## Steps

1. **Find the test home.** Locate the project's test runner and an existing test close to the change. Match its
   style. Run the suite once to know the starting state (note any tests already failing; they are not yours).
2. **Write one failing test** for the behaviour you want, named after the behaviour ("rejects an empty cart"), not
   the function.
3. **Run it and read the failure.** It must fail *because the behaviour is missing*, not because of a typo, an import
   error or a wrong path. If it fails for the wrong reason, fix the test first.
4. **Write the smallest change** that makes it pass. Resist adding features the test does not ask for.
5. **Run the whole suite.** Everything that passed before still passes.
6. **Tidy** names, duplication and structure with the tests green. Run them again.
7. **Repeat** for the next behaviour. For a bug, the first test reproduces the bug.

## Report

For each behaviour: the test name, the failing output (one line), the passing run, and the files changed.

## Never

- Never change a test to make it pass unless the test itself was wrong, and say so if you do.
- Never skip or delete a failing test to get green.
- Never claim "tests pass" without the command and its output.
