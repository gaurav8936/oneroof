#!/usr/bin/env bash
# oneroof · check terminal basics in the real app before a release (needs herdr running and a built app).
#
#   tools/terminal-basics.sh [path/to/One Roof.app]      default: app/build/One Roof.app
#
# Opens a herdr-attached terminal in a throwaway profile, types a marker, selects it with a mouse drag (herdr turns
# on mouse reporting, so this is the case that broke before), copies, pastes, and fails unless all of it worked.
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
APP="${1:-$ROOT/app/build/One Roof.app}"
OUT="$(mktemp -d)/basics"
command -v herdr >/dev/null || { echo "terminal-basics: herdr not installed" >&2; exit 2; }
env ONEROOF_FRESH_PROFILE=1 ONEROOF_STORE="$OUT.sqlite" ONEROOF_SELFTEST_QUIT=1 ONEROOF_SELFTEST_OUT="$OUT" \
    ONEROOF_SELFTEST_TERMINAL=1 ONEROOF_SELFTEST_WAIT=7 ONEROOF_SELFTEST_TYPE="echo ONEROOF-COPY-MARKER-42" \
    ONEROOF_SELFTEST_COPYTEST=1 "$APP/Contents/MacOS/OneRoof" >/dev/null 2>&1 &
pid=$!
for _ in $(seq 1 60); do kill -0 $pid 2>/dev/null || break; sleep 1; done
kill $pid 2>/dev/null || true
R="$OUT.copytest.txt"
[ -f "$R" ] || { echo "terminal-basics: no result (did a terminal open?)" >&2; exit 1; }
bad=0
grep -q "selection after drag: true" "$R" && echo "ok   a mouse drag selects text" || { echo "FAIL a mouse drag selects text"; bad=1; }
grep -q "ONEROOF-COPY-MARKER-42" "$R" && echo "ok   Copy puts the selection on the clipboard" || { echo "FAIL Copy puts the selection on the clipboard"; bad=1; }
grep -q "paste reached the terminal: true" "$R" && echo "ok   Paste types the clipboard into the terminal" || { echo "FAIL Paste types the clipboard into the terminal"; bad=1; }
grep -q "mouse captured by the program: true" "$R" && echo "ok   (the program had mouse reporting on, the hard case)" || echo "note the program did not turn on mouse reporting; the hard case was not exercised"
[ "$bad" = 0 ] && echo "terminal-basics: all good" || { echo "terminal-basics: FAILED (details: $R)"; exit 1; }
