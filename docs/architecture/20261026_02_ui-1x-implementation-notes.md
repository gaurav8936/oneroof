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

### 1.4.1 · the places, part 2

- **Needs you (A6.1):** in v2 the always button reads "Always allow this" (tooltip: the pattern and repo), the waiting count sits beside the title, and "This waits until you choose. ↩ allow once · esc deny · ⌘] next decision · ⌘[ previous" sits under the buttons. The handover's "Nothing is approved for you" was not used: Always allow sends the agent's own "don't ask again", and auto-mode objectives approve their own steps.
- **Objective planner (D1.2):** "Send all to ▾" sets every step to one seat in a single save, offering this Mac's Claude accounts (Claude2 only when ~/.claude-2 exists) and every other agent, as the per-step pickers do; a typed model stays when the agent does not change. The router's "Route all steps" is unchanged. Pause, Watch, Re-plan, Delete, Steps run without asking, per-step Agent · Account · model and ↑↓ reorder were already there.
- **Board (A7.2, C3.2):** v2 labels Status · Agent · Project (the eight status columns, drop rules and Tonight picker are today's). New work item (A7.3), the issue picker (A7.4), project detail (A7.1), New objective (C1.4) and New loop (C5.2) already match their screens and are kept.
- **Loops rows (A9):** name with trigger · limits · repo, where it stands, the last checks and the state pill.
- **Not done, tracked for 1.4.2 on their issues:** the ticket page (C3.1), Send for approval and drag to reorder (D1.2), the Seats and Limit cards with a real seat/time budget (D1.2, NEW-15), the plan approval's risk-and-cost card with a total from seat cost data (D1.3, NEW-27: the planner writes cost as low · medium · high, so a dollar total from its text would be invented), the loop fence column (A9).
- **Independent audit (before landing):** no change with ui2 off; fixed: Send all to offered Claude2 on Macs without it and missed Antigravity; the dollar total (it read "30 min" as $30) was removed; the keys line no longer claims nothing is approved.
## M5 · 1.5.0 · Settings, Setup, Foundations, Help

**Pages over the place (LAB-1084).** `MainWindowController.v2Page` ("Settings", "Help", "Release notes") shows `V2PageHost` on a layer over the centre item (`V2PageHostingView`, which takes the keyboard while shown so keys never reach the terminal underneath; checked in the self-test snapshot's firstResponder). While a page shows, `v2ApplyLayout` treats the window as outside Sessions (rail shown, column and Plan folded). The window's key monitor owns Esc (unless a text field is editing or a shortcut is being recorded) and ⌘[ while a page shows, so nothing underneath sees them; any place, or any change of the centre (a notification, Search, a link), closes the page; opening one brings the window to the front. AppDelegate routes Settings… ⌘,, the Shortcuts item, One Roof Help and Release Notes to pages in the v2 window; the 0.5 Settings tab numbers map onto panes.

**Settings (B1.x).** `V2SettingsPage`: the nine panes down the left, `SettingsView(v2Pane:)` on the right. General (Start: folder, startup check, Dock badge, Sessions; New sessions: Done when required, Step review; In the background: scheduled runs, menu-bar extra; Layout: Classic layout), Appearance (the Looks picker), Seats & accounts (today's per-agent defaults), Notifications, On-device model (captions + model row), Foundations (today's folders form + Open Foundations ⇧⌘F), Learn (kit + Learn folders), Shortcuts, Updates (version, build, roofd, Release notes, Check now → the latest-release page; it says there is no updater and no channel yet). Every 0.5 control is in a pane.

**Classic layout (NEW-28)** asks, sets ui2 off and quits; the classic window's General has **Use the new window…** (the same, the other way) so the fallback is two-way. **Done when required (NEW-30)**, a new setting off by default and shown only in v2, blocks Launch and Save as planned in New session with its own reason; other launch paths (Work's ▶, planned rows, objectives) are not gated, which the setting's text says ("New session can't launch…"). **Fix all (NEW-21, part)** runs the fixes of failing (red) checks in one terminal joined with "; " (each runs after the previous ends, failures or not), never warnings (optional add-ons) and never the long-running roofd daemon fix.

**Help (B4.1)** shows the bundled help pages (list on the right, the page rendered on the left) with Open in Learn (today's Help in Learn). **Release notes (B4.2)** parses the bundled notes (`## ` releases and `- ` bullets) into one card per release, with Open the file.

**Setup (B3.1-B3.3, LAB-1195)** in v2: step 1 agents on this Mac; step 2 projects folder, shared rules and docs, required tools; step 3 the kit, the look, Linear; Back / Continue / Open One Roof. Every field of today's form is kept and saved by Open One Roof whatever step it was set on. The classic window keeps the one-page form and Start.

**Deviations, on purpose:** panes use macOS grouped forms (switches) rather than the mockup's card rows with Turn on / Turn off buttons; Foundations stays its own window (handover v2.4); the classic window gains one row (Use the new window…), the only visible change with the setting off.

**Independent audit of M5 (before landing): no regression with ui2 off; nothing from 0.5 Settings or Setup lost. Fixed from its findings:** the page takes the keyboard (verified); one owner for Esc and ⌘[ while a page shows; Done when required has its own blocked reason; Fix all only runs failing checks and skips the foreground roofd fix; a way back from Classic layout; pages open in front and close when the centre changes; the Setup look picker handles a custom mix; per-step Setup subtitles.

**Left for 1.5.1 (tracked on their issues):** Seats & accounts usage, Sign in / Install (NEW-20) and routing rules (NEW-6, 1.8.0); General's Default seat and Auto mode for objectives; the Foundations pane's inline checks (B1.3); Learn's narration speed; notification extras (NEW-11); Foundations B2 headline and Ignore for this repo (NEW-21 rest); the update channel (NEW-29); the on-device model fallback and memory cap (NEW-12).

## M6 · 1.6.0 · menus, parity sign-off, the new window by default

**Default on (PAR.17, LAB-1145).** `AppSettings.ui2` is true for new settings; a new `ui2Chosen` records an explicit pick (Classic layout / Use the new window…). Decoding forces ui2 on unless ui2Chosen, so everyone on 1.0.0-1.5.0's default-off moves to the new window and a choice made from 1.6.0 on is kept. Known edge: a Classic pick made in 1.5.0 was saved without ui2Chosen and opens the new window once; Settings › General › Classic layout restores it. Self-tests stay on the classic window unless ONEROOF_SELFTEST_UI2=1 (also on the legacy-migration path).

**Menus (A11, MENUS.md).** `AppDelegate.v2AdjustMenus` (UI/V2/V2Menus.swift) runs on the built menus in a v2 app: the MENUS.md names (Overview → Home, Resources → Machine, Decisions → Needs You, Work: Projects and Roadmap → Work, Toggle Sidebar → Sessions Column, Toggle Plan Panel → Plan, File Browser → Files Tab, Review Changes → Changes, Focus: Terminal Only → Focus: Step On, Focus Terminal → Sessions ⌘L); Focus: Step Back, Dock and Split Editor shown; Single (on) · Grid · Wall (disabled, "arrives in 1.7.0 / 1.8.0") at ⌃⌥⌘1-3; Look…; Edit › Copy Session Output (NEW-13, enabled when a terminal is shown). The four per-panel theme menus go (Customize each panel holds them); Terminal Theme stays (Blueprint lives only there). `ShortcutBridge.renamed` maps each new name to its old one, resolved twice so chains work. ⌃⌘1-7 place aliases are titled "Open <place>": overrides are keyed by title, and the old titles ("Learn", "Loops") clashed with the visible items, so one of each pair lost its key (a v2-only bug since 1.1.0). Every item keeps its action; MENUS.md's order is not adopted (0.5's order kept).

**Behaviour in v2:** ⌥⌘C brings the terminal forward (collapsing the centre would resize the window, LAB-596); ⌥⌘B opens the Files tab (and back); ⇧⌘A opens the trace of every session's subagents; a page closes when the session selection changes; Esc leaves Focus only in the Sessions place.

**Parity sign-off (PAR.01-PAR.16):** two independent auditors checked all 80 rows of NO_REGRESSION.csv against the v2 window from code and about 45 self-test captures: every 0.5.2.9 feature is reachable. Fixed from their findings before landing: a menu-validation crash when no main window is left (`main` is nil; since 1.2.0, both windows) — all v2 checks now go through `isV2Window`; the Files-tab editor hid the first characters of every line (the clip view kept x = 0 under the 52 pt gutter when first laid out hidden; it now starts at -gutter once per file); the toolbar extras (Learn player, Run · Debug) were sized empty and drew over Single · Grid · Wall (min/max sizing now tracks the content); ⌥⌘C resized the window; Files Tab opened the old panel; ⇧⌘A routing; Copy Session Output always enabled; pages not closing on session picks; Esc at Focus outside Sessions; the self-test legacy path ignoring UI2.

**Still open (tracked):** notifications for the selected session are suppressed while a page covers the window; at steps 2-3 roofd state and the foundations count show nowhere (the dock and dock line show them at steps 0-1); the legacy MenusV2.swift / KeymapV2.swift starter files are unused.

## 1.7.0 · composer and Grid

**Composer (NEW-1).** In the v2 window the strip under an agent's terminal is `V2Composer` (UI/V2/V2Composer.swift): an NSTextView-backed box (`ComposerField`) so Return arrives as `insertNewline:` only after an input method has committed its text. ↩ sends through `SessionRuntime.submit` (roofd input, a pause, then Enter: the same as typing in the terminal); ⇧↩ inserts a line; ↑ / ↓ walk this session's sent messages when the box is empty or recalling; ⌃↩ sends "!" + text to Claude (its shell mode) and is refused for other agents; ⌘. interrupts when the box has the keyboard. Drafts and history are kept per session while One Roof runs. **While the session needs you, the composer does not send** (the trailing Enter would confirm the highlighted option of a permission prompt); the text is kept and the placeholder says why. A click into another pane's composer keeps the keyboard there (the pane focus change no longer hands it to that pane's terminal). Shell sessions keep no bar; the classic window keeps the hint strip. Not built: attachments and / skill, @ file completion (typed as text for the agent to complete).

**Grid (NEW-2).** `PaneNode.grid(_:wide:)` (OneRoofCore, tested) builds 2 × 2 tiles, or 3 × 2 when the window is wider than 1440 pt. `TerminalAreaController.applyLayout` keeps the Single panes aside, fills the Grid with this window's live sessions (the selected one first, then needs-you, running, others; popped-out sessions left out), and puts the Single panes back on Single; a save queued just before never writes the Grid over them. Tiles are panes: focus ring, ⌥⌘arrows, split, close and zoom work; choosing a session in the column fills the focused tile. Grid and Wall are not restored on relaunch (they are built from live sessions); a window starts in Single. The layout control and View › Grid (⌃⌥⌘2) are enabled; Wall stays disabled until 1.8.0.

**Held for the owner:** the plan removes the Classic layout in 1.7.0; it is kept, since no 1.x build had been installed and verified yet (LAB-1225).

**Independent audit (before landing):** classic untouched. Fixed: the composer could answer a permission prompt (it now holds text while the session needs you); IME Return and ⇧↩ (NSTextView field); focus taken back to a terminal when clicking another tile's composer; a queued pane save writing the Grid over the Single panes; relaunching into an empty Grid; popped-out sessions in tiles; wide judged on the window width. **Still open:** "n on screen · m more" title and ⌘1-⌘4 tile markers, drag a session onto a tile, double-click a tile for Single, tile choices kept in WindowState, the composer growing past one line (it scrolls), Grid not adding sessions started while it shows.

## 1.8.0 · Wall, seat routing, Learn Radio

**Wall (NEW-3, A4.2)** is the "All windows" page (`UI/V2/V2Wall.swift`) shown while `win.layout == .wall`: tiles for every window's live sessions in window order, 10 (15 at 2400 pt and wider), each with status, name, window, state, the Right now line and the last terminal lines (roofd `read`, every 3 s, only for the tiles shown, one batch at a time, stopped when the page closes). A tile opens its window at Single on that session (on its terminal). Unlike other pages the Wall does not close when the selection changes (background launches and exits change it). Not built: a Needs-you count and window colours on tiles, group headers.

**Seat routing (NEW-6).** The router and the objective runner already skipped seats past `routing.json`'s limits and rotated running steps (handoff, then restart on another vendor's agent, at most twice). Settings › Seats & accounts › Routing shows the hand-off point (an override, `handOffAt`, applied through `AppModel.routingPolicy()`; "Use the routing file's value" clears it) and "Prefer a different model family for review" (`reviewOtherFamily`, on = the old behaviour).

**Learn Radio (NEW-8, A12.2, partial).** In v2, Learn has Pages (today's Learn, the default) · Radio · All cards (`UI/V2/V2LearnRadio.swift`). Radio reads the deck's catalog once (suits, bands, card lists) and shows the bands with card counts, a now-playing panel driving `CoursePlayer` (play / pause, speed, next, part and progress; Tune in plays the band's first narrated card) and the band's cards with ▶ and Open (the card page in Pages: diagram, transcript, skill). All cards lists the deck by suit and band. A link, a Search result or How do I… while Radio shows switches to Pages. Not built: Writing and the post reader, programmes, the band page, separate card-station tabs, the dial and waveform, the toolbar mini player's Radio state.

**Independent audit (before landing):** classic untouched; routing at the defaults identical to before. Fixed: the Wall closed itself on background selection changes; Learn ignored targets while on Radio; the selected band was white-on-white in dark themes (now accent tokens, no emoji); the catalog was re-read on every render; the Wall feed read every session, overlapped batches and could leak its timer; the rotation copy; a Wall tile could open behind another view.

## 1.8.1 · real-profile audit

Every earlier audit ran on a fresh profile with demo sessions. This one ran the v2 window on a copy of the owner's real profile (settings, per-window state, 20 sessions in the "Blogs & Public Presence" window, 15 workspaces) and compared it with the classic window from the same build (LAB-1234).

**How (test only).** `ONEROOF_PROFILE_SEED=<exported defaults plist>` is honoured only with `ONEROOF_FRESH_PROFILE=1`: after the fresh suite is emptied, the plist's keys are copied in (`SeedFilter` drops AppKit's `NS*` frames and the roofd registration). `Prefs.seeded` lets `WindowState` (step, layout, place, text size, widths), the saved panes and the v2 first-launch rule read that state, which self-tests otherwise ignore; nothing is saved. Run it with `ONEROOF_STORE=<a copy of sessions.sqlite per run>`, `ONEROOF_SELFTEST_DEMO=0`, `ROOFD_DIR=<scratch>` (the test's own roofd: without it a debug build would ask the installed app's daemon to upgrade) and `CFFIXED_USER_HOME=<scratch>` (keeps App Support out of reach; seat usage and Linear are then empty). A fresh profile no longer reads the real domain's saved window frame. Because the run has its own roofd, every real session shows Exited.

**Fixed.**
- *Launch state for an upgraded window.* A window with no saved step opened at Sessions (step 1): the Plan folded to the edge tab and the dock to one line, where 0.5.2.9 showed the Plan and the status footer. `V2Layout.initialStep`: a window that existed before (its classic pane layout is saved under `OneRoofPanes[.<id>]`) opens once at Full; a new window still opens at Sessions. The decision is saved at once, so it applies a single time. (The owner's own window was already saved at Full after the 019700d fix.)
- *Sessions step kept across places.* Opening Sessions from Home, Work, Machine … always reset it to step 1, folding a Plan opened at Full every time. `WindowState.sessionsStep` (saved as `sessionsStep.<id>`) remembers the step Sessions was last at; `V2Layout.openingStep` returns to it. Other places still open at Full.
- *Selected session hidden by the exited cap.* The Exited group shows four rows and "+ n more ›" (A1.1); with real data the selected session was often further down and vanished from the list. `V2Layout.cappedRows` keeps it.
- *Files and Changes on the wrong folder.* Sessions start at the workspace root (startInRepo off, "one memory") and work in a repo below it; the row and Plan already show that repo (`BoardItem.repoPath`: live, else last seen), but the Files tab, the Changes tab and its count, ⌥⌘R and the row's Review Changes used the start folder: ~/Projects and "not in a git repo". `AppModel.workRepo` uses the work repo in the v2 window (the classic window keeps the start folder; repo stats are also read for the work repo).
- *Window colour.* 0.5.2.9 tinted the toolbar band in the window's colour (LAB-590); the v2 band follows the columns, so only the switcher dot was left and coloured windows could not be told apart at a glance. A coloured window now keeps the 2 pt stripe in its ink under the band.
- *Dragged widths.* `v2ApplyLayout` set the column to 280/250 pt and the Plan to 270 pt on every step change and launch, so a width you dragged never stuck (0.5.2.9 kept panel widths). A drag of divider 1 or 3 (only during a mouse drag; `setPosition` also names a divider) is saved per window (`v2.columnWidth.<id>`, `v2.planWidth.<id>`) and used within the column limits (`V2Layout.columnWidth/planWidth`).
- *Dock line.* A dangling "·" after roofd when no seat has a usage feed.

**Checked, not changed.** Menus: every 0.5.2.9 item is in the v2 menus under its new name with the same key; only the four per-panel theme submenus go (Look… and Settings › Appearance hold them; Terminal Theme stays). Shortcuts: KeymapV2 matches SHORTCUTS.md; ⌘L still puts the cursor in the terminal (and opens Sessions). Kept as the handover draws them: the four-row Exited cap, exited rows at 60 %, the session name (not the window name) in the toolbar and the window name truncated in the switcher, no version label in the toolbar, Grid filling empty tiles when fewer sessions are live. Same in 0.5.2.9, so not regressions: the Plan's name field clips a long name without an ellipsis; the filter field has the keyboard at launch when the selected session has exited; the saved place is not restored (a window opens on Sessions).

**Not checked.** Live states (running, needs you, the approval card, the composer sending, Grid/Wall with live tiles): the run had its own empty roofd. Seat usage and Linear (no App Support or config in the scratch home). AppKit's split-view autosave restore (off in self-tests). The width memory with a real mouse drag (the rule is unit-tested). Learn was being rebuilt in another lane and was only looked at.

## 1.8.1 · Learn

**What it is (LAB-1233).** The owner found 1.8.0's Learn unlike the design (a grey band with a left-aligned picker, the
old sidebar in an inset box, a Radio that was a headline, a black "Pick a band" box and a button grid). 1.8.1 ports the
handover's `One Roof Learn.dc.html` as drawn. Files: `UI/V2/V2LearnRadio.swift` (LearnNav, the header pieces, Radio
home, the dial, disc, keys, knob), `V2LearnBand.swift` (band, programme), `V2LearnCard.swift` (card station and its
header actions), `V2LearnLibrary.swift` (Writing, post reader, All cards map and search); `LearnView.swift` gains
`v2Body` (classic `pagesBody` untouched); data in `OneRoofCore/LearnDeck.swift` (tests: `LearnDeckTests`).

**How Pages and Radio co-exist (my reading of A12 / A12.2 / LAB-1183).** v2.5 says 1.0.0 ships today's Learn (A12) and
Radio arrives in 1.2.0 with the control "Radio | Writing | All cards" (A12.2). By 1.8 both exist, and Pages holds
things Radio cannot (course, field manual, One Roof Help, Learn folders, hidden pages). So the control is the design's
three segments with **Pages** appended: Radio · Writing · All cards · Pages. Learn opens on Radio when the deck is in
the build, else on Pages. In Pages the header sits beside the 300 pt sidebar (as 42-A12 draws it) and has no search
field (the sidebar's "How do I…? or search N pages" is the search); elsewhere the header spans the width with the
search field on the right (43-A12_2). A link, Search's Learn result, the player bar's title or the toolbar mini player
opens a deck card's station while Radio's family shows; anything else, and anything while Pages shows, opens in Pages
(1.8.0's rule). How do I… (learnQuery) always goes to Pages.

**What matches.** Header (breadcrumb with links, section, card actions, mode control, search). Radio home: edition
line, headline and blurb, the panel (disc, ▶ / speed / ⏭ keys, KEEPS PLAYING WHILE YOU WORK, display with status,
title, subtitle · part, progress, dial with band labels and needle, four band keys with the pressed one dark, knob
from -135° to +135° across the dial, ON THIS BAND chips, Open the band →), broadcast schedule and programmes below.
Band page (kicker, title, sub, definition, Play the band, posts, the band's dial with track names, Start here + tracks
as card rows). Card station (kicker → band, meta, tabs; Listen panel with scene n of m, live status, kicker, heading,
the section's diagram nodes with this scene's nodes lit, lede and points, prev / scene dots / next, narration text;
Transcript rows that play from a scene; Skill file with path, frontmatter table and rendered body; right column with
chapters, triggers, pairs with, read about it, next on the band). Programme page, Writing, post reader, All cards map
(by band / by kind, start-here squares, length bars, playing ring, hover reader, block list with Play all, search
dimming with matches and posts). Toast for Use in a session. Player bar = today's PlayerBar (it already matched the
prototype's bar); its queue lists Up next pages. Toolbar mini player = today's MiniPlayer (NO_REGRESSION: kept); it now
opens the card station for a deck card. Colours only from tokens; the display's dark colours are new tokens
(`ThemeTokens.display`, the prototype's --disp/--dtx/--dmute/--dacc/--keyedge).

**Data, and what is real.** Cards, tracks, suits, paths, card lengths and scene counts: the bundled deck's
`content/catalog.json`. Scenes, narration text, diagram nodes and highlights: each card's `spec.json` (0.2.0 schema:
scenes carry kicker/heading/lede/points/highlight/narration; sections carry a diagram). Skill file: the card's
`SKILL.md`. Audio: the card page's `__TTS__` list through `CourseAudio` and `CoursePlayer` (no new player; the player
gained an up-next queue of pages). **Bug fixed on the way:** the 0.2.0 pages write `window.__TTS__ = {` with spaces and
CourseAudio searched for `window.__TTS__=`, so no deck card had playable clips in 1.8.0. The four bands, their lines,
start-here cards and the plain track names are the design's layer over the catalog (prototype PARTS / TI / KINDS),
ported as constants in `LearnDeck`; cards missing from the catalog are skipped. **The dial is not an audio waveform:**
each line is one card and its height is the card's catalog length (est_seconds), exactly as the prototype draws it.
Radio's time reads earlier parts at the catalog estimate per part plus the clip being heard.

**Deviations.** "NEW EVERY RELEASE" left off the edition line (not something the app can promise; the deck is
re-bundled each release but may not change); the post count shows only when posts exist. Scene visuals use the
spec's diagram nodes (the prototype parsed the card HTML's `.fv` blocks, which the 0.2.0 cards do not have). Post
bodies render with the app's Markdown viewer; the site-only `gg-diagram` / `gg-chart` blocks are left out. The radio
headline is held to 600 pt so it breaks over three lines like the design's balanced text. Content is capped at
1360 pt and centred, as in the prototype (wide windows show margins). The card's "Use in a session ▾" is a popover
listing live agent sessions with status (refuses with a toast while the session works, as `sendSkill` does).

**Captures** (`scripts/ui2-screens.tsv`, new hooks: `ONEROOF_SELFTEST_LEARN=<page title>`,
`ONEROOF_SELFTEST_PLAY=<title>@paused`, `ONEROOF_SELFTEST_LEARNMODE=pages|radio|band:<id>|card:<slug>[:tab]|writing|
post:<slug>|path:<id>|library|search:<text>`): A12, A12.2 (compared with 42 and 43), A12.3 map, A12.band, A12.card,
A12.transcript, A12.skill, A12.writing, A12.path, A12.search. Bundle with `ONEROOF_AE_DECK_REPO` set, or Radio shows
"not in this build".

**Still open.** Posts: the app and deck ship none; Writing, the schedule, band posts and "Read about it" are filled
only from posts in the owner's Learn folders (`<folder>/index.md` with title and date) and otherwise say so. The deck's
card visuals (the animated explainers) are not drawn in the station; Open in browser shows them. Track plain names
should come from the catalog (handover GAPS D6). Audio-to-scene order assumes one clip per narrated scene in
`__TTS__` order (GAPS G2). Only Daylight was captured; Graphite and Midnight follow the tokens but were not looked at.
The Radio panel and header were not checked at narrow window widths (the header can crowd below ~1250 pt).

