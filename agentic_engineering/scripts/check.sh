#!/usr/bin/env bash
# agentic_engineering · check the package is complete and clean before it ships.
#   scripts/check.sh        exit 1 on any problem
set -uo pipefail
PKG="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
bad=0; ok() { echo "  ok   $1"; }; no() { echo "  FAIL $1"; bad=1; }

echo "== skills"
n=0
for md in "$PKG"/skills/*/*/SKILL.md; do
  n=$((n + 1)); dir="$(basename "$(dirname "$md")")"
  name="$(sed -n '2,/^---$/s/^name: //p' "$md" | head -1)"
  desc="$(sed -n '2,/^---$/s/^description: //p' "$md" | head -1)"
  [ "$(head -1 "$md")" = "---" ] || no "$dir: no frontmatter"
  [ "$name" = "$dir" ] || no "$dir: name '$name' differs from its folder"
  [ -n "$desc" ] || no "$dir: no description"
  [ "$(wc -l < "$md")" -le 120 ] || no "$dir: longer than 120 lines"
done
names="$(for md in "$PKG"/skills/*/*/SKILL.md; do basename "$(dirname "$md")"; done | sort)"
dupes="$(echo "$names" | uniq -d)"; [ -z "$dupes" ] || no "duplicate skill names: $dupes"
ok "$n skills"

echo "== routing"
for f in routing roles; do
  python3 -m json.tool "$PKG/skills/fleet/agent-routing/$f.json" >/dev/null && ok "$f.json parses" || no "$f.json is not valid JSON"
done
for s in $(python3 -c "import json,sys; print(' '.join(r['skill'] for r in json.load(open(sys.argv[1]))['roles']))" "$PKG/skills/fleet/agent-routing/roles.json"); do
  echo "$names" | grep -qx "$s" || no "roles.json names a skill that is not in the package: $s"
done
ok "every role's skill exists"

echo "== course"
for l in "$PKG"/course/[0-9][0-9]-*.md; do
  b="$(basename "$l" .md)"; want="$(grep -c '^## ' "$l")"
  have="$(find "$PKG/course/audio/$b" -name '*.mp3' 2>/dev/null | wc -l | tr -d ' ')"
  [ "$want" = "$have" ] || no "$b: $want sections but $have audio clips (run scripts/make-audio.py)"
done
ok "$(find "$PKG"/course -maxdepth 1 -name '[0-9][0-9]-*.md' | wc -l | tr -d ' ') lessons"

echo "== nothing personal or private"
# Add your own handles and private hostnames with AE_PRIVATE_PATTERN (an extended regex, joined with "|").
pat="/Users/[a-z]|@gmail\.com|sk-[A-Za-z0-9]{20,}|xox[bp]-${AE_PRIVATE_PATTERN:+|$AE_PRIVATE_PATTERN}"
hits="$(grep -rInE "$pat" "$PKG" --exclude-dir=audio --exclude=check.sh || true)"
[ -z "$hits" ] && ok "no private strings" || { no "private strings found:"; echo "$hits"; }

[ "$bad" = 0 ] && echo "check: all good" || { echo "check: problems found"; exit 1; }
