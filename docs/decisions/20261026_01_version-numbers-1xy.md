# ADR · One Roof version numbers are always 1.x.y

**Status:** ACCEPTED · **Date:** 2026-10-26 · **Project:** LAB-ONEROOF-UI-REDESIGN · **Linear:** LAB-1209

> **One line:** from 1.0.0 on, every One Roof version has exactly three parts, 1.x.y: 1 is the major release, x the milestone, y a step inside that milestone.

## Context

Before 1.0, One Roof used `MAJOR.RELEASE.MILESTONE.FIX` (for example 0.5.1.2): a release project, its milestones, and a fourth part for fix builds. The v2 window (the 1.x UI redesign) is the first true version, so numbering restarts at 1.0.0 and gets simpler.

## Decision

- **1** = the overall major release. A new major (2.0.0) only by owner decision.
- **x** = the milestone (R1, R2 … or M1, M2, M3 …). Each milestone is its own minor version: M0 = 1.0, M1 = 1.1, M2 = 1.2 …
- **y** = a step inside the milestone: a bug-fix build, or a milestone broken into smaller releases (1.3.0, 1.3.1, 1.3.2 …).
- Always write three parts (1.3.0, never 1.3). No fourth part, no `-beta` suffix.
- `CFBundleVersion` (the build number) still goes up by one on every build.
- A full release follows every milestone (signed, notarized, both download pages, installed and verified), as before.

The 1.x UI redesign therefore ships as: 1.0.0 M0 baseline · 1.1.0 M1 window shell · 1.2.0 M2 session tabs and Plan · 1.3.0 M3 looks and sheets · 1.4.0 M4 places · 1.5.0 M5 settings, setup, help · 1.6.0 M6 menus, Learn, parity audit, v2 on by default · 1.7.0 composer and Grid · 1.8.0 Wall, seat routing, Learn Radio.

## Consequences

- `AppVersion.compare` already handles any number of parts; three-part versions need no code change.
- The release runbook's four-part rule is replaced by this one for 1.0.0 and later.
