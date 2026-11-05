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
        // the floor is the pair's own task version's
        let v2 = try board([row("claude_code:default:off", run: "after", started: "2026-11-02T00:00:00Z", right: 5, layer: "agent_model", agent: "claude_code", model: nil, rules: "off")], floor: 5)
        let v3 = try board([row("claude_code:default:off", run: "other", started: "2026-11-02T00:00:00Z", right: 5, layer: "agent_model", agent: "claude_code", model: nil, rules: "off")], floor: 2)
        XCTAssertEqual(EvalsAChanges.floor(before: "before", after: "after", boards: [v3, v2]), 0.5)
        XCTAssertNil(EvalsAChanges.floor(before: "x", after: "y", boards: [v3, v2]))
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
        XCTAssertTrue(cc.sub.contains("rules off"))
        XCTAssertEqual(off.rows.first { $0.agent == nil }?.cells["claude-opus-5-5"]?.run, "model")
        let on = EvalsAGrid.build(lb, rules: true)
        XCTAssertEqual(on.rows.first { $0.agent == "claude_code" }?.cells["claude-opus-5-5"]?.run, "on")
        XCTAssertEqual(on.rows.first { $0.agent == nil }?.cells["claude-opus-5-5"]?.run, "model")
    }
}
