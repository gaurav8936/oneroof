# New profiles start every agent in Manual

**Status:** accepted · **Date:** 2026-11-01 · **Workstream:** LAB-ONEROOF-v2.0.3 (LAB-2169)

> **One line:** for the public release, a new One Roof profile starts every agent in Manual (it asks before it acts);
> a profile from before 2.0.3 keeps the Auto / Full defaults it had, written into it once.

## Context

Since LAB-1600 (10-29) every agent started in Auto, and since LAB-1935 (10-31) Antigravity in Full. Those were the
owner's own preferences. The 2.0.3 QA audit (LAB-2139) found that a stranger's first Gemini session would start with
`--approval-mode yolo`, Kimi with `--yolo` and Antigravity with `--dangerously-skip-permissions`, with no question asked.

## Decision

- `PermissionMode.defaultMode` is Manual for every agent (hosted agents were already Manual).
- Settings saved before 2.0.3 (`permissionDefaultsVersion` < 2) get the previous default written in for every local
  agent with no stored mode: Auto, Antigravity Full. The owner's Mac behaves exactly as before.
- Settings › Permissions and the help page are unchanged in how they work; the help text now says agents start in Manual.

Supersedes the default (not the per-agent mode design) in `20261029_01_permission-mode-per-agent.md` and
`20261031_01_full-permission-mode-antigravity-default.md`.

## Consequences

- A new user's agents ask before acting until the user picks Auto or Full.
- Tests: `test_LAB2169_newProfilesStartInManualOlderProfilesKeepAutoAndFull`.
