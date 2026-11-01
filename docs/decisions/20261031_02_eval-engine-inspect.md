# Eval engine: Inspect AI, run outside the app, results indexed in evals.db

**Status:** ACCEPTED · **Date:** 2026-10-31 · **Project:** LAB-EVALS · **Owner:** gaurav · **Linear:** LAB-1973

> **One line:** One Roof runs evals with Inspect AI and inspect_evals, installed by `roof eval setup` into One Roof's own data folder (never linked into the app); every run keeps Inspect's full log, and a small SQLite index makes runs comparable.

## Context

The owner wants to learn evals by running them: any model, any public benchmark, results with their uncertainty and the transcripts behind them. The app rule is "no new dependencies" (no linked libraries, no web framework); optional tools such as llama-server run outside the app.

## Decision

1. **Engine:** [Inspect AI](https://inspect.aisi.org.uk/) (MIT) plus `inspect_evals` (129 benchmarks with metadata, 239 tasks at 0.27.0). Pinned per One Roof release in `app/Resources/evals/requirements.txt`, together with the Anthropic, OpenAI and Google client packages.
2. **Runtime:** `uv` creates a Python 3.12 environment in `~/Library/Application Support/One Roof/evals/venv`. `roof eval setup` installs it; `--repair` rebuilds it. The launcher `roof_eval.py` needs only the system `python3` and its standard library.
3. **Runs:** one folder per run (`runs/<id>/`: `run.json`, `console.log`, Inspect's `.eval` log). Background runs use a detached worker that records the outcome. Cancel interrupts Inspect, which writes a partial log; resume uses `inspect eval-retry` and keeps the samples already done.
4. **Outcome comes from the log.** Inspect can exit 0 while every call failed (a rejected key gives log status `error`). A run is `done` only when the log says `success`.
5. **Index:** `evals.db` (runs + scores) is rebuilt from the logs at any time (`roof eval index`), so the logs stay the truth.
6. **Uncertainty:** proportions get a 95 % Wilson interval (honest at 0 %, 100 % and small n); other metrics get value ± 1.96 × stderr.
7. **Cost:** prices come from OpenRouter's public model list (USD per million tokens, dated, refreshed weekly). An estimate is shown before every run, and a run is refused when the estimate is over the cap (default $2). The cap is also enforced *during* the run: each sample may spend at most cap ÷ samples (Inspect `--cost-limit`), so the total cannot pass it. A model without a known price only runs with `--allow-unknown-cost`. The stand-in model (`mockllm`) and local models are free.
8. **Keys:** `providers.json` (mode 600) stores the *path* of a key file the owner chose, never a key value. The key goes only into the run's process environment. Errors are redacted before they are stored or shown. Known limit: Inspect's own `.eval` log keeps the provider's error text, which for OpenAI includes the provider's own masked key fragment.
9. **Sandboxed benchmarks** (they execute code or let an agent act: SWE-bench, Terminal-Bench, CTFs, some coding sets) need Docker locally, or a hosted option. That choice is LAB-2000 (hosted SWE-bench grading via sb-cli, Modal, Daytona/E2B/Runloop via Harbor, Kubernetes via inspect-k8s-sandbox).

## Consequences

- Most benchmarks (question-and-answer) download only a small dataset and call the model's API: no Docker, nothing installed per benchmark.
- The Evals place in the app (M2–M5) reads `catalog.json`, `evals.db` and the `.eval` logs, and calls `roof eval … --json`; it never imports Python.
- A second framework (lm-evaluation-harness, M8) plugs in behind the same run folder and index (`framework` column).

## Verified (2026-10-31)

`tests/test_eval_engine.py`: 9 offline unit tests, and with `ROOF_EVAL_INTEGRATION=1` a real install plus foreground and background runs of a four-question task on the stand-in model. Manually: GSM8K and MMLU-Pro on the stand-in model, a 3,000-sample background run cancelled and resumed, the over-cap refusal, the missing-key refusal, and a rejected key reported as `failed` with the key redacted.
