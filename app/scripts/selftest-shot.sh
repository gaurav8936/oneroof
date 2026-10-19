#!/usr/bin/env bash
# Capture One Roof in-process (no screen takeover): scripts/selftest-shot.sh <name> [VAR=value ...]
# Uses a scratch store, the demo sessions, and quits after the snapshot. Output: $OUT_DIR/<name>.png/.json/.txt
set -euo pipefail
cd "$(dirname "$0")/.."
NAME="$1"; shift
OUT_DIR="${OUT_DIR:-/tmp/oneroof-shots}"
mkdir -p "$OUT_DIR/store-$NAME"
APP="build/One Roof.app/Contents/MacOS/OneRoof"
env ONEROOF_STORE="$OUT_DIR/store-$NAME/sessions.sqlite" ONEROOF_SELFTEST_DEMO=1 ONEROOF_SELFTEST_QUIT=1 \
    ONEROOF_SELFTEST_OUT="$OUT_DIR/$NAME" "$@" "$APP" >/dev/null 2>&1 &
PID=$!
for _ in $(seq 1 60); do kill -0 $PID 2>/dev/null || break; sleep 1; done
kill $PID 2>/dev/null || true
ls -la "$OUT_DIR/$NAME.png" 2>/dev/null || echo "no capture for $NAME"
