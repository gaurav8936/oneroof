#!/usr/bin/env python3
"""What changed that could move a score (EV-6): your rules and skills, and the agents themselves. Standard library only.

  python3 changes.py [--repo PATH …] [--days 60] [--json]        (also: roof eval changes …)

"you"    = git history of the files an agent reads as instructions or skills, in each repo: CLAUDE.md and AGENTS.md
           (any folder), .claude/skills/**, skills/**, .claude/settings*.json. One row per file (per skill) per commit.
"vendor" = the agent changed under you: the CLI version or the model its default resolved to, between consecutive
           recorded run stamps of that agent (run.json "stamp", recorded: true), and the CLI versions `roof eval doctor`
           saw (<evals folder>/agents-seen.json).
Each row says which finished agent run came last before it and first after it ("tested"), so a re-test can be offered.
Real data only: an empty list is a valid answer. No repo is changed; nothing is sent anywhere.
"""
from __future__ import annotations

import json
import os
import re
import subprocess
import sys
from datetime import datetime, timedelta, timezone
from pathlib import Path

sys.dont_write_bytecode = True   # LAB-2219
os.environ["PYTHONDONTWRITEBYTECODE"] = "1"

EVALS = Path(os.environ.get("ONEROOF_EVALS_DIR") or Path.home() / "Library/Application Support/One Roof/evals")
RUNS = EVALS / "runs"
SEEN = EVALS / "agents-seen.json"
NAMES = {"claude_code": "Claude Code", "codex_cli": "Codex"}
# git pathspecs of the files an agent reads by itself
PATHSPECS = [":(glob)**/CLAUDE.md", ":(glob)**/AGENTS.md", ":(glob).claude/skills/**", ":(glob)skills/**",
             ":(glob).claude/settings*.json"]
SKILL = re.compile(r"^(?:\.claude/)?skills/([^/]+)/")
SEP = "\x1f"


def read_json(p: Path, default=None):
    try:
        return json.loads(Path(p).read_text())
    except (OSError, ValueError):
        return default


def iso(dt: datetime) -> str:
    return dt.astimezone(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def git(repo: str, *a: str) -> str:
    r = subprocess.run(["git", "-C", repo, *a], capture_output=True, text=True, errors="replace")
    return r.stdout if r.returncode == 0 else ""


def your_changes(repo: str, since: datetime) -> list[dict]:
    """One row per rules file, settings file or skill touched by a commit in the window, newest first."""
    out = git(repo, "log", f"--since={since.isoformat()}", "--no-merges", "--name-status", "--no-renames",
              f"--format=@@{SEP}%h{SEP}%cI", "--", *PATHSPECS)
    rows, commit, at = [], None, None
    skills: dict = {}

    def flush():
        for name, sts in skills.items():
            what = ("Skill added: " if set(sts) == {"A"} else "Skill removed: " if set(sts) == {"D"} else "Skill changed: ") + name
            rows.append({"at": at, "who": "you", "what": what, "path": None, "commit": commit, "_skill_path": name})
        skills.clear()

    for line in out.splitlines():
        if line.startswith("@@" + SEP):
            flush()
            _, commit, when = line.split(SEP)[:3]
            try:
                at = iso(datetime.fromisoformat(when))
            except ValueError:
                at = when
            commit = commit[:7]
            continue
        if not line.strip() or commit is None:
            continue
        st, _, path = line.partition("\t")
        st = st[:1]
        m = SKILL.match(path)
        if m:
            skills.setdefault(m.group(1), []).append(st)
            continue
        verb = {"A": "added", "D": "removed"}.get(st, "changed")
        rows.append({"at": at, "who": "you", "what": f"{path} {verb}", "path": path, "commit": commit})
    flush()
    for r in rows:   # a skill row points at its folder
        name = r.pop("_skill_path", None)
        if name:
            r["path"] = next((p for p in (f".claude/skills/{name}", f"skills/{name}") if Path(repo, p).exists()),
                             f"skills/{name}")
    return rows


def stamped_runs() -> list[dict]:
    """Every run with a recorded stamp, oldest first: id, agent, started, status, stamp, repo."""
    out = []
    for f in sorted(RUNS.glob("*/run.json")) if RUNS.is_dir() else []:
        r = read_json(f, {}) or {}
        st = r.get("stamp")
        if not isinstance(st, dict) or st.get("recorded") is False:
            continue
        out.append({"id": r.get("id"), "agent": r.get("agent"), "started": r.get("started") or r.get("created") or "",
                    "status": r.get("status"), "stamp": st, "repo": r.get("repo_path")})
    out.sort(key=lambda x: x["started"])
    return out


def all_agent_runs() -> list[dict]:
    """Finished agent runs (recorded or not), oldest first: the candidates for "tested"."""
    out = []
    for f in sorted(RUNS.glob("*/run.json")) if RUNS.is_dir() else []:
        r = read_json(f, {}) or {}
        if r.get("status") == "done" and r.get("agent"):
            out.append({"id": r.get("id"), "agent": r.get("agent"), "started": r.get("started") or r.get("created") or "",
                        "repo": r.get("repo_path")})
    out.sort(key=lambda x: x["started"])
    return out


def vendor_changes(since: datetime) -> list[dict]:
    rows, seen_pairs = [], set()
    by_agent: dict = {}
    for r in stamped_runs():
        if r["agent"]:
            by_agent.setdefault(r["agent"], []).append(r)
    for agent, rs in by_agent.items():
        name = NAMES.get(agent, agent)
        prev_v = prev_m = None
        for r in rs:
            st = r["stamp"]
            v = st.get("agent_version")
            if v and prev_v and v != prev_v[0]:
                rows.append({"at": r["started"], "who": "vendor", "what": f"{name} {prev_v[0]} → {v}", "path": None,
                             "commit": None, "_agent": agent, "_before": prev_v[1], "_after": r["id"]})
                seen_pairs.add((agent, prev_v[0], v))
            if v:
                prev_v = (v, r["id"])
            m = st.get("model") if st.get("model_source") == "cli_default_resolved" else None
            if m and prev_m and m != prev_m[0]:
                rows.append({"at": r["started"], "who": "vendor", "what": f"{name}'s default model: {prev_m[0]} → {m}",
                             "path": None, "commit": None, "_agent": agent, "_before": prev_m[1], "_after": r["id"]})
            if m:
                prev_m = (m, r["id"])
    for agent, hist in (read_json(SEEN, {}) or {}).items():
        name = NAMES.get(agent, agent)
        for a, b in zip(hist, hist[1:]):
            if a.get("version") and b.get("version") and a["version"] != b["version"] \
                    and (agent, a["version"], b["version"]) not in seen_pairs:
                rows.append({"at": b.get("at"), "who": "vendor", "what": f"{name} {a['version']} → {b['version']}",
                             "path": None, "commit": None, "_agent": agent})
                seen_pairs.add((agent, a["version"], b["version"]))
    cut = iso(since)
    return [r for r in rows if (r.get("at") or "") >= cut]


def same_repo(a: str | None, b: str | None) -> bool:
    try:
        return bool(a and b) and Path(a).resolve() == Path(b).resolve()
    except OSError:
        return False


def tested(row: dict, runs: list[dict], repo: str | None) -> dict:
    if "_before" in row or "_after" in row:
        return {"before": row.get("_before"), "after": row.get("_after")}
    pool = [r for r in runs if r["agent"] == row["_agent"]] if row.get("_agent") else \
        [r for r in runs if same_repo(r["repo"], repo)]
    at = row.get("at") or ""
    before = [r["id"] for r in pool if r["started"] < at]
    after = [r["id"] for r in pool if r["started"] >= at]
    return {"before": before[-1] if before else None, "after": after[0] if after else None}


def default_repos() -> list[str]:
    """The repos your eval sets were built from (when --repo is not given)."""
    out = []
    for f in sorted((EVALS / "sets").glob("*/v*/set.json")) if (EVALS / "sets").is_dir() else []:
        p = (read_json(f, {}) or {}).get("repo_path")
        if p and Path(p, ".git").exists() and p not in out:
            out.append(p)
    return out


def changes(repos: list[str], days: int) -> list[dict]:
    since = datetime.now(timezone.utc) - timedelta(days=days)
    runs = all_agent_runs()
    rows = []
    for repo in repos:
        for r in your_changes(repo, since):
            r["tested"] = tested(r, runs, repo)
            rows.append(r)
    for r in vendor_changes(since):
        r["tested"] = tested(r, runs, None)
        rows.append(r)
    for r in rows:
        for k in [k for k in r if k.startswith("_")]:
            r.pop(k)
    rows.sort(key=lambda r: (r.get("at") or "", r.get("what") or ""), reverse=True)
    return rows


def main(argv: list[str]) -> int:
    repos, days, as_json, i = [], 60, False, 0
    while i < len(argv):
        a = argv[i]
        if a == "--repo" and i + 1 < len(argv):
            repos.append(os.path.expanduser(argv[i + 1]))
            i += 1
        elif a == "--days" and i + 1 < len(argv):
            days = int(argv[i + 1])
            i += 1
        elif a == "--json":
            as_json = True
        elif a in ("-h", "--help"):
            print(__doc__)
            return 0
        else:
            msg = f"unknown option {a}"
            print(json.dumps({"error": msg, "code": 2}) if as_json else f"roof eval changes: {msg}")
            return 2
        i += 1
    for r in repos:
        if not Path(r, ".git").exists():
            msg = f"not a git repository: {r}"
            print(json.dumps({"error": msg, "code": 2}) if as_json else f"roof eval changes: {msg}")
            return 2
    rows = changes(repos or default_repos(), days)
    if as_json:
        print(json.dumps(rows, indent=2, sort_keys=True))
    else:
        print("\n".join(f"{r['at']}  {r['who']:<6} {r['what']}" + (f"  ({r['commit']})" if r.get("commit") else "")
                        for r in rows) or f"no changes in the last {days} days")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
