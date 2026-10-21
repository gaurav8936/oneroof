#!/usr/bin/env bash
# roofd smoke (LAB-255): a throwaway daemon in its own ROOFD_DIR, so the owner's daemon and sessions are never touched.
# Checks create · input/read · daemon kill -9 (sessions survive) · holder kill · exit + linger · unicode · long input.
# Usage: app/scripts/roofd-smoke.sh   (needs a full build: scripts/bundle.sh)
set -u
B="${ROOFD_BIN:-$(cd "$(dirname "$0")/.." && pwd)/build/One Roof.app/Contents/MacOS/roofd}"
export ROOFD_DIR=$(mktemp -d "${TMPDIR:-/tmp}/roofd-smoke.XXXX") ROOFD_LINGER=1
unset ONEROOF_ROOFD
ok(){ echo "PASS $1"; }; bad(){ echo "FAIL $1"; FAILS=$((FAILS+1)); }; FAILS=0
start(){ "$B" daemon >"$ROOFD_DIR/d.log" 2>&1 & DPID=$!; for i in $(seq 20); do "$B" hello >/dev/null 2>&1 && return; sleep 0.2; done; }
start; "$B" hello >/dev/null && ok "daemon up" || bad "daemon up"
"$B" create --id roof-smoke1 --label s1 --cols 80 --rows 24 -- /bin/bash --noprofile --norc >/dev/null
"$B" create --id roof-smoke2 --label s2 --cols 80 --rows 24 -- /bin/bash --noprofile --norc >/dev/null
sleep 0.5
"$B" input roof-smoke1 'echo hello-$((40+2))' --submit >/dev/null; sleep 0.5
"$B" read roof-smoke1 | grep -q 'hello-42' && ok "input+read" || bad "input+read"
# daemon killed hard: holders (sessions) must survive and be listed again by a new daemon
kill -9 $DPID; sleep 0.3; start
"$B" list | grep -q roof-smoke1 && "$B" list | grep -q roof-smoke2 && ok "sessions survive daemon kill -9" || bad "sessions survive daemon kill -9"
"$B" input roof-smoke1 'echo after-$((1+1))' --submit >/dev/null; sleep 0.5
"$B" read roof-smoke1 | grep -q 'after-2' && ok "typing after daemon restart" || bad "typing after daemon restart"
# one holder killed: only that session ends
HP=$("$B" list | python3 -c 'import json,sys;print([s["pid"] for s in json.load(sys.stdin)["sessions"] if s["id"]=="roof-smoke2"][0])')
HOLDER=$(ps -o ppid= -p "$HP" | tr -d ' '); kill -9 "$HOLDER"; sleep 1
"$B" list | grep -q roof-smoke2 && bad "killed holder gone" || ok "killed holder gone"
"$B" list | grep -q roof-smoke1 && ok "other session unaffected" || bad "other session unaffected"
# exit code / exited state
"$B" input roof-smoke1 'exit 3' --submit >/dev/null; sleep 1
"$B" info roof-smoke1 > "$ROOFD_DIR/info.json" 2>&1; echo "  info after exit: $(tr -d '\n ' < "$ROOFD_DIR/info.json" | cut -c1-200)"
"$B" close roof-smoke1 >/dev/null; sleep 2.5
"$B" list | grep -q roof-smoke1 && bad "exited session gone after linger" || ok "exited session gone after linger"
# unicode + long input
"$B" create --id roof-smoke3 --cols 80 --rows 24 -- /bin/bash --noprofile --norc >/dev/null; sleep 0.5
"$B" input roof-smoke3 'echo "ünïcødé ✓ 日本"' --submit >/dev/null; sleep 0.5
"$B" read roof-smoke3 | grep -q '日本' && ok "unicode round trip" || bad "unicode round trip"
LONG=$(python3 -c 'print("x"*5000)'); "$B" input roof-smoke3 "echo \${#X} ; X=$LONG; echo len=\${#X}" --submit >/dev/null; sleep 1
"$B" read roof-smoke3 | grep -q 'len=5000' && ok "5000-char input" || bad "5000-char input"
"$B" close roof-smoke3 >/dev/null
kill $DPID 2>/dev/null; sleep 0.3
echo "fails=$FAILS"; rm -rf "$ROOFD_DIR"; exit $((FAILS > 0))
