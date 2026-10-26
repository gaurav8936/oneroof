# One Roof 1.x window · implementation notes

**Status:** ACTIVE · **Date:** 2026-10-26 · **Project:** LAB-ONEROOF-UI-REDESIGN

> **One line:** how the v2 window (Claude Design handover v2.5) is being built into One Roof, milestone by milestone, behind the `ui2` setting, and every deviation from the handover.

## Rules that hold for every milestone

- The handover's screens and specs win over its starter Swift. Today's behaviour (0.5.2.9) wins over both when they disagree about *what* a feature does; the handover wins on look, layout and copy.
- Nothing that works in 0.5.2.9 is removed. The list to tick is [20261026_01_ui-1x-feature-baseline-0529.md](20261026_01_ui-1x-feature-baseline-0529.md).
- The terminal itself (libghostty view, roofd attach) never changes; only its chrome.
- Tokens only in views (no hex), SF Pro / SF Mono, no new dependencies.
- Versions follow [the 1.x.y decision](../decisions/20261026_01_version-numbers-1xy.md): one minor version per milestone.

## M0 · 1.0.0 · baseline, flag and build-in

**Build log (handover starter Swift, 16 files, about 1,500 lines).**
- Dropped in unchanged, it failed with 765 errors. Nearly all came from type names that already exist in the app: `Action`, `AgentBadge`, `Block`, `Caption`, `Card`, `Decision`, `FeedEvent`, `Item`, `LoopsView`, `PlanTab`, `Row`, `SessionContextMenu`, `WorkView`. Inside the new files only, these are now `V2<Name>`. With that, the starter compiles with no other change.
- The starter's sample rows named real projects and repos, which the neutral-source tests reject; they now use neutral names (Docs site, App · Bug fixes, DOC-12, WEB-7 …).
- The starter views are placeholders (most are 50 to 150 lines). They are kept as a starting point and replaced screen by screen from M1 on.

**Patches to existing files (handover PATCHES.md).**
- P1 `WindowState`: `focusStep`, `layout`, `place`, saved per window (`focusStep.<id>`, `layout.<id>`, `place.<id>`), plus `open(_:)`, `stepOn()`, `stepBack()`.
- P2 `AppSettings`: `ui2` (default off) and the look, saved by name (`lookName`; `"custom"` = panels customised one by one). Saved by name because Swift's synthesized encoder drops a nil optional, which would turn "custom" back into Sky Studio after a relaunch (caught by `LookTests`).
- P3 `railFill`: not needed yet; decided when the rail is drawn in M1.
- P4 (host the v2 shell) and P5 (menus from `MenuSpecV2`) move to M1 and M6, where the shell and the menus are built.
- P6 self-test: `ONEROOF_SELFTEST_UI2=1`, `LOOK=<look>`, `PLACE=<place>`, `FOCUS=<0-3>`, `LAYOUT=<single|grid|wall>`. UI2 and LOOK are read with the settings, before any window opens.

**Models (`OneRoofCore/Look.swift`, from the starter, unchanged):** `Look` (six presets → `PanelThemes`), `FocusStep` (0 Full · 1 Sessions · 2 Wide · 3 Focus, with which panels each shows), `Place` (seven places with SF Symbols and ⌃⌘1-7 digits), `SessionLayout` (Single · Grid · Wall). `LookTests` covers the handover table, look matching, text contrast ≥ 4.5:1 on every plane of every look, the Focus round trip, default steps per place and layout, and settings round-trips from 0.5.2.9 files.

**Glyphs → SF Symbols (handover G3):** Home `house` · Needs you `exclamationmark.bubble` · Sessions `rectangle.stack` · Work `square.grid.2x2` · Machine `gauge` · Loops `arrow.triangle.2.circlepath` · Learn `graduationcap` · Look `circle.lefthalf.filled`.

**Screen check harness:** `app/scripts/ui2-compare.sh` with `app/scripts/ui2-screens.tsv`. Each listed screen is captured in-process with `selftest-shot.sh` and placed next to its handover shot (`UI2_SHOTS=<handover>/01_handover/assets/shots`). The handover itself is local-only and never published.

**With `ui2` off (the default), 1.0.0 looks and behaves exactly like 0.5.2.9.**

## M1 · 1.1.0 · the window shell

**How it is built.** The v2 window uses the same split view as 0.5, so every panel action (⌥⌘S, ⌥⌘P, ⌥⌘C, ⌥⌘B, split panes, the editor) keeps working: a 66 pt rail item is added in front, the files item stays collapsed, the session column and the Plan column get v2 views. The toolbar band is a native unified toolbar whose sections line up with the columns through `NSTrackingSeparatorToolbarItem`: the places icon row over the session column (step 1 only), then title · player · Single · Grid · Wall · Focus step · + New over the centre. The band behind it is painted per column (rail, column, centre, Plan) from the split view's frames. The dock is a 50 pt bar under the split view (0 pt and clipped when folded). Files: `UI/V2/V2Chrome.swift`, `V2SessionColumn.swift`, `V2Toolbar.swift`, `MainWindowController+V2.swift`.

**Focus ladder.** Step widths from FOCUS_LADDER.md: rail 66 at steps 0 and 2; column 250 / 280 / 250 / 52 (avatars); Plan 270 at step 0, a 28 pt edge tab at steps 1-2, gone at 3; dock full at 0, one line in the column at 1, seat bars in the rail at 2, nothing at 3. Places other than Sessions show rail + their view + dock (no column, no Plan). ⌥⌘F steps on (the old "Focus: Terminal Only" key), ⇧⌥⌘F steps back, ⌃⌘J dock full ↔ line, ⌃⌘1-7 places; the new keys are hidden menu items until the A11 menus land (1.6.0) and exist only with ui2 on. The step is saved per window.

**Place and centre stay in step inside `WindowState`** (synchronous `didSet`s): opening a place shows its view, and opening a view from a menu (⇧⌘L Overview, ⌘B Board, ⌘I Decisions …) moves the place. Reacting to both through Combine caused an endless flip between two stale values; found by the screen check, fixed before landing.

**Until each place is redrawn (M4), a place shows today's view inside the new frame:** Home → Overview, Needs you → Decisions, Work → Work (and Board), Machine → Resources, Loops → Loops, Learn → Learn. The Plan column is today's Plan panel (M2 redraws it); its per-panel theme list is hidden in the v2 window (Looks replace it; Settings › Appearance › Customize keeps every panel's choice).

**Terminal card.** The terminal area sits in a card 8 pt in from the centre's edges (6 pt at the top), corners 12, on the centre's background. The terminal itself is unchanged. The Focus hint pill floats over the card at step 3 and never takes the mouse.

**Kept from 0.5.2.9 although the mockup does not show them:** the Learn mini player and the Editor's Run · Debug in the toolbar; the startup-check issue count in the step-1 dock line when the check found something (0.5's footer always showed it); "Remove all exited sessions" under the Exited chip; the row's ••• popover, inline rename, ✕, drag and every row mark (A1.8); typing in the column's search box filters the list as today's Filter field did, and Return or ⌘K opens Search with the text.

**Deviations, on purpose:**
- **Esc leaves Focus only when the terminal does not have the keyboard.** In the terminal, Esc belongs to the agent (it interrupts Claude); taking it would break 0.5.2.9 behaviour. ⇧⌥⌘F and the step button always leave Focus.
- Grid and Wall show in the layout control but are disabled with "arrives in 1.7.0 / 1.8.0" (CAP-2, CAP-3).
- The app-version label from the 0.5 toolbar is not in the v2 band (the mockup has none); the version stays in Help › Release Notes and, from 1.5.0, Settings › Updates.
- The traffic lights stay in their standard row at step 3 (the mockup stacks them vertically over the avatar column).
- The self-test snapshot draws the toolbar band from AppKit's own material, so captures show it white; on screen the band takes each column's colour. Checked in code, not in captures.
- P3 (`railFill`): not needed; the rail uses its theme's `control` token and reads clearly in all six looks.

**Independent audit of M1 (before landing): build, tests and release check green; nothing changes with ui2 off. Fixed from its findings:** the v2 window saves its split layout under its own name (`OneRoofSplitV2…`, it has a rail item 0.5's does not); outside Sessions the rail stays at Focus so Needs you is always visible; the 28 pt edge tab no longer counts as an open Plan, so the Subagents column beside the terminal shows at steps 1-2 as in 0.5; the centre un-collapses on any place change and the Editor still opens the file tree beside it until the Files tab arrives; Plan tab requests carry the window id; the Esc monitor is removed when the window closes; the v2 self-test hooks do nothing with ui2 off; the edge strips never take clicks; the edge reveal waits before hiding (menus and popovers over it); at Focus the right edge (and ⌥⌘P) slides the Plan over. The handover starter's placeholder views (about 1,250 lines) were removed in M1: every v2 view is written against the real model, screen by screen.

## M2 · 1.2.0 · session tabs and the Plan inspector

**Session tabs (A2.0)** replace the 0.5 centre strip in the v2 window (`UI/V2/V2SessionTabs.swift`): Terminal → the terminal card, Files → the Editor centre, Changes n → Review changes for the session's repo (count from the repo's git stat), Subagents n → the session's subagents. They show whenever the centre is one of those four views, in any place (an Editor or Review reached from Overview or a link keeps its way back). Split ⌘D and Raw ⌘R send today's actions; Wrap toggles reading mode (LAB-657) on the focused pane of that window only.

**Files (A2.1, A2.4, C6.1)** is `V2FilesTab`: today's `FileBrowserView` at 220 pt beside today's `EditorView`, with the LAB-799 file tabs above (`V2FileTabs`, unsaved dot kept; a file opened from search or a link shows as a tab too; closing the last tab leaves the tree and "Pick a file"). The Editor no longer opens the separate Files panel in v2; ⌥⌘B still toggles it.

**Split editor ⌘\ (CAP-18)** shows a second open text file beside the main one, read-only (saving, claims and Take over stay with the main file, so an agent's claim can never be bypassed from the second pane); ⌘\ again closes it. The key is a hidden menu item enabled only when the v2 window's centre is the Editor, so ⌘\ in a terminal is untouched. In the 0.5 window the label stays as it was.

**Changes (A2.2, CAP-17)** is today's Review changes (file list · diff · Checks and Commit, kept whole) with **Ask <agent> to commit** (a message to the repo's live session asking it to commit and not push) and **Discard…** under the file list. Discard asks first and runs `git restore --staged --worktree` on modified and deleted files only: staged-new files, the new side of a rename and binaries are never passed to git (restore would delete a staged new file); the dialog says how many are kept.

**Subagents (A2.3, C6.2)** is `V2SubagentsTab`: a card per subagent (status dot, name, model · tokens · age, Asked:, Doing:/Done:, right-click Ask the parent to stop) and FILES TOUCHED. Trace ▸ (one subagent) and Whole trace ▸ open today's `SubagentTraceView` with ‹ Subagents back; picking another session returns to the cards. Outside Sessions (Overview, Window menu) the trace view opens as in 0.5.

**Plan inspector (A3)**: in the v2 window the tab bar is one segmented row of text tabs, Plan · Ticket · Notes · Files · Usage (`PlanPanelView.v2TabBar`); the tabs' content is today's, which already holds every field A3.1-A3.6 shows. The 0.5 icon bar is unchanged with the setting off.

**Undo on the terminal card (CAP-26)**: Always allow on a terminal approval card shows "Always allow <pattern> in <repo> · Undo" for 5 s on that window's card.

**Deviations, on purpose:**
- Changes keeps 0.5's Checks and Commit column (the handover draws two columns); dropping it would lose Commit ⌘↩ and the handoff ask. The diff header does not yet say "by <agent> · step n" (the step-to-file link is not recorded per hunk).
- The Editor keeps its own file header (name, folder, Preview/Source, Split editor) under the file tabs, so Files has two thin rows where the mockup has one.
- Split ⌘D · Raw ⌘R · Wrap are dimmed outside the Terminal tab: they act on terminals.
- "Pick a file" (Files with no file open) is new text; the mockup always shows a file.

**Independent audit of M2 (before landing): nothing changes with ui2 off; build and 563 tests green. Fixed from its findings:** Discard no longer touches staged-new, renamed or binary files (it deleted a staged new file in a scratch repo); the split pane is read-only and resets when its file becomes the main one, and ⌘\ is a validated menu key; file tabs show the unsaved dot again; the session tabs show outside Sessions; Files reopens the file you were on and closing the last tab stays on Files; Ask to commit is enabled and labelled from the session it sends to; Subagents has ‹ Subagents and Whole trace ▸ and resets on a new session; the Undo toast shows only in the window where Always allow was clicked.

## M3 · 1.3.0 · Looks, sheets and overlays

**Looks (A10.3, CAP-5).** In the v2 window Settings › Appearance is `V2LooksPicker`: six preview cards from `Look.panelThemes` (rail colour, centre with a terminal block, Plan strip); a click sets `chosenThemes` to the look, and `AppModel` keeps `settings.lookName` in step (the matching look or "custom") whenever the panels change, from any place (Customize, View menus, Search, Plan panel). Customize each panel… shows today's per-panel grid (opens by itself when the panels are a custom mix). Text size 85–130 % (⌘+ ⌘− ⌘0), Follow macOS (with its Dark Mode note), Fill rows with their colour, Sticker style and the window's colour (LAB-590) follow. The 0.5 Appearance page is unchanged with the setting off.

**Search ⌘K (A10.2, A10.5).** `V2SearchPalette` takes today's palette items unchanged and groups them by source in the handover's order, Best answer first: Learn's two best pages for the text (Listen for a narrated card, Read for a page), then Views, Actions, Windows, Decisions, Roof windows, Theme (in v2 the six looks), Sessions, Objectives, Projects, Repo files (selected repo, up to 4,000), Skills, Learn. Each group shows 5 (3 with no text) and "Show all n" opens the rest, so every match 0.5's flat list reached is still reachable. ↑↓ ↩ Esc as before; **⌘↩ sends the typed text to the selected session** (refused while it works, as typing is); while Search has the keyboard, File › Launch's ⌘↩ yields to it. The palette observes the model, so Learn's answers appear once its index has loaded. How do I ⌥⌘/ still opens Learn as in 0.5.

**New session (A10.1, CAP-14).** Today's NewSessionSheet already has every control the v2.4 screen lists (Team · Project · Issues with New… last, attachments, Similar ticket, Suggested + Use it, the seven agent cards, Model · Repo · Start in, Done when, Opening message, Advanced: arguments, Role, Resume, Own git worktree (not connected), When: Now · Next · Tonight · Nightly · Every · On demand, Save as planned); kept as is. Team/Project/Issues and Similar ticket show when Linear is connected.

**Row right-click (A10.4, LAB-1086).** `SessionContextMenu` in v2 adds Rename…, Schedule ▸ (Tonight 2:00 AM, Nightly, On Demand), Interrupt and Send Handoff (live agent), gathers the copies under Copy ▸ (Folder Path, Session ID, Link, Attach Command) and ends Close Agent… · Delete (red) · Remove Exited Sessions…. Every item acts on the row's own session directly (never through the selection), so it is right from Overview and from a window that is not in front.

**Find in Workspace (A10.6)** opens as its own page (no file tree, file tabs or session tabs), titled "Find in Workspace ⇧⌘S"; its ✕, the rail or a result lead back. In v2 the file viewer's pages (Markdown, HTML, folders, search, diffs) take the centre's theme rather than the terminal's, as the handover draws them (C6.1, A10.6).

**Window switcher (LAB-968)** was built in M1/M2 (`V2SessionColumn` switcher and `v2ShowWindowMenu`); Move to iPad stays hidden (LAB-1189).

**Deviations, on purpose:**
- Search's Theme items are the six looks in v2 (the handover's "Theme: all panels Sky Studio"); single-theme-for-all-panels stays under Customize.
- NEW-14's permission mode, budget, window and objective fields are not on New session (they were never in 0.5.2.9; arguments carry a permission mode).
- The toolbar keeps the session's title over Find in Workspace; the page's own header says "Find in Workspace ⇧⌘S".

**Independent audit of M3 (before landing): nothing changes with ui2 off; build and 563 tests green. Fixed from its findings:** row-menu items act on the row's session directly (they went through the active window's selection, so from Overview an Interrupt could hit another session) and no longer change what the window shows; Search groups have "Show all n"; Learn answers appear when the index finishes loading; ⌘↩ in Search no longer launches a planned session; `lookName` follows any panel change; Copy ▸ Session ID only for a live agent and no duplicate Working Directory; Appearance keeps 0.5's help lines; Search's theme items are looks.

## M4 · 1.4.0 · the places, part 1 (1.4.1 finishes M4)

**How it is built.** The place views stay today's views; in the v2 window they read a SwiftUI environment flag `\.v2Window` (set by `CentreThemed`) and change layout only where the handover differs. `FleetPage` draws flat on the centre's colour in v2 (the 0.5 desk gradient otherwise). New views live in `UI/V2/V2Places.swift`.

**Machine (A8, C4.x).** Title Machine; four meter cards (One Roof memory with its sparkline, CPU with its sparkline, This Mac with the memory meter and pressure, roofd with uptime, session count and its headroom bar); then two columns: today's `MacAppsCard` (This Mac by app, Quit, End, leftovers, browser tabs) and One Roof itself + every window's sessions, this window first (other windows keep the chosen sort). The roofd memory-guard line sits under them.

**Loops (A9, C5.1, NEW-24).** The loop list (today's rows) beside `V2TonightPanel`: Tonight and Nightly sessions, nightly loops that are not stopped or paused, + Schedule a session (Planned and Next sessions, Tonight 2:00 AM, as the row's Schedule menu), and Last night: loop stop lines and Tonight/Nightly session runs since 6 PM yesterday. Clicking a loop opens today's `LoopDetail` as a page (‹ Loops, ⌘[) with `V2LoopFences`: ✓ for what roofd enforces (the limits; each round starts in the loop's worktree) and • for what the loop is only told (never push, merge or deploy, or touch your checkout; prompts come to Needs you unless the agent already allows the command). Nothing is claimed beyond the code.

**Needs you (A6, C2.2, NEW-19).** Title Needs you; the footer "Earlier today · n decided · m rules learned ›" opens `V2RulesPage`: every always-allow rule (pattern, repo, when added) with Remove, and today's decisions (allowed once, always allowed, denied, replied). Its copy says exactly what a rule is: One Roof notes a matching decision in the same repo and never answers for you; the agent's own "don't ask again" lives in its settings and Remove does not undo it. The page closes when you leave Needs you or a new decision arrives; ‹ Needs you / ⌘[ goes back.

**Home (A5, C1.3, NEW-23).** + New objective next to + New work item (opens today's New objective sheet); the Projects tab shows each active project's done percentage beside its live count.

**Deviations, on purpose:**
- The fences are worded from the code, not the handover: the mockup's "Lands on live, never protected branches", "Moves issues to In Review, never Done" and "Approves its own steps inside the fences" are not what 0.5.2.9 loops do. A real push guard for loops would be a new capability (tracked).
- The Rules page does not promise that Remove brings the prompt back (it cannot: the agent keeps its own permission).
- + New work item / + New objective sit in Home's header rather than under the window cards.

**Independent audit of M4 (before landing): nothing changes with ui2 off; build and 563 tests green; no feature lost. Fixed from its findings:** Rules page and fences copy rewritten to match the code; Tonight includes nightly loops and their last-night results, Last night is only overnight Tonight/Nightly runs, Schedule a session offers Planned and Next sessions only; the Rules page no longer traps the queue; Machine's window order uses a valid sort; no loop row looks selected when none is open; the fence's time limit is formatted exactly.

**Left for 1.4.1 (same milestone, tracked on its Linear issues):** Work and Board (A7.x), New work item and issue picker (A7.3, A7.4), the objective planner page (D1.2) and plan approval card (D1.3, NEW-27 total), New objective fields (C1.4), the planner budget's seat and time limits (NEW-15), the loop row layout (A9: budget, when, result pill) and the decision card restyle (A6.1: short Always allow, keys footer, count).
