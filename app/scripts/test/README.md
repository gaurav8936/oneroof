# oneroof-test — the release test harness

One command from the terminal runs One Roof's functional journeys, its performance against the previous release, a
side-by-side with Warp and the simulator, and writes one report to review (LAB-ONEROOF-SIMULATOR, LAB-1594…1599).

```
app/scripts/oneroof-test                    # build this checkout, run every suite (~20 min)
app/scripts/oneroof-test --quick            # shorter perf windows (~8 min with the build)
app/scripts/oneroof-test --suite functional --app "/path/One Roof.app"
app/scripts/oneroof-test --gate 1.9.24      # release gate: writes scratchpad/perf/release-1.9.24/result.json on PASS
```

Options: `--quick`, `--suite functional,perf,compare,sim`, `--app <bundle>`, `--baseline <version|file|dir>`,
`--out <dir>`, `--gate <version>`, `--profile <dir>`, `--limits <json>`, `--secs <n>` (perf-check window).
Exit 0 PASS · 1 FAIL · 2 usage or environment (no profile, an install running, build failed).

## Safety

Everything runs on a **test copy**: the bundle is copied, re-identified (`io.github.gaurav8936.oneroof.perf`) and
ad-hoc signed; every launch gets a copy of the owner's profile (`make-profile.sh`: an online sqlite backup of the store
and an export of the defaults, both read only), its own roofd under a short `ROOFD_DIR` in `/tmp/claude-$UID`, and a
minimal environment (`env -i`: the calling shell may point at the live roofd through `ONEROOF_ROOFD*`). After each run
the copy's roofd is stopped and the bundle unregistered from Launch Services. The installed roofd's pid and build are
checked before and after; a change fails the run. One test instance runs at a time.

## Suites

| Suite | Required | What it does |
|---|---|---|
| functional | yes | `journeys/functional.txt` through the in-app self-test: three windows, sessions in each, switch sessions and windows, Focus steps 0–3 and back, drag the Sessions edge closed and reopen it, Full/Wide, window resize with terminal text kept whole, Needs you, session catalog (open, search, resume a row), close a session. Every `expect` / `textcount` logs `CHECK PASS|FAIL`; every journey has screenshots. Any FAIL, or a run that does not reach its last step, fails the suite. |
| perf | yes | `scripts/perf/perf-check.sh` (idle, places, spinners6, memory; `--quick`: idle, places) plus `journeys/gestures.txt`: window resize (shrink, grow, wiggle), Sessions edge drag, Full/Wide/Focus/Sessions steps. Per gesture: main-thread gaps and hitch time (4 ms run-loop timer), display frames (display link), terminal size changes sent (grid changes), settle time, and the terminal text checked for stacked copies after the resizes. Compared with the newest `scratchpad/perf/baseline-<v>.json` older than this version under `limits.json`; a passing full run stores `baseline-<this version>.json`. |
| compare | no | `compare.py`: Warp and One Roof's test copy measured the same way from the outside (ps for CPU/RSS of every process of each app, System Events for window resizes, screencapture of the window's rectangle for redraw settle and in-between frames). Warp's files, settings and data are never read. Measures that cannot be taken fairly are listed as not taken, with the reason. |
| sim | no | Calls `app/scripts/sim/simulate.sh --app <copy> --out <run>/sim` when it exists; skipped with a note otherwise. |

## Release gate (`--gate <version>`)

Requires the app's version to be `<version>`, a full run (no `--quick`) and both required suites. Only when the run
PASSes it writes `scratchpad/perf/release-<version>/result.json` in the shape `scratchpad/ship-picks.sh` checks
(`{"version": "<v>", "fails": [], …}`) plus `report.md`; on FAIL nothing is written, so the release script refuses to ship.

## The screen must be unlocked for the full picture

With the Mac's screen locked nothing draws: libghostty makes no terminal surfaces, the display link does not tick and
screencapture sees nothing. The harness detects this (`CGSSessionScreenIsLocked`) and reports terminal size changes,
display frames, settle time and Warp redraw timing as **not measured**; main-thread gaps, CPU, memory and the terminal
text (read from roofd instead of the surface) are still measured. A baseline taken with the screen in the other state
is compared for information only.

## Files

- `../oneroof-test` — the entry point; `run-app.sh` — one self-test run on a profile copy; `make-profile.sh`.
- `journeys/functional.txt`, `journeys/gestures.txt` — the scripts (`##` lines name journeys; steps in `SelfTestScript.swift` and `SelfTestHarness.swift`).
- `functional.py`, `perf.py`, `compare.py`, `report.py` — one JSON per suite, then `report.md` + `report.html` + `summary.json`.
- `limits.json` — regression percentage, per-measure minimum change, per-gesture budgets.

Report folder (default `scratchpad/test-runs/<version>-<timestamp>/` in the main checkout): `report.md`, `report.html`,
`summary.json`, `env.json`, `functional/` (log, screenshots), `perf/scenarios/` (perf-check), `perf/gestures/`, `compare/`, `sim/`.

## New self-test steps (SelfTestHarness)

`expect <key> <op> <value>` (keys: windows, openwindows, window, sessions, live, allsessions, alllive, centre, place,
focusstep, selected, decisions, catalog, searchhits, gridchanges, termsurface, sessionsopen, filesopen, width, height,
paneswidth; ops `= != >= <= > < ~`; `@key` = a value saved with `mark <key>`), `newwindow <name>`,
`switchwindow <name|#n>`, `selectindex <n>`, `place <place>`, `search <query>`, `textcount <needle> <op> <n>`,
`hitch start` / `hitch stop <label>`, `gesturemark`, `resizegesture <from> <to> <ms>`, `windowsize <w> <h>`.
