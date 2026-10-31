#!/usr/bin/env bash
# loops-guard-test.sh — LAB-2001 self-check: the scratch shared folder copies loops and links the rest; the guard
# passes on run-state writes and fails on a definition change. Uses a fake shared folder only. Exit 0 = all good.
set -eu
HERE="$(cd "$(dirname "$0")" && pwd)"; T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
export ONEROOF_REAL_SHARED="$T/real"
mkdir -p "$T/real/docs" "$T/real/loops/nightly"; echo '{"id":"nightly"}' > "$T/real/loops/nightly/loop.json"
bash "$HERE/scratch-shared.sh" "$T/scratch" >/dev/null
[ -L "$T/scratch/docs" ] && [ ! -L "$T/scratch/loops" ] && [ -f "$T/scratch/loops/nightly/loop.json" ] || { echo "FAIL: scratch layout"; exit 1; }
echo '{"id":"nightly","migrated":true}' > "$T/scratch/loops/nightly/loop.json"     # a test copy migrates its copy
bash "$HERE/loops-guard.sh" snapshot "$T/before.txt"
echo '{"state":"running"}' > "$T/real/loops/nightly/state.json"; echo '{}' >> "$T/real/loops/nightly/rounds.jsonl"
bash "$HERE/loops-guard.sh" verify "$T/before.txt" >/dev/null || { echo "FAIL: run state counted as a change"; exit 1; }
grep -q migrated "$T/real/loops/nightly/loop.json" && { echo "FAIL: the scratch copy reached the live loop"; exit 1; }
echo '{"id":"nightly","v":2}' > "$T/real/loops/nightly/loop.json"
if bash "$HERE/loops-guard.sh" verify "$T/before.txt" >/dev/null; then echo "FAIL: a definition change passed"; exit 1; fi
echo "loops-guard-test: ok"
