# One Roof help: Evals

**Status:** LIVE · **Date:** 2026-10-31

> **One line:** Evals runs any model on any public benchmark, at a size and cost you choose, and shows every score with its 95 % range, the answers behind it and a plain explanation of what it means.

## Open it

The Evals place (⌃⌘8 in the One Roof 1 window), or the command palette: **Evals**. The first time, choose **Install**: One Roof installs the eval engine (Inspect AI and its benchmark collection, MIT) into its own folder with `uv`. Nothing is added to the app itself. If `uv` is missing, install it once with `brew install uv`.

## Catalog

Every benchmark the engine knows (129 at inspect-evals 0.27.0), with **Start here** (★) first: 24 benchmarks picked so that each teaches something about evals. Filter by category, search by name or task, or hide the ones that need Docker. A benchmark's card says what it measures, how many questions it has, the score people reach where known, what it needs (Docker, internet, a Hugging Face sign-in), and an estimate of what 50 questions (or all of a smaller set) cost on a few models.

## Your evals

Benchmarks measure other people's tasks. **Your evals** measure yours: a set of questions built from a repo's own history, listed first in the catalog.

- Build one from the command line: `roof eval evalset build --repo <your repo>`, adding `--linear-key-file <file>` to use the Linear issue as each bug report (the file must hold only the key).
- The first kind of question is the **fix locator**. It shows a real bug report and the repo's source files as they were just before the fix, and asks which files to change. It is checked by code: correct when one of the first three files named is a file the real fix changed.
- The questions come from fix commits that name an issue and change one to three source files (tests, docs and site pages aside). An issue's first fix commit is the answer. A report that already names the file is left out, and so is an issue that is not fixed.
- **The no-model floor** on the card is what you get with no model at all, by always guessing the three files fixed most often. A score means something only above it.
- Sets are versioned and never edited. A rebuild that finds different questions makes a new version; an unchanged one reuses the last. Old results stay comparable to the version they ran on.

## A model as judge

Some answers code can't check: a triage note, an explanation, a summary. A model can grade them, but only after you know how often it agrees with you.

- **Answers to judge** come from any runs: `roof eval judge new <name> --runs RUN[,RUN2] --rubric "<what PASS means>"`. Add `--pairwise` with two runs to have the judge pick the better of two answers to the same question.
- **You label first.** `roof eval judge label <name>` shows each answer in the terminal: `p` pass, `f` fail (`a`, `b`, `t` for pairs), then one sentence on why. Label 30.
- **No time to label?** `roof eval judge autolabel <name> --code --model <a stronger model>` labels for you, from two other sources, each measured on its own:
  - **code** checks one fact, whether the answer points at a file the real fix changed. The judge should fail what code fails.
  - **a model** (not one that wrote the answers) applies your rubric. Results then say "agrees with <model>'s labels", never "agrees with you". Your own labels, when you add them, take over the headline.
- **Build and run the judge.** `roof eval judge build <name>` turns your first 10 labels into the judge's worked examples and holds the rest back. Run the task file it prints like any benchmark, with the model you want as judge.
- **Agreement shows next to the judged score** in Results:
  - how often the judge agrees with you on the labels it never saw;
  - how often it passes answers you passed (good) and fails answers you failed (bad). A judge that passes everything looks fine on a mostly-good set; these two numbers expose it;
  - "too few labels" with fewer than 10 held back;
  - "grades its own answers" when the judge model also wrote some of them.
- **Pairwise** judges see each pair twice, in both orders. A win counts only when it holds both ways; "same winner both orders" measures the judge's position bias.

`roof eval evalset build --kind triage` makes a set whose answers are prose, the natural first thing to judge.

## Two frameworks, one benchmark

One Roof runs benchmarks with Inspect. It can also run the same benchmark with EleutherAI's lm-evaluation-harness, so you can see how much the framework itself moves a score.

- Install it once (in its own folder): `roof eval lmeval setup`.
- Run a local model behind an OpenAI-compatible server, for example llama-server on port 18731: `roof eval lmeval run arc_challenge_chat_letter --model openai-api/local/<name> --base-url http://127.0.0.1:18731/v1 --limit 100`.
- Run the same questions in Inspect: `LOCAL_BASE_URL=http://127.0.0.1:18731/v1 LOCAL_API_KEY=none roof eval run arc_challenge --model openai-api/local/<name> --limit 100 --seed ''` (no seed means no shuffle, so both frameworks get the first 100 questions).
- Results show both side by side; the lm-eval column is named `lm-eval:<task>`. **Learn › Two frameworks, one benchmark** explains why they differ, with a measured example.

`arc_challenge_chat_letter` is lm-eval's `arc_challenge_chat` with one change: it reads the answer letter out of the sentence. The original expects the server to continue a pre-filled reply, which llama-server does not, so it scores 0.

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

`roof eval` does everything the place does: `setup`, `doctor`, `catalog`, `estimate`, `run`, `status`, `cancel`, `resume`, `results`, `samples`, `sample`, `export`, `evalset`, `judge`, `lmeval`. Add `--json` for scripts and loops. The data lives in `~/Library/Application Support/One Roof/evals`.
