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
