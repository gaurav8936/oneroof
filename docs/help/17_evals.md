# One Roof help: Evals

**Status:** LIVE · **Date:** 2026-10-31

> **One line:** Evals runs any model on any public benchmark, at a size and cost you choose, and shows every score with its 95 % range, the answers behind it and a plain explanation of what it means.

## Open it

The Evals place (⌃⌘8 in the One Roof 1 window), or the command palette: **Evals**. The first time, choose **Install**: One Roof installs the eval engine (Inspect AI and its benchmark collection, MIT) into its own folder with `uv`. Nothing is added to the app itself. If `uv` is missing, install it once with `brew install uv`.

## Catalog

Every benchmark the engine knows (129 at inspect-evals 0.27.0), with **Start here** (★) first: 24 benchmarks picked so that each teaches something about evals. Filter by category, search by name or task, or hide the ones that need Docker. A benchmark's card says what it measures, how many questions it has, the score people reach where known, what it needs (Docker, internet, a Hugging Face sign-in), and an estimate of what 50 questions cost on a few models.

## Run

**Run this…** (or **+ New run**) opens the run sheet: pick the tasks and the models, how many questions, how many attempts per question (empty = the benchmark's own default), the temperature, and a spending cap. The sheet shows the cost of each run before you start. A run over its cap cannot start, and while it runs no answer may spend more than its share of the cap, so the total cannot pass it.

Runs start in the background and queue (two at a time). Closing One Roof does not stop them. **Runs** shows progress; **Cancel** stops a run and keeps what it finished; **Resume** finishes a stopped run without redoing finished questions.

The stand-in model (`mockllm/model`) and models on this Mac are free: use them to try a benchmark before paying for a real model.

## Results

- **The grid:** the latest finished run of each model on each task. The number is the main score; the bar under it is its 95 % range. A dashed border means fewer than 30 questions, so the range is wide.
- **Compare two runs:** says whether the difference is real or noise. When both runs answered the same questions, the comparison is question by question (paired), which finds smaller real differences.
- **A run:** every metric with its range, tokens, cost, cost per correct answer and time; then every question: the model's answer, the expected one, and the full conversation and the grader's reasoning when you open it. **Only the ones it got wrong** is the fastest way to learn what a benchmark really tests.
- **Export CSV / JSON:** every run and metric, with the ranges.

## Learn

A free guided first run (5 math questions on the stand-in model, then on a cheap real model), and short explanations of accuracy, the 95 % range, standard error, paired comparison, pass@k, attempts per question, contamination, a model as the grader, the harness, cost per correct answer, and chance level.

## Keys and sign-ins

One Roof never stores a key value. Point it at a key file you keep, once per provider:

```
roof eval providers set anthropic --key-file ~/path/to/anthropic.key
```

Providers: anthropic, openai, google, openrouter, fireworks, together, mistral, grok, groq, deepseek. A key already in your shell environment also works.

Some datasets are gated on Hugging Face (Humanity's Last Exam, LiveCodeBench Pro, GAIA, XSTest): sign in once (`hf auth login`) and press **Agree and access** on each dataset's page. A failed run says which step is missing.

## From the command line

`roof eval` does everything the place does: `setup`, `doctor`, `catalog`, `estimate`, `run`, `status`, `cancel`, `resume`, `results`, `samples`, `sample`, `export`. Add `--json` for scripts and loops. The data lives in `~/Library/Application Support/One Roof/evals`.
