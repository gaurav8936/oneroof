#!/usr/bin/env python3
# oneroof · fanout: run a handful of tasks in parallel, each in its own git worktree, then merge the green ones.
#
#   roof swarm run <spec.json> [--dry-run]   validate, make one worktree + branch per task, run them, commit the green ones
#   roof swarm merge <run-dir>               merge each green branch into the current branch (--no-ff), stop at a conflict
#   roof swarm clean <run-dir> [--force]     remove the run's worktrees; delete branches that are merged (or all, --force)
#
# Spec (JSON; `repo` is relative to the spec file's folder):
#   {"repo": ".", "base": "HEAD", "max_parallel": 2, "timeout_s": 900, "retries": 1, "min_free_gb": 1,
#    "tasks": [{"id": "a", "files": ["src/a.py"], "cmd": "shell command", "check": "optional shell command"}]}
#
# Guard rails: every task claims the files it may edit and claims must not overlap (refused before anything is made);
# a task that edits outside its claim fails; parallelism is capped at 4, retries at 3; each attempt has a timeout
# (the whole process group is killed); a free-disk check runs first. State lives in <repo>/.fanout/<run-id>/run.json
# (its `claims` objects are what the One Roof Mac app imports). Exit codes: 0 all green, 1 some task failed, 2 refused.
# Python 3.9+ standard library only.
import argparse
import concurrent.futures
import datetime
import json
import os
import posixpath
import re
import shutil
import signal
import subprocess
import sys
import threading
import time

MAX_PARALLEL_CEILING = 4
RETRIES_CEILING = 3
DEFAULTS = {"base": "HEAD", "max_parallel": 2, "timeout_s": 900, "retries": 1, "min_free_gb": 1}
ID_RE = re.compile(r"^[a-z0-9-]+$")
FALLBACK_IDENTITY = ["-c", "user.name=fanout", "-c", "user.email=fanout@localhost"]


class Refused(Exception):
    """A spec or repo problem found before anything was created (exit 2)."""


def now_iso():
    return datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def git(repo, *args, check=True):
    p = subprocess.run(["git", "-C", repo] + list(args), capture_output=True, text=True)
    if check and p.returncode != 0:
        raise RuntimeError("git %s failed: %s" % (" ".join(args), (p.stderr or p.stdout).strip()))
    return p


def identity_args(repo):
    """-c user.name/email only when the repo has no identity configured (never overrides the user's)."""
    has_name = git(repo, "config", "user.name", check=False).stdout.strip()
    has_mail = git(repo, "config", "user.email", check=False).stdout.strip()
    return [] if has_name and has_mail else FALLBACK_IDENTITY


def norm_claim(path):
    """'./src/' -> 'src'. Claims are repo-relative; absolute paths and '..' are refused."""
    p = path.strip().replace("\\", "/")
    while p.startswith("./"):
        p = p[2:]
    p = posixpath.normpath(p) if p else p
    if not p or p == "." or p.startswith("/") or p == ".." or p.startswith("../"):
        raise Refused("claim %r must be a path inside the repo" % path)
    return p


def covers(claim, path):
    """True when `path` is `claim` itself or lies inside the directory `claim`."""
    return path == claim or path.startswith(claim + "/")


def changed_files(worktree):
    """Every path git sees as changed in the worktree, untracked included (both sides of a rename)."""
    out = git(worktree, "status", "--porcelain=v1", "-z", "--untracked-files=all").stdout
    parts, files, i = out.split("\0"), [], 0
    while i < len(parts):
        entry = parts[i]
        i += 1
        if len(entry) < 4:
            continue
        status, path = entry[:2], entry[3:]
        files.append(path)
        if "R" in status or "C" in status:  # -z puts the original path in the next field
            files.append(parts[i])
            i += 1
    return sorted(set(files))


def write_json_atomic(path, data):
    tmp = "%s.tmp.%d.%d" % (path, os.getpid(), threading.get_ident())
    with open(tmp, "w") as f:
        json.dump(data, f, indent=2)
        f.write("\n")
    os.replace(tmp, path)


def exclude_runner_dirs(repo):
    """Keep .fanout/ and .worktrees/ out of `git status` locally (info/exclude is never committed)."""
    common = git(repo, "rev-parse", "--git-common-dir").stdout.strip()
    if not os.path.isabs(common):
        common = os.path.join(repo, common)
    path = os.path.join(common, "info", "exclude")
    os.makedirs(os.path.dirname(path), exist_ok=True)
    have = open(path).read().split("\n") if os.path.exists(path) else []
    missing = [d for d in ("/.fanout/", "/.worktrees/") if d not in have]
    if missing:
        with open(path, "a") as f:
            f.write("".join("\n" + d for d in missing) + "\n")


# ---------------------------------------------------------------- spec


def load_spec(spec_path):
    try:
        with open(spec_path) as f:
            spec = json.load(f)
    except (OSError, ValueError) as e:
        raise Refused("cannot read spec %s: %s" % (spec_path, e))
    if not isinstance(spec, dict):
        raise Refused("spec must be a JSON object")
    cfg = dict(DEFAULTS)
    cfg.update({k: spec[k] for k in DEFAULTS if k in spec})
    for k in ("max_parallel", "timeout_s", "retries", "min_free_gb"):
        if not isinstance(cfg[k], (int, float)) or isinstance(cfg[k], bool) or cfg[k] < 0:
            raise Refused("%s must be a non-negative number" % k)
    cfg["max_parallel"] = max(1, min(int(cfg["max_parallel"]), MAX_PARALLEL_CEILING))
    cfg["retries"] = min(int(cfg["retries"]), RETRIES_CEILING)
    spec_dir = os.path.dirname(os.path.abspath(spec_path))
    cfg["repo"] = os.path.realpath(os.path.join(spec_dir, spec.get("repo", ".")))
    cfg["spec"] = os.path.abspath(spec_path)

    tasks, seen = spec.get("tasks"), set()
    if not isinstance(tasks, list) or not tasks:
        raise Refused("spec needs a non-empty `tasks` list")
    for t in tasks:
        if not isinstance(t, dict):
            raise Refused("each task must be an object")
        tid = t.get("id")
        if not isinstance(tid, str) or not ID_RE.match(tid):
            raise Refused("task id %r must match [a-z0-9-]+" % (tid,))
        if tid in seen:
            raise Refused("duplicate task id %r" % tid)
        seen.add(tid)
        files = t.get("files")
        if not isinstance(files, list) or not files or not all(isinstance(x, str) for x in files):
            raise Refused("task %s needs `files`: a non-empty list of paths" % tid)
        if not isinstance(t.get("cmd"), str) or not t["cmd"].strip():
            raise Refused("task %s needs `cmd`" % tid)
        if t.get("check") is not None and not isinstance(t["check"], str):
            raise Refused("task %s: `check` must be a string" % tid)
        t["files"] = sorted(set(norm_claim(x) for x in files))

    # no two tasks may claim the same path, or a path inside another's directory claim
    for i, a in enumerate(tasks):
        for b in tasks[i + 1:]:
            for pa in a["files"]:
                for pb in b["files"]:
                    if covers(pa, pb) or covers(pb, pa):
                        raise Refused("claims overlap: task %s claims %r and task %s claims %r"
                                      % (a["id"], pa, b["id"], pb))
    cfg["tasks"] = tasks
    return cfg


def check_repo(cfg):
    repo = cfg["repo"]
    if not os.path.isdir(repo):
        raise Refused("repo %s does not exist" % repo)
    top = git(repo, "rev-parse", "--show-toplevel", check=False)
    if top.returncode != 0:
        raise Refused("%s is not a git repo" % repo)
    cfg["repo"] = repo = os.path.realpath(top.stdout.strip())
    dirty = git(repo, "status", "--porcelain", "--untracked-files=no").stdout.strip()
    if dirty:
        raise Refused("working tree of %s is not clean (commit or stash first):\n%s" % (repo, dirty))
    base = git(repo, "rev-parse", "--verify", "--quiet", cfg["base"] + "^{commit}", check=False)
    if base.returncode != 0:
        raise Refused("base %r is not a commit" % cfg["base"])
    cfg["base_sha"] = base.stdout.strip()
    free_gb = shutil.disk_usage(repo).free / 1024 ** 3
    if free_gb < cfg["min_free_gb"]:
        raise Refused("only %.1f GB free on the repo's volume; need %s GB (min_free_gb)" % (free_gb, cfg["min_free_gb"]))


def new_run_id(repo):
    """UTC timestamp; waits for the next second if a run with this id already exists."""
    for _ in range(5):
        rid = datetime.datetime.now(datetime.timezone.utc).strftime("%Y%m%d-%H%M%S")
        if not os.path.exists(os.path.join(repo, ".fanout", rid)):
            return rid
        time.sleep(1)
    raise Refused("could not pick a fresh run id")


# ---------------------------------------------------------------- run


class Run:
    def __init__(self, cfg, run_id):
        self.cfg, self.run_id = cfg, run_id
        self.repo = cfg["repo"]
        self.dir = os.path.join(self.repo, ".fanout", run_id)
        self.lock = threading.Lock()
        self.state = {"run_id": run_id, "spec": cfg["spec"], "repo": self.repo, "base": cfg["base"],
                      "base_sha": cfg["base_sha"], "started": now_iso(), "finished": None, "tasks": []}
        for t in cfg["tasks"]:
            since = now_iso()
            self.state["tasks"].append({
                "id": t["id"], "status": "queued", "attempts": 0,
                "branch": "fanout/%s/%s" % (run_id, t["id"]),
                "worktree": os.path.join(self.repo, ".worktrees", "fanout-%s-%s" % (run_id, t["id"])),
                "changed": [], "reason": "",
                "claims": [{"path": os.path.join(self.repo, f), "sessionId": "fanout:%s:%s" % (run_id, t["id"]),
                            "since": since} for f in t["files"]],
            })

    def task_state(self, tid):
        return next(s for s in self.state["tasks"] if s["id"] == tid)

    def update(self, tid=None, **fields):
        with self.lock:
            if tid is not None:
                self.task_state(tid).update(fields)
            write_json_atomic(os.path.join(self.dir, "run.json"), self.state)

    def attempt(self, task, ts, n):
        """One try of cmd (+check). Returns (outcome, reason, changed) with outcome in green/failed/timeout/claim."""
        wt, log_path = ts["worktree"], os.path.join(self.dir, "%s.attempt%d.log" % (task["id"], n))
        timeout = self.cfg["timeout_s"]
        with open(log_path, "w") as log:
            log.write("$ %s\n" % task["cmd"])
            log.flush()
            proc = subprocess.Popen(["bash", "-c", task["cmd"]], cwd=wt, stdout=log, stderr=subprocess.STDOUT,
                                    stdin=subprocess.DEVNULL, start_new_session=True)
            try:
                rc = proc.wait(timeout=timeout)
            except subprocess.TimeoutExpired:
                try:
                    os.killpg(proc.pid, signal.SIGKILL)
                except ProcessLookupError:
                    pass
                proc.wait()
                log.write("\n[fanout] timed out after %ss; process group killed\n" % timeout)
                return "timeout", "timed out after %ss" % timeout, []
        changed = changed_files(wt)
        outside = [p for p in changed if not any(covers(c, p) for c in task["files"])]
        if outside:
            return "claim", "edited outside its claim: %s" % ", ".join(outside), changed
        if rc != 0:
            return "failed", "cmd exited %d" % rc, changed
        if not changed:
            return "failed", "no changes", changed
        if task.get("check"):
            with open(log_path, "a") as log:
                log.write("\n$ %s\n" % task["check"])
                log.flush()
                try:
                    crc = subprocess.run(["bash", "-c", task["check"]], cwd=wt, stdout=log, stderr=subprocess.STDOUT,
                                         stdin=subprocess.DEVNULL, timeout=timeout, start_new_session=True).returncode
                except subprocess.TimeoutExpired:
                    return "timeout", "check timed out after %ss" % timeout, changed
            if crc != 0:
                return "failed", "check exited %d" % crc, changed
        return "green", "", changed

    def run_task(self, task):
        ts = self.task_state(task["id"])
        wt, tries = ts["worktree"], 1 + self.cfg["retries"]
        self.update(task["id"], status="running")
        outcome, reason, changed = "failed", "", []
        for n in range(1, tries + 1):
            if n > 1:  # fresh start for a retry
                git(wt, "reset", "--hard", "--quiet")
                git(wt, "clean", "-fdq")
            self.update(task["id"], attempts=n)
            try:
                outcome, reason, changed = self.attempt(task, ts, n)
            except Exception as e:  # a crash in the runner itself is a failed attempt, not a dead run
                outcome, reason, changed = "failed", "runner error: %s" % e, []
            if outcome in ("green", "claim"):
                break
        if outcome == "green":
            try:
                git(wt, "add", "-A", "--", *changed)
                git(wt, *(identity_args(wt) + ["commit", "--quiet", "--no-verify", "-m",
                                               "fanout %s: %s" % (self.run_id, task["id"])]))
            except RuntimeError as e:
                outcome, reason = "failed", "commit failed: %s" % e
        status = {"green": "green", "timeout": "timeout"}.get(outcome, "failed")
        self.update(task["id"], status=status, reason=reason, changed=changed)

    def execute(self):
        os.makedirs(self.dir)
        exclude_runner_dirs(self.repo)
        os.makedirs(os.path.join(self.repo, ".worktrees"), exist_ok=True)
        self.update()
        for ts in self.state["tasks"]:
            git(self.repo, "worktree", "add", "--quiet", "-b", ts["branch"], ts["worktree"], self.cfg["base_sha"])
        with concurrent.futures.ThreadPoolExecutor(max_workers=self.cfg["max_parallel"]) as pool:
            list(pool.map(self.run_task, self.cfg["tasks"]))
        self.state["finished"] = now_iso()
        self.update()


def print_table(tasks):
    rows = [("TASK", "STATUS", "TRIES", "FILES", "REASON")]
    rows += [(t["id"], t["status"], str(t["attempts"]), str(len(t["changed"])), t["reason"]) for t in tasks]
    widths = [max(len(r[i]) for r in rows) for i in range(4)]
    for r in rows:
        print("  ".join(r[i].ljust(widths[i]) for i in range(4)) + "  " + r[4])


def cmd_run(args):
    try:
        cfg = load_spec(args.spec)
        check_repo(cfg)
        run_id = "<run-id>" if args.dry_run else new_run_id(cfg["repo"])
    except Refused as e:
        print("fanout: refused: %s" % e, file=sys.stderr)
        return 2
    if args.dry_run:
        run = Run(cfg, run_id)
        print("fanout dry run · repo %s · base %s (%s)" % (cfg["repo"], cfg["base"], cfg["base_sha"][:12]))
        print("max_parallel %d · timeout_s %s · retries %d · min_free_gb %s"
              % (cfg["max_parallel"], cfg["timeout_s"], cfg["retries"], cfg["min_free_gb"]))
        print("run dir  %s" % run.dir)
        for t, ts in zip(cfg["tasks"], run.state["tasks"]):
            print("\n[%s] %s" % (t["id"], t["cmd"]))
            if t.get("check"):
                print("  check     %s" % t["check"])
            print("  claims    %s" % ", ".join(t["files"]))
            print("  worktree  %s" % ts["worktree"])
            print("  branch    %s" % ts["branch"])
        print("\n(dry run: nothing created)")
        return 0
    run = Run(cfg, run_id)
    try:
        run.execute()
    except RuntimeError as e:
        print("fanout: %s" % e, file=sys.stderr)
        return 1
    print("fanout run %s · %s" % (run_id, run.dir))
    print_table(run.state["tasks"])
    return 0 if all(t["status"] == "green" for t in run.state["tasks"]) else 1


# ---------------------------------------------------------------- merge / clean


def load_run(run_dir):
    path = os.path.join(run_dir, "run.json")
    try:
        with open(path) as f:
            return json.load(f), path
    except (OSError, ValueError) as e:
        raise Refused("cannot read %s: %s" % (path, e))


def is_merged(repo, branch):
    return git(repo, "merge-base", "--is-ancestor", branch, "HEAD", check=False).returncode == 0


def cmd_merge(args):
    try:
        state, path = load_run(args.run_dir)
    except Refused as e:
        print("fanout: %s" % e, file=sys.stderr)
        return 2
    repo = state["repo"]
    current = git(repo, "rev-parse", "--abbrev-ref", "HEAD").stdout.strip()
    ident = identity_args(repo)
    for t in state["tasks"]:
        if t["status"] != "green":
            print("skip   %s (%s)" % (t["id"], t["status"]))
            continue
        if is_merged(repo, t["branch"]):
            print("done   %s (already in %s)" % (t["id"], current))
            continue
        p = git(repo, *(ident + ["merge", "--no-ff", "--no-edit", "-m",
                                 "fanout %s: merge %s" % (state["run_id"], t["id"]), t["branch"]]), check=False)
        if p.returncode != 0:
            git(repo, "merge", "--abort", check=False)
            print("CONFLICT %s: merging %s into %s failed; merge aborted, later tasks not merged.\n%s"
                  % (t["id"], t["branch"], current, (p.stdout + p.stderr).strip()), file=sys.stderr)
            return 1
        t["merged"] = True
        write_json_atomic(path, state)
        print("merged %s -> %s" % (t["branch"], current))
    return 0


def cmd_clean(args):
    try:
        state, _ = load_run(args.run_dir)
    except Refused as e:
        print("fanout: %s" % e, file=sys.stderr)
        return 2
    repo, kept = state["repo"], []
    for t in state["tasks"]:
        if os.path.exists(t["worktree"]):
            git(repo, "worktree", "remove", "--force", t["worktree"], check=False)
            print("removed worktree %s" % t["worktree"])
        if git(repo, "rev-parse", "--verify", "--quiet", "refs/heads/" + t["branch"], check=False).returncode != 0:
            continue
        if args.force or is_merged(repo, t["branch"]):
            git(repo, "branch", "-D", t["branch"], check=False)
            print("deleted branch %s" % t["branch"])
        else:
            kept.append(t["branch"])
    git(repo, "worktree", "prune", check=False)
    for b in kept:
        print("kept unmerged branch %s (use --force to delete)" % b)
    return 0


def main(argv=None):
    ap = argparse.ArgumentParser(prog="fanout.py", description="Run tasks in parallel, one git worktree each, "
                                 "with non-overlapping file claims, a parallel ceiling, timeouts and capped retries.")
    sub = ap.add_subparsers(dest="command")
    r = sub.add_parser("run", help="run a spec")
    r.add_argument("spec")
    r.add_argument("--dry-run", action="store_true", help="validate and print the plan; create nothing")
    m = sub.add_parser("merge", help="merge the run's green branches into the current branch")
    m.add_argument("run_dir")
    c = sub.add_parser("clean", help="remove the run's worktrees and merged branches")
    c.add_argument("run_dir")
    c.add_argument("--force", action="store_true", help="also delete unmerged branches")
    args = ap.parse_args(argv)
    if args.command is None:
        ap.print_help()
        return 2
    return {"run": cmd_run, "merge": cmd_merge, "clean": cmd_clean}[args.command](args)


if __name__ == "__main__":
    sys.exit(main())
