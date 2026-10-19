#!/usr/bin/env bash
# oneroof · link ONE skills folder into every agent's skills home.
#
#   roof sync-skills <skills-dir> [--dry-run]
#
# <skills-dir> holds one folder per skill, each with a SKILL.md (nested track folders are fine: */SKILL.md or
# */*/SKILL.md). Every skill becomes a symlink in each agent home that exists:
#   ~/.claude/skills  ~/.claude-*/skills  ~/.codex/skills  ~/.hermes/skills  ~/.gemini/skills  + $ROOF_SKILL_HOMES
# A skill whose frontmatter says `runtime: [...]` without `shared` or `interactive` is skipped (background-only).
# Never replaces a real folder; prunes our own dangling links; drops a README-NOT-CANONICAL.md in each home.
set -euo pipefail
SRC="${1:?usage: roof sync-skills <skills-dir> [--dry-run]}"; DRY=0; [ "${2:-}" = "--dry-run" ] && DRY=1
SRC="$(cd "$SRC" && pwd -P)"

homes() {
  local h
  for h in "$HOME/.claude" "$HOME"/.claude-* "$HOME/.codex" "$HOME/.hermes" "$HOME/.gemini"; do
    [ -d "$h" ] && printf '%s/skills\n' "$h"
  done
  for h in ${ROOF_SKILL_HOMES:-}; do printf '%s\n' "$h"; done
}

wanted() { # skill dir → 0 if it should be linked for interactive agents
  local rt
  rt="$(sed -n '1,/^---$/{/^runtime:/p;}' "$1/SKILL.md" 2>/dev/null | head -1)"
  [ -z "$rt" ] && return 0
  case "$rt" in *shared*|*interactive*) return 0 ;; esac
  return 1
}

skills="$(find "$SRC" -mindepth 2 -maxdepth 3 -name SKILL.md -not -path '*/node_modules/*' -exec dirname {} \; | sort)"
n_link=0; n_skip=0; n_keep=0; n_prune=0
while IFS= read -r home; do
  [ "$DRY" = 1 ] || mkdir -p "$home"
  [ "$DRY" = 1 ] || printf 'Skills here are symlinks into %s.\nEdit them there, then run: roof sync-skills %s\n' "$SRC" "$SRC" > "$home/README-NOT-CANONICAL.md"
  for s in $skills; do
    name="$(basename "$s")"; dst="$home/$name"
    if ! wanted "$s"; then n_skip=$((n_skip + 1)); continue; fi
    if [ -e "$dst" ] && [ ! -L "$dst" ]; then echo "  ! $dst is a real folder: left alone"; n_keep=$((n_keep + 1)); continue; fi
    if [ -L "$dst" ] && [ "$(readlink "$dst")" = "$s" ]; then continue; fi
    if [ "$DRY" = 1 ]; then echo "  would link $dst → $s"; else ln -sfn "$s" "$dst"; fi
    n_link=$((n_link + 1))
  done
  for l in "$home"/*; do
    [ -L "$l" ] || continue
    case "$(readlink "$l")" in "$SRC"/*) [ -e "$l" ] || { [ "$DRY" = 1 ] || rm -f "$l"; n_prune=$((n_prune + 1)); } ;; esac
  done
done < <(homes)
echo "sync-skills: $n_link linked/updated · $n_skip skipped (not interactive) · $n_keep real folders kept · $n_prune dangling pruned"
