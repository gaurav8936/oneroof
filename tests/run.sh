#!/usr/bin/env bash
# oneroof test suite. Everything runs in a throwaway HOME with fake agent binaries:
# no real settings, shells, agents or tokens are touched.   bash tests/run.sh   (exit 0 = all pass)
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SANDBOX="$(cd "$(mktemp -d "${TMPDIR:-/tmp}/oneroof-test.XXXXXX")" && pwd)"
trap 'rm -rf "$SANDBOX"' EXIT
export HOME="$SANDBOX/home" XDG_CONFIG_HOME="" ROOF_ALLOW_OUTSIDE="" CLAUDE_ALLOW_OUTSIDE=""
unset XDG_CONFIG_HOME ROOF_WORKSPACE ROOF_SHARED ROOF_AGENTS
mkdir -p "$HOME" "$SANDBOX/fakebin"
for a in claude codex kimi gemini agy; do
  printf '#!/usr/bin/env bash\necho "REAL %s in $(pwd -P)"\n' "$a" > "$SANDBOX/fakebin/$a"; chmod +x "$SANDBOX/fakebin/$a"
done
PYDIR="$(dirname "$(command -v python3)")"
export PATH="$SANDBOX/fakebin:/usr/bin:/bin:/usr/sbin:/sbin:$PYDIR"
WS="$HOME/Projects"; ROOF="$ROOT/bin/roof"; CFG="$HOME/.config/oneroof"
pass=0; fail=0
ok()   { pass=$((pass + 1)); printf '  \033[32mPASS\033[0m %s\n' "$1"; }
no()   { fail=$((fail + 1)); printf '  \033[31mFAIL\033[0m %s\n' "$1"; }
check() { local name="$1"; shift; if "$@" >/dev/null 2>&1; then ok "$name"; else no "$name"; fi; }
phys() { (cd "$1" && pwd -P); }

echo "== install"
mkdir -p "$HOME/.claude"
printf '{"theme":"dark","hooks":{"Stop":[{"hooks":[{"type":"command","command":"/x/keep-me.sh"}]}]}}\n' > "$HOME/.claude/settings.json"
touch "$HOME/.zshrc"
"$ROOF" install > "$SANDBOX/install1.log" 2>&1; check "install exits 0" test $? -eq 0
"$ROOF" install > "$SANDBOX/install2.log" 2>&1; check "second install exits 0 (idempotent)" test $? -eq 0
check "config written" test -f "$CFG/config"
check "shared rulebook written" test -f "$WS/_common/AGENTS.md"
check "CLAUDE.md is a link to AGENTS.md" test "$(readlink "$WS/_common/CLAUDE.md")" = AGENTS.md
check "READ-FIRST written with workspace path" grep -q "$WS" "$WS/_common/docs/READ-FIRST.md"
check "handoff folder created" test -d "$WS/_common/docs/next-session-handoff"
check "workspace CLAUDE.md imports the shared rulebook" grep -q "@$WS/_common/AGENTS.md" "$WS/CLAUDE.md"
check "workspace AGENTS.md points at the shared rulebook" grep -q "$WS/_common/AGENTS.md" "$WS/AGENTS.md"
check "rc file sources the shell layer exactly once" test "$(grep -c '# oneroof' "$HOME/.zshrc")" -eq 1
check "home notes written" grep -q 'oneroof home note' "$HOME/CLAUDE.md"
check "home READ-FIRST is a link" test -L "$HOME/READ-FIRST.md"
MEM="$HOME/.claude/projects/$(printf '%s' "$WS" | sed 's/[^A-Za-z0-9]/-/g')/memory"
check "memory dir created" test -d "$MEM"
check "settings: memory pin + hooks present" python3 "$ROOT/lib/claude_settings.py" check "$HOME/.claude/settings.json" "$MEM" "$ROOT/guard/claude-hook.sh"
check "settings: other keys kept" python3 -c "import json,sys; d=json.load(open('$HOME/.claude/settings.json')); sys.exit(0 if d['theme']=='dark' and d['hooks']['Stop'] else 1)"
check "settings: hook entries not duplicated by second install" python3 -c "import json,sys; d=json.load(open('$HOME/.claude/settings.json')); sys.exit(0 if len(d['hooks']['UserPromptSubmit'])==1 else 1)"
check "settings backup written" ls "$HOME/.claude/"settings.json.before-oneroof-*
check "codex stand-in written" test -x "$CFG/bin/codex"
check "kimi stand-in written" test -x "$CFG/bin/kimi"

echo "== claude hook (layer 3)"
H="$ROOT/guard/claude-hook.sh"
check "blocks a prompt from ~" sh -c "printf '{\"cwd\":\"%s\"}' '$HOME' | '$H' prompt | grep -q '\"decision\":\"block\"'"
check "blocks a prompt from /tmp" sh -c "printf '{\"cwd\":\"/tmp\"}' | '$H' prompt | grep -q block"
check "blocks a look-alike folder (~/ProjectsOld)" sh -c "printf '{\"cwd\":\"%s\"}' '${WS}Old' | '$H' prompt | grep -q block"
check "allows the workspace (no output)" sh -c "test -z \"\$(printf '{\"cwd\":\"%s\"}' '$WS' | '$H' prompt)\""
check "allows a repo inside the workspace" sh -c "test -z \"\$(printf '{\"cwd\":\"%s/app/src\"}' '$WS' | '$H' prompt)\""
check "start mode warns the user and the model" sh -c "printf '{\"cwd\":\"%s\"}' '$HOME' | '$H' start | python3 -c 'import json,sys; d=json.load(sys.stdin); assert d[\"systemMessage\"] and d[\"hookSpecificOutput\"][\"additionalContext\"]'"
check "ROOF_ALLOW_OUTSIDE=1 lets a one-off through" sh -c "test -z \"\$(printf '{\"cwd\":\"/tmp\"}' | ROOF_ALLOW_OUTSIDE=1 '$H' prompt)\""
check "falls back to \$PWD without a payload" sh -c "cd /tmp && '$H' prompt </dev/null | grep -q block"

echo "== PATH stand-ins (layer 2b)"
(cd "$HOME" && "$CFG/bin/codex" --version >/dev/null 2>&1); check "codex refuses in ~ (exit 64)" test $? -eq 64
(cd /tmp && "$CFG/bin/kimi" >/dev/null 2>&1); check "kimi refuses in /tmp (exit 64)" test $? -eq 64
mkdir -p "$WS/app"
check "codex runs the real binary inside the workspace" sh -c "cd '$WS/app' && '$CFG/bin/codex' | grep -q 'REAL codex'"
check "ROOF_ALLOW_OUTSIDE=1 runs it anywhere" sh -c "cd /tmp && ROOF_ALLOW_OUTSIDE=1 '$CFG/bin/codex' | grep -q 'REAL codex'"
ln -s "$WS/app" "$HOME/applink"
check "a symlink into the workspace counts as inside" sh -c "cd '$HOME/applink' && '$CFG/bin/codex' | grep -q 'REAL codex'"

echo "== shell layer (layers 1 + 2)"
out="$(cd "$HOME" && bash -c ". '$ROOT/shell/oneroof.sh'; codex" 2>&1)"
check "typing codex in ~ moves to the workspace and runs it there" sh -c "printf '%s' \"\$1\" | grep -q \"REAL codex in $(phys "$WS")\$\"" _ "$out"
check "wrapper says why it moved" sh -c "printf '%s' \"\$1\" | grep -q 'moving there'" _ "$out"
out="$(cd "$WS/app" && bash -c ". '$ROOT/shell/oneroof.sh'; claude")"
check "claude inside the workspace stays put" test "$out" = "REAL claude in $(phys "$WS/app")"
out="$(cd "$HOME" && bash -c ". '$ROOT/shell/oneroof.sh'; pwd")"
check "non-interactive shells never auto-cd" test "$out" = "$HOME"
check "stand-ins are first on PATH after sourcing" bash -c ". '$ROOT/shell/oneroof.sh'; test \"\$(type -P codex)\" = '$CFG/bin/codex'"

echo "== doctor"
PATH="$CFG/bin:$PATH" "$ROOF" doctor > "$SANDBOX/doctor.log" 2>&1; check "doctor passes after install" test $? -eq 0
grep -q 'claude hook blocks a session in ~ (live)' "$SANDBOX/doctor.log"; check "doctor tests the hook live" test $? -eq 0
python3 "$ROOT/lib/claude_settings.py" uninstall "$HOME/.claude/settings.json" "$ROOT/guard/claude-hook.sh"
"$ROOF" doctor > "$SANDBOX/doctor2.log" 2>&1; check "doctor fails when the memory pin is removed" test $? -ne 0
"$ROOF" install >/dev/null 2>&1

echo "== never clobber"
rm -f "$HOME/AGENTS.md"; echo "my own notes" > "$HOME/AGENTS.md"; echo "custom" > "$WS/_common/docs/READ-FIRST.md.keep"
cp "$WS/_common/AGENTS.md" "$SANDBOX/rulebook.before"; echo "owner edit" >> "$WS/_common/AGENTS.md"
"$ROOF" install > "$SANDBOX/install3.log" 2>&1
check "an existing ~/AGENTS.md that isn't ours is left alone" grep -qx 'my own notes' "$HOME/AGENTS.md"
check "install warns about it" grep -q 'not ours' "$SANDBOX/install3.log"
check "an edited shared rulebook is never overwritten" grep -q 'owner edit' "$WS/_common/AGENTS.md"

echo "== doors (every agent finds READ-FIRST from every level)"
mkdir -p "$WS/projA/repo1" "$WS/projA/repo2" "$WS/solo-repo"; for r in projA/repo1 projA/repo2 solo-repo; do git -C "$WS/$r" init -q; done
echo "repo ctx" > "$WS/projA/repo1/CLAUDE.md"; echo "mine" > "$WS/projA/repo2/AGENTS.md"
"$ROOF" doors --check >/dev/null 2>&1; check "doors --check fails while doors are missing" test $? -ne 0
"$ROOF" doors > "$SANDBOX/doors.log" 2>&1
check "project folder gets an AGENTS.md door" grep -q 'oneroof door' "$WS/projA/AGENTS.md"
check "project folder gets a READ-FIRST link" test -L "$WS/projA/READ-FIRST.md"
check "repo door points at the shared READ-FIRST" test "$(cd "$WS/projA/repo1" && readlink READ-FIRST.md)" = "../../_common/docs/READ-FIRST.md"
check "repo door mentions the repo's own CLAUDE.md" grep -q 'CLAUDE.md' "$WS/projA/repo1/AGENTS.md"
check "a repo's own AGENTS.md is never overwritten" grep -qx mine "$WS/projA/repo2/AGENTS.md"
check "a top-level repo gets a door" test -f "$WS/solo-repo/AGENTS.md"
check "Gemini global note written" grep -q 'Launch-folder rule' "$HOME/.gemini/GEMINI.md"
check "Gemini reads AGENTS.md (context.fileName)" python3 -c "import json,sys; d=json.load(open('$HOME/.gemini/settings.json')); sys.exit(0 if 'AGENTS.md' in d['context']['fileName'] else 1)"
"$ROOF" doors --check >/dev/null 2>&1; check "doors --check passes after roof doors" test $? -eq 0
"$ROOF" doors > "$SANDBOX/doors2.log" 2>&1; check "roof doors is idempotent" grep -q 'doors: 0 created' "$SANDBOX/doors2.log"
(cd "$HOME" && "$CFG/bin/gemini" >/dev/null 2>&1); check "gemini stand-in refuses in ~ (exit 64)" test $? -eq 64
(cd "$HOME" && "$CFG/bin/agy" >/dev/null 2>&1); check "agy stand-in refuses in ~ (exit 64)" test $? -eq 64

echo "== sync-skills"
mkdir -p "$HOME/.codex" "$SANDBOX/skills/rhythms/handoff" "$SANDBOX/skills/rhythms/nightly-only" "$SANDBOX/skills/tools/plain"
printf -- '---\nname: handoff\nruntime: [shared]\n---\n' > "$SANDBOX/skills/rhythms/handoff/SKILL.md"
printf -- '---\nname: nightly-only\nruntime: [nightly]\n---\n' > "$SANDBOX/skills/rhythms/nightly-only/SKILL.md"
printf -- '---\nname: plain\n---\n' > "$SANDBOX/skills/tools/plain/SKILL.md"
mkdir -p "$HOME/.claude/skills/plain-real" "$HOME/.claude/skills/plain"; rmdir "$HOME/.claude/skills/plain"
"$ROOF" sync-skills "$SANDBOX/skills" > "$SANDBOX/sync.log" 2>&1
S="$(phys "$SANDBOX/skills")"
check "skill linked into Claude's home" test "$(readlink "$HOME/.claude/skills/handoff")" = "$S/rhythms/handoff"
check "skill linked into Codex's home" test -L "$HOME/.codex/skills/handoff"
check "skill without runtime is linked" test -L "$HOME/.codex/skills/plain"
check "background-only skill is skipped" test ! -e "$HOME/.claude/skills/nightly-only"
check "README-NOT-CANONICAL dropped" test -f "$HOME/.codex/skills/README-NOT-CANONICAL.md"
rm -rf "$SANDBOX/skills/tools/plain"; "$ROOF" sync-skills "$SANDBOX/skills" >/dev/null 2>&1
check "dangling link pruned after a skill is deleted" test ! -L "$HOME/.claude/skills/plain"
check "a real folder in a skills home is never touched" test -d "$HOME/.claude/skills/plain-real"

echo "== uninstall"
"$ROOF" uninstall > "$SANDBOX/uninstall.log" 2>&1
check "pin + hooks removed" sh -c "! python3 '$ROOT/lib/claude_settings.py' check '$HOME/.claude/settings.json' '$MEM' '$ROOT/guard/claude-hook.sh'"
check "unrelated settings survive uninstall" python3 -c "import json,sys; d=json.load(open('$HOME/.claude/settings.json')); sys.exit(0 if d['theme']=='dark' and d['hooks']['Stop'] else 1)"
check "rc line removed" sh -c "! grep -q '# oneroof' '$HOME/.zshrc'"
check "our home note removed" test ! -e "$HOME/CLAUDE.md"
check "someone else's home note kept" grep -qx 'my own notes' "$HOME/AGENTS.md"
check "stand-ins + config removed" test ! -e "$CFG"
check "shared docs kept" test -f "$WS/_common/AGENTS.md"
check "memory kept" test -d "$MEM"

echo "== fanout (roof swarm: parallel tasks in worktrees)"
bash "$ROOT/tests/test_fanout.sh" > "$SANDBOX/fanout.log" 2>&1; check "fanout: parallel tasks in worktrees, claims, timeout, retry, clean merge" test $? -eq 0

echo ""
echo "$pass passed, $fail failed"
[ "$fail" = 0 ]
