#!/usr/bin/env bash
# agentic_engineering · link every skill of the bundled Agentic Engineering deck into each agent's skills home.
#
#   scripts/sync-skills.sh [--dry-run] [--unlink]
#
# Skills live in the deck (deck/skills/<track>/<name>/SKILL.md: the deck repository at main, packaged into the app, LAB-768),
# or at skills/<track>/<name>/SKILL.md when this script runs from the deck repository itself (ONEROOF_AE_PATH).
# Each becomes a symlink <home>/<name> in every home that exists:
#   ~/.claude/skills  ~/.claude-*/skills  ~/.codex/skills  ~/.kimi-code/skills  ~/.gemini/config/skills  + $AE_SKILL_HOMES
# --dry-run prints "[DRY] ln -sfn <source> <dest>" for every link that is missing or wrong (One Roof reads this).
# A real folder with the same name is never replaced, and neither is a link to a folder outside this package that exists
# (someone's own copy of a skill, e.g. a checkout of the deck repository). --unlink removes only links into this package.
# 1.9.0 (LAB-1257): One Roof ships no skills of its own, so only deck skills are linked and nothing in the app can win
# over the deck on a name clash. Links into this package whose target is gone (the old starter skills) are removed.
set -euo pipefail
PKG="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
DECK="$PKG/deck"; [ -d "$DECK/skills" ] || DECK="$PKG"   # the deck repository itself has skills/ at its root
DRY=0; UNLINK=0
for a in "$@"; do
  case "$a" in --dry-run) DRY=1 ;; --unlink) UNLINK=1 ;; *) echo "unknown option: $a" >&2; exit 2 ;; esac
done

homes() {
  local d
  for d in "$HOME/.claude" "$HOME"/.claude-* "$HOME/.codex" "$HOME/.kimi-code" "$HOME/.gemini/config"; do
    [ -d "$d" ] && printf '%s/skills\n' "$d"
  done
  for d in ${AE_SKILL_HOMES:-}; do printf '%s\n' "$d"; done
}

made=0; same=0; kept=0; removed=0
while IFS= read -r home; do
  if [ "$UNLINK" = 1 ]; then
    for l in "$home"/*; do
      [ -L "$l" ] || continue
      case "$(readlink "$l")" in "$PKG"/*) if [ "$DRY" = 1 ]; then echo "[DRY] rm $l"; else rm -f "$l"; fi; removed=$((removed + 1)) ;; esac
    done
    continue
  fi
  [ "$DRY" = 1 ] || mkdir -p "$home"
  # A link into this package that points nowhere (a removed skill) goes.
  for l in "$home"/*; do
    [ -L "$l" ] && [ ! -e "$l" ] || continue
    case "$(readlink "$l")" in "$PKG"/*) if [ "$DRY" = 1 ]; then echo "[DRY] rm $l"; else rm -f "$l"; fi; removed=$((removed + 1)) ;; esac
  done
  for md in "$DECK"/skills/*/*/SKILL.md; do
    [ -e "$md" ] || continue
    src="$(dirname "$md")"; name="$(basename "$src")"; dst="$home/$name"
    if [ -L "$dst" ] && [ "$(readlink "$dst")" = "$src" ]; then same=$((same + 1)); continue; fi
    if [ -L "$dst" ]; then
      to="$(readlink "$dst")"
      case "$to" in "$PKG"/*) ;; *) if [ -d "$to" ]; then kept=$((kept + 1)); continue; fi ;; esac
    fi
    if [ -e "$dst" ] && [ ! -L "$dst" ]; then echo "  kept $dst (a real folder, not ours)"; kept=$((kept + 1)); continue; fi
    if [ "$DRY" = 1 ]; then echo "[DRY] ln -sfn $src $dst"; else ln -sfn "$src" "$dst"; fi
    made=$((made + 1))
  done
done < <(homes)
if [ "$UNLINK" = 1 ]; then echo "sync-skills: $removed links removed"
else echo "sync-skills: $made to link · $same already linked · $kept real folders kept · $removed dead links removed"; fi
