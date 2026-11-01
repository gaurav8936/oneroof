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
  evalset build --repo PATH [--count 20] [--linear-key-file PATH] | list | show <name>   your own eval set from a
                                   repo's fix history (evalset.py); the catalog lists it under "Your evals"
  judge new|label|build|agreement|list|show   a model as judge, measured against your own pass/fail labels (judge.py)
  lmeval setup | run <task> --model openai-api/<svc>/<name> --base-url URL   the same benchmark in lm-evaluation-harness
  overview [--since ISO] [--json]   your scorecard: each eval's contestants (agents first), what changed, running, a next step
  anatomy <benchmark> [--json]      what a benchmark is made of: questions, answer, graded by, chance, how one is scored
  items <task> [--limit 50] [--offset K] [--filter all|seen|wrong|random] [--seed N] [--download] [--json]
                                   its real questions on this Mac (first open downloads the dataset), one dot per run
  item <task> <id> [--json]        one question: reference, what the model sees, how it's marked, each run's answer
  item-results <task> <id> [--json]   each run's answer to one question
  scores show <benchmark> | refresh [--json]   published best scores, one official source each, with date
  run <your set's task file> --agent claude_code|codex_cli --seat C1|CX [--seat-limit 90]   the agent CLI on your
                                   subscription seat answers each case in a fresh worktree at the commit before the fix
                                   (agent_runner.py); never an API key; waits while the seat is over its limit, or
                                   while its use is unknown until you say run-anyway
  run-anyway <run> [--json]        a seat run waiting with "seat use unknown" goes on without knowing the seat's use
                                   (the owner's explicit choice, recorded in the run)
  power --n N [--epochs E] [--p 0.5] [--json]   the ± points a run of N questions × E attempts can tell apart
  compare <runA> <runB> [--json]   paired difference over shared questions, verdict a|b|noise, the questions only one solved
  leaderboard <task | set@vN> [--json]   latest finished run per contestant, the floor, judge agreement
  history <task | set@vN> [--json]       every finished run per contestant over time, with possible drops
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
    # Hugging Face (not a model provider here): gated datasets such as HLE need a token after you accept their terms.
    "hf": "HF_TOKEN",
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
           "where": {w: where_ready(w) if w != "local" else dk.startswith("running") for w in WHERE},
           "agents": agents_state()}
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
    if p in PROVIDER_ENV and not model.startswith(FREE_PREFIXES) and not env.get(PROVIDER_ENV[p]):
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


def seat_estimate_row(task: str, agent: str, limit: int, epochs: int, seat_limit: float | None = None) -> dict:
    """An agent on your seat: no dollars, a share of the seat's five-hour window (HP EV-1)."""
    ar = _sibling("agent_runner")
    if agent not in ar.SEAT_AGENTS:
        die(f"{AGENT_NAMES.get(agent, agent)} cannot run on a seat yet", 2, True)
    s = ar.seat_estimate(agent, limit, epochs, seat_limit)
    return dict(s, task=task_name(task), model=f"seat/{s['seat']}", agent=agent, samples=limit, epochs=epochs, calls=limit * epochs,
                tokens_per_sample={"input": 0, "output": 0}, token_basis="a share of your seat's 5-hour window, not tokens",
                usd=0.0, model_usd=0.0, cap_check_usd=0.0, grader={"models": [], "usd": 0.0, "basis": "none"}, where="local")


def cmd_estimate(argv):
    pos, o = args_of(argv, {"--model": "", "--limit": "50", "--epochs": "1", "--where": "local", "--agent": "", "--seat": "",
                            "--seat-limit": "", "--json": False})
    if len(pos) == 1 and o["seat"]:
        e = seat_estimate_row(pos[0], o["agent"], int(o["limit"]), int(o["epochs"]),
                              float(o["seat_limit"]) if o["seat_limit"] else None)
        out(e, o["json"], f"{e['task']} × {AGENT_NAMES.get(o['agent'], o['agent'])} on {e['seat']}: {e['calls']} cases · about "
            f"{e['seat_share'] * 100:.1f} % of the seat's 5-hour window ({e['seat_basis']})")
        return
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
    if r.get("sample_id"):
        c += ["--sample-id", str(r["sample_id"])]   # LAB-2064: Run just this one
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
                            "--sample-id": "", "--seat": "", "--seat-limit": "", "--wait": False,
                            "--json": False})
    if len(pos) == 1 and o["seat"]:
        return run_on_seat(pos[0], o)
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
    if o["sample_id"]:
        limit = len([x for x in o["sample_id"].split(",") if x])   # one question (or a few): priced and run at that size
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
         "sample_id": o["sample_id"] or None,
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
                             stdin=subprocess.DEVNULL, start_new_session=True, env=env, cwd=str(d))
        out({"id": rid, "pid": p.pid, "estimate": est}, o["json"], f"started {rid} in the background (pid {p.pid})")
        return
    rc = work(rid, env)
    rr = read_json(d / "run.json")
    out(dict(rr, results=results_for(rid)), o["json"], render_result(rid))
    sys.exit(0 if rr["status"] == "done" else 1)


def run_on_seat(task: str, o: dict):
    """HP EV-1: an agent CLI on your subscription seat answers your own set, one fresh worktree per case. Refused before
    it starts when the seat would pass its limit (unless --wait: then it queues and waits); never fails mid-run for it."""
    ar = _sibling("agent_runner")
    agent = o["agent"]
    if agent not in ar.SEAT_AGENTS:
        why = (ar.NOT_YET.get(agent) or (agent, agent, "not an agent One Roof knows"))[2]
        die(f"{AGENT_NAMES.get(agent, agent)} cannot run on a seat: {why}", 2, o["json"])
    task = str(Path(os.path.expanduser(task)).resolve())
    sname, sver = set_of(task)
    if not sname or not os.path.isfile(task):
        die("agents on your seats answer your own eval sets; for a benchmark, run the agent on an API model "
            "(--agent with --model)", 2, o["json"])
    if not ar.find_bin(agent):
        die(f"{ar.SEAT_AGENTS[agent]['bin']} is not installed on this Mac", 6, o["json"])
    meta, cases = ar.load_set(task)
    limit = min(int(o["limit"]), len(cases)) if o["limit"] else len(cases)
    if o["sample_id"]:
        limit = len([x for x in o["sample_id"].split(",") if x])
    epochs = int(o["epochs"]) if o["epochs"] else None
    lim = float(o["seat_limit"]) if o["seat_limit"] else None
    est = seat_estimate_row(task, agent, limit, epochs or 1, lim)
    if not est["seat_fits"] and not o["wait"]:
        die(f"{est['seat']} is at {est['seat_used']:.0f} % of its 5-hour window; this run needs about "
            f"{est['seat_share'] * 100:.0f} % more and would pass the {est['seat_limit']:.0f} % limit. Wait for the window "
            "to reset, or start it with --wait to queue it", 9, o["json"])
    es = _sibling("evalset")
    rid = new_run_id(task)
    d = RUNS / rid
    d.mkdir(parents=True)
    r = {"id": rid, "task": task_name(task), "task_ref": task, "model": f"seat/{est['seat']}", "limit": limit, "epochs": epochs,
         "seed": None, "temperature": None, "task_args": [], "where": "local", "agent": agent, "seat": est["seat"],
         "seat_limit": est["seat_limit"], "runner": "seat", "sample_id": o["sample_id"] or None, "max_cost": 0.0,
         "repo_path": es.repo_of(meta), "estimate": est, "status": "queued", "created": now(), "dir": str(d),
         "cap_mode": "no API credit: the agent runs on your subscription seat"}
    write_json(d / "run.json", r)
    env = ar.strip_keys(dict(os.environ))
    if o["background"]:
        log = open(d / "console.log", "ab")
        p = subprocess.Popen([sys.executable, str(Path(__file__).resolve()), "_worker", rid], stdout=log, stderr=log,
                             stdin=subprocess.DEVNULL, start_new_session=True, env=env, cwd=str(d))
        out({"id": rid, "pid": p.pid, "estimate": est}, o["json"], f"started {rid} in the background (pid {p.pid})")
        return
    rc = work(rid)
    rr = read_json(d / "run.json")
    out(dict(rr, results=results_for(rid)), o["json"], render_result(rid))
    sys.exit(0 if rc == 0 else 1)


def set_status(d: Path, **kw):
    r = read_json(d / "run.json", {})
    r.update(kw)
    write_json(d / "run.json", r)
    return r


def run_cwd(r: dict) -> str:
    """Where Inspect runs: a task file's own folder, otherwise the run's folder. Never the caller's folder: a run started
    from a worktree that is removed mid-run would crash at the end (Inspect's closing panel calls getcwd; LAB-1993)."""
    return task_cwd(r) or r["dir"]


def final_status(rc: int, log_status: str | None, cancelled: bool) -> str:
    """The log decides. Inspect can exit 0 with every call failed (log status 'error'), and can exit non-zero AFTER a
    complete, scored log (a closing or sandbox-shutdown error): that run is done, with the error kept as a note."""
    if cancelled:
        return "cancelled"
    return "done" if log_status == "success" else "failed"


def work(rid: str, env: dict | None = None, retry_log: str | None = None) -> int:
    d = RUNS / rid
    if read_json(d / "run.json", {}).get("runner") == "seat":   # an agent on your seat: no Inspect, no API key
        rc = _sibling("agent_runner").work(rid)
        index()
        r = read_json(d / "run.json", {})
        if r.get("status") != "done" and r.get("error"):
            set_status(d, hint=hint_for(r["error"]))
        return rc
    r = set_status(d, status="running", started=now(), pid=os.getpid())
    cmd = [str(INSPECT), "eval-retry", retry_log, "--log-dir", str(d)] if retry_log else inspect_cmd(r)
    with open(d / "console.log", "ab") as log:
        env = dict(env or run_env(r["model"]))
        if r.get("where") == "modal":
            # Modal 1.5 (held for inspect-sandboxes) predates the newest image builder new accounts default to.
            env.setdefault("MODAL_IMAGE_BUILDER_VERSION", MODAL_IMAGE_BUILDER)
        p = subprocess.Popen(cmd, stdout=log, stderr=subprocess.STDOUT, env=env, cwd=run_cwd(r))
        set_status(d, child=p.pid)
        rc = p.wait()
    index()
    # The log decides: Inspect can exit 0 with every call failed (e.g. a rejected key) and status 'error'.
    with sqlite3.connect(DB) as db:
        row = db.execute("SELECT log_status, error FROM runs WHERE id=?", (rid,)).fetchone()
    log_status, err = row if row else (None, None)
    status = final_status(rc, log_status, (d / "CANCEL").exists())
    if status != "done" and not err:
        try:  # errors before the log exists (dataset download, missing package) are only in the console
            lines = [x for x in (d / "console.log").read_text(errors="ignore").splitlines() if x.strip()]
            err = next((x for x in reversed(lines) if re.search(r"Error|error:|requires", x)), lines[-1] if lines else None)
        except OSError:
            pass
    error = None if status == "done" else redact(err or f"inspect exited {rc}; see console.log")[:2000]
    closing = None
    if status == "done" and rc != 0:   # scored and logged, then Inspect failed while closing: keep why, as a note
        try:
            lines = [x for x in (d / "console.log").read_text(errors="ignore").splitlines() if x.strip()]
            closing = redact(next((x for x in reversed(lines) if "Error" in x), f"inspect exited {rc}"))[:500]
        except OSError:
            closing = f"inspect exited {rc}"
    set_status(d, status=status, finished=now(), returncode=rc, log_status=log_status, error=error,
               closing_error=closing, hint=hint_for(err) if status != "done" else None)
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
            if r.get("child_group"):   # an agent on a seat: its whole process group
                os.killpg(os.getpgid(r["child"]), signal.SIGTERM)
            else:
                os.kill(r["child"], signal.SIGINT)
        except OSError:
            pass
    if r.get("status") in ("queued", "running", "waiting", "interrupted") and not pid_alive(r.get("pid")):
        set_status(d, status="cancelled", finished=now())
    out({"id": argv[0], "cancelled": True}, o["json"], f"cancel sent to {argv[0]}")


def cmd_run_anyway(argv):
    """QA (M9): the owner's Run anyway for a seat run waiting because the seat's use is unknown or stale."""
    _, o = args_of(argv[1:], {"--json": False})
    if not argv:
        die("run-anyway <run>", 2, o["json"])
    d = run_dir(argv[0])
    r = read_json(d / "run.json", {})
    if r.get("runner") != "seat":
        die(f"{argv[0]} is not an agent run on a seat", 2, o["json"])
    if r.get("status") in ("done", "failed", "cancelled"):
        die(f"{argv[0]} already {r['status']}", 3, o["json"])
    r = _sibling("agent_runner").run_anyway(d)
    out({"id": argv[0], "seat_unknown_ok": True, "at": r.get("seat_unknown_ok_at")}, o["json"],
        f"{argv[0]} goes on without knowing {r.get('seat')}'s use (from the next case)")


def latest_log(d: Path) -> Path | None:
    logs = sorted(d.glob("*.eval"), key=lambda p: p.stat().st_mtime)
    return logs[-1] if logs else None


def cmd_resume(argv):
    _, o = args_of(argv[1:], {"--json": False})
    if not argv:
        die("resume <run>", 2)
    d = run_dir(argv[0])
    if read_json(d / "run.json", {}).get("runner") == "seat":   # answered cases are kept; the rest are asked again
        if read_json(d / "run.json", {}).get("status") in ("running", "waiting", "queued") and pid_alive(read_json(d / "run.json", {}).get("pid")):
            die(f"{argv[0]} is still going", 3, o["json"])
        (d / "CANCEL").unlink(missing_ok=True)
        set_status(d, status="queued", error=None, hint=None, finished=None)
        logf = open(d / "console.log", "ab")
        env = _sibling("agent_runner").strip_keys(dict(os.environ))
        p = subprocess.Popen([sys.executable, str(Path(__file__).resolve()), "_worker", argv[0]], stdout=logf, stderr=logf,
                             stdin=subprocess.DEVNULL, start_new_session=True, env=env, cwd=str(d))
        out({"id": argv[0], "pid": p.pid}, o["json"], f"resuming {argv[0]} (pid {p.pid}); answered cases are kept")
        return
    log = latest_log(d)
    if not log:
        die("nothing to resume: the run never wrote a log; start it again", 3)
    (d / "CANCEL").unlink(missing_ok=True)
    r = read_json(d / "run.json")
    env = run_env(r["model"])
    logf = open(d / "console.log", "ab")
    p = subprocess.Popen([sys.executable, str(Path(__file__).resolve()), "_retry", argv[0], str(log)], stdout=logf,
                         stderr=logf, stdin=subprocess.DEVNULL, start_new_session=True, env=env, cwd=str(d))
    out({"id": argv[0], "pid": p.pid}, o["json"], f"resuming {argv[0]} (pid {p.pid}); samples already done are kept")


def cmd_status(argv):
    _, o = args_of(argv, {"--json": False})
    rows = []
    for f in sorted(RUNS.glob("*/run.json")) if RUNS.exists() else []:
        r = read_json(f, {})
        if r.get("status") in ("running", "queued", "waiting") and r.get("pid") and not pid_alive(r.get("pid")):
            r = set_status(f.parent, status="cancelled" if (f.parent / "CANCEL").exists() else "interrupted")
        rows.append(status_row(r, f.parent))
    out(rows, o["json"], "\n".join(f"{r['id']:<44} {r['model']:<36} {r['status']:<11} {r['progress']}" for r in rows)
        or "no runs yet")


def status_row(r: dict, d: Path) -> dict:
    """A queue row (HP EV-2): who is running, how far, and why it stopped (the last line of the error and what to do)."""
    err = r.get("error")
    last = redact(err.strip().splitlines()[-1][:300]) if err and err.strip() else None
    sname, sver = set_of(r.get("task_ref") or "")
    return dict({k: r.get(k) for k in ("id", "task", "model", "limit", "epochs", "status", "created", "finished", "agent",
                                       "seat", "waiting", "where", "seat_unknown_ok")},
                progress=progress(d), error=last, hint=(r.get("hint") or hint_for(err)) if last else None,
                contestant=contestant(r.get("model"), r.get("agent")), set_name=sname, set_version=sver,
                task_ref=r.get("task_ref"))


def progress(d: Path) -> str:
    """Samples finished: the .eval log is a zip that gains one samples/<id>_epoch_<n>.json per scored sample (flushed in
    small batches while running); Inspect's plain display ('Samples: 12/50') is the fallback."""
    r = read_json(d / "run.json", {})
    total = (r.get("limit") or 0) * (r.get("epochs") or 1)
    if r.get("runner") == "seat":   # an agent on a seat: one line per answered case
        p = d / "answers.jsonl"
        n = len([x for x in p.read_text().splitlines() if x.strip()]) if p.exists() else 0
        return f"{n}/{total}" if total else str(n)
    log = latest_log(d)
    if not log and (r.get("summary") or {}).get("samples_done") is not None:   # lm-eval: no Inspect log, a summary
        n = r["summary"]["samples_done"]
        return f"{n}/{total}" if total else str(n)
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
  log_status TEXT, error TEXT, where_run TEXT, sample_seconds REAL, agent TEXT, set_name TEXT, set_version INTEGER);
CREATE TABLE IF NOT EXISTS scores (run_id TEXT, scorer TEXT, metric TEXT, value REAL,
  PRIMARY KEY (run_id, scorer, metric));
-- LAB-2064: one row per question and attempt, so per-question dots, solve counts and paired compares read no logs.
CREATE TABLE IF NOT EXISTS sample_scores (run_id TEXT, sample_id TEXT, epoch INTEGER, score REAL,
  PRIMARY KEY (run_id, sample_id, epoch));
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
    secs, samples = 0.0, []
    try:
        from inspect_ai.log import read_eval_log_sample_summaries
        from inspect_ai.scorer import value_to_float
        to_f = value_to_float()
        for x in read_eval_log_sample_summaries(p):
            secs += x.total_time or 0
            sc = next(iter((x.scores or {}).values()), None)
            v = None
            if sc is not None and not isinstance(sc.value, dict):
                try:
                    v = to_f(sc.value)
                except Exception:
                    v = None
            samples.append([str(x.id), x.epoch, v])
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
      "cost": sum(cost) if cost else None, "usage": usage, "sample_seconds": secs, "samples": samples,
      "scores": [{"scorer": s.name, "metrics": {k: m.value for k, m in s.metrics.items()}} for s in (l.results.scores if l.results else [])]}
print(json.dumps(out))
"""


SET_PATH = re.compile(r"/sets/([^/]+)/v(\d+)/[^/]+\.py$")


def set_of(task_ref: str) -> tuple:
    """Your own eval set's name and version from its task file path (<evals>/sets/<name>/v<N>/<task>.py), else (None, None).
    Runs keep the version they ran on, so scores are only ever compared within one frozen version (LAB-2062, LAB-2065)."""
    m = SET_PATH.search(task_ref or "")
    return (m.group(1), int(m.group(2))) if m else (None, None)


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
            h = heads.get(str(logs[d]), {}) if logs[d] else (r.get("summary") or {})   # lm-eval runs: no Inspect log
            pk = h.get("packages") or {}
            sname, sver = set_of(r.get("task_ref") or "")
            db.execute("INSERT INTO runs VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)", (
                r.get("id"), r.get("task"), h.get("task_version"), r.get("model"), r.get("status"),
                h.get("started") or r.get("started"), h.get("finished") or r.get("finished"), r.get("limit"),
                r.get("epochs"), r.get("seed"), r.get("temperature"), r.get("max_cost"),
                (r.get("estimate") or {}).get("usd"), h.get("cost"), h.get("input_tokens"), h.get("output_tokens"),
                h.get("samples_total"), h.get("samples_done"), h.get("dataset"), h.get("dataset_size"),
                pk.get("inspect_ai"), pk.get("inspect_evals"), str(logs[d]) if logs[d] else r.get("results_file"),
                r.get("framework") or "inspect",
                h.get("status"), redact(h.get("error") or r.get("error")), r.get("where") or "local", h.get("sample_seconds"), r.get("agent"),
                sname, sver))
            for sid, ep, v in h.get("samples") or []:
                db.execute("INSERT OR REPLACE INTO sample_scores VALUES (?,?,?,?)", (r.get("id"), sid, ep, v))
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
    for r in runs:
        r["contestant"] = contestant(r.get("model"), r.get("agent"))
        r["task_ref"] = (read_json(RUNS / str(r["id"]) / "run.json", {}) or {}).get("task_ref")   # Run again (LAB-2069)
        a = judge_agreement(r)
        if a:
            r["judge_agreement"] = a
    return runs


# ── contestants (HP EV-2): agents first, then models, then models on this Mac, then the no-model baseline ─────────────
AGENT_NAMES = {"claude_code": "Claude Code", "codex_cli": "Codex", "opencode": "OpenCode", "kimi_code": "Kimi",
               "gemini_cli": "Gemini CLI", "antigravity": "Antigravity", "mini_swe_agent": "mini-SWE-agent"}
LOCAL_PREFIXES = ("ollama/", "openai-api/local/", "hf/", "llama-cpp-python/", "vllm/", "sglang/")
KIND_RANK = {"agent": 0, "model": 1, "local": 2, "baseline": 3}


def short_model(model: str) -> str:
    if not model or model.startswith(FREE_PREFIXES):
        return model or "?"
    return model.split("/", 1)[-1]


def contestant(model, agent) -> dict:
    """Who is being measured: an agent (its CLI is the subject, the model its brain), a model (API), a model on this Mac,
    or the baseline (the mock stand-in that always gives the same answer)."""
    model = model or ""
    if agent and model.startswith("seat/"):   # the agent on your subscription seat (HP EV-1)
        return {"kind": "agent", "id": f"{agent}@{model}", "agent": agent, "model": model, "seat": model[5:],
                "name": f"{AGENT_NAMES.get(agent, agent)} · {model[5:]}"}
    if agent:
        return {"kind": "agent", "id": f"{agent}@{model}", "agent": agent, "model": model,
                "name": f"{AGENT_NAMES.get(agent, agent)} · {short_model(model)}"}
    if model.startswith("mockllm/"):
        return {"kind": "baseline", "id": model, "model": model, "name": model}
    if model.startswith(LOCAL_PREFIXES):
        return {"kind": "local", "id": model, "model": model, "name": short_model(model)}
    return {"kind": "model", "id": model, "model": model, "name": short_model(model)}


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
    if r.get("judge_agreement"):
        lines.append("  judge: " + _sibling("judge").render(r["judge_agreement"]))
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
      "item": (s.metadata or {}).get("item"),
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


def sample_rows(rid: str, as_json: bool = False) -> list[dict]:
    """Every answer of a run: from its Inspect log; an agent on a seat keeps its answers in answers.jsonl; a run with
    neither (lm-eval) has only the per-question scores of the index."""
    d = run_dir(rid)
    log = latest_log(d)
    if log:
        need_engine(as_json)
        r = subprocess.run([str(VPY), "-c", _SAMPLES_CODE, str(log)], capture_output=True, text=True)
        if r.returncode != 0:
            die(f"could not read the log: {r.stderr.strip()[-300:]}", 8, as_json)
        return json.loads(r.stdout)
    ans = d / "answers.jsonl"
    if ans.exists():
        rows = []
        for line in ans.read_text().splitlines():
            try:
                a = json.loads(line)
            except ValueError:
                continue
            rows.append({"id": a["id"], "epoch": a["epoch"], "score": a.get("score"), "answer": a.get("answer"),
                         "target": a.get("target"), "input": a.get("input"), "output": (a.get("output") or "")[:400],
                         "explanation": a.get("explanation"), "time": a.get("time"), "error": a.get("error")})
        return rows
    if DB.exists():
        with sqlite3.connect(DB) as db:
            got = db.execute("SELECT sample_id, epoch, score FROM sample_scores WHERE run_id=? ORDER BY sample_id, epoch",
                             (rid,)).fetchall()
        if got:
            return [{"id": a, "epoch": b, "score": c} for a, b, c in got]
    die("This run has no log yet", 3, as_json)


def cmd_samples(argv):
    pos, o = args_of(argv, {"--json": False})
    if len(pos) != 1:
        die("samples <run>", 2, o["json"])
    rows = with_verdicts(pos[0], sample_rows(pos[0], o["json"]))
    for x in rows:
        x["error"] = redact(x.get("error"))
    out(rows, o["json"], "\n".join(f"{x['id']:<24} e{x['epoch']} score={x.get('score')} answer={x.get('answer')!r} target={x.get('target')!r}"
                                   for x in rows) or "no samples yet")


def cmd_sample(argv):
    pos, o = args_of(argv, {"--epoch": "1", "--json": False})
    if len(pos) != 2:
        die("sample <run> <id> [--epoch N]", 2, o["json"])
    d = run_dir(pos[0])
    log = latest_log(d)
    if not log and (d / "answers.jsonl").exists():   # an agent on a seat: the question it got and its final message
        a = next((x for x in sample_rows(pos[0], o["json"]) if x["id"] == pos[1] and str(x["epoch"]) == o["epoch"]), None)
        if not a:
            die("no such sample", 3, o["json"])
        full = json.loads(next(line for line in (d / "answers.jsonl").read_text().splitlines()
                               if json.loads(line)["id"] == pos[1] and str(json.loads(line)["epoch"]) == o["epoch"]))
        r0 = read_json(d / "run.json", {})
        ask = _sibling("agent_runner").SYSTEM.get((read_json(Path(r0.get("task_ref", "")).parent / "set.json", {}) or {}).get("kind"), "")
        msgs = [{"role": "system", "text": ask, "tool_calls": []}, {"role": "user", "text": full.get("input") or "", "tool_calls": []},
                {"role": "assistant", "text": full.get("output") or full.get("error") or "", "tool_calls": []}]
        d2 = {"id": pos[1], "epoch": int(o["epoch"]), "target": full.get("target"), "messages": msgs,
              "scores": {"fix_located": {"value": "C" if full.get("score") else "I", "answer": full.get("answer"),
                                         "explanation": full.get("explanation")}},
              "time": full.get("time"), "error": full.get("error")}
        out(d2, o["json"], "\n\n".join(f"[{m['role']}]\n{m['text']}" for m in msgs))
        return
    need_engine(o["json"])
    if not log:
        die("This run has no log yet", 3, o["json"])
    r = subprocess.run([str(VPY), "-c", _SAMPLE_CODE, str(log), pos[1], o["epoch"]], capture_output=True, text=True)
    if r.returncode != 0:
        die(f"could not read the log: {r.stderr.strip()[-300:]}", 8, o["json"])
    d = json.loads(r.stdout)
    if d.get("error"):
        d["error"] = redact(d["error"])
    out(d, o["json"], "\n\n".join(f"[{m['role']}]\n{m['text']}" for m in d.get("messages", [])) or json.dumps(d))


# ── LAB-2067/2068/2069 (stage 2): agents, power, compare, leaderboard, history, verdicts per answer ──────────────────
def agents_state() -> list[dict]:
    try:   # doctor must answer even when the agent runner cannot look at the seats
        return _sibling("agent_runner").agents_state()
    except Exception as e:
        print(f"roof eval: agents were skipped: {e}", file=sys.stderr)
        return []


def power(n: int, epochs: int = 1, p: float = 0.5) -> dict:
    """HP EV-9: the ± points a run of n questions × epochs attempts can tell apart (Wilson half-width at p): differences
    smaller than this are noise. Every contestant answers the same questions, so they compare question by question."""
    total = max(n * max(epochs, 1), 1)
    lo, hi, _ = interval(p, total, None, True)
    half = (hi - lo) / 2
    return {"n": n, "epochs": max(epochs, 1), "p": p, "method": "wilson", "plus_minus_points": round(half * 100, 1)}


def cmd_power(argv):
    _, o = args_of(argv, {"--n": "", "--epochs": "1", "--p": "0.5", "--paired": False, "--json": False})
    if not o["n"]:
        die("power --n N [--epochs E] [--p 0.5]", 2, o["json"])
    r = power(int(o["n"]), int(o["epochs"] or 1), float(o["p"]))
    r["paired"] = bool(o["paired"])
    out(r, o["json"], f"{r['n']} questions × {r['epochs']} attempts: about ±{r['plus_minus_points']:.0f} points")


def solved(means: dict) -> set:
    return {k for k, v in means.items() if v is not None and v >= 0.5}


def compare_runs(a: str, b: str) -> dict | None:
    """The engine's twin of the app's EvalStats.compare (HP blend), plus the questions only one of them solved."""
    ma, mb = sample_means(a), sample_means(b)
    c = paired_compare(ma, mb)
    if c is None:
        return None
    shared = set(ma) & set(mb)
    sa, sb = solved(ma) & shared, solved(mb) & shared
    c = dict(c, verdict={"a_better": "a", "b_better": "b"}.get(c["verdict"], "noise"), a=a, b=b,
             only_a=sorted(sa - sb), only_b=sorted(sb - sa), tied=len(shared) - len(sa ^ sb))
    return c


def cmd_compare(argv):
    pos, o = args_of(argv, {"--json": False})
    if len(pos) != 2:
        die("compare <runA> <runB>", 2, o["json"])
    index()
    for x in pos:
        if not (RUNS / x / "run.json").exists():
            die(f"no run {x}", 3, o["json"])
    c = compare_runs(*pos)
    if c is None:
        die("too few scored questions to compare (each run needs at least 2)", 3, o["json"])
    word = {"a": f"{pos[0]} is better", "b": f"{pos[1]} is better", "noise": "can't tell them apart yet"}[c["verdict"]]
    if c.get("too_few"):
        word = f"can't tell them apart yet: too few shared questions ({c['n']})"
    out(c, o["json"], f"{word}: {c['diff'] * 100:+.0f} points, 95 % {c['ci95'][0] * 100:+.0f} to {c['ci95'][1] * 100:+.0f} "
        f"over {c['n']} {'shared questions (paired)' if c['paired'] else 'questions (unpaired)'}; only A solved "
        f"{len(c['only_a'])}, only B {len(c['only_b'])}, {c['tied']} tied")


def parse_key(k: str) -> tuple:
    """'oneroof@v1' → ('set', 'oneroof', 1); 'gsm8k' → ('task', 'gsm8k', None)."""
    m = re.match(r"^(.+)@v(\d+)$", k)
    return ("set", m.group(1), int(m.group(2))) if m else ("task", k, None)


def key_text(key: tuple) -> str:
    return f"{key[1]}@v{key[2]}" if key[0] == "set" else str(key[1])


def chance_share(task: str) -> float | None:
    """A benchmark's chance level as a share (anatomy.json, reviewed): '25 %' → 0.25, '≈ 0 %' → 0."""
    try:
        b = catalog_entry(task) or {}
    except Exception:
        b = {}
    ch = (anatomy_table().get(b.get("folder") or task) or {}).get("chance") or ""
    m = re.search(r"(\d+(?:\.\d+)?)\s*%", ch)
    return float(m.group(1)) / 100 if m else None


def eval_info(key: tuple) -> dict:
    """Title, cases, kind and the floor of one eval (one set version or one benchmark task)."""
    if key[0] == "set":
        try:
            vs = {(s["name"], s["version"]): s for s in _sibling("evalset").all_versions()}
        except Exception:
            vs = {}
        s = vs.get((key[1], key[2])) or {}
        floor = {"right": s.get("baseline_frequent_files"), "of": s.get("count"), "kind": "no-model floor"} if s else None
        share = (floor["right"] / floor["of"]) if floor and floor["of"] and floor["right"] is not None else None
        versions = sorted(v for (n, v) in vs if n == key[1])
        return {"key": key_text(key), "title": eval_title(key, vs), "set": key[1], "version": key[2], "kind": s.get("kind"),
                "cases": s.get("count"), "task_file": s.get("task_file"), "floor": share, "floor_kind": "no-model floor",
                "floor_counts": floor, "versions": versions, "judged": s.get("kind") == "triage"}
    share = chance_share(str(key[1]))
    return {"key": key_text(key), "title": str(key[1]), "task": key[1], "cases": None, "floor": share,
            "floor_kind": "chance" if share is not None else None, "versions": [], "judged": str(key[1]).startswith("judge_")}


def judge_for(info: dict) -> dict | None:
    """The judge that grades this eval's answers, with its agreement with you (judged scores always show it)."""
    try:
        j = _sibling("judge")
        for name in sorted(p.name for p in j.JUDGES.glob("*") if (p / "judge.json").exists()) if j.JUDGES.is_dir() else []:
            meta = read_json(j.JUDGES / name / "judge.json", {}) or {}
            task = meta.get("task") or ""
            if info.get("task") == f"judge_{name}" or str(info.get("task") or "").startswith(f"judge_{name}_v") or \
                    (info.get("set") and task.startswith(f"own_{info['set']}_v")):
                t = j.trust(name)
                return {"name": name, "agreement": t.get("agreement"), "n": t.get("n"), "tpr": t.get("tpr"),
                        "tnr": t.get("tnr"), "ready": t.get("ready"), "reference": t.get("reference")}
    except (Exception, SystemExit) as e:
        print(f"roof eval: judge skipped: {e}", file=sys.stderr)
    return None


def runs_of_key(key: tuple, statuses=("done",)) -> list[dict]:
    rs = [r for r in results_for() if r.get("status") in statuses and not str(r.get("task") or "").startswith("labeller_")]
    return [r for r in rs if eval_key(r) == key]


def leaderboard(k: str) -> dict:
    """HP EV-8: the latest finished run per contestant on one eval version, agents first then best first, the baseline
    last; the floor; the judge's agreement for judged evals; cost and $ per right answer."""
    key = parse_key(k)
    info = eval_info(key)
    runs = runs_of_key(key)
    rows = leaderboard_rows(runs)
    rows = [x for x in rows if x["kind"] != "baseline"] + [x for x in rows if x["kind"] == "baseline"]
    failed = [r for r in runs_of_key(key, ("failed",))]
    latest_failed = None
    if failed and (not runs or (failed[0].get("started") or "") > (runs[0].get("started") or "")):
        f = failed[0]
        latest_failed = {"run": f["id"], "error": (f.get("error") or "").strip().splitlines()[-1][:300] if f.get("error") else None,
                         "hint": hint_for(f.get("error"))}
    return dict(info, rows=rows, runs=len(runs), judge=judge_for(info) if info.get("judged") else None, latest_failed=latest_failed)


def cmd_leaderboard(argv):
    pos, o = args_of(argv, {"--json": False})
    if len(pos) != 1:
        die("leaderboard <task | set@vN>", 2, o["json"])
    index()
    lb = leaderboard(pos[0])
    lines = [lb["title"] + (f" · floor {lb['floor'] * 100:.0f} %" if lb.get("floor") is not None else "")]
    for i, r in enumerate(lb["rows"], 1):
        sc = "–" if r["score"] is None else f"{r['score'] * 100:.0f} %"
        lines.append(f"  {'-' if r['kind'] == 'baseline' else i:<3} {r['kind']:<8} {r['contestant']:<36} {sc:>6}  n={r['n']}  {r['run']}")
    out(lb, o["json"], "\n".join(lines))


def history_of(k: str) -> dict:
    """HP EV-8: every finished run per contestant on one eval version, oldest first; a drop is a contestant's latest
    score below its previous one, 'possible' unless the paired range of the difference excludes 0 (HP G4)."""
    key = parse_key(k)
    runs = sorted(runs_of_key(key), key=lambda r: r.get("started") or "")
    series: dict = {}
    for r in runs:
        c = r.get("contestant") or contestant(r.get("model"), r.get("agent"))
        p = primary(r) or {}
        s = series.setdefault(c["id"], {"contestant": c["name"], "kind": c["kind"], "points": []})
        s["points"].append({"run": r["id"], "date": r.get("started"), "score": p.get("value"), "ci95": p.get("ci95"),
                            "n": p.get("n"), "epochs": r.get("epochs")})
    drops = []
    for cid, s in series.items():
        pts = [x for x in s["points"] if x["score"] is not None]
        if len(pts) < 2 or pts[-1]["score"] >= pts[-2]["score"]:
            continue
        a, b = pts[-1], pts[-2]
        c = compare_runs(a["run"], b["run"])
        possible = not (c and c["verdict"] == "b")
        pts_ = round((a["score"] - b["score"]) * 100)
        day = EvalDay.of(a["date"])
        text = (f"{s['contestant']} dropped {-pts_} points on {day}, inside its range. Re-run with 3 attempts to check."
                if possible else f"{s['contestant']} dropped {-pts_} points on {day}, outside its range: a real drop. "
                                 "Open both runs to see the cases it lost.")
        drops.append({"contestant": s["contestant"], "id": cid, "run": a["run"], "prev_run": b["run"],
                      "delta": round(a["score"] - b["score"], 4), "possible": possible, "text": text})
    order = sorted(series.values(), key=lambda s: (KIND_RANK.get(s["kind"], 9), s["contestant"]))
    dates = [r.get("started") for r in runs if r.get("started")]
    return {"key": key_text(key), "series": order, "drops": drops, "first": dates[0] if dates else None,
            "last": dates[-1] if dates else None, "floor": eval_info(key).get("floor")}


class EvalDay:
    @staticmethod
    def of(iso: str | None) -> str:
        try:
            return datetime.strptime((iso or "")[:10], "%Y-%m-%d").strftime("%b %-d")
        except ValueError:
            return iso or "?"


def cmd_history(argv):
    pos, o = args_of(argv, {"--json": False})
    if len(pos) != 1:
        die("history <task | set@vN>", 2, o["json"])
    index()
    h = history_of(pos[0])
    lines = [f"{s['contestant']}: " + ", ".join("–" if p["score"] is None else f"{p['score'] * 100:.0f}" for p in s["points"])
             for s in h["series"]] + [d["text"] for d in h["drops"]]
    out(h, o["json"], "\n".join(lines) or "no finished runs on this eval")


def with_verdicts(rid: str, rows: list[dict]) -> list[dict]:
    """HP EV-10: beside each answer, the code check, the judge and you, and whether the judge disagrees with you.
    Code check: your set's own scorer (or a benchmark's scorer); for a judge run, the set's check on the judged answer.
    Judge: a judge run's own verdict, or the verdict of a judge whose items come from this run. You: your label."""
    r = read_json(RUNS / rid / "run.json", {}) or {}
    task = str(r.get("task") or "")
    sname, _ = set_of(r.get("task_ref") or "")
    try:
        j = _sibling("judge")
    except Exception:
        j = None
    judge_items: dict = {}   # item id → (judge name, item, owner label, judge verdict)
    jt = j.judge_of_task(task) if j else None
    if j and j.JUDGES.is_dir():
        for jd in sorted(p for p in j.JUDGES.glob("*") if (p / "judge.json").exists()):
            try:
                items = {x["id"]: x for x in j.items_of(jd)}
            except (OSError, ValueError, KeyError):
                continue
            if jt and jd.name != jt[0]:
                continue
            if not jt:   # only the items this run answered (ids carry just a 4-letter run suffix)
                items = {k: x for k, x in items.items() if x.get("run") == rid}
                if not items:
                    continue
            try:
                last = (j.last_run(jd.name) or {}).get("verdicts") or {}
            except (Exception, SystemExit):
                last = {}
            owner = j.labels_of(jd)
            for iid, x in items.items():
                judge_items[iid] = (jd.name, x, owner.get(iid), last.get(iid))
    suffix = rid.rsplit("-", 1)[-1]
    out_rows = []
    for x in rows:
        sid, ep = str(x["id"]), x.get("epoch") or 1
        sc = x.get("score")
        x = dict(x)
        iid = x.get("item") or (sid if jt else f"{suffix}:{sid}:{ep}")
        ji = judge_items.get(iid)
        question = (ji[1].get("question") if ji else None) or x.get("input") or ""
        key, report = j.report_of(question) if j else ("", question)
        x["issue"] = key or None
        x["title"] = (report.split("\n", 1)[0] or sid)[:160]
        if jt:   # a judge run: the score is the judge's verdict; the code check is the set's own check on the answer
            x["judge"] = {"verdict": "pass" if (sc or 0) >= 1 else "fail", "why": judge_reason(x.get("explanation"))}
            if ji and ji[1].get("target"):
                cd = j.code_detail(ji[1].get("answer") or "", ji[1]["target"])
                x["code"] = {"verdict": "pass" if cd["right"] else "fail",
                             "why": ("names " + ", ".join(cd["hits"]) + ", changed by the fix") if cd["right"] else
                             "The fix changed " + ", ".join(t for t in ji[1]["target"].splitlines() if t.strip()),
                             "named": cd["named"], "changed": [t for t in ji[1]["target"].splitlines() if t.strip()]}
        else:
            changed = [t for t in str(x.get("target") or "").splitlines() if t.strip()]
            right = sc is not None and sc >= 1
            why = x.get("explanation") or ""
            if sname and changed:
                names = [n.strip() for n in str(x.get("answer") or "").split(",") if n.strip()]
                hits = [n for n in names if any(f == n or f.endswith("/" + n) for f in changed)]
                why = ("names " + ", ".join(hits or names) + ", changed by the fix") if right else "The fix changed " + ", ".join(changed)
            x["code"] = {"verdict": "pass" if right else "fail" if sc is not None else "none", "why": why[:600],
                         "named": [n.strip() for n in str(x.get("answer") or "").split(",") if n.strip()] if sname else None,
                         "changed": changed if sname else None}
            if ji and ji[3]:
                x["judge"] = {"verdict": ji[3], "why": None}
        if ji:
            x["judge_item"] = {"judge": ji[0], "item": iid}
            if ji[2]:
                x["you"] = {"verdict": ji[2]["verdict"], "why": ji[2].get("why") or None}
        jv, yv = (x.get("judge") or {}).get("verdict"), (x.get("you") or {}).get("verdict")
        x["disagree"] = bool(jv and yv and jv != yv)
        x["labelled"] = yv is not None
        out_rows.append(x)
    return out_rows


def judge_reason(text: str | None) -> str | None:
    """The judge's one-line reason: its last sentence before the VERDICT line."""
    if not text:
        return None
    body = re.split(r"VERDICT:", text, flags=re.I)[0].strip()
    lines = [x.strip() for x in body.splitlines() if x.strip()]
    return (lines[-1] if lines else body)[:300] or None


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


def cmd_evalset(argv):
    """Your own eval sets (LAB-1995): evalset.py beside this file, standard library only."""
    os.execv(sys.executable, [sys.executable, str(HERE / "evalset.py"), *argv])


def cmd_judge(argv):
    """A model as judge, measured against your labels (LAB-1996): judge.py beside this file."""
    os.execv(sys.executable, [sys.executable, str(HERE / "judge.py"), *argv])


def _sibling(name: str):
    import importlib.util
    spec = importlib.util.spec_from_file_location(name, HERE / f"{name}.py")
    m = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(m)
    return m


def judge_agreement(r: dict) -> dict | None:
    """A judge run's agreement with your held-back labels, measured once from its log and kept (LAB-1996). Never fatal:
    results must show even when the judge folder is gone or damaged."""
    if not str(r.get("task") or "").startswith("judge_") or r.get("status") != "done":
        return None
    try:
        j = _sibling("judge")
        return j.cached(r["id"]) or j.measure(r["id"])
    except (Exception, SystemExit) as e:   # judge.py's die() exits; a results call must not
        print(f"roof eval: agreement for {r['id']} not measured: {e}", file=sys.stderr)
        return None


def cmd_lmeval(argv):
    """A second framework, lm-evaluation-harness, behind the same runs and results (LAB-1997): lmeval_adapter.py."""
    os.execv(sys.executable, [sys.executable, str(HERE / "lmeval_adapter.py"), *argv])


def own_benchmarks() -> list[dict]:
    """Your eval sets as catalog benchmarks, read fresh each time (a new set shows without a catalog refresh)."""
    try:   # cmd_run reads the catalog before every run: your sets must never stop a run
        return _sibling("evalset").catalog_entries()
    except Exception as e:
        print(f"roof eval: your eval sets were skipped: {e}", file=sys.stderr)
        return []


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
    curated = anatomy_table()
    cat = dict(cat, benchmarks=[dict(b, **catalog_extras(b, curated)) for b in cat["benchmarks"]])
    own = [dict(b, **catalog_extras(b, curated)) for b in own_benchmarks()]
    if own:
        cat = dict(cat, benchmarks=own + cat["benchmarks"], count=cat["count"] + len(own), tasks=cat["tasks"] + len(own),
                   categories=["Your evals"] + [c for c in cat.get("categories", []) if c != "Your evals"])
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


# ── LAB-2061 redesign: overview, anatomy, questions, published scores ─────────────────────────────────────────────────
def done_runs() -> list[dict]:
    """Finished runs, newest first, with their contestant (results_for), minus the judge's own helper runs."""
    return [r for r in results_for() if r.get("status") == "done" and not str(r.get("task") or "").startswith("labeller_")]


def sample_means(rid: str) -> dict:
    """Question → its mean score over attempts, from the index (no log read)."""
    if not DB.exists():
        return {}
    with sqlite3.connect(DB) as db:
        try:
            rows = db.execute("SELECT sample_id, AVG(score) FROM sample_scores WHERE run_id=? AND score IS NOT NULL "
                              "GROUP BY sample_id", (rid,)).fetchall()
        except sqlite3.OperationalError:
            return {}
    return {a: b for a, b in rows}


MIN_VERDICT_N = 10   # the fewest shared questions (or, unpaired, answers per run) a verdict needs; EvalStats.minVerdictN


def paired_compare(a: dict, b: dict) -> dict | None:
    """The engine's twin of the app's EvalStats.compare: paired over shared questions (≥ 2), else unpaired (Welch)."""
    shared = sorted(set(a) & set(b))
    if len(shared) >= 2:
        d = [a[k] - b[k] for k in shared]
        n = len(d)
        mean = sum(d) / n
        sd = math.sqrt(sum((x - mean) ** 2 for x in d) / (n - 1))
        half = 1.96 * sd / math.sqrt(n)
        lo, hi, paired = mean - half, mean + half, True
    else:
        xa, xb = list(a.values()), list(b.values())
        if len(xa) < 2 or len(xb) < 2:
            return None
        def mv(x):
            m = sum(x) / len(x)
            return m, sum((y - m) ** 2 for y in x) / (len(x) - 1)
        (m1, v1), (m2, v2) = mv(xa), mv(xb)
        se = math.sqrt(v1 / len(xa) + v2 / len(xb))
        mean, lo, hi, n, paired = m1 - m2, m1 - m2 - 1.96 * se, m1 - m2 + 1.96 * se, min(len(xa), len(xb)), False
    # QA (stage 2): under MIN_VERDICT_N shared questions no winner is called, however clear the interval looks (2 shared
    # questions with the same difference give a zero-width range).
    too_few = n < MIN_VERDICT_N
    verdict = "noise" if too_few else "a_better" if lo > 0 else "b_better" if hi < 0 else "noise"
    return {"diff": round(mean, 4), "ci95": [round(lo, 4), round(hi, 4)], "n": n, "paired": paired, "verdict": verdict,
            "too_few": too_few}


def primary(r: dict) -> dict | None:
    return next((m for m in r.get("metrics") or [] if m.get("value") is not None), None)


def eval_key(r: dict) -> tuple:
    """What a score is comparable within: one frozen version of your set, or one benchmark task."""
    return ("set", r["set_name"], r["set_version"]) if r.get("set_name") else ("task", r.get("task"), None)


def board_row(r: dict) -> dict:
    p = primary(r) or {}
    c = r.get("contestant") or contestant(r.get("model"), r.get("agent"))
    score, n = p.get("value"), p.get("n")
    cost = r.get("cost")
    free = (r.get("model") or "").startswith(FREE_PREFIXES) and not cost
    per_right = (round(cost / (score * n), 6) if cost and score and n and p.get("ci_method") == "wilson" else None)
    return {"contestant": c["name"], "kind": c["kind"], "agent": c.get("agent"), "model": r.get("model"), "run": r["id"],
            "score": score, "metric": p.get("metric"), "ci95": p.get("ci95"), "ci_method": p.get("ci_method"), "n": n,
            "epochs": r.get("epochs"), "cost": cost, "free": free,
            "seat": c["kind"] == "agent" and not cost,   # an agent on your seat; one run through Inspect on an API key paid dollars
            "usd_per_right": per_right, "date": r.get("started")}


def leaderboard_rows(runs: list[dict]) -> list[dict]:
    """The latest finished run per contestant; agents first, then models, models on this Mac, the baseline; best first."""
    latest = {}
    for r in runs:   # newest first
        cid = (r.get("contestant") or {}).get("id") or r.get("model")
        latest.setdefault(cid, r)
    rows = [board_row(r) for r in latest.values()]
    rows.sort(key=lambda x: (KIND_RANK.get(x["kind"], 9), -(x["score"] if x["score"] is not None else -1),
                             x["cost"] or 0.0, x["contestant"]))   # ties: the cheaper first
    return rows


def eval_title(key: tuple, sets: dict) -> str:
    if key[0] == "set":
        s = sets.get((key[1], key[2])) or {}
        kind = {"fix-locator": "fix locator", "triage": "bug triage"}.get(s.get("kind"), s.get("kind") or "")
        return f"{s.get('repo') or key[1]} · {kind} v{key[2]}".strip()
    return str(key[1])


def overview(since: str | None = None) -> dict:
    """Overview (LAB-2062): one call, so the app does no joins. Your evals (newest version of each set), then benchmarks
    run at least twice; what changed between each contestant's last two runs on the same eval; runs going now; one
    suggested next eval (the first rule that fires)."""
    runs = done_runs()
    try:
        es = _sibling("evalset")
        all_versions = es.all_versions()
    except Exception as e:   # a damaged set never stops the overview
        print(f"roof eval: your eval sets were skipped: {e}", file=sys.stderr)
        es, all_versions = None, []
    sets = {(s["name"], s["version"]): s for s in all_versions}
    newest = {}
    for s in all_versions:
        if s["version"] >= newest.get(s["name"], {}).get("version", 0):
            newest[s["name"]] = s
    groups: dict = {}
    for r in runs:
        if str(r.get("task") or "").startswith("judge_"):
            continue
        groups.setdefault(eval_key(r), []).append(r)
    cards = []
    for name, s in sorted(newest.items(), key=lambda kv: kv[1].get("built") or "", reverse=True):
        key = ("set", name, s["version"])
        cards.append({"key": f"{name}@v{s['version']}", "set": name, "version": s["version"], "kind": s.get("kind"),
                      "title": eval_title(key, sets), "cases": s.get("count"),
                      "checked_by": "judged" if s.get("kind") == "triage" else "code",
                      "task_file": s.get("task_file"),
                      "floor": {"right": s.get("baseline_frequent_files"), "of": s.get("count")},
                      "rows": leaderboard_rows(groups.get(key, []))})
    for key, rs in sorted(groups.items(), key=lambda kv: kv[1][0].get("started") or "", reverse=True):
        if key[0] == "task" and len(rs) >= 2 and not str(key[1]).startswith(("lm-eval:",)):
            cards.append({"key": key[1], "task": key[1], "title": key[1], "cases": None, "checked_by": None, "floor": None,
                          "rows": leaderboard_rows(rs)})
    changes = []
    for key, rs in groups.items():
        by_c: dict = {}
        for r in rs:
            by_c.setdefault((r.get("contestant") or {}).get("id"), []).append(r)
        for cid, xs in by_c.items():
            if len(xs) < 2:
                continue
            a, b = xs[0], xs[1]   # newest, the one before
            if since and (a.get("started") or "") < since:
                continue
            cmp = paired_compare(sample_means(a["id"]), sample_means(b["id"]))
            if not cmp:
                continue
            pts = round(cmp["diff"] * 100)
            word = "inside the noise" if cmp["verdict"] == "noise" else "a real change"
            name = (a.get("contestant") or {}).get("name") or a.get("model")
            text = f"{name} {pts:+d} on {eval_title(key, sets)}, {word}."
            if cmp["verdict"] != "noise" and cmp["diff"] < 0:
                text = f"{name} {pts:+d} on {eval_title(key, sets)}: a real change. Re-run to confirm."
            changes.append(dict(cmp, text=text, eval=eval_title(key, sets), contestant=name, delta=cmp["diff"],
                                runs=[a["id"], b["id"]], date=a.get("started")))
    changes.sort(key=lambda c: c.get("date") or "", reverse=True)
    status_rows = []
    for f in sorted(RUNS.glob("*/run.json")) if RUNS.exists() else []:
        r = read_json(f, {})
        if r.get("status") in ("running", "queued", "waiting") and pid_alive(r.get("pid")):
            status_rows.append({"id": r.get("id"), "task": r.get("task"), "model": r.get("model"), "status": r.get("status"),
                                "progress": progress(f.parent), "contestant": contestant(r.get("model"), r.get("agent"))["name"]})
    return {"evals": cards, "changes": changes[:5], "running": status_rows,
            "suggestion": suggestion(runs, newest, es), "finished_runs": len(runs)}


def judges_summary() -> list[dict]:
    try:
        j = _sibling("judge")
        return [j.summary(d) for d in sorted(j.JUDGES.glob("*")) if (d / "judge.json").exists()] if j.JUDGES.is_dir() else []
    except (Exception, SystemExit) as e:
        print(f"roof eval: judges were skipped: {e}", file=sys.stderr)
        return []


def suggestion(runs: list[dict], newest: dict, es) -> dict | None:
    """One suggested next eval: the first of five rules that fires (LAB-2062)."""
    for j in judges_summary():
        try:   # your labels the judge never saw as examples (judge.py trust); 10 are needed before it is trusted
            held = _sibling("judge").trust(j["name"]).get("held_back_yours") or 0
        except (Exception, SystemExit):
            held = j.get("labelled") or 0
        if held < 10:
            return {"rule": "judge_untrusted", "text": f"Judge not trusted yet: label {10 - held} answers",
                    "target": {"tab": "your-evals", "judge": j["name"]}}
    for name, s in newest.items():
        mine = [r for r in runs if r.get("set_name") == name and r.get("set_version") == s["version"]]
        if not mine:
            continue
        best = max(mine, key=lambda r: (primary(r) or {}).get("value") or 0)
        p = primary(best) or {}
        if (best.get("epochs") or 1) == 1 and p.get("ci95"):
            pts = round((p["ci95"][1] - p["ci95"][0]) * 50)
            title = eval_title(("set", name, s["version"]), {(name, s["version"]): s})
            return {"rule": "one_attempt", "text": f"Add attempts: {title} has 1 attempt per case, ±{pts} points",
                    "target": {"tab": "run", "task": s.get("task_file"), "epochs": 3, "limit": s.get("count")}}
    if es is not None:
        for name, s in newest.items():
            try:
                n = es.new_fix_count(s)
            except Exception:
                n = None
            if n:
                return {"rule": "new_fixes", "text": f"{n} bugs fixed since v{s['version']}: build v{s['version'] + 1}",
                        "target": {"tab": "your-evals", "set": name}}
    if not newest:
        return {"rule": "no_set", "text": "Build your first eval from a repo's fixed bugs", "target": {"tab": "your-evals"}}
    if not runs:
        return {"rule": "nothing_ran", "text": "Your first eval, free", "target": {"tab": "learn"}}
    return None


def cmd_overview(argv):
    _, o = args_of(argv, {"--since": "", "--json": False})
    index()
    ov = overview(o["since"] or None)
    lines = []
    for c in ov["evals"]:
        lines.append(f"{c['title']}" + (f" · floor {c['floor']['right']}/{c['floor']['of']}" if c.get("floor") and c["floor"].get("of") else ""))
        for r in c["rows"][:6]:
            sc = "–" if r["score"] is None else f"{r['score'] * 100:.0f} %"
            lines.append(f"  {r['kind']:<8} {r['contestant']:<40} {sc:>6}  n={r['n']}  {r['run']}")
    lines += ["changed: " + c["text"] for c in ov["changes"]]
    lines += [f"running: {r['task']} × {r['contestant']} {r['progress']}" for r in ov["running"]]
    if ov["suggestion"]:
        lines.append("next: " + ov["suggestion"]["text"])
    out(ov, o["json"], "\n".join(lines) or "no runs yet")


# Anatomy (HP EV-3): what a benchmark is made of, read from its own files, overridden by a reviewed anatomy.json for the
# Start-here shelf. Unknown facts are left out, never guessed.
CODE_SCORERS = ("match(", "choice(", "includes(", "exact(", "f1(", "pattern(", "answer(", "verify(")


def evals_source() -> Path | None:
    hits = sorted(VENV.glob("lib/python*/site-packages/inspect_evals"))
    return hits[-1] if hits else None


def derived_facts(folder: str, sandbox: bool) -> dict:
    """Graded by and the prompt template, read from the benchmark's own code (nothing when it can't be read)."""
    src = evals_source()
    d = src / folder if src else None
    facts = {}
    if not d or not d.is_dir():
        return {"graded_by": "tests"} if sandbox else {}
    text = ""
    for f in sorted(d.glob("*.py")):
        try:
            text += f.read_text(errors="ignore") + "\n"
        except OSError:
            pass
    if sandbox:
        facts["graded_by"] = "tests"
    elif "model_graded" in text or any((d / n).exists() and "get_model(" in (d / n).read_text(errors="ignore")
                                       for n in ("scorer.py", "scorers.py")):
        facts["graded_by"] = "judge"
    elif any(c in text for c in CODE_SCORERS):
        facts["graded_by"] = "code"
    m = re.search(r'^[A-Z_]*PROMPT[A-Z_]*TEMPLATE\s*=\s*(?:r?"""|\(?\s*r?""")(.*?)"""', text, re.S | re.M)
    if m and "{" in m.group(1):
        facts["prompt_template"] = m.group(1).strip()
    fs = re.search(r"def \w+\([^)]*fewshot: int = (\d+)", text)
    if fs:
        facts["few_shot"] = int(fs.group(1))
    return facts


GRADED_LABEL = {"code": "Code / exact match", "judge": "Model judge", "tests": "Runs tests"}
GRADED_SHORT = {"code": "checked by code", "judge": "judged", "tests": "runs tests"}


def anatomy_table() -> dict:
    return (read_json(HERE / "anatomy.json", {}) or {}).get("benchmarks", {})


def catalog_extras(b: dict, curated: dict | None = None) -> dict:
    """The catalog row's extra facts: what it is made of, how it is graded, which shelf (HP EV-3)."""
    a = (curated if curated is not None else anatomy_table()).get(b["folder"], {})
    graded = a.get("graded_by") or derived_facts(b["folder"], b.get("sandbox", False)).get("graded_by")
    if b.get("category") == "Your evals":
        graded = graded or ("judge" if "triage" in (b.get("tags") or []) else "code")
    parts = [x for x in (a.get("made_of"), a.get("answer_short"), GRADED_SHORT.get(graded)) if x]
    shelf = ("own" if b.get("category") == "Your evals" else "start" if b.get("starter") else
             "agent" if b.get("sandbox") or "Agent" in (b.get("tags") or []) else None)
    return {"made_of": " · ".join(parts) or None, "graded_by": graded, "shelf": shelf}


def anatomy(folder: str) -> dict:
    cat = build_catalog()
    b = next((x for x in cat["benchmarks"] if x["folder"] == folder or any(t["name"] == folder for t in x["tasks"])), None)
    if b is None:
        die(f"no benchmark {folder}", 3, True)
    a = dict(anatomy_table().get(b["folder"], {}))
    d = derived_facts(b["folder"], b.get("sandbox", False))
    graded = a.get("graded_by") or d.get("graded_by")
    task = next((s["task"] for s in sorted(b.get("starter") or [], key=lambda s: s["rank"])), b["tasks"][0]["name"] if b["tasks"] else folder)
    n = next((t.get("samples") for t in b["tasks"] if t["name"] == task), None)
    res = {"benchmark": b["folder"], "task": task, "title": b.get("title") or b["folder"], "summary": b.get("description"),
           "category": b.get("category"), "maker": a.get("maker"), "year": a.get("year"), "questions": n,
           "questions_note": a.get("questions_note"), "answer_format": a.get("answer_format"),
           "graded_by": graded, "graded_by_label": GRADED_LABEL.get(graded), "judge": a.get("judge"),
           "chance": a.get("chance"), "made_of": catalog_extras(b).get("made_of"),
           "prompt_template": a.get("prompt_template") or d.get("prompt_template"),
           "few_shot": a.get("few_shot", d.get("few_shot")), "watch_out": a.get("watch_out") or [],
           "teaches": next((s["teaches"] for s in b.get("starter") or []), None), "paper": b.get("arxiv"),
           "dataset": a.get("dataset"), "gated": bool(a.get("gated")), "terms_url": a.get("terms_url"),
           "marking": a.get("marking"), "lesson": a.get("lesson"), "split": a.get("split"),
           "metrics": a.get("metrics"), "needs": needs_of(b, a)}
    steps = a.get("steps")
    if not steps:
        third = {"judge": ("Judge compares", "A grader model reads the answer and the reference and says right or wrong."
                           + (f" Judge: {a['judge']}." if a.get("judge") else "")),
                 "code": ("Code checks", "Code compares the answer with the reference. No model is involved."),
                 "tests": ("Tests run", "The answer's code runs against the benchmark's tests in a sandbox.")}.get(graded)
        fmt = None
        if res["prompt_template"]:
            fm = re.search(r'"([^"\n]*\$ANSWER[^"\n]*)"', res["prompt_template"])
            fmt = fm.group(1) if fm else None
        steps = [{"title": "Prompt", "body": "The question is put into the benchmark's template"
                  + (f", with {res['few_shot']} worked examples first." if res.get("few_shot") else ".")},
                 {"title": "Model answers", "body": ("Its last line must read " + fmt) if fmt else "The model writes its answer."}]
        if third:
            steps.append({"title": third[0], "body": third[1]})
        steps.append({"title": "The number", "body": "Right answers over all questions, with the 95 % range."})
    res["steps"] = steps
    try:
        res["headroom"] = _sibling("published_scores").headroom(b["folder"])
    except Exception:
        res["headroom"] = None
    return {k: v for k, v in res.items() if v not in (None, [], "")} | {"steps": steps}


def needs_of(b: dict, a: dict) -> list[str]:
    n = []
    if a.get("gated"):
        n.append("Hugging Face sign-in, terms accepted")
    if b.get("sandbox"):
        n.append("Docker (it runs code)")
    if b.get("internet"):
        n.append("internet during the run")
    if b.get("extra"):
        n.append(f"an extra package ({b['extra']})")
    if not b.get("sandbox"):
        n.append("no Docker")
    return n


def cmd_anatomy(argv):
    pos, o = args_of(argv, {"--json": False})
    if len(pos) != 1:
        die("anatomy <benchmark folder or task> [--json]", 2, o["json"])
    need_engine(o["json"])
    a = anatomy(pos[0])
    lines = [f"{a['title']} · {a.get('maker', '?')} · {a.get('year', '?')}", a.get("summary", ""),
             f"questions {a.get('questions')} · answer {a.get('answer_format', '?')} · graded by {a.get('graded_by_label', '?')} "
             f"· chance {a.get('chance', '?')}"] + [f"  {i + 1}. {s['title']}: {s['body']}" for i, s in enumerate(a["steps"])]
    out(a, o["json"], "\n".join(lines))


# Questions (HP EV-4/EV-5, LAB-2064): a benchmark's real questions on this Mac, browsed without running it.
QUESTIONS = EVALS / "questions"
GATED_ERR = re.compile(r"gated (dataset|repo)|GatedRepoError|must be authenticated|401 Client Error|403 Client Error", re.I)

_ITEMS_CODE = r"""
import json, sys, inspect_evals._registry as r
t = getattr(r, sys.argv[1])()
out = open(sys.argv[2], "w")
def text(x):
    if isinstance(x, str): return x, False
    parts, img = [], False
    for m in x:
        c = getattr(m, "content", m)
        if isinstance(c, str): parts.append(c); continue
        for p in c if isinstance(c, list) else [c]:
            if type(p).__name__ == "ContentImage": img = True
            elif getattr(p, "text", None): parts.append(p.text)
    return "\n".join(parts), img
for i, s in enumerate(t.dataset):
    q, img = text(s.input)
    tgt = s.target if isinstance(s.target, str) else ", ".join(s.target)
    md = s.metadata or {}
    sol = next((md[k] for k in ("reasoning", "solution", "rationale", "explanation") if isinstance(md.get(k), str) and md.get(k)), None)
    out.write(json.dumps({"id": str(s.id) if s.id is not None else str(i + 1), "index": i + 1, "input": q, "target": tgt,
                          "solution": sol, "choices": s.choices, "image": img}) + "\n")
out.close()
print(json.dumps({"ok": True}))
"""


def questions_file(task: str) -> Path:
    v = (build_catalog().get("inspect_evals") or "x") if not task.endswith(".py") else "set"
    return QUESTIONS / task_name(task) / f"{v}.jsonl"


def own_items(task: str) -> list[dict] | None:
    """Your own set's questions come from its cases file: nothing to download."""
    if not task.endswith(".py"):
        return None
    p = Path(os.path.expanduser(task)).resolve().parent / "cases.jsonl"
    rows = [json.loads(x) for x in p.read_text().splitlines()] if p.exists() else []
    out = []
    for i, r in enumerate(rows):
        q = r["input"].split("\n\nSource files:\n", 1)[0]
        out.append({"id": r["id"], "index": i + 1, "input": q, "target": "\n".join(r["target"]) if isinstance(r["target"], list) else r["target"],
                    "solution": None, "choices": None, "image": False})
    return out


def dataset_size(dataset: str | None) -> int | None:
    """Bytes of the dataset's files, from Hugging Face's public size endpoint (no key, nothing sent but the name)."""
    if not dataset:
        return None
    try:
        with urllib.request.urlopen(f"https://datasets-server.huggingface.co/size?dataset={dataset}", timeout=15) as r:
            d = json.load(r)
        return int(((d.get("size") or {}).get("dataset") or {}).get("num_bytes_original_files") or 0) or None
    except Exception:
        return None


def runs_of_task(task: str) -> list[dict]:
    """Every run of this task (any status) with its contestant, oldest first: the order of a question's dots."""
    tn = task_name(task)
    return sorted([r for r in results_for() if r.get("task") == tn], key=lambda r: r.get("started") or "")


def scores_by_item(runs: list[dict]) -> dict:
    """sample id → [(run id, mean score)] for the runs given."""
    if not DB.exists() or not runs:
        return {}
    out: dict = {}
    with sqlite3.connect(DB) as db:
        for r in runs:
            try:
                rows = db.execute("SELECT sample_id, AVG(score) FROM sample_scores WHERE run_id=? GROUP BY sample_id", (r["id"],))
            except sqlite3.OperationalError:
                return {}
            for sid, v in rows:
                out.setdefault(sid, []).append([r["id"], v])
    return out


def load_items(task: str, download: bool) -> tuple:
    """(items, None) or (None, state) where state says what is needed first: a download, or the dataset's terms."""
    own = own_items(task)
    if own is not None:
        return own, None
    qf = questions_file(task)
    if qf.exists():
        return [json.loads(x) for x in qf.read_text().splitlines() if x.strip()], None
    entry = catalog_entry(task) or {"folder": task_name(task)}
    a = anatomy_table().get(entry["folder"], {})
    gated = {"gated": True, "dataset": a.get("dataset"), "terms_url": a.get("terms_url") or
             (f"https://huggingface.co/datasets/{a['dataset']}" if a.get("dataset") else None)}
    if not download:
        ran = any(r.get("task") == task_name(task) for r in results_for())
        return None, {"needs_download": True, "dataset": a.get("dataset"), "gated": bool(a.get("gated")),
                      "terms_url": gated["terms_url"], "already_on_mac": ran,
                      "size_bytes": None if ran else dataset_size(a.get("dataset"))}
    need_engine(True)
    qf.parent.mkdir(parents=True, exist_ok=True)
    tmp = qf.with_suffix(".tmp")
    r = subprocess.run([str(VPY), "-c", _ITEMS_CODE, task_name(task), str(tmp)], capture_output=True, text=True,
                       env=run_env("mockllm/model"))
    if r.returncode != 0:
        tmp.unlink(missing_ok=True)
        if GATED_ERR.search(r.stderr):
            return None, gated
        die(f"could not load the questions: {redact(r.stderr.strip().splitlines()[-1] if r.stderr.strip() else 'no output')[:400]}", 8, True)
    tmp.replace(qf)
    return [json.loads(x) for x in qf.read_text().splitlines() if x.strip()], None


def filter_items(items: list[dict], dots: dict, how: str, seed: int) -> list[dict]:
    if how == "seen":
        return [x for x in items if dots.get(x["id"])]
    if how == "wrong":
        return [x for x in items if any(v is not None and v < 1 for _, v in dots.get(x["id"], []))]
    if how == "random":
        rnd = random.Random(seed)
        return sorted(rnd.sample(items, min(10, len(items))), key=lambda x: x["index"])
    return items


def cmd_items(argv):
    pos, o = args_of(argv, {"--limit": "50", "--offset": "0", "--filter": "all", "--seed": "17", "--download": False,
                            "--json": False})
    if len(pos) != 1:
        die("items <task> [--limit 50] [--offset 0] [--filter all|seen|wrong|random] [--seed N] [--download]", 2, o["json"])
    if o["filter"] not in ("all", "seen", "wrong", "random"):
        die("--filter is one of all, seen, wrong, random", 2, o["json"])
    task = pos[0]
    items, state = load_items(task, o["download"])
    if items is None:
        out(dict(state, task=task_name(task)), o["json"], json.dumps(state))
        return
    index()
    runs = runs_of_task(task)
    dots = scores_by_item(runs)
    chosen = filter_items(items, dots, o["filter"], int(o["seed"]))
    off, lim = int(o["offset"]), int(o["limit"])
    page = []
    for x in chosen[off:off + lim]:
        page.append(dict(x, input=x["input"][:400], dots=[{"run": rid, "score": v} for rid, v in dots.get(x["id"], [])]))
    res = {"task": task_name(task), "total": len(items), "shown": len(chosen), "offset": off, "seed": int(o["seed"]),
           "filter": o["filter"], "runs": [{"id": r["id"], "contestant": r["contestant"]["name"]} for r in runs],
           "counts": {"all": len(items), "seen": len(filter_items(items, dots, "seen", 0)),
                      "wrong": len(filter_items(items, dots, "wrong", 0))}, "items": page}
    out(res, o["json"], "\n".join(f"#{x['index']:<5} {x['input'][:90]!r} → {x['target'][:30]}" for x in page) or "no questions")


_ITEM_RUNS_CODE = r"""
import json, sys
from inspect_ai.log import read_eval_log_sample
want = sys.argv[1]
res = []
for spec in sys.argv[2:]:
    rid, log = spec.split("=", 1)
    for ep in range(1, 50):
        try:
            s = read_eval_log_sample(log, want, ep)
        except Exception:
            break
        sc = next(iter((s.scores or {}).values()), None)
        msgs = [{"role": m.role, "text": (m.text or "")[:8000]} for m in s.messages if m.role in ("system", "user")]
        res.append({"run": rid, "epoch": ep, "answer": (sc.answer if sc and sc.answer else None),
                    "output": (s.output.completion if s.output else "")[-600:], "value": str(sc.value) if sc else None,
                    "explanation": (sc.explanation or "")[:600] if sc else None, "prompt": msgs})
print(json.dumps(res))
"""


def item_runs(task: str, sid: str) -> tuple[list[dict], dict | None]:
    """Each run's answer to one question (from its log) and the exact prompt the first such run sent."""
    runs = [r for r in runs_of_task(task) if r.get("log_path")]
    dots = scores_by_item(runs)
    saw = {rid for rid, _ in dots.get(sid, [])}
    specs = [f"{r['id']}={r['log_path']}" for r in runs if r["id"] in saw and str(r["log_path"]).endswith(".eval")]
    if not specs or not engine_ready():
        return [], None
    r = subprocess.run([str(VPY), "-c", _ITEM_RUNS_CODE, sid, *specs], capture_output=True, text=True)
    rows = json.loads(r.stdout) if r.returncode == 0 and r.stdout.strip() else []
    by_id = {x["id"]: x for x in runs}
    prompt = None
    out_rows = []
    for x in rows:
        run = by_id.get(x["run"], {})
        if prompt is None and x["prompt"]:
            prompt = {"messages": x["prompt"], "source": f"as sent in run {x['run']}"}
        tail = (x["output"] or "").strip().splitlines()
        out_rows.append({"run": x["run"], "epoch": x["epoch"], "contestant": (run.get("contestant") or {}).get("name"),
                         "kind": (run.get("contestant") or {}).get("kind"), "model": run.get("model"),
                         "score": next((v for rid, v in dots.get(sid, []) if rid == x["run"]), None),
                         "answer": x["answer"], "answer_tail": (tail[-1] if tail else "")[-200:],
                         "explanation": x["explanation"]})
    return out_rows, prompt


def cmd_item(argv):
    pos, o = args_of(argv, {"--json": False})
    if len(pos) != 2:
        die("item <task> <question id> [--json]", 2, o["json"])
    task, sid = pos
    items, state = load_items(task, False)
    if items is None:
        out(dict(state, task=task_name(task)), o["json"], json.dumps(state))
        return
    x = next((i for i in items if i["id"] == sid or str(i["index"]) == sid), None)
    if x is None:
        die(f"no question {sid} in {task_name(task)}", 3, o["json"])
    index()
    rows, prompt = item_runs(task, x["id"])
    entry = catalog_entry(task) or {"folder": task_name(task)}
    a = anatomy_table().get(entry["folder"], {})
    tpl = a.get("prompt_template") or derived_facts(entry["folder"], bool(entry.get("sandbox"))).get("prompt_template")
    if prompt is None and tpl:
        prompt = {"template": tpl, "source": "the benchmark's template (no run has seen this question yet)"}
    if prompt is not None and a.get("few_shot") is not None:
        prompt["few_shot"] = a["few_shot"]
    marking = [{"scorer": a.get("graded_by") or "?", "text": a["marking"].replace("{target}", x["target"])}] if a.get("marking") else []
    res = dict(x, task=task_name(task), dataset=a.get("dataset"), split=a.get("split"), prompt=prompt, marking=marking,
               lesson=a.get("lesson"), runs=rows, no_reference=(a.get("graded_by") == "judge" and not x.get("target")))
    out(res, o["json"], f"#{x['index']} {x['input']}\n→ {x['target']}\n" + "\n".join(
        f"  {'✓' if (r['score'] or 0) >= 1 else '✕'} {r['contestant']}: {r['answer_tail']}" for r in rows))


def cmd_item_results(argv):
    pos, o = args_of(argv, {"--json": False})
    if len(pos) != 2:
        die("item-results <task> <question id> [--json]", 2, o["json"])
    index()
    rows, _ = item_runs(pos[0], pos[1])
    out(rows, o["json"], "\n".join(f"{r['run']} {r['contestant']} {r['score']} {r['answer_tail']}" for r in rows) or "no run saw it")


def cmd_scores(argv):
    """Published best-model scores, one official source per benchmark (LAB-2063): published_scores.py beside this file."""
    os.execv(sys.executable, [sys.executable, str(HERE / "published_scores.py"), *argv])


# ── main ───────────────────────────────────────────────────────────────────────────────────────────────────────────
COMMANDS = {"setup": cmd_setup, "doctor": cmd_doctor, "catalog": cmd_catalog, "providers": cmd_providers,
            "prices": cmd_prices, "estimate": cmd_estimate, "run": cmd_run, "status": cmd_status, "cancel": cmd_cancel,
            "resume": cmd_resume, "run-anyway": cmd_run_anyway, "results": cmd_results, "index": cmd_index, "_worker": cmd_worker,
            "samples": cmd_samples, "sample": cmd_sample, "export": cmd_export, "xray": cmd_xray,
            "evalset": cmd_evalset, "judge": cmd_judge, "lmeval": cmd_lmeval, "overview": cmd_overview,
            "anatomy": cmd_anatomy, "items": cmd_items, "item": cmd_item, "item-results": cmd_item_results,
            "scores": cmd_scores, "power": cmd_power, "compare": cmd_compare, "leaderboard": cmd_leaderboard,
            "history": cmd_history}


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
