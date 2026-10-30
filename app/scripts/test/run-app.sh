#!/usr/bin/env bash
# run-app.sh — one self-test script run of a One Roof TEST COPY on a COPY of a profile (LAB-1595).
#
#   run-app.sh <One Roof.app> <script.txt> <run dir> <profile dir> [timeout s]
#
# <profile dir> holds sessions.sqlite + defaults.plist (a copy; oneroof-test makes it). The run gets its own store copy,
# its own roofd (short ROOFD_DIR under /tmp/claude-$UID, socket path ≤104 chars) and a minimal environment (env -i), so
# the installed app, its roofd and the owner's store are never touched. Afterwards the run's roofd is stopped and the
# bundle unregistered from Launch Services. Output: <run dir>/st-log.txt, st-*.png/json/txt, app.log.
set -u
APP=$1; SCRIPT=$2; RUN=$3; PROFILE=$4; LIMIT=${5:-600}
HERE="$(cd "$(dirname "$0")" && pwd)"; APPDIR="$(cd "$HERE/../.." && pwd)"
BIN="$APP/Contents/MacOS/OneRoof"
[ -x "$BIN" ] || { echo "run-app: no app at $APP" >&2; exit 2; }
mkdir -p "$RUN/work"; RUN="$(cd "$RUN" && pwd)"
cp "$PROFILE/sessions.sqlite" "$RUN/store.sqlite"
sed "s|@DIR@|$RUN/work|g" "$SCRIPT" > "$RUN/script.txt"
BASE=/tmp/claude-$(id -u); mkdir -p "$BASE"; RD=$(mktemp -d "$BASE/ort.XXXX"); chmod 700 "$RD"
env -i HOME="$HOME" USER="${USER:-$(id -un)}" LOGNAME="${LOGNAME:-$(id -un)}" SHELL="${SHELL:-/bin/zsh}" \
    PATH="/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin" LANG=en_US.UTF-8 TMPDIR="${TMPDIR:-/tmp/}" \
    ONEROOF_FRESH_PROFILE=1 ONEROOF_PROFILE_SEED="$PROFILE/defaults.plist" ONEROOF_STORE="$RUN/store.sqlite" \
    ONEROOF_SELFTEST_DEMO=0 ONEROOF_SELFTEST_UI2=1 ONEROOF_SELFTEST_SCRIPT="$RUN/script.txt" ONEROOF_SELFTEST_OUT="$RUN/st" \
    ROOFD_DIR="$RD" "$BIN" > "$RUN/app.log" 2>&1 &
PID=$!
T0=$(date +%s)
while kill -0 "$PID" 2>/dev/null; do
  grep -qE " (done|quit)$" "$RUN/st-log.txt" 2>/dev/null && { sleep 2; break; }
  [ $(( $(date +%s) - T0 )) -ge "$LIMIT" ] && { echo "$(date +%s) TIMEOUT after ${LIMIT}s" >> "$RUN/st-log.txt"; break; }
  sleep 1
done
echo "$(( $(date +%s) - T0 ))" > "$RUN/seconds.txt"
kill -0 "$PID" 2>/dev/null && { kill "$PID" 2>/dev/null; sleep 2; kill -9 "$PID" 2>/dev/null; }
wait "$PID" 2>/dev/null; echo "$?" > "$RUN/exit.txt"
bash "$APPDIR/scripts/stop-test-roofd.sh" "$(dirname "$APP")" >/dev/null 2>&1
rm -rf "$RD"
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -u "$APP" 2>/dev/null
exit 0
