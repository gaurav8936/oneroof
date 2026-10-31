#!/usr/bin/env bash
# LAB-1838 · capture the shared Learn page as One Roof shows it (scripts/learn-shot.swift), for the visual sign-off.
#   scripts/learn-shot.sh --learn <learn dir> --deck <deck dir> --out <dir> [--theme daylight|graphite|midnight] [--size WxH] [#ae/… …]
#   scripts/learn-shot.sh --app "<path>/One Roof.app" --out <dir> [...]   # the saved page and deck inside a built app
# Screens are hashes of the embed: #ae/radio · #ae/writing · #ae/cards[/kind|/folder] · #ae/band/<id> · #ae/card/<slug>[/transcript|/skill].
# Exit 0 = every screen captured and no http(s) request; 3 = the page went to the network or reported an error.
set -euo pipefail
cd "$(dirname "$0")/.."
args=()
while [ $# -gt 0 ]; do
  if [ "$1" = --app ]; then R="$2/Contents/Resources/agentic_engineering"; args+=(--learn "$R/learn" --deck "$R/deck"); shift 2
  else args+=("$1"); shift; fi
done
swift build --target OneRoofCore >/dev/null
BIN="$(swift build --show-bin-path)"
OUT="${TMPDIR:-/tmp}/oneroof-learn-shot"
swiftc -O -o "$OUT" scripts/learn-shot.swift -I "$BIN/Modules" "$BIN"/OneRoofCore.build/*.o -lsqlite3 2>&1 | grep -v warning || true
[ -x "$OUT" ] || { echo "learn-shot: build failed"; exit 1; }
exec "$OUT" "${args[@]}"
