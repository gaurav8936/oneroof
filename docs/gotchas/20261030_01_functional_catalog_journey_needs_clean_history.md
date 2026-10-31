# The catalog test needs clean terminal history

**Status:** ACTIVE · **Date:** 2026-10-30 · **Project:** LAB-AE-OPEN-AGENTS

> **One line:** seed one archived terminal history row for the standard functional suite; an empty profile cannot test Resume, and an entire old test store carries stale selections.

With an empty synthetic profile the unchanged catalog journey failed because no History row existed to resume (56/57 passed). Copying the whole previous store introduced stale windows and live IDs, making later terminal-selection checks fail. Neither result proved a product regression.

Use a clean profile with exactly one archived, previously launched plain-terminal row, no active runtime ID and no saved windows. The session stays out of the active window but remains available in All sessions. The unchanged suite then passed 57/57 checks across 14 journeys. Keep the failed runs as evidence; do not weaken assertions or reset fixtures during read-only inspection.

See [hosted-agent acceptance](../reports/20261030_hosted-agents/README.md).
