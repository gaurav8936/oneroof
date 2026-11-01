import XCTest
@testable import OneRoofCore

/// LAB-2061 · the Evals redesign's pure logic (stage 1: shell, Overview, Explore, Questions, Your evals, Judge), fed with
/// JSON shaped exactly as the engine prints it (snake_case, captured from a real-profile copy and trimmed).
final class EvalsRedesignTests: XCTestCase {
    private func snake<T: Decodable>(_ t: T.Type, _ json: String) throws -> T {
        let d = JSONDecoder(); d.keyDecodingStrategy = .convertFromSnakeCase
        return try d.decode(T.self, from: Data(json.utf8))
    }

    // MARK: Shell (LAB-2061)

    func test_LAB2061_tabs_in_the_owners_order_with_overview_first() {
        XCTAssertEqual(EvalsTabV2.allCases.map(\.title), ["How to", "Overview", "Your evals", "Explore", "Run", "Results", "Learn"])   // LAB-2113
        XCTAssertEqual(EvalsTabV2.allCases.first, .howTo)
        XCTAssertEqual(EvalsTabV2.allCases.map(\.keyDigit), ["1", "2", "3", "4", "5", "6", "7"])   // ⌃⌥1…⌃⌥7
    }

    func test_LAB2061_selftest_values_reach_every_tab_and_drill_down() {
        XCTAssertEqual(EvalsTabV2.selfTest("overview")?.tab, .overview)
        XCTAssertEqual(EvalsTabV2.selfTest("your-evals")?.tab, .yourEvals)
        XCTAssertEqual(EvalsTabV2.selfTest("build")?.tab, .yourEvals)          // HP's name still works
        XCTAssertEqual(EvalsTabV2.selfTest("judge")?.drill, "judge")
        XCTAssertEqual(EvalsTabV2.selfTest("question")?.drill, "questions")
        XCTAssertEqual(EvalsTabV2.selfTest("scores")?.drill, "scores")
        XCTAssertEqual(EvalsTabV2.selfTest("catalog")?.tab, .explore)          // 1.9.37's values keep working
        XCTAssertEqual(EvalsTabV2.selfTest("runs")?.tab, .run)
        XCTAssertEqual(EvalsTabV2.selfTest("sheet")?.drill, "sheet")
        XCTAssertNil(EvalsTabV2.selfTest("nope"))
    }

    func test_LAB2061_subtitle_from_real_counts() {
        XCTAssertEqual(EvalsSubtitle.text(benchmarks: 129, ownEvals: 2, judges: 1, finished: 32, running: 0),
                       "129 benchmarks · 2 of your evals · 1 judge · 32 finished runs")
        XCTAssertEqual(EvalsSubtitle.text(benchmarks: nil, ownEvals: 0, judges: 2, finished: 1, running: 3),
                       "0 of your evals · 2 judges · 1 finished run · 3 running")
    }

    // MARK: Overview (LAB-2062)

    private let overviewJSON = """
    {"evals": [{"key": "oneroof@v1", "set": "oneroof", "version": 1, "kind": "fix-locator", "title": "oneroof · fix locator v1",
       "cases": 20, "checked_by": "code", "task_file": "/x/sets/oneroof/v1/own_oneroof_v1.py", "floor": {"right": 8, "of": 20},
       "rows": [
        {"contestant": "claude-haiku-5-5", "kind": "model", "agent": null, "model": "anthropic/claude-haiku-5-5", "run": "r2",
         "score": 0.8, "metric": "accuracy", "ci95": [0.584, 0.919], "ci_method": "wilson", "n": 20, "epochs": null, "cost": 0.0123,
         "free": false, "seat": false, "usd_per_right": 0.00077, "date": "2026-11-01T02:13:42+00:00"},
        {"contestant": "Claude Code · claude-sonnet-5-5", "kind": "agent", "agent": "claude_code", "model": "anthropic/claude-sonnet-5-5",
         "run": "r3", "score": 0.75, "metric": "accuracy", "ci95": [0.53, 0.89], "ci_method": "wilson", "n": 20, "epochs": 1,
         "cost": null, "free": false, "seat": true, "usd_per_right": null, "date": "2026-11-01T03:00:00+00:00"},
        {"contestant": "mockllm/model", "kind": "baseline", "agent": null, "model": "mockllm/model", "run": "r1", "score": 0.0,
         "metric": "accuracy", "ci95": [0.0, 0.161], "ci_method": "wilson", "n": 20, "epochs": null, "cost": null, "free": true,
         "seat": false, "usd_per_right": null, "date": "2026-11-01T02:12:10+00:00"}]},
      {"key": "gsm8k", "task": "gsm8k", "title": "gsm8k", "cases": null, "checked_by": null, "floor": null, "rows": []}],
     "changes": [{"ci95": [-0.2042, 0.2442], "contestant": "qwen3-1.7b", "date": "2026-11-01T03:07:08+00:00", "delta": 0.02,
       "diff": 0.02, "eval": "arc_challenge", "n": 20, "paired": false, "runs": ["a", "b"],
       "text": "qwen3-1.7b +2 on arc_challenge, inside the noise.", "verdict": "noise"}],
     "running": [], "suggestion": {"rule": "judge_untrusted", "target": {"judge": "oneroof_triage", "tab": "your-evals"},
       "text": "Judge not trusted yet: label 10 answers"}, "finished_runs": 44}
    """

    func test_LAB2062_overview_decodes_and_keeps_agents_first() throws {
        let o = try snake(EvalOverview.self, overviewJSON)
        XCTAssertEqual(o.finishedRuns, 44)
        let c = o.evals[0]
        XCTAssertTrue(c.isOwn)
        XCTAssertEqual(c.header, "oneroof · fix locator v1 · 20 cases · checked by code")
        XCTAssertEqual(c.floorShare, 0.4)
        XCTAssertEqual(EvalOverview.ordered(c.rows).map(\.kind), [.agent, .model, .baseline])   // agents, models, baseline
        XCTAssertEqual(c.rows.first { $0.kind == .agent }?.costText, "seat")
        XCTAssertEqual(c.rows.first { $0.kind == .baseline }?.costText, "free")
        XCTAssertEqual(c.rows.first { $0.kind == .model }?.costText, "$0.012")
        XCTAssertFalse(o.evals[1].isOwn)
        XCTAssertTrue(o.changes[0].isNoise)
        XCTAssertEqual(o.suggestion?.target.judge, "oneroof_triage")
    }

    func test_LAB2062_empty_profile_has_no_rows() throws {
        let o = try snake(EvalOverview.self, #"{"evals": [], "changes": [], "running": [], "suggestion": {"rule": "no_set", "text": "Build your first eval from a repo's fixed bugs", "target": {"tab": "your-evals"}}, "finished_runs": 0}"#)
        XCTAssertTrue(o.evals.isEmpty)
        XCTAssertEqual(o.suggestion?.rule, "no_set")
    }

    // MARK: Explore (LAB-2063)

    private func bench(_ folder: String, category: String, starter: Bool = false, sandbox: Bool = false, graded: String? = nil,
                       tags: [String] = [], shelf: String? = nil, task: String? = nil) throws -> EvalBenchmark {
        var o: [String: Any] = ["folder": folder, "category": category, "description": "d \(folder)", "sandbox": sandbox, "tags": tags,
                                "tasks": [["name": task ?? folder, "samples": 10]],
                                "starter": starter ? [["task": task ?? folder, "teaches": "t", "rank": 1]] : []]
        if let g = graded { o["graded_by"] = g }
        if let s = shelf { o["shelf"] = s }
        return try JSONDecoder().decode(EvalBenchmark.self, from: JSONSerialization.data(withJSONObject: o))
    }

    func test_LAB2063_explore_filters_shelf_topic_gradedby_docker_and_ran() throws {
        let bs = [try bench("gsm8k", category: "Math", starter: true, graded: "code"),
                  try bench("hle", category: "Hard frontier", starter: true, graded: "judge"),
                  try bench("swe_bench", category: "Software engineering", starter: true, sandbox: true, graded: "tests", tags: ["Agent"]),
                  try bench("cyber", category: "Cybersecurity", sandbox: true, graded: "tests"),
                  try bench("aime", category: "Mathematics", graded: "code"),
                  try bench("own-oneroof", category: "Your evals", graded: "code", shelf: "own", task: "/x/own_oneroof_v1.py")]
        XCTAssertEqual(EvalExploreFilter(shelf: .start).apply(bs).map(\.id), ["gsm8k", "hle", "swe_bench"])
        XCTAssertEqual(EvalExploreFilter(shelf: .own).apply(bs).map(\.id), ["own-oneroof"])
        XCTAssertEqual(EvalExploreFilter(shelf: .agent).apply(bs).map(\.id), ["swe_bench", "cyber"])
        XCTAssertEqual(EvalExploreFilter(topic: "Math").apply(bs).map(\.id), ["gsm8k", "aime"])          // Math + Mathematics
        XCTAssertEqual(EvalExploreFilter(topic: "Code").apply(bs).map(\.id), ["swe_bench"])
        XCTAssertEqual(EvalExploreFilter(gradedBy: ["judge", "tests"]).apply(bs).map(\.id), ["hle", "swe_bench", "cyber"])
        XCTAssertEqual(EvalExploreFilter(shelf: .start, noDocker: true).apply(bs).map(\.id), ["gsm8k", "hle"])
        XCTAssertEqual(EvalExploreFilter(ranIt: true).apply(bs, ran: ["hle", "own_oneroof_v1"]).map(\.id), ["hle", "own-oneroof"])
        XCTAssertEqual(EvalExploreFilter(category: "Cybersecurity").apply(bs).map(\.id), ["cyber"])     // More topics: nothing lost
        XCTAssertEqual(EvalExploreFilter.otherCategories(bs), ["Cybersecurity"])
        XCTAssertEqual(EvalExploreFilter(search: "d hle").apply(bs).map(\.id), ["hle"])
        XCTAssertEqual(EvalExploreFilter.count(bs, shelf: .start), 3)
    }

    func test_LAB2063_anatomy_decodes_and_hides_unknown_facts() throws {
        let a = try snake(EvalAnatomy.self, """
        {"answer_format": "Short or letter", "benchmark": "hle", "category": "Hard frontier", "chance": "≈ 0 %", "gated": true,
         "graded_by": "judge", "graded_by_label": "Model judge", "headroom": {"best": 0.548, "checked": "2026-11-01",
         "contestant": "GPT 6 Astra", "level": "lots", "source_name": "Scale AI leaderboard", "text": "Lots · far from max"},
         "maker": "Center for AI Safety & Scale AI", "paper": "https://arxiv.org/abs/2501.14249", "questions": 668,
         "questions_note": "text-only", "steps": [{"title": "Prompt", "body": "b"}, {"title": "Model answers", "body": "b"},
         {"title": "Judge compares", "body": "b"}, {"title": "Two numbers", "body": "b"}], "task": "hle", "title": "Humanity's Last Exam",
         "year": 2025, "watch_out": ["The judge is a second model."], "needs": ["Hugging Face sign-in, terms accepted", "no Docker"]}
        """)
        XCTAssertEqual(a.eyebrow, "Hard frontier · Center for AI Safety & Scale AI · 2025")
        XCTAssertEqual(a.facts.map(\.label), ["Questions", "Answer", "Graded by", "Chance", "Headroom"])
        XCTAssertEqual(a.facts[0].value, "668 text-only")
        XCTAssertFalse(a.headroom?.saturated ?? true)
        let b = try snake(EvalAnatomy.self, #"{"benchmark": "x", "task": "x", "title": "X", "steps": []}"#)
        XCTAssertTrue(b.facts.isEmpty)                     // nothing known, nothing shown
        XCTAssertEqual(b.eyebrow, "")
    }

    func test_LAB2063_published_scores_decode_with_source_and_date() throws {
        let s = try snake(EvalPublishedScores.self, """
        {"benchmark": "swe_bench", "has_source": true, "source": {"name": "SWE-bench leaderboard (official)", "url": "https://x"},
         "rows": [{"checked": "2026-11-01", "contestant": "Model only", "kind": "model", "score": 0.81, "source_name": "S", "source_url": "https://x", "stale": false},
                  {"checked": "2026-11-01", "contestant": "Agent + model", "kind": "agent", "score": 0.79, "published": "2025-12-05",
                   "source_name": "S", "source_url": "https://x", "stale": true}],
         "checked": "2026-11-01T10:02:03Z", "failed": {"date": "2026-11-08", "reason": "offline"}}
        """)
        XCTAssertEqual(s.ordered.map(\.contestant), ["Agent + model", "Model only"])   // agents first
        XCTAssertEqual(s.ordered.first?.stale, true)
        XCTAssertEqual(s.failed?.reason, "offline")
        let none = try snake(EvalPublishedScores.self, #"{"benchmark": "niah", "has_source": false, "source": null, "rows": [], "checked": null, "failed": null}"#)
        XCTAssertFalse(none.hasSource)
        XCTAssertTrue(none.rows.isEmpty)
    }

    func test_LAB2063_range_warning_matches_the_wilson_range() {
        XCTAssertEqual(EvalRangeWarning.text([(score: 1.0, n: 2), (score: 0.0, n: 2)]),
                       "Both runs used 2 questions. 100 % on 2 still allows anything from 34 % to 100 %.")
        XCTAssertNil(EvalRangeWarning.text([(score: 0.8, n: 100)]))
        XCTAssertEqual(EvalRangeWarning.text([(score: 0.8, n: 100), (score: 0.5, n: 10)]),
                       "A run used 10 questions. 50 % on 10 still allows anything from 24 % to 76 %.")
    }

    // MARK: Questions (LAB-2064)

    func test_LAB2064_items_page_or_what_is_needed_first() throws {
        let p = try snake(EvalItemsPage.self, """
        {"counts": {"all": 1319, "seen": 50, "wrong": 3}, "filter": "all", "offset": 0, "seed": 17, "shown": 1319, "task": "gsm8k",
         "total": 1319, "runs": [{"id": "r1", "contestant": "claude-haiku-5-5"}],
         "items": [{"id": "gsm8k_4b7e54d8", "index": 1, "input": "Janet’s ducks lay 16 eggs per day.", "target": "18",
                    "solution": "16 - 3 - 4 = 9", "choices": null, "image": false, "dots": [{"run": "r1", "score": 1.0}, {"run": "r2", "score": 0.0}]}]}
        """)
        XCTAssertTrue(p.isPage)
        XCTAssertEqual(p.items?.first?.dots.count, 2)
        XCTAssertEqual(p.counts?.wrong, 3)
        let need = try snake(EvalItemsPage.self, #"{"already_on_mac": false, "dataset": "openai/gsm8k", "gated": false, "needs_download": true, "size_bytes": 4200000, "task": "gsm8k", "terms_url": "https://huggingface.co/datasets/openai/gsm8k"}"#)
        XCTAssertFalse(need.isPage)
        XCTAssertTrue(need.confirmLine.hasPrefix("Download the questions of openai/gsm8k ("))
        XCTAssertTrue(need.confirmLine.hasSuffix(") to this Mac?"))
        let gated = try snake(EvalItemsPage.self, #"{"gated": true, "dataset": "cais/hle", "terms_url": "https://huggingface.co/datasets/cais/hle", "task": "hle"}"#)
        XCTAssertFalse(gated.isPage)
        XCTAssertEqual(gated.gated, true)
    }

    func test_LAB2064_question_detail_decodes() throws {
        let d = try snake(EvalItemDetail.self, """
        {"choices": null, "dataset": "openai/gsm8k", "id": "gsm8k_96805fca", "image": false, "index": 16, "input": "A merchant…",
         "lesson": "A right answer in the wrong format is wrong here.", "marking": [{"scorer": "code", "text": "Code reads the number after ANSWER: and compares it with 125."}],
         "no_reference": false, "prompt": {"few_shot": 10, "messages": [{"role": "system", "text": "examples"}, {"role": "user", "text": "Solve…"}],
         "source": "as sent in run r1"}, "runs": [{"answer": "125", "answer_tail": "ANSWER: 125", "contestant": "claude-haiku-5-5", "epoch": 1,
         "explanation": "x", "kind": "model", "model": "anthropic/claude-haiku-5-5", "run": "r1", "score": 1.0}],
         "solution": "5000*2.5/100", "split": "test", "target": "125", "task": "gsm8k"}
        """)
        XCTAssertEqual(d.locator, "gsm8k · test · #16")
        XCTAssertEqual(d.prompt?.fewShot, 10)
        XCTAssertTrue(d.runs[0].right)
        XCTAssertEqual(d.marking.first?.scorer, "code")
    }

    // MARK: Your evals (LAB-2065)

    private let setJSON = """
    {"name": "oneroof", "version": 1, "task": "own_oneroof_v1", "kind": "fix-locator", "repo": "oneroof", "built": "2026-11-01T02:11:59Z",
     "days": 120, "count": 3, "stats": {"commits_considered": 47, "left_out_leak": 12}, "task_file": "/x/own_oneroof_v1.py",
     "cases": [
      {"id": "A-1", "issue": "LAB-1942", "report": "Loop definitions are git-ignored", "files": ["a.swift"], "date": "2026-10-31", "solved_by": {"right": 2, "runs": 2}},
      {"id": "A-2", "issue": "LAB-1829", "report": "Rail can't be dragged closed", "files": ["b.swift"], "date": "2026-10-30", "solved_by": {"right": 0, "runs": 2}},
      {"id": "A-3", "issue": "LAB-1828", "report": "Focus steps", "files": ["c.swift"], "date": "2026-11-01", "solved_by": {"right": 1, "runs": 2}}],
     "runs": 2, "best": {"score": 0.8, "contestant": "claude-haiku-5-5", "run": "r", "n": 20}, "floor": {"right": 8, "of": 20},
     "description": "The agent gets a real bug report…", "repo_path": "/x/oneroof", "frozen": "2026-11-01", "versions": [1]}
    """

    func test_LAB2065_cases_sorted_hardest_first_with_who_solved_them() throws {
        let s = try snake(EvalSetDetail.self, setJSON)
        XCTAssertEqual(s.sorted(.hardest).map(\.id), ["A-2", "A-3", "A-1"])
        XCTAssertEqual(s.sorted(.newest).map(\.id), ["A-3", "A-1", "A-2"])
        XCTAssertEqual(s.cases.map { EvalSetDetail.solvedText($0.solvedBy) }, ["2 of 2", "nobody", "1 of 2"])
        XCTAssertEqual(EvalSetDetail.solvedText(.init(right: 0, runs: 0)), "not run yet")
        XCTAssertEqual(s.stats?.commitsConsidered, 47)
        XCTAssertEqual(s.kindTitle, "fix locator")
    }

    func test_LAB2065_build_preview_says_what_was_left_out() throws {
        let p = try snake(EvalBuildPreview.self, """
        {"name": "oneroof", "base_version": 1, "next_version": 2, "repo": "/x", "days": 120, "kind": "fix-locator",
         "report_source": "commit subjects", "kept": 20, "new": [{"id": "N-1", "issue": "LAB-2050", "report": "Projects page", "files": ["p.swift"], "date": "2026-11-01"}],
         "total": 21, "left_out": {"leak": 7, "not_a_fix": 23, "not_fixed": 0, "too_many_files": 106}, "considered": 51, "written": false}
        """)
        XCTAssertEqual([p.kept, p.new.count, p.total], [20, 1, 21])
        XCTAssertFalse(p.written)
        XCTAssertEqual(p.leftOutText, "Left out on purpose: 7 reports that already name the file (too easy), 106 fixes touching more than 3 source files, 23 commits that are not a fix.")
    }

    // MARK: Judge (LAB-2066)

    func test_LAB2066_label_keys_only_while_the_queue_has_focus() {
        XCTAssertEqual(EvalLabelKey.action("p", typing: false), .pass)
        XCTAssertEqual(EvalLabelKey.action("F", typing: false), .fail)
        XCTAssertEqual(EvalLabelKey.action("s", typing: false), .skip)
        XCTAssertNil(EvalLabelKey.action("p", typing: true))                    // typing the Why: letters are text
        XCTAssertEqual(EvalLabelKey.action("z", command: true, typing: true), .undo)
        XCTAssertEqual(EvalLabelKey.action("a", pairwise: true, typing: false), .a)
        XCTAssertNil(EvalLabelKey.action("p", pairwise: true, typing: false))
        XCTAssertEqual(EvalLabelKey.pass.verdict, "pass")
        XCTAssertNil(EvalLabelKey.skip.verdict)
    }

    func test_LAB2066_trust_tiles_turn_red_under_70_and_items_decode() throws {
        XCTAssertTrue(EvalJudgeTrust.weak(0.53))
        XCTAssertFalse(EvalJudgeTrust.weak(0.7))
        XCTAssertFalse(EvalJudgeTrust.weak(nil))
        let tr = try snake(EvalJudgeTrust.self, """
        {"name": "oneroof_triage", "mode": "single", "items": 40, "labelled": 0, "to_label": 40, "examples": 10, "run": "r",
         "judge_model": "openai/gpt-5-mini", "version": 1, "min_held": 10, "by_source": {"model": {"n": 30, "agreement": 0.7}},
         "reference": "model", "n": 30, "agreement": 0.7, "tpr": 0.8667, "tnr": 0.5333, "label_pass": 15, "label_fail": 15,
         "held_back_yours": 0, "judged_pass_rate": 0.575, "ready": false, "reading": "It's lenient…"}
        """)
        XCTAssertEqual(tr.verdictLine, "Not ready to stand in for you")
        XCTAssertTrue(tr.tooFew)
        XCTAssertEqual(EvalJudgeTrust.pct(tr.tnr), "53 %")
        let item = try snake(EvalJudgeItem.self, """
        {"id": "t7mw:LAB-1305-41fa382:1", "issue": "LAB-1305", "title": "Learn shows incomplete content", "report": "r", "model": "anthropic/claude-haiku-5-5",
         "run": "x", "answer": "a", "target": "a/DocumentPages.swift\\na/V2LearnCard.swift",
         "labels": {"model": {"verdict": "fail", "why": "w", "by": "anthropic/claude-sonnet-5-5"}, "code": {"verdict": "pass", "why": "w", "by": "code"}},
         "split": "unlabelled", "judge": "pass", "code": {"named": ["a/V2LearnCard.swift"], "right": 1, "of": 2, "hits": ["a/V2LearnCard.swift"]}}
        """)
        XCTAssertNil(item.mine)                                                  // a model's label is never "you"
        XCTAssertEqual(item.codeLine, "files named: 1 of 2 right · checked by code")
        XCTAssertEqual(item.changed, ["a/DocumentPages.swift", "a/V2LearnCard.swift"])
    }

    func test_LAB2066_confusion_counts_only_answers_the_judge_did_not_learn_from() throws {
        func it(_ id: String, judge: String, owner: String?, split: String = "held back") throws -> EvalJudgeItem {
            let labels = owner.map { #"{"owner": {"verdict": "\#($0)"}}"# } ?? "{}"
            return try snake(EvalJudgeItem.self, #"{"id": "\#(id)", "issue": "", "title": "", "report": "", "answer": "", "labels": \#(labels), "split": "\#(split)", "judge": "\#(judge)"}"#)
        }
        let items = [try it("1", judge: "pass", owner: "pass"), try it("2", judge: "pass", owner: "fail"),
                     try it("3", judge: "fail", owner: "fail"), try it("4", judge: "pass", owner: "fail"),
                     try it("5", judge: "fail", owner: "pass", split: "example"), try it("6", judge: "pass", owner: nil)]
        let c = EvalJudgeConfusion.from(items, source: "owner")
        XCTAssertEqual(c.n, 4)
        XCTAssertEqual(c.judgePassLabelFail, ["2", "4"])
        XCTAssertEqual(c.agreement, 0.5)
        XCTAssertEqual(c.tpr, 1.0)
        XCTAssertEqual(c.tnr ?? 0, 1.0 / 3.0, accuracy: 1e-9)
    }

    // MARK: Audit (LAB-2061): every 1.9.37 action still has a home while stage 2/3 is built

    func test_LAB2061_every_1937_action_has_an_entry_point() {
        // Stage 1 routes Run, Results and Learn to today's views, so their actions stay where they were.
        let homes: [String: EvalsTabV2] = ["catalog search": .explore, "category filter": .explore, "start here": .explore,
                                           "no docker needed": .explore, "rescan": .explore, "run sheet": .run, "cancel": .run,
                                           "resume": .run, "export csv": .results, "export json": .results, "compare": .results,
                                           "every run": .results, "run detail": .results, "first eval free": .learn, "glossary": .learn]
        for (action, tab) in homes { XCTAssertTrue(EvalsTabV2.allCases.contains(tab), action) }
        XCTAssertEqual(Set(homes.values), [.explore, .run, .results, .learn])
        XCTAssertEqual(EvalBenchmark.topics.first, "Knowledge")
    }

    func test_LAB2061_redesign_is_on_by_default_and_kept_when_saved() throws {
        XCTAssertTrue(AppSettings().evalsRedesign)
        var s = AppSettings(); s.evalsRedesign = false
        let back = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(s))
        XCTAssertFalse(back.evalsRedesign)                                      // the 1.9.37 view stays reachable
        let old = try JSONDecoder().decode(AppSettings.self, from: Data("{}".utf8))
        XCTAssertTrue(old.evalsRedesign)                                        // settings from before 2.0.0: on
    }
}
