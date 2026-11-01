#!/usr/bin/env python3
"""A second framework behind the same runs and results (LAB-1997): EleutherAI's lm-evaluation-harness.

  lmeval setup                                  install lm-eval (pinned) into its own folder, apart from Inspect
  lmeval run <task> --model openai-api/<service>/<name> --base-url URL [--limit 50] [--json]
                                                 e.g. arc_challenge_chat_letter on a local llama-server
  lmeval tasks [--grep TEXT]                    lm-eval's task names

Why two frameworks: the same benchmark is not one number. Frameworks differ in prompt wording, examples shown,
whether the model writes an answer or its option probabilities are compared, and how the answer is read back. Run the
same benchmark on the same model in both and the Results grid shows the gap (the 'Two frameworks' explainer).

Scope: models behind an OpenAI-compatible chat endpoint (a local llama-server or Ollama, free). lm-eval's default
multiple-choice scoring compares the log-probabilities of each option and needs the server to return them for the
prompt (vLLM does; llama-server and chat APIs do not), so here both frameworks make the model write its answer.

Each run is a normal run folder: run.json with framework 'lm-eval' and a summary parsed from lm-eval's own results
file (kept beside it), so the index, Results, compare and export treat it like any other run. Standard library only.
"""
from __future__ import annotations

import json
import os
import random
import string
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path

HERE = Path(__file__).resolve().parent
EVALS = Path(os.environ.get("ONEROOF_EVALS_DIR") or Path.home() / "Library/Application Support/One Roof/evals")
VENV = EVALS / "lmeval-venv"
LM_EVAL = VENV / "bin/lm_eval"
RUNS = EVALS / "runs"
PIN = "lm-eval[api]==0.4.13"   # MIT; checked 2026-10-31 (pypi.org/project/lm-eval)
TASKS = HERE / "lmeval_tasks"


def now() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def die(msg: str, code: int = 1, as_json: bool = False):
    if as_json:
        print(json.dumps({"error": msg}))
    else:
        print(f"roof eval lmeval: {msg}", file=sys.stderr)
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


def cmd_setup(argv):
    _, o = args_of(argv, {"--json": False})
    uv = next((p for p in ("/opt/homebrew/bin/uv", "/usr/local/bin/uv") if Path(p).exists()), None) or "uv"
    if not (VENV / "bin/python").exists():
        subprocess.run([uv, "venv", "--quiet", "--python", "3.12", str(VENV)], check=True)
    subprocess.run([uv, "pip", "install", "--quiet", PIN], check=True, env=dict(os.environ, VIRTUAL_ENV=str(VENV)))
    v = subprocess.run([str(VENV / "bin/python"), "-c", "import lm_eval; print(lm_eval.__version__)"],
                       capture_output=True, text=True).stdout.strip()
    print(json.dumps({"lm_eval": v, "folder": str(VENV)}) if o["json"] else f"lm-eval {v} ready in {VENV}")


def summary_of(results: dict, task: str) -> dict:
    """lm-eval's results file → the index's run summary. Each metric,filter pair becomes one score; exact_match and
    acc are proportions, named accuracy so the range is the same Wilson range Inspect's accuracy gets."""
    r = results["results"][task]
    n = (results.get("n-samples") or {}).get(task, {})
    scores = []
    for k, v in r.items():
        if "," not in k or "_stderr" in k or not isinstance(v, (int, float)):
            continue
        metric, flt = k.split(",", 1)
        se = r.get(f"{metric}_stderr,{flt}")
        name = "accuracy" if metric in ("exact_match", "acc", "acc_norm") else metric
        scores.append({"scorer": f"{metric} ({flt})", "metrics": dict({name: v}, **({"stderr": se} if isinstance(se, (int, float)) else {}))})
    return {"status": "success", "samples_total": n.get("effective") or r.get("sample_len"),
            "samples_done": n.get("effective") or r.get("sample_len"), "dataset_size": n.get("original"),
            "scores": scores, "lm_eval": results.get("lm_eval_version"),
            "seconds": float(results.get("total_evaluation_time_seconds") or 0) or None}


def cmd_run(argv):
    pos, o = args_of(argv, {"--model": "", "--base-url": "", "--limit": "50", "--json": False})
    if len(pos) != 1 or not o["model"].startswith("openai-api/") or not o["base_url"]:
        die("lmeval run <task> --model openai-api/<service>/<name> --base-url URL [--limit N]", 2, o["json"])
    if not LM_EVAL.exists():
        die("lm-eval is not installed: roof eval lmeval setup", 4, o["json"])
    task, name = pos[0], o["model"].split("/", 2)[-1]
    rid = datetime.now().strftime("%Y%m%d-%H%M%S") + f"-lm-eval_{task}-" + "".join(random.choices(string.ascii_lowercase, k=4))
    d = RUNS / rid
    d.mkdir(parents=True)
    r = {"id": rid, "task": f"lm-eval:{task}", "task_ref": task, "model": o["model"], "limit": int(o["limit"]),
         "framework": "lm-eval", "status": "running", "started": now(), "dir": str(d), "where": "local"}
    (d / "run.json").write_text(json.dumps(r, indent=2))
    base = o["base_url"].rstrip("/")
    cmd = [str(LM_EVAL), "--model", "local-chat-completions",
           "--model_args", f"model={name},base_url={base}/chat/completions,num_concurrent=2,max_retries=2,tokenized_requests=False",
           "--tasks", task, "--apply_chat_template", "--limit", o["limit"], "--include_path", str(TASKS),
           "--output_path", str(d / "lmeval"), "--log_samples"]
    with open(d / "console.log", "ab") as log:
        rc = subprocess.run(cmd, stdout=log, stderr=subprocess.STDOUT, cwd=str(d),
                            env=dict(os.environ, OPENAI_API_KEY=os.environ.get("OPENAI_API_KEY", "none"))).returncode
    found = sorted((d / "lmeval").rglob("results_*.json"))
    if rc == 0 and found:
        r.update(status="done", summary=summary_of(json.loads(found[-1].read_text()), task), results_file=str(found[-1]))
    else:
        tail = (d / "console.log").read_text(errors="ignore").strip().splitlines()[-1:] or [f"lm_eval exited {rc}"]
        r.update(status="failed", error=tail[0][:500])
    r["finished"] = now()
    (d / "run.json").write_text(json.dumps(r, indent=2))
    subprocess.run([sys.executable, str(HERE / "roof_eval.py"), "index"], capture_output=True)
    shown = subprocess.run([sys.executable, str(HERE / "roof_eval.py"), "results", rid] + (["--json"] if o["json"] else []),
                           capture_output=True, text=True).stdout
    print(shown.strip() or json.dumps(r))
    sys.exit(0 if r["status"] == "done" else 1)


def cmd_tasks(argv):
    _, o = args_of(argv, {"--grep": ""})
    if not LM_EVAL.exists():
        die("lm-eval is not installed: roof eval lmeval setup", 4)
    out = subprocess.run([str(LM_EVAL), "ls", "tasks", "--include_path", str(TASKS)], capture_output=True, text=True).stdout
    for line in out.splitlines():
        if not o["grep"] or o["grep"] in line:
            print(line)


COMMANDS = {"setup": cmd_setup, "run": cmd_run, "tasks": cmd_tasks}

if __name__ == "__main__":
    if len(sys.argv) < 2 or sys.argv[1] not in COMMANDS:
        print(__doc__)
        sys.exit(0 if len(sys.argv) < 2 else 2)
    COMMANDS[sys.argv[1]](sys.argv[2:])
