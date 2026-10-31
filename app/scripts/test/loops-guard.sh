#!/usr/bin/env bash
# loops-guard.sh snapshot|verify <file> — the gate's proof that a test run left the live loops alone (LAB-2001).
# Hashes every loop DEFINITION under the real shared loops folder (loop.json, *.loop.yaml, prompts, scripts, *.bak);
# run state that the live roofd writes while the gate runs (state.json, rounds.jsonl, logs, caches) is left out.
# verify exits 1 and lists what changed. The real shared folder: $ONEROOF_REAL_SHARED, else ~/Projects/_common.
set -u
MODE=$1; FILE=$2
LOOPS="${ONEROOF_REAL_SHARED:-$HOME/Projects/_common}/loops"
snap() {
  [ -d "$LOOPS" ] || return 0
  (cd "$LOOPS" && find . -type f ! -name state.json ! -name rounds.jsonl ! -name '*.log' ! -path '*/__pycache__/*' \
     ! -path '*/.events/*' ! -name '.DS_Store' -print0 | sort -z | xargs -0 shasum -a 256 2>/dev/null)
}
case "$MODE" in
  snapshot) snap > "$FILE" ;;
  verify)
    now=$(mktemp); snap > "$now"
    if diff -q "$FILE" "$now" >/dev/null; then rm -f "$now"; echo "loops-guard: live loops untouched"; exit 0; fi
    echo "loops-guard: a test run CHANGED the live loops ($LOOPS):"; diff "$FILE" "$now" | sed -n '1,20p'; rm -f "$now"; exit 1 ;;
  *) echo "usage: loops-guard.sh snapshot|verify <file>" >&2; exit 2 ;;
esac
