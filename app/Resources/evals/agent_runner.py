#!/usr/bin/env python3
"""Agents on your seats as eval contestants (LAB-2067, HP EV-1). Standard library only; roof_eval.py calls it.

An agent is a model plus its harness. Here the agent CLI itself (Claude Code, Codex) answers each case of your own eval
set, headless, on your subscription login: never an API key (every *_API_KEY variable is removed from its environment),
so a seat run spends a share of the seat's five-hour window, not API credit.

Per case: a fresh detached git worktree of the set's repo at the commit before the fix (a temp folder when the repo is
not on this Mac), the agent started in it read-only with the case's question, a 10-minute limit, its final message taken
as the answer and scored by the set's own check (one of the first three files named was changed by the fix). The
worktree is removed in a `finally`, also on cancel or a crash; leftovers are swept when the next seat run starts.
Nothing is committed or pushed: the agents get read-only tools only.

Seat guard: before each case, while the seat's five-hour use is at or over the limit (the router's skip threshold, 90 %
by default), the run waits with status "waiting" and says why, instead of failing. When the use is unknown or stale
(no usage file, or older than 6 hours) the run also waits ("seat use unknown") until the use is known and under the
limit, or until the owner presses Run anyway on that run (`roof eval run-anyway <run>`, recorded in its run.json as
"seat_unknown_ok"). The gate is checked between cases, not during one: a case is one read-only question with a 10-minute
limit, so a run can pass the limit by at most one case's share. One run per seat at a time.

Containment (QA, M9): each case runs in its own worktree in the system temp folder (not under ~/Library), with that
folder as the working directory. Claude Code runs in --restricted mode (file tools confined to the working directory,
no Bash or other code-running tools, the user's, project's and local settings files ignored, so no global hooks), with
a per-run --settings JSON that also sets disableAllHooks and denies Read on secrets folders (Read rules cover Grep and
Glob too), --strict-mcp-config (no MCP servers) and --permission-prompts none (anything that would ask is refused).
Codex runs `exec --sandbox read-only` from the case folder with --ignore-user-config, --ignore-rules, --ephemeral and
the hooks, plugins, apps, browser and computer-use features off. Its read-only sandbox blocks writes, not reads: Codex
can still read files outside the case folder (the Codex CLI has no read-path restriction); Run says so.
"""
from __future__ import annotations

import fcntl
import json
import os
import re
import shutil
import signal
import subprocess
import sys
import tempfile
import time
from datetime import datetime, timezone
from pathlib import Path

EVALS = Path(os.environ.get("ONEROOF_EVALS_DIR") or Path.home() / "Library/Application Support/One Roof/evals")
RUNS = EVALS / "runs"
# Case worktrees live in the system temp folder, outside ~/Library (whose reads are denied to the agent) and outside the
# evals folder; ONEROOF_EVAL_WORKTREES overrides (tests).
WORKTREES = Path(os.environ.get("ONEROOF_EVAL_WORKTREES") or Path(tempfile.gettempdir()) / "oneroof-eval-worktrees")
USAGE = Path(os.environ.get("ONEROOF_USAGE_DIR") or Path.home() / "Library/Application Support/One Roof/usage")
CASE_TIMEOUT = int(os.environ.get("ONEROOF_AGENT_TIMEOUT") or 600)
SEAT_POLL = float(os.environ.get("ONEROOF_SEAT_POLL") or 30)
SEAT_LIMIT = 90.0          # the router's five-hour skip threshold (OneRoofCore/Router.swift, RoutingPolicy.skipFiveHour)
STALE_HOURS = 6            # as SeatUsage.stale
SHARE_GUESS = 0.003        # share of a five-hour window per case, until this Mac has measured one (labelled "guess")

# The agents that can be contestants on a seat today, and why the others cannot (shown in Run, never hidden).
SEAT_AGENTS = {
    "claude_code": {"name": "Claude Code", "seat": "C1", "lane": "Claude1", "bin": "claude"},
    "codex_cli": {"name": "Codex", "seat": "CX", "lane": "Codex", "bin": "codex"},
}
NOT_YET = {
    "opencode": ("OpenCode", "opencode", "coming: its headless mode is not verified yet"),
    "kimi_code": ("Kimi", "kimi", "no headless mode"),
    "gemini_cli": ("Gemini CLI", "gemini", "coming: headless mode not verified yet"),
    "antigravity": ("Antigravity", "antigravity", "coming: headless mode not verified yet"),
}
ORDER = ["claude_code", "codex_cli", "opencode", "kimi_code", "gemini_cli", "antigravity"]
# Removed from a seat agent's environment so it can only use its subscription login: API keys, tokens, cloud credentials
# and the switches that route Claude Code or Codex to a paid API instead of the seat. CLAUDE_CODE_OAUTH_TOKEN is the
# subscription login itself on a headless Mac, so it stays.
KEY_VARS = re.compile(r"(_API_KEY|_TOKEN|_SECRET|_SECRET_ACCESS_KEY|_ACCESS_KEY_ID|_SESSION_TOKEN)$|^AWS_|^AZURE_|^GOOGLE_APPLICATION_CREDENTIALS$"
                      r"|^CLAUDE_CODE_USE_(BEDROCK|VERTEX)$|^(ANTHROPIC|OPENAI)_BASE_URL$|^ANTHROPIC_AUTH_TOKEN$")
KEEP_VARS = {"CLAUDE_CODE_OAUTH_TOKEN"}


def strip_keys(env: dict) -> dict:
    return {k: v for k, v in env.items() if k in KEEP_VARS or not KEY_VARS.search(k)}

SYSTEM = {
    "fix-locator": ("You are helping fix a bug in this repository, checked out at the commit just before the fix. Read the "
                    "bug report, look around the code, and answer with the paths of up to three files you would change to "
                    "fix it, most likely first, one path per line, exactly as they appear in the repository. Do not edit "
                    "anything. No other text."),
    "triage": ("You are triaging a bug report for this repository, checked out at the commit just before the fix. Look around "
               "the code, then in two or three sentences say what is most likely wrong and which file you would open first "
               "(its path exactly as in the repository). Do not edit anything. Plain text."),
}
PATH = re.compile(r"[\w./+-]+\.\w+")


def now() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def read_json(p: Path, default=None):
    try:
        return json.loads(Path(p).read_text())
    except (OSError, ValueError):
        return default


def write_json(p: Path, obj) -> None:
    p.parent.mkdir(parents=True, exist_ok=True)
    tmp = p.with_suffix(p.suffix + ".tmp")
    tmp.write_text(json.dumps(obj, indent=2, sort_keys=True))
    tmp.replace(p)


def set_status(d: Path, **kw) -> dict:
    r = read_json(d / "run.json", {})
    r.update(kw)
    write_json(d / "run.json", r)
    return r


# ── which agents, which seats ─────────────────────────────────────────────────────────────────────────────────────
def find_bin(agent: str) -> str | None:
    """The agent's CLI: ONEROOF_AGENT_BIN_<AGENT> (tests use a fake), else the usual install folders, else PATH."""
    over = os.environ.get("ONEROOF_AGENT_BIN_" + agent.upper())
    if over:
        return over if os.access(over, os.X_OK) else None
    name = (SEAT_AGENTS.get(agent) or {}).get("bin") or (NOT_YET.get(agent) or (None, agent))[1]
    home = Path.home()
    for d in ("/opt/homebrew/bin", "/usr/local/bin", str(home / ".local/bin"), str(home / ".npm-global/bin"),
              str(home / ".claude/local"), str(home / "bin")):
        p = Path(d) / name
        if os.access(p, os.X_OK):
            return str(p)
    return shutil.which(name)


def seat_usage(seat: str) -> dict:
    """{'seat', 'five_hour' (percent or None), 'updated' (epoch), 'stale'}: Claude from the status line's usage file
    (the same file SeatUsage reads), Codex from its newest session log that carries rate limits."""
    lane = next((a["lane"] for a in SEAT_AGENTS.values() if a["seat"] == seat), seat)
    pct, updated = None, 0.0
    j = read_json(USAGE / f"{lane}.json")
    if j:
        rl = j.get("rate_limits") or {}
        pct = (rl.get("five_hour") or {}).get("used_percentage", (rl.get("primary") or {}).get("used_percent"))
        updated = float(j.get("updated") or 0)
    elif lane == "Codex":
        pct, updated = codex_usage()
    stale = pct is None or time.time() - updated > STALE_HOURS * 3600
    return {"seat": seat, "five_hour": pct, "updated": updated, "stale": stale}


def codex_usage() -> tuple:
    root = Path(os.environ.get("CODEX_HOME") or Path.home() / ".codex") / "sessions"
    try:
        files = sorted(root.rglob("*.jsonl"), key=lambda p: p.stat().st_mtime, reverse=True)[:40]
    except OSError:
        return None, 0.0
    for p in files:
        try:
            lines = p.read_text(errors="ignore").splitlines()
        except OSError:
            continue
        for line in reversed(lines):
            if '"rate_limits":{' not in line.replace(" ", ""):
                continue
            try:
                rl = find_key(json.loads(line), "rate_limits") or {}
            except ValueError:
                continue
            return (rl.get("primary") or {}).get("used_percent"), p.stat().st_mtime
    return None, 0.0


def find_key(obj, key):
    if isinstance(obj, dict):
        if obj.get(key) is not None:
            return obj[key]
        for v in obj.values():
            f = find_key(v, key)
            if f is not None:
                return f
    elif isinstance(obj, list):
        for v in obj:
            f = find_key(v, key)
            if f is not None:
                return f
    return None


def agents_state() -> list[dict]:
    """Every agent in Run's order with whether it can run on a seat now, and why not (doctor --json 'agents')."""
    rows = []
    for a in ORDER:
        if a in SEAT_AGENTS:
            s = SEAT_AGENTS[a]
            b = find_bin(a)
            u = seat_usage(s["seat"])
            rows.append({"id": a, "name": s["name"], "seat": s["seat"], "installed": b is not None, "available": b is not None,
                         "why": None if b else f"{s['bin']} is not installed on this Mac",
                         "five_hour": u["five_hour"], "stale": u["stale"]})
        else:
            name, b, why = NOT_YET[a]
            rows.append({"id": a, "name": name, "seat": None, "installed": find_bin(a) is not None, "available": False,
                         "why": why, "five_hour": None, "stale": True})
    return rows


def share_per_case(agent: str) -> tuple:
    """(share of the five-hour window per case, 'measured' | 'guess') from this Mac's finished seat runs of this agent:
    the seat's five-hour use after the run minus before, over the cases answered (last 5 runs that moved it)."""
    per = []
    for f in sorted(RUNS.glob("*/run.json"), reverse=True) if RUNS.is_dir() else []:
        r = read_json(f, {})
        if r.get("runner") != "seat" or r.get("agent") != agent or r.get("status") != "done":
            continue
        a, b, n = r.get("seat_before"), r.get("seat_after"), r.get("cases_done") or 0
        if a is not None and b is not None and b > a and n:
            per.append((b - a) / 100 / n)
        if len(per) >= 5:
            break
    return (sum(per) / len(per), "measured") if per else (SHARE_GUESS, "guess")


def seat_estimate(agent: str, cases: int, epochs: int, limit: float | None = None) -> dict:
    s = SEAT_AGENTS[agent]
    per, basis = share_per_case(agent)
    u = seat_usage(s["seat"])
    share = per * cases * epochs
    lim = SEAT_LIMIT if limit is None else limit
    fits = u["five_hour"] is None or u["stale"] or u["five_hour"] + share * 100 <= lim
    return {"seat": s["seat"], "seat_share": round(share, 4), "seat_basis": basis, "seat_used": u["five_hour"],
            "seat_stale": u["stale"], "seat_limit": lim, "seat_fits": fits}


# ── one case ──────────────────────────────────────────────────────────────────────────────────────────────────────
def named(text: str) -> list[str]:
    """As the set's scorer: the paths named, in order (bullets, numbers and backticks ignored)."""
    out = []
    for line in (text or "").splitlines():
        m = PATH.search(line.replace("`", " "))
        if m and m.group(0).lstrip("./") not in out:
            out.append(m.group(0).lstrip("./"))
    return out


def score(answer: str, target: list[str]) -> tuple:
    names = named(answer)[:3]
    ranks = [i + 1 for i, n in enumerate(names) if any(f == n or f.endswith("/" + n) for f in target)]
    expl = (f"first right file at rank {ranks[0]}" if ranks else "no named file was changed by the fix") + \
        "; the fix changed: " + ", ".join(target)
    return (1.0 if ranks else 0.0), ", ".join(names) or "(no path)", expl


def question(case: dict) -> str:
    """The report only: the agent reads the repository itself (the set's file list is for models without one)."""
    return case["input"].split("\n\nSource files:\n", 1)[0]


def clean_env() -> dict:
    """The agent's own login only: API keys and tokens are removed, so a seat run never spends API credit."""
    return {k: v for k, v in strip_keys(dict(os.environ)).items() if k != "ONEROOF_EVALS_DIR"}


# Read is denied here for Claude Code even inside --restricted (belt and braces): the secrets and settings folders.
# Your own secrets folders go in <evals folder>/deny-read.txt (one path or glob per line, # for comments), kept on
# this Mac only, so the public app names none of them.
DENY_READ = ["~/.config/**", "~/.ssh/**", "~/Library/**", "~/.aws/**", "~/.gnupg/**",
             "~/.claude/**", "~/.claude-2/**", "~/.codex/**", "~/.netrc", "~/.docker/**", "~/.kube/**"]
CODEX_OFF = ["hooks", "plugins", "apps", "browser_use", "computer_use"]


def deny_read() -> list[str]:
    """DENY_READ plus the paths in <evals folder>/deny-read.txt (this Mac's own secrets folders)."""
    base = Path(os.environ.get("ONEROOF_EVALS_DIR") or Path.home() / "Library/Application Support/One Roof/evals")
    try:
        extra = [ln.strip() for ln in (base / "deny-read.txt").read_text().splitlines()]
    except OSError:
        extra = []
    return DENY_READ + [p for p in extra if p and not p.startswith("#") and p not in DENY_READ]


def claude_settings() -> str:
    """The per-run --settings JSON: no hooks at all, Read denied outside the case on the secrets folders, and no tool
    that writes, runs code or reaches the web."""
    return json.dumps({"disableAllHooks": True,
                       "permissions": {"deny": [f"Read({p})" for p in deny_read()]
                                       + ["Bash", "Edit", "Write", "MultiEdit", "NotebookEdit", "WebFetch", "WebSearch"]}})


def command(agent: str, binary: str, prompt: str, out_file: Path, folder: Path | None = None) -> list[str]:
    if agent == "claude_code":   # read-only tools in the case folder; edits, shell, web, hooks and MCP are refused
        return [binary, "-p", prompt, "--output-format", "text", "--restricted", "--settings", claude_settings(),
                "--strict-mcp-config", "--permission-mode", "default", "--permission-prompts", "none",
                "--no-session-persistence",
                "--allowedTools", "Read,Grep,Glob,LS", "--disallowedTools", "Bash,Edit,Write,MultiEdit,NotebookEdit,WebFetch,WebSearch"]
    off = [x for f in CODEX_OFF for x in ("--disable", f)]
    return [binary, "exec", "--sandbox", "read-only", "--skip-git-repo-check", "--ignore-user-config", "--ignore-rules",
            "--ephemeral", *off, *(["-C", str(folder)] if folder else []), "--output-last-message",
            str(out_file), prompt]


def kill_group(pid: int, sig) -> None:
    try:
        os.killpg(os.getpgid(pid), sig)
    except (ProcessLookupError, PermissionError, OSError):
        pass


def git(repo: str, *a: str) -> subprocess.CompletedProcess:
    return subprocess.run(["git", "-C", repo, *a], capture_output=True, text=True)


def make_worktree(repo: str | None, commit: str | None, where: Path) -> tuple:
    """(folder, how): a detached worktree at the commit before the fix, or an empty temp folder when there is none."""
    where.parent.mkdir(parents=True, exist_ok=True)
    if repo and commit and Path(repo, ".git").exists():
        if where.exists():   # left by a crash before a resume: never answer in a stale tree
            remove_worktree(repo, where, "worktree")
        r = git(repo, "worktree", "add", "--detach", str(where), f"{commit}^")
        if r.returncode == 0:
            return where, "worktree"
        raise RuntimeError(f"could not make a worktree at {commit}^: {(r.stderr.strip().splitlines() or ['git failed'])[-1][:200]}")
    return Path(tempfile.mkdtemp(prefix="oneroof-agent-case-", dir=str(where.parent))), "temp"


def remove_worktree(repo: str | None, folder: Path, how: str) -> None:
    if how == "worktree" and repo:
        git(repo, "worktree", "remove", "--force", str(folder))
        git(repo, "worktree", "prune")
    shutil.rmtree(folder, ignore_errors=True)


def sweep(repo: str | None = None) -> int:
    """Leftover case folders of runs that are no longer going (a crash, a killed worker): removed before a new run."""
    n = 0
    for d in sorted(WORKTREES.glob("*")) if WORKTREES.is_dir() else []:
        r = read_json(RUNS / d.name / "run.json", {})
        if r.get("status") in ("running", "waiting", "queued") and pid_alive(r.get("pid")):
            continue
        for case in d.glob("*"):
            remove_worktree(r.get("repo_path") or repo, case, "worktree")
            n += 1
        shutil.rmtree(d, ignore_errors=True)
    if repo:
        git(repo, "worktree", "prune")
    return n


def pid_alive(pid) -> bool:
    if not pid:
        return False
    try:
        os.kill(pid, 0)
        return True
    except (ProcessLookupError, PermissionError):
        return False


def answer_case(r: dict, d: Path, case: dict, epoch: int, kind: str) -> dict:
    binary = find_bin(r["agent"])
    started = time.time()
    row = {"id": case["id"], "epoch": epoch, "target": "\n".join(case["target"]), "input": question(case)[:400]}
    try:
        folder, how = make_worktree(r.get("repo_path"), (case.get("meta") or {}).get("commit"),
                                    WORKTREES / r["id"] / f"{case['id']}-e{epoch}")
    except RuntimeError as e:
        row.update(score=0.0, answer="(no answer)", output="", explanation="", error=str(e)[:400], time=0.0)
        return row
    row.update(where=how, worktree_commit=((case.get("meta") or {}).get("commit") or "") + "^" if how == "worktree" else None)
    try:
        if not binary:
            raise RuntimeError(f"{SEAT_AGENTS[r['agent']]['bin']} is not installed on this Mac")
        out_file = folder.parent / f"{case['id']}-e{epoch}.last.txt"
        prompt = SYSTEM.get(kind, SYSTEM["fix-locator"]) + "\n\n" + question(case)
        p = subprocess.Popen(command(r["agent"], binary, prompt, out_file, folder), cwd=str(folder), env=clean_env(),
                             stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, stdin=subprocess.DEVNULL,
                             start_new_session=True)   # its own process group: a timeout or cancel stops its children too
        set_status(d, child=p.pid, child_group=True)
        try:
            so, se = p.communicate(timeout=CASE_TIMEOUT)
        except subprocess.TimeoutExpired:
            kill_group(p.pid, signal.SIGKILL)
            so, se = p.communicate()
            raise RuntimeError(f"no answer within {CASE_TIMEOUT // 60} minutes")
        finally:
            set_status(d, child=None)
        text = out_file.read_text() if out_file.exists() else so
        out_file.unlink(missing_ok=True)
        if p.returncode != 0 and not text.strip():
            raise RuntimeError((se.strip().splitlines() or [f"{binary} exited {p.returncode}"])[-1][:300])
        value, ans, expl = score(text, case["target"])
        row.update(score=value, answer=ans, output=text.strip()[:4000], explanation=expl)
    except Exception as e:   # one case's failure is that case's answer, never the run's end
        row.update(score=0.0, answer="(no answer)", output="", explanation="", error=str(e)[:400])
    finally:
        remove_worktree(r.get("repo_path"), folder, how)
    row["time"] = round(time.time() - started, 1)
    return row


# ── the run ───────────────────────────────────────────────────────────────────────────────────────────────────────
UNKNOWN_WAIT = "seat use unknown"


def seat_gate(u: dict, lim: float, run_anyway: bool) -> str | None:
    """None when a case may start; otherwise why the run waits. Unknown or stale use never passes silently: only known
    use under the limit, or the owner's Run anyway on this run, lets a case start."""
    if u["five_hour"] is None or u["stale"]:
        if run_anyway:
            return None
        return (f"{UNKNOWN_WAIT}: One Roof cannot see how much of {u['seat']}'s 5-hour window is used, so it waits until "
                f"it can (under {lim:.0f} %), or press Run anyway")
    if u["five_hour"] >= lim:
        return f"waiting for seat {u['seat']}: {u['five_hour']:.0f} % of its 5-hour window used (limit {lim:.0f} %)"
    return None


def wait_for_seat(r: dict, d: Path) -> bool:
    """Pause (status 'waiting') while the seat is at or over its limit, or its use is unknown and the owner has not pressed
    Run anyway; False when the run was cancelled meanwhile. Checked before each case (between cases, never mid-case)."""
    lim = float(r.get("seat_limit") or SEAT_LIMIT)
    while True:
        if (d / "CANCEL").exists():
            return False
        why = seat_gate(seat_usage(r["seat"]), lim, bool(read_json(d / "run.json", {}).get("seat_unknown_ok")))
        if why is None:
            if read_json(d / "run.json", {}).get("status") == "waiting":
                set_status(d, status="running", waiting=None)
            return True
        set_status(d, status="waiting", waiting=why)
        time.sleep(SEAT_POLL)


def run_anyway(d: Path) -> dict:
    """The owner's explicit Run anyway for one run whose seat use is unknown: recorded in its plan (run.json)."""
    return set_status(d, seat_unknown_ok=True, seat_unknown_ok_at=now())


def seat_lock(seat: str, d: Path):
    """One run per seat at a time (a second waits in the queue)."""
    (EVALS / "slots").mkdir(parents=True, exist_ok=True)
    f = open(EVALS / "slots" / f"seat-{seat}.lock", "w")
    while True:
        if (d / "CANCEL").exists():
            f.close()
            return None
        try:
            fcntl.flock(f, fcntl.LOCK_EX | fcntl.LOCK_NB)
            return f
        except OSError:
            time.sleep(2)


def load_set(task_ref: str) -> tuple:
    folder = Path(task_ref).parent
    meta = read_json(folder / "set.json", {}) or {}
    cases = [json.loads(x) for x in (folder / "cases.jsonl").read_text().splitlines() if x.strip()]
    return meta, cases


def answers_of(d: Path) -> list[dict]:
    p = d / "answers.jsonl"
    rows = []
    for line in p.read_text().splitlines() if p.exists() else []:
        try:
            rows.append(json.loads(line))
        except ValueError:
            continue
    return rows


def work(rid: str) -> int:
    """Answer every case × attempt not yet answered (a resume skips the done ones), then write the summary the index reads."""
    d = RUNS / rid
    r = set_status(d, status="running", started=read_json(d / "run.json", {}).get("started") or now(), pid=os.getpid())
    sweep(r.get("repo_path"))
    lock = seat_lock(r["seat"], d)
    if lock is None:
        set_status(d, status="cancelled", finished=now())
        return 1
    try:
        meta, cases = load_set(r["task_ref"])
        if r.get("sample_id"):
            want = set(r["sample_id"].split(","))
            cases = [c for c in cases if c["id"] in want]
        cases = cases[: r.get("limit") or len(cases)]
        epochs = r.get("epochs") or 1
        done = {(a["id"], a["epoch"]) for a in answers_of(d)}
        if r.get("seat_before") is None:
            r = set_status(d, seat_before=seat_usage(r["seat"])["five_hour"])
        for epoch in range(1, epochs + 1):
            for c in cases:
                if (c["id"], epoch) in done:
                    continue
                if not wait_for_seat(r, d):
                    raise KeyboardInterrupt
                row = answer_case(r, d, c, epoch, meta.get("kind") or "fix-locator")
                if (d / "CANCEL").exists():   # stopped mid-case: that case is asked again on resume, never kept as a 0
                    raise KeyboardInterrupt
                with open(d / "answers.jsonl", "a") as f:
                    f.write(json.dumps(row) + "\n")
        rows = answers_of(d)
        vals = [a["score"] for a in rows]
        acc = sum(vals) / len(vals) if vals else 0.0
        se = (sum((v - acc) ** 2 for v in vals) / (len(vals) - 1) / len(vals)) ** 0.5 if len(vals) > 1 else 0.0
        errors = [a for a in rows if a.get("error")]
        fin = now()
        summary = {"status": "success" if rows and len(errors) < len(rows) else "error", "samples_done": len(rows),
                   "samples_total": len(cases) * epochs, "started": r.get("started"), "finished": fin,
                   "input_tokens": None, "output_tokens": None, "cost": 0.0, "sample_seconds": sum(a.get("time") or 0 for a in rows),
                   "scores": [{"scorer": "fix_located", "metrics": {"accuracy": acc, "stderr": se}}],
                   "samples": [[a["id"], a["epoch"], a["score"]] for a in rows],
                   "error": errors[-1]["error"] if errors and len(errors) == len(rows) else None}
        ok = summary["status"] == "success"
        set_status(d, status="done" if ok else "failed", finished=fin, summary=summary, cases_done=len(rows),
                   seat_after=seat_usage(r["seat"])["five_hour"], error=None if ok else summary["error"], child=None)
        return 0 if ok else 1
    except KeyboardInterrupt:
        set_status(d, status="cancelled", finished=now(), child=None)
        return 1
    except Exception as e:
        set_status(d, status="failed", finished=now(), error=str(e)[:2000], child=None)
        return 1
    finally:
        lock.close()
        shutil.rmtree(WORKTREES / rid, ignore_errors=True)


if __name__ == "__main__":
    if sys.argv[1:2] == ["agents"]:
        print(json.dumps(agents_state(), indent=2))
    elif sys.argv[1:2] == ["sweep"]:
        print(json.dumps({"removed": sweep(sys.argv[2] if len(sys.argv) > 2 else None)}))
    else:
        print(__doc__)
