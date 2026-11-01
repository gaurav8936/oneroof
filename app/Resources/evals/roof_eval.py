#!/usr/bin/env python3
"""One Roof eval engine (LAB-EVALS). `roof eval <command>`; the Evals place calls the same commands with --json.

The engine is Inspect AI + inspect_evals, installed with uv into One Roof's own folder and never linked into the app
(ADR docs/decisions/20261031_02_eval-engine-inspect.md). This file runs on the system python3 with the standard library
only; the few steps that need Inspect re-run this file under the engine's own python (`_catalog`, `_index`).

  setup [--repair]                 install or repair the engine (uv venv + pinned requirements.txt)
  doctor [--json]                  engine, versions, Docker, which providers have a key (names only)
  catalog [--refresh] [--json]     every installed benchmark, the starter shelf first
  providers [--json]               provider → key source;  providers set <provider> --key-file PATH
  prices [--refresh]               live per-million prices (OpenRouter's public list), dated
  estimate <task> --model M [--limit N] [--epochs E] [--json]
  run <task> --model M [--limit 50] [--epochs 1] [--seed 42] [--temperature T] [--max-cost 2] [--background] [--json]
      [--where local|daytona|modal]   where code-running benchmarks execute (cloud sandboxes need no Docker here)
      [--agent claude_code|codex_cli|gemini_cli|kimi_code|opencode|antigravity|mini_swe_agent]   the real agent CLI is the subject
      [--parallel N]   questions (and containers) at once; agent runs default to 2
  status [--json]   cancel <run>   resume <run>   results [<run>] [--json]   index
  samples <run> [--json]           every question: id, attempt, score, answer, target, time, tokens
  sample <run> <id> [--epoch N] [--json]   one question's full transcript (messages, tool calls, scorer's reasoning)
  export [--format csv|json] [--out FILE]  every run with its metrics and 95 % intervals
  xray --repo PATH [--repo …] [--days 30] [--horizon 14] [--json]   agent X-ray from git: churn, reverts, fix-ups
  Runs started with --background wait for a free slot (ONEROOF_EVALS_SLOTS, default 2), so a queue of runs survives
  closing One Roof.

Data: ~/Library/Application Support/One Roof/evals (ONEROOF_EVALS_DIR overrides; tests use it).
Keys: never stored here. providers.json holds the path of a key file you chose; the key is read at run time and given
to the run's process environment only. Logs never contain it.
"""
from __future__ import annotations

import json
import math
import os
import random
import re
import shutil
import signal
import sqlite3
import string
import subprocess
import sys
import time
import urllib.request
import zipfile
from datetime import datetime, timezone
from pathlib import Path

HERE = Path(__file__).resolve().parent
EVALS = Path(os.environ.get("ONEROOF_EVALS_DIR") or Path.home() / "Library/Application Support/One Roof/evals")
VENV = EVALS / "venv"
VPY = VENV / "bin/python"
INSPECT = VENV / "bin/inspect"
RUNS = EVALS / "runs"
DB = EVALS / "evals.db"
PRICES = EVALS / "prices.json"
PROVIDERS = EVALS / "providers.json"
CATALOG = EVALS / "catalog.json"
PRICE_SOURCE = "https://openrouter.ai/api/v1/models"
PRICE_MAX_AGE_DAYS = 7

# Inspect provider prefix → the environment variable its client reads. Empty: needs no key.
PROVIDER_ENV = {
    "anthropic": "ANTHROPIC_API_KEY", "openai": "OPENAI_API_KEY", "google": "GOOGLE_API_KEY",
    "openrouter": "OPENROUTER_API_KEY", "fireworks": "FIREWORKS_API_KEY", "together": "TOGETHER_API_KEY",
    "mistral": "MISTRAL_API_KEY", "grok": "XAI_API_KEY", "groq": "GROQ_API_KEY", "deepseek": "DEEPSEEK_API_KEY",
    # Cloud sandboxes (not models): where code-running benchmarks execute. Modal signs in with `modal setup` instead.
    "daytona": "DAYTONA_API_KEY", "e2b": "E2B_API_KEY",
}
# Where a benchmark that runs code executes: this Mac's Docker, or a cloud sandbox (inspect-sandboxes).
WHERE = {"local": None, "daytona": "daytona", "modal": "modal"}
MODAL_IMAGE_BUILDER = "2025.06"
# Cloud sandbox prices, USD per hour, checked live 2026-10-31 (daytona.io/pricing, modal.com/pricing; Modal's sandbox
# rate is its non-preemptible rate). Estimates assume 1 vCPU + 2 GiB per sandbox, billed per second.
SANDBOX_RATES = {
    "daytona": {"vcpu_hour": 0.0504, "gib_hour": 0.0162, "source": "https://www.daytona.io/pricing", "checked": "2026-10-31"},
    "modal": {"vcpu_hour": 0.00003942 * 3600, "gib_hour": 0.00000667 * 3600, "source": "https://modal.com/pricing", "checked": "2026-10-31"},
}
SANDBOX_SHAPE = {"vcpu": 1, "gib": 2}
DEFAULT_SANDBOX_SECONDS = 120   # per question, until this Mac has measured the benchmark
GRADER_MARGIN = 1.5
# Coding agents that can be the subject of a run (inspect-swe): the real CLI runs inside the benchmark's sandbox and
# calls the chosen model through Inspect, so "Claude Code on Haiku" and "Haiku alone" are separate, comparable runs.
AGENTS = ["claude_code", "codex_cli", "gemini_cli", "kimi_code", "opencode", "antigravity", "mini_swe_agent"]
# Agent loops read whole files and call tools many times: per-task token guess until this Mac has measured one.
AGENT_DEFAULT_TOKENS = {"input": 300000, "output": 15000}             # grader cost varies per answer and is not capped mid-run, so the pre-run check pads it


def where_ready(where: str) -> bool:
    if where == "local":
        return True
    if where == "modal":
        return (Path.home() / ".modal.toml").exists() or bool(os.environ.get("MODAL_TOKEN_ID"))
    return read_key(where) is not None or bool(os.environ.get(PROVIDER_ENV[where]))
FREE_PREFIXES = ("mockllm/", "ollama/", "openai-api/local/", "hf/", "llama-cpp-python/", "vllm/", "sglang/")
# Used only until this Mac has measured a task: typical prompt and answer sizes, labelled as a guess.
DEFAULT_TOKENS = {"input": 1000, "output": 500}


# ── small helpers ──────────────────────────────────────────────────────────────────────────────────────────────────
def now() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def out(obj, as_json: bool, text: str | None = None) -> None:
    print(json.dumps(obj, indent=2, sort_keys=True) if as_json else (text if text is not None else obj))


def die(msg: str, code: int = 1, as_json: bool = False):
    if as_json:
        print(json.dumps({"error": msg, "code": code}))
    else:
        print(f"roof eval: {msg}", file=sys.stderr)
    sys.exit(code)


KEYLIKE = re.compile(r"(sk-[A-Za-z0-9_*\-]{4,}|AIza[0-9A-Za-z_\-]{10,}|fw_[A-Za-z0-9]{10,}|"
                     r"(?i:api[_ ]?key(?: provided)?[:= ]+)\S+)")


HINTS = [
    (re.compile(r"gated (dataset|repo)|GatedRepoError|must be authenticated", re.I),
     "This dataset is gated on Hugging Face: sign in once (hf auth login, or HF_TOKEN) and accept the dataset's terms on its page."),
    (re.compile(r"optional dependenc|pip install", re.I),
     "This benchmark needs an extra package: roof eval setup --extra <benchmark folder>."),
    (re.compile(r"requires (\d+) epochs", re.I),
     "This benchmark scores several attempts per question: leave --epochs unset or raise it."),
    (re.compile(r"401|Incorrect API key|AuthenticationError|invalid x-api-key", re.I),
     "A provider rejected the key. If the model under test has a valid key, this is the grader model: set its key, or "
     "choose the grader with --task-args judge_llm=<model> (name varies per benchmark)."),
    (re.compile(r"docker|sandbox", re.I), "This benchmark runs code in a sandbox: start Docker (or see LAB-2000 for hosted options)."),
]


def hint_for(err: str | None) -> str | None:
    for pat, hint in HINTS:
        if err and pat.search(err):
            return hint
    return None


def redact(text: str | None) -> str | None:
    """Errors from providers can echo a masked key; nothing key-like is stored or shown by One Roof."""
    return KEYLIKE.sub("[redacted]", text) if text else text


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


def args_of(argv: list[str], flags: dict[str, object]) -> tuple[list[str], dict]:
    """Tiny flag parser: flags maps '--name' → default (bool default ⇒ switch)."""
    opts = {k.lstrip("-").replace("-", "_"): v for k, v in flags.items()}
    pos, i = [], 0
    while i < len(argv):
        a = argv[i]
        if a in flags:
            key = a.lstrip("-").replace("-", "_")
            if isinstance(flags[a], bool):
                opts[key] = True
            else:
                if i + 1 >= len(argv):
                    die(f"{a} needs a value", 2)
                i += 1
                opts[key] = argv[i]
        elif a.startswith("--"):
            die(f"unknown option {a}", 2)
        else:
            pos.append(a)
        i += 1
    return pos, opts


def find_uv() -> str | None:
    for c in (shutil.which("uv"), "/opt/homebrew/bin/uv", "/usr/local/bin/uv", str(Path.home() / ".local/bin/uv")):
        if c and os.access(c, os.X_OK):
            return c
    return None


def engine_ready() -> bool:
    return VPY.exists() and INSPECT.exists()


def need_engine(as_json=False):
    if not engine_ready():
        die("the eval engine is not installed: run `roof eval setup`", 4, as_json)


def task_ref(task: str) -> str:
    """'gsm8k' → 'inspect_evals/gsm8k'; full refs and file paths pass through."""
    return task if ("/" in task or task.endswith(".py")) else f"inspect_evals/{task}"


def task_name(task: str) -> str:
    return task.rsplit("/", 1)[-1].removesuffix(".py")


# ── setup / doctor ─────────────────────────────────────────────────────────────────────────────────────────────────
def cmd_setup(argv):
    _, o = args_of(argv, {"--repair": False, "--extra": "", "--json": False})
    uv = find_uv()
    if not uv:
        die("uv is not installed. Install it once with `brew install uv`, then run `roof eval setup` again.", 5, o["json"])
    EVALS.mkdir(parents=True, exist_ok=True)
    if o["repair"] and VENV.exists():
        shutil.rmtree(VENV)
    if not VPY.exists():
        subprocess.run([uv, "venv", "--quiet", "--python", "3.12", str(VENV)], check=True)
    env = dict(os.environ, VIRTUAL_ENV=str(VENV))
    subprocess.run([uv, "pip", "install", "--quiet", "-r", str(HERE / "requirements.txt")], check=True, env=env)
    install_extras(sorted(set(STARTER_EXTRAS) | {x for x in o["extra"].split(",") if x}), uv)
    info = engine_info()
    write_json(EVALS / "engine.json", dict(read_json(EVALS / "engine.json", {}) or {}, **info, installed=now()))
    out(info, o["json"], f"eval engine ready: inspect-ai {info.get('inspect_ai')} · inspect-evals {info.get('inspect_evals')} · {EVALS}")


# Optional packages some starter benchmarks need (inspect-evals extras); setup installs them with the engine.
STARTER_EXTRAS = ["ifeval", "math", "niah", "bfcl", "gaia"]
# Extras whose dependency is not on PyPI: installed from source at a pinned commit first (Apache-2.0).
EXTRA_SOURCES = {"ifeval": "instruction_following_eval @ git+https://github.com/josejg/instruction_following_eval"
                           "@0c495b2f95155e8b10acb919ae283bfb4d5be6e2"}


def pinned(name: str) -> str:
    for line in (HERE / "requirements.txt").read_text().splitlines():
        if line.startswith(name + "=="):
            return line.split("==", 1)[1].strip()
    return ""


def installed_extras() -> list[str]:
    return (read_json(EVALS / "engine.json", {}) or {}).get("extras", [])


def install_extras(extras: list[str], uv: str | None = None) -> None:
    """inspect-evals[<extra>] at the pinned version; extra names use dashes (eval.yaml may say swe_bench)."""
    extras = [x.replace("_", "-") for x in extras if x]
    if not extras:
        return
    uv = uv or find_uv()
    if not uv:
        die("uv is not installed (brew install uv)", 5)
    env = dict(os.environ, VIRTUAL_ENV=str(VENV))
    done, failed = [], {}
    for x in extras:  # one at a time: one broken extra must not block the others
        steps = ([[uv, "pip", "install", "--quiet", EXTRA_SOURCES[x]]] if x in EXTRA_SOURCES else []) + \
                [[uv, "pip", "install", "--quiet", f"inspect-evals[{x}]=={pinned('inspect-evals')}"]]
        for cmd in steps:
            r = subprocess.run(cmd, capture_output=True, text=True, env=env)
            if r.returncode != 0:
                failed[x] = (r.stderr.strip().splitlines() or ["install failed"])[-1][:300]
                break
        else:
            done.append(x)
    info = read_json(EVALS / "engine.json", {}) or {}
    info["extras"] = sorted(set(info.get("extras", [])) | set(done))
    info["extras_failed"] = failed
    write_json(EVALS / "engine.json", info)
    for x, why in failed.items():
        print(f"roof eval: extra '{x}' did not install: {why}", file=sys.stderr)


def catalog_entry(task: str) -> dict | None:
    for b in build_catalog().get("benchmarks", []):
        if any(t["name"] == task_name(task) for t in b["tasks"]):
            return b
    return None


def engine_info() -> dict:
    if not engine_ready():
        return {"ready": False, "dir": str(EVALS)}
    code = ("import json,importlib.metadata as m;print(json.dumps({p.replace('-','_'):m.version(p) "
            "for p in ('inspect-ai','inspect-evals')}))")
    r = subprocess.run([str(VPY), "-c", code], capture_output=True, text=True)
    v = json.loads(r.stdout) if r.returncode == 0 else {}
    return dict(v, ready=r.returncode == 0, dir=str(EVALS))


def docker_state() -> str:
    d = shutil.which("docker") or ("/usr/local/bin/docker" if os.path.exists("/usr/local/bin/docker") else None)
    if not d:
        return "not installed"
    r = subprocess.run([d, "info", "--format", "{{.ServerVersion}}"], capture_output=True, text=True, timeout=20)
    return f"running {r.stdout.strip()}" if r.returncode == 0 else "installed, not running"


def cmd_doctor(argv):
    _, o = args_of(argv, {"--json": False})
    info = engine_info()
    try:
        dk = docker_state()
    except subprocess.TimeoutExpired:
        dk = "not answering"
    prov = provider_table()
    pr = read_json(PRICES, {})
    rep = {"engine": info, "uv": find_uv(), "docker": dk, "providers": prov,
           "prices_checked": pr.get("checked"), "runs": len(list(RUNS.glob("*/run.json"))) if RUNS.exists() else 0,
           "where": {w: where_ready(w) if w != "local" else dk.startswith("running") for w in WHERE}}
    lines = [f"engine    {'ready' if info.get('ready') else 'NOT INSTALLED (roof eval setup)'}"
             + (f" · inspect-ai {info.get('inspect_ai')} · inspect-evals {info.get('inspect_evals')}" if info.get("ready") else ""),
             f"folder    {EVALS}", f"uv        {rep['uv'] or 'missing (brew install uv)'}", f"docker    {dk}",
             f"prices    {'checked ' + pr['checked'] if pr.get('checked') else 'none yet (roof eval prices --refresh)'}",
             "providers " + ", ".join(f"{p}:{'key' if v['ready'] else '-'}" for p, v in prov.items()),
             "sandboxes " + ", ".join(f"{w}:{'ready' if ok else '-'}" for w, ok in rep['where'].items())]
    out(rep, o["json"], "\n".join(lines))


# ── providers and keys ─────────────────────────────────────────────────────────────────────────────────────────────
def provider_table() -> dict:
    conf = read_json(PROVIDERS, {})
    t = {}
    for p, env in PROVIDER_ENV.items():
        kf = (conf.get(p) or {}).get("key_file")
        kfp = Path(os.path.expanduser(kf)) if kf else None
        src = "key file" if kfp and kfp.is_file() else ("environment" if os.environ.get(env) else None)
        t[p] = {"env": env, "key_file": kf, "source": src, "ready": src is not None}
    return t


def cmd_providers(argv):
    if argv[:1] == ["set"]:
        pos, o = args_of(argv[1:], {"--key-file": "", "--json": False})
        if len(pos) != 1 or pos[0] not in PROVIDER_ENV:
            die(f"providers set <{'|'.join(PROVIDER_ENV)}> --key-file PATH", 2, o["json"])
        kf = os.path.expanduser(o["key_file"])
        if not kf or not os.path.isfile(kf):
            die("choose an existing key file (never paste a key value)", 2, o["json"])
        conf = read_json(PROVIDERS, {})
        conf[pos[0]] = {"key_file": o["key_file"]}
        write_json(PROVIDERS, conf)
        os.chmod(PROVIDERS, 0o600)
        out({"provider": pos[0], "key_file": o["key_file"]}, o["json"], f"{pos[0]}: key file set")
        return
    _, o = args_of(argv, {"--json": False})
    t = provider_table()
    out(t, o["json"], "\n".join(f"{p:<11} {v['source'] or 'no key':<12} {v['env']}" for p, v in t.items()))


def provider_of(model: str) -> str:
    return model.split("/", 1)[0]


def read_key(p: str) -> str | None:
    """The key in provider p's key file, or None; a file with more than the key is refused (never guess)."""
    kf = (read_json(PROVIDERS, {}).get(p) or {}).get("key_file")
    if not kf or not os.path.isfile(os.path.expanduser(kf)):
        return None
    key = Path(os.path.expanduser(kf)).read_text(errors="replace").strip()
    if not key or any(c in key for c in "\r\n\t ") or any(ord(c) < 32 for c in key):
        die(f"the key file for {p} ({kf}) must hold only the key, on one line; it has other text. "
            f"Point {p} at a file with just the key: roof eval providers set {p} --key-file PATH", 6)
    return key


def run_env(model: str) -> dict:
    """The run's environment: every configured provider key (a benchmark's grader model can be from any provider),
    given to the run's process only and written nowhere. The model under test must have one."""
    env = dict(os.environ)
    for p, var in PROVIDER_ENV.items():
        k = read_key(p)
        if k:
            env[var] = k
    p = provider_of(model)
    if p in PROVIDER_ENV and not env.get(PROVIDER_ENV[p]):
        die(f"no key for {p}: roof eval providers set {p} --key-file PATH", 6)
    env.setdefault("INSPECT_LOG_LEVEL", "warning")
    return env


# ── prices and estimates ───────────────────────────────────────────────────────────────────────────────────────────
def refresh_prices() -> dict:
    with urllib.request.urlopen(PRICE_SOURCE, timeout=30) as r:
        data = json.load(r)["data"]
    models = {}
    for m in data:
        pr = m.get("pricing") or {}
        try:
            i, o = float(pr.get("prompt") or 0) * 1e6, float(pr.get("completion") or 0) * 1e6
        except ValueError:
            continue
        if i < 0 or o < 0:
            continue
        models[m["id"]] = {"input": round(i, 6), "output": round(o, 6)}
    doc = {"source": PRICE_SOURCE, "checked": now(), "unit": "USD per million tokens", "models": models}
    write_json(PRICES, doc)
    return doc


def prices(refresh=False) -> dict:
    doc = read_json(PRICES, {})
    stale = True
    if doc.get("checked"):
        age = time.time() - datetime.strptime(doc["checked"], "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=timezone.utc).timestamp()
        stale = age > PRICE_MAX_AGE_DAYS * 86400
    if refresh or stale:
        try:
            doc = refresh_prices()
        except OSError:
            pass  # offline: keep the last list; the estimate says how old it is
    return doc


def price_for(model: str, doc: dict) -> dict | None:
    """Inspect model name → price. Tries the OpenRouter id, then the provider/model with -N-N versions as N.N."""
    if model.startswith(FREE_PREFIXES):
        return {"input": 0.0, "output": 0.0, "free": True}
    table = doc.get("models") or {}
    name = model.removeprefix("openrouter/")
    cands = [name]
    p, _, rest = name.partition("/")
    if p == "google" and not rest.startswith("gemini"):
        cands.append(f"google/{rest}")
    dotted = re.sub(r"-(\d+)-(\d+)(?=$|-)", r"-\1.\2", rest)
    undated = re.sub(r"-\d{8}$", "", dotted)
    cands += [f"{p}/{dotted}", f"{p}/{undated}"]
    for c in cands:
        if c in table:
            return dict(table[c], matched=c)
    return None


def tokens_per_sample(task: str, agent: str | None = None) -> tuple[dict, str]:
    """Measured averages on this Mac (last 10 runs of this task, same agent or bare model). Prompt size comes from any
    such run (the prompt is the same for every model); answer size only from paid models, since the stand-in model's
    answers are not real. An agent works through many calls per task, so its guess is far larger than a bare model's."""
    tps, basis = dict(AGENT_DEFAULT_TOKENS if agent else DEFAULT_TOKENS), []
    if DB.exists():
        free = " OR ".join("model LIKE ?" for _ in FREE_PREFIXES)
        q = ("SELECT SUM(input_tokens), SUM(output_tokens), SUM(samples_done) FROM (SELECT * FROM runs WHERE task=? "
             "AND agent IS ? AND samples_done>0 AND input_tokens>0 {} ORDER BY started DESC LIMIT 10)")
        pats = [p + "%" for p in FREE_PREFIXES]
        try:
            with sqlite3.connect(DB) as db:
                a = db.execute(q.format(""), (task_name(task), agent)).fetchone()
                b = db.execute(q.format(f"AND NOT ({free})"), (task_name(task), agent, *pats)).fetchone()
        except sqlite3.OperationalError:
            a = b = None   # an index from before this version; the next `index` rebuilds it
        if a and a[2]:
            tps["input"] = a[0] / a[2]
            basis.append("prompt measured")
        if b and b[2]:
            tps["output"] = max(b[1] / b[2], 1)
            basis.append("answer measured")
    if len(basis) < 2:
        basis.append("answer is a guess" if basis else
                     ("agent guess: 300k in / 15k out per task until measured" if agent else "default guess (no run of this task yet)"))
    return tps, ", ".join(basis)


def history(task: str) -> list[sqlite3.Row]:
    """Finished runs of this task with answers, newest first (at most 10)."""
    if not DB.exists():
        return []
    with sqlite3.connect(DB) as db:
        db.row_factory = sqlite3.Row
        try:
            return db.execute("SELECT * FROM runs WHERE task=? AND samples_done>0 ORDER BY started DESC LIMIT 10",
                              (task_name(task),)).fetchall()
        except sqlite3.OperationalError:
            return []   # an index from before this version: rebuilt by the next `index`


def grader_usage(task: str, model: str) -> tuple[dict, str]:
    """Tokens per answer of the OTHER models a benchmark called (its grader), from earlier runs of the task."""
    runs = history(task)
    if not runs:
        return {}, "unknown until this benchmark has run once here (some grade every answer with a second model)"
    per, n = {}, 0
    with sqlite3.connect(DB) as db:
        for r in runs:
            n += r["samples_done"] or 0
            for m, i, o in db.execute("SELECT model, input_tokens, output_tokens FROM model_usage WHERE run_id=? AND model<>?",
                                      (r["id"], r["model"])):
                a = per.setdefault(m, [0, 0])
                a[0] += i or 0
                a[1] += o or 0
    if not per:
        return {}, "none seen: this benchmark did not call a second model in earlier runs"
    return {m: {"input": i / n, "output": o / n} for m, (i, o) in per.items()}, "measured on this Mac"


def sandbox_seconds(task: str) -> tuple[float, str]:
    secs = [(r["sample_seconds"] or 0) / r["samples_done"] for r in history(task) if r["sample_seconds"]]
    if secs:
        return sum(secs) / len(secs), "measured on this Mac"
    return DEFAULT_SANDBOX_SECONDS, f"guess ({DEFAULT_SANDBOX_SECONDS} s per question until measured)"


def sandbox_rate(where: str) -> float:
    r = SANDBOX_RATES[where]
    return SANDBOX_SHAPE["vcpu"] * r["vcpu_hour"] + SANDBOX_SHAPE["gib"] * r["gib_hour"]


def estimate(task: str, model: str, limit: int, epochs: int, where: str = "local", agent: str | None = None) -> dict:
    """Cost before a run: the model under test + the benchmark's grader model + cloud sandbox time (LAB-2012)."""
    doc = prices()
    pr = price_for(model, doc)
    tps, basis = tokens_per_sample(task, agent)
    n = limit * epochs
    est = {"task": task_name(task), "model": model, "agent": agent, "samples": limit, "epochs": epochs, "calls": n,
           "tokens_per_sample": {k: round(v) for k, v in tps.items()}, "token_basis": basis,
           "prices_checked": doc.get("checked"), "price": pr, "where": where}
    notes = []
    model_usd = None if pr is None else n * (tps["input"] * pr["input"] + tps["output"] * pr["output"]) / 1e6
    if pr is None:
        notes.append("no price known for this model: pass --max-cost and --allow-unknown-cost to run anyway")
    graders, gbasis = grader_usage(task, model)
    grader_usd, unpriced = 0.0, []
    for gm, t in graders.items():
        gp = price_for(gm, doc)
        if gp is None:
            unpriced.append(gm)
            continue
        grader_usd += n * (t["input"] * gp["input"] + t["output"] * gp["output"]) / 1e6
    if unpriced:
        notes.append("grader without a known price: " + ", ".join(unpriced))
    est["grader"] = {"models": sorted(graders), "usd": round(grader_usd, 4), "basis": gbasis}
    sandbox_usd = 0.0
    if where in SANDBOX_RATES:
        secs, sbasis = sandbox_seconds(task)
        sandbox_usd = n * secs / 3600 * sandbox_rate(where)
        est["sandbox"] = {"where": where, "seconds_per_question": round(secs, 1), "usd": round(sandbox_usd, 4),
                          "basis": sbasis, "rate_per_hour": round(sandbox_rate(where), 4),
                          "shape": SANDBOX_SHAPE, "prices_checked": SANDBOX_RATES[where]["checked"]}
    est["model_usd"] = None if model_usd is None else round(model_usd, 4)
    est["cap_check_usd"] = None if model_usd is None else round(model_usd + GRADER_MARGIN * grader_usd + sandbox_usd, 4)
    est["usd"] = None if model_usd is None else round(model_usd + grader_usd + sandbox_usd, 4)
    if notes:
        est["note"] = "; ".join(notes)
    return est


def cmd_prices(argv):
    _, o = args_of(argv, {"--refresh": False, "--json": False})
    try:
        doc = refresh_prices() if o["refresh"] else prices()
    except OSError as e:
        die(f"could not reach {PRICE_SOURCE}: {e}", 7, o["json"])
    out({k: doc.get(k) for k in ("source", "checked", "unit")} | {"models": len(doc.get("models", {}))}, o["json"],
        f"{len(doc.get('models', {}))} model prices from {doc.get('source')} · checked {doc.get('checked')}")


def cmd_estimate(argv):
    pos, o = args_of(argv, {"--model": "", "--limit": "50", "--epochs": "1", "--where": "local", "--agent": "", "--json": False})
    if len(pos) != 1 or not o["model"]:
        die("estimate <task> --model M [--limit N] [--epochs E] [--where local|daytona|modal]", 2, o["json"])
    if o["where"] not in WHERE:
        die(f"--where must be one of {', '.join(WHERE)}", 2, o["json"])
    if o["agent"] and o["agent"] not in AGENTS:
        die(f"--agent must be one of {', '.join(AGENTS)}", 2, o["json"])
    e = estimate(pos[0], o["model"], int(o["limit"]), int(o["epochs"]), o["where"], o["agent"] or None)
    usd = "unknown" if e["usd"] is None else f"${e['usd']:.4f}"
    lines = [f"{e['task']} × {(e['agent'] + ' on ') if e.get('agent') else ''}{e['model']}: {e['calls']} calls · estimate {usd}",
             f"  model    ~{e['tokens_per_sample']['input']} in / {e['tokens_per_sample']['output']} out per answer "
             f"({e['token_basis']}) → " + ("unknown" if e["model_usd"] is None else f"${e['model_usd']:.4f}"),
             f"  grader   {', '.join(e['grader']['models']) or 'none'} → ${e['grader']['usd']:.4f} ({e['grader']['basis']})"]
    if e.get("sandbox"):
        sb = e["sandbox"]
        lines.append(f"  sandbox  {sb['where']} ~{sb['seconds_per_question']} s per answer × ${sb['rate_per_hour']}/h "
                     f"(1 vCPU + 2 GiB, prices {sb['prices_checked']}) → ${sb['usd']:.4f} ({sb['basis']})")
    if e.get("note"):
        lines.append("  note     " + e["note"])
    out(e, o["json"], "\n".join(lines))


# ── runs ───────────────────────────────────────────────────────────────────────────────────────────────────────────
def new_run_id(task: str) -> str:
    stamp = datetime.now().strftime("%Y%m%d-%H%M%S")
    return f"{stamp}-{task_name(task)}-{''.join(random.choices(string.ascii_lowercase + string.digits, k=4))}"


def run_dir(rid: str) -> Path:
    d = RUNS / rid
    if not (d / "run.json").exists():
        die(f"no run {rid}", 3)
    return d


def cost_config(model: str, task: str, doc: dict) -> dict:
    """Inspect's model-cost config for this run. Inspect checks every name against its own model list and refuses
    unknown ones, so it holds only names it already used: the model under test, and the grader models seen in this
    task's earlier logs (their cost then shows in results). The per-answer limit needs only the first."""
    cfg = {}
    for m in [model, *grader_usage(task, model)[0]]:
        p = price_for(m, doc)
        if p and not p.get("free"):
            cfg[m] = {"input": p["input"], "output": p["output"], "input_cache_write": p["input"], "input_cache_read": p["input"]}
    return cfg


def inspect_cmd(r: dict) -> list[str]:
    ref = task_ref(r["task_ref"])
    if ref.endswith(".py"):
        ref = Path(ref).name  # Inspect takes task files relative to the working folder (see task_cwd)
    c = [str(INSPECT), "eval", ref, "--model", r["model"], "--limit", str(r["limit"]),
         "--log-dir", r["dir"], "--display", "plain", "--no-log-images"]
    if r.get("epochs"):
        c += ["--epochs", str(r["epochs"])]
    for a in r.get("task_args") or []:
        c += ["-T", a]
    if r.get("parallel"):
        c += ["--max-samples", str(r["parallel"]), "--max-sandboxes", str(r["parallel"])]
    if r.get("agent"):
        c += ["--solver", f"inspect_swe/{r['agent']}"]   # the real agent CLI is the subject; the model is its brain
    if WHERE.get(r.get("where") or "local"):
        c += ["--sandbox", WHERE[r["where"]]]   # the task's own Dockerfile / compose file is reused by the provider
    if r.get("seed") is not None:
        c += ["--seed", str(r["seed"]), "--sample-shuffle", str(r["seed"])]
    if r.get("temperature") is not None:
        c += ["--temperature", str(r["temperature"])]
    if r.get("per_sample_cap") is not None:
        c += ["--cost-limit", f"{r['per_sample_cap']:.6f}", "--model-cost-config", str(Path(r["dir"]) / "prices.json")]
    return c


_EPOCHS_CODE = r"""
import json, sys, inspect_evals._registry as r
t = getattr(r, sys.argv[1])()
e = t.epochs
print(json.dumps(getattr(e, "epochs", e) or 1))
"""


def default_epochs(task: str) -> int:
    """The benchmark's own attempts per question (MBPP: 5 for pass@k). Builds the task once (cached dataset)."""
    if task.endswith(".py") or "/" in task and not task.startswith("inspect_evals/"):
        return 1
    r = subprocess.run([str(VPY), "-c", _EPOCHS_CODE, task_name(task)], capture_output=True, text=True)
    try:
        return max(int(json.loads(r.stdout.strip().splitlines()[-1])), 1)
    except (ValueError, IndexError):
        return 1


def task_cwd(r: dict) -> str | None:
    ref = r.get("task_ref", "")
    return str(Path(os.path.expanduser(ref)).resolve().parent) if ref.endswith(".py") else None


def pid_alive(pid: int | None) -> bool:
    if not pid:
        return False
    try:
        os.kill(pid, 0)
        return True
    except (ProcessLookupError, PermissionError):
        return False


def cmd_run(argv):
    pos, o = args_of(argv, {"--model": "", "--limit": "50", "--epochs": "", "--seed": "42", "--temperature": "",
                            "--task-args": "", "--where": "local", "--agent": "", "--parallel": "", "--max-cost": "2", "--allow-unknown-cost": False, "--background": False,
                            "--json": False})
    if len(pos) != 1 or not o["model"]:
        die("run <task> --model M [--limit 50] [--epochs 1] [--seed 42] [--temperature T] [--max-cost 2] [--background]",
            2, o["json"])
    need_engine(o["json"])
    task, model = pos[0], o["model"]
    if task.endswith(".py"):
        task = str(Path(os.path.expanduser(task)).resolve())
        if not os.path.isfile(task):
            die(f"no task file {task}", 2, o["json"])
    # Epochs: the benchmark's own default unless asked (MBPP needs 2 for pass@2). Estimates assume 1 when unset.
    limit, epochs, cap = int(o["limit"]), (int(o["epochs"]) if o["epochs"] else None), float(o["max_cost"])
    if limit < 1 or (epochs is not None and epochs < 1) or cap < 0:
        die("limit and epochs must be ≥ 1 and the cap ≥ 0", 2, o["json"])
    if o["where"] not in WHERE:
        die(f"--where must be one of {', '.join(WHERE)}", 2, o["json"])
    if o["agent"] and o["agent"] not in AGENTS:
        die(f"--agent must be one of {', '.join(AGENTS)}", 2, o["json"])
    if not where_ready(o["where"]):
        die(f"no sign-in for {o['where']}: " + ("run  python3 -m modal setup  once" if o["where"] == "modal" else
            f"roof eval providers set {o['where']} --key-file PATH"), 6, o["json"])
    env = run_env(model)  # refuses early when the key is missing
    entry = catalog_entry(task)
    if entry and entry.get("extra") and entry["extra"].replace("_", "-") not in installed_extras():
        install_extras([entry["extra"]])
    attempts = epochs or default_epochs(task)
    est = estimate(task, model, limit, attempts, o["where"], o["agent"] or None)
    if epochs is None and attempts > 1:
        est["note_epochs"] = f"this benchmark answers each question {attempts} times by default (pass@k)"
    if est["usd"] is None and not o["allow_unknown_cost"]:
        die(est["note"], 3, o["json"])
    check = None if est["usd"] is None else est["usd"] + (GRADER_MARGIN - 1) * est["grader"]["usd"]
    if check is not None and check > cap:
        what = (f"estimate ${est['usd']:.4f}, ${check:.4f} with the grader counted ×{GRADER_MARGIN} (grading is not "
                f"stopped mid-run)," if est["grader"]["usd"] else f"estimate ${est['usd']:.4f}")
        die(f"{what} is over the cap ${cap:.2f}: lower --limit or raise --max-cost", 3, o["json"])
    rid = new_run_id(task)
    d = RUNS / rid
    d.mkdir(parents=True)
    r = {"id": rid, "task": task_name(task), "task_ref": task, "model": model, "limit": limit, "epochs": epochs,
         "seed": int(o["seed"]) if o["seed"] != "" else None,
         "temperature": float(o["temperature"]) if o["temperature"] != "" else None,
         "task_args": [a for a in o["task_args"].split(",") if a], "where": o["where"], "agent": o["agent"] or None,
         # Containers at once: agent runs start a container per question; ~10 emulated x86 SWE-bench containers on a Mac
         # made sandbox commands time out (LAB-1993), so sandboxed agent runs default to 2.
         "parallel": int(o["parallel"]) if o["parallel"] else (2 if o["agent"] else None), "max_cost": cap, "estimate": est, "status": "queued", "created": now(), "dir": str(d)}
    # Hard cap while answering: no answer may spend more than its share of the cap (Inspect's per-sample cost limit,
    # with every known price so tools and sub-agents count). Inspect applies it to the solver only: grading runs after
    # it (inspect_ai/_eval/task/run.py, the scoring block has only a time limit), and sandbox time is not tokens. Both
    # are covered by the pre-run check instead (estimate, grader × GRADER_MARGIN, must be within the cap).
    # Inspect fails a run whose cost limit meets a model without a price (it knows no price for the stand-in model,
    # and a benchmark's grader is only known after its first run here), so the limit is set only when the model under
    # test is paid and every grader seen in earlier runs of this benchmark has a price. Otherwise the cost-before-start
    # check is the only guard, and the run says so.
    doc = prices()
    graders = grader_usage(task, model)[0]
    paid = bool(est.get("price")) and not est["price"].get("free")
    if paid and history(task) and all(price_for(g, doc) for g in graders):
        r["per_sample_cap"] = max(cap / (limit * attempts), 1e-6)
        write_json(d / "prices.json", cost_config(model, task, doc))
        r["cap_mode"] = "per-answer limit while answering + cost-before-start check"
    else:
        r["cap_mode"] = ("cost-before-start check only (" + ("free model" if not paid else
                         "first run of this benchmark here: its graders are not known yet") + ")")
    write_json(d / "run.json", r)
    if o["background"]:
        log = open(d / "console.log", "ab")
        p = subprocess.Popen([sys.executable, str(Path(__file__).resolve()), "_worker", rid], stdout=log, stderr=log,
                             stdin=subprocess.DEVNULL, start_new_session=True, env=env)
        out({"id": rid, "pid": p.pid, "estimate": est}, o["json"], f"started {rid} in the background (pid {p.pid})")
        return
    rc = work(rid, env)
    rr = read_json(d / "run.json")
    out(dict(rr, results=results_for(rid)), o["json"], render_result(rid))
    sys.exit(0 if rr["status"] == "done" else 1)


def set_status(d: Path, **kw):
    r = read_json(d / "run.json", {})
    r.update(kw)
    write_json(d / "run.json", r)
    return r


def work(rid: str, env: dict | None = None, retry_log: str | None = None) -> int:
    d = RUNS / rid
    r = set_status(d, status="running", started=now(), pid=os.getpid())
    cmd = [str(INSPECT), "eval-retry", retry_log, "--log-dir", str(d)] if retry_log else inspect_cmd(r)
    with open(d / "console.log", "ab") as log:
        env = dict(env or run_env(r["model"]))
        if r.get("where") == "modal":
            # Modal 1.5 (held for inspect-sandboxes) predates the newest image builder new accounts default to.
            env.setdefault("MODAL_IMAGE_BUILDER_VERSION", MODAL_IMAGE_BUILDER)
        p = subprocess.Popen(cmd, stdout=log, stderr=subprocess.STDOUT, env=env, cwd=task_cwd(r))
        set_status(d, child=p.pid)
        rc = p.wait()
    index()
    # The log decides: Inspect can exit 0 with every call failed (e.g. a rejected key) and status 'error'.
    with sqlite3.connect(DB) as db:
        row = db.execute("SELECT log_status, error FROM runs WHERE id=?", (rid,)).fetchone()
    log_status, err = row if row else (None, None)
    if (d / "CANCEL").exists():
        status = "cancelled"
    elif rc == 0 and log_status == "success":
        status = "done"
    else:
        status = "failed"
    if status != "done" and not err:
        try:  # errors before the log exists (dataset download, missing package) are only in the console
            lines = [x for x in (d / "console.log").read_text(errors="ignore").splitlines() if x.strip()]
            err = next((x for x in reversed(lines) if re.search(r"Error|error:|requires", x)), lines[-1] if lines else None)
        except OSError:
            pass
    error = None if status == "done" else redact(err or f"inspect exited {rc}; see console.log")[:2000]
    set_status(d, status=status, finished=now(), returncode=rc, log_status=log_status, error=error,
               hint=hint_for(err) if status != "done" else None)
    index()
    return 0 if status == "done" else 1


def take_slot(rid: str):
    """Wait for one of N slot locks (flock); the lock is held for the run's life and freed when the worker exits."""
    import fcntl
    n = max(int(os.environ.get("ONEROOF_EVALS_SLOTS", "2") or 2), 1)
    (EVALS / "slots").mkdir(parents=True, exist_ok=True)
    d = RUNS / rid
    while True:
        if (d / "CANCEL").exists():
            return None
        for i in range(n):
            f = open(EVALS / "slots" / f"slot{i}.lock", "w")
            try:
                fcntl.flock(f, fcntl.LOCK_EX | fcntl.LOCK_NB)
                return f
            except OSError:
                f.close()
        time.sleep(2)


def cmd_worker(argv):
    rid = argv[0]
    set_status(RUNS / rid, pid=os.getpid())  # queued and alive
    slot = take_slot(rid)
    if slot is None:
        set_status(RUNS / rid, status="cancelled", finished=now())
        index()
        sys.exit(1)
    rc = work(rid)
    slot.close()
    sys.exit(0 if rc == 0 else 1)


def cmd_cancel(argv):
    _, o = args_of(argv[1:], {"--json": False})
    if not argv:
        die("cancel <run>", 2)
    d = run_dir(argv[0])
    r = read_json(d / "run.json")
    if r.get("status") in ("done", "failed", "cancelled"):
        out({"id": argv[0], "cancelled": False, "status": r["status"]}, o["json"], f"{argv[0]} already {r['status']}")
        return
    (d / "CANCEL").write_text(now())
    # Interrupt Inspect only: it writes a partial 'cancelled' log, and the worker (left alive) records the outcome.
    if r.get("status") == "running" and pid_alive(r.get("child")):
        try:
            os.kill(r["child"], signal.SIGINT)
        except OSError:
            pass
    if r.get("status") in ("queued", "running", "interrupted") and not pid_alive(r.get("pid")):
        set_status(d, status="cancelled", finished=now())
    out({"id": argv[0], "cancelled": True}, o["json"], f"cancel sent to {argv[0]}")


def latest_log(d: Path) -> Path | None:
    logs = sorted(d.glob("*.eval"), key=lambda p: p.stat().st_mtime)
    return logs[-1] if logs else None


def cmd_resume(argv):
    _, o = args_of(argv[1:], {"--json": False})
    if not argv:
        die("resume <run>", 2)
    d = run_dir(argv[0])
    log = latest_log(d)
    if not log:
        die("nothing to resume: the run never wrote a log; start it again", 3)
    (d / "CANCEL").unlink(missing_ok=True)
    r = read_json(d / "run.json")
    env = run_env(r["model"])
    logf = open(d / "console.log", "ab")
    p = subprocess.Popen([sys.executable, str(Path(__file__).resolve()), "_retry", argv[0], str(log)], stdout=logf,
                         stderr=logf, stdin=subprocess.DEVNULL, start_new_session=True, env=env)
    out({"id": argv[0], "pid": p.pid}, o["json"], f"resuming {argv[0]} (pid {p.pid}); samples already done are kept")


def cmd_status(argv):
    _, o = args_of(argv, {"--json": False})
    rows = []
    for f in sorted(RUNS.glob("*/run.json")) if RUNS.exists() else []:
        r = read_json(f, {})
        if r.get("status") in ("running", "queued") and r.get("pid") and not pid_alive(r.get("pid")):
            r = set_status(f.parent, status="cancelled" if (f.parent / "CANCEL").exists() else "interrupted")
        rows.append({k: r.get(k) for k in ("id", "task", "model", "limit", "epochs", "status", "created", "finished")}
                    | {"progress": progress(f.parent)})
    out(rows, o["json"], "\n".join(f"{r['id']:<44} {r['model']:<36} {r['status']:<11} {r['progress']}" for r in rows)
        or "no runs yet")


def progress(d: Path) -> str:
    """Samples finished: the .eval log is a zip that gains one samples/<id>_epoch_<n>.json per scored sample (flushed in
    small batches while running); Inspect's plain display ('Samples: 12/50') is the fallback."""
    r = read_json(d / "run.json", {})
    total = (r.get("limit") or 0) * (r.get("epochs") or 1)
    log = latest_log(d)
    if log:
        try:
            with zipfile.ZipFile(log) as z:
                done = sum(1 for n in z.namelist() if n.startswith("samples/") and n.endswith(".json"))
            if done:
                return f"{done}/{total}" if total else str(done)
        except (zipfile.BadZipFile, OSError):
            pass  # being written right now
    try:
        tail = (d / "console.log").read_bytes()[-4000:].decode(errors="ignore")
    except OSError:
        return ""
    m = re.findall(r"Samples:\s*(\d+)/\s*(\d+)", tail)
    return f"{m[-1][0]}/{m[-1][1]}" if m else (f"0/{total}" if total else "")


# ── index and results ──────────────────────────────────────────────────────────────────────────────────────────────
SCHEMA = """
CREATE TABLE IF NOT EXISTS runs (id TEXT PRIMARY KEY, task TEXT, task_version TEXT, model TEXT, status TEXT,
  started TEXT, finished TEXT, limit_n INTEGER, epochs INTEGER, seed INTEGER, temperature REAL, max_cost REAL,
  est_cost REAL, cost REAL, input_tokens INTEGER, output_tokens INTEGER, samples_total INTEGER, samples_done INTEGER,
  dataset TEXT, dataset_size INTEGER, inspect_ai TEXT, inspect_evals TEXT, log_path TEXT, framework TEXT,
  log_status TEXT, error TEXT, where_run TEXT, sample_seconds REAL, agent TEXT);
CREATE TABLE IF NOT EXISTS scores (run_id TEXT, scorer TEXT, metric TEXT, value REAL,
  PRIMARY KEY (run_id, scorer, metric));
CREATE TABLE IF NOT EXISTS model_usage (run_id TEXT, model TEXT, input_tokens INTEGER, output_tokens INTEGER, cost REAL,
  PRIMARY KEY (run_id, model));
"""

_INDEX_CODE = r"""
import json, sys
from inspect_ai.log import read_eval_log
out = {}
for p in sys.argv[1:]:
    try:
        l = read_eval_log(p, header_only=True)
    except Exception as e:
        out[p] = {"error": str(e)}; continue
    u = l.stats.model_usage or {}
    cost = [x.total_cost for x in u.values() if x.total_cost is not None]
    err = (l.error.message if l.error else None)
    secs = 0.0
    try:
        from inspect_ai.log import read_eval_log_sample_summaries
        secs = sum((x.total_time or 0) for x in read_eval_log_sample_summaries(p))
    except Exception:
        pass
    usage = [{"model": k, "input_tokens": x.input_tokens + (x.input_tokens_cache_read or 0) + (x.input_tokens_cache_write or 0),
              "output_tokens": x.output_tokens, "cost": x.total_cost} for k, x in u.items()]
    out[p] = {"status": l.status, "error": (err or "")[:2000] or None, "task_version": str(l.eval.task_version), "model": l.eval.model,
      "dataset": l.eval.dataset.name, "dataset_size": l.eval.dataset.samples, "packages": l.eval.packages,
      "started": l.stats.started_at, "finished": l.stats.completed_at,
      "samples_total": l.results.total_samples if l.results else None,
      "samples_done": l.results.completed_samples if l.results else 0,
      "input_tokens": sum(x.input_tokens + (x.input_tokens_cache_read or 0) + (x.input_tokens_cache_write or 0) for x in u.values()),
      "output_tokens": sum(x.output_tokens for x in u.values()),
      "cost": sum(cost) if cost else None, "usage": usage, "sample_seconds": secs,
      "scores": [{"scorer": s.name, "metrics": {k: m.value for k, m in s.metrics.items()}} for s in (l.results.scores if l.results else [])]}
print(json.dumps(out))
"""


def index() -> int:
    """Rebuild evals.db from the run folders and their Inspect logs (the logs are the truth)."""
    EVALS.mkdir(parents=True, exist_ok=True)
    dirs = sorted(p.parent for p in RUNS.glob("*/run.json")) if RUNS.exists() else []
    logs = {d: latest_log(d) for d in dirs}
    heads = {}
    paths = [str(p) for p in logs.values() if p]
    if paths and engine_ready():
        r = subprocess.run([str(VPY), "-c", _INDEX_CODE, *paths], capture_output=True, text=True)
        heads = json.loads(r.stdout) if r.returncode == 0 and r.stdout.strip() else {}
    # Inspect records cost only for models priced in the run's cost config; for the rest (e.g. a grader on the first
    # run of a benchmark) the cost comes from the logged tokens and the dated price list.
    doc = read_json(PRICES, {}) or {}
    for h in heads.values():
        for mu in h.get("usage", []):
            if mu["cost"] is None:
                pr = price_for(mu["model"], doc)
                if pr and not pr.get("free"):
                    mu["cost"] = (mu["input_tokens"] * pr["input"] + mu["output_tokens"] * pr["output"]) / 1e6
        known = [mu["cost"] for mu in h.get("usage", []) if mu["cost"] is not None]
        if h.get("cost") is None and known:
            h["cost"] = sum(known)
    tmp = DB.with_suffix(".tmp")
    tmp.unlink(missing_ok=True)
    with sqlite3.connect(tmp) as db:
        db.executescript(SCHEMA)
        for d in dirs:
            r = read_json(d / "run.json", {})
            h = heads.get(str(logs[d]), {}) if logs[d] else {}
            pk = h.get("packages") or {}
            db.execute("INSERT INTO runs VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)", (
                r.get("id"), r.get("task"), h.get("task_version"), r.get("model"), r.get("status"),
                h.get("started") or r.get("started"), h.get("finished") or r.get("finished"), r.get("limit"),
                r.get("epochs"), r.get("seed"), r.get("temperature"), r.get("max_cost"),
                (r.get("estimate") or {}).get("usd"), h.get("cost"), h.get("input_tokens"), h.get("output_tokens"),
                h.get("samples_total"), h.get("samples_done"), h.get("dataset"), h.get("dataset_size"),
                pk.get("inspect_ai"), pk.get("inspect_evals"), str(logs[d]) if logs[d] else None, "inspect",
                h.get("status"), redact(h.get("error") or r.get("error")), r.get("where") or "local", h.get("sample_seconds"), r.get("agent")))
            for mu in h.get("usage", []):
                db.execute("INSERT OR REPLACE INTO model_usage VALUES (?,?,?,?,?)",
                           (r.get("id"), mu["model"], mu["input_tokens"], mu["output_tokens"], mu["cost"]))
            for s in h.get("scores", []):
                for m, v in s["metrics"].items():
                    if isinstance(v, (int, float)):
                        db.execute("INSERT OR REPLACE INTO scores VALUES (?,?,?,?)", (r.get("id"), s["scorer"], m, v))
    tmp.replace(DB)
    return len(dirs)


def interval(value: float, n: int | None, stderr: float | None, bounded: bool) -> tuple[float, float, str]:
    """95 % interval. Proportions use Wilson (honest at 0 % and 100 % and small n); other metrics value ± 1.96·stderr."""
    if bounded and n:
        z = 1.96
        den = 1 + z * z / n
        mid = (value + z * z / (2 * n)) / den
        half = z * math.sqrt(value * (1 - value) / n + z * z / (4 * n * n)) / den
        return max(0.0, mid - half), min(1.0, mid + half), "wilson"
    if stderr is not None:
        return value - 1.96 * stderr, value + 1.96 * stderr, "normal"
    return value, value, "none"


PROPORTION_METRICS = {"accuracy", "mean", "pass_at_1", "resolved", "pass@1"}


def is_stderr(metric: str) -> bool:
    return metric == "stderr" or metric.endswith("_stderr")


def is_proportion(metric: str) -> bool:
    return metric in PROPORTION_METRICS or metric.endswith(("_acc", "accuracy")) or metric.startswith("pass_at")


def stderr_for(s: dict, scores: list[dict]) -> float | None:
    """'stderr' belongs to the scorer's metrics; 'final_stderr' to 'final_acc' (shared prefix before the last _)."""
    same = [x for x in scores if x["scorer"] == s["scorer"] and is_stderr(x["metric"])]
    prefix = s["metric"].rsplit("_", 1)[0] if "_" in s["metric"] else None
    for x in same:
        if prefix and x["metric"] == prefix + "_stderr":
            return x["value"]
    plain = [x for x in same if x["metric"] == "stderr"]
    return plain[0]["value"] if len(plain) == 1 else None


def results_for(rid: str | None = None) -> list[dict]:
    if not DB.exists():
        index()
    q = "SELECT * FROM runs" + (" WHERE id=?" if rid else "") + " ORDER BY started DESC"
    with sqlite3.connect(DB) as db:
        db.row_factory = sqlite3.Row
        runs = [dict(x) for x in db.execute(q, (rid,) if rid else ())]
        for r in runs:
            sc = [dict(x) for x in db.execute("SELECT scorer, metric, value FROM scores WHERE run_id=?", (r["id"],))]
            r["metrics"] = []
            n = (r["samples_done"] or 0) or None
            for s in sc:
                if is_stderr(s["metric"]):
                    continue
                se = stderr_for(s, sc)
                v = s["value"]
                if v is None or (isinstance(v, float) and math.isnan(v)):
                    r["metrics"].append({"scorer": s["scorer"], "metric": s["metric"], "value": None, "stderr": se,
                                         "n": n, "ci95": None, "ci_method": "none",
                                         "note": "not computable on these samples (e.g. too few for this metric)"})
                    continue
                bounded = is_proportion(s["metric"]) and 0 <= v <= 1
                lo, hi, how = interval(v, n, se, bounded)
                r["metrics"].append({"scorer": s["scorer"], "metric": s["metric"], "value": v, "stderr": se,
                                     "n": n, "ci95": [round(lo, 4), round(hi, 4)], "ci_method": how})
    return runs


def render_result(rid: str) -> str:
    rs = results_for(rid)
    if not rs:
        return f"{rid}: no results"
    r = rs[0]
    # A free model can still pay its benchmark's grader: show the money spent whenever the log has it.
    cost = (f"${r['cost']:.4f}" if r["cost"] else "free" if r["model"].startswith(FREE_PREFIXES)
            else "$0.0000" if r["cost"] == 0 else "cost unknown")
    head = (f"{r['task']} · {r['model']} · {r['status']} · {r['samples_done']}/{r['samples_total']} samples · "
            f"{r['input_tokens'] or 0:,} in / {r['output_tokens'] or 0:,} out tokens · {cost}").replace("/None samples", f"/{r['limit_n'] * (r['epochs'] or 1)} samples")
    if r.get("error"):
        head += "\n  error: " + r["error"].strip().splitlines()[-1][:300]
        h = hint_for(r["error"])
        if h:
            head += "\n  what to do: " + h
    lines = [head] + [f"  {m['scorer']}/{m['metric']}: n/a ({m['note']})" if m["value"] is None else
                      f"  {m['scorer']}/{m['metric']}: {m['value']:.3f}  95% [{m['ci95'][0]:.3f}, {m['ci95'][1]:.3f}] "
                      f"({m['ci_method']}, n={m['n']})" for m in r["metrics"]]
    return "\n".join(lines)


def cmd_results(argv):
    pos, o = args_of(argv, {"--json": False})
    index()
    if pos:
        run_dir(pos[0])
        out(results_for(pos[0]), o["json"], render_result(pos[0]))
    else:
        rs = results_for()
        out(rs, o["json"], "\n".join(render_result(r["id"]) for r in rs) or "no runs yet")


def cmd_index(argv):
    _, o = args_of(argv, {"--json": False})
    n = index()
    out({"runs": n, "db": str(DB)}, o["json"], f"indexed {n} runs into {DB}")


_SAMPLES_CODE = r"""
import json, sys
from inspect_ai.log import read_eval_log_samples
from inspect_ai.scorer import value_to_float
to_f = value_to_float()
def text(x, n):
    if x is None: return None
    if isinstance(x, list): x = "\n".join(getattr(m, "text", str(m)) for m in x)
    x = str(x); return x if len(x) <= n else x[:n] + " …"
rows = []
for s in read_eval_log_samples(sys.argv[1], all_samples_required=False):
    sc = s.scores or {}
    first = next(iter(sc.values()), None)
    u = s.model_usage or {}
    rows.append({"id": str(s.id), "epoch": s.epoch,
      "score": to_f(first.value) if first is not None and not isinstance(first.value, dict) else None,
      "scores": {k: (to_f(v.value) if not isinstance(v.value, dict) else None) for k, v in sc.items()},
      "raw": {k: str(v.value)[:40] for k, v in sc.items()},
      "answer": text(first.answer if first else None, 200), "target": text(s.target, 200),
      "input": text(s.input, 400), "output": text(s.output.completion if s.output else None, 400),
      "explanation": text(first.explanation if first else None, 600),
      "time": s.total_time, "input_tokens": sum(x.input_tokens for x in u.values()),
      "output_tokens": sum(x.output_tokens for x in u.values()), "error": text(s.error.message if s.error else None, 400)})
print(json.dumps(rows))
"""

_SAMPLE_CODE = r"""
import json, sys
from inspect_ai.log import read_eval_log_samples
want, epoch = sys.argv[2], int(sys.argv[3])
for s in read_eval_log_samples(sys.argv[1], all_samples_required=False):
    if str(s.id) != want or s.epoch != epoch: continue
    msgs = []
    for m in s.messages:
        calls = [{"function": c.function, "arguments": json.dumps(c.arguments)[:2000]} for c in (getattr(m, "tool_calls", None) or [])]
        msgs.append({"role": m.role, "text": (m.text or "")[:20000], "tool_calls": calls})
    sc = {k: {"value": str(v.value), "answer": v.answer, "explanation": (v.explanation or "")[:20000]} for k, v in (s.scores or {}).items()}
    print(json.dumps({"id": str(s.id), "epoch": s.epoch, "target": str(s.target)[:20000], "messages": msgs, "scores": sc,
                      "time": s.total_time, "error": s.error.message[:4000] if s.error else None}))
    break
else:
    print(json.dumps({"error": "no such sample"}))
"""


def cmd_samples(argv):
    pos, o = args_of(argv, {"--json": False})
    if len(pos) != 1:
        die("samples <run>", 2, o["json"])
    need_engine(o["json"])
    log = latest_log(run_dir(pos[0]))
    if not log:
        die("this run has no log yet", 3, o["json"])
    r = subprocess.run([str(VPY), "-c", _SAMPLES_CODE, str(log)], capture_output=True, text=True)
    if r.returncode != 0:
        die(f"could not read the log: {r.stderr.strip()[-300:]}", 8, o["json"])
    rows = json.loads(r.stdout)
    for x in rows:
        x["error"] = redact(x.get("error"))
    out(rows, o["json"], "\n".join(f"{x['id']:<24} e{x['epoch']} score={x['score']} answer={x['answer']!r} target={x['target']!r}"
                                   for x in rows) or "no samples yet")


def cmd_sample(argv):
    pos, o = args_of(argv, {"--epoch": "1", "--json": False})
    if len(pos) != 2:
        die("sample <run> <id> [--epoch N]", 2, o["json"])
    need_engine(o["json"])
    log = latest_log(run_dir(pos[0]))
    if not log:
        die("this run has no log yet", 3, o["json"])
    r = subprocess.run([str(VPY), "-c", _SAMPLE_CODE, str(log), pos[1], o["epoch"]], capture_output=True, text=True)
    if r.returncode != 0:
        die(f"could not read the log: {r.stderr.strip()[-300:]}", 8, o["json"])
    d = json.loads(r.stdout)
    if d.get("error"):
        d["error"] = redact(d["error"])
    out(d, o["json"], "\n\n".join(f"[{m['role']}]\n{m['text']}" for m in d.get("messages", [])) or json.dumps(d))


def cmd_export(argv):
    _, o = args_of(argv, {"--format": "csv", "--out": "", "--json": False})
    index()
    rows = []
    for r in results_for():
        base = {k: r.get(k) for k in ("id", "task", "model", "status", "started", "finished", "limit_n", "epochs", "seed",
                                      "temperature", "samples_done", "input_tokens", "output_tokens", "cost", "est_cost",
                                      "inspect_ai", "inspect_evals", "task_version")}
        for m in r["metrics"] or [{}]:
            ci = m.get("ci95") or [None, None]
            rows.append(dict(base, scorer=m.get("scorer"), metric=m.get("metric"), value=m.get("value"),
                             stderr=m.get("stderr"), ci95_low=ci[0], ci95_high=ci[1], ci_method=m.get("ci_method")))
    if o["format"] == "json":
        text = json.dumps(rows, indent=2)
    else:
        import csv, io
        buf = io.StringIO()
        cols = list(rows[0].keys()) if rows else ["id"]
        w = csv.DictWriter(buf, fieldnames=cols)
        w.writeheader()
        w.writerows(rows)
        text = buf.getvalue()
    if o["out"]:
        Path(os.path.expanduser(o["out"])).write_text(text)
        out({"rows": len(rows), "file": o["out"]}, o["json"], f"wrote {len(rows)} rows to {o['out']}")
    else:
        print(text)


def cmd_xray(argv):
    """The agent X-ray from git (LAB-1961): xray.py beside this file, standard library only."""
    os.execv(sys.executable, [sys.executable, str(HERE / "xray.py"), *argv])


# ── catalog ────────────────────────────────────────────────────────────────────────────────────────────────────────
_CATALOG_CODE = r"""
import json, os, sys, yaml, inspect_evals
base = os.path.dirname(inspect_evals.__file__)
out = []
for folder in sorted(os.listdir(base)):
    p = os.path.join(base, folder, "eval.yaml")
    if not os.path.isfile(p):
        continue
    try:
        y = yaml.safe_load(open(p)) or {}
    except Exception:
        continue
    md = y.get("metadata") or {}
    out.append({"folder": folder, "title": y.get("title"), "group": y.get("group"),
      "description": (y.get("description") or "").strip(), "arxiv": y.get("arxiv"), "version": str(y.get("version")),
      "tags": y.get("tags") or [], "extra": y.get("dependency"),
      "sandbox": bool(md.get("sandbox")), "internet": bool((md.get("requires") or {}).get("internet")),
      "supports_k8s": bool(md.get("supports_k8s")),
      "assets": sorted({a.get("type") for a in (y.get("external_assets") or []) if isinstance(a, dict) and a.get("type")}),
      "tasks": [{"name": t.get("name"), "samples": t.get("dataset_samples"), "human_baseline": t.get("human_baseline")}
                for t in (y.get("tasks") or []) if isinstance(t, dict)]})
print(json.dumps(out))
"""


def build_catalog(refresh: bool = False, as_json: bool = False) -> dict:
    """The benchmark catalog, scanned from the installed inspect_evals when missing, stale or asked."""
    info = engine_info()
    cat = read_json(CATALOG, {})
    if refresh or cat.get("inspect_evals") != info.get("inspect_evals"):
        r = subprocess.run([str(VPY), "-c", _CATALOG_CODE], capture_output=True, text=True)
        if r.returncode != 0:
            die(f"catalog scan failed: {r.stderr.strip()[-400:]}", 8, as_json)
        starter = read_json(HERE / "starter.json", {"shelf": []})
        shelf = {s["task"]: dict(s, rank=i) for i, s in enumerate(starter["shelf"])}
        benches = json.loads(r.stdout)
        for b in benches:
            picks = [shelf[t["name"]] for t in b["tasks"] if t["name"] in shelf]
            b["starter"] = [{k: p[k] for k in ("task", "teaches", "rank")} | ({"milestone": p["milestone"]} if "milestone" in p else {})
                            for p in picks]
            b["category"] = picks[0]["category"] if picks else (b["group"] or "Other")
        benches.sort(key=lambda b: (min((s["rank"] for s in b["starter"]), default=999), b["category"], b["folder"]))
        cat = {"inspect_ai": info.get("inspect_ai"), "inspect_evals": info.get("inspect_evals"), "scanned": now(),
               "categories": starter.get("categories", []), "benchmarks": benches,
               "count": len(benches), "tasks": sum(len(b["tasks"]) for b in benches)}
        write_json(CATALOG, cat)
    return cat


def cmd_catalog(argv):
    _, o = args_of(argv, {"--refresh": False, "--json": False})
    need_engine(o["json"])
    cat = build_catalog(o["refresh"], o["json"])
    if o["json"]:
        out(cat, True)
        return
    lines = [f"{cat['count']} benchmarks · {cat['tasks']} tasks · inspect-evals {cat['inspect_evals']}"]
    for b in cat["benchmarks"]:
        mark = "★" if b["starter"] else " "
        need = ",".join(x for x, f in (("sandbox", b["sandbox"]), ("internet", b["internet"])) if f)
        lines.append(f"{mark} {b['category']:<22} {b['folder']:<24} {(b['title'] or '')[:60]:<60} {need}")
    print("\n".join(lines))


# ── main ───────────────────────────────────────────────────────────────────────────────────────────────────────────
COMMANDS = {"setup": cmd_setup, "doctor": cmd_doctor, "catalog": cmd_catalog, "providers": cmd_providers,
            "prices": cmd_prices, "estimate": cmd_estimate, "run": cmd_run, "status": cmd_status, "cancel": cmd_cancel,
            "resume": cmd_resume, "results": cmd_results, "index": cmd_index, "_worker": cmd_worker,
            "samples": cmd_samples, "sample": cmd_sample, "export": cmd_export, "xray": cmd_xray}


def main(argv: list[str]) -> None:
    if argv[:1] == ["_retry"]:
        rc = work(argv[1], retry_log=argv[2])
        sys.exit(0 if rc == 0 else 1)
    if not argv or argv[0] in ("-h", "--help", "help") or argv[0] not in COMMANDS:
        print(__doc__)
        sys.exit(0 if not argv or argv[0] in ("-h", "--help", "help") else 2)
    COMMANDS[argv[0]](argv[1:])


if __name__ == "__main__":
    main(sys.argv[1:])
