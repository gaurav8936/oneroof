---
name: ship-domain
description: Promote finished work from your working branch to staging and then production through the pipeline — pre-flight checks, one promotion per stage, verification after each hop, and a known way back.
runtime: [shared]
dependencies: [ask-before-irreversible]
triggers: [ship it, ship-domain, promote to production, release, deploy]
---

# ship-domain — one stage at a time, verified

Set the three branch names once per repository (defaults shown):

```
WORK=work        # where you and your agents commit
STAGING=develop  # deploys to staging on push
PROD=main        # deploys to production on push
```

A "domain" is a product: one or more repositories that ship together. Run the steps for each repository in it.

## 1. Pre-flight (stop on any red)

```bash
git fetch origin
git status --porcelain                                # clean working tree
git log --oneline origin/$STAGING..$WORK              # exactly what will ship; read it
<run the test suite>                                  # green, with output
```

Check that nobody else's unshipped commits are mixed in (in shared repos, look at the authors). Write a one-line
summary of what is shipping.

## 2. Work → staging

Open a pull request from a short-lived release branch cut from `$WORK` into `$STAGING`, or merge directly if that is
your team's rule. Wait for CI. Merge with a **merge commit**, not a squash: a squash can carry a "skip CI" marker from
one commit onto the whole release, so the deploy never runs.

## 3. Verify staging

The deploy pipeline ran and passed · the staging site reports the commit you merged (a version endpoint, a footer, a
build id) · a short smoke test of the main path passes. A green pipeline that still serves the old version is a
failure.

## 4. Staging → production

Production is an irreversible, outward-facing step: confirm you have approval (`ask-before-irreversible`) unless the
person has given standing permission to ship. Merge `$STAGING` into `$PROD` the same way, wait for the pipeline, and
verify production exactly as in step 3.

## 5. After

Bring `$WORK` level with `$PROD` (merge or fast-forward; never reset a branch that others may have pushed to without
checking `git log $PROD..origin/$WORK` first). Record what shipped, with commit ids and URLs, in the handoff.

## The way back

Know it before you ship: `git revert -m 1 <merge commit>` on `$PROD`, pushed through the same pipeline. Prefer a
revert over rewriting history.
