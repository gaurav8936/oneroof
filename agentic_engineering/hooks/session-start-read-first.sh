#!/usr/bin/env bash
# Claude Code SessionStart hook: remind the agent to read the shared must-read list before anything else.
# Install: add to ~/.claude/settings.json →
#   "hooks": {"SessionStart": [{"hooks": [{"type": "command", "command": "<path>/hooks/session-start-read-first.sh"}]}]}
# Reads AE_SHARED (default: <workspace>/_common) and prints a line Claude adds to its context.
shared="${AE_SHARED:-${ROOF_WORKSPACE:-$HOME/Projects}/_common}"
rf="$shared/docs/READ-FIRST.md"
if [ -f "$rf" ]; then
  echo "Before any other action, read $rf and the must-read files it lists. Newest handoff: $(ls -t "$shared"/docs/next-session-handoff/* 2>/dev/null | head -1)"
fi
exit 0
