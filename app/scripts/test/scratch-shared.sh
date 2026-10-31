#!/usr/bin/env bash
# scratch-shared.sh <dir> — a scratch shared folder for a One Roof TEST COPY (LAB-2001). Every top-level entry of the real
# shared folder is linked in read-through, except loops/, which is COPIED: a test copy may read and migrate its loops
# (LAB-1942 did, at 13:41 on 10-31) without touching the live ones. Point the test copy at it with ONEROOF_SHARED=<dir>.
# The real shared folder: $ONEROOF_REAL_SHARED, else ~/Projects/_common. Prints <dir>. Idempotent: an existing <dir> is kept.
set -eu
DIR=$1
REAL="${ONEROOF_REAL_SHARED:-$HOME/Projects/_common}"
if [ -d "$DIR/loops" ] || [ -L "$DIR/docs" ]; then echo "$DIR"; exit 0; fi
mkdir -p "$DIR"
if [ -d "$REAL" ]; then
  for e in "$REAL"/* "$REAL"/.[!.]*; do
    [ -e "$e" ] || continue
    n=$(basename "$e")
    case "$n" in loops|.git) continue ;; esac
    ln -s "$e" "$DIR/$n"
  done
  [ -d "$REAL/loops" ] && rsync -a --exclude '__pycache__' "$REAL/loops/" "$DIR/loops/"
fi
mkdir -p "$DIR/loops"
echo "$DIR"
