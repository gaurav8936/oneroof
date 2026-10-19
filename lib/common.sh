# shellcheck shell=bash
# oneroof · shared helpers. Sourced by bin/roof, the guards and the tests. POSIX-ish bash 3.2+ (macOS default).

ROOF_CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/oneroof"
ROOF_CONFIG="$ROOF_CONFIG_DIR/config"

# Load config if present; defaults otherwise. Config is plain KEY="value" lines written by `roof install`.
roof_load_config() {
  # shellcheck disable=SC1090
  [ -f "$ROOF_CONFIG" ] && . "$ROOF_CONFIG"
  ROOF_WORKSPACE="${ROOF_WORKSPACE:-$HOME/Projects}"
  ROOF_SHARED="${ROOF_SHARED:-$ROOF_WORKSPACE/_common}"
  ROOF_AGENTS="${ROOF_AGENTS:-claude codex kimi gemini agy}"
}

# Lowercase on macOS (case-insensitive filesystems); exact elsewhere.
roof_fold() {
  if [ "$(uname -s)" = "Darwin" ]; then printf '%s' "$1" | tr '[:upper:]' '[:lower:]'; else printf '%s' "$1"; fi
}

# roof_inside <dir> → 0 if <dir> is the workspace or below it. Prefix match on whole path segments,
# so ~/ProjectsOld is NOT inside ~/Projects.
# Both the logical and the physical (symlink-resolved) forms are compared, so a workspace reached through a symlink
# (or macOS's /var → /private/var) still counts as inside.
roof_phys() { (cd "$1" 2>/dev/null && pwd -P) || printf '%s' "$1"; }
roof_inside() {
  local d dp ws wp x
  d="${1%/}"; [ -z "$d" ] && d="/"
  dp="$(roof_phys "$d")"; ws="${ROOF_WORKSPACE%/}"; wp="$(roof_phys "$ws")"
  for x in "$d" "$dp"; do
    x="$(roof_fold "$x")"
    case "$x" in "$(roof_fold "$ws")"|"$(roof_fold "$ws")"/*|"$(roof_fold "$wp")"|"$(roof_fold "$wp")"/*) return 0 ;; esac
  done
  return 1
}

# Escape hatch for a deliberate, owner-only one-off.
roof_allowed_outside() { [ -n "${ROOF_ALLOW_OUTSIDE:-}${CLAUDE_ALLOW_OUTSIDE:-}" ]; }

# Claude Code's per-project folder name: the absolute path with every non-alphanumeric character turned into "-".
roof_claude_project_key() { printf '%s' "$1" | sed 's/[^A-Za-z0-9]/-/g'; }
roof_claude_memory_dir() { printf '%s/.claude/projects/%s/memory' "$HOME" "$(roof_claude_project_key "${ROOF_WORKSPACE%/}")"; }

roof_say()  { printf '%s\n' "$*"; }
roof_ok()   { printf '  \033[32m✓\033[0m %s\n' "$*"; }
roof_warn() { printf '  \033[33m!\033[0m %s\n' "$*"; }
roof_bad()  { printf '  \033[31m✗\033[0m %s\n' "$*"; }
