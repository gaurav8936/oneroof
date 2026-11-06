# Evals v3 coverage map (One Roof 2.0.5)

Every Evals element in One Roof 2.0.4 and where it lives in 2.0.5, so nothing is lost in the redesign, followed by what 2.0.5 adds and, so the map is complete across versions, every 2.0.3 feature and its 2.0.4 home. The same rows are in the app: Evals › Lessons › Where everything went (from `EvalsCoverage.rows` in `app/Sources/OneRoofCore/EvalsLaneB.swift`); a unit test (`EvalsLaneBTests`) fails if this page and the code disagree. The 2.0.4 page, `docs/evals-v2-coverage.md`, is kept as it was.

Status: **Kept** (same feature, maybe new words or a new way in) · **Merged** (joined with another screen) · **Moved** (a new home) · **Removed** · **New** (added in that release).

## 2.0.5 screens

No tabs. Evals opens on the **launch view**: two bars, one per kind of job, each split by where its evidence comes from. **One-shot jobs** (one prompt to a model, tested as the model alone): Public tests · Ours · Loops. **Agent jobs** (Claude Code or Codex on our code with our setup, tested as we use it): Our tests · Our loop runs; Public agent benchmarks sit outside the agent bar, under it, as context. Each segment opens its page: One-shot jobs › Public tests, One-shot jobs › Our tests, One-shot jobs › Loop runs, Agent jobs › Our tests (with the Agent × model grid), Agent jobs › Our loop runs. Changes and Real history are Agent jobs pages, also reached from the launch view's answer buttons. Our tasks and Public benchmarks (the library) are unchanged. Drill-downs as in 2.0.4: One test, All results, One task, Check the grader, A public benchmark. Two sheets over any page: Set up a test and Lessons. A breadcrumb replaces the tab bar; ⌘[ goes back.

How the 2.0.4 tabs map: **Overview** → the launch view · **Compare** → One-shot jobs › Our tests and Agent jobs › Our tests (the grid is on Agent jobs) · **Changes** and **Real history** → Agent jobs pages, also answer buttons on the launch view · **Our tasks** → unchanged · **Public benchmarks** → One-shot jobs › Public tests and Agent jobs › Public agent benchmarks, plus the library.

Keys: ⌃⌥0 the launch view · ⌃⌥1–5 the five segment pages · ⌃⌥6 Public agent benchmarks · ⌃⌥7 Changes · ⌃⌥8 Real history. ⌘[ back, Esc closes a sheet.

## 2.0.4 → 2.0.5

| 2.0.4 element | Was in | Now in 2.0.5 | Status | Opens |
|---|---|---|---|---|
| Header: title and back crumb | header | Breadcrumb ‹ Evals › job › source (› item); each step but the last opens its page | Moved | every page |
| Header: one Draft tag | header | Header, unchanged | Kept | every page |
| Header: subtitle counts | header | Header subtitle (benchmarks · our tasks · graders · finished tests · running), unchanged | Kept | Evals (launch view) |
| Header: six tabs | header | The launch view (one bar per kind of job) and the breadcrumb | Merged | Evals (launch view) |
| Header: setup card and Install | header | Shown instead of every page until the engine is ready, unchanged | Kept | every page |
| Header: Checking the eval engine… line | header | Under the header, unchanged | Kept | every page |
| Header: Running · N | header | Header, unchanged: opens Set up a test › Running and recent | Kept | Set up a test |
| Header: New test or task ▾ | header | Header, unchanged (the name stays, not + New) | Kept | Our tasks |
| Header: Lessons button | header | Header, unchanged | Kept | Lessons |
| Header: busy and error lines | header | Under the header, unchanged | Kept | every page |
| Header: two sheets over any page | header | Set up a test and Lessons open over any page, unchanged | Kept | every page |
| Keys: Esc closes a sheet | keys | Unchanged | Kept | every page |
| Keys: ⌘[ back | keys | ⌘[ goes back: a drill-down first, then the breadcrumb, then the launch view | Kept | every page |
| Keys: ⌃⌥1–6 open the six tabs | keys | ⌃⌥0–8: the launch view, the five segment pages, Public agent benchmarks, Changes, Real history | Moved | Evals (launch view) |
| Header: refresh every 3 seconds while tests run | header | Unchanged | Kept | every page |
| Header: a started test opens the queue | header | Unchanged: Start opens Set up a test › Running and recent | Kept | Set up a test |
| Settings: Redesigned Evals switch | Settings › Evals | Settings › Evals, unchanged: off still shows the 1.9.37 Evals | Kept | no screen |
| Settings: Evals › Hugging Face | Settings › Evals | Settings › Evals, unchanged | Kept | no screen |
| Self-test: the 13 screen names | self-test | 18 names, one per 2.0.5 screen (below); each 2.0.4 name opens its 2.0.5 home | Moved | no screen |
| Self-test: other 2.0.4 spellings | self-test | Still accepted, mapped below | Kept | no screen |
| Self-test: the 25 names from 2.0.3 and 1.9.37 | self-test | Still accepted, mapped below | Kept | no screen |
| Self-test: the other variables (run, set, judge …) | self-test | Every ONEROOF_SELFTEST_EVALS_* variable keeps working | Kept | no screen |
| Self-test: COMPARE_VIEW=grid | self-test | Opens the Agent × model grid on Agent jobs › Our tests | Moved | Agent jobs › Our tests |
| Self-test: HOVER and QUESTION | self-test | Unchanged | Kept | no screen |
| Overview: inside / outside layer picture | Overview | Launch view: one bar per kind of job, split by where its evidence comes from | Merged | Evals (launch view) |
| Overview: top band, the model | Overview | Launch view: the One-shot jobs bar (Public tests · Ours · Loops) | Merged | Evals (launch view) |
| Overview: middle band, the agent out of the box | Overview | Agent jobs › Our tests with Rules: clean, and Agent jobs › Public agent benchmarks | Moved | Agent jobs › Our tests |
| Overview: stand-in count | Overview | Launch view subtitle hover; the stand-in line on Our tests | Moved | Evals (launch view) |
| Overview: waiting count | Overview | Launch view bar hover; waiting rows on Our tests | Moved | Evals (launch view) |
| Overview: N agent tasks outside | Overview | The Public agent benchmarks button under the agent bar | Moved | Agent jobs › Public agent benchmarks |
| Overview: grader runs counted apart | Overview | Launch view: grader runs counted apart from setups | Moved | Evals (launch view) |
| Overview: counted from the run store note | Overview | Launch view: the line under the legend, counted from this Mac's run store and the loops' ledger (30 days) | Moved | Evals (launch view) |
| Overview: base band, the full setup | Overview | Launch view: the Agent jobs bar (Our tests · Our loop runs) | Merged | Evals (launch view) |
| Overview: band clicks | Overview | Each bar segment opens its page | Kept | Evals (launch view) |
| Overview: How to read Evals and the first-test link | Overview | Lessons (header button) › Your first test, free | Moved | Lessons |
| Overview: question 1, which setup does best | Overview | One-shot jobs › Our tests and Agent jobs › Our tests: the question and a one-sentence answer | Moved | One-shot jobs › Our tests |
| Overview: question 1 rules and the Open the queue fix | Overview | Agent jobs › Our tests: the answer and Open the queue | Moved | Agent jobs › Our tests |
| Overview: question 1 mini-chart with the blind-guess tick | Overview | Our tests rows: squares with the blind-guess tick | Merged | One-shot jobs › Our tests |
| Overview: question 1, to answer it properly | Overview | Our tests pages, under the answer | Moved | One-shot jobs › Our tests |
| Overview: question 2, did my last change help | Overview | Agent jobs › Changes; the launch view's Did my last change help? button | Moved | Changes |
| Overview: what a test records today | Overview | Launch view › Question 2 card: What a test records today; Lessons | Moved | Evals (launch view) |
| Overview: question 2 fix (model per commit) | Overview | Launch view › Question 2 card: the fix under What a test records today | Moved | Evals (launch view) |
| Overview: question 3, what git says | Overview | Agent jobs › Real history; the launch view's What does git say about our real work? button | Moved | Real history |
| Overview: question 3 bars per agent | Overview | Real history: one card and bar per agent | Merged | Real history |
| Overview: question 3 fix (sign every commit) | Overview | Real history: the No agent name card | Merged | Real history |
| Overview: also suggested | Overview | Launch view (it still reads the overview answer) | Moved | Evals (launch view) |
| Overview: error line | Overview | Under the header on the launch view | Moved | Evals (launch view) |
| Overview: the overview engine call | Overview | Still read by the launch view: suggestions, the re-run ×3 card on Changes, the error line | Kept | Evals (launch view) |
| Verdicts: two-setup sentences | every page | Same rules, every page that compares | Kept | One-shot jobs › Our tests |
| Verdicts: against the blind guess | every page | Same rules: Our tests, One task, One test | Kept | One-shot jobs › Our tests |
| Verdicts: on new bugs, expect L to H | every page | Same rules: Our tests, One test | Kept | One-shot jobs › Our tests |
| Verdicts: a blind guess gets N | every page | Same rules: Our tests, One task | Kept | One-shot jobs › Our tests |
| Verdicts: Changes lead and the unknown-floor caveat | Changes | Agent jobs › Changes, unchanged | Kept | Changes |
| Verdicts: how far to trust the grader | Check the grader | Check the grader, unchanged | Kept | Check the grader |
| Compare: task cards | Compare | One-shot jobs › Our tests and Agent jobs › Our tests: task cards, with a kind chip | Kept | One-shot jobs › Our tests |
| Compare: All results button | Compare | Our tests pages: All results ›; the launch view's Every result, one grid | Kept | All results |
| Compare: empty, error and reading states | Compare | One-shot jobs › Our tests and Agent jobs › Our tests, unchanged | Kept | One-shot jobs › Our tests |
| Compare: headline sentence | Compare | One-shot jobs › Our tests and Agent jobs › Our tests: the one-sentence answer | Kept | One-shot jobs › Our tests |
| Compare: By setup · Agent × model switch | Compare | Agent jobs › Our tests | Kept | Agent jobs › Our tests |
| Compare: vN · frozen bugs note | Compare | One-shot jobs › Our tests and Agent jobs › Our tests, unchanged | Kept | One-shot jobs › Our tests |
| Compare: ranked setup rows, ↑ ↓ and Return | Compare | One-shot jobs › Our tests and Agent jobs › Our tests, unchanged | Kept | One-shot jobs › Our tests |
| Compare: row score and verdict against the blind guess | Compare | One-shot jobs › Our tests and Agent jobs › Our tests, unchanged | Kept | One-shot jobs › Our tests |
| Compare: tick two for the paired verdict | Compare | One-shot jobs › Our tests and Agent jobs › Our tests, unchanged | Kept | One-shot jobs › Our tests |
| Compare: row caption by layer | Compare | One-shot jobs › Our tests and Agent jobs › Our tests: tested as model · agent clean · agent with our rules | Kept | One-shot jobs › Our tests |
| Compare: stamp line on rows | Compare | One-shot jobs › Our tests and Agent jobs › Our tests, unchanged | Kept | One-shot jobs › Our tests |
| Compare: waiting, queued, expired and failed rows | Compare | One-shot jobs › Our tests and Agent jobs › Our tests, unchanged | Kept | Agent jobs › Our tests |
| Compare: Open the queue and Resume or start again | Compare | One-shot jobs › Our tests and Agent jobs › Our tests, unchanged | Kept | Agent jobs › Our tests |
| Compare: bug squares and the blind-guess tick | Compare | One-shot jobs › Our tests and Agent jobs › Our tests, unchanged | Kept | One-shot jobs › Our tests |
| Compare: missed-bugs sentence | Compare | One-shot jobs › Our tests and Agent jobs › Our tests, unchanged | Kept | One-shot jobs › Our tests |
| Compare: cost, $ per right answer, date | Compare | One-shot jobs › Our tests and Agent jobs › Our tests, unchanged | Kept | One-shot jobs › Our tests |
| Compare: legend and stand-in line | Compare | One-shot jobs › Our tests and Agent jobs › Our tests, unchanged | Kept | One-shot jobs › Our tests |
| Compare: paired card and its empty texts | Compare | One-shot jobs › Our tests and Agent jobs › Our tests, unchanged | Kept | One-shot jobs › Our tests |
| Compare: paired verdict, axis, only-line, See the N bugs | Compare | One-shot jobs › Our tests and Agent jobs › Our tests, unchanged | Kept | One-shot jobs › Our tests |
| Compare: Agent × model grid | Compare | Agent jobs › Our tests › Agent × model grid | Moved | Agent jobs › Our tests |
| Compare: grid rules off / on picker | Compare | Agent × model grid: Rules: with our rules (default) · clean | Kept | Agent jobs › Our tests |
| Compare: grid done cell | Compare | Agent × model grid, unchanged | Kept | Agent jobs › Our tests |
| Compare: grid live cell | Compare | Agent × model grid, unchanged | Kept | Agent jobs › Our tests |
| Compare: grid not run · Test cell | Compare | Agent × model grid, unchanged | Kept | Agent jobs › Our tests |
| Compare: grid not available cell | Compare | Agent × model grid, unchanged | Kept | Agent jobs › Our tests |
| Compare: grid No model floor row | Compare | Agent × model grid, unchanged | Kept | Agent jobs › Our tests |
| Compare: grid CLI-default note | Compare | Agent × model grid, unchanged | Kept | Agent jobs › Our tests |
| Compare: not tested on this task yet (N) and Test them | Compare | One-shot jobs › Our tests and Agent jobs › Our tests, unchanged | Kept | One-shot jobs › Our tests |
| Compare: engine leaderboard by setup, compare | Compare | Unchanged | Kept | One-shot jobs › Our tests |
| One test: opens on the newest test | One test | One test, bug by bug, unchanged | Kept | One test |
| One test: title and subtitle | One test | One test, bug by bug, unchanged | Kept | One test |
| One test: score strip and verdict | One test | One test, bug by bug, unchanged | Kept | One test |
| One test: squares and tick, clickable | One test | One test, bug by bug, unchanged | Kept | One test |
| One test: numbers line (expect, cost, $ per right, date, seed) | One test | One test, bug by bug, unchanged | Kept | One test |
| One test: Compare with… | One test | One test, bug by bug, unchanged | Kept | One test |
| One test: Test again | One test | One test, bug by bug, unchanged | Kept | One test |
| One test: stamp line | One test | One test, bug by bug, unchanged | Kept | One test |
| One test: facts line | One test | One test, bug by bug, unchanged | Kept | One test |
| One test: Test again reading and unreadable notes | One test | One test, bug by bug, unchanged | Kept | One test |
| One test: judged code score, trust line, metrics | One test | One test, bug by bug, unchanged | Kept | One test |
| One test: failure line, What to do, Resume | One test | One test, bug by bug, unchanged | Kept | One test |
| One test: toast | One test | One test, bug by bug, unchanged | Kept | One test |
| One test: All · Wrong · Grader ≠ you chips | One test | One test, bug by bug, unchanged | Kept | One test |
| One test: sort menu | One test | One test, bug by bug, unchanged | Kept | One test |
| One test: N bugs where the two tests differ | One test | One test, bug by bug, unchanged | Kept | One test |
| One test: answer rows, ↑ ↓ and W | One test | One test, bug by bug, unchanged | Kept | One test |
| One test: bug header and Label for the grader | One test | One test, bug by bug, unchanged | Kept | One test |
| One test: Add to next version sheet | One test | One test, bug by bug, unchanged | Kept | One test |
| One test: what it named vs what the fix changed | One test | One test, bug by bug, unchanged | Kept | One test |
| One test: attempt switcher | One test | One test, bug by bug, unchanged | Kept | One test |
| One test: code check · grader · you boxes, P / F quick label | One test | One test, bug by bug, unchanged | Kept | One test |
| One test: takeaway and B's answer | One test | One test, bug by bug, unchanged | Kept | One test |
| One test: reasoning, transcript, tool calls, expected answer, scorers | One test | One test, bug by bug, unchanged | Kept | One test |
| One test: refresh while a test runs | One test | One test, bug by bug, unchanged | Kept | One test |
| One test: engine calls | One test | Unchanged | Kept | One test |
| All results: Export CSV · JSON | All results | All results, unchanged | Kept | All results |
| All results: grid and its order | All results | All results, unchanged, plus a Kind column | Kept | All results |
| All results: cells, dashed under 30 | All results | All results, unchanged | Kept | All results |
| All results: grader and labeller columns | All results | All results, unchanged | Kept | All results |
| All results: scroll note and legend | All results | All results, unchanged | Kept | All results |
| All results: empty state and Set up a test | All results | All results, unchanged | Kept | All results |
| All results: every test list, Show all | All results | All results, unchanged | Kept | All results |
| Changes: intro line | Changes | Agent jobs › Changes, unchanged | Kept | Changes |
| Changes: we can't tell yet, Test the baseline now | Changes | Agent jobs › Changes, unchanged | Kept | Changes |
| Changes: recent changes card | Changes | Agent jobs › Changes, unchanged | Kept | Changes |
| Changes: Read again | Changes | Agent jobs › Changes, unchanged | Kept | Changes |
| Changes: change rows and Test before & after | Changes | Agent jobs › Changes, unchanged | Kept | Changes |
| Changes: row status rule | Changes | Agent jobs › Changes, unchanged | Kept | Changes |
| Changes: empty, error and reading states | Changes | Agent jobs › Changes, unchanged | Kept | Changes |
| Changes: before / after squares and ring | Changes | Agent jobs › Changes, unchanged | Kept | Changes |
| Changes: verdict line | Changes | Agent jobs › Changes, unchanged | Kept | Changes |
| Changes: floor of the pair's own version | Changes | Agent jobs › Changes, unchanged | Kept | Changes |
| Changes: never draws a pair that spans several changes | Changes | Agent jobs › Changes, unchanged | Kept | Changes |
| Changes: same setup, tested again | Changes | Agent jobs › Changes, unchanged | Kept | Changes |
| Changes: Re-run ×3 | Changes | Agent jobs › Changes, unchanged | Kept | Changes |
| Changes: re-test after every change switch | Changes | Agent jobs › Changes, unchanged | Kept | Changes |
| Changes: engine changes, compare, leaderboard | Changes | Unchanged | Kept | Changes |
| Real history: not a test line | Real history | Agent jobs › Real history, unchanged | Kept | Real history |
| Real history: repo picker (several repos, Add a repo, Back to our tasks' repos) | Real history | Agent jobs › Real history, unchanged | Kept | Real history |
| Real history: 30 / 60 / 90 days | Real history | Agent jobs › Real history, unchanged | Kept | Real history |
| Real history: Read again | Real history | Agent jobs › Real history, unchanged | Kept | Real history |
| Real history: empty, error and reading states | Real history | Agent jobs › Real history, unchanged | Kept | Real history |
| Real history: headline sentence | Real history | Agent jobs › Real history, unchanged | Kept | Real history |
| Real history: meta line with the computed date | Real history | Agent jobs › Real history, unchanged | Kept | Real history |
| Real history: agent card, commits and lines | Real history | Agent jobs › Real history, unchanged | Kept | Real history |
| Real history: split bar | Real history | Agent jobs › Real history, unchanged; its followed-by-a-fix part opens those commits | Kept | Real history |
| Real history: followed by a fix | Real history | Agent jobs › Real history, unchanged; See the N commits opens them | Kept | Real history |
| Real history: rewritten in N days | Real history | Agent jobs › Real history, unchanged; See the N commits opens them | Kept | Real history |
| Real history: fixes its own work | Real history | Agent jobs › Real history, unchanged | Kept | Real history |
| Real history: reverted | Real history | Agent jobs › Real history, unchanged; See the N commits opens them | Kept | Real history |
| Real history: model per commit, not recorded | Real history | Agent jobs › Real history, unchanged | Kept | Real history |
| Real history: No agent name card, hatched | Real history | Agent jobs › Real history, unchanged | Kept | Real history |
| Real history: how this fits with the tests | Real history | Agent jobs › Real history, unchanged | Kept | Real history |
| Real history: test-vs-history table | Real history | Agent jobs › Real history, unchanged | Kept | Real history |
| Real history: Open Compare | Real history | Agent jobs › Real history, unchanged, now a button | Kept | Real history |
| Real history: foot note (from git alone) | Real history | Agent jobs › Real history, unchanged | Kept | Real history |
| Real history: lesson hints on git numbers | Real history | Agent jobs › Real history, unchanged | Kept | Real history |
| Real history: engine xray | Real history | Unchanged, plus the commit lists | Kept | Real history |
| Our tasks: intro line | Our tasks | Our tasks, unchanged | Kept | Our tasks |
| Our tasks: empty state | Our tasks | Our tasks, unchanged | Kept | Our tasks |
| Our tasks: task card | Our tasks | Our tasks, unchanged, plus a kind chip | Kept | Our tasks |
| Our tasks: N real bugs and the ± hover | Our tasks | Our tasks, unchanged | Kept | Our tasks |
| Our tasks: layer chips per task | Our tasks | Our tasks: tested as chips (model · agent clean · agent with our rules) | Kept | Our tasks |
| Our tasks: next version footer, Preview, See the bugs | Our tasks | Our tasks, unchanged | Kept | Our tasks |
| Our tasks: grader banner, Check, Start labelling | Our tasks | Our tasks, unchanged | Kept | Our tasks |
| Our tasks: + New task tiles (two coming) | Our tasks | Our tasks, unchanged | Kept | Our tasks |
| Our tasks: graders list | Our tasks | Our tasks, unchanged | Kept | Our tasks |
| Our tasks: New task sheet | Our tasks | Our tasks, unchanged | Kept | Our tasks |
| Our tasks: coming sheets | Our tasks | Our tasks, unchanged | Kept | Our tasks |
| Our tasks: New grader sheet | Our tasks | Our tasks, unchanged | Kept | Our tasks |
| Our tasks: engine calls | Our tasks | Unchanged | Kept | Our tasks |
| One task: title and meta | One task | One task, unchanged | Kept | One task |
| One task: Test setups on it… | One task | One task, unchanged | Kept | One task |
| One task: built from | One task | One task, unchanged | Kept | One task |
| One task: picked and left out | One task | One task, unchanged | Kept | One task |
| One task: blind guess gets, and its rule | One task | One task, unchanged | Kept | One task |
| One task: best so far and its verdict | One task | One task, unchanged | Kept | One task |
| One task: bugs table, sort, solved by | One task | One task, unchanged | Kept | One task |
| One task: a bug row opens every setup's answer | One task | One task, unchanged | Kept | One task |
| One task: note under the table | One task | One task, unchanged | Kept | One task |
| One task: Next version card | One task | One task, unchanged | Kept | One task |
| One task: Versions card | One task | One task, unchanged | Kept | One task |
| One task: command line card | One task | One task, unchanged | Kept | One task |
| One task: engine calls | One task | Unchanged | Kept | One task |
| Check the grader: no grader yet | Check the grader | Check the grader, unchanged | Kept | Check the grader |
| Check the grader: title and subtitle | Check the grader | Check the grader, unchanged | Kept | Check the grader |
| Check the grader: Label · Rule · Agreement · Versions | Check the grader | Check the grader, unchanged | Kept | Check the grader |
| Check the grader: trust tiles | Check the grader | Check the grader, unchanged | Kept | Check the grader |
| Check the grader: verdict tile and Run the grader | Check the grader | Check the grader, unchanged | Kept | Check the grader |
| Check the grader: queue and progress | Check the grader | Check the grader, unchanged | Kept | Check the grader |
| Check the grader: labelled by you, Undo ⌘Z | Check the grader | Check the grader, unchanged | Kept | Check the grader |
| Check the grader: queue note (the first 10 teach) | Check the grader | Check the grader, unchanged | Kept | Check the grader |
| Check the grader: bug report and what the fix changed | Check the grader | Check the grader, unchanged | Kept | Check the grader |
| Check the grader: note, files named, what the grader and the other model said | Check the grader | Check the grader, unchanged | Kept | Check the grader |
| Check the grader: your label line | Check the grader | Check the grader, unchanged | Kept | Check the grader |
| Check the grader: A / B / T keys and buttons, ↑ ↓ in the queue | Check the grader | Check the grader, unchanged | Kept | Check the grader |
| Check the grader: every note labelled | Check the grader | Check the grader, unchanged | Kept | Check the grader |
| Check the grader: the rule and Edit | Check the grader | Check the grader, unchanged | Kept | Check the grader |
| Check the grader: versions and Rebuild | Check the grader | Check the grader, unchanged | Kept | Check the grader |
| Check the grader: what would help | Check the grader | Check the grader, unchanged | Kept | Check the grader |
| Check the grader: also checked | Check the grader | Check the grader, unchanged | Kept | Check the grader |
| Check the grader: rule draft and diff | Check the grader | Check the grader, unchanged | Kept | Check the grader |
| Check the grader: agreement per label source | Check the grader | Check the grader, unchanged | Kept | Check the grader |
| Check the grader: confusion grid | Check the grader | Check the grader, unchanged | Kept | Check the grader |
| Check the grader: a grid cell opens those notes | Check the grader | Check the grader, unchanged | Kept | Check the grader |
| Check the grader: Versions part | Check the grader | Check the grader, unchanged | Kept | Check the grader |
| Check the grader: engine calls | Check the grader | Unchanged | Kept | Check the grader |
| Public benchmarks: headline | Public benchmarks | One-shot jobs › Public tests (model benchmarks) and Agent jobs › Public agent benchmarks | Moved | One-shot jobs › Public tests |
| Public benchmarks: context, never the answer | Public benchmarks | One-shot jobs › Public tests, unchanged | Kept | One-shot jobs › Public tests |
| Public benchmarks: table with a Layer column | Public benchmarks | Public tests and Public agent benchmarks; the column reads Model or Agent, out of the box | Kept | One-shot jobs › Public tests |
| Public benchmarks: small-sample warning | Public benchmarks | One-shot jobs › Public tests, unchanged | Kept | One-shot jobs › Public tests |
| Public benchmarks: empty and reading states | Public benchmarks | Public tests and Public agent benchmarks, unchanged | Kept | One-shot jobs › Public tests |
| Public benchmarks: model rows before agent rows | Public benchmarks | Split: model rows on One-shot jobs › Public tests, agent rows on Public agent benchmarks | Moved | Agent jobs › Public agent benchmarks |
| Public benchmarks: three purpose cards | Public benchmarks | One-shot jobs › Public tests, unchanged | Kept | One-shot jobs › Public tests |
| Public benchmarks: engine calls | Public benchmarks | Unchanged | Kept | One-shot jobs › Public tests |
| Library: one of N line | A public benchmark | Public benchmarks › the library, unchanged | Kept | Public benchmarks |
| Library: search ⌘F | A public benchmark | Public benchmarks › the library, unchanged | Kept | Public benchmarks |
| Library: Start here shelf | A public benchmark | Public benchmarks › the library, unchanged | Kept | Public benchmarks |
| Library: Your evals shelf | A public benchmark | Public benchmarks › the library, unchanged | Kept | Public benchmarks |
| Library: Agent tasks shelf | A public benchmark | Public benchmarks › the library, unchanged; also reached from Public agent benchmarks | Kept | Public benchmarks |
| Library: Judges shelf opens Check the grader | A public benchmark | Public benchmarks › the library, unchanged | Kept | Public benchmarks |
| Library: topics and more topics | A public benchmark | Public benchmarks › the library, unchanged | Kept | Public benchmarks |
| Library: graded by | A public benchmark | Public benchmarks › the library, unchanged | Kept | Public benchmarks |
| Library: No Docker and I've run it filters | A public benchmark | Public benchmarks › the library, unchanged | Kept | Public benchmarks |
| Library: benchmark rows, chips and hint | A public benchmark | Public benchmarks › the library, unchanged | Kept | Public benchmarks |
| Library: footer, Rescan and versions | A public benchmark | Public benchmarks › the library, unchanged | Kept | Public benchmarks |
| A public benchmark: header, Test a model on it, lock card | A public benchmark | A public benchmark, unchanged | Kept | A public benchmark |
| A public benchmark: the four parts | A public benchmark | A public benchmark, unchanged | Kept | A public benchmark |
| A public benchmark: facts strip and hovers | A public benchmark | A public benchmark, unchanged | Kept | A public benchmark |
| A public benchmark: how one question is scored | A public benchmark | A public benchmark, unchanged | Kept | A public benchmark |
| A public benchmark: on this Mac so far, Why | A public benchmark | A public benchmark, unchanged | Kept | A public benchmark |
| A public benchmark: teaches, watch out | A public benchmark | A public benchmark, unchanged | Kept | A public benchmark |
| A public benchmark: needs, cost, paper | A public benchmark | A public benchmark, unchanged | Kept | A public benchmark |
| A public benchmark: tasks list and people baseline | A public benchmark | A public benchmark, unchanged | Kept | A public benchmark |
| A public benchmark: own set version | A public benchmark | A public benchmark, unchanged | Kept | A public benchmark |
| A public benchmark: your runs | A public benchmark | A public benchmark, unchanged | Kept | A public benchmark |
| A public benchmark: engine calls | A public benchmark | Unchanged | Kept | A public benchmark |
| Questions: header, meta, source, lock | A public benchmark › Questions | A public benchmark, unchanged | Kept | A public benchmark |
| Questions: confirm download | A public benchmark › Questions | A public benchmark, unchanged | Kept | A public benchmark |
| Questions: gated card | A public benchmark › Questions | A public benchmark, unchanged | Kept | A public benchmark |
| Questions: downloading and failed | A public benchmark › Questions | A public benchmark, unchanged | Kept | A public benchmark |
| Questions: filter chips | A public benchmark › Questions | A public benchmark, unchanged | Kept | A public benchmark |
| Questions: R for 10 at random, ↑ ↓, pages | A public benchmark › Questions | A public benchmark, unchanged | Kept | A public benchmark |
| Questions: dot rows | A public benchmark › Questions | A public benchmark, unchanged | Kept | A public benchmark |
| Questions: legend and seed | A public benchmark › Questions | A public benchmark, unchanged | Kept | A public benchmark |
| Questions: question detail | A public benchmark › Questions | A public benchmark, unchanged | Kept | A public benchmark |
| Questions: what the model sees, how it's marked, runs that answered it | A public benchmark › Questions | A public benchmark, unchanged | Kept | A public benchmark |
| Questions: Add to an eval set, Run just this one | A public benchmark › Questions | A public benchmark, unchanged | Kept | A public benchmark |
| Questions: engine items and item | A public benchmark › Questions | Unchanged | Kept | A public benchmark |
| Published scores: Check now | A public benchmark › Published scores | A public benchmark, unchanged | Kept | A public benchmark |
| Published scores: table with Agent rows | A public benchmark › Published scores | A public benchmark, unchanged | Kept | A public benchmark |
| Published scores: failed, empty and weekly states | A public benchmark › Published scores | A public benchmark, unchanged | Kept | A public benchmark |
| Published scores: engine scores | A public benchmark › Published scores | Unchanged | Kept | A public benchmark |
| Set up a test: header, subtitle, Close | Set up a test | Set up a test, unchanged | Kept | Set up a test |
| Set up a test: what pre-fills it | Set up a test | Set up a test, unchanged | Kept | Set up a test |
| Set up a test: a valid default (never Start 0 tests) | Set up a test | Set up a test, unchanged | Kept | Set up a test |
| Set up a test: how one test works strip | Set up a test | Set up a test, unchanged | Kept | Set up a test |
| Set up a test: our sets | Set up a test | Set up a test, unchanged | Kept | Set up a test |
| Set up a test: graders as tasks | Set up a test | Set up a test, unchanged | Kept | Set up a test |
| Set up a test: public benchmarks and + a public benchmark | Set up a test | Set up a test, unchanged | Kept | Set up a test |
| Set up a test: layer switch (three layers) | Set up a test | Set up a test › 2: One-shot · Agent (an agent is picked with its model) | Moved | Set up a test |
| Set up a test: model rows and no-key hints | Set up a test | Set up a test, unchanged | Kept | Set up a test |
| Set up a test: + any model id | Set up a test | Set up a test, unchanged | Kept | Set up a test |
| Set up a test: seat agent rows, model menu, seat % | Set up a test | Set up a test, unchanged | Kept | Set up a test |
| Set up a test: + an agent with another model | Set up a test | Set up a test, unchanged | Kept | Set up a test |
| Set up a test: + an agent on an API key | Set up a test | Set up a test, unchanged | Kept | Set up a test |
| Set up a test: full setup rows, rules on | Set up a test | Set up a test › Agent: Rules: with our rules (the default) | Kept | Set up a test |
| Set up a test: rules off (clean) | Set up a test | Set up a test › Agent: Rules: clean | Kept | Set up a test |
| Set up a test: rules files line @ hash | Set up a test | Set up a test, unchanged | Kept | Set up a test |
| Set up a test: seats answer our own tasks only | Set up a test | Set up a test, unchanged | Kept | Set up a test |
| Set up a test: agents not ready yet | Set up a test | Set up a test, unchanged | Kept | Set up a test |
| Set up a test: how many fields | Set up a test | Set up a test, unchanged | Kept | Set up a test |
| Set up a test: where its code runs and set-up hints | Set up a test | Set up a test, unchanged | Kept | Set up a test |
| Set up a test: cloud sandbox price note | Set up a test | Set up a test, unchanged | Kept | Set up a test |
| Set up a test: Advanced › task arguments | Set up a test | Set up a test, unchanged | Kept | Set up a test |
| Set up a test: what this test can tell you | Set up a test | Set up a test, unchanged | Kept | Set up a test |
| Set up a test: seats ignore temperature and seed | Set up a test | Set up a test, unchanged | Kept | Set up a test |
| Set up a test: cost lines and seat share | Set up a test | Set up a test, unchanged | Kept | Set up a test |
| Set up a test: API cost and the cap ×1.5 | Set up a test | Set up a test, unchanged | Kept | Set up a test |
| Set up a test: recorded with each result | Set up a test | Set up a test, unchanged | Kept | Set up a test |
| Set up a test: repeat rules note | Set up a test | Set up a test, unchanged | Kept | Set up a test |
| Set up a test: seat use unknown warning | Set up a test | Set up a test, unchanged | Kept | Set up a test |
| Set up a test: not-recorded note on Test again | Set up a test | Set up a test, unchanged | Kept | Set up a test |
| Set up a test: Start N and the reasons it is off | Set up a test | Set up a test, unchanged | Kept | Set up a test |
| Set up a test: two at a time, worktree, Codex note | Set up a test | Set up a test, unchanged | Kept | Set up a test |
| Set up a test: ↩ starts, Esc closes | Set up a test | Set up a test, unchanged | Kept | Set up a test |
| Set up a test: engine calls | Set up a test | Unchanged | Kept | Set up a test |
| Running and recent: list and empty state | Set up a test | Set up a test, unchanged | Kept | Set up a test |
| Running and recent: rows, status, progress | Set up a test | Set up a test, unchanged | Kept | Set up a test |
| Running and recent: Run anyway · Cancel · Resume · Results | Set up a test | Set up a test, unchanged | Kept | Set up a test |
| Running and recent: 8 recent and Show all | Set up a test | Set up a test, unchanged | Kept | Set up a test |
| Running and recent: why a test expired | Set up a test | Set up a test, unchanged | Kept | Set up a test |
| Lessons: header, subtitle, Close | Lessons | Lessons, unchanged | Kept | Lessons |
| Lessons: Lessons · How to · Where everything went | Lessons | Lessons, all three parts kept | Kept | Lessons |
| Lessons: lessons in six groups, with marks | Lessons | Lessons: 18 lessons in six groups (16 + 2 new) | Kept | Lessons |
| Lessons: lesson text | Lessons | Lessons, unchanged | Kept | Lessons |
| Lessons: Try it | Lessons | Lessons, unchanged | Kept | Lessons |
| Lessons: in your tests | Lessons | Lessons, unchanged | Kept | Lessons |
| Lessons: your first test, free | Lessons | Lessons, unchanged | Kept | Lessons |
| Lessons: where this shows up, Next | Lessons | Lessons, unchanged; links can open the 2.0.5 pages | Kept | Lessons |
| Lessons: done when read, saved | Lessons | Lessons, unchanged | Kept | Lessons |
| Lessons: falls back to the 1.9.37 Learn | Lessons | Lessons, unchanged | Kept | Lessons |
| How to: header | Lessons › How to | Lessons › How to, unchanged | Kept | Lessons |
| How to: narration Play, or narration coming | Lessons › How to | Lessons › How to, unchanged | Kept | Lessons |
| How to: N of 8 read, Start over | Lessons › How to | Lessons › How to, unchanged | Kept | Lessons |
| How to: AI voice note | Lessons › How to | Lessons › How to, unchanged | Kept | Lessons |
| How to: the 8 scenes | Lessons › How to | Lessons › How to, unchanged | Kept | Lessons |
| How to: per scene Open, Play, Mark as read | Lessons › How to | Lessons › How to, unchanged | Kept | Lessons |
| How to: read state saved | Lessons › How to | Lessons › How to, unchanged | Kept | Lessons |
| Where everything went: intro | Lessons › Where everything went | Lessons › Where everything went: now 2.0.4 → 2.0.5 first | Kept | Lessons |
| Where everything went: status filter | Lessons › Where everything went | Lessons › Where everything went, unchanged | Kept | Lessons |
| Where everything went: map table with links | Lessons › Where everything went | Lessons › Where everything went: each row has an Open button | Kept | Lessons |
| Where everything went: the docs page and its unit test | Lessons › Where everything went | docs/evals-v3-coverage.md (this page) and its unit test; the 2.0.4 page is kept as it was | Kept | Lessons |
| Hover card and Lesson › | every page | Every number, every page, unchanged | Kept | every page |
| Right-click Explain and Open the lesson | every page | Unchanged | Kept | every page |
| Hover kinds and their lessons | every page | Unchanged | Kept | Lessons |
| Lesson hints on git numbers | Real history | Agent jobs › Real history, unchanged | Kept | Real history |
| Hover inside sheets | every page | Unchanged | Kept | every page |
| Engine: setup, doctor | engine | Unchanged | Kept | no screen |
| Engine: catalog | engine | Unchanged | Kept | no screen |
| Engine: status, results | engine | Unchanged | Kept | no screen |
| Engine: estimate, power, run | engine | Unchanged | Kept | no screen |
| Engine: cancel, run-anyway, resume | engine | Unchanged | Kept | no screen |
| Engine: samples, sample | engine | Unchanged | Kept | no screen |
| Engine: export | engine | Unchanged | Kept | no screen |
| Engine: overview | engine | Still read by the launch view | Kept | Evals (launch view) |
| Engine: leaderboard by setup | engine | Unchanged | Kept | no screen |
| Engine: compare | engine | Unchanged | Kept | no screen |
| Engine: changes | engine | Unchanged | Kept | no screen |
| Engine: xray | engine | Unchanged, plus --commits (fixup, churn or revert) --agent NAME | Kept | no screen |
| Engine: evalset | engine | Unchanged | Kept | no screen |
| Engine: judge | engine | Unchanged | Kept | no screen |
| Engine: anatomy, items, item, item-results | engine | Unchanged | Kept | no screen |
| Engine: scores show and refresh | engine | Unchanged | Kept | no screen |
| Engine: history | engine | Unchanged | Kept | no screen |
| Engine: providers, prices, index, lmeval | engine | Unchanged | Kept | no screen |
| Two kinds of job: one-shot and agent | new in 2.0.5 | Evals (launch view): one bar per kind; every task and loop is sorted by kind | New | Evals (launch view) |
| Evidence bars: public tests · ours · loop runs (amber · blue · light blue) | new in 2.0.5 | Evals (launch view); widths from real counts, the hover gives them | New | Evals (launch view) |
| Segment pages: One-shot jobs › Public tests · Our tests · Loop runs; Agent jobs › Our tests · Our loop runs | new in 2.0.5 | One page per bar segment, each with its question and answer | New | One-shot jobs › Public tests |
| Loop runs: runs, failed and dry per loop, good run: not recorded | new in 2.0.5 | One-shot jobs › Loop runs and Agent jobs › Our loop runs; each row opens the loop in Loops | New | One-shot jobs › Loop runs |
| What a good run is, by loop kind | new in 2.0.5 | Each loop's row on the Loop runs pages | New | Agent jobs › Our loop runs |
| Loops with no model, on a line of their own | new in 2.0.5 | Evals (launch view): N loops use no model, so Evals doesn't judge them (opens Loops) | New | Evals (launch view) |
| Public agent benchmarks, outside the agent bar | new in 2.0.5 | The button under the agent bar: out of the box, never our setup | New | Agent jobs › Public agent benchmarks |
| Three answer buttons on the launch view | new in 2.0.5 | Did my last change help? · What does git say about our real work? · Every result, one grid | New | Evals (launch view) |
| Breadcrumb | new in 2.0.5 | The header on every page: ‹ Evals › job › source (› item) | New | every page |
| Keys ⌃⌥0–8 | new in 2.0.5 | ⌃⌥0 the launch view · ⌃⌥1–5 the five segment pages · ⌃⌥6 Public agent benchmarks · ⌃⌥7 Changes · ⌃⌥8 Real history | New | Evals (launch view) |
| Tested as chips: model · agent clean · agent with our rules | new in 2.0.5 | Our tasks, Our tests rows, the stamp | New | Our tasks |
| Real history: the commits behind a count | new in 2.0.5 | Real history: See the N commits under followed by a fix, rewritten and reverted (and the bar's fix part): each commit with the later commit that fixed, rewrote or reverted it | New | Real history |
| All results: Kind column (one-shot · agent · public model · public agent) | new in 2.0.5 | All results | New | All results |
| Lesson: One-shot jobs and agent jobs | new in 2.0.5 | Lessons › Agents vs models | New | Lessons |
| Lesson: Loop runs as evidence | new in 2.0.5 | Lessons › Our own tasks | New | Lessons |

## 2.0.3 → 2.0.4

The rows of the 2.0.4 map, unchanged; the last column is where each one opens in 2.0.5.

| 2.0.3 feature | Was in | Now in 2.0.4 | Status | Opens in 2.0.5 |
|---|---|---|---|---|
| How to: 8 scenes, narration, read marks | How to tab | Lessons › How to; Overview's layer picture | Merged | Lessons |
| Overview scorecards per eval | Overview | Compare per task + All results | Merged | One-shot jobs › Our tests |
| Hover card on every number + Lesson › | every tab | Every number, every screen | Kept | every page |
| Overview: what changed since last time | Overview | Changes | Kept | Changes |
| Overview: running now | Overview | Set up a test › Running and recent (Running · N in the header) | Moved | Set up a test |
| Overview: one suggested next eval | Overview | Overview: "To answer it properly" on each question | Kept | Evals (launch view) |
| Setup card: install engine with uv, uv/Docker status | every tab | Shown instead of the tabs until the engine is ready | Kept | every page |
| Busy and error lines | every tab | Under the header | Kept | every page |
| Subtitle counts | header | Overview subtitle + coverage | Kept | Evals (launch view) |
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
| Results: By eval leaderboard, version switch | Results | Compare (per task); versions in One task | Merged | One-shot jobs › Our tests |
| Results: Compare A vs B, paired verdict, see the N cases | Results | Compare headline + Compare with… | Kept | One-shot jobs › Our tests |
| Results: Over time, possible drop, re-run ×3 | Results | Changes | Kept | Changes |
| Results: All × all + every run | Results | All results | Kept | All results |
| Results: X-ray | Results | Real history | Moved | Real history |
| Results: Export CSV · JSON | Results | All results | Kept | All results |
| Run detail: facts, score strip, answers list, filters, sort | Run detail | One test, bug by bug | Kept | One test |
| Run detail: code check · judge · you, add to regression set, compare with, run again | Run detail | One test, bug by bug | Kept | One test |
| Learn: 16 lessons, Try it, In your runs, first eval steps, where this shows up | Learn tab | Lessons (In your tests, Your first test) | Kept | Lessons |
| Keys, Hugging Face sign-in, providers | Settings › Evals | Settings › Evals (unchanged) | Kept | every page |
| Second Draft banner on drill-downs | drill-downs | One Draft tag by the title | Removed | every page |
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
| Verdicts by rule (paired 95 % range, no winner under 10 shared bugs, blind guess) | new in 2.0.4 | Compare, One task, Overview | New | One-shot jobs › Our tests |
| What a test can tell you before what it costs (power) | new in 2.0.4 | Set up a test › 3 How many; One task › Next version | New | Set up a test |
| Plain task names and the blind guess | new in 2.0.4 | Our tasks, One task, Compare | New | Our tasks |
| Public benchmarks framed by purpose | new in 2.0.4 | Public benchmarks › three purpose cards | New | Public benchmarks |
| Where everything went (this map) | new in 2.0.4 | Lessons › Where everything went; docs/evals-v2-coverage.md | New | Lessons |

## Self-test names

`ONEROOF_SELFTEST_EVALS_TAB` takes one name per 2.0.5 screen: `launch`, `oneshot-public`, `oneshot-ours`, `oneshot-loops`, `agent-ours`, `agent-loops`, `agent-public`, `changes`, `real-history`, `one-test`, `all-results`, `our-tasks`, `one-task`, `grader`, `benchmarks`, `one-benchmark`, `setup`, `lessons`. Every other `ONEROOF_SELFTEST_EVALS_*` variable keeps working; `ONEROOF_SELFTEST_EVALS_COMPARE_VIEW=grid` opens the Agent × model grid on Agent jobs › Our tests.

Every older name still opens a screen:

| Name | Opens in 2.0.5 | Name from |
|---|---|---|
| `overview` | launch | 2.0.4 |
| `compare` | oneshot-ours | 2.0.4 |
| `one-test` | one-test | 2.0.4 |
| `all-results` | all-results | 2.0.4 |
| `changes` | changes | 2.0.4 |
| `real-history` | real-history | 2.0.4 |
| `our-tasks` | our-tasks | 2.0.4 |
| `one-task` | one-task | 2.0.4 |
| `grader` | grader | 2.0.4 |
| `benchmarks` | benchmarks | 2.0.4 |
| `one-benchmark` | one-benchmark | 2.0.4 |
| `setup` | setup | 2.0.4 |
| `lessons` | lessons | 2.0.4 |
| `realhistory` | real-history | 2.0.4 |
| `history` | real-history | 2.0.4 |
| `ourtasks` | our-tasks | 2.0.4 |
| `tasks` | our-tasks | 2.0.4 |
| `allresults` | all-results | 2.0.4 |
| `onetest` | one-test | 2.0.4 |
| `test` | one-test | 2.0.4 |
| `onetask` | one-task | 2.0.4 |
| `task` | one-task | 2.0.4 |
| `onebenchmark` | one-benchmark | 2.0.4 |
| `benchmark` | one-benchmark | 2.0.4 |
| `public-benchmarks` | oneshot-public | 2.0.4 |
| `set-up` | setup | 2.0.4 |
| `setup-sheet` | setup | 2.0.4 |
| `new-test` | setup | 2.0.4 |
| `home` | launch | 2.0.5 alias |
| `evals` | launch | 2.0.5 alias |
| `public-agent` | agent-public | 2.0.5 alias |
| `agent-benchmarks` | agent-public | 2.0.5 alias |
| `how-to` | lessons (How to) | 2.0.3 / 1.9.37 |
| `howto` | lessons (How to) | 2.0.3 / 1.9.37 |
| `your-evals` | our-tasks | 2.0.3 / 1.9.37 |
| `yourevals` | our-tasks | 2.0.3 / 1.9.37 |
| `build` | our-tasks | 2.0.3 / 1.9.37 |
| `judge` | grader | 2.0.3 / 1.9.37 |
| `explore` | benchmarks | 2.0.3 / 1.9.37 |
| `catalog` | benchmarks | 2.0.3 / 1.9.37 |
| `question` | one-benchmark (Questions) | 2.0.3 / 1.9.37 |
| `questions` | one-benchmark (Questions) | 2.0.3 / 1.9.37 |
| `scores` | one-benchmark (Published scores) | 2.0.3 / 1.9.37 |
| `your-runs` | one-benchmark (Your runs) | 2.0.3 / 1.9.37 |
| `run` | setup | 2.0.3 / 1.9.37 |
| `runs` | setup | 2.0.3 / 1.9.37 |
| `sheet` | setup (pre-filled) | 2.0.3 / 1.9.37 |
| `results` | oneshot-ours | 2.0.3 / 1.9.37 |
| `run-detail` | one-test | 2.0.3 / 1.9.37 |
| `one-run` | one-test | 2.0.3 / 1.9.37 |
| `all-by-all` | all-results | 2.0.3 / 1.9.37 |
| `allbyall` | all-results | 2.0.3 / 1.9.37 |
| `matrix` | all-results | 2.0.3 / 1.9.37 |
| `xray` | real-history | 2.0.3 / 1.9.37 |
| `x-ray` | real-history | 2.0.3 / 1.9.37 |
| `learn` | lessons | 2.0.3 / 1.9.37 |

Not a coverage row: the 2.0.5 Keychain fix (fewer password prompts) changes no Evals screen.
