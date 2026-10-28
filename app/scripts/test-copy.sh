#!/bin/bash
# LAB-1486 · run a throwaway copy of One Roof for a repro, and always clean up after it.
# The copy lives in its own /tmp folder with its own roofd folder (ROOFD_DIR) and its own home (CFFIXED_USER_HOME), so it
# never touches the owner's sessions or store. On exit (normal, error or Ctrl-C) every roofd started from the copy is
# stopped and the copy is unregistered from Launch Services, so no test daemon outlives the repro (LAB-1385 left seven).
#
#   app/scripts/test-copy.sh [path/to/One Roof.app] [-- command to run against the copy]
#   default app: /Applications/One Roof.app · default command: launch the app and wait until it exits
#   inside the command: $COPY (the app copy), $RD (its roofd folder), $H (its home)
set -u
SRC="/Applications/One Roof.app"; if [ $# -gt 0 ] && [ "$1" != "--" ]; then SRC=$1; shift; fi; [ "${1:-}" = "--" ] && shift
LSREG=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
T=$(mktemp -d /tmp/oneroof-copy.XXXX); COPY="$T/One Roof.app"; RD="$T/rd"; H="$T/home"
mkdir -p "$RD" "$H"
cleanup() {
  for p in $(pgrep -f "^$COPY/Contents/MacOS/"); do kill "$p" 2>/dev/null; done; sleep 1
  for p in $(pgrep -f "^$COPY/Contents/MacOS/"); do kill -9 "$p" 2>/dev/null; done
  "$LSREG" -u "$COPY" 2>/dev/null
  rm -rf "$T"
  echo "test-copy: cleaned up $T (no roofd left: $(pgrep -f "^$COPY/" | wc -l | tr -d ' '))"
}
trap cleanup EXIT INT TERM
ditto "$SRC" "$COPY" || exit 1
export COPY RD H
if [ $# -gt 0 ]; then
  ROOFD_DIR="$RD" CFFIXED_USER_HOME="$H" "$@"
else
  ROOFD_DIR="$RD" CFFIXED_USER_HOME="$H" "$COPY/Contents/MacOS/OneRoof"
fi
