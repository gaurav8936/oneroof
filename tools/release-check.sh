#!/usr/bin/env bash
# oneroof · release gate: fail if anything private or workspace-specific is still in the tracked tree.
#
#   tools/release-check.sh            scan tracked files (what a clone would get)
#   RELEASE_PRIVATE="me|myhost" tools/release-check.sh   add your own handles, hostnames, product names
#   tools/release-check.sh --app "<path>/One Roof.app"   only scan a built app for build-machine paths
#   tools/release-check.sh --zip dist/One-Roof-<v>.zip   only scan a release zip (no __MACOSX, app inside clean)
#
# Allowed on purpose: LICENSE (copyright line), the GitHub repo URL and the app's bundle id.
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
cd "$ROOT" || exit 2
bad=0

# A built app must hold no path or name of the machine that built it: home folders, zig's default cache, hostname.
HOST="$(scutil --get LocalHostName 2>/dev/null || hostname -s)"
scan_app() {   # scan_app <path.app> → 0 clean, 1 hits (printed)
  local app="$1" exe hits n=0
  exe="$app/Contents/MacOS/OneRoof"
  [ -f "$exe" ] || { echo "FAIL no executable in $app"; return 1; }
  # Home folders, zig's default cache, the hostname, and absolute Swift source paths (#filePath: they give away where
  # the app was built, even from a neutral folder).
  hits="$(strings -a "$exe" > "${TMPDIR:-/tmp}/oneroof-strings.$$"
          grep -E '/Users/|\.cache/zig|^/.*\.swift$' "${TMPDIR:-/tmp}/oneroof-strings.$$"
          grep -iF -- "$HOST" "${TMPDIR:-/tmp}/oneroof-strings.$$"; rm -f "${TMPDIR:-/tmp}/oneroof-strings.$$")"
  [ -n "$hits" ] && { echo "FAIL build-machine strings in the executable:"; echo "$hits" | head -20; n=1; }
  # Every file, binaries too (-a). "/Users/" followed by a name, so a regex like "/Users/[a-z]" in a script is fine.
  hits="$(grep -rlaE '/Users/[A-Za-z0-9._-]|\.cache/zig' "$app" ; grep -rlaiF -- "$HOST" "$app")"
  [ -n "$hits" ] && { echo "FAIL build-machine paths in bundle files:"; echo "$hits" | sed "s|^$app/||" | sort -u | head -20; n=1; }
  [ "$n" = 0 ] && echo "ok   no build-machine paths in $(basename "$app") ($(find "$app" -type f | wc -l | tr -d ' ') files)"
  return "$n"
}
scan_zip() {   # scan_zip <zip> → 0 clean, 1 hits
  local zip="$1" tmp app n=0
  if unzip -l "$zip" | grep -q '__MACOSX'; then echo "FAIL $(basename "$zip") has __MACOSX entries"; n=1
  else echo "ok   no __MACOSX entries in $(basename "$zip")"; fi
  tmp="$(mktemp -d)"
  unzip -q "$zip" -d "$tmp"
  app="$(find "$tmp" -maxdepth 2 -name '*.app' -type d | head -1)"
  if [ -z "$app" ]; then echo "FAIL no .app in $(basename "$zip")"; n=1; else scan_app "$app" || n=1; fi
  rm -rf "$tmp"
  return "$n"
}
case "${1:-}" in
  --app) scan_app "${2:?usage: release-check.sh --app <path.app>}"; exit $? ;;
  --zip) scan_zip "${2:?usage: release-check.sh --zip <zip>}"; exit $? ;;
esac

pat='/Users/[a-z][a-z0-9_-]+|@gmail\.com|@[a-z0-9-]+\.edu\b|\b(CMN|GBL|HYP|AGM|ZIB)-[0-9]+\b|\bws-(wsp|gg|inf|hy|hyp|el|ae|ca|lc|agm|dl|ed|br|sec|dc|onewksp|blog)(-[a-z0-9]+)*\b|\bganarasi\b|labs-agentic-engineering|labs-data|access_admin|sk-[A-Za-z0-9]{20,}|xox[bp]-|AKIA[0-9A-Z]{16}|BEGIN [A-Z ]*PRIVATE KEY'
[ -n "${RELEASE_PRIVATE:-}" ] && pat="$pat|$RELEASE_PRIVATE"
allow='github\.com/gaurav8936/oneroof|io\.github\.gaurav8936\.oneroof|/Users/(someone|example|you)\b|com\.gaurav8936\.oneroof'

hits="$(git ls-files -z | grep -zv -E '^(LICENSE|tools/release-check\.sh|app/Sources/OneRoofCore/LegacyMigration\.swift|app/Tests/OneRoofCoreTests/NeutralTests\.swift)$' | grep -zv -E '\.(png|jpg|jpeg|gif|icns|mp3|gguf)$' \
  | xargs -0 grep -nIiE "$pat" 2>/dev/null | grep -viE "$allow" || true)"
if [ -n "$hits" ]; then
  echo "FAIL private or workspace-specific strings:"; echo "$hits" | head -100
  echo "($(echo "$hits" | wc -l | tr -d ' ') lines)"; bad=1
else
  echo "ok   no private strings in $(git ls-files | wc -l | tr -d ' ') tracked files"
fi

big="$(git ls-files -z | xargs -0 du -k 2>/dev/null | awk '$1 > 5120 {print $2" ("$1" KB)"}')"
[ -z "$big" ] && echo "ok   no tracked file over 5 MB" || { echo "FAIL tracked files over 5 MB:"; echo "$big"; bad=1; }

bash "$ROOT/agentic_engineering/scripts/check.sh" >/dev/null && echo "ok   agentic_engineering package check" || { echo "FAIL agentic_engineering/scripts/check.sh"; bad=1; }

shopt -s nullglob; zips=(dist/*.zip); shopt -u nullglob
if [ "${#zips[@]}" = 0 ]; then echo "skip release zip scan: no dist/*.zip (tools/package-app.sh makes one)"
else for z in "${zips[@]}"; do scan_zip "$z" || bad=1; done; fi

[ "$bad" = 0 ] && echo "release-check: clean" || { echo "release-check: NOT ready"; exit 1; }
