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

# LAB-2219: the engine never writes bytecode next to itself (inside the signed app bundle), nor do its children.
sys.dont_write_bytecode = True
os.environ["PYTHONDONTWRITEBYTECODE"] = "1"

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
# LAB-2237: a run waiting because the seat's use is unknown gives up after this many hours (status "expired").
EXPIRE_HOURS = float(os.environ.get("ONEROOF_SEAT_EXPIRE_HOURS") or 6)
# EV-1 (LAB-2240): the instruction files an agent reads by itself. Rules "off" removes them from the case worktree;
# rules "on" puts the repo HEAD's copies there (not the pre-fix commit's).
RULE_NAMES = ("CLAUDE.md", "AGENTS.md", "CLAUDE.local.md")
VERSION = re.compile(r"\d+(?:\.\d+)+")

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
    env = {k: v for k, v in strip_keys(dict(os.environ)).items() if k not in ("ONEROOF_EVALS_DIR", "ONEROOF_AGENT")}
    env["PYTHONDONTWRITEBYTECODE"] = "1"
    return env


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


def command(agent: str, binary: str, prompt: str, out_file: Path, folder: Path | None = None, model: str | None = None,
            rules: str = "off") -> list[str]:
    """The agent CLI's argv. --model is passed to the CLI as chosen (claude --model, codex -m); none = the CLI's default.
    The output is the CLI's machine-readable one (claude --output-format json, codex exec --json), so the model that
    answered can be read back. Rules "on" keeps the same read-only containment; Codex then loads its rules files."""
    if agent == "claude_code":   # read-only tools in the case folder; edits, shell, web, hooks and MCP are refused
        return [binary, "-p", prompt, "--output-format", "json", *(["--model", model] if model else []),
                "--restricted", "--settings", claude_settings(),
                "--strict-mcp-config", "--permission-mode", "default", "--permission-prompts", "none",
                "--no-session-persistence",
                "--allowedTools", "Read,Grep,Glob,LS", "--disallowedTools", "Bash,Edit,Write,MultiEdit,NotebookEdit,WebFetch,WebSearch"]
    off = [x for f in CODEX_OFF for x in ("--disable", f)]
    return [binary, "exec", "--sandbox", "read-only", "--skip-git-repo-check", "--ignore-user-config",
            *([] if rules == "on" else ["--ignore-rules"]), "--ephemeral", *off, "--json", *(["-m", model] if model else []),
            *(["-C", str(folder)] if folder else []), "--output-last-message", str(out_file), prompt]


def parse_output(agent: str, stdout: str, last: str | None) -> tuple:
    """(answer text, model that answered or None) from the CLI's own output. Claude Code's json result lists the
    models it used (modelUsage; the one with the most output is the one that answered, side calls use a small model);
    Codex's JSONL events are searched for a model name. Plain text (an older CLI, a fake) is the answer as it is."""
    text, model = (last if last is not None else None), None
    raw = (stdout or "").strip()
    if agent == "claude_code":
        try:
            j = json.loads(raw)
        except ValueError:
            j = None
        if isinstance(j, dict):
            mu = j.get("modelUsage") or {}
            if isinstance(mu, dict) and mu:
                def out_tokens(v):
                    return (v or {}).get("outputTokens") or 0 if isinstance(v, dict) else 0
                model = max(mu, key=lambda k: (out_tokens(mu[k]), k))
            if text is None:
                text = j.get("result") if isinstance(j.get("result"), str) else ""
        elif text is None:
            text = stdout or ""
        return text, model
    events = []
    for line in raw.splitlines():
        try:
            ev = json.loads(line)
        except ValueError:
            continue
        if isinstance(ev, dict):
            events.append(ev)
    for ev in events:
        m = find_key(ev, "model")
        if isinstance(m, str) and m.strip():
            model = m.strip()
    if text is None:
        msgs = [find_key(ev, "text") for ev in events if "agent_message" in json.dumps(ev)]
        msgs = [m for m in msgs if isinstance(m, str)]
        text = msgs[-1] if msgs else ("" if events else (stdout or ""))
    return text, model


def agent_version(binary: str | None) -> str | None:
    """`<bin> --version`, first line: the version number in it ("2.1.31 (Claude Code)" → "2.1.31"), else the line."""
    if not binary:
        return None
    try:
        r = subprocess.run([binary, "--version"], capture_output=True, text=True, timeout=30, stdin=subprocess.DEVNULL,
                           env=clean_env())
    except (OSError, subprocess.SubprocessError):
        return None
    line = next((x.strip() for x in (r.stdout or r.stderr or "").splitlines() if x.strip()), "")
    if not line:
        return None
    m = VERSION.search(line)
    return m.group(0) if m else line[:80]


# ── rules on / off (EV-1) ─────────────────────────────────────────────────────────────────────────────────────────
def rule_files_at_head(repo: str | None) -> list[str]:
    """The instruction files tracked at the repo's HEAD (any folder), sorted."""
    if not repo or not Path(repo, ".git").exists():
        return []
    r = git(repo, "ls-tree", "-r", "--name-only", "HEAD")
    return sorted(p for p in r.stdout.splitlines() if p.rsplit("/", 1)[-1] in RULE_NAMES) if r.returncode == 0 else []


def capture_rules(repo: str | None, d: Path) -> dict:
    """Rules "on": the HEAD's instruction files copied into <run>/rules (so every case gets the same bytes, even if
    HEAD moves during the run). Returns the stamp's rules_hash (first 7 hex of sha256 over their bytes, in path order),
    rules_commit and rules_files."""
    import hashlib
    files, h = [], hashlib.sha256()
    commit = None
    if repo and Path(repo, ".git").exists():
        c = git(repo, "rev-parse", "--short=7", "HEAD")
        commit = c.stdout.strip() or None if c.returncode == 0 else None
        for path in rule_files_at_head(repo):
            b = subprocess.run(["git", "-C", repo, "show", f"HEAD:{path}"], capture_output=True)
            if b.returncode != 0:
                continue
            (d / "rules").mkdir(parents=True, exist_ok=True)
            safe_write(d / "rules", path, b.stdout)
            h.update(b.stdout)
            files.append(path)
    return {"rules_hash": h.hexdigest()[:7] if files else None, "rules_commit": commit, "rules_files": files}


class UnsafePath(RuntimeError):
    """A rules path that goes through a symlink, leaves the case folder, or is not a plain name."""


def _dir_fd(root: Path, parts: list[str], create: bool) -> int:
    """An fd for root/parts..., opened one component at a time with O_NOFOLLOW (review P1): a symlink anywhere on the
    way (the root included) is refused, never followed, so nothing outside the case folder can be reached by a path that
    looks like it is inside. Missing folders are made (create) one level at a time, again without following."""
    flags = os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW
    try:
        fd = os.open(str(root), flags)
    except OSError as e:
        raise UnsafePath(f"{root} is not a plain folder ({e.strerror})")
    try:
        for part in parts:
            if part in ("", ".", "..") or "/" in part:
                raise UnsafePath(f"bad path component {part!r}")
            try:
                nfd = os.open(part, flags, dir_fd=fd)
            except FileNotFoundError:
                if not create:
                    raise
                os.mkdir(part, 0o755, dir_fd=fd)
                nfd = os.open(part, flags, dir_fd=fd)
            except OSError as e:   # ELOOP (a symlink) or ENOTDIR (a file): refused
                raise UnsafePath(f"{part} is a symlink or not a folder ({e.strerror})")
            os.close(fd)
            fd = nfd
        return fd
    except BaseException:
        os.close(fd)
        raise


def safe_write(root: Path, rel: str, data: bytes) -> Path:
    """Write `data` at root/rel without following any symlink: every folder on the way is opened no-follow (a symlinked
    one is refused), a symlink or file already at the destination is unlinked (the link itself, never its target), and the
    file is created O_EXCL | O_NOFOLLOW. The resolved destination is checked to stay inside root."""
    parts = Path(rel).parts
    if not parts or Path(rel).is_absolute():
        raise UnsafePath(f"bad rules path {rel!r}")
    fd = _dir_fd(root, list(parts[:-1]), create=True)
    try:
        name = parts[-1]
        if name in ("", ".", ".."):
            raise UnsafePath(f"bad rules path {rel!r}")
        try:
            st = os.stat(name, dir_fd=fd, follow_symlinks=False)
        except FileNotFoundError:
            st = None
        if st is not None:
            import stat as _stat
            if _stat.S_ISDIR(st.st_mode):
                raise UnsafePath(f"{rel} is a folder")
            os.unlink(name, dir_fd=fd)
        out = os.open(name, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o644, dir_fd=fd)
        with os.fdopen(out, "wb") as f:
            f.write(data)
    finally:
        os.close(fd)
    dest = root / rel
    real_root = os.path.realpath(root)
    if os.path.commonpath([real_root, os.path.realpath(dest)]) != real_root:   # belt and braces
        raise UnsafePath(f"{rel} resolves outside {root}")
    return dest


def remove_rule_files(folder: Path) -> None:
    """Rules off: every instruction file in the case folder is removed. The walk never follows a symlinked folder (so a
    folder that links outside the case is never entered), and a rules file that is a symlink is unlinked itself, never
    its target. .git is skipped."""
    if folder.is_symlink() or not folder.is_dir():
        return
    for top, dirs, files in os.walk(folder, followlinks=False):
        dirs[:] = [x for x in dirs if x != ".git" and not os.path.islink(os.path.join(top, x))]
        rel = os.path.relpath(top, folder)
        names = [x for x in files if x in RULE_NAMES]
        if not names:
            continue
        fd = _dir_fd(folder, [] if rel == "." else rel.split(os.sep), create=False)
        try:
            for x in names:
                try:
                    os.unlink(x, dir_fd=fd)
                except FileNotFoundError:
                    pass
        finally:
            os.close(fd)
    # a symlinked folder or file named like a rules file (not walked into): the link itself goes
    for top, dirs, _ in os.walk(folder, followlinks=False):
        dirs[:] = [x for x in dirs if x != ".git"]
        for x in dirs:
            p = os.path.join(top, x)
            if x in RULE_NAMES and os.path.islink(p):
                os.unlink(p)


def prepare_rules(folder: Path, d: Path, rules: str) -> list[str]:
    """Rules off: every instruction file is removed from the case worktree, so the agent reads none. Rules on: the
    same, then the run's captured HEAD copies are put in, never through a symlink (review P1: a pre-fix commit can have
    a folder that is a symlink to somewhere outside the case; that copy is refused and the case says why). Returns the
    files the agent can read."""
    remove_rule_files(folder)
    given = []
    src_root = d / "rules"
    if rules == "on" and src_root.is_dir() and not src_root.is_symlink():
        for top, dirs, files in os.walk(src_root, followlinks=False):
            dirs[:] = sorted(x for x in dirs if not os.path.islink(os.path.join(top, x)))
            for name in sorted(files):
                src = Path(top) / name
                if src.is_symlink() or not src.is_file():
                    continue
                rel = str(src.relative_to(src_root))
                try:
                    safe_write(folder, rel, src.read_bytes())
                except UnsafePath as e:
                    raise RuntimeError(f"rules file {rel} not copied: {e}")
                given.append(rel)
    return sorted(given)


CHILD_GRACE = float(os.environ.get("ONEROOF_CHILD_GRACE") or 3)


def stop_child(p: subprocess.Popen, grace: float | None = None) -> None:
    """Stop an agent CLI started with start_new_session (it leads its own group, pgid = pid) and reap it: SIGTERM to the
    group, SIGKILL to the group after `grace` seconds if the leader is still there, then SIGKILL again for anything left in
    the group (a grandchild that outlived the leader), and wait. Returns only when the leader is reaped."""
    grace = CHILD_GRACE if grace is None else grace
    def group(sig):
        try:
            os.killpg(p.pid, sig)
        except (ProcessLookupError, PermissionError, OSError):
            pass
    if p.poll() is None:
        group(signal.SIGTERM)
        try:
            p.wait(timeout=grace)
        except subprocess.TimeoutExpired:
            pass
    group(signal.SIGKILL)
    while True:
        try:
            p.wait()
            return
        except KeyboardInterrupt:   # a second stop while reaping: finish reaping first
            continue


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
        rules = r.get("rules") or "off"
        if how == "worktree" or rules == "on":
            row["rules_files"] = prepare_rules(folder, d, rules)
        prompt = SYSTEM.get(kind, SYSTEM["fix-locator"]) + "\n\n" + question(case)
        # Review P1 (cancel): a cancel that lands while the child is being started is held until its pid is known (and
        # recorded), then acted on; whatever happens next, the finally stops the child's whole group (SIGTERM, SIGKILL
        # after CHILD_GRACE) and reaps it BEFORE the record is cleared, the worktree removed or the seat lock released.
        p = None
        try:
            with _held_stop():
                p = subprocess.Popen(command(r["agent"], binary, prompt, out_file, folder, r.get("model_requested"), rules),
                                     cwd=str(folder), env=clean_env(),
                                     stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, stdin=subprocess.DEVNULL,
                                     start_new_session=True)   # its own process group: a timeout or cancel stops its children too
                set_status(d, child=p.pid, child_group=True)
            so, se = p.communicate(timeout=CASE_TIMEOUT)
        except subprocess.TimeoutExpired:
            stop_child(p)
            so, se = p.communicate()
            raise RuntimeError(f"no answer within {CASE_TIMEOUT // 60} minutes")
        finally:
            if p is not None:
                stop_child(p)
            set_status(d, child=None)
        text, seen = parse_output(r["agent"], so, out_file.read_text() if out_file.exists() else None)
        out_file.unlink(missing_ok=True)
        if seen:
            row["model_seen"] = seen
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


def final_stamp(r: dict, rows: list[dict]) -> dict | None:
    """The stamp once the run is answered: the model that answered, as the CLI itself reported it (the most common one
    over the cases). Chosen = the --model asked for; otherwise the CLI default, resolved when the CLI said which."""
    st = dict(r.get("stamp") or {})
    if not st:
        return None
    seen = [a["model_seen"] for a in rows if a.get("model_seen")]
    resolved = max(set(seen), key=lambda m: (seen.count(m), m)) if seen else None
    if st.get("model_requested"):
        st["model"], st["model_source"] = resolved or st["model_requested"], "chosen"
    else:
        st["model"], st["model_source"] = resolved, "cli_default_resolved" if resolved else "cli_default_unknown"
    given = sorted({f for a in rows for f in a.get("rules_files") or []})
    if st.get("rules") == "on" and given:
        st["rules_files"] = given
    return st


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


def wait_for_seat(r: dict, d: Path):
    """Pause (status 'waiting') while the seat is at or over its limit, or its use is unknown and the owner has not pressed
    Run anyway. True = a case may start; False = the run was cancelled meanwhile; "expired" = it waited with the seat's
    use unknown for EXPIRE_HOURS (LAB-2237): the run ends with status "expired" and says why. Checked before each case
    (between cases, never mid-case)."""
    lim = float(r.get("seat_limit") or SEAT_LIMIT)
    while True:
        if (d / "CANCEL").exists():
            return False
        cur = read_json(d / "run.json", {})
        why = seat_gate(seat_usage(r["seat"]), lim, bool(cur.get("seat_unknown_ok")))
        if why is None:
            if cur.get("status") == "waiting" or cur.get("waiting_since"):
                set_status(d, status="running", waiting=None, waiting_since=None)
            return True
        since = cur.get("waiting_since") if why.startswith(UNKNOWN_WAIT) else None
        if why.startswith(UNKNOWN_WAIT) and not since:
            since = now()
        if since and hours_since(since) >= EXPIRE_HOURS:
            reason = (f"expired: waited {EXPIRE_HOURS:g} h without knowing how much of {r['seat']}'s 5-hour window is used; "
                      "start it again, or press Run anyway next time")
            set_status(d, status="expired", waiting=None, expired_reason=reason, finished=now(), child=None)
            return "expired"
        set_status(d, status="waiting", waiting=why, waiting_since=since)
        time.sleep(SEAT_POLL)


def hours_since(iso: str) -> float:
    try:
        t = datetime.strptime(iso, "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=timezone.utc)
    except (TypeError, ValueError):
        return 0.0
    return (datetime.now(timezone.utc) - t).total_seconds() / 3600


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


_STOP = {"held": 0, "pending": False, "raised": False}


def _stop(*_):
    """SIGTERM (a cancel): stop like Ctrl-C, once. While a child is being started (held), the stop waits until its pid is
    recorded, so the cleanup always knows which child to stop. A second SIGTERM while cleaning up is ignored (the cancel's
    SIGKILL deadline is the backstop)."""
    if _STOP["raised"]:
        return
    if _STOP["held"]:
        _STOP["pending"] = True
        return
    _STOP["raised"] = True
    raise KeyboardInterrupt


class _held_stop:
    def __enter__(self):
        _STOP["held"] += 1

    def __exit__(self, *exc):
        _STOP["held"] -= 1
        if not _STOP["held"] and _STOP["pending"] and exc[0] is None:
            _STOP["pending"] = False
            _STOP["raised"] = True
            raise KeyboardInterrupt
        return False


def work(rid: str) -> int:
    """Answer every case × attempt not yet answered (a resume skips the done ones), then write the summary the index reads."""
    d = RUNS / rid
    # LAB-2237: cancel sends SIGTERM to this worker's process group; stop like a cancel, so the finally below removes
    # the case worktrees and frees the seat.
    _STOP.update(held=0, pending=False, raised=False)
    try:
        signal.signal(signal.SIGTERM, _stop)
    except ValueError:   # not the main thread (tests): cancel still works through the CANCEL file
        pass
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
                gate = wait_for_seat(r, d)
                if gate == "expired":
                    return 1
                if not gate:
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
                   seat_after=seat_usage(r["seat"])["five_hour"], error=None if ok else summary["error"], child=None,
                   stamp=final_stamp(read_json(d / "run.json", {}), rows))
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
