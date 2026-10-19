---
name: write-the-spec
description: Before any code, write a one-page spec — the problem, what done looks like as checks anyone can run, what is out of scope, and the open questions — and get it approved.
runtime: [shared]
triggers: [write the spec, spec this, define done, what does done look like]
---

# write-the-spec — agree on done before anyone builds

Agents build whatever they are asked for, fast. A spec makes sure it is the right thing. Keep it to one page.

## Steps

1. **Restate the problem** in two or three sentences, in the user's terms, not the code's. Who has it, and what
   happens today?
2. **Write the done-when checks.** Each is something anyone can run or see: a command that must exit 0, a test that
   must pass, a page that must show a specific thing. Three to seven checks. No "works well" or "is clean".
3. **List what is out of scope.** The nearby things you will *not* do. This stops the work from growing quietly.
4. **Name the constraints**: files or modules that must not change, performance or cost limits, compatibility.
5. **List open questions**, each with your recommended answer, so a reviewer can approve with one word.
6. **Save it** next to the work (e.g. `docs/specs/YYYYMMDD_<topic>.md`) and ask for approval. Do not start building
   until the checks are agreed.

## Template

```markdown
# Spec: <title>
**Problem:** …
**Done when:**
- [ ] `npm test -- cart` passes, including the new test for empty carts
- [ ] …
**Out of scope:** …
**Constraints:** …
**Open questions:** 1. … (recommend: …)
```

## Never

- Never write implementation steps here; that is the plan's job (`plan-objective`).
- Never leave a check that only a person's opinion can settle.
