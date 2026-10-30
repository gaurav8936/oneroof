#!/bin/bash
# oneroof-test's sim suite (LAB-1594): run the stand-in simulator and fail when an ask never reached Needs you or an
# answered one stayed there. Usage: simulate.sh [--app <bundle>] --out <dir>   (--app is accepted; the simulator
# runs the test build at app/build/One Roof.app).
set -u
OUT=""; while [ $# -gt 0 ]; do case "$1" in --out) OUT=$2; shift 2 ;; --app) shift 2 ;; *) shift ;; esac; done
[ -n "$OUT" ] || { echo "simulate.sh: --out <dir> needed" >&2; exit 2; }
python3 "$(dirname "$0")/simulate.py" --sessions 9 --minutes 3 --seed 5 --deny 0.4 --out "$OUT" || exit $?
R="$OUT/report.md"; [ -f "$R" ] || { echo "simulate.sh: no report" >&2; exit 1; }
missing=$(grep -o 'missing: [0-9]*' "$R" | head -1 | grep -o '[0-9]*$'); stale=$(grep -o 'Stale Needs you entries[^:]*: [0-9]*' "$R" | grep -o '[0-9]*$')
echo "sim: missing=${missing:-?} stale=${stale:-?}"
[ "${missing:-1}" = 0 ] && [ "${stale:-1}" = 0 ]
