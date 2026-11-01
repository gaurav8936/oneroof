#!/usr/bin/env python3
"""Your own eval sets (LAB-1995): golden tasks built from a repo's own history, run like any benchmark.

  evalset build --repo PATH [--name NAME] [--count 20] [--days 120] [--linear-key-file PATH] [--json]
  evalset list [--json]
  evalset show <name> [--version N] [--json]

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
def candidates(repo: str, days: int) -> list[dict]:
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


def build_cases(repo: str, count: int, days: int, token: str | None) -> tuple[list[dict], dict]:
    seen, cases = set(), []
    stats = {"commits_considered": 0, "left_out_leak": 0, "left_out_not_a_fix": 0, "left_out_not_fixed": 0, "linear": 0, "subject": 0}
    for c in first_fixes(candidates(repo, days)):
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
                     "report_from": source, "files_listed": len(tree)},
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


def write_set(name: str, repo: str, cases: list[dict], stats: dict, days: int, kind: str = "fix-locator") -> tuple[Path, bool]:
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
            "issues": [c["meta"]["issue"] for c in cases]}
    (d / "set.json").write_text(json.dumps(meta, indent=2) + "\n")
    return d, True


def task_file(d: Path) -> Path:
    return d / (json.loads((d / "set.json").read_text())["task"] + ".py")


def cmd_build(argv):
    _, o = args_of(argv, {"--repo": "", "--name": "", "--count": "20", "--days": "120", "--linear-key-file": "",
                          "--kind": "fix-locator", "--json": False})
    if o["kind"] not in KINDS:
        die(f"--kind is one of {', '.join(KINDS)}", 2, o["json"])
    repo = os.path.expanduser(o["repo"])
    if not repo or not Path(repo, ".git").exists():
        die("--repo must be a git checkout", 2, o["json"])
    name = slug(o["name"] or Path(repo).resolve().name + ("_triage" if o["kind"] == "triage" else ""))
    token = read_key(o["linear_key_file"]) if o["linear_key_file"] else None
    cases, stats = build_cases(repo, int(o["count"]), int(o["days"]), token)
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
            out.append(dict(m, versions=len(vs), task_file=str(task_file(vs[-1]))))
        except (OSError, ValueError, KeyError) as e:
            print(f"roof eval evalset: skipped {d.name}: {e}", file=sys.stderr)
    return out


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
        print(json.dumps(dict(meta, task_file=str(task_file(d)), cases=[{k: r[k] for k in ("id", "target", "meta")} for r in rows])))
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


COMMANDS = {"build": cmd_build, "list": cmd_list, "show": cmd_show}

if __name__ == "__main__":
    if len(sys.argv) < 2 or sys.argv[1] not in COMMANDS:
        print(__doc__)
        sys.exit(0 if len(sys.argv) < 2 else 2)
    COMMANDS[sys.argv[1]](sys.argv[2:])
