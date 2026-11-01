#!/usr/bin/env bash
# oneroof · build the release app and zip it for GitHub Releases.
#
#   tools/package-app.sh                      → dist/One-Roof-<version>.zip + .sha256
#   tools/package-app.sh --build-only <dir>   → <dir>/One Roof.app (unsigned) + <dir>/candidate.json; no zip (LAB-1903)
#   tools/package-app.sh --prebuilt <app>     → sign + zip that app instead of building again; refuses unless its
#                                               candidate.json names this exact tree and version (LAB-1903, LAB-1561)
#
# --build-only + --prebuilt let the release gate test the very build that is signed: build once, test it, then sign it.
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
MODE=full; TARGET=""
case "${1:-}" in
  --build-only) MODE=build; TARGET="${2:?usage: package-app.sh --build-only <dir>}" ;;
  --prebuilt) MODE=prebuilt; TARGET="${2:?usage: package-app.sh --prebuilt <One Roof.app>}" ;;
  "") ;; *) echo "package-app: unknown option $1" >&2; exit 2 ;;
esac
cd "$ROOT"
bash tools/release-check.sh
[ -z "$(git status --porcelain)" ] || { echo "package-app: commit or discard changes first" >&2; exit 1; }
VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' app/Resources/Info.plist)"
STAGE="${ONEROOF_RELEASE_DIR:-/private/tmp/oneroof-release}"
TREE="$(git rev-parse 'HEAD^{tree}')"

if [ "$MODE" = prebuilt ]; then
  # The tested build, signed as is: only when it was built from this exact tree and version.
  CJ="$(dirname "$TARGET")/candidate.json"
  [ -f "$CJ" ] || { echo "package-app: no candidate.json next to $TARGET" >&2; exit 1; }
  read -r CV CT < <(python3 -c 'import json,sys;j=json.load(open(sys.argv[1]));print(j["version"],j["tree"])' "$CJ")
  [ "$CV" = "$VERSION" ] && [ "$CT" = "$TREE" ] || { echo "package-app: $TARGET was built from $CV tree $CT, this checkout is $VERSION tree $TREE: build again" >&2; exit 1; }
  APP="$STAGE/prebuilt/One Roof.app"; rm -rf "$STAGE/prebuilt"; mkdir -p "$STAGE/prebuilt"; ditto "$TARGET" "$APP"
  echo "package-app: signing the tested build ($VERSION, tree ${TREE:0:12}) instead of building again"
else

# 1. libghostty in the neutral folder (incremental after the first run).
t0=$(date +%s)
app/scripts/build-ghosttykit.sh --release-build "$STAGE/ghostty"
echo "package-app: libghostty release build took $(( $(date +%s) - t0 ))s"

# LAB-1257 · a release always packages the deck repository at origin/main; ONEROOF_AE_DECK_REF is for local test builds.
[ "${ONEROOF_AE_DECK_REF:-origin/main}" = origin/main ] || { echo "package-app: ONEROOF_AE_DECK_REF=$ONEROOF_AE_DECK_REF; a release uses origin/main (unset it)" >&2; exit 1; }
# LAB-1834 · a release saves the hub's shared Learn page, never a local embed build or none.
[ -z "${ONEROOF_GGAE_DIR:-}" ] && [ -z "${ONEROOF_LEARN_SKIP:-}" ] || { echo "package-app: ONEROOF_GGAE_DIR / ONEROOF_LEARN_SKIP are for local test builds; a release saves the hub's Learn page (unset them)" >&2; exit 1; }

# 2. A clean copy of HEAD, linked to that libghostty (its .build is kept between runs).
[ -d "$STAGE/src/app/.build" ] && mv "$STAGE/src/app/.build" "$STAGE/swift-build-keep"
rm -rf "$STAGE/src"; mkdir -p "$STAGE/src"
git archive HEAD | tar -x -C "$STAGE/src"
[ -d "$STAGE/swift-build-keep" ] && mv "$STAGE/swift-build-keep" "$STAGE/src/app/.build"
mkdir -p "$STAGE/src/app/Vendor"
ln -sfn "$STAGE/ghostty/macos/GhosttyKit.xcframework" "$STAGE/src/app/Vendor/GhosttyKit.xcframework"
# roofd's terminal core (RoofVT, Zig) from the same Ghostty source, then the bundle (which builds and adds roofd).
(cd "$STAGE/src/app" && ONEROOF_GHOSTTY_DIR="$STAGE/ghostty" bash roofd/build-roofvt.sh)
(cd "$STAGE/src/app" && ONEROOF_GHOSTTY_DIR="$STAGE/ghostty" scripts/bundle.sh release)

APP="$STAGE/src/app/build/One Roof.app"
fi
# LAB-1257 · the skill-linking script, One Roof's own routing rules and the deck's catalog (it carries the Learn bands).
# 1.9.2 (LAB-1274): no course is required (or packaged) any more.
for need in agentic_engineering agentic_engineering/scripts/sync-skills.sh agentic_engineering/deck/content/catalog.json agentic_engineering/learn/learn-manifest.json agentic_engineering/learn/ggae.js agent-routing/routing.json agent-routing/roles.json evals/roof_eval.py evals/requirements.txt evals/starter.json THIRD-PARTY-NOTICES.md licenses/Qwen3-LICENSE.txt MacOS/OneRoof MacOS/roofd Library/LaunchAgents/io.github.gaurav8936.oneroof.roofd.plist; do
  [ -e "$APP/Contents/Resources/$need" ] || [ -e "$APP/Contents/$need" ] || { echo "package-app: $need missing from the bundle" >&2; exit 1; }
done
grep -q '"bands"' "$APP/Contents/Resources/agentic_engineering/deck/content/catalog.json" || { echo "package-app: the deck catalog has no Learn bands (deck repository main predates LAB-1257)" >&2; exit 1; }
bash tools/release-check.sh --app "$APP" || { echo "package-app: the built app leaks build-machine paths" >&2; exit 1; }
bash tools/release-check.sh --learn "$APP" || { echo "package-app: the saved Learn page is incomplete (LAB-1834)" >&2; exit 1; }

if [ "$MODE" = build ]; then   # the release candidate the gate tests (unsigned; signing happens after the gate passes)
  mkdir -p "$TARGET"; rm -rf "$TARGET/One Roof.app"; ditto "$APP" "$TARGET/One Roof.app"
  python3 -c 'import json,sys;json.dump(dict(version=sys.argv[2],commit=sys.argv[3],tree=sys.argv[4]),open(sys.argv[1],"w"),indent=1)' \
    "$TARGET/candidate.json" "$VERSION" "$(git rev-parse HEAD)" "$TREE"
  echo "package-app: candidate $VERSION ($(git rev-parse --short HEAD)) → $TARGET/One Roof.app"
  exit 0
fi

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
