#!/usr/bin/env bash
# perf-check.sh — One Roof's repeatable performance check (LAB-1325). One command: build a test copy, run the
# scenarios on a copy of a real profile, measure, compare with the baseline and the phase gate.
#
#   scripts/perf/perf-check.sh [--app <One Roof.app>] [--scenarios idle,places,spinners6,memory] [--gate <phase>]
#                              [--baseline <json>] [--out <dir>] [--secs 60] [--tp 20]
#
#   --app        measure this bundle (copied, re-identified); default: build this checkout (scripts/bundle.sh release)
#   --scenarios  comma list from scenarios/ (idle home places spinners6 memory learn); default idle,places,spinners6,memory
#   --gate       a phase in gates.json (1.9.8 …): its thresholds must hold too; default none (baseline check only)
#   --baseline   default baseline-1.9.3.json (the study's numbers); a headline >15 % worse than it fails the check
#   --secs/--tp  measurement window and Time Profiler window, seconds
#
# The test copy gets its own bundle id (io.github.gaurav8936.oneroof.perf), its own roofd (ROOFD_DIR under /tmp), a
# scratch home (CFFIXED_USER_HOME) and a copy of the profile in $ONEROOF_PERF_PROFILE (sessions.sqlite +
# defaults.plist; default: scratchpad/perf-profile in the main checkout, git-ignored, never committed). The installed app and its roofd
# are never touched: the check verifies the installed roofd's pid and build before and after.
# Exit: 0 pass · 1 regression or gate miss · 2 usage / environment.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"; APPDIR="$(cd "$HERE/../.." && pwd)"; REPO="$(cd "$APPDIR/.." && pwd)"
SCEN="idle,places,spinners6,memory"; GATE=""; BASE="$HERE/baseline-1.9.3.json"; SRC=""; SECS=60; TP=20
OUT="$REPO/scratchpad/perf/$(date +%Y%m%d-%H%M%S)"
while [ $# -gt 0 ]; do case "$1" in
  --app) SRC=$2; shift 2 ;; --scenarios) SCEN=$2; shift 2 ;; --gate) GATE=$2; shift 2 ;; --baseline) BASE=$2; shift 2 ;;
  --out) OUT=$2; shift 2 ;; --secs) SECS=$2; shift 2 ;; --tp) TP=$2; shift 2 ;;
  -h|--help) sed -n 2,20p "$0"; exit 0 ;; *) echo "perf-check: unknown option $1" >&2; exit 2 ;; esac; done
MAIN="$(cd "$(git -C "$REPO" rev-parse --path-format=absolute --git-common-dir)/.." && pwd)"   # the main checkout, also from a worktree
PROFILE="${ONEROOF_PERF_PROFILE:-$MAIN/scratchpad/perf-profile}"
[ -f "$PROFILE/sessions.sqlite" ] || { echo "perf-check: no profile at $PROFILE (set ONEROOF_PERF_PROFILE)" >&2; exit 2; }
pgrep -f oneroof-install >/dev/null && { echo "perf-check: an install is running (it quits test builds); try later" >&2; exit 2; }
mkdir -p "$OUT"; OUT="$(cd "$OUT" && pwd)"; LOG="$OUT/perf-check.log"; say() { echo "$*" | tee -a "$LOG"; }
FAILED=""

# ── the test copy ──
BUILD="$OUT/build"; APP="$BUILD/One Roof.app"; mkdir -p "$BUILD"
if [ -z "$SRC" ]; then
  say "building this checkout (release)…"
  (cd "$APPDIR" && ONEROOF_BUNDLE_OUT="$BUILD" bash scripts/bundle.sh release) >> "$LOG" 2>&1 || { say "perf-check: build failed (see $LOG)"; exit 2; }
else
  ditto "$SRC" "$APP"
fi
[ -x "$APP/Contents/MacOS/OneRoof" ] || { say "perf-check: no app at $APP"; exit 2; }
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier io.github.gaurav8936.oneroof.perf" "$APP/Contents/Info.plist"
codesign --force --deep -s - "$APP" >> "$LOG" 2>&1
VERSION=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$APP/Contents/Info.plist")
BIN="$APP/Contents/MacOS/OneRoof"

INST="/Applications/One Roof.app/Contents/MacOS/roofd"
installed() { [ -x "$INST" ] && ROOFD_DIR="$HOME/Library/Application Support/One Roof/roofd" "$INST" hello 2>/dev/null |
  python3 -c 'import json,sys;d=json.load(sys.stdin);print(d["pid"],d["build"])' 2>/dev/null || echo none; }
BEFORE=$(installed)

H=/tmp/orperf-home; RD=/tmp/orperf-rd; WORKDIR="$OUT/work"
mkdir -p "$H/Library/Application Support" "$H/Library/Preferences" "$WORKDIR" && mkdir -p "$RD" && chmod 700 "$RD"
ln -sfn "$HOME/Projects" "$H/Projects"; [ -e "$H/.claude" ] || ln -sfn "$HOME/.claude" "$H/.claude"

cleanup() {
  for p in $(pgrep -f "^$BIN"); do kill "$p" 2>/dev/null; done; sleep 2
  for p in $(pgrep -f "^$BIN"); do kill -9 "$p" 2>/dev/null; done
  bash "$APPDIR/scripts/stop-test-roofd.sh" "$BUILD" >> "$LOG" 2>&1
  rm -f "$RD"/*.sock 2>/dev/null
}
trap 'cleanup; /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -u "$APP" 2>/dev/null' EXIT

launch() {   # launch <run dir> <scenario file> [VAR=value …] → pid
  local d=$1 s=$2; shift 2
  cp "$PROFILE/sessions.sqlite" "$d/store.sqlite"
  sed "s|@DIR@|$WORKDIR|g" "$s" > "$d/script.txt"
  env ONEROOF_FRESH_PROFILE=1 ONEROOF_PROFILE_SEED="$PROFILE/defaults.plist" ONEROOF_STORE="$d/store.sqlite" \
      ONEROOF_SELFTEST_DEMO=0 ONEROOF_SELFTEST_UI2=1 ROOFD_DIR="$RD" CFFIXED_USER_HOME="$H" \
      ONEROOF_SELFTEST_SCRIPT="$d/script.txt" ONEROOF_SELFTEST_OUT="$d/st" "$@" "$BIN" > "$d/app-stdout.txt" 2>&1 &
  echo $!
}

run_window() {   # run_window <name> <warm s> [VAR=value …]  — the standard scenario: warm up, measure, profile
  local name=$1 warm=$2; shift 2; local d="$OUT/$name"; mkdir -p "$d"
  local f="$HERE/scenarios/$name.txt"; [ "$name" = learn ] && f="$HERE/scenarios/idle.txt"
  say "· $name: launch, warm ${warm}s, measure ${SECS}s, profile ${TP}s (load $(sysctl -n vm.loadavg))"
  local pid; pid=$(launch "$d" "$f" "$@"); sleep "$warm"
  kill -0 "$pid" 2>/dev/null || { say "  $name: the app exited during warm-up"; FAILED="$FAILED $name"; cleanup; return 1; }
  python3 "$HERE/measure.py" "$d" "$SECS" "$pid" "$d/st-log.txt" > /dev/null
  xcrun xctrace record --template 'Time Profiler' --attach "$pid" --time-limit "${TP}s" --output "$d/tp.trace" > "$d/tp.log" 2>&1 &&
    python3 "$HERE/parse_tp.py" "$d/tp.trace" "$d/tp.json" > /dev/null
  rm -rf "$d/tp.trace"
  cleanup
}

run_memory() {   # 10 terminals with scrollback visited in turn; footprint every 2 s
  local d="$OUT/memory"; mkdir -p "$d"; say "· memory: 10 terminals visited, footprint every 2 s"
  local pid; pid=$(launch "$d" "$HERE/scenarios/memory.txt"); local t0; t0=$(date +%s)
  while kill -0 "$pid" 2>/dev/null && [ $(( $(date +%s) - t0 )) -le 150 ]; do
    echo "$(( $(date +%s) - t0 )) $(top -l 1 -pid "$pid" -stats mem | tail -1)" >> "$d/mem.txt"; sleep 2
  done
  cleanup
}

IFS=, read -r -a LIST <<< "$SCEN"
for s in "${LIST[@]}"; do case "$s" in
  memory) run_memory ;;
  spinners6) run_window spinners6 25 ;;
  learn) run_window learn 15 ONEROOF_SELFTEST_PLACE=learn ONEROOF_SELFTEST_PLAYCARD=loops-first@muted ;;
  idle|home|places) run_window "$s" 15 ;;
  *) say "perf-check: unknown scenario $s"; exit 2 ;; esac; done

AFTER=$(installed)
[ "$BEFORE" = "$AFTER" ] || say "⚠ INSTALLED ROOFD CHANGED during the check: $BEFORE → $AFTER"
python3 "$HERE/report.py" "$OUT" "$VERSION" "$BASE" "$HERE/gates.json" "$GATE" | tee -a "$LOG"
rc=${PIPESTATUS[0]}
[ -n "$FAILED" ] && { say "**FAIL**: no measurement for:$FAILED"; rc=1; }
exit "$rc"
