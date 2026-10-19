#!/usr/bin/env bash
# oneroof · build the release app and zip it for GitHub Releases.
#
#   tools/package-app.sh            → dist/One-Roof-<version>.zip + .sha256
#
# Needs the libghostty source (app/scripts/build-ghosttykit.sh once). Runs the release gate first; refuses to package a
# tree that is not clean. With ONEROOF_SIGN_IDENTITY + ONEROOF_NOTARY_PROFILE set, the app is Developer ID signed, notarized and stapled.
#
# The release is built away from this checkout so no build-machine path ends up in it: libghostty is rebuilt from a
# copy of the Ghostty source in $ONEROOF_RELEASE_DIR/ghostty (zig caches there too), the app from `git archive HEAD`
# in $ONEROOF_RELEASE_DIR/src with source paths mapped to ".". This checkout and its Vendor/ link are not touched.
# The gate (tools/release-check.sh --app / --zip) fails the run on any home-folder path, zig cache path, the
# hostname, or a __MACOSX entry in the zip.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
cd "$ROOT"
bash tools/release-check.sh
[ -z "$(git status --porcelain)" ] || { echo "package-app: commit or discard changes first" >&2; exit 1; }
VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' app/Resources/Info.plist)"
STAGE="${ONEROOF_RELEASE_DIR:-/private/tmp/oneroof-release}"

# 1. libghostty in the neutral folder (incremental after the first run).
t0=$(date +%s)
app/scripts/build-ghosttykit.sh --release-build "$STAGE/ghostty"
echo "package-app: libghostty release build took $(( $(date +%s) - t0 ))s"

# 2. A clean copy of HEAD, linked to that libghostty (its .build is kept between runs).
[ -d "$STAGE/src/app/.build" ] && mv "$STAGE/src/app/.build" "$STAGE/swift-build-keep"
rm -rf "$STAGE/src"; mkdir -p "$STAGE/src"
git archive HEAD | tar -x -C "$STAGE/src"
[ -d "$STAGE/swift-build-keep" ] && mv "$STAGE/swift-build-keep" "$STAGE/src/app/.build"
mkdir -p "$STAGE/src/app/Vendor"
ln -sfn "$STAGE/ghostty/macos/GhosttyKit.xcframework" "$STAGE/src/app/Vendor/GhosttyKit.xcframework"
(cd "$STAGE/src/app" && ONEROOF_GHOSTTY_DIR="$STAGE/ghostty" scripts/bundle.sh release)

APP="$STAGE/src/app/build/One Roof.app"
for need in agentic_engineering MacOS/OneRoof; do
  [ -e "$APP/Contents/Resources/$need" ] || [ -e "$APP/Contents/$need" ] || { echo "package-app: $need missing from the bundle" >&2; exit 1; }
done
bash tools/release-check.sh --app "$APP" || { echo "package-app: the built app leaks build-machine paths" >&2; exit 1; }

# 3. Zip: no resource forks, extended attributes or ACLs (so no __MACOSX/ entries), then gate the zip itself.
mkdir -p dist
ZIP="dist/One-Roof-$VERSION.zip"
rm -f "$ZIP" "$ZIP.sha256"
# Developer ID signing + notarization when the identity and notary profile are set (tools/sign-and-notarize.sh).
if [ -n "${ONEROOF_SIGN_IDENTITY:-}" ]; then bash "$ROOT/tools/sign-and-notarize.sh" "$APP"; else echo "package-app: not signed with a Developer ID (set ONEROOF_SIGN_IDENTITY + ONEROOF_NOTARY_PROFILE)"; fi
ditto -c -k --norsrc --noextattr --noacl --keepParent "$APP" "$ZIP"
bash tools/release-check.sh --zip "$ZIP" || { rm -f "$ZIP"; echo "package-app: zip failed the gate (removed)" >&2; exit 1; }
(cd dist && shasum -a 256 "$(basename "$ZIP")") | tee "$ZIP.sha256"
echo "package-app: $ZIP ($(du -h "$ZIP" | cut -f1)) from $(git rev-parse --short HEAD)"
