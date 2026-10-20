#!/usr/bin/env bash
# Build RoofVT (roofd's headless terminal, Zig over Ghostty's ghostty-vt, T14 §3b) and wrap it as
# Vendor/RoofVT.xcframework: one static archive (RoofVT + simdutf, highway, utfcpp) with RoofVT.h and a module map.
# Uses the same pinned Ghostty source and zig as scripts/build-ghosttykit.sh.
#
#   roofd/build-roofvt.sh          build and link into Vendor/
set -euo pipefail
APP="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
cd "$APP"
if [ -z "${ONEROOF_GHOSTTY_DIR:-}" ] && [ -L Vendor/GhosttyKit.xcframework ]; then
  ONEROOF_GHOSTTY_DIR="$(cd "$(dirname "$(readlink -f Vendor/GhosttyKit.xcframework)")/.." && pwd)"
fi
DIR="${ONEROOF_GHOSTTY_DIR:-$HOME/Library/Caches/oneroof/ghostty}"
ZIG="${ZIG:-/opt/homebrew/opt/zig@0.15/bin/zig}"
[ -f "$DIR/src/lib_vt.zig" ] || { echo "build-roofvt: no Ghostty source at $DIR (run scripts/build-ghosttykit.sh first)" >&2; exit 1; }
[ -x "$ZIG" ] || { echo "build-roofvt: zig 0.15 not found at $ZIG (brew install zig@0.15)" >&2; exit 1; }

cd roofd/RoofVT
ln -sfn "$DIR" ghostty
"$ZIG" build --release=fast
OUT="$APP/build/RoofVT"
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
rm -rf "$APP/build/RoofVT.xcframework"
xcodebuild -create-xcframework -library "$OUT/libroofvt.a" -headers "$OUT/include" -output "$APP/build/RoofVT.xcframework" >/dev/null
mkdir -p "$APP/Vendor"
rm -rf "$APP/Vendor/RoofVT.xcframework"
cp -R "$APP/build/RoofVT.xcframework" "$APP/Vendor/RoofVT.xcframework"
echo "built: $APP/Vendor/RoofVT.xcframework"
