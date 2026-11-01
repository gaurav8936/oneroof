#!/usr/bin/env python3
"""Published best scores (LAB-2063, EVO-3): what the best models and agents score on a benchmark, from ONE official
source per benchmark, each value with its source and the date it was checked.

  scores refresh [--only <benchmark>] [--json]     fetch every source in score_sources.json (weekly loop: published-scores)
  scores show <benchmark or task> [--auto] [--json]  the stored scores; --auto refreshes first when older than 7 days

Sources (score_sources.json) are the benchmark's own leaderboard, else its makers' or a model maker's published results;
never an aggregator. Values are parsed from the page; a row without a score, a source URL or a date is dropped, never
guessed. A failed check keeps the last good values and says when and why it failed. Public pages only: no key, nothing
sent but the request. Stored in <evals>/published_scores.json. Standard library only (Python 3.9).
"""
from __future__ import annotations

import json
import os
import re
import sys
import urllib.request
from datetime import datetime, timezone
from pathlib import Path

HERE = Path(__file__).resolve().parent
EVALS = Path(os.environ.get("ONEROOF_EVALS_DIR") or Path.home() / "Library/Application Support/One Roof/evals")
STORE = EVALS / "published_scores.json"
SOURCES = HERE / "score_sources.json"
MAX_AGE_DAYS = 7
STALE_DAYS = 30
KEEP = 10   # best rows kept per benchmark


def now() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def today() -> str:
    return now()[:10]


def die(msg: str, code: int = 1, as_json: bool = False):
    if as_json:
        print(json.dumps({"error": msg, "code": code}))
    else:
        print(f"roof eval scores: {msg}", file=sys.stderr)
    sys.exit(code)


def read_json(p: Path, default=None):
    try:
        return json.loads(p.read_text())
    except (OSError, ValueError):
        return default


def write_json(p: Path, obj) -> None:
    p.parent.mkdir(parents=True, exist_ok=True)
    tmp = p.with_suffix(p.suffix + ".tmp")
    tmp.write_text(json.dumps(obj, indent=2, sort_keys=True))
    tmp.replace(p)


def sources() -> dict:
    return (read_json(SOURCES, {}) or {}).get("sources", {})


def fetch(url: str) -> str:
    req = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0 (One Roof published-scores check)"})
    with urllib.request.urlopen(req, timeout=30) as r:
        return r.read().decode("utf-8", errors="replace")


def num(x) -> float | None:
    try:
        v = float(str(x).strip().rstrip("%"))
    except (TypeError, ValueError):
        return None
    return v / 100 if v > 1 else v


def clean(name: str) -> str:
    name = re.sub(r"\[\^[^\]]*\]", "", name)        # markdown footnotes
    name = re.sub(r"<[^>]+>", "", name)
    return re.sub(r"\s+", " ", name.replace("**", "")).strip()


# ── parsers: page text → [{contestant, score (0…1), published?, setting?}] ─────────────────────────────────────────────
def parse_swebench_json(text: str, src: dict) -> list[dict]:
    d = json.loads(text)
    board = next((b for b in d.get("leaderboards", []) if b.get("name") == src.get("board", "Verified")), None)
    rows = []
    for e in (board or {}).get("results", []):
        s = num(e.get("resolved"))
        if s is None or not e.get("name"):
            continue
        rows.append({"contestant": clean(e["name"]), "score": s, "published": e.get("date"),
                     "model": e.get("model_display")})
    return rows


SCALE_ROW = re.compile(r'data-model-name="true"[^>]*title="([^"]+)".*?<span class="text-ink">([\d.]+)</span>'
                       r'(?:<span class="text-neutral-600">±(?:<!-- -->)?([\d.]+)</span>)?', re.S)


def parse_scale_html(text: str, src: dict) -> list[dict]:
    rows = []
    for name, score, pm in SCALE_ROW.findall(text):
        s = num(score)
        if s is not None:
            rows.append({"contestant": clean(name), "score": s, "plus_minus": num(pm) if pm else None})
    return rows


def cells(row: str) -> list[str]:
    return [clean(c) for c in re.findall(r"<t[dh][^>]*>(.*?)(?=<t[dh]|</tr|$)", row, re.S)]


def parse_html_table_row(text: str, src: dict) -> list[dict]:
    """A model card's results table: the header names the models; the row named src['row'] holds their scores."""
    label = src["row"]
    for tab in re.findall(r"<table.*?</table>", text, re.S):
        trs = re.split(r"<tr[^>]*>", tab)[1:]
        if len(trs) < 2:
            continue
        head = cells(trs[0])
        for tr in trs[1:]:
            c = cells(tr)
            if label not in c:
                continue
            vals = c[c.index(label) + 1:]
            models = [h for h in head if num(h) is None and re.search(r"\d", h)]   # 'Llama 3.1 405B Instruct'
            scores = [v for v in vals if num(v) is not None or v == "-"]
            scores = scores[-len(models):] if models else []
            shots = vals[0] if vals and vals[0].isdigit() else None
            rows = []
            for m, v in zip(models, scores):
                s = num(v)
                if s is not None:
                    rows.append({"contestant": m, "score": s,
                                 "setting": src.get("setting") or (f"{shots}-shot, {label}" if shots else label)})
            return rows
    return []


def parse_md_table_column(text: str, src: dict) -> list[dict]:
    """A Markdown table: the first column names the model; the column whose header starts with src['column']."""
    lines = [x for x in text.splitlines() if x.strip().startswith("|")]
    rows, col = [], None
    for x in lines:
        c = [clean(v) for v in x.strip().strip("|").split("|")]
        if col is None:
            hit = [i for i, h in enumerate(c) if h.split(" ")[0].startswith(src["column"])]
            if hit:
                col = hit[0]
            continue
        if set("".join(c)) <= set(":- "):
            continue
        if col < len(c) and num(c[col]) is not None and c[0]:
            rows.append({"contestant": c[0], "score": num(c[col])})
    return rows


PARSERS = {"swebench_json": parse_swebench_json, "scale_html": parse_scale_html,
           "html_table_row": parse_html_table_row, "md_table_column": parse_md_table_column}


def rows_for(key: str, src: dict, text: str, checked: str) -> list[dict]:
    """Parsed rows, each carrying its source and date; best first; at most KEEP. Rows missing a field are dropped."""
    out = []
    for r in PARSERS[src["parser"]](text, src):
        row = {"contestant": r["contestant"], "kind": src.get("kind", "model"), "score": round(r["score"], 4),
               "metric": src.get("metric", "accuracy"), "setting": r.get("setting") or src.get("setting"),
               "source_url": src["url"], "source_name": src["name"], "published": r.get("published"), "checked": checked}
        if r.get("plus_minus") is not None:
            row["plus_minus"] = round(r["plus_minus"], 4)
        if valid(row):
            out.append(row)
    seen, best = set(), []
    for r in sorted(out, key=lambda r: -r["score"]):
        if r["contestant"] not in seen:
            seen.add(r["contestant"])
            best.append(r)
    return best[:KEEP]


def valid(row: dict) -> bool:
    return bool(row.get("contestant")) and isinstance(row.get("score"), (int, float)) and 0 <= row["score"] <= 1 \
        and str(row.get("source_url", "")).startswith("https://") and bool(row.get("checked"))


def refresh(only: str | None = None, get=fetch) -> dict:
    """Check every source; a source that fails (network, page changed, nothing parsed) keeps its last good rows."""
    doc = read_json(STORE, {}) or {}
    doc.setdefault("benchmarks", {})
    doc.setdefault("failures", {})
    checked = today()
    cache: dict = {}
    for key, src in sources().items():
        if only and key != only and only not in src.get("tasks", []):
            continue
        try:
            if src["url"] not in cache:
                cache[src["url"]] = get(src["url"])
            rows = rows_for(key, src, cache[src["url"]], checked)
            if not rows:
                raise ValueError("the page had no scores this check could read (it may have changed)")
            doc["benchmarks"][key] = rows
            doc["failures"].pop(key, None)
        except Exception as e:   # keep the last good rows; say what happened
            doc["failures"][key] = {"date": checked, "reason": str(e)[:200]}
    doc["checked"] = now()
    write_json(STORE, doc)
    return doc


def resolve(name: str) -> str | None:
    s = sources()
    if name in s:
        return name
    return next((k for k, v in s.items() if name in v.get("tasks", [])), None)


def age_days(iso: str | None) -> float | None:
    if not iso:
        return None
    try:
        t = datetime.strptime(iso[:10], "%Y-%m-%d").replace(tzinfo=timezone.utc)
    except ValueError:
        return None
    return (datetime.now(timezone.utc) - t).total_seconds() / 86400


def show(name: str) -> dict:
    key = resolve(name)
    doc = read_json(STORE, {}) or {}
    src = sources().get(key) if key else None
    rows = (doc.get("benchmarks") or {}).get(key, []) if key else []
    for r in rows:
        a = age_days(r.get("checked"))
        r["stale"] = a is not None and a > STALE_DAYS
    return {"benchmark": key or name, "has_source": src is not None,
            "source": {"name": src["name"], "url": src["url"]} if src else None,
            "rows": rows, "checked": doc.get("checked"), "failed": (doc.get("failures") or {}).get(key) if key else None}


def headroom(name: str) -> dict | None:
    """How far the best published score is from the top: Saturated (≥ 90 %), Some, or Lots (≤ 60 %)."""
    s = show(name)
    if not s["rows"]:
        return None
    best = s["rows"][0]
    v = best["score"]
    level = "saturated" if v >= 0.9 else "lots" if v <= 0.6 else "some"
    text = {"saturated": "Saturated · best > 90 %", "lots": "Lots · far from max", "some": f"Some · best {round(v * 100)} %"}[level]
    return {"level": level, "text": text, "best": v, "contestant": best["contestant"], "source_name": best["source_name"],
            "checked": best["checked"]}


def cmd_refresh(argv):
    o = {"only": None, "json": "--json" in argv}
    if "--only" in argv:
        o["only"] = argv[argv.index("--only") + 1]
    doc = refresh(o["only"])
    res = {"checked": doc["checked"], "benchmarks": {k: len(v) for k, v in doc["benchmarks"].items()}, "failures": doc["failures"]}
    if o["json"]:
        print(json.dumps(res))
        return
    for k, n in sorted(res["benchmarks"].items()):
        print(f"{k:<14} {n} scores" + (f"  (last check failed: {res['failures'][k]['reason']})" if k in res["failures"] else ""))
    for k in sorted(set(res["failures"]) - set(res["benchmarks"])):
        print(f"{k:<14} no scores: {res['failures'][k]['reason']}")


def cmd_show(argv):
    as_json = "--json" in argv
    pos = [a for a in argv if not a.startswith("--")]
    if len(pos) != 1:
        die("scores show <benchmark or task> [--auto] [--json]", 2, as_json)
    if "--auto" in argv:
        doc = read_json(STORE, {}) or {}
        a = age_days(doc.get("checked"))
        if a is None or a > MAX_AGE_DAYS:
            try:
                refresh()
            except Exception:
                pass   # offline: the last good file stays
    s = show(pos[0])
    if as_json:
        print(json.dumps(s))
        return
    if not s["rows"]:
        print(f"{s['benchmark']}: no published score yet" + (f" (source: {s['source']['name']})" if s["source"] else ""))
    for r in s["rows"]:
        print(f"{r['contestant']:<44} {r['score'] * 100:5.1f} %  {r['source_name']} · checked {r['checked']}")


COMMANDS = {"refresh": cmd_refresh, "show": cmd_show}

if __name__ == "__main__":
    if len(sys.argv) < 2 or sys.argv[1] not in COMMANDS:
        print(__doc__)
        sys.exit(0 if len(sys.argv) < 2 else 2)
    COMMANDS[sys.argv[1]](sys.argv[2:])
