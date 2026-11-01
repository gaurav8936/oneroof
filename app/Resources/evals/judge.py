#!/usr/bin/env python3
"""A model as judge, measured against you (LAB-1996): for answers code can't check.

  judge new <name> --runs RUN[,RUN2] --rubric TEXT [--pairwise] [--json]
  judge label <name>                                   label in the terminal: p(ass) f(ail) [a b t for pairs], s q
  judge label <name> --item ID --verdict pass|fail|a|b|tie [--why TEXT]
  judge build <name> [--examples 10] [--json]          the judge's task file: your rubric + your first labels
  judge agreement <name> [--run RUN] [--json]          how often the judge agrees with you on labels it never saw
  judge list [--json]   judge show <name> [--json]
  judge items <name> [--json]       every answer with its labels (yours, code's, a model's) and example / held back
  judge queue <name> [--first ID] [--json]   answers you have not labelled, likely fails first (judge passed, code failed)
  judge label <name> --undo [--item ID]        take back your last label (or that item's); the file keeps the history
  judge trust <name> [--json]       how far to trust it now: the last judge run against your labels as they are today
  judge advise <name> [--json]      what would help most (rule-based)
  judge rubric <name> [--set TEXT] [--json]     the rubric; --set saves a draft for the next version (never edits one)
  judge versions <name> [--json]    every version: rubric, examples, held back, runs, agreement

How it works (the judge-models skill): you grade real answers pass or fail, each with a reason. The first labels become
the judge's worked examples; the rest are held back. The judge (any model) grades every answer; agreement is measured
only on the held-back labels, as overall agreement, true positive rate (good answers it passes) and true negative rate
(bad answers it fails). A judge that passes everything looks good on a mostly-good set; TPR and TNR show it.

Pairwise (--pairwise with two runs): the judge sees both answers to each question twice, in both orders. A win counts
only when it holds both ways; how often it does not is the judge's position bias. A judge model that also wrote one
of the answers is flagged (self-preference).

Run the judge like any benchmark: `roof eval run <its task file> --model M` (cost before start, cap, results).
Results then show the agreement next to the judged score. Data: <evals>/judges/<name>/; each build is a new version,
never edited. Standard library only; reading run logs uses the engine's python.
"""
from __future__ import annotations

import json
import os
import re
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path

EVALS = Path(os.environ.get("ONEROOF_EVALS_DIR") or Path.home() / "Library/Application Support/One Roof/evals")
JUDGES = EVALS / "judges"
RUNS = EVALS / "runs"
VPY = EVALS / "venv/bin/python"
AGREEMENTS = JUDGES / "agreements.json"   # judge run id → agreement summary (results read this)
MIN_HELD_OUT = 10
MAX_TEXT = 6000

VERDICTS = {"single": ("pass", "fail"), "pairwise": ("a", "b", "tie")}
KEYS = {"p": "pass", "f": "fail", "a": "a", "b": "b", "t": "tie"}


def now() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def die(msg: str, code: int = 1, as_json: bool = False):
    if as_json:
        print(json.dumps({"error": msg}))
    else:
        print(f"roof eval judge: {msg}", file=sys.stderr)
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


def read_json(p: Path, default=None):
    try:
        return json.loads(p.read_text())
    except (OSError, ValueError):
        return default


def jdir(name: str) -> Path:
    d = JUDGES / name
    if not (d / "judge.json").exists():
        die(f"no judge named {name}: roof eval judge new {name} --runs RUN --rubric TEXT")
    return d


def latest_log(rid: str) -> Path | None:
    logs = sorted((RUNS / rid).glob("*.eval"), key=lambda p: p.stat().st_mtime)
    return logs[-1] if logs else None


# Full question and answer text per sample (the engine's `samples` cuts them short for display).
_READ = r"""
import json, sys
from inspect_ai.log import read_eval_log, read_eval_log_samples
def text(x):
    if x is None: return ""
    if isinstance(x, list): return "\n".join(getattr(m, "text", str(m)) for m in x)
    return str(x)
hdr = read_eval_log(sys.argv[1], header_only=True)
out = {"task": hdr.eval.task, "model": hdr.eval.model, "samples": []}
for s in read_eval_log_samples(sys.argv[1], all_samples_required=False):
    sc = next(iter((s.scores or {}).values()), None)
    out["samples"].append({"id": str(s.id), "epoch": s.epoch, "input": text(s.input), "target": text(s.target),
      "output": s.output.completion if s.output else "", "answer": sc.answer if sc else None,
      "value": str(sc.value) if sc else None, "metadata": s.metadata or {}})
print(json.dumps(out))
"""


def read_run(rid: str) -> dict:
    log = latest_log(rid)
    if not log:
        die(f"run {rid} has no log yet")
    r = subprocess.run([str(VPY), "-c", _READ, str(log)], capture_output=True, text=True)
    if r.returncode != 0:
        die(f"could not read {rid}'s log: {r.stderr.strip()[-300:]}")
    return json.loads(r.stdout)


def short(text: str, n: int = MAX_TEXT) -> str:
    return text if len(text) <= n else text[:n] + " …"


# ── new ───────────────────────────────────────────────────────────────────────────────────────────────────────────
def cmd_new(argv):
    pos, o = args_of(argv, {"--runs": "", "--rubric": "", "--pairwise": False, "--json": False})
    if not pos or not o["runs"] or not o["rubric"].strip():
        die("judge new <name> --runs RUN[,RUN2] --rubric TEXT [--pairwise]", 2, o["json"])
    name = pos[0]
    d = JUDGES / name
    if (d / "judge.json").exists():
        die(f"judge {name} exists (its labels are kept): pick another name", 3, o["json"])
    runs = [x.strip() for x in o["runs"].split(",") if x.strip()]
    mode = "pairwise" if o["pairwise"] else "single"
    if mode == "pairwise" and len(runs) != 2:
        die("--pairwise compares exactly two runs", 2, o["json"])
    data = [read_run(r) for r in runs]
    items = []
    if mode == "single":
        for rid, doc in zip(runs, data):
            for s in doc["samples"]:
                items.append({"id": f"{rid.rsplit('-', 1)[-1]}:{s['id']}:{s['epoch']}", "run": rid, "model": doc["model"],
                              "sample": s["id"], "question": short(s["input"]), "answer": short(s["output"]),
                              "target": short(s["target"], 1000)})
    else:
        b = {(s["id"], s["epoch"]): s for s in data[1]["samples"]}
        for s in data[0]["samples"]:
            t = b.get((s["id"], s["epoch"]))
            if t:
                items.append({"id": f"{s['id']}:{s['epoch']}", "sample": s["id"], "question": short(s["input"]),
                              "a": short(s["output"]), "b": short(t["output"]), "target": short(s["target"], 1000)})
    if not items:
        die("those runs have no answers to judge" + (" on the same questions" if mode == "pairwise" else ""), 3, o["json"])
    d.mkdir(parents=True)
    (d / "items.jsonl").write_text("".join(json.dumps(x) + "\n" for x in items))
    meta = {"name": name, "mode": mode, "rubric": o["rubric"].strip(), "runs": runs,
            "models": [doc["model"] for doc in data], "task": data[0]["task"], "items": len(items), "created": now()}
    (d / "judge.json").write_text(json.dumps(meta, indent=2) + "\n")
    res = dict(meta, folder=str(d))
    if o["json"]:
        print(json.dumps(res))
        return
    print(f"judge {name}: {len(items)} {'pairs' if mode == 'pairwise' else 'answers'} from {', '.join(runs)}")
    print(f"next: label 30 of them yourself: roof eval judge label {name}")


# ── labels ────────────────────────────────────────────────────────────────────────────────────────────────────────
def items_of(d: Path) -> list[dict]:
    return [json.loads(x) for x in (d / "items.jsonl").read_text().splitlines()]


# Where a label came from. Each source has its own file and is measured on its own, never mixed:
#   owner: you (labels.jsonl) · model: a stronger model applying the rubric (labels-model.jsonl, "silver" labels)
#   code: a fact code can check, e.g. the note names a file the real fix changed (labels-code.jsonl)
SOURCES = {"owner": "labels.jsonl", "model": "labels-model.jsonl", "code": "labels-code.jsonl"}


def labels_of(d: Path, source: str = "owner") -> dict[str, dict]:
    """Labels from one source, the latest per item (the files are append-only: a changed mind is a new line)."""
    out = {}
    p = d / SOURCES[source]
    for line in p.read_text().splitlines() if p.exists() else []:
        try:
            x = json.loads(line)
            if x.get("undone"):
                out.pop(x["item"], None)   # a taken-back label (LAB-2066 ⌘Z): the line before it is gone too
                continue
            out[x["item"]] = x
        except (ValueError, KeyError):
            continue
    return out


def add_label(d: Path, item: str, verdict: str, why: str, source: str = "owner", by: str | None = None) -> dict:
    x = {"item": item, "verdict": verdict, "why": why.strip(), "at": now()} | ({"by": by} if by else {})
    with open(d / SOURCES[source], "a") as f:
        f.write(json.dumps(x) + "\n")
    return x


def cmd_label(argv):
    pos, o = args_of(argv, {"--item": "", "--verdict": "", "--why": "", "--undo": False, "--json": False})
    if not pos:
        die("judge label <name> [--item ID --verdict V --why TEXT] [--undo]", 2, o["json"])
    d = jdir(pos[0])
    meta = read_json(d / "judge.json")
    allowed = VERDICTS[meta["mode"]]
    items = {x["id"]: x for x in items_of(d)}
    if o["undo"]:
        mine = sorted(labels_of(d).values(), key=lambda x: x["at"])
        target = o["item"] or (mine[-1]["item"] if mine else "")
        if not target or target not in {x["item"] for x in mine}:
            die("nothing of yours to take back" + (f" on {o['item']}" if o["item"] else ""), 3, o["json"])
        with open(d / SOURCES["owner"], "a") as f:
            f.write(json.dumps({"item": target, "undone": True, "at": now()}) + "\n")
        print(json.dumps({"item": target, "undone": True}) if o["json"] else f"{target}: label taken back")
        return
    if o["item"]:
        if o["item"] not in items:
            die(f"no item {o['item']}", 3, o["json"])
        if o["verdict"] not in allowed:
            die(f"--verdict is one of {', '.join(allowed)}", 2, o["json"])
        x = add_label(d, o["item"], o["verdict"], o["why"])
        print(json.dumps(x) if o["json"] else f"{x['item']}: {x['verdict']}")
        return
    done = labels_of(d)
    todo = [x for x in items.values() if x["id"] not in done]
    keys = "p = pass · f = fail" if meta["mode"] == "single" else "a = A is better · b = B is better · t = tie"
    print(f"Rubric: {meta['rubric']}\n{len(done)} labelled, {len(todo)} to go. {keys} · s = skip · q = quit. "
          "Then a short reason (it becomes the judge's example).\n")
    for x in todo:
        q = x["question"].split("\n\nSource files:\n", 1)[0]   # your own sets: the file list is for the model, not you
        q = re.sub(r"!\[[^\]]*\]\([^)]*\)", "[image]", q)   # a terminal can't show it; the model still got the link
        q = re.sub(r"\n{3,}", "\n\n", q)
        print("─" * 100 + f"\n{x['id']}\nQUESTION\n{short(q, 1500)}\n")
        if meta["mode"] == "single":
            print(f"ANSWER\n{short(x['answer'], 2500)}\n")
        else:
            print(f"A\n{short(x['a'], 2000)}\n\nB\n{short(x['b'], 2000)}\n")
        if x.get("target"):
            print(f"REFERENCE (what the real fix changed, or the expected answer)\n{short(x['target'], 600)}\n")
        while True:
            k = input("verdict> ").strip().lower()[:1]
            if k in ("q", "s") or KEYS.get(k) in allowed:
                break
        if k == "q":
            break
        if k == "s":
            continue
        why = input("why> ")
        add_label(d, x["id"], KEYS[k], why)
    n = len(labels_of(d))
    print(f"\n{n} labelled." + ("" if n >= 30 else f" {30 - n} more for a measured judge (30 recommended)."))


# ── build ─────────────────────────────────────────────────────────────────────────────────────────────────────────
PROMPT_SINGLE = """You are grading an answer against a rubric written by the person who owns this work.

RUBRIC
{rubric}

Graded examples from that person (their verdict and reason):
{examples}

Now grade this one.

QUESTION
{question}

ANSWER
{answer}
{reference}
Think briefly, then end with one line: VERDICT: PASS or VERDICT: FAIL"""

PROMPT_PAIR = """You are comparing two answers to the same question against a rubric written by the person who owns this
work.

RUBRIC
{rubric}

Examples from that person (which answer they preferred and why):
{examples}

Now compare these.

QUESTION
{question}

ANSWER A
{a}

ANSWER B
{b}
{reference}
Think briefly, then end with one line: VERDICT: A, VERDICT: B or VERDICT: TIE"""

TASK_FILE = '''"""Judge {name} v{version}: your rubric and labels as a grader (LAB-1996). Never edited: a rebuild is a new version."""
import json
import re
from pathlib import Path

from inspect_ai import Task, task
from inspect_ai.dataset import Sample
from inspect_ai.scorer import Score, Target, mean, scorer, stderr
from inspect_ai.solver import TaskState, generate

HERE = Path(__file__).resolve().parent
MODE = {mode!r}
WORDS = {{"single": {{"PASS": 1.0, "FAIL": 0.0}}, "pairwise": {{"A": 1.0, "B": 0.0, "TIE": 0.5}}}}[MODE]


def verdict(text: str) -> str | None:
    m = re.findall(r"VERDICT:\\s*(PASS|FAIL|TIE|A|B)\\b", text.upper())
    return m[-1] if m and m[-1] in WORDS else None


@scorer(metrics=[mean(), stderr()])
def judged():
    """Single: 1 = the judge passed the answer. Pairwise: 1 = the first run's answer won (order swapped back), 0.5 tie."""
    async def score(state: TaskState, target: Target) -> Score:
        v = verdict(state.output.completion)
        if v is None:
            return Score(value=0.5 if MODE == "pairwise" else 0.0, answer="(no verdict)",
                         explanation="the judge gave no VERDICT line", metadata=state.metadata)
        if MODE == "pairwise" and state.metadata.get("order") == "ba":
            v = {{"A": "B", "B": "A"}}.get(v, v)   # the answers were shown swapped
        return Score(value=WORDS[v], answer=v, explanation=state.output.completion[-600:], metadata=state.metadata)
    return score


@task
def {func}():
    rows = [json.loads(line) for line in open(HERE / "cases.jsonl")]
    return Task(dataset=[Sample(id=r["id"], input=r["input"], target=r["label"] or "", metadata=r["meta"]) for r in rows],
                solver=[generate()], scorer=judged(), name={func!r})
'''


def example_text(mode: str, items: dict, labels: list[dict]) -> str:
    out = []
    for lb in labels:
        x = items[lb["item"]]
        if mode == "single":
            out.append(f"- QUESTION: {short(x['question'], 600)}\n  ANSWER: {short(x['answer'], 800)}\n"
                       f"  VERDICT: {lb['verdict'].upper()} because {lb['why'] or '(no reason given)'}")
        else:
            out.append(f"- QUESTION: {short(x['question'], 500)}\n  A: {short(x['a'], 500)}\n  B: {short(x['b'], 500)}\n"
                       f"  VERDICT: {lb['verdict'].upper()} because {lb['why'] or '(no reason given)'}")
    return "\n".join(out) or "(none yet)"


def cmd_build(argv):
    pos, o = args_of(argv, {"--examples": "10", "--json": False})
    if not pos:
        die("judge build <name> [--examples 10]", 2, o["json"])
    name, d = pos[0], jdir(pos[0])
    meta = read_json(d / "judge.json")
    draft = d / "rubric-draft.txt"
    if draft.exists() and draft.read_text().strip():   # LAB-2066: an edited rubric goes into the next version only
        meta["rubric"] = draft.read_text().strip()
    items = {x["id"]: x for x in items_of(d)}
    by_src = {src: labels_of(d, src) for src in SOURCES}
    teach = "owner" if by_src["owner"] else "model"   # worked examples carry a reason: yours first, else the model's
    labels = sorted(by_src[teach].values(), key=lambda x: x["at"])
    if not any(by_src.values()):
        die(f"no labels yet: label answers yourself (roof eval judge label {name}) or let code and a model label them "
            f"(roof eval judge autolabel {name} --code --model M)", 3, o["json"])
    k = min(int(o["examples"]), max(len(labels) - MIN_HELD_OUT, 0))
    examples = labels[:k]
    ex_ids = {x["item"] for x in examples}
    held = {i for src in by_src.values() for i in src} - ex_ids
    ex = example_text(meta["mode"], items, examples)
    cases = []
    for x in items.values():
        split = "example" if x["id"] in ex_ids else "held-out" if x["id"] in held else "unlabelled"
        labs = {src: v[x["id"]]["verdict"] for src, v in by_src.items() if x["id"] in v}
        label = labs.get("owner") or labs.get("model")
        ref = f"\nREFERENCE (may help)\n{short(x['target'], 800)}\n" if x.get("target") else ""
        orders = [("ab", x.get("a"), x.get("b")), ("ba", x.get("b"), x.get("a"))] if meta["mode"] == "pairwise" else [("", None, None)]
        for order, first, second in orders:
            prompt = (PROMPT_SINGLE.format(rubric=meta["rubric"], examples=ex, question=x["question"], answer=x["answer"], reference=ref)
                      if meta["mode"] == "single" else
                      PROMPT_PAIR.format(rubric=meta["rubric"], examples=ex, question=x["question"], a=first, b=second, reference=ref))
            cases.append({"id": x["id"] + (f"|{order}" if order else ""), "input": prompt, "label": label,
                          "meta": {"item": x["id"], "split": split, "label": label, "labels": labs, "order": order or None}})
    vs = sorted((p for p in d.glob("v*") if p.name[1:].isdigit()), key=lambda p: int(p.name[1:]))
    body = "".join(json.dumps(c, sort_keys=True) + "\n" for c in cases)
    if vs and (vs[-1] / "cases.jsonl").read_text() == body:
        v, new = int(vs[-1].name[1:]), False
    else:
        v, new = (int(vs[-1].name[1:]) + 1 if vs else 1), True
        vd = d / f"v{v}"
        vd.mkdir()
        func = f"judge_{name}_v{v}"
        (vd / "cases.jsonl").write_text(body)
        (vd / f"{func}.py").write_text(TASK_FILE.format(name=name, version=v, mode=meta["mode"], func=func))
        (vd / "build.json").write_text(json.dumps({"version": v, "task": func, "examples": len(examples),
                                                    "examples_from": teach, "held_out": len(held), "built": now(),
                                                    "rubric": meta["rubric"], "example_items": sorted(ex_ids),
                                                    "label_models": sorted({x.get("by") for x in by_src["model"].values() if x.get("by")})},
                                                   indent=2) + "\n")
    vd = d / f"v{v}"
    tf = vd / (read_json(vd / "build.json")["task"] + ".py")
    if new and draft.exists():   # the draft is now that version's rubric
        j = read_json(d / "judge.json")
        j["rubric"] = meta["rubric"]
        (d / "judge.json").write_text(json.dumps(j, indent=2) + "\n")
        draft.unlink()
    res = {"name": name, "version": v, "new": new, "examples": len(examples), "examples_from": teach,
           "held_out": len(held), "questions": len(cases), "task_file": str(tf),
           "labels": {src: len(v) for src, v in by_src.items()}}
    if o["json"]:
        print(json.dumps(res))
        return
    print(f"judge {name} v{v}{'' if new else ' (unchanged)'}: {len(examples)} {'of your' if teach == 'owner' else 'model'} "
          f"labels as examples, {len(held)} answers held back to measure it (labels: you {res['labels']['owner']}, "
          f"model {res['labels']['model']}, code {res['labels']['code']}), {len(cases)} judge calls")
    if len(held) < MIN_HELD_OUT:
        print(f"only {len(held)} held back: label more (30 recommended) before trusting the agreement")
    print(f"run it: roof eval run '{tf}' --model <judge model> --limit {len(cases)}")


# ── agreement ─────────────────────────────────────────────────────────────────────────────────────────────────────
def rate(hit: int, n: int) -> float | None:
    return round(hit / n, 4) if n else None


def full_metrics(pairs: list[tuple[str, str]]) -> dict:
    pos = [j for j, lb in pairs if lb == "pass"]
    neg = [j for j, lb in pairs if lb == "fail"]
    return {"n": len(pairs), "agreement": rate(sum(j == lb for j, lb in pairs), len(pairs)),
            "tpr": rate(pos.count("pass"), len(pos)), "tnr": rate(neg.count("fail"), len(neg)),
            "label_pass": len(pos), "label_fail": len(neg)}


def agreement_for(rid: str, doc: dict, meta: dict, judge_model: str, label_models: list[str] | None = None) -> dict:
    """Agreement on held-back labels, per source: yours (the measure that counts), a model's (silver: agreement with
    that model, not with you) and code's. Code labels check one fact (does the note point at a changed file), so
    against them only 'fails what code fails' is meaningful: a note pointing nowhere right must not pass."""
    by_item: dict[str, dict] = {}
    for s in doc["samples"]:
        m = s["metadata"] or {}
        labs = m.get("labels") or ({"owner": m["label"]} if m.get("label") else {})
        it = by_item.setdefault(m.get("item", s["id"]), {"split": m.get("split"), "labels": labs, "v": []})
        it["v"].append((s["answer"] or "").lower())
    res = {"run": rid, "judge": meta["name"], "mode": meta["mode"], "judge_model": judge_model, "measured": now()}
    held = {k: x for k, x in by_item.items() if x["split"] == "held-out"}
    if meta["mode"] == "single":
        verdicts = {k: ("pass" if "pass" in x["v"][0] else "fail") for k, x in by_item.items()}
        src = {s: [(verdicts[k], x["labels"][s]) for k, x in held.items() if s in x["labels"]] for s in SOURCES}
        res["by_source"] = {s: full_metrics(src[s]) for s in ("owner", "model") if src[s]}
        if src["code"]:
            neg = [j for j, lb in src["code"] if lb == "fail"]
            pos = [j for j, lb in src["code"] if lb == "pass"]
            res["code"] = {"n": len(src["code"]), "fails_what_code_fails": rate(neg.count("fail"), len(neg)),
                           "code_fail": len(neg), "passes_when_code_passes": rate(pos.count("pass"), len(pos)),
                           "code_pass": len(pos)}
        res["judged_pass_rate"] = rate(sum(v == "pass" for v in verdicts.values()), len(verdicts))
    else:
        winners = {}
        for k, x in by_item.items():
            vs = set(x["v"])
            winners[k] = x["v"][0] if len(x["v"]) == 2 and len(vs) == 1 else "inconsistent"
        consistent = [w for w in winners.values() if w != "inconsistent"]
        res["by_source"] = {}
        for s in ("owner", "model"):
            pairs = [(winners[k], x["labels"][s]) for k, x in held.items() if s in x["labels"]]
            if pairs:
                res["by_source"][s] = {"n": len(pairs), "agreement": rate(sum(w == lb for w, lb in pairs), len(pairs))}
        res.update(position_consistency=rate(len(consistent), len(winners)), a_wins=consistent.count("a"),
                   b_wins=consistent.count("b"), ties=consistent.count("tie"), inconsistent=len(winners) - len(consistent))
    # The headline: your labels once there are enough of them, else the model's, named as such.
    own = res["by_source"].get("owner", {})
    ref = "owner" if own.get("n", 0) >= MIN_HELD_OUT or "model" not in res["by_source"] else "model"
    head = res["by_source"].get(ref, {"n": 0, "agreement": None})
    res.update(reference="you" if ref == "owner" else "model:" + ",".join(label_models or ["?"]),
               n=head["n"], agreement=head.get("agreement"), tpr=head.get("tpr"), tnr=head.get("tnr"))
    answering = [m.split("/", 1)[-1] for m in meta.get("models", [])]
    if judge_model.split("/", 1)[-1] in answering:
        res["self_preference"] = "the judge model also wrote answers it grades: expect it to favour its own"
    if ref == "model" and judge_model.split("/", 1)[-1] in [m.split("/", 1)[-1] for m in (label_models or [])]:
        res["same_as_labeller"] = "the judge is the model that made the labels: agreement says little"
    return res


def judge_of_task(task: str) -> tuple[str, Path] | None:
    """judge_<name>_v<N> → (name, version folder)."""
    if not task.startswith("judge_"):
        return None
    name, _, v = task[len("judge_"):].rpartition("_v")
    d = JUDGES / name / f"v{v}"
    return (name, d) if d.is_dir() else None


def measure(rid: str) -> dict | None:
    doc = read_run(rid)
    j = judge_of_task(doc["task"])
    if not j:
        return None
    meta = read_json(JUDGES / j[0] / "judge.json")
    build = read_json(j[1] / "build.json", {}) or {}
    res = agreement_for(rid, doc, meta, doc["model"], build.get("label_models"))
    res["version"] = int(j[1].name[1:])
    if meta["mode"] == "single":   # each answer's verdict, so the app re-measures against new labels with no new run
        res["verdicts"] = {(s["metadata"] or {}).get("item", s["id"]): ("pass" if "pass" in (s["answer"] or "").lower() else "fail")
                           for s in doc["samples"]}
        res["examples"] = sorted({(s["metadata"] or {}).get("item", s["id"]) for s in doc["samples"]
                                  if (s["metadata"] or {}).get("split") == "example"})
    allr = read_json(AGREEMENTS, {}) or {}
    allr[rid] = res
    JUDGES.mkdir(parents=True, exist_ok=True)
    AGREEMENTS.write_text(json.dumps(allr, indent=2) + "\n")
    return res


def cached(rid: str) -> dict | None:
    return (read_json(AGREEMENTS, {}) or {}).get(rid)


def cmd_agreement(argv):
    pos, o = args_of(argv, {"--run": "", "--json": False})
    if not pos:
        die("judge agreement <name> [--run RUN]", 2, o["json"])
    name, _ = pos[0], jdir(pos[0])
    rid = o["run"]
    if not rid:   # the newest judge run of this judge
        cands = [p.name for p in RUNS.glob(f"*-judge_{name}_v*") if latest_log(p.name)] if RUNS.is_dir() else []
        if not cands:
            die(f"no run of judge {name} yet: roof eval judge build {name}, then roof eval run <task file>", 3, o["json"])
        rid = sorted(cands)[-1]
    res = measure(rid)
    if not res:
        die(f"{rid} is not a run of a judge", 3, o["json"])
    if o["json"]:
        print(json.dumps(res))
        return
    print(render(res))


def render(a: dict) -> str:
    pct = lambda x: "—" if x is None else f"{round(x * 100)} %"
    who = "you" if a.get("reference", "you") == "you" else a["reference"].split(":", 1)[1].split("/")[-1] + "'s labels"
    if a["mode"] == "single":
        s = (f"agrees with {who} on {pct(a['agreement'])} of {a['n']} held-back answers · passes good answers "
             f"{pct(a.get('tpr'))} · fails bad ones {pct(a.get('tnr'))}")
        c = a.get("code")
        if c:
            s += f" · fails {pct(c['fails_what_code_fails'])} of the {c['code_fail']} that point at no changed file (code)"
        s += f" · judged pass rate {pct(a.get('judged_pass_rate'))}"
    else:
        s = (f"agrees with {who} on {pct(a['agreement'])} of {a['n']} held-back pairs · same winner in both orders "
             f"{pct(a['position_consistency'])} · A {a['a_wins']} · B {a['b_wins']} · tie {a['ties']} · "
             f"inconsistent {a['inconsistent']}")
    if a["n"] < MIN_HELD_OUT:
        s += f" · only {a['n']} held back: not yet trustworthy"
    if who != "you":
        s += " · model labels, not yours"
    for k in ("self_preference", "same_as_labeller"):
        if a.get(k):
            s += " · ⚠ " + a[k]
    return s


# ── list / show ───────────────────────────────────────────────────────────────────────────────────────────────────
def summary(d: Path) -> dict:
    meta = read_json(d / "judge.json") or {}
    labels = labels_of(d)
    vs = sorted((p for p in d.glob("v*") if p.name[1:].isdigit()), key=lambda p: int(p.name[1:]))
    runs = {k: v for k, v in (read_json(AGREEMENTS, {}) or {}).items() if v.get("judge") == meta.get("name")}
    last = max(runs.values(), key=lambda x: x["measured"]) if runs else None
    return dict(meta, labelled=len(labels), versions=len(vs), last_agreement=last,
                task_file=str(vs[-1] / (read_json(vs[-1] / "build.json")["task"] + ".py")) if vs else None)


def cmd_list(argv):
    _, o = args_of(argv, {"--json": False})
    js = [summary(d) for d in sorted(JUDGES.glob("*")) if (d / "judge.json").exists()] if JUDGES.is_dir() else []
    if o["json"]:
        print(json.dumps({"judges": js}))
        return
    if not js:
        print("no judges yet: roof eval judge new <name> --runs RUN --rubric TEXT")
    for j in js:
        print(f"{j['name']:<20} {j['mode']:<8} {j['items']} items · {j['labelled']} labelled · "
              + (render(j["last_agreement"]) if j["last_agreement"] else "not run yet"))


def cmd_show(argv):
    pos, o = args_of(argv, {"--json": False})
    if not pos:
        die("judge show <name>", 2, o["json"])
    s = summary(jdir(pos[0]))
    if o["json"]:
        print(json.dumps(s))
        return
    print(f"{s['name']} · {s['mode']} · runs {', '.join(s['runs'])} · {s['items']} items · {s['labelled']} labelled\n"
          f"rubric: {s['rubric']}\n" + (render(s["last_agreement"]) if s["last_agreement"] else "not run yet"))


# ── labels from code and from a model ─────────────────────────────────────────────────────────────────────────────
NAMED = re.compile(r"[\w./+-]+\.\w+")


def code_verdict(answer: str, target: str) -> tuple[str, str]:
    """Pass when one of the first three paths the note names is a file the real fix changed (as the set's own check)."""
    changed = [t for t in target.splitlines() if t.strip()]
    names = []
    for m in NAMED.findall(answer.replace("`", " ")):
        n = m.lstrip("./")
        if n not in names:
            names.append(n)
    hit = next((n for n in names[:3] if any(f == n or f.endswith("/" + n) for f in changed)), None)
    return ("pass", f"names {hit}, changed by the fix") if hit else ("fail", "names none of the files the fix changed")


REFERENCE = '''"""Labeller for judge {name}: the rubric alone, no examples (LAB-1996). Its verdicts become model labels."""
import json
import re
from pathlib import Path

from inspect_ai import Task, task
from inspect_ai.dataset import Sample
from inspect_ai.scorer import Score, Target, mean, scorer
from inspect_ai.solver import TaskState, generate

HERE = Path(__file__).resolve().parent


@scorer(metrics=[mean()])
def verdict():
    async def score(state: TaskState, target: Target) -> Score:
        m = re.findall(r"VERDICT:\\s*(PASS|FAIL)\\b", state.output.completion.upper())
        v = m[-1] if m else None
        return Score(value=1.0 if v == "PASS" else 0.0, answer=v or "(no verdict)", explanation=state.output.completion[-800:])
    return score


@task
def {func}():
    rows = [json.loads(line) for line in open(HERE / "cases.jsonl")]
    return Task(dataset=[Sample(id=r["id"], input=r["input"]) for r in rows], solver=[generate()], scorer=verdict(), name={func!r})
'''


def cmd_autolabel(argv):
    pos, o = args_of(argv, {"--code": False, "--model": "", "--max-cost": "0.50", "--json": False})
    if not pos or not (o["code"] or o["model"]):
        die("judge autolabel <name> [--code] [--model M] [--max-cost 0.50]", 2, o["json"])
    name, d = pos[0], jdir(pos[0])
    meta = read_json(d / "judge.json")
    if meta["mode"] != "single":
        die("autolabel labels single answers (pairwise needs your labels)", 2, o["json"])
    items = items_of(d)
    res = {"name": name}
    if o["code"]:
        done = labels_of(d, "code")
        n = 0
        for x in items:
            if x["id"] not in done and x.get("target"):
                v, why = code_verdict(x["answer"], x["target"])
                add_label(d, x["id"], v, why, "code", "code")
                n += 1
        labs = labels_of(d, "code").values()
        res["code"] = {"added": n, "pass": sum(x["verdict"] == "pass" for x in labs), "fail": sum(x["verdict"] == "fail" for x in labs)}
    if o["model"]:
        if any(o["model"].split("/", 1)[-1] == m.split("/", 1)[-1] for m in meta.get("models", [])):
            die(f"{o['model']} wrote some of these answers: pick another model to label them", 2, o["json"])
        rd = d / "labeller"
        rd.mkdir(exist_ok=True)
        func = f"labeller_{name}"
        cases = [{"id": x["id"], "input": PROMPT_SINGLE.format(rubric=meta["rubric"], examples="(none)", question=x["question"],
                  answer=x["answer"], reference=f"\nREFERENCE (may help)\n{short(x['target'], 800)}\n" if x.get("target") else "")}
                 for x in items]
        (rd / "cases.jsonl").write_text("".join(json.dumps(c) + "\n" for c in cases))
        (rd / f"{func}.py").write_text(REFERENCE.format(name=name, func=func))
        r = subprocess.run([sys.executable, str(Path(__file__).resolve().parent / "roof_eval.py"), "run", str(rd / f"{func}.py"),
                            "--model", o["model"], "--limit", str(len(cases)), "--max-cost", o["max_cost"], "--json"],
                           capture_output=True, text=True)
        try:
            run = json.loads(r.stdout)
        except ValueError:
            die(f"the labelling run did not start: {(r.stderr or r.stdout).strip()[-300:]}", 8, o["json"])
        if run.get("error") or run.get("status") != "done":
            die(f"the labelling run did not finish: {run.get('error') or run.get('status')}", 8, o["json"])
        n = 0
        for s in read_run(run["id"])["samples"]:
            v = (s["answer"] or "").lower()
            if v in ("pass", "fail"):
                why = re.sub(r"\s+", " ", (s["output"] or "").rsplit("VERDICT", 1)[0]).strip()[-300:]
                add_label(d, s["id"], v, why, "model", o["model"])
                n += 1
        labs = labels_of(d, "model").values()
        res["model"] = {"by": o["model"], "run": run["id"], "added": n, "cost": run.get("cost"),
                        "pass": sum(x["verdict"] == "pass" for x in labs), "fail": sum(x["verdict"] == "fail" for x in labs)}
    if o["json"]:
        print(json.dumps(res))
        return
    if "code" in res:
        print(f"code labels: {res['code']['pass']} name a changed file, {res['code']['fail']} do not")
    if "model" in res:
        m = res["model"]
        print(f"model labels by {m['by']}: {m['pass']} pass, {m['fail']} fail (run {m['run']}, "
              f"{'$%.4f' % m['cost'] if m.get('cost') else 'cost in the run'}); these are the model's, not yours")
    print(f"next: roof eval judge build {name}")


# ── the app's judge screen (LAB-2066, HP EV-7) ───────────────────────────────────────────────────────────────────
def code_detail(answer: str, target: str) -> dict:
    """The code check in words: which of the first three named files the fix changed ('files named: 1 of 2 right')."""
    changed = [t for t in target.splitlines() if t.strip()]
    names = []
    for m in NAMED.findall((answer or "").replace("`", " ")):
        n = m.lstrip("./")
        if n not in names:
            names.append(n)
    right = [n for n in names[:3] if any(f == n or f.endswith("/" + n) for f in changed)]
    return {"named": names[:3], "right": len(right), "of": len(changed), "hits": right}


def last_run(name: str) -> dict | None:
    """The newest measured run of this judge (agreements.json), measured from its log once if needed."""
    runs = [v for v in (read_json(AGREEMENTS, {}) or {}).values() if v.get("judge") == name]
    best = max(runs, key=lambda x: x["run"]) if runs else None
    cands = sorted(p.name for p in RUNS.glob(f"*-judge_{name}_v*") if latest_log(p.name)) if RUNS.is_dir() else []
    if cands and (best is None or cands[-1] > best["run"] or "verdicts" not in best):
        try:
            return measure(cands[-1])
        except (Exception, SystemExit):
            return best
    return best


def split_of(item: str, run: dict | None, owner: dict) -> str:
    if run and item in set(run.get("examples") or []):
        return "example"
    return "held back" if item in owner else "unlabelled"


def report_of(question: str) -> tuple[str, str]:
    """('LAB-1931', 'Rail badge count stale after quit\n…'): your sets' questions start 'Bug report (KEY):'."""
    q = question.split("\n\nSource files:\n", 1)[0]
    m = re.match(r"Bug report \(([A-Z][A-Z0-9]+-\d+)\):\n", q)
    return (m.group(1), q[m.end():].strip()) if m else ("", q.strip())


def item_rows(d: Path, run: dict | None = None) -> list[dict]:
    meta = read_json(d / "judge.json")
    labs = {src: labels_of(d, src) for src in SOURCES}
    rows = []
    for x in items_of(d):
        key, report = report_of(x.get("question", ""))
        r = {"id": x["id"], "issue": key, "title": report.split("\n", 1)[0][:160], "report": short(report, 3000),
             "model": x.get("model"), "run": x.get("run"), "answer": x.get("answer") or "", "target": x.get("target") or "",
             "labels": {s: {"verdict": v[x["id"]]["verdict"], "why": v[x["id"]].get("why", ""), "by": v[x["id"]].get("by")}
                        for s, v in labs.items() if x["id"] in v},
             "split": split_of(x["id"], run, labs["owner"]),
             "judge": (run or {}).get("verdicts", {}).get(x["id"])}
        if meta["mode"] == "single" and x.get("target"):
            r["code"] = code_detail(x.get("answer") or "", x["target"])
        else:
            r.pop("target") if meta["mode"] != "single" else None
        if meta["mode"] == "pairwise":
            r.update(a=x.get("a"), b=x.get("b"))
        rows.append(r)
    return rows


def cmd_items(argv):
    pos, o = args_of(argv, {"--json": False})
    if not pos:
        die("judge items <name>", 2, o["json"])
    d = jdir(pos[0])
    rows = item_rows(d, last_run(pos[0]))
    print(json.dumps(rows) if o["json"] else "\n".join(f"{r['id']:<24} {r['split']:<10} {r['title'][:70]}" for r in rows))


def queue_order(rows: list[dict], first: str = "") -> list[dict]:
    """Unlabelled by you; likely fails first (the judge passed it but code says no changed file was named), then the
    rest where code failed, then the others (HP EV-7). `first` (from one run's 'Label for the judge') goes on top."""
    todo = [r for r in rows if "owner" not in r["labels"]]
    def rank(r):
        code_fail = (r.get("code") or {}).get("right", 1) == 0 if r.get("code") else False
        return (0 if r["id"] == first else 1, 0 if (r.get("judge") == "pass" and code_fail) else 1 if code_fail else 2)
    return sorted(todo, key=rank)


def cmd_queue(argv):
    pos, o = args_of(argv, {"--first": "", "--json": False})
    if not pos:
        die("judge queue <name> [--first ID]", 2, o["json"])
    d = jdir(pos[0])
    rows = item_rows(d, last_run(pos[0]))
    q = queue_order(rows, o["first"])
    print(json.dumps({"total": len(rows), "labelled": sum("owner" in r["labels"] for r in rows), "queue": q}) if o["json"]
          else "\n".join(f"{r['id']:<24} judge={r.get('judge') or '-':<5} {r['title'][:70]}" for r in q))


def trust(name: str) -> dict:
    """How far to trust the judge now: its last run's verdicts against your labels as they are today (no new run).
    Your labels on its examples are left out; everything else you labelled is held back from it."""
    d = jdir(name)
    meta = read_json(d / "judge.json")
    run = last_run(name)
    labs = {src: labels_of(d, src) for src in SOURCES}
    owner = labs["owner"]
    examples = set((run or {}).get("examples") or [])
    res = {"name": name, "mode": meta["mode"], "items": len(items_of(d)), "labelled": len(owner),
           "to_label": len(items_of(d)) - len(owner), "examples": len(examples), "run": (run or {}).get("run"),
           "judge_model": (run or {}).get("judge_model"), "version": (run or {}).get("version"), "min_held": MIN_HELD_OUT}
    if not run or "verdicts" not in run:
        res.update(n=0, agreement=None, tpr=None, tnr=None, ready=False, reference="you",
                   reading="The judge has not run yet: build it, then run it to measure it.")
        return res
    v = run["verdicts"]
    by = {}
    for src in ("owner", "model"):
        pairs = [(v[i], x["verdict"]) for i, x in labs[src].items() if i in v and i not in examples]
        if pairs:
            by[src] = full_metrics(pairs)
    own = by.get("owner", {"n": 0})
    ref = "owner" if own["n"] >= MIN_HELD_OUT or "model" not in by else "model"
    head = by.get(ref, {"n": 0})
    res.update(by_source=by, reference="you" if ref == "owner" else "model", n=head["n"], agreement=head.get("agreement"),
               tpr=head.get("tpr"), tnr=head.get("tnr"), label_pass=head.get("label_pass", 0), label_fail=head.get("label_fail", 0),
               held_back_yours=own["n"], judged_pass_rate=rate(sum(x == "pass" for x in v.values()), len(v)))
    if run.get("self_preference"):
        res["self_preference"] = run["self_preference"]
    rates = [x for x in (res["tpr"], res["tnr"]) if x is not None]
    res["ready"] = ref == "owner" and own["n"] >= MIN_HELD_OUT and bool(rates) and min(rates) >= 0.7
    tnr, tpr = res["tnr"], res["tpr"]
    who = "you" if ref == "owner" else "the model's labels"
    if res["n"] == 0:
        res["reading"] = "No labels held back from it yet: label answers to measure it."
    elif tnr is not None and tnr < 0.7 and (tpr is None or tnr <= tpr):
        res["reading"] = (f"It's lenient: it passes {round((1 - tnr) * 100)} % of the answers {who} failed, so judged scores "
                          "read high.")
    elif tpr is not None and tpr < 0.7:
        res["reading"] = f"It's strict: it fails {round((1 - tpr) * 100)} % of the answers {who} passed, so judged scores read low."
    else:
        res["reading"] = f"It agrees with {who} on {round((res['agreement'] or 0) * 100)} % of the held-back answers."
    if own["n"] < MIN_HELD_OUT:
        res["reading"] += f" Too few of your labels to trust: label {MIN_HELD_OUT - own['n']} more."
    elif not res["ready"]:
        res["reading"] += " Not ready to stand in for you."
    return res


def cmd_trust(argv):
    pos, o = args_of(argv, {"--json": False})
    if not pos:
        die("judge trust <name>", 2, o["json"])
    t = trust(pos[0])
    print(json.dumps(t) if o["json"] else t["reading"])


def advise(name: str) -> list[str]:
    """What would help, in order: label where it is weakest, tighten the rubric where it disagrees, rebuild."""
    t = trust(name)
    d = jdir(name)
    out = []
    if t["to_label"]:
        tnr, tpr = t.get("tnr"), t.get("tpr")
        weak = ("" if tnr is None or tpr is None else
                "mostly fails, where it's weakest" if tnr < tpr else "mostly passes, where it's weakest")
        out.append(f"Label the {t['to_label']} waiting answers" + (f" ({weak})" if weak else "") + ".")
    if t.get("tnr") is not None and t["tnr"] < 0.7:
        out.append("Tighten the rubric's fail side: say what a vague or wrong-file answer looks like.")
    if t.get("tpr") is not None and t["tpr"] < 0.7:
        out.append("Loosen the rubric's pass side: say which partly right answers still pass.")
    vs = [p for p in d.glob("v*") if p.name[1:].isdigit()]
    if t["labelled"] >= MIN_HELD_OUT:
        out.append(f"Then rebuild it as v{len(vs) + 1} so your labels become its examples.")
    if t.get("self_preference"):
        out.append("Use a judge model that wrote none of the answers.")
    return out or ["Nothing pressing: it agrees with you well enough to stand in."]


def cmd_advise(argv):
    pos, o = args_of(argv, {"--json": False})
    if not pos:
        die("judge advise <name>", 2, o["json"])
    a = advise(pos[0])
    print(json.dumps({"advice": a}) if o["json"] else "\n".join(a))


def cmd_rubric(argv):
    pos, o = args_of(argv, {"--set": "", "--json": False})
    if not pos:
        die("judge rubric <name> [--set TEXT]", 2, o["json"])
    d = jdir(pos[0])
    if o["set"].strip():
        (d / "rubric-draft.txt").write_text(o["set"].strip() + "\n")
    draft = (d / "rubric-draft.txt").read_text().strip() if (d / "rubric-draft.txt").exists() else None
    res = {"current": read_json(d / "judge.json")["rubric"], "draft": draft}
    print(json.dumps(res) if o["json"] else f"current: {res['current']}\ndraft: {res['draft'] or '(none)'}")


def cmd_versions(argv):
    pos, o = args_of(argv, {"--json": False})
    if not pos:
        die("judge versions <name>", 2, o["json"])
    d = jdir(pos[0])
    meta = read_json(d / "judge.json")
    agr = [v for v in (read_json(AGREEMENTS, {}) or {}).values() if v.get("judge") == pos[0]]
    rows = []
    for vd in sorted((p for p in d.glob("v*") if p.name[1:].isdigit()), key=lambda p: int(p.name[1:])):
        b = read_json(vd / "build.json", {}) or {}
        v = int(vd.name[1:])
        mine = [a for a in agr if a.get("version") == v or a["run"].find(f"judge_{pos[0]}_v{v}") >= 0]
        last = max(mine, key=lambda a: a["run"]) if mine else None
        rows.append({"version": v, "built": b.get("built"), "rubric": b.get("rubric") or (meta["rubric"] if v == 1 else None),
                     "examples": b.get("examples"), "examples_from": b.get("examples_from"), "held_out": b.get("held_out"),
                     "runs": len(mine), "agreement": (last or {}).get("agreement"), "reference": (last or {}).get("reference")})
    draft = d / "rubric-draft.txt"
    print(json.dumps({"name": pos[0], "versions": rows, "draft": draft.read_text().strip() if draft.exists() else None})
          if o["json"] else "\n".join(f"v{r['version']} · {r['examples']} examples · {r['held_out']} held back · {r['runs']} runs" for r in rows))


COMMANDS = {"items": cmd_items, "queue": cmd_queue, "trust": cmd_trust, "advise": cmd_advise, "rubric": cmd_rubric,
            "versions": cmd_versions, "autolabel": cmd_autolabel, "new": cmd_new, "label": cmd_label, "build": cmd_build, "agreement": cmd_agreement, "list": cmd_list,
            "show": cmd_show}

if __name__ == "__main__":
    if len(sys.argv) < 2 or sys.argv[1] not in COMMANDS:
        print(__doc__)
        sys.exit(0 if len(sys.argv) < 2 else 2)
    COMMANDS[sys.argv[1]](sys.argv[2:])
