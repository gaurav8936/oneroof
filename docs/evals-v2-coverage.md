# Evals v2 coverage map (One Roof 2.0.4)

Every Evals feature in One Roof 2.0.3 and where it lives in 2.0.4, so nothing is lost in the redesign. The same rows are in the app: Evals › Lessons › Where everything went (from `EvalsCoverage.rows` in `app/Sources/OneRoofCore/EvalsLaneB.swift`); a unit test (`EvalsLaneBTests`) fails if this page and the code disagree.

Status: **Kept** (same feature, maybe new words or place in the screen) · **Merged** (joined with another screen) · **Moved** (a new home) · **Removed** · **New** (added in 2.0.4).

## 2.0.4 screens

Six tabs: Overview · Compare · Changes · Real history · Our tasks · Public benchmarks. Five drill-downs: One test (bug by bug) and All results (under Compare), One task and Check the grader (under Our tasks), A public benchmark (under Public benchmarks). Two sheets over any tab: Set up a test (also the only home of the queue, opened by Running · N in the header) and Lessons.

## Features

| 2.0.3 feature | Was in | Now in 2.0.4 | Status | Screen |
|---|---|---|---|---|
| How to: 8 scenes, narration, read marks | How to tab | Lessons › How to; Overview's layer picture | Merged | Lessons |
| Overview scorecards per eval | Overview | Compare per task + All results | Merged | Compare |
| Hover card on every number + Lesson › | every tab | Every number, every screen | Kept | every screen |
| Overview: what changed since last time | Overview | Changes | Kept | Changes |
| Overview: running now | Overview | Set up a test › Running and recent (Running · N in the header) | Moved | Set up a test |
| Overview: one suggested next eval | Overview | Overview: "To answer it properly" on each question | Kept | Overview |
| Setup card: install engine with uv, uv/Docker status | every tab | Shown instead of the tabs until the engine is ready | Kept | every screen |
| Busy and error lines | every tab | Under the header | Kept | every screen |
| Subtitle counts | header | Overview subtitle + coverage | Kept | Overview |
| Your evals: set page facts | Your evals › set | One task › Built from · Picked · Blind guess gets · Best so far | Kept | One task |
| Cases table, solved by, sort | Your evals › set | One task › the bugs table (hardest first, newest, issue) | Kept | One task |
| Build next version: settings, left out on purpose, preview, freeze | Your evals › set | One task › Next version | Kept | One task |
| Versions list | Your evals › set | One task › Versions | Kept | One task |
| Start a new one: from fixed bugs (+ CLI) | Your evals sidebar | Our tasks › + New task · From fixed bugs in a repo; One task › command line | Kept | Our tasks |
| Judge: Label queue, P/F/S, Why, undo | Your evals › judge | Check the grader › Label | Kept | Check the grader |
| Judge: How far to trust it, what would help, also checked | Your evals › judge | Check the grader › trust tiles + verdict; right column | Kept | Check the grader |
| Judge: Rubric, Agreement, Versions, Rebuild v2 | Your evals › judge | Check the grader › Rule · Agreement · Versions; Rebuild grader | Kept | Check the grader |
| Explore: shelves, topics, more topics, graded by, filters, search, rescan | Explore | A public benchmark › the list on the left | Kept | A public benchmark |
| Benchmark: facts, how one question is scored, on this Mac, teaches, watch out, needs, cost, paper, source | Explore › benchmark | A public benchmark › How it works | Kept | A public benchmark |
| Benchmark: Questions (load prompt, gated sets) | Explore › Questions | A public benchmark › Questions | Kept | A public benchmark |
| Benchmark: Published scores, Check now | Explore › Scores | A public benchmark › Published scores | Kept | A public benchmark |
| Benchmark: Your runs | Explore › Your runs | A public benchmark › Your runs | Kept | A public benchmark |
| Run: What (sets, benchmarks, tasks, any benchmark) | Run tab | Set up a test › 1 Which task | Kept | Set up a test |
| Run: Who (agents with seat %, API models, on this Mac, any model id, agent on API model) | Run tab | Set up a test › 2 Which setups (layer, agent + model, runs on, rules) | Kept | Set up a test |
| Run: How much (questions, attempts, temperature, seed, cap, advanced) | Run tab | Set up a test › 3 How many | Kept | Set up a test |
| Run: What this run can tell you | Run tab | Set up a test › What this test can tell you (before the cost) | Kept | Set up a test |
| Run: Cost before you start, seat share, cap ×1.5, Start N | Run tab | Set up a test › Before you start | Kept | Set up a test |
| Run: Queue (two at a time, Run anyway, Cancel, Resume, Results, show all) | Run tab | Set up a test › Running and recent | Kept | Set up a test |
| Results: By eval leaderboard, version switch | Results | Compare (per task); versions in One task | Merged | Compare |
| Results: Compare A vs B, paired verdict, see the N cases | Results | Compare headline + Compare with… | Kept | Compare |
| Results: Over time, possible drop, re-run ×3 | Results | Changes | Kept | Changes |
| Results: All × all + every run | Results | All results | Kept | All results |
| Results: X-ray | Results | Real history | Moved | Real history |
| Results: Export CSV · JSON | Results | All results | Kept | All results |
| Run detail: facts, score strip, answers list, filters, sort | Run detail | One test, bug by bug | Kept | One test |
| Run detail: code check · judge · you, add to regression set, compare with, run again | Run detail | One test, bug by bug | Kept | One test |
| Learn: 16 lessons, Try it, In your runs, first eval steps, where this shows up | Learn tab | Lessons (In your tests, Your first test) | Kept | Lessons |
| Keys, Hugging Face sign-in, providers | Settings › Evals | Settings › Evals (unchanged) | Kept | every screen |
| Second Draft banner on drill-downs | drill-downs | One Draft tag by the title | Removed | every screen |
| Your evals: Judges list with trust and labels to go | Your evals sidebar | Our tasks › the grader banner on its task + Check the grader | Moved | Our tasks |
| Your evals: From past sessions / From a file of questions (coming) | Your evals sidebar | Our tasks › the two + New task tiles marked coming | Kept | Our tasks |
| Your evals: A judge for prose answers | Your evals sidebar | New test or task ▾ › New grader | Moved | Our tasks |
| Explore: Judges shelf | Explore | A public benchmark › Judges shelf (opens Check the grader) | Kept | A public benchmark |
| Explore: Run this… | Explore › benchmark | A public benchmark › Test a model on it… (Set up a test pre-filled) | Kept | A public benchmark |
| Run: where its code runs (Docker, Modal, cloud sandboxes) | Run tab | Set up a test › 3 How many › Where its code runs | Kept | Set up a test |
| Run: Hugging Face gate on gated sets | Run tab | Set up a test › Before you start (Start stays off until signed in) | Kept | Set up a test |
| Learn: Try it widgets (16, local maths, no cost) | Learn tab | Lessons › Try it | Kept | Lessons |
| The stamp: layer · model · agent + CLI version · rules on/off @ hash · task version | new in 2.0.4 | Every score; Set up a test previews it | New | Set up a test |
| Our rules off (clean) or on @ hash | new in 2.0.4 | Set up a test › 2 Which setups › Our rules | New | Set up a test |
| Agent and model picked together (agent × model grid) | new in 2.0.4 | Set up a test › 2 Which setups; Compare's grid | New | Set up a test |
| Verdicts by rule (paired 95 % range, no winner under 10 shared bugs, blind guess) | new in 2.0.4 | Compare, One task, Overview | New | Compare |
| What a test can tell you before what it costs (power) | new in 2.0.4 | Set up a test › 3 How many; One task › Next version | New | Set up a test |
| Plain task names and the blind guess | new in 2.0.4 | Our tasks, One task, Compare | New | Our tasks |
| Public benchmarks framed by purpose | new in 2.0.4 | Public benchmarks › three purpose cards | New | Public benchmarks |
| Where everything went (this map) | new in 2.0.4 | Lessons › Where everything went; docs/evals-v2-coverage.md | New | Lessons |

## Self-test names

`ONEROOF_SELFTEST_EVALS_TAB` keeps every 2.0.3 name; each opens its 2.0.4 home (`EvalsScreen.selfTest`).

| 2.0.3 name | Opens in 2.0.4 |
|---|---|
| `how-to` | lessons (How to) |
| `howto` | lessons (How to) |
| `overview` | overview |
| `your-evals` | our-tasks |
| `yourevals` | our-tasks |
| `build` | our-tasks |
| `judge` | grader |
| `explore` | benchmarks |
| `catalog` | benchmarks |
| `question` | one-benchmark (Questions) |
| `questions` | one-benchmark (Questions) |
| `scores` | one-benchmark (Published scores) |
| `your-runs` | one-benchmark (Your runs) |
| `run` | setup |
| `runs` | setup |
| `sheet` | setup (pre-filled) |
| `results` | compare |
| `run-detail` | one-test |
| `one-run` | one-test |
| `all-by-all` | all-results |
| `allbyall` | all-results |
| `matrix` | all-results |
| `xray` | real-history |
| `x-ray` | real-history |
| `learn` | lessons |

New names: `overview`, `compare`, `one-test`, `all-results`, `changes`, `real-history`, `our-tasks`, `one-task`, `grader`, `benchmarks`, `one-benchmark`, `setup`, `lessons`.
