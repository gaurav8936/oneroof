#!/usr/bin/env bash
# agentic_engineering · check the package is complete and clean before it ships.
#   scripts/check.sh        exit 1 on any problem
# 1.9.0 (LAB-1257): One Roof authors no agentic-engineering content. The package is the linking script plus the deck
# (deck/, the deck repository at main, added when the app is built); the routing rules are One Roof's own configuration
# (app/Resources/agent-routing in the source checkout, Resources/agent-routing in the app).
set -uo pipefail
PKG="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
bad=0; ok() { echo "  ok   $1"; }; no() { echo "  FAIL $1"; bad=1; }

echo "== package"
[ -f "$PKG/scripts/sync-skills.sh" ] && ok "sync-skills.sh present" || no "scripts/sync-skills.sh missing"
for d in skills course hooks; do
  [ -e "$PKG/$d" ] && no "$d/ is back in the package: agentic-engineering content belongs in the deck repository (LAB-1257)"
done
ok "no content of the app's own"

echo "== routing"
ROUTING=""
for d in "$PKG/../app/Resources/agent-routing" "$PKG/../agent-routing"; do [ -f "$d/routing.json" ] && { ROUTING="$(cd "$d" && pwd -P)"; break; }; done
if [ -z "$ROUTING" ]; then no "agent-routing/routing.json not found next to the package"
else
  for f in routing roles; do
    python3 -m json.tool "$ROUTING/$f.json" >/dev/null && ok "$f.json parses" || no "$f.json is not valid JSON"
  done
fi

echo "== deck (LAB-768, present in a built app)"
if [ -f "$PKG/deck/content/catalog.json" ]; then
  python3 -m json.tool "$PKG/deck/content/catalog.json" >/dev/null && ok "deck catalog parses" || no "deck/content/catalog.json is not valid JSON"
  for md in "$PKG"/deck/skills/*/*/SKILL.md; do
    d="$(basename "$(dirname "$md")")"; [ "$(sed -n '2,/^---$/s/^name: //p' "$md" | head -1)" = "$d" ] || no "deck $d: name differs from its folder"
  done
  ok "$(find "$PKG/deck/skills" -name SKILL.md | wc -l | tr -d ' ') deck skills"
  if [ -n "$ROUTING" ]; then
    for s in $(python3 -c "import json,sys; print(' '.join(r['skill'] for r in json.load(open(sys.argv[1]))['roles']))" "$ROUTING/roles.json"); do
      compgen -G "$PKG/deck/skills/*/$s/SKILL.md" >/dev/null || no "roles.json names a skill that is not in the deck: $s"
    done
    ok "every role's skill is in the deck"
  fi
  # 1.9.2 (LAB-1274): One Roof has no course; bundle.sh leaves the deck's content/course out.
  [ -e "$PKG/deck/content/course" ] && no "deck/content/course is packaged: One Roof has no course since 1.9.2 (LAB-1274)" || ok "no course packaged"
else
  ok "no deck in the source checkout (added when the app is built)"
fi

echo "== nothing personal or private"
# Add your own handles and private hostnames with AE_PRIVATE_PATTERN (an extended regex, joined with "|").
pat="/Users/[a-z]|@gmail\.com|sk-[A-Za-z0-9]{20,}|xox[bp]-${AE_PRIVATE_PATTERN:+|$AE_PRIVATE_PATTERN}"
hits="$(grep -rInE "$pat" "$PKG" ${ROUTING:+"$ROUTING"} --exclude-dir=audio --exclude-dir='*_audio' --exclude=check.sh || true)"
[ -z "$hits" ] && ok "no private strings" || { no "private strings found:"; echo "$hits"; }

[ "$bad" = 0 ] && echo "check: all good" || { echo "check: problems found"; exit 1; }
