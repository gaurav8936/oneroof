import XCTest
@testable import OneRoofCore

/// LAB-2240 · Evals v2: the second-model review's Swift-side findings (scratchpad review, findings 4–8): the one attempts
/// policy (fractional counts, part-filled squares), the before/after verdict with the real floor and each side's bounds,
/// Test again from the stamp, the grid cell carrying its model, and rules mode as a grid dimension with the latest run.
final class EvalsReviewFixesTests: XCTestCase {
    private func snake<T: Decodable>(_ t: T.Type, _ json: String) throws -> T {
        let d = JSONDecoder(); d.keyDecodingStrategy = .convertFromSnakeCase
        return try d.decode(T.self, from: Data(json.utf8))
    }
    private let ids = (1...10).map { "XYZ-\($0)-abc" }

    private func board(_ rows: [String], floor: Int? = 5) throws -> EvalSetupLeaderboard {
        let cases = ids.map { #"{"id": "\#($0)", "issue": "XYZ", "title": null}"# }.joined(separator: ",")
        let f = floor.map { #"{"right": \#($0), "of": 10, "rule": "a blind guess: the three most-fixed files"}"# } ?? "null"
        return try snake(EvalSetupLeaderboard.self, #"{"task": "own_demo", "version": 2, "title": "Find the files a bug fix needs", "n": 10, "checked_by": "code", "floor": \#(f), "cases": [\#(cases)], "rows": [\#(rows.joined(separator: ","))], "stand_in": null}"#)
    }
    private func row(_ setup: String, run: String, started: String, right: Double, layer: String, agent: String?, model: String?,
                     rules: String? = nil, status: String = "done", scores: [Double]? = nil) -> String {
        let per = (scores ?? ids.indices.map { Double($0) < right ? 1 : 0 }).enumerated().map { i, s in
            #"{"id": "\#(ids[i])", "right": \#(s >= 1), "score": \#(s)}"# }.joined(separator: ",")
        let a = agent.map { "\"\($0)\"" } ?? "null", m = model.map { "\"\($0)\"" } ?? "null", r = rules.map { "\"\($0)\"" } ?? "null"
        return #"{"setup_id": "\#(setup)", "label": "\#(setup)", "status": "\#(status)", "status_note": null, "run": "\#(run)", "started": "\#(started)", "right": \#(right), "n": 10, "lo": 0.2, "hi": 0.8, "cost": 0, "cost_per_right": null, "per_case": [\#(per)], "stamp": {"recorded": true, "layer": "\#(layer)", "agent": \#(a), "model": \#(m), "model_requested": \#(m), "runs_on": "\#(agent == nil ? "api:anthropic" : "seat:C1")", "rules": \#(r)}}"#
    }

    // MARK: 4 · one attempts policy

    func test_review4_two_attempts_one_success_each_is_half_not_ten_of_ten() throws {
        let lb = try board([row("model:claude-opus-5-5", run: "half", started: "2026-11-01T00:00:00Z", right: 5, layer: "model",
                                agent: nil, model: "claude-opus-5-5", scores: Array(repeating: 0.5, count: 10))])
        let r = lb.rows[0]
        XCTAssertEqual(r.right, 5)
        XCTAssertEqual(r.share, 0.5)
        XCTAssertEqual(r.scoreText, "5 of 10")
        let sq = EvalsASquares.ordered(cases: lb.cases, perCase: r.perCase)
        XCTAssertTrue(sq.allSatisfy(\.isPartial))                              // drawn half filled
        XCTAssertEqual(sq.map(\.right), Array(repeating: false, count: 10))
        let s = try XCTUnwrap(EvalsAOneTest.score(sq))
        XCTAssertEqual(s.right, 5, accuracy: 1e-9)
        XCTAssertEqual(s.n, 10)
        XCTAssertEqual(EvalVerdicts.Side(r).right, 5)                         // the verdict reads the same count
    }

    func test_review4_fractional_counts_and_samples_mean_over_attempts() throws {
        XCTAssertEqual(EvalScoreText.count(7.5), "7.5")
        XCTAssertEqual(EvalScoreText.count(8), "8")
        let scores: [Double] = [1, 1, 1, 1, 1, 1, 1, 0.5, 0, 0]
        let lb = try board([row("model:x", run: "m", started: "2026-11-01T00:00:00Z", right: 7.5, layer: "model", agent: nil, model: "x", scores: scores)])
        XCTAssertEqual(lb.rows[0].scoreText, "7.5 of 10")
        let sq = EvalsASquares.ordered(cases: lb.cases, perCase: lb.rows[0].perCase)
        XCTAssertEqual(sq.map(\.score), [1, 1, 1, 1, 1, 1, 1, 0.5, 0, 0])      // right, then partial, then wrong
        // samples of 2 attempts: the bug's square is the mean (the 2.0.3 first-attempt-only reading said right)
        let samples = try JSONDecoder().decode([EvalSample].self, from: Data(#"[{"id": "A-1-x", "epoch": 1, "score": 1.0}, {"id": "A-1-x", "epoch": 2, "score": 0.0}, {"id": "A-2-x", "epoch": 1, "score": 1.0}, {"id": "A-2-x", "epoch": 2, "score": 1.0}]"#.utf8))
        let fs = EvalsASquares.fromSamples(samples)
        XCTAssertEqual(fs.map(\.id), ["A-2-x", "A-1-x"])
        XCTAssertEqual(fs.map(\.score), [1, 0.5])
        XCTAssertEqual(EvalsAOneTest.score(fs)?.right, 1.5)
        // an engine before 2.0.4 sends no score: right = 1, wrong = 0
        let old = try snake(EvalSetupRow.CaseRight.self, #"{"id": "x", "right": true}"#)
        XCTAssertEqual(old.score, 1)
    }

    // MARK: 5 · Changes verdict uses the pair's floor and each side's bounds

    func test_review5_changes_verdict_says_when_after_only_matches_a_blind_guess() throws {
        func sq(_ right: Int) -> [EvalsASquare] { ids.enumerated().map { i, id in EvalsASquare(id: id, issue: id, right: i < right) } }
        let c = EvalCompareResult(diff: 0.5, ci95: [0.17, 0.83], n: 10, paired: true, verdict: "a", onlyA: Array(ids.prefix(5)), onlyB: [], tied: 5)
        let v = EvalsAChanges.verdict(before: sq(0), after: sq(5), compare: c, floor: 0.5)
        XCTAssertEqual(v.kind, .betterOnlyMatchesFloor)                        // 5/10: Wilson 24–76 % touches 50 %
        XCTAssertEqual(v.text, "After is better, but only matches a blind guess")
        XCTAssertEqual(EvalsAChanges.verdict(before: sq(0), after: sq(5), compare: c, floor: nil).kind, .better)
        XCTAssertEqual(EvalsAChanges.side("After", sq(5)).lo ?? 0, EvalStats.wilson(0.5, n: 10).lo, accuracy: 1e-9)
    }

    // MARK: Re-review (codex-rereview.md) · 3, 5, 6

    private func change(_ tested: String) throws -> EvalChange {
        try snake(EvalChange.self, #"{"at": "2026-11-04T18:22:00Z", "who": "you", "what": "CLAUDE.md changed", "path": "CLAUDE.md", "commit": "7b0b2bd", "tested": \#(tested)}"#)
    }

    func test_rereview3_a_pair_over_several_rules_commits_is_credited_to_none() throws {
        let span = try change(#"{"before": "a", "after": "b", "spans": ["1111111", "2222222"], "task": "own_x_v2", "task_version": 2}"#)
        XCTAssertTrue(span.isSpan)
        XCTAssertTrue(span.testedBoth)
        XCTAssertFalse(span.testedAlone)
        XCTAssertEqual(EvalsAChanges.status(span), "covers 2 changes together — can't tell which one")
        let alone = try change(#"{"before": "a", "after": "b", "task": "own_x_v2", "task_version": 2}"#)
        XCTAssertTrue(alone.testedAlone)
        XCTAssertEqual(EvalsAChanges.status(alone), "tested before and after")
        XCTAssertEqual(EvalsAChanges.status(try change(#"{"before": null, "after": null}"#)), "no comparable before/after tests")
        // Overview's "did my change help?" never names a span as one change's test
        let ans = EvalsAQuestions.didMyChangeHelp([], changes: [span])
        XCTAssertNotEqual(ans.headline, "Tested before and after")
        XCTAssertEqual(EvalsAQuestions.didMyChangeHelp([], changes: [span, alone]).headline, "Tested before and after")
    }

    func test_rereview5_floor_is_read_by_the_pairs_task_version_not_the_latest_board() throws {
        func sq(_ right: Int) -> [EvalsASquare] { ids.enumerated().map { i, id in EvalsASquare(id: id, issue: id, right: i < right) } }
        let c = EvalCompareResult(diff: 0.5, ci95: [0.17, 0.83], n: 10, paired: true, verdict: "a", onlyA: Array(ids.prefix(5)), onlyB: [], tied: 5)
        let ch = try change(#"{"before": "gone-1", "after": "gone-2", "task": "own_demo", "task_version": 2}"#)
        XCTAssertEqual(EvalsAChanges.floorQuery(ch), ["leaderboard", "own_demo", "--version", "2", "--by", "setup"])
        // the runs were displaced by later repeats: the version-2 board holds neither, but its floor is still the pair's
        let v2 = try board([row("claude_code:default:off", run: "newer", started: "2026-11-05T00:00:00Z", right: 5, layer: "agent_model", agent: "claude_code", model: nil, rules: "off")], floor: 5)
        XCTAssertEqual(EvalsAChanges.floor(of: ch, board: v2), .known(0.5))
        let v = EvalsAChanges.verdict(before: sq(0), after: sq(5), compare: c, floor: EvalsAChanges.floor(of: ch, board: v2))
        XCTAssertEqual(v.text, "After is better, but only matches a blind guess")
        // a newer task version's board is not the pair's: floor unknown, and a winner only with the caveat
        var v3 = try board([], floor: 2); v3.version = 3
        XCTAssertEqual(EvalsAChanges.floor(of: ch, board: v3), .unknown)
        XCTAssertEqual(EvalsAChanges.floor(of: ch, board: nil), .unknown)
        XCTAssertEqual(EvalsAChanges.floor(of: ch, board: try board([], floor: nil)), .unknown)
        let u = EvalsAChanges.verdict(before: sq(0), after: sq(5), compare: c, floor: .unknown)
        XCTAssertEqual(u.winner, "After")
        XCTAssertTrue(u.text.hasSuffix("(floor unknown — can't check it against a blind guess)"), u.text)
        XCTAssertTrue(EvalsAChanges.verdict(before: sq(0), after: sq(5), compare: c, floor: .reading).text.contains("floor unknown"))
        // a pair without a recorded task version: no query, floor unknown
        XCTAssertNil(EvalsAChanges.floorQuery(try change(#"{"before": "a", "after": "b"}"#)))
        // no winner, no caveat
        let tie = EvalCompareResult(diff: 0.1, ci95: [-0.2, 0.4], n: 10, paired: true, verdict: "noise", onlyA: [], onlyB: [], tied: 10)
        XCTAssertFalse(EvalsAChanges.verdict(before: sq(4), after: sq(5), compare: tie, floor: .unknown).text.contains("floor unknown"))
    }

    func test_rereview6_test_again_waits_for_the_stamp_and_flags_an_unreadable_one() throws {
        let r = try JSONDecoder().decode(EvalResult.self, from: Data(#"{"id": "y", "task": "own_oneroof_v1", "model": "seat/C1", "agent": "claude_code", "limit_n": 20, "metrics": []}"#.utf8))
        let st = EvalStamp(layer: .full, agent: "claude_code", model: "claude-opus-5-5", modelRequested: "claude-opus-5-5",
                           modelSource: "chosen", runsOn: "seat:C1", rules: "on", rulesHash: "a1b2c3d")
        // before the stamps are read: off (no plan), never a CLI-default / rules-off draft
        XCTAssertEqual(EvalRunPlan.againState(hasResult: true, stamp: nil, stampsRead: nil), .reading)
        XCTAssertEqual(EvalRunPlan.againState(hasResult: false, stamp: nil, stampsRead: true), .reading)
        XCTAssertNil(EvalRunPlan.again(r, stamp: nil, state: .reading))
        // read: the stamp's setup
        XCTAssertEqual(EvalRunPlan.againState(hasResult: true, stamp: st, stampsRead: nil), .ready)
        let ready = try XCTUnwrap(EvalRunPlan.again(r, stamp: st, state: .ready))
        XCTAssertEqual(EvalSetupChoice.from(ready), [.seat("claude_code", model: "claude-opus-5-5", rules: true)])
        XCTAssertFalse(ready.notRecorded)
        // read (or failed) and no stamp for this run: the agent, with model and rules flagged "pick again — not recorded"
        XCTAssertEqual(EvalRunPlan.againState(hasResult: true, stamp: nil, stampsRead: true), .unreadable)
        XCTAssertEqual(EvalRunPlan.againState(hasResult: true, stamp: nil, stampsRead: false), .unreadable)
        let u = try XCTUnwrap(EvalRunPlan.again(r, stamp: nil, state: .unreadable))
        XCTAssertTrue(u.notRecorded)
        XCTAssertEqual(u.agents, ["claude_code"])
        XCTAssertEqual(EvalSetupChoice.from(u).map(\.agent), ["claude_code"])
        XCTAssertTrue(EvalRunPlan.notRecordedNote.contains("Model: pick again — not recorded"))
        XCTAssertTrue(EvalRunPlan.notRecordedNote.contains("Rules on or off: pick again — not recorded"))
        XCTAssertEqual(EvalRunPlan.againReading, "reading the test…")
    }

    // MARK: 6 · Test again keeps the seat model and rules mode

    func test_review6_test_again_rebuilds_the_setup_from_the_stamp() throws {
        let r = try JSONDecoder().decode(EvalResult.self, from: Data(#"{"id": "y", "task": "own_oneroof_v1", "model": "seat/C1", "agent": "claude_code", "limit_n": 20, "metrics": []}"#.utf8))
        let st = EvalStamp(layer: .full, agent: "claude_code", model: "claude-opus-5-5", modelRequested: "claude-opus-5-5",
                           modelSource: "chosen", runsOn: "seat:C1", rules: "on", rulesHash: "a1b2c3d")
        let p = EvalRunPlan.again(r, stamp: st)
        XCTAssertEqual(EvalSetupChoice.from(p), [.seat("claude_code", model: "claude-opus-5-5", rules: true)])
        XCTAssertEqual(p.repeatRulesHash, "a1b2c3d")
        XCTAssertEqual(EvalSetupChoice.from(p).first?.label, "Claude Code using Opus, with our rules")
        let note = EvalSetupChoice.repeatRulesNote(old: "a1b2c3d", now: "9f8e7d6")
        XCTAssertTrue(note.contains("HEAD") && note.contains("9f8e7d6") && note.contains("a1b2c3d"), note)
        // the CLI default, rules off: no model, no rules, no note
        let off = EvalRunPlan.again(r, stamp: EvalStamp(layer: .agentModel, agent: "claude_code", model: "claude-sonnet-5-5",
                                                       modelSource: "cli_default_resolved", runsOn: "seat:C1", rules: "off"))
        XCTAssertEqual(EvalSetupChoice.from(off), [.seat("claude_code")])
        XCTAssertNil(off.repeatRulesHash)
        // without a stamp, 2.0.3's behaviour
        XCTAssertEqual(EvalSetupChoice.from(EvalRunPlan.again(r, stamp: nil)), [.seat("claude_code")])
    }

    // MARK: 7 · a grid cell carries its column's model

    func test_review7_grid_cell_carries_the_model_and_refuses_unsupported_pairs() throws {
        let lb = try board([row("model:claude-opus-5-5", run: "m", started: "2026-11-01T00:00:00Z", right: 6, layer: "model", agent: nil, model: "claude-opus-5-5")])
        let c = try XCTUnwrap(EvalsAGrid.choice(agent: "claude_code", column: "claude-opus-5-5", rules: false, lb: lb))
        XCTAssertEqual(c, .seat("claude_code", model: "claude-opus-5-5"))
        XCTAssertNil(EvalsAGrid.choice(agent: "codex_cli", column: "claude-opus-5-5", rules: false, lb: lb))   // disabled
        XCTAssertEqual(EvalsAGrid.choice(agent: "codex_cli", column: EvalsAGrid.cliDefault, rules: true, lb: lb), .seat("codex_cli", rules: true))
        XCTAssertEqual(EvalsAGrid.choice(agent: nil, column: "claude-opus-5-5", rules: false, lb: lb), .model("anthropic/claude-opus-5-5"))
        let u = EvalsAUntested(label: c.label, agent: c.agent, model: c.model, rules: c.rules)
        let p = EvalsACompare.plan([u], taskFile: "/x/own_demo_v2.py", cases: 10)
        XCTAssertEqual(EvalSetupChoice.from(p), [.seat("claude_code", model: "claude-opus-5-5")])   // never the CLI default
        XCTAssertEqual(p.models, [])                                                               // not a model-alone run too
        XCTAssertEqual(p.agents, ["claude_code"])
    }

    // MARK: 8 · rules mode is a grid dimension; latest run per cell

    func test_review8_grid_keeps_rules_apart_and_picks_the_latest_run() throws {
        let lb = try board([
            row("claude_code:claude-opus-5-5:on", run: "on", started: "2026-11-03T00:00:00Z", right: 9, layer: "full", agent: "claude_code", model: "claude-opus-5-5", rules: "on"),
            row("claude_code:claude-opus-5-5:off", run: "off-old", started: "2026-11-01T00:00:00Z", right: 8, layer: "agent_model", agent: "claude_code", model: "claude-opus-5-5", rules: "off"),
            row("claude_code:claude-opus-5-5:off", run: "off-new", started: "2026-11-02T00:00:00Z", right: 6, layer: "agent_model", agent: "claude_code", model: "claude-opus-5-5", rules: "off"),
            row("model:claude-opus-5-5", run: "model", started: "2026-11-01T00:00:00Z", right: 5, layer: "model", agent: nil, model: "claude-opus-5-5"),
        ])
        let off = EvalsAGrid.build(lb)                                       // default: rules off (clean)
        let cc = try XCTUnwrap(off.rows.first { $0.agent == "claude_code" })
        XCTAssertEqual(cc.cells["claude-opus-5-5"]?.run, "off-new")          // the latest, not the 9 with rules nor the old 8
        XCTAssertTrue(cc.sub.contains("clean (no rules)"))
        XCTAssertFalse(off.rows.contains { $0.sub.contains("layer") }, "QA #5: no layer wording")
        XCTAssertTrue(EvalsAGrid.build(lb, rules: true).rows.first { $0.agent == "claude_code" }!.sub.contains("with our rules"))
        XCTAssertEqual(off.rows.first { $0.agent == nil }?.cells["claude-opus-5-5"]?.run, "model")
        let on = EvalsAGrid.build(lb, rules: true)
        XCTAssertEqual(on.rows.first { $0.agent == "claude_code" }?.cells["claude-opus-5-5"]?.run, "on")
        XCTAssertEqual(on.rows.first { $0.agent == nil }?.cells["claude-opus-5-5"]?.run, "model")
    }

    // MARK: Independent QA (QA-REPORT.md m1, m2, m4, m9, m11, m14)

    func test_QA_m1_one_count_of_finished_tests_everywhere() throws {
        let js = #"[{"id": "a", "task": "own_oneroof_v2", "status": "done", "set_name": "oneroof", "set_version": 2, "metrics": []},"#
            + #"{"id": "b", "task": "own_oneroof_v1", "status": "done", "set_name": "oneroof", "set_version": 1, "metrics": []},"#
            + #"{"id": "c", "task": "gsm8k", "status": "done", "metrics": []}, {"id": "d", "task": "gsm8k", "status": "failed", "metrics": []},"#
            + #"{"id": "e", "task": "labeller_oneroof_triage_v1", "status": "done", "metrics": []}, {"id": "f", "task": "judge_oneroof_triage_v1", "status": "done", "metrics": []}]"#
        let rs = try JSONDecoder().decode([EvalResult].self, from: Data(js.utf8))
        let c = EvalFinished.count(rs)
        XCTAssertEqual(c.tests, 4)   // the engine's finished_runs: done, minus the labeller helper run
        XCTAssertEqual(c.tasks, 4)   // oneroof@v2, oneroof@v1, gsm8k, the grader
        XCTAssertEqual(EvalFinished.text(rs), "4 finished tests across 4 tasks")
        XCTAssertEqual(EvalFinished.text(Array(rs.prefix(1))), "1 finished test across 1 task")
        // a benchmark's badge and its "Your runs" tab: the same finished runs
        XCTAssertEqual(EvalFinished.runs(taskNames: ["gsm8k"], rs).map { $0.id }, ["c"])
    }

    func test_QA_m2_evals_menu_is_not_a_second_new() {
        XCTAssertFalse(EvalsNewMenu.title.hasPrefix("+ New"))
        XCTAssertEqual(EvalsNewMenu.items, ["New test…", "New task from fixed bugs…", "New grader…"])   // nothing lost
        XCTAssertEqual(EvalsNewMenu.path("New grader"), "New test or task ▾ › New grader")
    }

    func test_QA_m4_setup_sheet_defaults_to_a_valid_setup() {
        let pub = EvalSetupChoice.defaults(task: "gsm8k", seatAgents: ["claude_code"])
        XCTAssertEqual(pub.layer, .model)                                    // seats answer our own tasks only
        XCTAssertEqual(pub.choices, [.model("mockllm/model")])
        let own = EvalSetupChoice.defaults(task: "/e/sets/oneroof/v2/own_oneroof_v2.py", seatAgents: ["claude_code", "codex_cli"])
        XCTAssertEqual(own.layer, .agentModel)
        XCTAssertEqual(own.choices, [.seat("claude_code")])
        XCTAssertEqual(EvalSetupChoice.defaults(task: "/e/sets/oneroof/v2/own_oneroof_v2.py", seatAgents: []).choices, [.model("mockllm/model")])
        XCTAssertEqual(EvalSetupChoice.defaults(task: nil, seatAgents: []).choices.count, 1)   // never "Start 0 tests"
    }

    func test_QA_m9_untagged_history_states_facts_not_a_guess() {
        XCTAssertFalse(EvalsAHistory.untaggedLine.contains("Probably"))
        XCTAssertTrue(EvalsAHistory.untaggedLine.contains("LAB-2241"))
        XCTAssertTrue(EvalsAHistory.untaggedLine.hasPrefix("Commits with no agent name"))
    }

    func test_QA_m11_implausible_per_answer_input_tokens_are_hidden() {
        XCTAssertEqual(EvalSampleTokens.text(input: 4, output: 40), "40 tokens out")
        XCTAssertEqual(EvalSampleTokens.text(input: 60_284, output: 40), "60,284 tokens in, 40 out")
        XCTAssertNil(EvalSampleTokens.text(input: nil, output: nil))
        XCTAssertNil(EvalSampleTokens.text(input: 3, output: nil))
    }

    func test_QA_m14_hover_lines_for_our_tasks_and_benchmarks() {
        XCTAssertTrue(EvalHover.questions(1_319).hasPrefix("1,319 questions in this benchmark"))
        XCTAssertEqual(EvalHover.lesson(.n), "range")
        XCTAssertEqual(EvalHover.lesson(.agreement), "labels")
    }
}
