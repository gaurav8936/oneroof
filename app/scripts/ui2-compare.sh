#!/usr/bin/env bash
# v2 window screen check (1.x UI redesign, M0.7): capture each listed screen in-process and put it next to the
# handover screenshot it must match.
#
#   UI2_SHOTS=<handover>/01_handover/assets/shots scripts/ui2-compare.sh [code ...]
#
# Screens and their self-test settings come from scripts/ui2-screens.tsv (code <TAB> VAR=value ...). With codes given,
# only those run. Captures go through scripts/selftest-shot.sh (scratch store, demo sessions, quits after the shot),
# so build "build/One Roof.app" first (scripts/bundle.sh debug). Output: $OUT_DIR/compare/<code>.png, the capture on
# the left and the handover shot on the right, both scaled to 900 px high, plus $OUT_DIR/compare/index.txt.
set -uo pipefail
cd "$(dirname "$0")/.."
: "${UI2_SHOTS:?set UI2_SHOTS to the handover assets/shots folder}"
OUT_DIR="${OUT_DIR:-${TMPDIR:-/tmp}/oneroof-ui2}"; export OUT_DIR
mkdir -p "$OUT_DIR/compare"
want=" $* "
: > "$OUT_DIR/compare/index.txt"
while IFS=$'\t' read -r code vars; do
  [ -z "$code" ] || [ "${code:0:1}" = "#" ] && continue
  [ $# -gt 0 ] && [[ "$want" != *" $code "* ]] && continue
  name="ui2-${code//./_}"
  vars="${vars//@REPO@/$(cd .. && pwd)}"   # file paths in the list are relative to the repo root
  # shellcheck disable=SC2086
  bash scripts/selftest-shot.sh "$name" ONEROOF_SELFTEST_UI2=1 $vars >/dev/null 2>&1
  shot="$(ls "$UI2_SHOTS"/*-"${code//./_}".jpg 2>/dev/null | head -1)"
  cap="$OUT_DIR/$name.png"
  if [ ! -f "$cap" ]; then echo "$code  NO CAPTURE" | tee -a "$OUT_DIR/compare/index.txt"; continue; fi
  if [ -z "$shot" ]; then cp "$cap" "$OUT_DIR/compare/$code.png"; echo "$code  captured (no handover shot)" | tee -a "$OUT_DIR/compare/index.txt"; continue; fi
  ffmpeg -loglevel error -y -i "$cap" -i "$shot" \
    -filter_complex "[0]scale=-2:900[a];[1]scale=-2:900[b];[a][b]hstack=inputs=2" "$OUT_DIR/compare/$code.png" \
    && echo "$code  $OUT_DIR/compare/$code.png" | tee -a "$OUT_DIR/compare/index.txt"
done < scripts/ui2-screens.tsv
