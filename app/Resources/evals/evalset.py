#!/usr/bin/env python3
"""Your own eval sets (LAB-1995): golden tasks built from a repo's own history, run like any benchmark.

  evalset build --repo PATH [--name NAME] [--count 20] [--days 120] [--linear-key-file PATH] [--json]
  evalset list [--json]
  evalset show <name> [--version N] [--json]      each case with who solved it (n of m runs on that version), the floor
  evalset build --name NAME --extend [--dry-run] …   the next version: the newest version's cases + fixes since (LAB-2065)
  evalset versions <name> [--json]                every version with its cases, date and runs
  evalset add <name> --from-run RUN --sample ID [--epoch 1] [--json]   one answered question into the next version
  evalset add <name> --from-task TASK --sample ID [--json]             (HP EV-11; a frozen version is never edited)
  evalset add --new NAME --from-run RUN --sample ID [--json]            … or into a new set, its kind kept

The first kind of task is the fix locator: a real bug report (the Linear issue when a key file is given, otherwise the
fix commit's subject) and the repo's source files as they were just before the fix; the model names up to three files
it would change. Checked by code: correct when one of its first three names is a file the real fix changed.

Picked from the history: commits that name an issue key and say fix or bug (or whose issue has the Bug label),
touching one to three source files besides tests, docs and site pages; an issue's first such commit is its fix. A report that already names a changed file is left out (too easy), and so is an issue Linear says is not
fixed (still open or canceled: the commit is not its fix). In Review counts as fixed.

Sets are versioned and never edited (regression-corpus rule): each build that finds different tasks writes a new
version; an unchanged build reuses the last one. Stored in <evals>/sets/<name>/v<N>/ with cases.jsonl, set.json and
the Inspect task file; `roof eval run <that file>` runs it, and the Evals place lists the newest version under
"Your evals". Standard library only.
"""
from __future__ import annotations

import json
import os
import re
import subprocess
import sys
import urllib.request
from collections import Counter
from datetime import datetime, timezone
from pathlib import Path

EVALS = Path(os.environ.get("ONEROOF_EVALS_DIR") or Path.home() / "Library/Application Support/One Roof/evals")
SETS = EVALS / "sets"
CATEGORY = "Your evals"
SOURCE = re.compile(r"\.(swift|py|sh|js|ts|mjs|go|rs|rb|java|kt|c|cc|cpp|h|m)$")
NOT_SOURCE = re.compile(r"(^|/)(tests?|Tests|__tests__|spec|vendor|Vendor|scratchpad|node_modules|site|docs|dist|build|assets)(/|$)|Tests?\.\w+$|_test\.\w+$|[Ss]elf[Tt]est")
KEY = re.compile(r"^([A-Z][A-Z0-9]+-\d+)\b")
FIX_WORDS = re.compile(r"\b(fix|fixes|fixed|bug|bugs|broke|broken|crash|regression)\b|\[[^\]]*(bug|fix)[^\]]*\]", re.I)
LINEAR_API = "https://api.linear.app/graphql"
MAX_FILES = 3
# fix-locator: name the files to change (checked by code). triage: say what is wrong and where to look, in a few
# sentences: the same questions, but the answer is prose, so a person (and a judge calibrated on them) grades it; the
# files it names are still checked by code.
KINDS = ("fix-locator", "triage")
MAX_REPORT = 2500   # characters of the issue text shown to the model

TRIAGE = ("You are triaging a bug report for a software project. You get the report and the list of the project's "
          "source files. In two or three sentences, say what is most likely wrong and which file you would open first "
          "(its path exactly as listed). Plain text.")
SYSTEM = ("You are helping fix a bug in a software project. You get a bug report and the list of the project's source "
          "files. Answer with the paths of up to three files you would change to fix it, most likely first, one path "
          "per line, exactly as listed. No other text.")


def now() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def die(msg: str, code: int = 1, as_json: bool = False):
    if as_json:
        print(json.dumps({"error": msg}))
    else:
        print(f"roof eval evalset: {msg}", file=sys.stderr)
    sys.exit(code)


def args_of(argv: list[str], flags: dict[str, object]) -> tuple[list[str], dict]:
    pos, o, i = [], {k.lstrip("-").replace("-", "_"): v for k, v in flags.items()}, 0
    while i < len(argv):
        a = argv[i]
        if a in flags:
            k = a.lstrip("-").replace("-", "_")
            if isinstance(flags[a], bool):
                o[k] = True
            else:
                i += 1
                if i >= len(argv):
                    die(f"{a} needs a value")
                o[k] = argv[i]
        else:
            pos.append(a)
        i += 1
    return pos, o


def git(repo: str, *a: str) -> str:
    r = subprocess.run(["git", "-C", repo, *a], capture_output=True, text=True)
    if r.returncode != 0:
        die(f"git {' '.join(a[:2])} failed: {r.stderr.strip()[-200:]}")
    return r.stdout


def is_source(path: str) -> bool:
    return bool(SOURCE.search(path)) and not NOT_SOURCE.search(path)


def slug(s: str) -> str:
    return re.sub(r"[^a-z0-9]+", "_", s.lower()).strip("_") or "set"


# ── Linear (optional) ─────────────────────────────────────────────────────────────────────────────────────────────
def read_key(p: str) -> str:
    """The key file must hold only the key (the eval engine's rule: never guess which part is the key)."""
    text = Path(os.path.expanduser(p)).read_text().strip()
    if not text or len(text.split()) != 1:
        die("the Linear key file must hold only the key")
    return text


def linear_issue(key: str, token: str) -> dict | None:
    q = "query($id:String!){issue(id:$id){identifier title description labels{nodes{name}} project{name} state{type}}}"
    req = urllib.request.Request(LINEAR_API, data=json.dumps({"query": q, "variables": {"id": key}}).encode(),
                                 headers={"Content-Type": "application/json", "Authorization": token})
    try:
        with urllib.request.urlopen(req, timeout=20) as r:
            doc = json.load(r)
    except Exception:
        return None
    i = (doc.get("data") or {}).get("issue")
    if not i:
        return None
    return {"key": i["identifier"], "title": i["title"] or "", "description": i.get("description") or "",
            "labels": [n["name"] for n in (i.get("labels") or {}).get("nodes", [])],
            "project": ((i.get("project") or {}).get("name") or ""), "state": ((i.get("state") or {}).get("type") or "")}


# ── build ─────────────────────────────────────────────────────────────────────────────────────────────────────────
def candidates(repo: str, days: int, stats: dict | None = None) -> list[dict]:
    """Fix commits, newest first: subject with an issue key, one to three source files changed (tests aside)."""
    log = git(repo, "log", "--no-merges", f"--since={days} days ago", "--format=%x00%H%x1f%P%x1f%cs%x1f%s", "--name-only")
    out = []
    for block in log.split("\x00")[1:]:
        head, _, names = block.partition("\n")
        sha, parents, day, subject = head.split("\x1f", 3)
        m = KEY.match(subject)
        if not m or not parents or " " in parents.strip():
            continue
        files = [f for f in names.split("\n") if f.strip() and is_source(f.strip())]
        if not 1 <= len(files) <= MAX_FILES:
            if stats is not None and len(files) > MAX_FILES:
                stats["left_out_too_many_files"] = stats.get("left_out_too_many_files", 0) + 1
            continue
        out.append({"sha": sha, "parent": parents.split()[0], "date": day, "subject": subject, "key": m.group(1),
                    "files": sorted(set(files))})
    return out


def report_from_subject(subject: str) -> str:
    """'LAB-1 · [tag] Text' → 'Text' (the commit says what was wrong and what changed; the files stay hidden)."""
    s = KEY.sub("", subject).lstrip(" ·-:")
    return re.sub(r"^(\[[^\]]+\]\s*)+", "", s).strip()


def leaks(report: str, files: list[str]) -> bool:
    low = report.lower()
    return any(Path(f).stem.lower() in low and len(Path(f).stem) > 3 for f in files)


def first_fixes(cs: list[dict]) -> list[dict]:
    """One commit per issue: its FIRST fix commit (later ones are follow-ups, release notes or site pages), issues in
    order of their newest commit."""
    first, order = {}, []
    for c in cs:   # newest first
        if c["key"] not in first:
            order.append(c["key"])
        first[c["key"]] = c   # keeps overwriting: ends on the oldest
    return [first[k] for k in order]


def build_cases(repo: str, count: int, days: int, token: str | None, skip: set | None = None) -> tuple[list[dict], dict]:
    """Up to `count` cases, newest fix first. `skip`: issue keys already in the set (a next version keeps those as they are)."""
    seen, cases = set(skip or ()), []
    stats = {"commits_considered": 0, "left_out_leak": 0, "left_out_not_a_fix": 0, "left_out_not_fixed": 0, "linear": 0, "subject": 0,
             "left_out_too_many_files": 0}
    for c in first_fixes(candidates(repo, days, stats)):
        if len(cases) >= count:
            break
        if c["key"] in seen:
            continue
        stats["commits_considered"] += 1
        issue = linear_issue(c["key"], token) if token else None
        fixy = FIX_WORDS.search(c["subject"]) or (issue and ("Bug" in issue["labels"] or FIX_WORDS.search(issue["title"] + " " + issue["project"])))
        if not fixy:
            stats["left_out_not_a_fix"] += 1
            continue
        if issue and issue["state"] not in ("completed", "started"):   # not fixed yet, or dropped: no real answer
            stats["left_out_not_fixed"] += 1
            continue
        if issue:
            report, source = (issue["title"] + "\n\n" + issue["description"]).strip()[:MAX_REPORT], "linear"
        else:
            report, source = report_from_subject(c["subject"]), "commit subject"
        if leaks(report, c["files"]):
            stats["left_out_leak"] += 1
            continue
        tree = [f for f in git(repo, "ls-tree", "-r", "--name-only", c["parent"]).splitlines() if is_source(f)]
        targets = [f for f in c["files"] if f in tree]
        if not targets:   # the fix only added new files: nothing to find in the old tree
            continue
        seen.add(c["key"])
        stats["linear" if issue else "subject"] += 1
        cases.append({
            "id": f"{c['key']}-{c['sha'][:7]}",
            "input": f"Bug report ({c['key']}):\n{report}\n\nSource files:\n" + "\n".join(tree),
            "target": targets,
            "meta": {"kind": "fix-locator", "issue": c["key"], "commit": c["sha"][:12], "date": c["date"],
                     "report_from": source, "files_listed": len(tree), "title": report.split("\n", 1)[0][:160]},
        })
    return cases, stats


TASK_FILE = '''"""{title}: built by One Roof from {repo}'s history (LAB-1995). Never edited: a rebuild makes a new version."""
import json
import re
from pathlib import Path

from inspect_ai import Task, task
from inspect_ai.dataset import Sample
from inspect_ai.scorer import CORRECT, INCORRECT, Score, Target, accuracy, scorer, stderr
from inspect_ai.solver import TaskState, generate, system_message

HERE = Path(__file__).resolve().parent
SYSTEM = {system!r}
PATH = re.compile(r"[\\w./+-]+\\.\\w+")


def named(text: str) -> list[str]:
    """The paths the model named, in order (one per line; bullets, numbers and backticks ignored)."""
    out = []
    for line in text.splitlines():
        m = PATH.search(line.replace("`", " "))
        if m and m.group(0).lstrip("./") not in out:
            out.append(m.group(0).lstrip("./"))
    return out


def hit(name: str, changed: list[str]) -> bool:
    return any(f == name or f.endswith("/" + name) for f in changed)


@scorer(metrics=[accuracy(), stderr()])
def fix_located():
    """Correct when one of the first three named files is a file the real fix changed."""
    async def score(state: TaskState, target: Target) -> Score:
        names = named(state.output.completion)[:3]
        ranks = [i + 1 for i, n in enumerate(names) if hit(n, list(target))]
        return Score(value=CORRECT if ranks else INCORRECT, answer=", ".join(names) or "(no path)",
                     explanation=(f"first right file at rank {{ranks[0]}}" if ranks else "no named file was changed by the fix")
                                 + "; the fix changed: " + ", ".join(target))
    return score


@task
def {func}():
    rows = [json.loads(line) for line in open(HERE / "cases.jsonl")]
    return Task(dataset=[Sample(id=r["id"], input=r["input"], target=r["target"], metadata=r["meta"]) for r in rows],
                solver=[system_message(SYSTEM), generate()], scorer=fix_located(), name={func!r})
'''


def versions(name: str) -> list[Path]:
    d = SETS / name
    return sorted((p for p in d.glob("v*") if p.name[1:].isdigit()), key=lambda p: int(p.name[1:])) if d.is_dir() else []


def frequent_files_baseline(cases: list[dict]) -> int:
    """Questions a no-model guess gets right: the three files fixed most often in the OTHER questions (the floor a
    model's score must clear before it says anything about the model)."""
    hits = 0
    for i, c in enumerate(cases):
        counts = Counter(f for j, o in enumerate(cases) if j != i for f in o["target"])
        top = [f for f, _ in counts.most_common(3)]
        hits += any(t in top for t in c["target"])
    return hits


def write_set(name: str, repo: str, cases: list[dict], stats: dict, days: int, kind: str = "fix-locator",
              base: int | None = None) -> tuple[Path, bool]:
    """A new version unless the newest one holds exactly these tasks (then it is reused, untouched)."""
    old = versions(name)
    body = "".join(json.dumps(c, sort_keys=True) + "\n" for c in cases)
    if old and (old[-1] / "cases.jsonl").read_text() == body:
        return old[-1], False
    v = int(old[-1].name[1:]) + 1 if old else 1
    d = SETS / name / f"v{v}"
    d.mkdir(parents=True)
    func = f"own_{name}_v{v}"
    (d / "cases.jsonl").write_text(body)
    (d / f"{func}.py").write_text(TASK_FILE.format(title=f"{name} v{v}", repo=Path(repo).name,
                                                       system=TRIAGE if kind == "triage" else SYSTEM, func=func))
    meta = {"name": name, "version": v, "task": func, "kind": kind, "repo": Path(repo).name,
            "head": git(repo, "rev-parse", "--short=12", "HEAD").strip(), "built": now(), "days": days,
            "count": len(cases), "stats": stats, "baseline_frequent_files": frequent_files_baseline(cases),
            "issues": [c["meta"]["issue"] for c in cases], "repo_path": str(Path(repo).resolve()), "frozen": now()[:10]}
    if base:
        meta["extends"] = base   # this version = v<base>'s cases unchanged + the fixes since
    (d / "set.json").write_text(json.dumps(meta, indent=2) + "\n")
    return d, True


def task_file(d: Path) -> Path:
    return d / (json.loads((d / "set.json").read_text())["task"] + ".py")


def cases_of(d: Path) -> list[dict]:
    return [json.loads(x) for x in (d / "cases.jsonl").read_text().splitlines() if x.strip()]


def case_row(c: dict) -> dict:
    """A case as the app's tables show it: issue, the report's first line, the files the fix touched."""
    report = c["input"].split("\n\nSource files:\n", 1)[0].split("\n", 1)
    first = (report[1] if len(report) > 1 else report[0]).strip().split("\n")[0]
    return {"id": c["id"], "issue": c["meta"].get("issue"), "report": first[:200], "files": c["target"],
            "date": c["meta"].get("date"), "report_from": c["meta"].get("report_from"), "commit": c["meta"].get("commit")}


def extend(name: str, repo: str, count: int, days: int, token: str | None) -> tuple[list[dict], list[dict], dict, dict]:
    """(old cases, new cases, stats, newest version's meta): the next version keeps every case of the newest version
    and adds fixes it does not have yet (HP EV-6: old scores stay comparable; v1 is never touched)."""
    vs = versions(name)
    if not vs:
        die(f"no set named {name}", 3, True)
    meta = json.loads((vs[-1] / "set.json").read_text())
    old = cases_of(vs[-1])
    new, stats = build_cases(repo, count, days, token, skip={c["meta"]["issue"] for c in old})
    built = (meta.get("built") or "")[:10]
    new = [c for c in new if (c["meta"].get("date") or "") >= built]   # fixed since that version, not older ones it left out
    return old, new, stats, meta


def guess_repo(name: str) -> str | None:
    """A set built before repo paths were kept: its repo by name under the projects folder."""
    root = Path(os.environ.get("ONEROOF_PROJECTS") or Path.home() / "Projects")
    for p in [root / name, *root.glob(f"*/{name}"), *root.glob(f"*/*/{name}")]:
        if (p / ".git").exists():
            return str(p)
    return None


def repo_of(meta: dict) -> str | None:
    p = meta.get("repo_path")
    return p if p and Path(p, ".git").exists() else guess_repo(meta.get("repo") or "")


def new_fix_count(meta: dict) -> int | None:
    """Fixes since the newest version (no Linear call: subjects only), for the Overview's suggestion."""
    repo = repo_of(meta)
    if not repo:
        return None
    old = {i for i in meta.get("issues", [])}
    new, _ = build_cases(repo, 50, int(meta.get("days") or 120), None, skip=old)
    built = (meta.get("built") or "")[:10]
    return len([c for c in new if (c["meta"].get("date") or "") >= built])


def cmd_build(argv):
    _, o = args_of(argv, {"--repo": "", "--name": "", "--count": "20", "--days": "120", "--linear-key-file": "",
                          "--kind": "fix-locator", "--dry-run": False, "--extend": False, "--json": False})
    if o["kind"] not in KINDS:
        die(f"--kind is one of {', '.join(KINDS)}", 2, o["json"])
    repo = os.path.expanduser(o["repo"])
    if o["extend"] and not repo and o["name"]:
        vs = versions(slug(o["name"]))
        repo = (repo_of(json.loads((vs[-1] / "set.json").read_text())) or "") if vs else ""
    if not repo or not Path(repo, ".git").exists():
        die("--repo must be a git checkout", 2, o["json"])
    name = slug(o["name"] or Path(repo).resolve().name + ("_triage" if o["kind"] == "triage" else ""))
    token = read_key(o["linear_key_file"]) if o["linear_key_file"] else None
    if o["extend"]:
        old, new, stats, meta = extend(name, repo, int(o["count"]), int(o["days"]), token)
        preview = {"name": name, "base_version": meta["version"], "next_version": meta["version"] + 1, "repo": repo,
                   "days": int(o["days"]), "kind": meta.get("kind"), "report_source": "linear" if token else "commit subjects",
                   "kept": len(old), "new": [case_row(c) for c in new], "total": len(old) + len(new),
                   "left_out": {k[len("left_out_"):]: v for k, v in stats.items() if k.startswith("left_out_")},
                   "considered": stats["commits_considered"]}
        if o["dry_run"] or not new:
            if o["json"]:
                print(json.dumps(dict(preview, written=False)))
            else:
                print(f"{name}: {len(new)} new fixes since v{meta['version']} ({len(old)} kept) · nothing written")
            return
        d, _ = write_set(name, repo, old + new, stats, int(o["days"]), meta.get("kind", "fix-locator"), base=meta["version"])
        res = dict(preview, written=True, version=int(d.name[1:]), task_file=str(task_file(d)))
        print(json.dumps(res) if o["json"] else f"{name} v{res['version']}: {res['total']} cases ({len(new)} new) · v{meta['version']} unchanged")
        return
    cases, stats = build_cases(repo, int(o["count"]), int(o["days"]), token)
    if o["dry_run"]:
        res = {"name": name, "next_version": (int(versions(name)[-1].name[1:]) + 1) if versions(name) else 1, "repo": repo,
               "days": int(o["days"]), "kind": o["kind"], "report_source": "linear" if token else "commit subjects",
               "kept": 0, "new": [case_row(c) for c in cases], "total": len(cases), "written": False,
               "left_out": {k[len("left_out_"):]: v for k, v in stats.items() if k.startswith("left_out_")},
               "considered": stats["commits_considered"], "floor": frequent_files_baseline(cases) if cases else 0}
        print(json.dumps(res) if o["json"] else f"{name}: would write {len(cases)} cases · nothing written")
        return
    if not cases:
        die("no fix commits found (an issue key in the subject, fix or bug, one to three source files)", 3, o["json"])
    d, new = write_set(name, repo, cases, stats, int(o["days"]), o["kind"])
    res = {"name": name, "version": int(d.name[1:]), "new": new, "count": len(cases), "task_file": str(task_file(d)),
           "stats": stats}
    if o["json"]:
        print(json.dumps(res))
        return
    print(f"{name} v{res['version']}: {len(cases)} tasks ({'new version' if new else 'unchanged, reused'}) · "
          f"reports from Linear {stats['linear']}, from commit subjects {stats['subject']} · "
          f"left out: {stats['left_out_leak']} name the file, {stats['left_out_not_a_fix']} not a fix, "
          f"{stats['left_out_not_fixed']} issue not fixed")
    print(f"no-model floor: guessing the three most-fixed files gets {frequent_files_baseline(cases)} of {len(cases)}")
    if len(cases) < int(o["count"]):
        print(f"only {len(cases)} of {o['count']} found: try --days {int(o['days']) * 2}")
    print(f"run it: roof eval run '{res['task_file']}' --model <model> --limit {len(cases)}")


def all_sets() -> list[dict]:
    out = []
    for d in sorted(SETS.glob("*")) if SETS.is_dir() else []:
        vs = versions(d.name)
        if not vs:
            continue
        try:   # a damaged set is skipped, never fatal: the catalog (and every run) reads this list
            m = json.loads((vs[-1] / "set.json").read_text())
            if "baseline_frequent_files" not in m:   # sets built before the floor existed: computed, never written
                rows = [json.loads(x) for x in (vs[-1] / "cases.jsonl").read_text().splitlines()]
                m["baseline_frequent_files"] = frequent_files_baseline(rows)
            out.append(dict(m, versions=len(vs), task_file=str(task_file(vs[-1])), repo_path=repo_of(m)))
        except (OSError, ValueError, KeyError) as e:
            print(f"roof eval evalset: skipped {d.name}: {e}", file=sys.stderr)
    return out


def all_versions() -> list[dict]:
    """Every version of every set (newest version last per set); damaged ones skipped."""
    out = []
    for d in sorted(SETS.glob("*")) if SETS.is_dir() else []:
        for v in versions(d.name):
            try:
                m = json.loads((v / "set.json").read_text())
                if "baseline_frequent_files" not in m:
                    m["baseline_frequent_files"] = frequent_files_baseline(cases_of(v))
                out.append(dict(m, task_file=str(task_file(v))))
            except (OSError, ValueError, KeyError) as e:
                print(f"roof eval evalset: skipped {v}: {e}", file=sys.stderr)
    return out


def runs_on(name: str, version: int) -> list[dict]:
    """Finished runs of one version (from the index the engine keeps): id, model, agent, start, and each case's mean."""
    db = EVALS / "evals.db"
    if not db.exists():
        return []
    import sqlite3
    with sqlite3.connect(db) as c:
        try:
            rs = c.execute("SELECT id, model, agent, started FROM runs WHERE set_name=? AND set_version=? AND status='done' "
                           "ORDER BY started", (name, version)).fetchall()
            out = []
            for rid, model, agent, started in rs:
                per = dict(c.execute("SELECT sample_id, AVG(score) FROM sample_scores WHERE run_id=? GROUP BY sample_id", (rid,)).fetchall())
                out.append({"id": rid, "model": model, "agent": agent, "started": started, "per_case": per})
            return out
        except sqlite3.OperationalError:   # an index from before 2.0.0: rebuilt by the next `roof eval index`
            return []


def who(model: str | None, agent: str | None) -> str:
    names = {"claude_code": "Claude Code", "codex_cli": "Codex", "opencode": "OpenCode", "kimi_code": "Kimi",
             "gemini_cli": "Gemini CLI", "antigravity": "Antigravity", "mini_swe_agent": "mini-SWE-agent"}
    m = model or "?"
    short = m if m.startswith("mockllm/") else m.split("/", 1)[-1]
    return f"{names.get(agent, agent)} · {short}" if agent else short


KIND_DESC = {"fix-locator": "The agent gets a real bug report and the code as it was before the fix, and names up to three files it "
                            "would change. Correct when one of them is a file the fix changed.",
             "triage": "The agent gets a real bug report and the code as it was before the fix, and says in a few sentences what "
                       "is wrong and where to look. A judge grades the prose; the files it names are also checked by code."}


def cmd_versions(argv):
    pos, o = args_of(argv, {"--json": False})
    if not pos:
        die("evalset versions <name>", 2, o["json"])
    name = slug(pos[0])
    rows = []
    for v in versions(name):
        m = json.loads((v / "set.json").read_text())
        rows.append({"version": m["version"], "count": m["count"], "built": m.get("built"), "frozen": m.get("frozen") or (m.get("built") or "")[:10],
                     "runs": len(runs_on(name, m["version"])), "extends": m.get("extends")})
    print(json.dumps({"name": name, "versions": rows}) if o["json"] else
          "\n".join(f"v{r['version']} · {r['count']} cases · {r['frozen']} · {r['runs']} runs" for r in rows))


def cmd_list(argv):
    _, o = args_of(argv, {"--json": False})
    sets = all_sets()
    if o["json"]:
        print(json.dumps({"sets": sets}))
        return
    if not sets:
        print("no eval sets yet: roof eval evalset build --repo PATH")
    for s in sets:
        print(f"{s['name']:<20} v{s['version']} · {s['count']} tasks · {s['kind']} · from {s['repo']} @ {s['head']} · {s['built']}")


def cmd_show(argv):
    pos, o = args_of(argv, {"--version": "", "--json": False})
    if not pos:
        die("which set? roof eval evalset show <name>", 2, o["json"])
    vs = versions(slug(pos[0]))
    if not vs:
        die(f"no set named {pos[0]}", 3, o["json"])
    d = next((v for v in vs if v.name == f"v{o['version']}"), None) if o["version"] else vs[-1]
    if not d:
        die(f"no version {o['version']}", 3, o["json"])
    meta = json.loads((d / "set.json").read_text())
    rows = [json.loads(line) for line in (d / "cases.jsonl").read_text().splitlines()]
    if o["json"]:
        runs = runs_on(meta["name"], meta["version"])
        cases = []
        for r in rows:
            right = sum(1 for x in runs if (x["per_case"].get(r["id"]) or 0) >= 0.5)
            seen = sum(1 for x in runs if r["id"] in x["per_case"])
            cases.append(dict({k: r[k] for k in ("id", "target", "meta")}, **case_row(r), solved_by={"right": right, "runs": seen}))
        best = None
        for x in runs:
            vals = [v for v in x["per_case"].values() if v is not None]
            if vals:
                sc = sum(vals) / len(vals)
                if best is None or sc > best["score"]:
                    best = {"score": round(sc, 4), "contestant": who(x["model"], x["agent"]), "run": x["id"], "n": len(vals)}
        floor = meta.get("baseline_frequent_files")
        if floor is None:
            floor = frequent_files_baseline(rows)
        print(json.dumps(dict(meta, task_file=str(task_file(d)), cases=cases, runs=len(runs), best=best,
                              floor={"right": floor, "of": len(rows)}, description=KIND_DESC.get(meta.get("kind"), ""),
                              repo_path=repo_of(meta), frozen=meta.get("frozen") or (meta.get("built") or "")[:10],
                              versions=[int(v.name[1:]) for v in versions(meta["name"])])))
        return
    print(f"{meta['name']} v{meta['version']} · {meta['count']} tasks · from {meta['repo']} @ {meta['head']} · "
          f"no-model floor {meta.get('baseline_frequent_files', '?')}/{meta['count']} (three most-fixed files)")
    for r in rows:
        report = r["input"].split("\n", 2)[1][:80]
        print(f"  {r['id']:<22} {report:<80} → {', '.join(r['target'])}")


KIND_TITLE = {"fix-locator": "fix locator", "triage": "bug triage"}
KIND_ASK = {"fix-locator": "the model names up to three files to change. ",
            "triage": "the model says in a few sentences what is wrong and where to look (grade the prose with a judge: "
                      "roof eval judge). "}


def catalog_entries() -> list[dict]:
    """The newest version of each set as a catalog benchmark (the Evals place shows these under 'Your evals')."""
    return [{"folder": f"own-{s['name']}", "title": f"{s['name']} · {KIND_TITLE.get(s['kind'], s['kind'])} (your work)", "group": CATEGORY,
             "description": (f"{s['count']} real bugs from {s['repo']}'s history (v{s['version']}, built {s['built'][:10]}). "
                             "Each question gives a bug report and the source files as they were before the fix; "
                             + KIND_ASK.get(s["kind"], "") +
                             "Correct when one of the first three files named is a file the fix changed. "
                             f"No-model floor: always guessing the three files fixed most often gets "
                             f"{s.get('baseline_frequent_files', '?')} of {s['count']}."),
             "arxiv": None, "version": str(s["version"]), "tags": ["own", s["kind"]], "extra": None, "sandbox": False,
             "internet": False, "supports_k8s": False, "assets": [],
             "tasks": [{"name": s["task_file"], "samples": s["count"], "human_baseline": None}],
             "starter": [], "category": CATEGORY} for s in all_sets()]


# A set of plain questions (from a benchmark or a run on one): checked by code, right when the reference answer is in the
# reply (Inspect's includes()). Fix-locator and triage cases keep their own check.
QUESTIONS_TASK = '''"""{title}: questions added by One Roof from runs and benchmarks (LAB-2069). Never edited: an addition is a new version."""
import json
from pathlib import Path

from inspect_ai import Task, task
from inspect_ai.dataset import Sample
from inspect_ai.scorer import includes
from inspect_ai.solver import generate

HERE = Path(__file__).resolve().parent


@task
def {func}():
    rows = [json.loads(line) for line in open(HERE / "cases.jsonl")]
    return Task(dataset=[Sample(id=r["id"], input=r["input"], target=r["target"], metadata=r["meta"]) for r in rows],
                solver=[generate()], scorer=includes(), name={func!r})
'''


def case_from_run(rid: str, sample: str, epoch: int = 1) -> tuple:
    """(case, kind) for one answered question of a run: your set's case as it is (its kind kept); a judge run's answer
    goes back to the run it judged; a benchmark's question is read from the run's log (needs the engine)."""
    rj = EVALS / "runs" / rid / "run.json"
    if not rj.exists():
        die(f"no run {rid}", 3, True)
    run = json.loads(rj.read_text())
    ref = run.get("task_ref") or ""
    m = re.search(r"/sets/([^/]+)/v(\d+)/[^/]+\.py$", ref)
    if m:
        d = Path(ref).parent
        kind = json.loads((d / "set.json").read_text()).get("kind") or "fix-locator"
        case = next((c for c in cases_of(d) if c["id"] == sample), None)
        if case is None:
            die(f"no case {sample} in {m.group(1)} v{m.group(2)}", 3, True)
        SOURCE_META.update(json.loads((d / "set.json").read_text()))
        return case, kind
    if str(run.get("task") or "").startswith("judge_"):
        name = run["task"][len("judge_"):].rpartition("_v")[0]
        items = EVALS / "judges" / name / "items.jsonl"
        rows = [json.loads(x) for x in items.read_text().splitlines() if x.strip()] if items.exists() else []
        item = next((x for x in rows if x["id"] == sample), None)
        if item and item.get("run"):
            return case_from_run(item["run"], item["sample"], int(str(item["id"]).rsplit(":", 1)[-1] or 1))
        die(f"the judge item {sample} does not say which run it came from", 3, True)
    import importlib.util
    spec = importlib.util.spec_from_file_location("judge", Path(__file__).resolve().parent / "judge.py")
    j = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(j)
    doc = j.read_run(rid)
    s = next((x for x in doc["samples"] if x["id"] == sample and x["epoch"] == epoch), None) or \
        next((x for x in doc["samples"] if x["id"] == sample), None)
    if s is None:
        die(f"no question {sample} in run {rid}", 3, True)
    return {"id": f"{run.get('task')}-{sample}", "input": s["input"], "target": s["target"],
            "meta": {"kind": "questions", "task": run.get("task"), "from_run": rid, "sample": sample}}, "questions"


def case_from_task(task: str, sample: str) -> tuple:
    """A benchmark question already on this Mac (Explore › Questions downloaded it); your own set's case as it is."""
    m = re.search(r"/sets/([^/]+)/v(\d+)/[^/]+\.py$", task)
    if m:
        d = Path(os.path.expanduser(task)).resolve().parent
        case = next((c for c in cases_of(d) if c["id"] == sample), None)
        if case is None:
            die(f"no case {sample} in {m.group(1)} v{m.group(2)}", 3, True)
        SOURCE_META.update(json.loads((d / "set.json").read_text()))
        return case, SOURCE_META.get("kind") or "fix-locator"
    name = task.rsplit("/", 1)[-1]
    name = name[:-3] if name.endswith(".py") else name
    for f in sorted((EVALS / "questions" / name).glob("*.jsonl"), key=lambda p: p.stat().st_mtime, reverse=True):
        for line in f.read_text().splitlines():
            try:
                x = json.loads(line)
            except ValueError:
                continue
            if str(x.get("id")) == sample:
                return {"id": f"{name}-{sample}", "input": x["input"], "target": x["target"],
                        "meta": {"kind": "questions", "task": name, "sample": sample}}, "questions"
    die(f"question {sample} of {name} is not on this Mac yet: open it in Explore › Questions first", 3, True)


CODE_KINDS = ("fix-locator", "triage")
# The set a case came from (its repo, so agents on seats can make worktrees for a new set's cases too).
SOURCE_META: dict = {}


def add_case(name: str, case: dict, kind: str, new: bool = False) -> dict:
    """The next version = the newest version's cases + this one (HP EV-11). The frozen versions stay byte for byte."""
    name = slug(name)
    vs = versions(name)
    if new and vs:
        die(f"a set named {name} exists: add to it, or pick another name", 3, True)
    if not new and not vs:
        die(f"no set named {name}", 3, True)
    old_meta = json.loads((vs[-1] / "set.json").read_text()) if vs else {}
    set_kind = old_meta.get("kind") or kind
    if (set_kind in CODE_KINDS) != (kind in CODE_KINDS):
        die(f"{name} holds {KIND_TITLE.get(set_kind, set_kind)} cases; a {KIND_TITLE.get(kind, kind)} case goes into a set "
            "of its own kind (choose New set)", 3, True)
    old = cases_of(vs[-1]) if vs else []
    if any(c["id"] == case["id"] for c in old):
        return {"name": name, "version": int(vs[-1].name[1:]), "added": False, "count": len(old),
                "message": f"Already in {name} v{vs[-1].name[1:]}"}
    cases = old + [case]
    v = int(vs[-1].name[1:]) + 1 if vs else 1
    d = SETS / name / f"v{v}"
    d.mkdir(parents=True)
    func = f"own_{name}_v{v}"
    (d / "cases.jsonl").write_text("".join(json.dumps(c, sort_keys=True) + "\n" for c in cases))
    if set_kind in CODE_KINDS:
        body = TASK_FILE.format(title=f"{name} v{v}", repo=old_meta.get("repo") or name,
                                system=TRIAGE if set_kind == "triage" else SYSTEM, func=func)
    else:
        body = QUESTIONS_TASK.format(title=f"{name} v{v}", func=func)
    (d / f"{func}.py").write_text(body)
    base = old_meta or (SOURCE_META if set_kind in CODE_KINDS else {})
    meta = {k: base[k] for k in ("head", "days", "repo_path") if k in base}
    if "repo_path" not in meta and base:
        rp = repo_of(base)
        if rp:
            meta["repo_path"] = rp
    meta.update(name=name, version=v, task=func, kind=set_kind, built=now(), frozen=now()[:10], count=len(cases),
                stats=old_meta.get("stats") or {}, issues=[(c.get("meta") or {}).get("issue") or c["id"] for c in cases],
                added=(old_meta.get("added") or []) + [case["id"]], repo=base.get("repo") or name)
    if set_kind in CODE_KINDS:
        meta["baseline_frequent_files"] = frequent_files_baseline(cases)
    if vs:
        meta["extends"] = int(vs[-1].name[1:])
    (d / "set.json").write_text(json.dumps(meta, indent=2) + "\n")
    return {"name": name, "version": v, "added": True, "count": len(cases), "task_file": str(d / f"{func}.py"),
            "message": f"Added to {name} (new version v{v})"}


def cmd_add(argv):
    pos, o = args_of(argv, {"--from-run": "", "--from-task": "", "--sample": "", "--epoch": "1", "--new": "", "--json": False})
    target = o["new"] or (pos[0] if pos else "")
    if not target or not o["sample"] or not (o["from_run"] or o["from_task"]):
        die("evalset add <name> | --new NAME  --from-run RUN | --from-task TASK  --sample ID", 2, o["json"])
    if o["from_run"]:
        case, kind = case_from_run(o["from_run"], o["sample"], int(o["epoch"] or 1))
    else:
        case, kind = case_from_task(o["from_task"], o["sample"])
    res = add_case(target, case, kind, new=bool(o["new"]))
    print(json.dumps(res) if o["json"] else res["message"])


KIND_TITLE["questions"] = "questions"


COMMANDS = {"build": cmd_build, "list": cmd_list, "show": cmd_show, "versions": cmd_versions, "add": cmd_add}

if __name__ == "__main__":
    if len(sys.argv) < 2 or sys.argv[1] not in COMMANDS:
        print(__doc__)
        sys.exit(0 if len(sys.argv) < 2 else 2)
    COMMANDS[sys.argv[1]](sys.argv[2:])
