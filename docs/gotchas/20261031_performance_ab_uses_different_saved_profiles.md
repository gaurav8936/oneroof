# Performance A/B uses different saved profiles

**Status:** ACTIVE · **Date:** 2026-10-31 · **Project:** LAB-AE-OPEN-AGENTS / LAB-1898

> **One line:** freeze the same profile, script, binaries and conditions, and inspect individual trials before attributing a median hitch difference to a commit.

Original One Roof A/B profiles differed in saved pane state, archived sessions and feed count. A slow baseline trial overlapped the candidate. Matched-profile retests changed the Full/drag conclusion while leaving Focus/Sessions suspicious. This does not prove the integration safe: causation and release acceptance remain open. Keep profiled diagnostic trials separate from unprofiled timing trials. See [investigation](../reports/20261031_hosted-performance-investigation.md).
