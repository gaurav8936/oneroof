#!/usr/bin/env bash
# oneroof-bugs-check.sh — the check for the One Roof loop "oneroof-nightly-bugs" (LAB-1371).
# Run from the repo root (or the loop worktree). Exit 0 only when all of these hold:
#   1. swift build passes in app/ (the app, OneRoofCore and roofd)
#   2. swift test passes in app/
#   3. Linear shows no issue of type Bug in state Backlog in project LAB-ONEROOF-BUGS
# Each failure prints one line saying what failed; the loop hands that output to the next round.
# ONEROOF_BUGS_CHECK_PERF=1 also runs app/scripts/perf/perf-check.sh (minutes; off by default).
set -uo pipefail
REPO="$(cd "$(dirname "$0")/../.." && pwd)"
LT="${LT:-$HOME/Projects/_common/scripts/linear/lt.py}"
LOG="$(mktemp -t oneroof-bugs-check)"; FAIL=0
fail() { echo "FAIL: $*"; FAIL=1; }

if (cd "$REPO/app" && swift build --build-tests) >"$LOG.build" 2>&1; then echo "ok: build"
else fail "build — $(grep -m1 'error:' "$LOG.build" || tail -1 "$LOG.build")"; fi

if [ $FAIL -eq 0 ]; then
  if (cd "$REPO/app" && swift test --skip-build) >"$LOG.test" 2>&1; then echo "ok: tests"
  else fail "tests — $(grep -E "error: -\[|failed \(" "$LOG.test" | head -3 | tr '\n' ' ')"; fi
fi

if [ "${ONEROOF_BUGS_CHECK_PERF:-0}" = 1 ] && [ $FAIL -eq 0 ]; then
  if bash "$REPO/app/scripts/perf/perf-check.sh" >"$LOG.perf" 2>&1; then echo "ok: perf"
  else fail "perf — $(tail -1 "$LOG.perf")"; fi
fi

if out="$(cd "$HOME/Projects" && python3 "$LT" project LAB-ONEROOF-BUGS 2>&1)"; then
  open="$(printf '%s\n' "$out" | grep -E '\[Backlog\] \(Bug\)' | sed -E 's/^- ([A-Z]+-[0-9]+).*/\1/' | tr '\n' ' ')"
  if [ -n "$open" ]; then fail "Bugs still in Backlog in LAB-ONEROOF-BUGS: $open"; else echo "ok: no Bug in Backlog"; fi
else fail "Linear — could not read LAB-ONEROOF-BUGS: $(printf '%s' "$out" | tail -1)"; fi

rm -f "$LOG" "$LOG".*
exit $FAIL
