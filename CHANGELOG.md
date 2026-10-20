# Changelog

## 0.4.0 — roofd, One Roof's own session manager (unreleased)

- **herdr is gone: nothing to install but your agents.** Sessions run in roofd, a small session manager inside the
  app. One terminal emulator end to end: real scrollback, native selection and copy, prompt marks, and keystroke echo
  about a hundred times faster than before.
- **Sessions outlive the app, and a crash costs only what it must.** Quit, update or reopen One Roof and every session
  comes back with its history; one session's crash never ends another.
- **Status from the agents themselves:** Claude's hooks, screen prompts and screen activity give Working, Needs you
  and Done for all five agents, including first-run menus.
- **Tonight and Nightly run with the app closed** when scheduled runs are allowed; roofd sends the opening message once
  the agent is ready.
- Agents typed into a One Roof terminal still show as that agent. Agents started in other terminal apps are no longer
  listed; Copy attach opens any One Roof session from another terminal.

## 0.3.1 — signed and notarized

- **The app is signed with an Apple Developer ID and notarized by Apple.** It opens on first launch like any other
  app: no "cannot verify" warning, no Privacy & Security › Open Anyway step.

## 0.3.0 — first public release

- **One Roof app (macOS 14+, Apple silicon).** libghostty terminals on herdr sessions for Claude Code, Codex, Kimi,
  Gemini CLI and Antigravity; live status, stickers, grouping, Board and Launchpad; planned sessions; objectives that
  are planned by a visible planner session and run step by step after approval; seat capacity and agent routing with
  an optional on-device classifier; code review panel, split panes, roof windows; Learn with a narrated course.
- **First-run setup.** Choose your projects folder, shared folder and agentic-engineering folder; see which agents are
  installed and signed in. Everything is a setting; nothing assumes a particular workspace layout.
- **Agentic engineering starter set** (`agentic_engineering/`): 17 skills and 12 narrated lessons, bundled with the app.
- **The kit (`roof`).** One launch folder, one memory, one rulebook for every agent; `roof swarm` for parallel tasks in
  git worktrees with file claims, timeouts, retries and one-at-a-time merging.
- **Terminals:** drag to select, ⌘C / ⌘V, right-click Copy · Paste · Select All · Clear, drop a file to type its
  path; Option sends the mouse to the program. Checked before every release with `tools/terminal-basics.sh`.
- The app download is not yet signed with an Apple Developer ID: allow it once on first launch (macOS 15+: System Settings › Privacy & Security › Open Anyway; macOS 14: right-click › Open).
