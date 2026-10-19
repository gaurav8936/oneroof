---
name: repo-map
description: Write or refresh docs/codebase-map.md — what the repository is, how to run it, its entry points, a one-line-per-folder tour, and the invariants that must not break — so any agent can orient in one read.
runtime: [shared]
triggers: [repo map, codebase map, map this repo, orient me in this codebase]
---

# repo-map — one page every agent reads first

## Steps

1. **Read before writing**: README, CLAUDE.md or AGENTS.md, the package or build file, the CI workflow, and the
   top-level folders. Run the app or tests once if it is cheap, so the "how to run" section is true.
2. **Write `docs/codebase-map.md`** with these sections, in this order:
   - **What it is**: two sentences.
   - **How to run**: install, run, test; ports; required environment variables (names only).
   - **Entry points**: the main executable(s), routes or commands, with paths.
   - **Folder tour**: one line per top-level folder and per important module: what it holds, what it does.
   - **Data and state**: where data lives, schemas, caches, what is generated.
   - **Invariants**: things that must stay true ("all writes go through `db/`", "never call the network in tests").
   - **Updated**: date and the commit the map was checked against.
3. **Keep it under about 150 lines.** Link to deeper docs instead of copying them.
4. When refreshing, diff the folder list against the map and fix every line that drifted; don't append.

## Never

- Never describe a folder you did not look in.
- Never include secrets, internal hostnames or personal data.
