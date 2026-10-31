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

# The bundled agentic-engineering package: the skill-linking script only (AEFolder; no folder choice since LAB-768).
# 1.9.0 (LAB-1257): One Roof authors no agentic-engineering content; skills, cards and the hooks all come from the deck
# below. 1.9.2 (LAB-1274): One Roof has no course; the deck's content/course (if its main still has one) is not packaged.
# The routing rules are One Roof's own configuration (Resources/agent-routing, overridable in
# ~/.config/oneroof/agent-routing/).
rsync -a --delete --exclude '.DS_Store' ../agentic_engineering/ "$APP/Contents/Resources/agentic_engineering/"
rsync -a --delete --exclude '.DS_Store' Resources/agent-routing/ "$APP/Contents/Resources/agent-routing/"
# LAB-768 · plus the whole Agentic Engineering deck (every skill, narrated card, track page and its audio, and the hooks)
# as published: the deck repository (ONEROOF_AE_DECK_REPO, a git checkout) at origin/main, into agentic_engineering/deck.
# ONEROOF_AE_DECK_REF overrides the ref for local test builds only (e.g. a commit not yet on main); releases use origin/main
# (tools/package-app.sh refuses anything else). Built from source without it, One Roof runs without the deck.
AE_DECK_REPO="${ONEROOF_AE_DECK_REPO:-}"
AE_DECK_REF="${ONEROOF_AE_DECK_REF:-origin/main}"
if [ -n "$AE_DECK_REPO" ] && git -C "$AE_DECK_REPO" rev-parse -q --verify "$AE_DECK_REF^{commit}" >/dev/null 2>&1; then
  [ "$AE_DECK_REF" = origin/main ] && { git -C "$AE_DECK_REPO" fetch -q origin main 2>/dev/null || true; }
  DECK="$APP/Contents/Resources/agentic_engineering/deck"; rm -rf "$DECK"; mkdir -p "$DECK"
  # hooks/ joined the deck repository with LAB-1257; kit/loops joined with LAB-1663; an older main has none.
  PARTS=(skills content)
  git -C "$AE_DECK_REPO" cat-file -e "$AE_DECK_REF:hooks" 2>/dev/null && PARTS+=(hooks)
  git -C "$AE_DECK_REPO" cat-file -e "$AE_DECK_REF:kit/loops" 2>/dev/null && PARTS+=(kit/loops)
  git -C "$AE_DECK_REPO" archive "$AE_DECK_REF" "${PARTS[@]}" | tar -x --exclude 'content/course' -C "$DECK"
  rm -rf "$DECK/content/course"
  printf '%s\n' "$AE_DECK_REF $(git -C "$AE_DECK_REPO" rev-parse --short "$AE_DECK_REF")" > "$DECK/.deck-ref"
  echo "deck: $(find "$DECK/skills" -name SKILL.md | wc -l | tr -d ' ') skills, $(find "$DECK/skills" -name '*.mp3' | wc -l | tr -d ' ') clips from the deck repository at $AE_DECK_REF $(git -C "$AE_DECK_REPO" rev-parse --short "$AE_DECK_REF")"
else
  echo "deck: ONEROOF_AE_DECK_REPO not set to a checkout with $AE_DECK_REF; bundling without the deck"
fi

# Help, README and release notes for the Help menu (read from Resources; the source checkout is the fallback).
rsync -a --delete --exclude '.DS_Store' ../docs/help/ "$APP/Contents/Resources/help/"
cp README.md "$APP/Contents/Resources/app-README.md"
cp ../CHANGELOG.md "$APP/Contents/Resources/RELEASE-NOTES.md"
# Third-party notices, and the on-device model's licence (copied next to the model when Get the model downloads it).
cp ../THIRD-PARTY-NOTICES.md "$APP/Contents/Resources/THIRD-PARTY-NOTICES.md"
rsync -a --delete --exclude '.DS_Store' Resources/licenses/ "$APP/Contents/Resources/licenses/"

# libghostty resources: shell integration, themes, terminfo (TERM=xterm-ghostty).
if [ -d "$GHOSTTY/zig-out/share/ghostty" ]; then
  cp -R "$GHOSTTY/zig-out/share/ghostty" "$APP/Contents/Resources/ghostty"
  cp -R "$GHOSTTY/zig-out/share/terminfo" "$APP/Contents/Resources/terminfo"
else
  echo "⚠ $GHOSTTY/zig-out/share missing — terminals will fall back to TERM=xterm-256color"
fi

codesign --force --deep --sign - "$APP" >/dev/null 2>&1 || echo "⚠ ad-hoc codesign failed (app still runs locally)"
case "$APP" in /*) echo "built: $APP";; *) echo "built: $(pwd)/$APP";; esac
