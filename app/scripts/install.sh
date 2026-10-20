#!/usr/bin/env bash
# Build One Roof (release) and copy it to /Applications. Sessions in roofd keep running across reinstalls.
set -euo pipefail
cd "$(dirname "$0")/.."
scripts/bundle.sh release
pkill -f "/Applications/One Roof.app/Contents/MacOS/OneRoof" 2>/dev/null || true
rm -rf "/Applications/One Roof.app"
cp -R "build/One Roof.app" "/Applications/One Roof.app"
echo "installed: /Applications/One Roof.app"
