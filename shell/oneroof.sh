# shellcheck shell=bash
# oneroof · shell layer (layers 1, 2 and the PATH for 2b). Sourced from ~/.zshrc or ~/.bashrc by `roof install`:
#   [ -f "<repo>/shell/oneroof.sh" ] && . "<repo>/shell/oneroof.sh"   # oneroof
# Works in zsh and bash.

__roof_conf="${XDG_CONFIG_HOME:-$HOME/.config}/oneroof/config"
# shellcheck disable=SC1090
[ -f "$__roof_conf" ] && . "$__roof_conf"
: "${ROOF_WORKSPACE:=$HOME/Projects}"
: "${ROOF_AGENTS:=claude codex kimi gemini agy}"

# Layer 2b: agent stand-ins first on PATH (codex, kimi, … refuse to start outside the workspace).
case ":$PATH:" in *":${XDG_CONFIG_HOME:-$HOME/.config}/oneroof/bin:"*) ;; *) PATH="${XDG_CONFIG_HOME:-$HOME/.config}/oneroof/bin:$PATH" ;; esac
export PATH

__roof_inside() { # logical and physical forms of both paths (symlinked workspaces count as inside)
  local x ws wp
  ws="${ROOF_WORKSPACE%/}"; wp="$( (cd "$ws" 2>/dev/null && pwd -P) || printf '%s' "$ws")"
  for x in "${PWD%/}" "$(pwd -P)"; do
    if [ "$(uname -s)" = "Darwin" ]; then
      x="$(printf '%s' "$x" | tr '[:upper:]' '[:lower:]')"
      case "$x" in "$(printf '%s' "$ws" | tr '[:upper:]' '[:lower:]')"|"$(printf '%s' "$ws" | tr '[:upper:]' '[:lower:]')"/*|"$(printf '%s' "$wp" | tr '[:upper:]' '[:lower:]')"|"$(printf '%s' "$wp" | tr '[:upper:]' '[:lower:]')"/*) return 0 ;; esac
    else
      case "$x" in "$ws"|"$ws"/*|"$wp"|"$wp"/*) return 0 ;; esac
    fi
  done
  return 1
}

# Layer 1: an interactive shell that opens in ~, /Users or / moves to the workspace. Scripts (zsh -c / bash -c) never move.
__roof_interactive=0
case "$-" in *i*) __roof_interactive=1 ;; esac
if [ "$__roof_interactive" = 1 ] && [ -z "${ZSH_EXECUTION_STRING:-}${BASH_EXECUTION_STRING:-}" ] && [ -d "$ROOF_WORKSPACE" ]; then
  case "$PWD" in "$HOME"|/Users|/home|/) cd "$ROOF_WORKSPACE" || true ;; esac
fi
unset __roof_interactive

# Layer 2: typing an agent anywhere outside the workspace moves you there first (friendlier than refusing;
# the hook and the stand-ins are the hard stops).
__roof_guard() {
  if ! __roof_inside && [ -z "${ROOF_ALLOW_OUTSIDE:-}${CLAUDE_ALLOW_OUTSIDE:-}" ]; then
    echo "⛔ Agents only run inside $ROOF_WORKSPACE, moving there from $PWD" >&2
    cd "$ROOF_WORKSPACE" || return 1
  fi
}
for __roof_a in $ROOF_AGENTS; do
  eval "$__roof_a() { __roof_guard && command $__roof_a \"\$@\"; }"
done
unset __roof_a __roof_conf
