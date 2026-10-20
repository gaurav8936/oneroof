#!/usr/bin/env bash
# Try One Roof on roofd (LAB-ROOFD P3, before the cut-over): builds the app with roofd inside, quits a running
# One Roof, and opens the built app with ONEROOF_RUNTIME=roofd on your normal profile.
#   - New sessions (⌘N, ⌘T) run on roofd; they keep running when One Roof quits, and reopen with their history.
#   - Sessions still on herdr show as Exited here (no fallback, owner Q11); relaunch one to move it to roofd.
#   - Back to herdr: quit, then open One Roof normally.
set -euo pipefail
APP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
cd "$APP_DIR"
[ -e Vendor/RoofVT.xcframework ] || bash roofd/build-roofvt.sh
bash scripts/bundle.sh >/tmp/oneroof-bundle.log 2>&1 || { tail -20 /tmp/oneroof-bundle.log; exit 1; }
osascript -e 'tell application "One Roof" to quit' >/dev/null 2>&1 || true
pkill -x OneRoof 2>/dev/null || true
sleep 1
ONEROOF_RUNTIME=roofd nohup "$APP_DIR/build/One Roof.app/Contents/MacOS/OneRoof" >/tmp/oneroof-roofd.log 2>&1 &
echo "One Roof is running on roofd (log: /tmp/oneroof-roofd.log)."
echo "Sessions: \"$APP_DIR/build/One Roof.app/Contents/MacOS/roofd\" list"
