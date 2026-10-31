#!/usr/bin/env bash
# oneroof · LAB-1934: Settings › Seats & accounts fields must look editable and save what is typed (needs a built app;
# uses a throwaway profile and roofd, so it never touches your settings or sessions).
#
#   tools/settings-fields-check.sh [path/to/One Roof.app]      default: app/build/One Roof.app
#
# Opens the page, gives every agent's Model and Extra arguments field the keyboard, types into it, and fails unless
# every field is drawn as a box (bezeled), takes the keys, shows the text, and the saved settings hold it.
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
APP="${1:-$ROOT/app/build/One Roof.app}"
OUT="$(mktemp -d)/fields"
RD="$(mktemp -d /tmp/oneroof-fields.XXXX)"
env ROOFD_DIR="$RD" ONEROOF_FRESH_PROFILE=1 ONEROOF_STORE="$OUT.sqlite" ONEROOF_SELFTEST_UI2=1 ONEROOF_SELFTEST_EDITAGENTS=1 \
    ONEROOF_SELFTEST_WAIT=40 ONEROOF_SELFTEST_QUIT=1 ONEROOF_SELFTEST_OUT="$OUT" "$APP/Contents/MacOS/OneRoof" >/dev/null 2>&1 &
pid=$!
for _ in $(seq 1 90); do kill -0 $pid 2>/dev/null || break; sleep 1; done
kill $pid 2>/dev/null || true
kill $(lsof -t "$RD/roofd.lock" 2>/dev/null) 2>/dev/null || true
R="$OUT.editagents.txt"
[ -f "$R" ] || { echo "settings-fields: no result (did Settings open?)" >&2; exit 1; }
grep -q '^done$' "$R" || { echo "FAIL the probe did not finish"; cat "$R"; exit 1; }
bad=0
n=$(grep -c '^#' "$R")
[ "$n" -ge 10 ] && echo "ok   $n Model / Extra arguments fields found" || { echo "FAIL only $n fields found (want 10)"; bad=1; }
grep '^#' "$R" | grep -qv 'bezeled=true' && { echo "FAIL a field is drawn without a box (looks like a label):"; grep '^#' "$R" | grep -v 'bezeled=true'; bad=1; } || echo "ok   every field is drawn as a box"
grep '^#' "$R" | grep -qv 'editing=true' && { echo "FAIL a field did not take the keyboard"; bad=1; } || echo "ok   every field takes the keyboard"
for i in $(seq 0 $((n - 1))); do grep -q "^#$i .*shows=\"p$i\"" "$R" || { echo "FAIL field $i does not show what was typed"; bad=1; }; done
for a in claude codex gemini agy kimi; do grep -q "^saved $a: model=p[0-9] args=p[0-9]$" "$R" || { echo "FAIL $a: typed values were not saved"; bad=1; }; done
[ $bad -eq 0 ] && echo "ok   typed values are saved for every agent"
exit $bad
