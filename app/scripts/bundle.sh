#!/usr/bin/env bash
# Build One Roof and wrap it as build/One Roof.app (ad-hoc signed, runs locally).
# Usage: scripts/bundle.sh [debug|release]   (default release)
set -euo pipefail
cd "$(dirname "$0")/.."
CONF="${1:-release}"
# Where the Ghostty source + build lives: ONEROOF_GHOSTTY_DIR, else the folder Vendor/GhosttyKit.xcframework already
# points into, else ~/Library/Caches/oneroof/ghostty.
if [ -z "${ONEROOF_GHOSTTY_DIR:-}" ] && [ -L Vendor/GhosttyKit.xcframework ]; then
  ONEROOF_GHOSTTY_DIR="$(cd "$(dirname "$(readlink -f Vendor/GhosttyKit.xcframework)")/.." && pwd)"
fi
GHOSTTY="${ONEROOF_GHOSTTY_DIR:-$HOME/Library/Caches/oneroof/ghostty}"
[ -e Vendor/GhosttyKit.xcframework ] || { echo "Vendor/GhosttyKit.xcframework missing — run scripts/build-ghosttykit.sh"; exit 1; }

# Release: map the checkout root to "." in debug info and module-cache references. #filePath is not remapped by
# swiftc, so the source-checkout fallback (AppResources.sourceCheckout) is compiled in debug builds only.
SWIFT_FLAGS=()
if [ "$CONF" = release ]; then
  # Both spellings of the root (e.g. /tmp and /private/tmp), so the map applies whichever one swift sees.
  for r in "$(cd .. && pwd)" "$(cd .. && pwd -P)"; do SWIFT_FLAGS+=(-Xswiftc -file-prefix-map -Xswiftc "$r=."); done
fi
swift build -c "$CONF" --product OneRoof ${SWIFT_FLAGS[@]+"${SWIFT_FLAGS[@]}"}
BIN="$(swift build -c "$CONF" --show-bin-path ${SWIFT_FLAGS[@]+"${SWIFT_FLAGS[@]}"})/OneRoof"

# ONEROOF_BUNDLE_OUT: build somewhere else (tests), so the app the owner runs from build/ is never replaced underneath.
APP="${ONEROOF_BUNDLE_OUT:-build}/One Roof.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
[ -n "${ONEROOF_BUNDLE_OUT:-}" ] && mkdir -p "$ONEROOF_BUNDLE_OUT"
cp "$BIN" "$APP/Contents/MacOS/OneRoof"
# roofd, One Roof's session manager (LAB-ROOFD): needs Vendor/RoofVT.xcframework (roofd/build-roofvt.sh).
if [ -e Vendor/RoofVT.xcframework ]; then
  swift build -c "$CONF" --product roofd ${SWIFT_FLAGS[@]+"${SWIFT_FLAGS[@]}"}
  cp "$(dirname "$BIN")/roofd" "$APP/Contents/MacOS/roofd"
  # Its launchd agent, registered by the app with SMAppService (Q13).
  mkdir -p "$APP/Contents/Library/LaunchAgents"
  cp Resources/io.github.gaurav8936.oneroof.roofd.plist "$APP/Contents/Library/LaunchAgents/"
else
  echo "⚠ Vendor/RoofVT.xcframework missing — roofd not bundled (run roofd/build-roofvt.sh)"
fi
cp Resources/Info.plist "$APP/Contents/Info.plist"
[ -f Resources/AppIcon.icns ] && cp Resources/AppIcon.icns "$APP/Contents/Resources/"

# The bundled agentic-engineering package: skills, routing rules, course + narration. Used whenever Settings ›
# Foundations points nowhere else (AEFolder). Your own folder, if chosen, is read in place instead.
rsync -a --delete --exclude '.DS_Store' --exclude '.hashes.json' ../agentic_engineering/ "$APP/Contents/Resources/agentic_engineering/"

# Help, README and release notes for the Help menu (read from Resources; the source checkout is the fallback).
rsync -a --delete --exclude '.DS_Store' ../docs/help/ "$APP/Contents/Resources/help/"
cp README.md "$APP/Contents/Resources/app-README.md"
cp ../CHANGELOG.md "$APP/Contents/Resources/RELEASE-NOTES.md"

# libghostty resources: shell integration, themes, terminfo (TERM=xterm-ghostty).
if [ -d "$GHOSTTY/zig-out/share/ghostty" ]; then
  cp -R "$GHOSTTY/zig-out/share/ghostty" "$APP/Contents/Resources/ghostty"
  cp -R "$GHOSTTY/zig-out/share/terminfo" "$APP/Contents/Resources/terminfo"
else
  echo "⚠ $GHOSTTY/zig-out/share missing — terminals will fall back to TERM=xterm-256color"
fi

codesign --force --deep --sign - "$APP" >/dev/null 2>&1 || echo "⚠ ad-hoc codesign failed (app still runs locally)"
case "$APP" in /*) echo "built: $APP";; *) echo "built: $(pwd)/$APP";; esac
