---
name: second-opinion
description: Review a change, a plan or a document as an independent second agent — correctness first, then risk, then simplicity — with every finding tied to a file and line and a severity.
runtime: [shared]
triggers: [second opinion, review this, code review, review the plan]
---

# second-opinion — the reviewer is not the author

Run this skill in a **different agent** from the one that produced the work, ideally from a different vendor. Same
agent, same blind spots.

## Steps

1. **Get the scope.** For code: `git diff <base>...HEAD` and `git log --oneline <base>..HEAD`. For a plan or doc: the
   file, plus the goal it serves.
2. **Read the goal first** (spec, ticket, objective), then the work. Judge the work against the goal, not your taste.
3. **Look in this order:**
   1. Correctness: does it do what was asked? Edge cases, error paths, off-by-one, empty and large inputs.
   2. Risk: data loss, security, secrets, irreversible steps, breaking changes for callers.
   3. Tests: does a test prove the change? Would it fail without it?
   4. Simplicity: dead code, duplication, a simpler way to get the same result.
4. **Check before you claim.** Run the tests or the snippet when you can. A finding you could not confirm is marked
   *unconfirmed*.
5. **Write findings**, most severe first:

```
[high] src/cart.ts:42 — total is negative when a coupon exceeds the price. Repro: … Fix: clamp at 0.
[low]  src/cart.ts:10 — unused import.
```

6. End with a verdict: **ship**, **ship after fixes** (list them), or **rework** (why).

## Never

- Never rewrite the work yourself unless asked; review it.
- Never pad the list with style nits to look thorough. No findings is a valid result.
