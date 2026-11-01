# One Roof help: Evals

**Status:** DRAFT · **Date:** 2026-11-01

> **One line:** Evals measures your agents and models on your own work and on public benchmarks, at a size and cost you choose, and shows every score with its 95 % range, the questions behind it and a plain explanation of what it means.

> **Draft · coming soon.** Evals is being redesigned. What you see may change, and results are for trying out only. The Evals place shows a Draft tag and this banner on every tab until the redesign ships.

## Open it

The Evals place (⌃⌘8 in the One Roof 1 window), or the command palette: **Evals**. The first time, choose **Install**: One Roof installs the eval engine (Inspect AI and its benchmark collection, MIT) into its own folder with `uv`. Nothing is added to the app itself. If `uv` is missing, install it once with `brew install uv`.

Six tabs, in this order: **Overview · Your evals · Explore · Run · Results · Learn** (⌃⌥1 to ⌃⌥6 while Evals shows). Evals opens on Overview. **+ New run** (top right, on every tab but Run) opens Run. A drill-down (a benchmark's questions, a judge, one run) has a breadcrumb and **‹ Back**; ⌘[ goes back too. The Draft banner shows on every tab and drill-down.

**Every number explains itself.** Hover a score, a 95 % range, n, the ± points in Run, pass@k, cost, dollars per right answer, the floor, chance, headroom, a judge's agreement or a compare verdict for a moment: a card says what the number is and what this one means ("75 % on 20 cases: the true score is probably between 53 % and 89 %"), with **Lesson ›** to its lesson in Learn. Right-click (or Control-click) the number for the same card and the lesson; VoiceOver reads it as the number's hint, with an "Open the lesson" action. The subtitle counts what you have: benchmarks, your evals, judges, finished runs, and runs going now.

**The redesigned Evals is new in 2.0.0** and on by default. To see the 1.9.37 Evals (Catalog · Runs · Results · Learn), turn off **Settings › General › Redesigned Evals**.

## Overview

"How your agents are doing on your work", without a click:

- **A scorecard per eval of yours** (the newest version of each set), then each benchmark you ran twice or more. Rows are contestants, **agents first** (Claude Code, Codex, …), then models, then models on this Mac, then the **baseline** (the free stand-in). Each row: the score, a bar with its 95 % range and the **no-model floor** as a dashed line, the cost ("seat" for agents, "free" for free models), dollars per right answer, and the run's date, which opens the run. ↑ ↓ and Return work once the card has focus.
- **What changed since last time:** for each contestant with two runs on the same eval, the change between the last two, in words: "inside the noise" when the paired 95 % range includes zero, "a real change" when it does not (a drop asks you to re-run to confirm).
- **Running now**, with Cancel.
- **One suggested next eval**, the first that applies: a judge not trusted yet (label answers) · a set whose best run had one attempt (add attempts) · fixes since your set's newest version (build the next one) · no set yet (build your first) · nothing run yet (your first eval, free).

A new profile shows the free first-eval invitation and no numbers.

## Explore

Every benchmark the engine knows (129 at inspect-evals 0.27.0). On the left: **Shelves** (Start here: 24 picked so each teaches something about evals; Your evals; Agent tasks; Judges), **What it tests** (Knowledge, Hard frontier, Factuality, Math, Reasoning, Code, Tool use, Long context, Safety, Instruction following, and More topics for the rest), **Graded by** (code, a model judge, or running tests), **No Docker needed** and **I've run it**. ⌘F searches. Each row's second line says what the benchmark is made of: the question type, the answer and how it is graded. **Rescan benchmarks** is at the foot of the list.

A benchmark's page: who made it and when, a summary, **Run this…**, and four tabs.

- **Anatomy:** questions, answer, graded by, chance, headroom (how far the best published score is from the top), **how one question is scored** in four steps (the template's real answer format), **on this Mac so far** with a red note when a run had under 30 questions, what it teaches and what to watch out for, what it needs, the cost of 50 questions on three models, and the paper. A fact that isn't known is left out.
- **Questions:** the real questions (below).
- **Scores:** the best published scores, from **one official source** per benchmark (its own leaderboard, else its makers' or a model maker's published results), each with its source link and the date it was checked, beside this Mac's latest run of the same model where there is one. Values are read from the source, never typed in; a benchmark with no source says "No published score yet". The check runs weekly (the `published-scores` loop, or on its own when the scores are over a week old and you open Scores); **Check now** runs it at once. A failed check keeps the last good values and says when and why. Rows older than 30 days are greyed "may be out of date".
- **Your runs:** every run of it here; a row opens the run.

### Questions

A benchmark's own questions, without running anything. The first time, One Roof asks before it downloads the dataset, with its size; the questions stay on this Mac. Gated datasets (Humanity's Last Exam, LiveCodeBench Pro, GAIA, XSTest) show the terms step first: accept the terms on Hugging Face while signed in, add a token with `roof eval providers set hf --key-file PATH`, then **Check again**.

- Chips: **All**, **Seen in your runs**, **Any run got wrong**, **Random 10** (seeded; press again, or R, for another ten). One dot per run that saw a question: green right, red wrong.
- A question: the text, the reference answer and the worked solution when the dataset has one; **what the model sees** (the prompt exactly as a run sent it, or the template, with the number of worked examples); **how it's marked** in plain words, with its lesson; **how your runs answered**, each with "transcript ›".
- **Run just this one** opens Run with that one question (cost first). **Add to an eval set** puts the question into the next version of a set of questions (or a new set); a frozen version is never edited. "transcript ›" opens that run at this question.

## Your evals

Benchmarks measure other people's tasks. **Your evals** measure yours: a set of questions built from a repo's own history.

- **Start a new one › From a repo's fixed bugs:** pick the repo, the kind (fix locator or bug triage), how far back, how many cases, and optionally a Linear key file (a path; the key is never shown), then **Preview** and **Freeze as v1**. Or from the command line: `roof eval evalset build --repo <your repo>`, adding `--linear-key-file <file>` to use the Linear issue as each bug report (the file must hold only the key).
- **From past sessions** and **From a file of questions** are coming (LAB-2079, LAB-2078).
- A set's page: its version and the date it was frozen, what the agent gets and when it is correct, its source, how many fixes were picked, the **no-model floor** and the **best so far**; then **every case** with the files the fix touched and **who solved it** ("2 of 5" runs on this version; "nobody" in red), hardest first (or newest, or by issue). A case opens to each run's answer.
- **Build v2** (right): how many bugs were fixed since this version, the settings, what is left out on purpose and why, **Preview the new cases**, then **Freeze as v2**. v2 is this version's cases unchanged plus the new ones; this version is never edited, so its scores stay comparable. **Versions** lists each with its cases and runs.
- The first kind of question is the **fix locator**. It shows a real bug report and the repo's source files as they were just before the fix, and asks which files to change. It is checked by code: correct when one of the first three files named is a file the real fix changed.
- The questions come from fix commits that name an issue and change one to three source files (tests, docs and site pages aside). An issue's first fix commit is the answer. A report that already names the file is left out, and so is an issue that is not fixed.
- **The no-model floor** on the card is what you get with no model at all, by always guessing the three files fixed most often. A score means something only above it.
- Sets are versioned and never edited. A rebuild that finds different questions makes a new version; an unchanged one reuses the last. Old results stay comparable to the version they ran on.

## A model as judge

Some answers code can't check: a triage note, an explanation, a summary. A model can grade them, but only after you know how often it agrees with you.

**In the app:** Your evals › a judge (or **A judge for prose answers** to make one: name, the runs whose answers it grades, your rubric).

- **Label:** the answers you haven't labelled come first, likely fails at the top (the judge passed them but code says no file the fix changed was named). Each shows the bug report and the files the fix changed, the answer with its code check ("files named: 1 of 2 right"), and the rubric. **P** pass, **F** fail, **S** skip, ↑ ↓ to move; for a reason, Tab to the one-line **Why?**, type it, Return, then P or F saves both and moves on. ⌘Z (or **Undo last**) takes back your last label. Labels are saved as yours; a model's label is shown as that model's and never counts as you.
- **How far to trust it** updates after each label, from the judge's last run against your labels as they are now (no new run): agrees, passes good, fails bad (red under 70 %), a plain reading ("It's lenient: it passes … of the answers you failed"), "Too few labels to trust" until 10 of yours are held back, what would help, and self-preference. **Rebuild judge as v2** makes your labels its examples; v1 and its results stay as they are.
- **Rubric:** edit it; saving makes a draft for the next version only. **Agreement:** the three numbers per source (you, a model's labels, code) with their ranges, and the table of judge × label, each cell opening its answers. **Versions:** each version's rubric, examples, held-back labels, runs and agreement.

**From the command line:**

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
- Results show both side by side; the lm-eval column is named `lm-eval:<task>`. **Learn › What the harness adds** explains why they differ, with a measured example.

`arc_challenge_chat_letter` is lm-eval's `arc_challenge_chat` with one change: it reads the answer letter out of the sentence. The original expects the server to continue a pre-filled reply, which llama-server does not, so it scores 0.

## Run

One page: **1 · What** × **2 · Who** × **3 · How much**, the cost on the right, the queue at the foot. **Run this…**, **Run…**, **Run just this one**, **Run again** and a suggestion all open it pre-filled; nothing starts until you press **Start**.

- **What:** your sets first, then the benchmarks you ran lately, then **+ any benchmark…** (search). A benchmark with several tasks lists them as checkboxes.
- **Who**, agents first. **Agents · your seats:** Claude Code (C1) and Codex (CX) answer on your subscription login, with how full each seat's 5-hour window is ("seat usage unknown" when its usage is older than 6 hours). OpenCode, Kimi (no headless mode), Gemini CLI and Antigravity are listed with why they can't run yet. **Models · API:** the suggested models whose provider has a key (the rest are folded, with the command that adds a key), and **agent on an API model…** (an agent's CLI run on an API model in a benchmark's sandbox, billed in dollars). **On this Mac · free:** local models, the free stand-in (`mockllm/model`) and **+ any model id…**. An agent is a model plus its harness; run both to see what the harness adds.
- **How much:** questions (5 or All for a set or a small benchmark), attempts each (empty = the benchmark's default), temperature, seed (42), cap per run; **where the code runs** for benchmarks that run code (this Mac's Docker, Daytona, Modal); **••• Advanced** for task arguments.
- **What this run can tell you:** "20 cases × 3 attempts gives about ±12 points per contestant, so differences smaller than that are noise." Everyone answers the same questions, so they compare question by question (paired).
- **Cost before you start**, per contestant: agents on seats show **seat** and the share of each seat's 5-hour window the run will use (a guess until this Mac has measured a run); models show dollars. Each run is capped (the grader counted ×1.5, since grading is not stopped mid-run). **Start N runs** is disabled with the reason: nothing picked, a provider without a key, Docker stopped, a seat too full, or over the cap. ↩ starts when the panel is valid (not while you type in a field).
- **Agents on your seats** answer your own sets only. Each case gets a fresh git worktree of the set's repo at the commit before the fix; the agent works in it with read-only tools, its last message is the answer, and the set's own check scores it. The worktree is removed after every case, also when a case fails or you cancel. Nothing is committed or pushed, and no API key is in the agent's environment, so a seat run never spends API credit. Before Start, the seat must have room under the router's limit (90 % of its 5-hour window); during a run, a full seat makes the run **wait** ("waiting for seat C1") instead of failing.
- **When a seat's use is unknown** (no usage file, or one older than 6 hours), the run never goes on silently: before each case it waits with "seat use unknown" until One Roof can see the use under 90 %, or until you press **Run anyway** on that run in the queue (your choice is recorded in the run; `roof eval run-anyway <run>` does the same). Run says so above Start instead of "One Roof waits if a seat runs low". The check is made between cases, not during one: a case is one read-only question with a 10-minute limit, so a run can pass 90 % by at most one case's share.
- **What an agent can reach.** Each case's worktree is in the system's temp folder, and the agent starts in it. Claude Code runs in restricted mode: its file tools stay in the case folder, it has no shell or web tools, your user, project and local settings are not loaded (so none of your hooks run), and a per-run settings file also turns every hook off and denies reading your secrets and settings folders (`~/Projects/_common/access_admin`, `~/.config`, `~/.ssh`, `~/Library`, `~/.aws`, `~/.claude`, `~/.codex` and others); MCP servers are off and anything that would ask permission is refused. Codex runs in its read-only sandbox from the case folder, without your Codex config, rules, hooks, plugins, apps, browser or computer use. Its sandbox blocks writes, not reads: **Codex can still read files outside the case folder**, and Run says so when Codex is picked.
- **The queue:** two runs at a time; closing One Roof does not stop them. Each row shows progress, why it failed ("failed: Docker stopped", with what to do on hover) or why it waits, and **Cancel**, **Resume** (finished questions are kept) and **Results**. A row opens the run.

The stand-in model (`mockllm/model`) and models on this Mac are free: use them to try a benchmark before paying for a real model.

## Results

On the left: **By eval · All × all · X-ray**, your evals then benchmarks with how many finished runs each has (red when the latest failed), and **Export CSV · JSON** (every run and metric with its range).

- **By eval:** the **leaderboard** of one eval version: the latest run of each contestant, agents first, the baseline (free stand-in) last and unranked. Each row: kind (Agent, Model, On this Mac, Baseline), score, a 0–100 bar with the 95 % range and the **floor** dashed (the no-model floor for your sets, chance for a benchmark), a dashed track under 30 answers, cost (seat, dollars or free), dollars per right answer, and the run's date, which opens it. A judged set shows the judge's agreement with you; click it for the judge. ↑ ↓ and Return work once the card has focus. A set with several versions shows a version switch: versions are never mixed.
- **Compare:** A vs B (the top two by default) on the same cases, paired, with the verdict in words: "Can't tell them apart yet" while the 95 % range of the difference crosses zero, else who is better. Under 10 shared questions no winner is called at all ("Can't tell them apart yet — too few shared questions (n)"), however clear the difference looks. The difference is drawn on an axis through 0, then how many cases only one of them solved and how many tied; **See the N cases** opens A's run at those cases with B's answer beside each. Runs that share no cases are compared unpaired, and it says so.
- **Over time:** every run on this version, a line per contestant, the floor dashed. A contestant's latest score below its previous one is circled as a **possible drop** ("possible" goes away only when the paired range excludes zero), with what to do (**Re-run ×3** opens Run with 3 attempts).
- **All × all:** the 1.9.37 grid (the latest run of each model on each task, its range, dashed under 30 questions, the judge's agreement) and **every run**.
- **X-ray:** per agent, from the repo's git history over 30 days: commits, lines added, churn, fixes its own work, reverted, followed by a fix (hover for each definition). Read-only; pick another repo from the menu.

### One run, question by question

Any score or run date opens it. The header: what ran on whom, its facts (answers, tokens, cost, dollars per right answer, time, seed, date), **Compare with…** (Results › Compare with this run as A) and **Run again** (Run with the same settings, cost first).

- **The strip:** the score with its 95 % range; for a judged run, the score checked by code beside it and **how far to trust the judge** (red when not trusted: "fails only 53 % of bad answers. Read this score as an upper bound."). Other runs list every metric with its range.
- **The answers:** **All · Wrong · Judge ≠ you** (W toggles Wrong; ↑ ↓ move), sorted wrong first (or by id, slowest, costliest). Each row: right or wrong, the case's title, what it named and where the fix was, and "judge ≠ you" or "unlabelled".
- **An answer:** the question (long inputs folded), the answer (the files it names highlighted; tool calls folded), then **Code check · Judge · You** side by side with each one's reason. Not labelled yet? **P** or **F** in the You box saves your label for the judge; **Label for the judge** opens the judge with this answer first. **Add to a regression set** puts this case into the next version of a set of the same kind (or a new set); old versions stay as they are. Expected answer and every scorer's reasoning are under the boxes.
- A run still going fills in live; a failed run shows its error, what to do and **Resume**.

## Learn

Sixteen short lessons on reading eval numbers, each using this Mac's own runs as examples. The subtitle counts them and how many you have done.

- **The lessons (left)**, in six groups: **Start** (Your first eval, free) · **Reading a score** (Accuracy and chance, The 95 % range, Standard error, Is the difference real?, pass@1 and pass@k, Attempts per question) · **How answers are marked** (Exact match and parsing, Model judges and their limits, Your labels as ground truth) · **Agents vs models** (What the harness adds, Cost per solved task) · **Your own evals** (Golden sets from repo history, Why versions are frozen) · **Reading leaderboards** (Saturation and headroom, Contamination). ✓ done, a filled dot for the one open, a ring for not yet. A lesson counts as done when you scroll to its end; ticks and the lesson you last opened are remembered.
- **A lesson (middle):** where it sits ("Reading a score · 2 of 6"), the text (the 1.9.37 explanations, word for word, plus the new lessons), an example, and **Try it**: change the inputs and see the number move, with no run and no cost. The 95 % range explorer (questions 5 · 10 · 20 · 50 · 200 · 1000 at 80 % right: 50 gives 67–89 %), options and chance, standard error, two scores and a paired toggle with the verdict, pass@k by attempts, questions × attempts (the same ± points as Run), GSM8K's marking on a reply you type, a judge's error rates and the score it reports, how many labels you need, cost per solved task, headroom, and an old against a fresh benchmark. Three lessons have a picture instead (the harness, golden sets, frozen versions).
- **In your runs:** up to three of this Mac's finished runs that show the lesson (for the range: runs on few questions and one on many, with their ranges, red under 30), one sentence on what they say, and **open ›** to the run. With no such run: "No runs on this Mac show this yet".
- **Your first eval, free (right):** the four steps of 1.9.37's walkthrough, ticked from what really happened: a free stand-in GSM8K run finished, Results opened, a run's questions opened, and a paid GSM8K run compared. **Continue: step N** goes to the next one: Run pre-filled with 5 GSM8K questions on the stand-in (cap $0) or on Claude Haiku (cap $0.05), Results, or that run's first question. The lesson "Your first eval, free" keeps 1.9.37's text and its two buttons.
- **Where this shows up:** the places in Evals where the lesson's number appears, each a link; then **Next** with one line on it.

## Keys and sign-ins

One Roof never stores a key value. Point it at a key file you keep, once per provider:

```
roof eval providers set anthropic --key-file ~/path/to/anthropic.key
```

Providers: anthropic, openai, google, openrouter, fireworks, together, mistral, grok, groq, deepseek. A key already in your shell environment also works.

Some datasets are gated on Hugging Face (Humanity's Last Exam, LiveCodeBench Pro, GAIA, XSTest): sign in once (`hf auth login`) and press **Agree and access** on each dataset's page. A failed run says which step is missing.

## From the command line

`roof eval` does everything the place does: `setup`, `doctor`, `catalog`, `overview`, `anatomy`, `items`, `item`, `item-results`, `scores`, `estimate`, `run` (`--sample-id` for one question), `status`, `cancel`, `resume`, `results`, `samples`, `sample`, `export`, `evalset` (`build --dry-run`, `build --extend`, `versions`), `judge` (`items`, `queue`, `trust`, `advise`, `rubric`, `versions`, `label --undo`), `lmeval`. Add `--json` for scripts and loops. The data lives in `~/Library/Application Support/One Roof/evals`.
