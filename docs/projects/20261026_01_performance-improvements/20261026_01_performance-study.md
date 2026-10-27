# One Roof performance study (1.9.3)

**Status:** DONE · **Date:** 2026-10-26 · **Project:** LAB-ONEROOF-UI-REDESIGN · **Linear:** LAB-1287 · **Plan:** [README.md](README.md) · **Follow-up:** project LAB-ONEROOF-PERFORMANCE-IMPROVEMENTS (LAB-1314 to LAB-1338)

> **One line:** One Roof re-renders its whole window about twice a second even when nothing changes, and each re-render runs a few expensive lookups inside SwiftUI view code; that idle churn, not the terminals, is why it feels jerky next to Warp.

## How it was measured

- A code review of every timer, poll, observer and view (20 findings).
- Live measurement on an M1 Pro MacBook Pro (macOS 15.8.1) of the installed 1.9.3 against Warp 0.2026.10.21, observe-only.
- An unhardened build of the same code on a copy of the session list, under scripted scenarios: idle, Learn playing, Grid with busy terminals, typing, switching places, resize, Machine view, hidden terminals, memory growth, process launches, startup. Every scenario ran at least twice, with load recorded per run.
- Tools: `top`, `ps`, `sample`, `xctrace` Time Profiler, kqueue and libproc for child processes. Animation Hitches and the SwiftUI template need administrator rights, so stalls are counted from Time Profiler instead (a run of busy main-thread samples of 50 ms or more counts as a visible hitch).

## Results

| Measure | One Roof | Warp |
|---|---|---|
| Idle CPU, installed, one agent working, 33 sessions (2 × 120 s) | 40.0 % ± 2.4 | 0.39 % |
| Idle CPU, installed, no agent working | 13.4 % | 0.25 % |
| Idle CPU, test build, no live sessions | 9.5 % | – |
| Context switches per second (wake-up proxy), first row | 1,531 | 171 |
| Memory footprint, first row | 533 MB | 194 MB |
| Main-thread stalls of 50 ms or more at idle | 58 per minute (longest ~110 ms) | – |
| Switching places once a second | 29 % CPU, ~250 ms stall per second | – |
| Background processes started | 242–318 per minute, nearly all `git` (~6 % of a core) | – |
| Memory per terminal visited | +30 MB, never freed (96 → 398 MB over 10) | – |
| Five terminals printing at full speed | app 165–202 %, plus roofd 233–295 % | – |
| Launch to first window | 553 ms ± 26 | not measured |

Warp had no window and no shells open, so its numbers are the floor for a quiet native app, not a peer with 33 sessions. The fair reading is One Roof's own idle cost with no live sessions, 9.5 %, which should be close to zero.

## Where the main thread goes at idle

The model announces a change 2 times a second with nothing happening, and about 100 views re-evaluate each time. Inside that update:

| Item | Share of main-thread busy time | Code |
|---|---|---|
| Handoff lookup in the exited-session placeholder (lists and stats 161 files, regex each) | 20 % | `UI/PaneChrome.swift` `PanePlaceholder.body` → `Workspace.handoffMatch` |
| Session tab strip measuring itself | 18 % | `MainWindowController.swift` `NoIdealWidth.HeightOnly` |
| "Related in Learn" ranking all 156 cards | 16 % (25 % switching places) | `UI/PlanPanelView.swift` `relatedInLearn` → `AppModel.learnCards` |
| Everything else in the update | 46 % | view re-evaluation, drawing, Core Animation commits |

With an agent working, the installed app's main thread is 35–40 % busy, mostly per-frame drawing driven by the running dot's endless SwiftUI animation (`StatusDot`, strong but indirect evidence).

## Recommendations (ranked; filed as Linear issues)

1. **LAB-1314** Stop the model announcing changes when nothing changed (S); later split the model or adopt `@Observable` (L).
2. **LAB-1315** Move the handoff lookup out of the view body; compute on exit, cache (S).
3. **LAB-1316** Cache "Related in Learn" per session, off the main thread (S).
4. **LAB-1317** Fixed height for the session tab strip (S).
5. **LAB-1318** Running dot as a Core Animation layer or static (S).
6. **LAB-1319** Repo stats only for running, visible sessions, on file changes; cache "not a repo" (S).
7. **LAB-1320** Tell hidden terminals they are hidden (libghostty occlusion) (S).
8. **LAB-1321** Keep 6–8 terminals alive, cap scrollback (M).
9. **LAB-1322** Event-driven roofd session processes (M).
10. **LAB-1323** App Nap and timer tolerance (S).
11. **LAB-1324** Study the heavy-output path before changing it (L, spike).

Items 1–7 make a first tuning release: small, low-risk, aimed at the idle stall and the work done while nothing changes.

## Where the measurements corrected the code review

- The two biggest idle items (handoff lookup, "Related in Learn") were not in the review.
- The model updates twice a second, not once.
- Starting git processes does not block the main thread; it costs background CPU, far more than estimated.
- Terminal pane rendering and the model rebuild are cheap (under 1.5 % each).
- Not observed: SQLite on the main thread, the old Wrap view, the on-device caption model (not running).

## Limits

- No frame-hitch or SwiftUI body counts (need administrator rights).
- Live drag-resizing not measured (the scenario jumped the width every 2 s).
- Two installs by other sessions happened during the study; affected runs were redone.
- Raw runs, scripts, the live results and the static audit are kept locally with the study data (not in this public repo).
