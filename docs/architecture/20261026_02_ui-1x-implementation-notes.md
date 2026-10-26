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
