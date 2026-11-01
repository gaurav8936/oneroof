#!/usr/bin/env python3
"""Agent X-ray from git (LAB-1961): how much of each agent's work survives, per agent, over a window.

  python3 xray.py --repo PATH [--repo PATH …] [--days 30] [--horizon 14] [--json]
  python3 xray.py --oneroof ~/Library/Application\ Support/One\ Roof/sessions.sqlite   supervision load (LAB-2008)
  (also: roof eval xray …)

Attribution: a commit belongs to an agent when its Co-Authored-By trailer or author names one (Claude, Codex, Gemini,
Kimi, Copilot, Cursor, Devin, Jules, Antigravity, OpenCode, Goose); everything else is "unattributed" (a person, or an
agent that does not sign its commits). Merge commits are skipped.

Metrics, per agent (definitions in labs-docs projects/lab-evals/02_agent-xray.md):
  commits, lines_added                         volume
  churn       lines it added that any later commit deleted or rewrote within the horizon, ÷ lines it added
              (GitClear's "code churn"; only commits at least `horizon` days old count, so every line had a full window)
  self_churn  the part of that churn done by the same agent (fixing its own work) vs by others
  revert_rate commits later reverted ("This reverts commit <sha>") ÷ commits
  fixup_rate  commits followed within 3 days by a commit that touches a same file and whose subject says fix/bug/
              regress/broke/revert ÷ commits (a proxy: it does not prove the fix was for this commit)
Only source-code files count (py, swift, ts/js, sh, go, rs, …); generated pages, data, docs, lock files and vendored trees
are left out. A repo younger than the horizon has no mature commits: use a shorter --horizon and say so.
"""
from __future__ import annotations

import json
import os
import re
import subprocess
import sys
from collections import defaultdict
from datetime import datetime, timedelta, timezone

AGENTS = ["Claude", "Codex", "Gemini", "Kimi", "Copilot", "Cursor", "Devin", "Jules", "Antigravity", "OpenCode", "Goose"]
# Source code only: generated pages, data, lock files and vendored trees would swamp the numbers.
CODE = re.compile(r"\.(py|swift|ts|tsx|js|jsx|mjs|sh|bash|go|rs|rb|java|kt|c|h|m|mm|cc|cpp|css|scss|sql|zig)$")
_EXCL = re.compile(r"(^|/)(Vendor|vendor|dist|build|node_modules|\.build)/|\.min\.")


class _Skip:
    @staticmethod
    def search(path: str) -> bool:
        return not CODE.search(path) or bool(_EXCL.search(path))


SKIP = _Skip()
FIXY = re.compile(r"\b(fix|fixes|fixed|bug|regress|regression|broke|broken|revert|hotfix)\b", re.I)
SEP = "\x1e"


def git(repo: str, *args: str) -> str:
    return subprocess.run(["git", "-C", repo, *args], capture_output=True, text=True, errors="replace").stdout


def agent_of(author: str, trailers: str) -> str:
    text = f"{author} {trailers}"
    for a in AGENTS:
        if re.search(rf"\b{a}\b", text, re.I):
            return a
    return "unattributed"


def commits(repo: str, since: datetime) -> list[dict]:
    fmt = f"%H{SEP}%P{SEP}%an{SEP}%at{SEP}%s{SEP}%(trailers:key=Co-Authored-By,valueonly,separator=|){SEP}%b"
    out = git(repo, "log", "--no-merges", "--reverse", f"--since={since.isoformat()}", f"--format={fmt}%x00", "HEAD")
    rows = []
    for rec in out.split("\x00"):
        p = rec.strip("\n").split(SEP)
        if len(p) < 7:
            continue
        sha, parents, author, at, subj, trailers, body = p[:7]
        rows.append({"sha": sha, "parent": parents.split()[0] if parents else None, "author": author,
                     "time": datetime.fromtimestamp(int(at), timezone.utc), "subject": subj,
                     "agent": agent_of(author, trailers), "body": body})
    return rows


def numstat(repo: str, sha: str) -> dict[str, int]:
    added = {}
    for line in git(repo, "show", "--numstat", "--format=", sha).splitlines():
        p = line.split("\t")
        if len(p) == 3 and p[0].isdigit() and not SKIP.search(p[2]):
            added[p[2]] = int(p[0])
    return added


def deleted_ranges(repo: str, sha: str) -> dict[str, list[tuple[int, int]]]:
    """Old-side line ranges each commit removes or rewrites, per file (from the unified diff's hunk headers)."""
    ranges: dict[str, list[tuple[int, int]]] = defaultdict(list)
    cur = None
    for line in git(repo, "show", "-U0", "--format=", "--no-renames", sha).splitlines():
        if line.startswith("--- "):
            cur = None if line == "--- /dev/null" else line[6:] if line.startswith("--- a/") else None
        elif line.startswith("@@") and cur and not SKIP.search(cur):
            m = re.match(r"@@ -(\d+)(?:,(\d+))? \+", line)
            if m:
                start, n = int(m.group(1)), int(m.group(2) or "1")
                if n > 0:
                    ranges[cur].append((start, start + n - 1))
    return ranges


def blame_origins(repo: str, parent: str, path: str, ranges: list[tuple[int, int]]) -> list[str]:
    """For each line in the ranges at `parent`, the commit that last wrote it."""
    args = ["blame", "--porcelain"]
    for a, b in ranges:
        args += ["-L", f"{a},{b}"]
    out = git(repo, *args, parent, "--", path)
    origins = []
    for line in out.splitlines():
        m = re.match(r"^([0-9a-f]{40}) \d+ \d+", line)
        if m:
            origins.append(m.group(1))
    return origins


def xray(repos: list[str], days: int, horizon: int) -> dict:
    now = datetime.now(timezone.utc)
    window_start, mature = now - timedelta(days=days), now - timedelta(days=horizon)
    per = defaultdict(lambda: defaultdict(float))
    for repo in repos:
        cs = commits(repo, window_start - timedelta(days=1))
        by_sha = {c["sha"]: c for c in cs}
        for c in cs:
            c["files"] = numstat(repo, c["sha"])
        # Volume, maturity
        for c in cs:
            if c["time"] < window_start:
                continue
            a = per[c["agent"]]
            a["commits"] += 1
            a["lines_added"] += sum(c["files"].values())
            if c["time"] <= mature:
                a["mature_commits"] += 1
                a["mature_lines"] += sum(c["files"].values())
        # Churn: lines later commits removed, traced back to who wrote them
        for later in cs:
            if not later["parent"]:
                continue
            for path, rng in deleted_ranges(repo, later["sha"]).items():
                for origin in blame_origins(repo, later["parent"], path, rng):
                    o = by_sha.get(origin)
                    if not o or o["time"] < window_start or o["time"] > mature:
                        continue
                    if later["time"] - o["time"] <= timedelta(days=horizon):
                        per[o["agent"]]["churned"] += 1
                        if later["agent"] == o["agent"]:
                            per[o["agent"]]["self_churned"] += 1
        # Reverts and fix-ups
        for c in cs:
            for m in re.finditer(r"This reverts commit ([0-9a-f]{7,40})", c["body"]):
                o = next((x for s, x in by_sha.items() if s.startswith(m.group(1))), None)
                if o and o["time"] >= window_start:
                    per[o["agent"]]["reverted"] += 1
        for i, c in enumerate(cs):
            if c["time"] < window_start:
                continue
            files = set(c["files"])
            for later in cs[i + 1:]:
                if later["time"] - c["time"] > timedelta(days=3):
                    break
                if FIXY.search(later["subject"]) and files & set(later["files"]):
                    per[c["agent"]]["fixed_up"] += 1
                    break
    out = {}
    for agent, a in sorted(per.items(), key=lambda kv: -kv[1]["commits"]):
        n, ml = a["commits"], a["mature_lines"]
        out[agent] = {
            "commits": int(n), "lines_added": int(a["lines_added"]), "mature_commits": int(a["mature_commits"]),
            "churn": round(a["churned"] / ml, 4) if ml else None,
            "self_churn_share": round(a["self_churned"] / a["churned"], 4) if a["churned"] else None,
            "revert_rate": round(a["reverted"] / n, 4) if n else None,
            "fixup_rate": round(a["fixed_up"] / n, 4) if n else None,
        }
    return {"window_days": days, "horizon_days": horizon, "computed": now.strftime("%Y-%m-%dT%H:%M:%SZ"),
            "repos": len(repos), "agents": out}


def supervision(store: str, days: int) -> dict:
    """LAB-2008 · how much each agent needed the owner, from One Roof's Needs-you decisions (read-only).
    asks per session, the answer mix (reply = the owner typed an answer or a redirect; always/allowOnce/deny = a
    permission), and how long an ask waited for the owner. Active hours are not recorded, so no per-hour rate."""
    import sqlite3, statistics, time
    db = sqlite3.connect(f"file:{store}?mode=ro", uri=True)
    since = time.time() - days * 86400
    sessions = defaultdict(set)
    for (sj,) in db.execute("SELECT json FROM sessions"):
        try:
            d = json.loads(sj)
        except ValueError:
            continue
        t = d.get("launchedAt") or d.get("createdAt") or 0
        if isinstance(t, (int, float)) and t > since - 978307200:   # Swift dates count from 2001
            sessions[d.get("agent") or "?"].add(d.get("id"))
    out = {}
    rows = db.execute("SELECT coalesce(agent,'?'), session_id, kind, asked_at, answered_at, coalesce(answer,'') "
                      "FROM decisions WHERE asked_at > ?", (since,)).fetchall()
    by = defaultdict(list)
    for r in rows:
        by[r[0]].append(r)
    for agent, rs in sorted(by.items(), key=lambda kv: -len(kv[1])):
        waits = [(r[4] - r[3]) for r in rs if r[4] and r[4] >= r[3]]
        mix = defaultdict(int)
        for r in rs:
            mix[r[5] or "unanswered"] += 1
        asked_in = len({r[1] for r in rs})
        n_sessions = max(len(sessions.get(agent, set())), asked_in)
        out[agent] = {"asks": len(rs), "sessions": n_sessions, "sessions_with_asks": asked_in,
                      "asks_per_session": round(len(rs) / n_sessions, 2) if n_sessions else None,
                      "median_wait_s": round(statistics.median(waits)) if waits else None,
                      "p90_wait_s": round(sorted(waits)[int(0.9 * (len(waits) - 1))]) if waits else None,
                      "answers": dict(mix), "run_command_share": round(sum(r[2] == "runCommand" for r in rs) / len(rs), 3)}
    return {"window_days": days, "agents": out}


def transcript_usage(path: str) -> dict:
    """Token totals per model from a Claude Code transcript (JSONL: message.usage + message.model on each reply).
    Other agents' transcripts use other formats and come back empty (counted as 'no usage read')."""
    per = defaultdict(lambda: defaultdict(int))
    try:
        with open(os.path.expanduser(path), errors="replace") as f:
            for line in f:
                if '"usage"' not in line:
                    continue
                try:
                    m = json.loads(line).get("message") or {}
                except ValueError:
                    continue
                u, model = m.get("usage"), m.get("model")
                if not isinstance(u, dict) or not model or model.startswith("<"):
                    continue
                t = per[model]
                t["input"] += int(u.get("input_tokens") or 0)
                t["cache_read"] += int(u.get("cache_read_input_tokens") or 0)
                t["cache_write"] += int(u.get("cache_creation_input_tokens") or 0)
                t["output"] += int(u.get("output_tokens") or 0)
    except OSError:
        pass
    return per


def issue_cost(store: str, prices_path: str, days: int) -> dict:
    """LAB-2009 · API-equivalent cost per linked issue, per agent: each One Roof session's transcript tokens priced at
    list prices (prices.json from `roof eval prices`; cache reads at 10 %, cache writes at 125 % of input), divided
    over the issues the session was attached to. Subscription seats are not billed per token: this is what the same
    work would cost on the API, a comparison figure, not a bill."""
    import sqlite3, time
    doc = json.load(open(prices_path)) if os.path.exists(prices_path) else {"models": {}}
    table = doc.get("models", {})

    def price(model: str):
        m = re.sub(r"-\d{8}$", "", model)
        for cand in (m, "anthropic/" + m, "anthropic/" + re.sub(r"-(\d+)-(\d+)", r"-\1.\2", m)):
            if cand in table:
                return table[cand]
        return None

    db = sqlite3.connect(f"file:{store}?mode=ro", uri=True)
    since = time.time() - days * 86400
    per = defaultdict(lambda: {"sessions": 0, "sessions_priced": 0, "issues": set(), "usd": 0.0, "unpriced_models": set()})
    for (j, updated) in db.execute("SELECT json, updated FROM sessions"):
        try:
            d = json.loads(j)
        except ValueError:
            continue
        if (updated or 0) and updated < since - 978307200 and updated < since:
            continue
        agent = d.get("agent") or "?"
        if agent == "shell":
            continue
        a = per[agent]
        a["sessions"] += 1
        keys = {t.get("key") for t in (d.get("moreTickets") or []) if isinstance(t, dict) and t.get("key")}
        a["issues"] |= keys
        usage = transcript_usage(d.get("conversationPath") or "") if d.get("conversationPath") else {}
        if not usage:
            continue
        a["sessions_priced"] += 1
        for model, t in usage.items():
            p = price(model)
            if not p:
                a["unpriced_models"].add(model)
                continue
            a["usd"] += (t["input"] * p["input"] + t["cache_read"] * p["input"] * 0.1 + t["cache_write"] * p["input"] * 1.25
                         + t["output"] * p["output"]) / 1e6
    out = {}
    for agent, a in sorted(per.items(), key=lambda kv: -kv[1]["usd"]):
        n = len(a["issues"])
        out[agent] = {"sessions": a["sessions"], "sessions_with_usage": a["sessions_priced"], "issues_linked": n,
                      "api_equivalent_usd": round(a["usd"], 2),
                      "usd_per_linked_issue": round(a["usd"] / n, 2) if n and a["usd"] else None,
                      "unpriced_models": sorted(a["unpriced_models"])}
    return {"window_days": days, "basis": "API-equivalent at list prices (prices.json " + str(doc.get("checked")) + ")",
            "agents": out}


def main(argv: list[str]) -> None:
    repos, days, horizon, as_json, store = [], 30, 14, False, None
    i = 0
    while i < len(argv):
        a = argv[i]
        if a == "--repo":
            repos.append(argv[i + 1]); i += 1
        elif a == "--days":
            days = int(argv[i + 1]); i += 1
        elif a == "--horizon":
            horizon = int(argv[i + 1]); i += 1
        elif a == "--json":
            as_json = True
        elif a == "--oneroof":
            store = os.path.expanduser(argv[i + 1]); i += 1
        else:
            print(__doc__); sys.exit(2)
        i += 1
    if not repos and not store:
        print(__doc__); sys.exit(2)
    r = xray(repos, days, horizon) if repos else {"agents": {}}
    if store:
        r["supervision"] = supervision(store, days)
        r["issue_cost"] = issue_cost(store, os.path.join(os.path.dirname(store), "evals", "prices.json"), days)
    if as_json:
        print(json.dumps(r, indent=2))
        return
    if store:
        sv = r["supervision"]["agents"]
        print(f"Supervision (One Roof Needs-you, last {days} days)")
        print(f"{'agent':<10}{'asks':>6}{'sessions':>9}{'per sess':>9}{'wait p50':>9}{'p90':>8}  answers")
        for a, m in sv.items():
            fmt = lambda s: "–" if s is None else (f"{s}s" if s < 120 else f"{s // 60}m")
            print(f"{a:<10}{m['asks']:>6}{m['sessions']:>9}{m['asks_per_session'] or 0:>9}{fmt(m['median_wait_s']):>9}"
                  f"{fmt(m['p90_wait_s']):>8}  " + ", ".join(f"{k} {v}" for k, v in sorted(m['answers'].items(), key=lambda kv: -kv[1])))
        ic = r["issue_cost"]
        print(f"\nCost per linked issue ({ic['basis']})")
        print(f"{'agent':<10}{'sessions':>9}{'w/ usage':>9}{'issues':>8}{'API-eq $':>10}{'$/issue':>9}")
        for a, m in ic["agents"].items():
            print(f"{a:<10}{m['sessions']:>9}{m['sessions_with_usage']:>9}{m['issues_linked']:>8}{m['api_equivalent_usd']:>10}"
                  f"{(m['usd_per_linked_issue'] if m['usd_per_linked_issue'] is not None else '–'):>9}")
        if not repos:
            return
    print(f"Agent X-ray · last {days} days · churn horizon {horizon} days · {len(repos)} repo(s)")
    print(f"{'agent':<14}{'commits':>8}{'lines':>9}{'churn':>10}{'self':>7}{'revert':>8}{'fixup':>7}")
    pct = lambda v: "–" if v is None else f"{v * 100:.1f}%"
    for agent, m in r["agents"].items():
        print(f"{agent:<14}{m['commits']:>8}{m['lines_added']:>9}{pct(m['churn']):>10}{pct(m['self_churn_share']):>7}"
              f"{pct(m['revert_rate']):>8}{pct(m['fixup_rate']):>7}")


if __name__ == "__main__":
    main(sys.argv[1:])
