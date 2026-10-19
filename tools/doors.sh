#!/usr/bin/env bash
# oneroof · doors: every agent finds the one READ-FIRST from every folder it can start in.
#
#   roof doors            create missing doors (idempotent; never overwrites a file that isn't a door)
#   roof doors --check    list missing doors; exit 1 if any
#
# Why: agents look for instructions under different names and in different places. Claude reads CLAUDE.md in the start
# folder and every parent; Codex reads AGENTS.md from the repo root down plus ~/.codex/AGENTS.md; Kimi reads AGENTS.md in
# the start folder only; Gemini reads GEMINI.md (and AGENTS.md once configured) up to the repo root plus
# ~/.gemini/GEMINI.md. A door is a small AGENTS.md pointing at READ-FIRST and the rulebook, never a copy of the rules.
# Levels: every project folder (a non-repo folder directly under the workspace) and every repo root (depth ≤ 2).
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
. "$HERE/../lib/common.sh"
roof_load_config
MARK="oneroof door v1"
CHECK=0; [ "${1:-}" = "--check" ] && CHECK=1
missing=0; made=0
shared_name="$(basename "$ROOF_SHARED")"

door() { # door <dir> <label>
  local dir="$1" label="$2" f="$1/AGENTS.md" rf="$1/READ-FIRST.md" rel
  if [ ! -e "$f" ] && [ ! -L "$f" ]; then
    missing=$((missing + 1))
    if [ "$CHECK" = 1 ]; then echo "  ✗ no AGENTS.md door: $dir"; else
      {
        echo "<!-- $MARK · written by roof doors · edit templates, not this file -->"
        echo "# Agent entry: $label"
        echo
        echo "Rules for every agent live in one place. Read, in this order:"
        echo
        echo "1. \`READ-FIRST.md\` in this folder (a link to \`$ROOF_SHARED/docs/READ-FIRST.md\`): the must-read list."
        echo "2. \`$ROOF_SHARED/AGENTS.md\`: the workspace rulebook."
        [ -f "$dir/CLAUDE.md" ] && echo "3. \`CLAUDE.md\` in this folder: this folder's own context. Written for Claude Code but it applies to every agent; skip Claude-only syntax such as \`@path\` imports."
        echo
        echo "Start sessions only inside \`$ROOF_WORKSPACE\`. Durable facts go in \`$ROOF_SHARED/docs/\`, not in any agent's private notes."
      } > "$f"
      made=$((made + 1)); echo "  + $f"
    fi
  fi
  if [ ! -e "$rf" ] && [ ! -L "$rf" ]; then
    missing=$((missing + 1))
    rel="$(python3 -c 'import os,sys; print(os.path.relpath(sys.argv[1], sys.argv[2]))' "$ROOF_SHARED/docs/READ-FIRST.md" "$dir")"
    if [ "$CHECK" = 1 ]; then echo "  ✗ no READ-FIRST.md link: $dir"; else ln -s "$rel" "$rf"; made=$((made + 1)); echo "  + $rf → $rel"; fi
  fi
}

[ -d "$ROOF_WORKSPACE" ] || { echo "no workspace at $ROOF_WORKSPACE (roof install first)"; exit 1; }
for d in "$ROOF_WORKSPACE"/*/; do
  d="${d%/}"; n="$(basename "$d")"
  case "$n" in "$shared_name"|_archive|.*) continue ;; esac
  [ -d "$d/.git" ] || door "$d" "$n (project folder)"
done
while IFS= read -r g; do
  r="$(dirname "$g")"
  [ "$r" = "$ROOF_SHARED" ] && continue
  door "$r" "$(basename "$r")"
done < <(find "$ROOF_WORKSPACE" -mindepth 2 -maxdepth 3 -name .git -not -path '*/_archive/*' -not -path '*/.worktrees/*' -not -path '*/node_modules/*' 2>/dev/null | sort)

G="$HOME/.gemini"
if [ -d "$G" ] || [[ " $ROOF_AGENTS " == *" gemini "* ]]; then
  if [ ! -f "$G/GEMINI.md" ]; then
    missing=$((missing + 1))
    if [ "$CHECK" = 1 ]; then echo "  ✗ no global ~/.gemini/GEMINI.md"; else
      mkdir -p "$G"
      sed -e "s|{{WORKSPACE}}|$ROOF_WORKSPACE|g" -e "s|{{SHARED}}|$ROOF_SHARED|g" -e "s|{{HOME}}|$HOME|g" "$HERE/../templates/home/GEMINI.md" > "$G/GEMINI.md"
      made=$((made + 1)); echo "  + $G/GEMINI.md"
    fi
  fi
  if ! python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); sys.exit(0 if "AGENTS.md" in (d.get("context",{}).get("fileName") or []) else 1)' "$G/settings.json" 2>/dev/null; then
    missing=$((missing + 1))
    if [ "$CHECK" = 1 ]; then echo "  ✗ Gemini does not read AGENTS.md (context.fileName)"; else
      python3 - "$G/settings.json" <<'PY'
import json, pathlib, shutil, sys, time
p = pathlib.Path(sys.argv[1])
if p.exists():
    shutil.copy2(p, p.with_name(f"{p.name}.before-oneroof-{time.strftime('%Y%m%d-%H%M%S')}"))
d = json.loads(p.read_text()) if p.exists() and p.read_text().strip() else {}
names = d.setdefault("context", {}).get("fileName") or ["GEMINI.md"]
names = [names] if isinstance(names, str) else names
for n in ("GEMINI.md", "AGENTS.md"):
    if n not in names: names.append(n)
d["context"]["fileName"] = names
p.parent.mkdir(parents=True, exist_ok=True); p.write_text(json.dumps(d, indent=2) + "\n")
PY
      made=$((made + 1)); echo "  + ~/.gemini/settings.json: context.fileName includes AGENTS.md"
    fi
  fi
fi

if [ "$CHECK" = 1 ]; then
  [ "$missing" = 0 ] && echo "doors: all present" || { echo "doors: $missing missing (run: roof doors)"; exit 1; }
else
  echo "doors: $made created"
fi
