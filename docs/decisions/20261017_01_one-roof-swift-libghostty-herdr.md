# ADR · One Roof is a new Swift app that draws libghostty terminals on herdr sessions

**Status:** ACCEPTED · **Date:** 2026-10-17

> **One line:** One Roof is built new in Swift 6 (AppKit + SwiftUI), uses herdr 0.9.5 unmodified as the session runtime and libghostty from Ghostty v1.3.1 to draw each terminal, and reads each agent's account from its running process.

## Context

Running several agent subscriptions (two Claude accounts, Codex, Kimi, Gemini) across many identical terminal tabs gives no status, grouping or planning. A survey of 22 tools found none that detects agent and account from the running process, queues planned sessions, or groups work by workstream. The question: build new, or extend an open-source terminal? The recommendation was to build new on libghostty + herdr, subject to two spikes: S1 (account from the process) and S2 (libghostty showing a herdr session). Development moved to macOS 15.8.1 + Xcode 26 so libghostty could be used from the start.

## Decision

**Build One Roof as a new native app in `app/`: Swift 6, AppKit window with SwiftUI panels, libghostty terminals, herdr runtime, SQLite for planned sessions.** Each terminal surface runs `herdr agent attach <name>`; herdr owns the processes. Account comes from `sysctl(KERN_PROCARGS2)` on the PID herdr reports (`pane.process_info`). SwiftTerm stays a documented fallback behind the same terminal view, unused.

## Why

- **Both spikes passed on 2026-10-17.** S2: GhosttyKit built from Ghostty v1.3.1 with zig 0.15.2 in 90 s; a libghostty surface in One Roof renders a shell and an attached herdr agent (Claude, Codex, Kimi, Antigravity, Gemini), takes keyboard input, and draws in Metal. S1: One Roof labelled sessions Claude1/Claude2 from the process environment, and `/status` inside each confirmed the two different logins.
- **herdr already does the hard runtime work**: PTY ownership, agents surviving app quits, process-based detection of 24 agents, status (idle / working / blocked / done), worktrees, a 128-method socket API. Apache-2.0.
- **libghostty gives Warp-grade terminals** (GPU text, IME, mouse) under MIT, and Ghostty's own macOS app is a working reference for embedding it.
- **Licence freedom**: no GPL/AGPL code (cmux, Warp, Claude Squad), so One Roof can later go open or closed.

## Rejected

- Fork cmux (B) — GPL-3.0 and a fast-moving upstream; a fork drifts within weeks.
- Host on cmux with a sidebar (B′) — Plan B only; not needed since S2 passed.
- Electron/Tauri forks (Orca, Jean, Crystal) — xterm.js terminals, and Jean drives agents as headless chat.
- SwiftTerm as the main terminal — kept only as a fallback; libghostty quality is the point.

## Consequences

- Building needs Xcode 26, the Metal Toolchain and zig 0.15 (`app/scripts/build-ghosttykit.sh`); the 135 MB libghostty build lives outside the repo (`ONEROOF_GHOSTTY_DIR`), never in git.
- herdr is a runtime dependency (`brew install herdr`); One Roof starts the server itself, with account variables stripped.
- herdr panes inherit the server's environment, so One Roof checks the server for leaked account variables before every launch (restart if idle, otherwise refuse).
- herdr is pre-1.0 (protocol 22): One Roof shows a warning when the protocol changes.
- The first usable version shipped on this architecture the same night; capacity, routing and the Linear/tracker views build on it.
