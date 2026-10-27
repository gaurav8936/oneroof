# One Roof performance improvements: implementation proposal

**Status:** PROPOSED · **Date:** 2026-10-26 · **Project:** LAB-ONEROOF-PERFORMANCE-IMPROVEMENTS · **Linear:** LAB-1287 (study), LAB-1314 to LAB-1338 · **Study:** [../../reports/20261026_01_performance-study.md](../../reports/20261026_01_performance-study.md)

> **Release numbering (owner, 2026-10-26):** 1.9.6 is the stable release and development stops after it; 1.9.7 is the Files-panel fix; performance work ships as 1.9.8 onwards, nothing else unless a critical item needs fixing.

> **One line:** fix the measured causes in four releases (1.9.8 to 1.9.11), cheapest and most noticeable first, with a perf check in the repo that proves every change against the 1.9.3 baseline before it ships.

## What "a difference" means

The study measured the feeling. These are the targets the plan is judged by, measured with the perf harness on the same Mac:

| Measure | 1.9.3 today | Target after 1.9.8 | Target after 1.9.10 |
|---|---|---|---|
| Idle CPU, no live sessions | 9.5 % | ≤ 2 % | ≤ 1 % |
| Installed, one agent working, nothing else changing | 40 % | ≤ 8 % | ≤ 5 % |
| Main-thread stalls ≥ 50 ms at idle | 58 / min | ≤ 5 / min | ≤ 2 / min |
| Switching places once a second: stall time | ~250 ms / s | ≤ 60 ms / s | ≤ 30 ms / s |
| Background processes started at idle | 242–318 / min | ≤ 20 / min | ≤ 10 / min |
| Memory after visiting 20 terminals | grows ~30 MB each | (unchanged) | flat |
| Idle session process wake-ups | 10.5 / s each | (unchanged) | ≤ 1 / s each |

Stalls are the number to watch: they are what you see as jerkiness. CPU is what you hear as fans and lose as battery.

## Principles

1. **Measure first, then change.** Every issue names its measured cost and a "done when" number. Nothing is merged on the strength of reasoning alone.
2. **Remove work; don't optimise it.** The study's biggest costs are work that shouldn't happen at all: re-rendering when nothing changed, lookups recomputed inside views, processes started for repos nobody is looking at, terminals drawn that nobody can see.
3. **Small, independent changes in the first release.** 1.9.8 is a set of contained fixes that each stand alone and can be reverted alone. The one structural change (splitting the app model) comes later, once the small fixes have made its effect measurable.
4. **No behaviour change.** Same features, same screens. Each release keeps the visual sign-off rule and adds the perf check next to it.

## Phase 0: the perf harness (before any fix)

| Issue | What |
|---|---|
| LAB-1325 | `app/scripts/perf-check.sh`: builds an unhardened release build with its own bundle id, runs the study's scenarios on a real-profile copy, records CPU, main-thread busy %, stalls (≥ 16.7 ms and ≥ 50 ms), model changes per second, child processes per minute and footprint, compares with `baseline-1.9.3.json` and the phase thresholds, and fails on a regression. |
| LAB-1326 | The release checklist runs it on every candidate and records the table next to the visual sign-off. A regression of more than 15 % on any headline number blocks the release. |

The study's scripts (kept with the raw data) already do most of this; P0 turns them into one command. Without it, later phases can't prove they helped. Estimated effort: a day.

## Phase 1: 1.9.8 "Quiet idle"

The aim: when nothing changes, nothing runs. This is the release you should feel.

| Order | Issue | Change | How |
|---|---|---|---|
| 1 | LAB-1314 | Stop the model announcing changes when nothing changed | Guard every published assignment in the 1 s poll (`runtimeOK`, `runtimeState`, per-session values) with an equality check; move per-session "last active" times out of published state into a plain dictionary that views read when they redraw anyway; stop forwarding each window's change to the app model. Add a debug counter so the harness can read changes per second (already exists in self-test). |
| 2 | LAB-1315 | Handoff lookup out of the view body | Compute a session's handoff match once when it exits, and again only when the handoff folder changes (folder modification time, or an FSEvents stream). Store it on the session; `PanePlaceholder` reads the stored value. |
| 3 | LAB-1316 | "Related in Learn" cached | Rank once per session when its title, objective or last prompt changes, on a background queue; cache the three results on the session; the Plan panel reads them. |
| 4 | LAB-1317 | Session tab strip stops measuring itself | Give the strip its known fixed height (one line of tabs) instead of asking SwiftUI for its size on every update; keep width flexible. |
| 5 | LAB-1318 | Running dot off the main thread | Draw the halo as a Core Animation layer animation (it runs in the render server, not the main thread), or make the dot static with a gentle opacity change only when the status changes; respect Reduce Motion. |
| 6 | LAB-1319 | Repo stats only where they matter | Compute git stats only for running sessions that are on screen, triggered by file changes in that repo (FSEvents) with a 10 s floor, never for exited sessions; cache "not a repo" so the workspace root is never asked again. |
| 7 | LAB-1327 | No git from views or menus | A shared `RepoRoots` cache, filled off the main thread and invalidated by FSEvents; views and menu validation read only the cache. |
| 8 | LAB-1328 | Cheaper poll tick | One lookup table per tick instead of one per session; Dock badge set only when its value changes; remove the `main.sync` from the poll queue. |
| 9 | LAB-1329 | Timers that fire | Move the four view-owned timers into long-lived objects or `.task` loops; add a test that each fires on time while the model churns (protects the editor's save flush). |

**Order and lanes.** Item 1 first, alone, and measure it: it changes how often everything else runs, so later numbers only mean something after it. Then items 2–4 in one lane (all "lookups inside views"), items 5–7 in a second lane (animation and process work), items 8–9 last. Two lanes, each in its own worktree, as in the 1.8–1.9 releases.

**Gate:** idle ≤ 2 % CPU, ≤ 5 stalls ≥ 50 ms per minute, ≤ 20 child processes per minute; installed with one agent working ≤ 8 %. **Effort:** 2–3 days including measurement.

## Phase 2: 1.9.9 "Light in the background"

The aim: no work for things you can't see.

| Issue | Change | How |
|---|---|---|
| LAB-1320 | Hidden terminals stop drawing | Tell libghostty a surface is occluded whenever it's hidden, covered or in a minimised window, and un-occluded just before it's shown (the pattern upstream Ghostty uses). |
| LAB-1323 | App Nap and timer tolerance | Hold the "don't nap" activity only while an agent needs it (the daemon keeps sessions alive anyway); give every timer 10–20 % tolerance; poll every 3–5 s when no window is visible. |
| LAB-1330 | On-device captions | Asynchronous model calls, at most every 30–60 s per session, only for visible sessions or on a status change; skip a tick while a call runs. |
| LAB-1331 | Incremental transcript reading | One shared reader per transcript that keeps a byte offset and parses only appended lines, triggered by a file watcher; used by captions, subagents and the Table view. |
| LAB-1332 | Learn player and readers | Playback progress in its own tiny object that only the scrubber and clock watch; parsed posts and release notes cached by path and modification time. |
| LAB-1333 | Resource monitor | Publish only while a view that shows it is on screen; keep history in an unpublished buffer. |
| LAB-1334 | Foreground marker from roofd | The session process already knows its foreground program; return it in the daemon's session list and delete the per-pane probe. |
| LAB-1335 | Table view refresh | Use the incremental transcript reader; for plain terminals read only new lines; append rendered blocks instead of rebuilding. |

**Gate:** hidden app ≤ 1 % CPU; Learn playing ≤ 5 %; hidden terminals add ≤ 0.5 points; Table view open on a working session adds ≤ 2 points. **Effort:** 3–4 days, two lanes (app side; daemon side for LAB-1334).

## Phase 3: 1.9.10 "Memory, daemon and resize"

| Issue | Change | How |
|---|---|---|
| LAB-1321 | Bounded terminal memory | Keep the 6–8 most recently used terminals live and free the rest (they re-attach to their session on demand, which roofd already supports); set a scrollback limit; free an exited session's terminal at once. |
| LAB-1322 | Quiet session processes | Replace the 200 ms poll and 250 ms status check with waiting on output or a deadline; check status on output, or every 1–2 s when idle. |
| LAB-1336 | No SQLite on the main thread | Batch session updates from the engines; write on the store's own queue; rebuild once. |
| LAB-1337 | Smooth live resize | Skip unchanged paints; do the expensive toolbar and Plan fitting once at the end of a live resize; throttle terminal size updates to the display rate. |
| LAB-1338 | Split the app model | Move to Swift Observation (`@Observable`) so a view re-renders only when a property it reads changes, or split the model into focused stores (sessions, engines, Learn, settings, Linear). Behaviour stays identical; done last in the phase so its gain is visible on top of 1.9.8. |

**Gate:** footprint flat after visiting 20 terminals; idle session process ≤ 1 wake-up per second; a 5 s live resize drag with no stall ≥ 50 ms; a status change in one session re-renders only that session's views. **Effort:** about a week; LAB-1338 is the largest single item and gets its own lane.

## Phase 4: 1.9.11 "Heavy output (decide)"

| Issue | Change |
|---|---|
| LAB-1324 | Measure the per-byte cost of the output path (session process parse, attach relay, libghostty) under the harness's busy-terminal scenario, try parsing less while a terminal is attached, and write a proposal with the expected gain. Change the path only if the gain justifies the risk: this path is what keeps sessions alive across app restarts. |

## Risks and how they're handled

| Risk | Handling |
|---|---|
| Caching hides a real change (a stale handoff match, stale repo stats) | Every cache has an explicit invalidation (file watcher or modification time) and a test that a change shows up within the stated time. |
| Fewer updates make something feel laggy | Status, title and output changes still publish immediately; only unchanged values stop publishing. The harness's place-switch and typing scenarios check responsiveness, and the visual sign-off checks the screens. |
| Occluding or freeing terminals loses output | Output lives in the session process (roofd), not in the app's terminal; a freed terminal re-attaches and redraws from it. Tested by visiting 20 terminals and reading each back. |
| The model split (LAB-1338) touches most views | Done last, behind the measured gains of 1.9.8–1.9.9, in its own lane, with the full test suite and visual sign-off of every place. |
| Daemon changes (LAB-1322, LAB-1334) affect live sessions | Built and tested on a test daemon only; installed through the normal release; sessions survive app swaps, and the release check confirms the daemon after install. |

Every release can be rolled back with the installer and the previous release's zip; the changes are independent enough to revert one by one.

## Timeline

| Release | Content | Rough effort |
|---|---|---|
| P0 | Perf harness, release gate | 1 day |
| 1.9.8 | Quiet idle (9 issues) | 2–3 days |
| 1.9.9 | Light in the background (8 issues) | 3–4 days |
| 1.9.10 | Memory, daemon, resize, model split (5 issues) | about a week |
| 1.9.11 | Heavy output: measure and decide (1 spike) | 1–2 days |

1.9.8 alone should change how the app feels. If it reaches its gate, the remaining phases make the app lighter on battery and memory rather than smoother.
