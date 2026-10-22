# Changelog

## Unreleased

- **Resources: see what One Roof itself uses** (LAB-493). View › Resources (⇧⌘U, or Resources in the toolbar) shows
  One Roof's total memory and CPU with 10-minute charts, the Mac's memory, pressure and swap, the app and the roofd
  daemon, and every running session by window, heaviest first, with a bar against roofd's memory guard (warns at
  1 GB, ends the session at 2 GB). Click a session to go to it. The plan panel has a **Resources** tab for the
  selected session: memory and CPU now and over 10 minutes, the guard, and every process under it.
- **A session can work on several issues** (LAB-474). Add issue… (session menu, right-click, or the Ticket tab) adds
  an open issue or a new one at any point; the row shows `KEY +N`, the Ticket tab lists each one, and closing asks
  per issue. A commit that names an issue moves it to In Review on its own, once. If the agent is busy when you add
  one, the note waits and goes in as soon as it is back at its prompt.
- **New session no longer slides off the screen** (LAB-472): picking New bug made the bottom row too wide; it now
  wraps to two lines when it does not fit.

## 0.4.3 — roofd memory fix (21 Oct 2026)

- **roofd no longer eats the Mac's memory.** Each session's process kept every answer it gave the app, so a session
  open for a day grew to several GB and macOS froze. It now stays at a few MB, and as a safety net a session that
  passes 2 GB ends itself (noted in `roofd-memory.log` in roofd's folder) instead of taking the Mac down.

## 0.4.2 — a one-click session menu, and pasting images (21 Oct 2026)

- **The session menu is one click for everything.** Stickers are labels only, colours are swatches and emoji sit in the menu itself; the colourful menu has a row of buttons (Open, Next, Pin, Rename, Highlight) instead of tiles, and no Close.
- **Paste or drop screenshots into New session** (LAB-462): ⌘V or a drop attaches them as removable thumbnails; the opening message names them for the agent, and a new Linear issue gets them uploaded into its description.
- **A launched agent's terminal shows at once** (LAB-299), with a "Starting…" strip while your login shell and the agent start, instead of a blank pane for 2–3 s.

## 0.4.1 — closing things, and fixes (21 Oct 2026)

- **Closing a window works.** Tick "Yes, I'm sure" and press Close, and the window closes (it stayed open before).
- **An ✕ on every session row.** Point at a row (or select it) and click ✕: a running session asks first, then
  closes; a stopped one is removed, and File › Reopen Closed Session (⇧⌘T) brings it back.
- **Exited sessions look stopped.** Their rows are grey and faded until you point at or select them.
- **A second window no longer blinks** while attaching, and no longer shows the doors dialog on launch.
- **Sessions don't inherit self-test settings**, so One Roof opened from a terminal session starts normally.

## 0.4.0 — roofd, One Roof's own session manager (20 Oct 2026)

- **herdr is gone: nothing to install but your agents.** Sessions run in roofd, a small session manager inside the
  app. One terminal emulator end to end: real scrollback, native selection and copy, prompt marks, and keystroke echo
  about a hundred times faster than before.
- **Sessions outlive the app, and a crash costs only what it must.** Quit, update or reopen One Roof and every session
  comes back with its history; one session's crash never ends another.
- **Status from the agents themselves:** Claude's hooks, screen prompts and screen activity give Working, Needs you
  and Ready for all five agents, including first-run menus.
- **Tonight and Nightly run with the app closed** when scheduled runs are allowed; roofd sends the opening message once
  the agent is ready.
- **Steps you can rewind and explain.** The steps list at the top of a pane is capped at six (it scrolls); click a
  step to scroll the terminal back to it and read on, **Back to current** to return. The right panel's **Step review**
  has Claude's reading of the latest step (or the one you clicked): what was asked, what happened, decisions and risks.
  It is off until you switch it on in that box, since each reviewed step is one more model call.
- **Loops.** Repeat a session every 15 min to 4 h (right-click › Repeat, or When › Every): roofd launches it, or
  sends its message again when the agent waits, never mid-work, even with the app closed.
- **Paste images into a terminal.** ⌘V with a screenshot or copied image saves it and types its path, so the agent
  attaches it; files copied in Finder paste as full paths; images dragged in from a browser work too.
- **Linear projects, all of them.** One Roof reads every Linear project (code = the part of the name before " · ",
  like `ENG-CHECKOUT`; older `WS-` names still work), and "Workstream" is now called Project everywhere. The New work
  sheet has Team and Project pickers, tickets get Linear's Type label (Deliverable, Bug, Task, Spike, Decision), and
  a new project is created in Linear with its milestones before a Claude session sets up its docs and first tickets.
- **The New session sheet starts sessions on existing work.** ⌘N has **Team ▾ · Project ▾ · Issue ▾** pickers
  instead of kind tabs: pick an open issue and the session works on it; the **New issue** types and **New project…** are the
  last menu items, for work not in Linear yet. Status names are the same in the filter chips and the group headings
  (Needs you · Working · Ready · Idle · Exited, with meanings on hover), and the session shown in the terminal stands
  out in the sidebar with an accent outline and a left bar.
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
