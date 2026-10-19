#!/usr/bin/env bash
# oneroof · Claude Code launch-folder guard (layer 3).
#
# Wired into ~/.claude/settings.json by `roof install`:
#   SessionStart      → claude-hook.sh start    tells the user and the model: wrong folder, do no work
#   UserPromptSubmit  → claude-hook.sh prompt   BLOCKS every prompt while the session's cwd is outside the workspace
#
# Inside the workspace it prints nothing and exits 0. Escape hatch (owner-only one-off): ROOF_ALLOW_OUTSIDE=1 claude
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
. "$HERE/../lib/common.sh"
roof_load_config

mode="${1:-prompt}"
roof_allowed_outside && exit 0

payload="$(cat 2>/dev/null || true)"
cwd="$(printf '%s' "$payload" | sed -n 's/.*"cwd"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)"
[ -z "$cwd" ] && cwd="$PWD"
roof_inside "$cwd" && exit 0

MSG="⛔ WRONG FOLDER: this session started in $cwd, outside $ROOF_WORKSPACE.
Agents only run inside $ROOF_WORKSPACE, so every session reads the same rules and the same memory.
Exit, then:  cd $ROOF_WORKSPACE && claude      (deliberate one-off? ROOF_ALLOW_OUTSIDE=1 claude)"

json_str() { python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))'; }
case "$mode" in
  start)
    m="$(printf '%s' "$MSG" | json_str)"
    c="$(printf '%s\nDo no work in this session. Tell the user to restart from the workspace.' "$MSG" | json_str)"
    printf '{"systemMessage":%s,"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":%s}}\n' "$m" "$c"
    ;;
  *)
    printf '{"decision":"block","reason":%s}\n' "$(printf '%s' "$MSG" | json_str)"
    ;;
esac
exit 0
