#!/usr/bin/env bash
# oneroof · tests for tools/fanout.py (roof swarm): parallel tasks in worktrees, claims, timeout, retry, clean merge.
#   bash tests/test_fanout.sh   (exit 0 = all pass; everything happens in a throwaway temp dir)
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
FANOUT="$ROOT/tools/fanout.py"
TMP="$(cd "$(mktemp -d "${TMPDIR:-/tmp}/fanout-test.XXXXXX")" && pwd -P)"
trap 'rm -rf "$TMP"' EXIT
fails=0
ok()   { printf '  ok   %s\n' "$1"; }
bad()  { fails=$((fails + 1)); printf '  FAIL %s\n' "$1"; }
expect() { local name="$1"; shift; if "$@" >/dev/null 2>&1; then ok "$name"; else bad "$name"; fi; }

new_repo() { # new_repo <dir>: a fresh repo with one commit on branch main
  mkdir -p "$1/src"
  git -C "$1" init --quiet
  git -C "$1" checkout --quiet -b main
  git -C "$1" config user.email test@example.com
  git -C "$1" config user.name test
  echo seed > "$1/README"; touch "$1/src/.keep"
  git -C "$1" add README src/.keep
  git -C "$1" commit --quiet -m seed
}
run_dir() { ls -d "$1"/.fanout/*/ 2>/dev/null | head -1; } # the (only) run dir of repo $1
task_field() { # task_field <run-dir> <task-id> <field>
  python3 -c 'import json,sys; d=json.load(open(sys.argv[1]+"/run.json")); print(next(t for t in d["tasks"] if t["id"]==sys.argv[2])[sys.argv[3]])' "$1" "$2" "$3"
}
worktree_count() { git -C "$1" worktree list | wc -l | tr -d ' '; }

echo "== a. golden: 2 parallel tasks -> 2 green branches -> clean merge -> clean"
R="$TMP/a"; new_repo "$R"
cat > "$R/spec.json" <<'JSON'
{"max_parallel": 2, "timeout_s": 10, "retries": 0, "min_free_gb": 0,
 "tasks": [{"id": "one", "files": ["src/one.txt"], "cmd": "echo one > src/one.txt", "check": "grep -q one src/one.txt"},
           {"id": "two", "files": ["./src/two.txt"], "cmd": "echo two > src/two.txt"}]}
JSON
git -C "$R" add spec.json && git -C "$R" commit --quiet -m spec
rc=0; python3 "$FANOUT" run "$R/spec.json" > "$TMP/a.log" 2>&1 || rc=$?
expect "run exits 0" test "$rc" -eq 0
D="$(run_dir "$R")"
expect "task one green" test "$(task_field "$D" one status)" = green
expect "task two green" test "$(task_field "$D" two status)" = green
expect "2 task branches exist" test "$(git -C "$R" branch --list 'fanout/*' | wc -l | tr -d ' ')" -eq 2
expect "claims carry absolute path + sessionId" python3 -c 'import json,sys; c=json.load(open(sys.argv[1]+"/run.json"))["tasks"][0]["claims"][0]; sys.exit(0 if c["path"].startswith("/") and c["sessionId"].startswith("fanout:") and c["since"] else 1)' "$D"
rc=0; python3 "$FANOUT" merge "$D" > "$TMP/a-merge.log" 2>&1 || rc=$?
expect "merge exits 0" test "$rc" -eq 0
expect "one.txt on main" test "$(git -C "$R" show main:src/one.txt)" = one
expect "two.txt on main" test "$(git -C "$R" show main:src/two.txt)" = two
expect "runner folders never committed" test -z "$(git -C "$R" ls-tree -r --name-only main | grep -E '^\.(fanout|worktrees)/' || true)"
python3 "$FANOUT" clean "$D" > "$TMP/a-clean.log" 2>&1 || true
expect "clean removes worktrees" test "$(worktree_count "$R")" -eq 1
expect "clean deletes merged branches" test -z "$(git -C "$R" branch --list 'fanout/*')"

echo "== b. overlapping claims are refused before anything is made"
R="$TMP/b"; new_repo "$R"
cat > "$TMP/b.json" <<'JSON'
{"repo": "b", "min_free_gb": 0,
 "tasks": [{"id": "a", "files": ["src/"], "cmd": "true"}, {"id": "b", "files": ["src/x.txt"], "cmd": "true"}]}
JSON
rc=0; python3 "$FANOUT" run "$TMP/b.json" > "$TMP/b.log" 2>&1 || rc=$?
expect "exit 2" test "$rc" -eq 2
expect "names both tasks and the path" grep -q "task a claims 'src' and task b claims 'src/x.txt'" "$TMP/b.log"
expect "no worktree made" test "$(worktree_count "$R")" -eq 1
expect "no run dir made" test ! -e "$R/.fanout"

echo "== c. editing outside the claim fails the task"
R="$TMP/c"; new_repo "$R"
cat > "$R/spec.json" <<'JSON'
{"timeout_s": 10, "retries": 1, "min_free_gb": 0,
 "tasks": [{"id": "sneaky", "files": ["src/mine.txt"], "cmd": "echo x > src/mine.txt; echo y > README"}]}
JSON
rc=0; python3 "$FANOUT" run "$R/spec.json" > "$TMP/c.log" 2>&1 || rc=$?
D="$(run_dir "$R")"
expect "exit 1" test "$rc" -eq 1
expect "status failed" test "$(task_field "$D" sneaky status)" = failed
expect "reason says outside its claim" sh -c "python3 -c 'import json; print(json.load(open(\"$D/run.json\"))[\"tasks\"][0][\"reason\"])' | grep -q 'outside its claim: README'"
expect "claim breach is not retried" test "$(task_field "$D" sneaky attempts)" -eq 1

echo "== d. timeout"
R="$TMP/d"; new_repo "$R"
cat > "$R/spec.json" <<'JSON'
{"timeout_s": 1, "retries": 0, "min_free_gb": 0,
 "tasks": [{"id": "slow", "files": ["src/slow.txt"], "cmd": "sleep 5"}]}
JSON
start=$SECONDS; rc=0; python3 "$FANOUT" run "$R/spec.json" > "$TMP/d.log" 2>&1 || rc=$?
D="$(run_dir "$R")"
expect "exit 1" test "$rc" -eq 1
expect "status timeout" test "$(task_field "$D" slow status)" = timeout
expect "killed well before sleep ends" test $((SECONDS - start)) -lt 5

echo "== e. retry: fails once, then succeeds"
R="$TMP/e"; new_repo "$R"
cat > "$R/spec.json" <<JSON
{"timeout_s": 10, "retries": 1, "min_free_gb": 0,
 "tasks": [{"id": "flaky", "files": ["src/f.txt"],
            "cmd": "echo partial > src/f.txt; if [ -e '$TMP/e.marker' ]; then echo done > src/f.txt; else touch '$TMP/e.marker'; exit 1; fi"}]}
JSON
rc=0; python3 "$FANOUT" run "$R/spec.json" > "$TMP/e.log" 2>&1 || rc=$?
D="$(run_dir "$R")"
expect "exit 0" test "$rc" -eq 0
expect "status green" test "$(task_field "$D" flaky status)" = green
expect "attempts 2" test "$(task_field "$D" flaky attempts)" -eq 2
expect "a log per attempt" test -f "$D/flaky.attempt1.log" -a -f "$D/flaky.attempt2.log"

echo "== f. dry run creates nothing"
R="$TMP/f"; new_repo "$R"
cat > "$TMP/f.json" <<'JSON'
{"repo": "f", "min_free_gb": 0, "tasks": [{"id": "x", "files": ["src/x.txt"], "cmd": "echo x > src/x.txt"}]}
JSON
rc=0; python3 "$FANOUT" run "$TMP/f.json" --dry-run > "$TMP/f.log" 2>&1 || rc=$?
expect "exit 0" test "$rc" -eq 0
expect "plan lists the claim" grep -q "claims    src/x.txt" "$TMP/f.log"
expect "no worktree" test "$(worktree_count "$R")" -eq 1
expect "no run dir" test ! -e "$R/.fanout"
expect "no branch" test -z "$(git -C "$R" branch --list 'fanout/*')"

echo ""
if [ "$fails" -eq 0 ]; then echo "all fanout tests passed"; else echo "$fails fanout check(s) failed"; exit 1; fi
