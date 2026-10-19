#!/usr/bin/env bash
# oneroof · sign One Roof.app with a Developer ID, notarize it with Apple and staple the ticket.
#
#   tools/sign-and-notarize.sh "<path>/One Roof.app"                       sign + notarize + staple
#   tools/sign-and-notarize.sh "<path>/One Roof.app" --runtime-test        ad-hoc sign WITH the hardened runtime (no Apple
#                                                                         account needed): checks the app still works
# Needs, once (see app/README.md › Signing):
#   ONEROOF_SIGN_IDENTITY  e.g. "Developer ID Application: Your Name (TEAMID)"   (security find-identity -v -p codesigning)
#   ONEROOF_NOTARY_PROFILE a notarytool keychain profile, made with:
#                          xcrun notarytool store-credentials oneroof-notary --apple-id <id> --team-id <TEAMID>
set -euo pipefail
APP="${1:?usage: sign-and-notarize.sh <app> [--runtime-test]}"; MODE="${2:-}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
ENT="$ROOT/app/Resources/OneRoof.entitlements"
[ -d "$APP" ] || { echo "no app at $APP" >&2; exit 2; }

if [ "$MODE" = "--runtime-test" ]; then ID="-"; else ID="${ONEROOF_SIGN_IDENTITY:?set ONEROOF_SIGN_IDENTITY}"; fi
TS=(--timestamp); [ "$ID" = "-" ] && TS=(--timestamp=none)

# Inside-out: every other Mach-O file in the bundle first, then the app itself.
while IFS= read -r f; do
  if file -b "$f" | grep -q "Mach-O"; then codesign --force --options runtime "${TS[@]}" --sign "$ID" "$f"; fi
done < <(find "$APP/Contents" -type f -perm -u+x ! -path "*/MacOS/OneRoof")
codesign --force --options runtime "${TS[@]}" --entitlements "$ENT" --sign "$ID" "$APP"
codesign --verify --deep --strict --verbose=2 "$APP"
codesign -dv "$APP" 2>&1 | grep -E "flags|Authority|TeamIdentifier" || true

[ "$MODE" = "--runtime-test" ] && { echo "sign-and-notarize: ad-hoc + hardened runtime applied (not notarized)"; exit 0; }

PROFILE="${ONEROOF_NOTARY_PROFILE:?set ONEROOF_NOTARY_PROFILE}"
ZIP="$(mktemp -d)/notarize.zip"
ditto -c -k --norsrc --noextattr --noacl --keepParent "$APP" "$ZIP"
xcrun notarytool submit "$ZIP" --keychain-profile "$PROFILE" --wait
xcrun stapler staple "$APP"
xcrun stapler validate "$APP"
spctl --assess --type execute --verbose=4 "$APP"
echo "sign-and-notarize: signed, notarized and stapled. Zip it again for release."
