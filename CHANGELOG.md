# Changelog

## 0.5.2.1 — round 2 fixes (23 Oct 2026)

Two things in 0.5.2 did not work on a real Mac. This fix build makes them work.

- **Loops work in their own worktree from the first check** (LAB-677). In 0.5.2 roofd read every command's result as
  "success", so the loop's worktree was never made, its first check failed with "Folder not found", round 1 started in
  a folder that did not exist, and a failing check could have counted as a pass. roofd now reads real exit codes, makes
  and checks the worktree before the first check, and never starts a round outside it. A loop whose id starts with
  `loop-` no longer gets a doubled `loop-loop-` folder.
- **Get the model is in Settings › Foundations too** (LAB-675). In 0.5.2 the button showed only on the Foundations
  check; the Settings model row now has it, and the folder rows no longer do.

## 0.5.2 — loops, notifications, a model you may use for anything (23 Oct 2026)

Round 2 of One Roof 0.5.

- **Loops** (LAB-86). A new Loops screen (View › Loops, or "Loops" in the command palette) for work that repeats
  until a check passes, or runs every night. Give a loop a goal, a check command (exit 0 = done), an agent and limits
  (default 8 rounds, 3 hours, stop when the same failure repeats twice). One Roof runs the check and decides whether
  another round starts; the agent works in the loop's own worktree (`<repo>/.worktrees/loop-<id>`), never in your
  checkout, and nothing is pushed or merged. Loops run with One Roof open or closed. A round that asks permission shows
  in Decisions. **Test the check** before you save; start from **Fix until green** or **Nightly tidy**. Help › Loops.
- **Desktop notifications** (LAB-197). One Roof tells you when an agent needs you, when one finishes its turn, and
  when a command that ran longer than 30 s finishes in a terminal you are not looking at; programs' own notifications
  (OSC 9 and 777) come through too. Click one to jump to the session. Turn each kind on or off in Settings › General.
- **Run in Terminal** (LAB-598). Select a command in a terminal, right-click › Run in Terminal: One Roof types it into
  the agent's own run terminal (a shell in the same repo, in a small floating window) and you press Return to run it.
  One run terminal per agent, listed under it; **Back to agent** returns you.
- **Issue quality bar** (LAB-533). Pick issues marks issues that are missing what their type needs (for a bug: steps
  to reproduce, expected vs actual, where seen) as **not ready**, with a filter chip; the Ticket tab shows what is
  missing. Help › Issue quality bar.
- **The on-device model is now Qwen3 1.7B (Apache-2.0)** (LAB-673, LAB-674), replacing Arch-Router 1.5B, whose licence
  did not allow commercial use. On 38 test sentences it picks the right task kind 37 times (Arch-Router: 32), in about
  0.15 s. If Settings still points at Arch-Router it keeps working, with a note about its licence.
- **Get the model** (LAB-675). One click in Settings › Foundations, or on the Foundations check, downloads the model
  (1.1 GB), checks its size and SHA-256, and installs it with its licence. Stop and continue later; a file that does
  not match is thrown away.
- Captions ask the model for a fixed reply shape, so fewer are rejected. Resources names the model a leftover
  llama-server is running. Third-party notices now ship in the app.

## 0.5.1.1 — round 1 fixes (23 Oct 2026)

Two things in 0.5.1 did not work on a real Mac. This fix build makes them work.

- **The window name really is big and bold now** (LAB-590). In 0.5.1 the name at the top showed in plain, regular
  text with no colour. It is now large and bold, drawn in the window's colour with a small swatch when it has one;
  click it for Rename, Colour and the other windows.
- **Subagents show up in Overview and Subagents** (LAB-652, LAB-595). One Roof now finds each Claude session's exact
  conversation from its running claude process, instead of matching titles that rarely agree, and reads every
  subagent's own file, so subagents from early in a long session are found too. A subagent started in the background
  no longer shows as finished the moment it starts.

## 0.5.1 — window names, formatted files (23 Oct 2026)

The first release of One Roof 0.5 (round 1 of 5). It also carries the two fixes that were waiting for 0.4.11.

- **Each window has a big, bold name and its own colour** (LAB-509, LAB-590). Click the window's name at the top (or
  use Window › Rename Window… and Window › Window Colour). A coloured window gets a tinted title bar with the name and
  a stripe in that colour, so several windows are easy to tell apart. Mission Control and the Window menu show the
  name. A window with no colour looks as before.
- **Every window shows which One Roof is running** (LAB-526): "One Roof 0.5.1 (15)" next to "window N of M"; click it
  for these release notes. The sidebar footer shows roofd's real version instead of a stale "roofd 0.4.0", and
  quietly notes "older than app" while a roofd from an older One Roof is still running.
- **Four pastel themes** (LAB-601): Mint, Sky, Lavender and Peach, for any panel and the terminal, beside Daylight,
  Graphite and Midnight (Settings › Appearance or View › Theme). They turn Midnight in Dark Mode when following macOS.
- **Markdown opens formatted** (LAB-479). A `.md` file shows as a proper page in the centre panel: headings, nested
  and task lists, tables, coloured code blocks with Copy, quotes and images next to the file. Links to other files
  open in the viewer, `#links` jump to the heading, web links open in your browser. **Preview | Source** at the top
  switches to the editor and back; the preview shows unsaved edits.
- **HTML opens like a browser page** (LAB-480). `.html` files render in the centre panel with their CSS, scripts and
  images (relative paths across the repo work). Clicked web links open in your browser. **Preview | Source** edits
  the page, and ↻ reloads it from disk.
- **Subagents hang under their agent in Overview** (LAB-595). Each session in a window card shows the subagents it
  started, joined to it by tree lines, with a status dot, what each is doing and how long it has run. Click one to
  open its trace.
- **Settings › Allow scheduled runs says what it does** (LAB-285): roofd starts Tonight, Nightly and repeating
  sessions with One Roof open or closed. Leftover code for an old launchd scheduler that was never used is gone.
- **Browser tabs by name** (LAB-554). In Resources › This Mac, open Chrome (or Brave, Edge, Arc, Vivaldi, Opera,
  Safari) and press **Show tab names**: its open tabs are listed by site with their titles, and clicking one brings it
  forward. macOS asks once whether One Roof may control the browser. Memory per tab stays in the browser's Task
  Manager (⇧Esc), because macOS does not say which process is which tab.
- **A force-quit no longer leaves the local model running** (LAB-549). The on-device model (llama-server) now runs
  under a small watchdog that stops it within about 2 seconds of One Roof ending, however it ended: Quit, Force Quit,
  a crash. One that an older version left behind counts in One Roof's figures at the top of Resources, and the model
  is restarted if it ever grows past 3 GB (one grew to 8.4 GB over a day on 22 Oct).

## 0.4.10 — the whole Mac in Resources (22 Oct 2026)

- **Resources covers the whole Mac** (LAB-544). A new **This Mac, by app** card lists every app with its memory and
  CPU; open one to see its processes, with Chrome's (and other Chromium apps') helpers named: tab or site, extension,
  GPU, network … **Quit** an app or **End** a process from there, after a confirmation. One Roof's leftovers (a local
  model a force-quit left running, roofd from older builds) show at the top with **Stop**, and One Roof stops a
  left-over local model by itself when it starts.
- **Pick issues refreshes from Linear** (LAB-546): on opening, on every chip click, every minute, and with a ↻ button,
  so new issues show up without restarting. **Columns sort** (LAB-547): Key (by number), Title, State, and the new
  Created and Updated columns.
- **Narrow plan panel fits** (LAB-548): the tab bar tightens, then shows icons, instead of pushing the panel off both
  edges. The Ticket tab's state buttons no longer wrap letter by letter; when they don't fit they become one
  **Move to** menu (LAB-530).

## 0.4.9 — no more freeze (22 Oct 2026)

- **0.4.8 froze the window** (LAB-540). The Artifacts tab's label worked out its count by rereading the handoff folder
  on every redraw, several times per redraw, so the window never caught up. The list is now kept and refreshed in the
  background (when the session changes, and every 10 s for new handoffs), and the folder is matched with one pattern.

## 0.4.8 — the backlog batch (22 Oct 2026)

- **Sessions list stays put** (LAB-515, LAB-490). Working, Ready and Idle are one **Active** group and chip (the row's
  dot and caption still say which). Rows keep their place while agents work and rest, and a status moves a row to
  another group only once it has held (2 s for Needs you, 6 s otherwise). Chips: All · Needs you · Active · Exited.
- **Rename persists** (LAB-487). The plan panel wrote its own stale copy of every field back when you left a session,
  undoing a rename made from the menu or popover. It now saves only the fields you edited there. **Notes › Save** says
  Saved (with the time) or Unsaved changes (LAB-512).
- **Ticket tab lists the issues a session works on** (LAB-511): keys in its name, opening message, notes and terminal
  ("LAB-474", "bugs 298 and 460"), with their Linear title and state and one-click Attach.
- **Artifacts tab is the session's own** (LAB-513): files its agent wrote or edited (kept after each turn), its plan,
  handoffs it wrote, and screenshots it was given. The exited pane offers only a handoff written during the session
  (LAB-510).
- **Opening messages start with Where Are We** (LAB-491), anchored in the session's project and team.
- **Toolbar toggles in panel order: Sessions · Files · Terminal · Plan** (LAB-522); Terminal is new. A toolbar
  double-click no longer shrinks a window that fills the screen (LAB-520). The pane header is never cut off (LAB-521).
- **Finder icons in the Files panel** (LAB-478).
- **Dotted project codes** like LAB-ONEROOF-v0.50 are read whole; their commit tag drops the dot (LAB-519).
- **Ask to fix** won't type into a working or waiting agent (LAB-284).
- **roofd repairs its background item** when launchd's job is stuck after a dev → release switch (LAB-516). CI runs
  roofd's tests again (LAB-283).

## 0.4.7 — pick issues in a panel (21 Oct 2026)

- **Pick issues in a panel you can resize and read** (LAB-523). Issue ▾ in New session opens a **Pick issues** panel
  beside the sheet instead of a fixed popover: a table with resizable columns (tick · order · key · title · state), the
  rows in one order (In Progress, To do, Backlog, In Review last), state filters with counts, a filter that also
  searches the description, and a pane under the table that shows the selected issue in full before you add it. The
  panel remembers its size.
- **Ticking an issue no longer moves it** (LAB-527). Picked issues used to jump to the top, so the list scrolled under
  the pointer. Rows stay put; a **Picked** chip shows just the ones you ticked, in the order you ticked them.
- **The opening message names every picked issue** (LAB-528). Once you had typed into the opening message it stopped
  following your picks, so a session started on 20 issues told its agent about the first 3. Your words now stay and
  only the list of issues in the message changes as you tick.
- **Agents in a session reach the right roofd** (LAB-529). One Roof opened from a terminal inside one of its own
  sessions passed that session's roofd path on to every new session, so agents could call an older roofd (their issue
  updates failed). Each session now gets its own.
- **Small fixes.** A finished turn's caption says **Ready**, the same word as its status (it said Done) (LAB-241). The
  exited pane's **Open … handoff** also finds a handoff named after any of the session's issues and says which one, and
  no longer matches a longer id that merely contains the key (LAB-250).

## 0.4.6 — one session on several issues (21 Oct 2026)

- **Start one session on several issues** (LAB-518). In New session, **Issue ▾** is now a checklist: tick several of the
  project's open issues (active, to do or backlog) and One Roof makes one session for all of them, named with every key
  (`LAB-1, LAB-2, LAB-3 · title`). Its opening message asks the agent to read them all and write one plan that resolves
  them in the best order, then work through them in that order.
- **Agents keep each issue up to date.** Inside a session an agent can run `"$ONEROOF_ROOFD_BIN" issue KEY --state "In
  Progress"|"In Review" --comment "…"`; One Roof applies it to Linear with your key, only for that session's own issues
  and never to Done. A session on several issues no longer moves them all to In Progress at launch.

## 0.4.5 — Resources names every session (21 Oct 2026)

- **Resources names every session correctly** (LAB-517). A session whose agent had finished while its terminal stayed
  open showed under Other as `roof-…`, "not a One Roof row". It now stays in its window under its own name (status
  Exited), and its Resources tab in the plan panel shows the memory that terminal still holds.

## 0.4.4 — Resources: what One Roof uses (21 Oct 2026)

- **Resources: see what One Roof itself uses** (LAB-493). View › Resources (⇧⌘U, or Resources in the toolbar) shows
  One Roof's total memory and CPU with 10-minute charts, the Mac's memory, pressure and swap, the app and the roofd
  daemon, and every running session by window, heaviest first, with a bar against roofd's memory guard (warns at
  1 GB, ends the session at 2 GB). Click a session to go to it. The plan panel has a **Resources** tab for the
  selected session: memory and CPU now and over 10 minutes, the guard, and every process under it.

## 0.4.3 — roofd memory fix (21 Oct 2026)

- **roofd no longer eats the Mac's memory.** Each session's process kept every answer it gave the app, so a session
  open for a day grew to several GB and macOS froze. It now stays at a few MB, and as a safety net a session that
  passes 2 GB ends itself (noted in `roofd-memory.log` in roofd's folder) instead of taking the Mac down.
- **A session can work on several issues** (LAB-474). Add issue… (session menu, right-click, or the Ticket tab) adds
  an open issue or a new one at any point; the row shows `KEY +N`, the Ticket tab lists each one, and closing asks
  per issue. A commit that names an issue moves it to In Review on its own, once. If the agent is busy when you add
  one, the note waits and goes in as soon as it is back at its prompt.
- **New session no longer slides off the screen** (LAB-472): picking New bug made the bottom row too wide; it now
  wraps to two lines when it does not fit.

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
