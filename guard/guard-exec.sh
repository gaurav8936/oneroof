#!/usr/bin/env bash
# oneroof · hard stop for agents that have no hooks (layer 2b): Codex, Kimi, Hermes, Gemini, …
# `roof install` writes a tiny stand-in per agent into ~/.config/oneroof/bin (first on PATH):
#     exec guard-exec.sh <real-binary> "$@"
# Inside the workspace it execs the real binary untouched; anywhere else it refuses with exit 64.
# `command codex` still resolves through PATH, so it is caught too. Owner one-off: ROOF_ALLOW_OUTSIDE=1.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
. "$HERE/../lib/common.sh"
roof_load_config

real="$1"; shift
here="$(pwd -P 2>/dev/null || pwd)"
if roof_inside "$here" || roof_allowed_outside; then exec "$real" "$@"; fi
name="$(basename "$real")"
echo "⛔ WRONG FOLDER: $name only runs inside $ROOF_WORKSPACE (you are in $here)." >&2
echo "   cd $ROOF_WORKSPACE && $name      (deliberate one-off? ROOF_ALLOW_OUTSIDE=1 $name)" >&2
exit 64
