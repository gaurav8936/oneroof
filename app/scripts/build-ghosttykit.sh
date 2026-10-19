#!/usr/bin/env bash
# Build libghostty (GhosttyKit.xcframework) from Ghostty v1.3.1 (outside the repo) and link it into Vendor/.
# Needs: Xcode 26 + Metal Toolchain (xcodebuild -downloadComponent MetalToolchain) + zig 0.15 (brew install zig@0.15).
#
#   scripts/build-ghosttykit.sh                      build in place, link Vendor/GhosttyKit.xcframework to it
#   scripts/build-ghosttykit.sh --release-build DIR  copy the Ghostty source to DIR (outside any home folder) and build
#                                                    there with zig caches under DIR's parent, so no home-folder path
#                                                    ends up in libghostty. Vendor/ is left alone; prints the
#                                                    xcframework path on the last line. Used by tools/package-app.sh.
set -euo pipefail
cd "$(dirname "$0")/.."
RELEASE_DIR=""
if [ "${1:-}" = "--release-build" ]; then
  RELEASE_DIR="${2:?usage: build-ghosttykit.sh --release-build <dir>}"
  case "$RELEASE_DIR" in /*) ;; *) echo "build-ghosttykit: --release-build needs an absolute path" >&2; exit 2 ;; esac
  case "$RELEASE_DIR" in "$HOME"/*|/Users/*) echo "build-ghosttykit: $RELEASE_DIR is inside a home folder" >&2; exit 2 ;; esac
fi
# Where the Ghostty source + build lives: ONEROOF_GHOSTTY_DIR, else the folder Vendor/GhosttyKit.xcframework already
# points into, else ~/Library/Caches/oneroof/ghostty.
if [ -z "${ONEROOF_GHOSTTY_DIR:-}" ] && [ -L Vendor/GhosttyKit.xcframework ]; then
  ONEROOF_GHOSTTY_DIR="$(cd "$(dirname "$(readlink -f Vendor/GhosttyKit.xcframework)")/.." && pwd)"
fi
DIR="${ONEROOF_GHOSTTY_DIR:-$HOME/Library/Caches/oneroof/ghostty}"
TAG="${GHOSTTY_TAG:-v1.3.1}"
ZIG="${ZIG:-/opt/homebrew/opt/zig@0.15/bin/zig}"
if [ ! -d "$DIR/.git" ]; then
  mkdir -p "$(dirname "$DIR")"
  git clone --depth 1 --branch "$TAG" https://github.com/ghostty-org/ghostty.git "$DIR"
fi
xcrun -sdk macosx metal --version >/dev/null 2>&1 || { echo "Metal Toolchain missing: xcodebuild -downloadComponent MetalToolchain"; exit 1; }
ZIG_FLAGS=(-Doptimize=ReleaseFast -Demit-macos-app=false -Dxcframework-target=native)

if [ -n "$RELEASE_DIR" ]; then
  # The source is only read: build outputs and caches are left behind, everything else is copied (kept between runs,
  # so a second release build is incremental).
  mkdir -p "$RELEASE_DIR"
  rsync -a --delete --exclude '/zig-out/' --exclude '/.zig-cache/' --exclude '/macos/GhosttyKit.xcframework/' \
    "$DIR/" "$RELEASE_DIR/"
  CACHE="$(dirname "$RELEASE_DIR")/zig-cache"
  mkdir -p "$CACHE/p"
  # Seed the neutral package cache from zig's default one (content-addressed, copied, never changed); anything
  # missing is fetched by zig. ONEROOF_ZIG_SEED="" skips the seeding.
  SEED="${ONEROOF_ZIG_SEED-$HOME/.cache/zig/p}"
  [ -n "$SEED" ] && [ -d "$SEED" ] && rsync -a --ignore-existing "$SEED/" "$CACHE/p/"
  ( cd "$RELEASE_DIR" && ZIG_GLOBAL_CACHE_DIR="$CACHE" ZIG_LOCAL_CACHE_DIR="$RELEASE_DIR/.zig-cache" \
      "$ZIG" build "${ZIG_FLAGS[@]}" )
  [ -d "$RELEASE_DIR/macos/GhosttyKit.xcframework" ] || { echo "build-ghosttykit: no xcframework in $RELEASE_DIR" >&2; exit 1; }
  echo "$RELEASE_DIR/macos/GhosttyKit.xcframework"
  exit 0
fi

( cd "$DIR" && "$ZIG" build "${ZIG_FLAGS[@]}" )
mkdir -p Vendor
ln -sfn "$DIR/macos/GhosttyKit.xcframework" Vendor/GhosttyKit.xcframework
echo "OK: Vendor/GhosttyKit.xcframework → $DIR/macos/GhosttyKit.xcframework"
