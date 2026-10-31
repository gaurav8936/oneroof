# One Roof app — agent rules (UI v2)

Copied from the UI v2 packet (`labs/oneroof-local/ui_mockups/20261018_01_initial_v2/OneRoof_v2_Transfer/01_handover/AGENT_RULES.md`, local-only). Binding for every agent working in `labs/oneroof/app`. Deviations: `IMPLEMENTATION_NOTES.md`.


Binding. Copy into `labs/oneroof/app/CLAUDE.md` and `AGENTS.md`.

## 1. Goal
Ship the v2 interface on top of the existing v0.1 app. **Nothing that works today is removed** (see GAPS.md §1 for the full feature list that must survive). New: captions, FYI feed, Decisions, Subagents trace, editor with Run/Debug, Review changes, intake + routing sheet, three-theme palette per panel.

## 2. Source of truth (per page)
`pages/<id>/SPEC.md` §1 → §2 → §3 → §4 → `theme/tokens.json` → `screenshots/` + `reference/*.dc.html` artboard.
- Behaviour that exists today (herdr, launch, accounts, Linear, objectives, self-test): the current code and the T-series docs win.
- Look, layout, copy: this packet wins.
- Record any conflict in `IMPLEMENTATION_NOTES.md`.

## 3. Stack (unchanged)
- SwiftPM, `swift-tools-version:6.0`, macOS 14+, Swift 5 language mode on every target.
- AppKit owns app, menus (built in code), window, `NSSplitViewController`, sheets, terminal `NSView`s. SwiftUI draws every panel and centre view inside `NSHostingController` / `NSHostingView` with `sizingOptions = []`. One exception: the centre's file tab strip (`CentreTabStrip`) uses `.intrinsicContentSize`, so it is 30 pt while a file is open and takes no space otherwise.
- libghostty (GhosttyKit.xcframework, Ghostty v1.3.1) is the only linked third-party library. herdr 0.9.5 is the only runtime. llama-server (Homebrew llama.cpp, MIT) and the on-device model (Qwen3-1.7B, Apache-2.0, since 0.5.2; Arch-Router before) are optional and never linked; third-party licences are listed in `THIRD-PARTY-NOTICES.md`.
- **No new dependencies.** The editor is built on `NSTextView` (TextKit 2) with a small in-house tokenizer; diffs come from `git diff --numstat` / `git diff -U3` run through `Foundations.run`-style process calls; no SwiftTerm, no tree-sitter, no Sparkle, no web framework.
- New pure logic goes in `OneRoofCore` (no AppKit/SwiftUI): `Captions.swift`, `Feed.swift`, `Decisions.swift`, `Subagents.swift`, `FileClaims.swift`, `Schedules.swift`, `ThemeV2.swift`.
- New views go in `Sources/OneRoof/UI/` with the names in README §3.

## 4. Styling
- Colours come only from `ThemeTokens` (generated from `theme/tokens.json`). **No hex literals in views.** Agent, status and sticker colours are tokens too.
- Fonts: system **SF Pro** (UI) and **SF Mono** (labels, code, ids). The mocks use Geist/Geist Mono as a browser stand-in; do not bundle Geist (licence rule: MIT/Apache/BSD/public domain only). Terminal font stays in the Ghostty config.
- Sizes in the specs are points. Type scale, spacing and radii: shared/APPEARANCE.md §4.
- Corners: window 12 · cards 12 · rows 9 · buttons 7 · chips 999 · agent squircle 6 (20 pt) to 9 (40 pt). Never 0, never more than 18.
- Every interactive element: hover (selection token at 50%), pressed (selection token), keyboard focus ring (accent, 2 pt, offset 2). Respect Reduce Motion and Increase Contrast.

## 5. Appearance
- Three themes: **Daylight · Graphite · Midnight**. Each of the four panels (Sessions, Files, Terminal, Plan) and the centre views pick one independently. Defaults: Sessions Daylight · Files Daylight · Terminal Midnight · Plan Graphite · centre views Daylight.
- The v0.1 themes map: Light → Daylight, Dim → Graphite, Dark → Midnight; **Paper is retired** (owner, 2026-10-18: "no off-white paper"); Blueprint is kept as a hidden terminal-only theme until the owner decides (GAPS.md D4).
- Persist in `UserDefaults` key `panelThemes.v2`; migrate `panelThemes` once.
- A page is done only when checked in all three themes on every panel it touches, with contrast tests passing (body 4.5:1, status 3:1).

## 6. Data
- herdr snapshot (1 s), SQLite, usage files (30 s), Linear (on demand), workspace files read in place. Never copy `_common` or agentic-engineering content; the AE folder is resolved by `AEFolder` (env → bundled `agentic_engineering/`). One Roof authors no agentic-engineering content (LAB-1257): skills, Learn bands/track names/kinds and the hooks come from the packaged deck (1.9.2: no course, LAB-1274); routing.json/roles.json are app config in `Resources/agent-routing/`.
- Captions and the decision "why" come from the caption engine (shared/ENGINES.md). The model is optional: every engine has a deterministic fallback, and the UI shows the fallback immediately.
- Write actions that need APIs not yet wired (e.g. Linear comment on handoff) render but stay inert, labelled "not connected", never faked.

## 7. Performance
- Sidebar and Board virtualise (`LazyVStack` inside `ScrollView`, stable ids). 60 sessions × 6 windows must scroll at 120 Hz.
- Captions update at most once per 5 s per session; feed keeps 200 events in memory, 7 days in SQLite.
- Terminal surfaces stay cached per session (today's behaviour); chapter folding is a view over the scrollback, never a re-render of the PTY.

## 8. Done (per page)
- SPEC §6 Acceptance ticked in Daylight, Graphite and Midnight at window sizes 1440×900, 1280×800 and 1700×1000.
- Keyboard reachable; VoiceOver labels on every row, badge and button.
- No console errors; no hex in new views.
- One XCTest per NAV / ACTION / SELECT / STATE / VIEW / LIVE row in §2, named by row id (`test_S03_D_1_allowOnce`).
- One self-test capture per state using `ONEROOF_SELFTEST_*` (add the new variables listed in each SPEC §5), compared against the design artboard.

## 9. Don'ts
- Don't send keystrokes with System Events; use the in-process self-test or `scripts/ax-drive.swift`.
- Don't remove a v0.1 menu item or shortcut (shared/SHORTCUTS.md is the contract).
- Don't auto-merge or auto-commit anything; schedules only start runs. Sessions start in the owner's chosen permission mode per agent (Settings › Permissions: Manual · Plan · Auto · Full), **Auto by default since 2026-10-29 (LAB-1600); Antigravity Full by default since 2026-10-31 (LAB-1935)**, and each mode's flags are editable; One Roof itself never answers an agent's permission prompt. Decisions: `docs/decisions/20261029_01_permission-mode-per-agent.md`, `docs/decisions/20261031_01_full-permission-mode-antigravity-default.md`.
- Don't invent agent output. Captions say "no caption yet" until there is one.
- Don't use emoji in UI. Glyphs allowed: → ↗ ▸ ▾ ✓ ✕ ● ⏱ ⌘ ⌥ ⇧ ⌃ ↩.

## 10. Where docs go
- User help: `docs/help/` (one page per area, Markdown, bundled into the app). Architecture decisions: `docs/decisions/`. The kit's design: `docs/architecture/`.
- Release notes: `CHANGELOG.md` at the repo root (bundled as the app's release notes).
