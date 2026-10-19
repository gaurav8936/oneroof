---
title: Shipping safely
summary: Move work from your branch to production through clear stages, with checks at each step and a way back.
---

# Shipping safely

## Stages, not a leap

Work moves through stages: your working branch, a shared integration branch that deploys to a staging site, and the
main branch that deploys to production. Each move is a deliberate step with its own checks, so a problem is caught as
early as possible.

## Let automation do the deploy

Hand-run deploys drift: one person remembers a step and another does not. Let pushes to each branch trigger the
pipeline, and keep the pipeline the only way changes reach a server. Your job is to promote, then confirm the result.

## Check after every hop

After each promotion, confirm the pipeline ran, the version on the site matches the commit you shipped, and a quick
smoke test passes. A deploy that reports success but serves the old version is a common, quiet failure.

## Always know the way back

Before you ship, know how to undo it: which commit to return to, and how long that takes. Prefer a revert commit over
rewriting shared history, so everyone's copy stays consistent.

## Skills for this lesson

ship-domain walks a change from your branch to production with a check at every stage.
