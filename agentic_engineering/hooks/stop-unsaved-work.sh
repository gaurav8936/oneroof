#!/usr/bin/env bash
# Claude Code Stop hook: when a session ends with uncommitted changes in the current repo, say so (never blocks).
# Install: "hooks": {"Stop": [{"hooks": [{"type": "command", "command": "<path>/hooks/stop-unsaved-work.sh"}]}]}
cat >/dev/null                                   # the hook's JSON input is not needed
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || exit 0
n="$(git status --porcelain | wc -l | tr -d ' ')"
if [ "$n" != 0 ]; then
  echo "Note: $n uncommitted change(s) in $(basename "$(git rev-parse --show-toplevel)"). Before leaving: commit or park them and run the last-call skill." >&2
fi
exit 0
