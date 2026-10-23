#!/usr/bin/env bash
# Build RoofVT (a Zig shim over Ghostty's ghostty-vt) and wrap it as Vendor/RoofVT.xcframework:
# one static archive (RoofVT + simdutf, highway, utfcpp) with RoofVT.h and a module map.
#
#   scripts/build-roofvt.sh
#
# Needs zig 0.15 (brew install zig@0.15) and Xcode's command-line tools. Fetches the pinned Ghostty source once into
# GHOSTTY_DIR (default ~/Library/Caches/roofd/ghostty). ZIG and GHOSTTY_TAG override the defaults.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
DIR="${GHOSTTY_DIR:-$HOME/Library/Caches/roofd/ghostty}"
TAG="${GHOSTTY_TAG:-v1.3.1}"
ZIG="${ZIG:-/opt/homebrew/opt/zig@0.15/bin/zig}"
[ -x "$ZIG" ] || { echo "build-roofvt: zig 0.15 not found at $ZIG (brew install zig@0.15, or set ZIG)" >&2; exit 1; }
if [ ! -f "$DIR/src/lib_vt.zig" ]; then
  mkdir -p "$(dirname "$DIR")"
  git clone --depth 1 --branch "$TAG" https://github.com/ghostty-org/ghostty.git "$DIR"
fi

cd "$ROOT/RoofVT"
ln -sfn "$DIR" ghostty
"$ZIG" build --release=fast
OUT="$ROOT/.build/RoofVT"
rm -rf "$OUT" && mkdir -p "$OUT/include"
libtool -static -o "$OUT/libroofvt.a" zig-out/lib/libroofvt.a zig-out/lib/libsimdutf.a zig-out/lib/libhighway.a zig-out/lib/libutfcpp.a 2>/dev/null
cp include/RoofVT.h "$OUT/include/"
cat > "$OUT/include/module.modulemap" <<'MAP'
module RoofVT {
    header "RoofVT.h"
    link "c++"
    export *
}
MAP
rm -rf "$ROOT/Vendor/RoofVT.xcframework"
mkdir -p "$ROOT/Vendor"
xcodebuild -create-xcframework -library "$OUT/libroofvt.a" -headers "$OUT/include" -output "$ROOT/Vendor/RoofVT.xcframework" >/dev/null
echo "built: Vendor/RoofVT.xcframework"
