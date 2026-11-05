#!/usr/bin/env python3
"""What changed that could move a score (EV-6): your rules and skills, and the agents themselves. Standard library only.

  python3 changes.py [--repo PATH …] [--days 60] [--json]        (also: roof eval changes …)

"you"    = git history of the files an agent reads as instructions or skills, in each repo: CLAUDE.md and AGENTS.md
           (any folder), .claude/skills/**, skills/**, .claude/settings*.json. One row per file (per skill) per commit.
"vendor" = the agent changed under you: the CLI version or the model its default resolved to, between consecutive
           recorded run stamps of that agent (run.json "stamp", recorded: true), and the CLI versions `roof eval doctor`
           saw (<evals folder>/agents-seen.json).
Each row says which finished agent runs test it ("tested"): the latest before and earliest after that are COMPARABLE
(recorded stamps, same task + version, agent, CLI version, models and rules mode, all known, differing only in what
changed; a rules commit only when the runs' rules hashes are the states just before and just after it, and several rules
commits between the two runs are returned as one pair with "spans", credited to none); with no such pair, "after" is null (and "before" the run to repeat, if one is eligible): "no comparable before/after tests".
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
    """Finished agent runs with a recorded stamp, oldest first: the only candidates for "tested" (review P1 #3: a run
    without a recorded stamp cannot be shown to match anything)."""
    out = []
    for f in sorted(RUNS.glob("*/run.json")) if RUNS.is_dir() else []:
        r = read_json(f, {}) or {}
        st = r.get("stamp")
        if r.get("status") == "done" and r.get("agent") and isinstance(st, dict) and st.get("recorded") is True:
            out.append({"id": r.get("id"), "agent": r.get("agent"), "started": r.get("started") or r.get("created") or "",
                        "repo": r.get("repo_path"), "stamp": st})
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
                             "commit": None, "_agent": agent, "_dim": "agent_version", "_old": prev_v[0], "_new": v})
                seen_pairs.add((agent, prev_v[0], v))
            if v:
                prev_v = (v, r["id"])
            m = st.get("model") if st.get("model_source") == "cli_default_resolved" else None
            if m and prev_m and m != prev_m[0]:
                rows.append({"at": r["started"], "who": "vendor", "what": f"{name}'s default model: {prev_m[0]} → {m}",
                             "path": None, "commit": None, "_agent": agent, "_dim": "model", "_old": prev_m[0], "_new": m})
            if m:
                prev_m = (m, r["id"])
    for agent, hist in (read_json(SEEN, {}) or {}).items():
        name = NAMES.get(agent, agent)
        for a, b in zip(hist, hist[1:]):
            if a.get("version") and b.get("version") and a["version"] != b["version"] \
                    and (agent, a["version"], b["version"]) not in seen_pairs:
                rows.append({"at": b.get("at"), "who": "vendor", "what": f"{name} {a['version']} → {b['version']}",
                             "path": None, "commit": None, "_agent": agent, "_dim": "agent_version",
                             "_old": a["version"], "_new": b["version"]})
                seen_pairs.add((agent, a["version"], b["version"]))
    cut = iso(since)
    return [r for r in rows if (r.get("at") or "") >= cut]


def same_repo(a: str | None, b: str | None) -> bool:
    try:
        return bool(a and b) and Path(a).resolve() == Path(b).resolve()
    except OSError:
        return False


# The setup parts a before/after pair must share (review P1 #3). The one the change is about may (must) differ.
SETUP_KEYS = ("task", "task_version", "agent", "agent_version", "model_requested", "model", "rules", "rules_hash")
# Re-review #3: parts that must be KNOWN on both runs. Two runs that both lack one are not "equal", they are unproven.
# (model_requested may be null: that is the CLI default, a real choice; rules_hash is checked per dimension.)
ESSENTIAL = ("task", "task_version", "agent", "agent_version", "model", "rules")
RULE_FILES = ("CLAUDE.md", "AGENTS.md", "CLAUDE.local.md")
RULE_SPECS = [f":(glob)**/{n}" for n in RULE_FILES]


def _runner():
    """agent_runner, for rules_state: the same hash function a run's capture uses (path order, first 7 hex)."""
    import importlib.util
    spec = importlib.util.spec_from_file_location("agent_runner", Path(__file__).resolve().parent / "agent_runner.py")
    m = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(m)
    return m


_AR = None
_STATE: dict = {}
_LOG: dict = {}


def rules_hash_at(repo: str, rev: str) -> str | None:
    """The rules hash of the repo at a revision (`<commit>^` for the state just before a commit; a root commit's
    parent is the empty rules set). None = unreadable."""
    global _AR
    key = (repo, rev)
    if key not in _STATE:
        _AR = _AR or _runner()
        if rev.endswith("^") and git(repo, "rev-parse", "--verify", "--quiet", rev + "^{commit}").strip() == "":
            # The parent can't be read. Only a commit with no parent at all proves "no rules before it"; a parent that
            # exists but isn't here (a shallow clone's boundary) or a git failure is unknown, never the empty set.
            head = git(repo, "cat-file", "-p", rev[:-1])
            is_root = bool(head) and not any(l.startswith("parent ") for l in head.split("\n\n", 1)[0].splitlines())
            _STATE[key] = _AR.EMPTY_RULES_HASH if is_root else None
        else:
            st = _AR.rules_state(repo, rev)
            _STATE[key] = st[0] if st else None
    return _STATE[key]


def rules_commits(repo: str) -> list[tuple]:
    """(short sha, full sha, committed at as UTC ISO) of every commit that touched a rules file, oldest first."""
    if repo not in _LOG:
        out = git(repo, "log", "--no-merges", "--reverse", f"--format=%H{SEP}%cI", "--", *RULE_SPECS)
        rows = []
        for line in out.splitlines():
            sha, _, when = line.partition(SEP)
            try:
                when = iso(datetime.fromisoformat(when))
            except ValueError:
                pass
            rows.append((sha[:7], sha, when))
        _LOG[repo] = rows
    return _LOG[repo]


def _dimension(row: dict) -> str | None:
    """What a change changes, as a stamp key: the rules (a CLAUDE.md / AGENTS.md edit, only seen by a rules-on run),
    the CLI version or the default model (vendor). None = no run can show it (skills and settings: seat runs never load
    them), so it is never "tested"."""
    if row.get("_dim"):
        return row["_dim"]
    path = row.get("path") or ""
    return "rules" if row.get("who") == "you" and path.rsplit("/", 1)[-1] in RULE_FILES else None


def _known(v) -> bool:
    return v is not None and v != ""


def _eligible(run: dict, row: dict, dim: str) -> bool:
    st = run["stamp"]
    if row.get("_agent") and run["agent"] != row["_agent"]:
        return False
    if not all(_known(st.get(k)) for k in ESSENTIAL):   # re-review #3: missing evidence is never compatibility
        return False
    if dim == "rules":   # re-review P2: "recorded" (a string, the empty set's hash included), not truthy
        return st.get("rules") == "on" and isinstance(st.get("rules_hash"), str)
    if dim == "model":   # the CLI default's resolution changed: only runs on the CLI default, resolved, show it
        return not st.get("model_requested") and st.get("model_source") == "cli_default_resolved"
    return True


def _key(run: dict, dim: str) -> tuple:
    st = run["stamp"]
    return tuple(st.get(k) for k in SETUP_KEYS if k != ("rules_hash" if dim == "rules" else dim))


def _pair(b: dict, a: dict) -> dict:
    """A before/after pair, with the task and task version both runs were on (the same: they are comparable), so the
    app reads that version's blind-guess floor (re-review #5), never the latest board's."""
    return {"before": b["id"], "after": a["id"], "task": b["stamp"].get("task"), "task_version": b["stamp"].get("task_version")}


def _rules_pair(row: dict, before: list, after: list, repo: str) -> dict | None:
    """Re-review #3 (P1): a rules pair is credited to a commit only when the before run's captured rules are the state
    just BEFORE that commit (`<commit>^`) and the after run's are the state just AFTER it (`<commit>`), and no other
    rules commit falls between the two runs. When several do, the pair covers all of them: it is returned with
    "spans" (each commit's short sha, oldest first), never credited to one of them. Exact pairs win over spans."""
    commit = (row.get("commit") or "")[:7]
    log = rules_commits(repo)
    span = None
    for a in after:   # earliest after first, then the latest comparable before it
        for b in reversed(before):
            if _key(a, "rules") != _key(b, "rules") or a["stamp"]["rules_hash"] == b["stamp"]["rules_hash"]:
                continue
            between = [(c, full) for c, full, when in log if b["started"] < when <= a["started"]]
            if commit not in [c for c, _ in between]:
                continue
            if rules_hash_at(repo, between[0][1] + "^") != b["stamp"]["rules_hash"] or \
                    rules_hash_at(repo, between[-1][1]) != a["stamp"]["rules_hash"]:
                continue
            if len(between) == 1:
                return _pair(b, a)
            span = span or dict(_pair(b, a), spans=[c for c, _ in between])
    return span


def tested(row: dict, runs: list[dict], repo: str | None) -> dict:
    """The before/after pair for a change: the latest run before it and the earliest after it that are COMPARABLE —
    both recorded, every essential part KNOWN (task, task version, agent, CLI version, answering model, rules mode),
    same requested model — differing only in what the change changed. A rules commit: the before run's rules hash must
    be the state just before the commit and the after run's the state just after (several rules commits between the
    runs = one pair with "spans", credited to none). A vendor change: the old value before and the new one after. No
    such pair: the latest eligible run before is kept as the one to repeat, and "after" is null; nothing eligible: both
    null ("no comparable before/after tests")."""
    dim = _dimension(row)
    if dim is None:
        return {"before": None, "after": None}
    at = row.get("at") or ""
    pool = [r for r in runs if _eligible(r, row, dim) and (row.get("who") != "you" or same_repo(r["repo"], repo))]
    old, new = row.get("_old"), row.get("_new")
    before = [r for r in pool if r["started"] < at and (old is None or r["stamp"].get(dim) == old)]
    after = [r for r in pool if r["started"] >= at and (new is None or r["stamp"].get(dim) == new)]
    if dim == "rules":
        pair = _rules_pair(row, before, after, repo) if repo else None
        if pair:
            return pair
    else:
        for a in after:   # earliest after first, then the latest comparable before it
            for b in reversed(before):
                if _key(a, dim) == _key(b, dim) and a["stamp"].get(dim) != b["stamp"].get(dim):
                    return _pair(b, a)
    return {"before": before[-1]["id"] if before else None, "after": None}


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
