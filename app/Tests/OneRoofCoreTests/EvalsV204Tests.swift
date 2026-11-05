import XCTest
@testable import OneRoofCore

/// LAB-2242 · Evals v2 (One Roof 2.0.4) shell: the six tabs, drill-downs, sheets and self-test names, the engine ↔ Swift
/// contract (the Evals v2 contract (CONTRACT.md) §1–§7, fixtures copied from it) and the verdict sentences (CONTRACT "Swift side").
final class EvalsV204Tests: XCTestCase {
    private func snake<T: Decodable>(_ t: T.Type, _ json: String) throws -> T {
        let d = JSONDecoder(); d.keyDecodingStrategy = .convertFromSnakeCase
        return try d.decode(T.self, from: Data(json.utf8))
    }

    // MARK: Navigation

    func test_LAB2242_every_screen_has_its_own_selftest_name() {
        let names = ["overview", "compare", "one-test", "all-results", "changes", "real-history", "our-tasks", "one-task", "grader",
                     "benchmarks", "one-benchmark", "setup", "lessons"]
        XCTAssertEqual(EvalsScreen.allCases.map(\.selfTestName), names)
        for s in EvalsScreen.allCases { XCTAssertEqual(EvalsScreen.selfTest(s.selfTestName), EvalsSelfTest(screen: s, part: nil), s.rawValue) }
        XCTAssertEqual(EvalsScreen.selfTest("Real-History")?.screen, .realHistory)   // case does not matter
    }

    func test_LAB2242_old_selftest_names_land_on_their_new_home() {
        let old: [String: (EvalsScreen, String?)] = [
            "how-to": (.lessons, "how-to"), "howto": (.lessons, "how-to"), "your-evals": (.ourTasks, nil), "build": (.ourTasks, nil),
            "judge": (.grader, nil), "explore": (.benchmarks, nil), "catalog": (.benchmarks, nil),
            "question": (.oneBenchmark, "questions"), "questions": (.oneBenchmark, "questions"), "scores": (.oneBenchmark, "scores"),
            "your-runs": (.oneBenchmark, "runs"), "run": (.setup, nil), "runs": (.setup, nil), "sheet": (.setup, "sheet"),
            "results": (.compare, nil), "run-detail": (.oneTest, nil), "one-run": (.oneTest, nil), "all-by-all": (.allResults, nil),
            "allbyall": (.allResults, nil), "matrix": (.allResults, nil), "xray": (.realHistory, nil), "x-ray": (.realHistory, nil),
            "learn": (.lessons, nil),
        ]
        for (name, (screen, part)) in old {
            XCTAssertEqual(EvalsScreen.selfTest(name), EvalsSelfTest(screen: screen, part: part), name)
        }
        XCTAssertNil(EvalsScreen.selfTest("nope"))
    }

    func test_LAB2242_screens_kinds_and_parents() {
        XCTAssertEqual(EvalsScreen.allCases.filter { $0.kind == .tab }.compactMap(\.tab), EvalsTabV2.allCases)
        XCTAssertEqual(EvalsScreen.allCases.filter { $0.kind == .drill }, [.oneTest, .allResults, .oneTask, .grader, .oneBenchmark])
        XCTAssertEqual(EvalsScreen.allCases.filter { $0.kind == .sheet }, [.setup, .lessons])
        XCTAssertEqual(EvalsScreen.oneTest.tab, .compare); XCTAssertEqual(EvalsScreen.allResults.tab, .compare)
        XCTAssertEqual(EvalsScreen.oneTask.tab, .ourTasks); XCTAssertEqual(EvalsScreen.grader.tab, .ourTasks)
        XCTAssertEqual(EvalsScreen.oneBenchmark.tab, .benchmarks)
        XCTAssertEqual(EvalsScreen.grader.backTitle, "Our tasks"); XCTAssertEqual(EvalsScreen.grader.title, "Check the grader")
        XCTAssertNil(EvalsScreen.compare.backTitle)
        XCTAssertNil(EvalsScreen.setup.tab); XCTAssertEqual(EvalsScreen.setup.title, "Set up a test")
        XCTAssertEqual(EvalsSelfTest(screen: .lessons, part: nil).tab, .overview)   // a sheet opens over Overview
        for tb in EvalsTabV2.allCases { XCTAssertEqual(tb.screen.tab, tb) }
    }

    func test_LAB2242_every_old_tab_has_a_new_home() {
        XCTAssertEqual(EvalsLegacyTab.allCases.map(\.home), [.lessons, .overview, .ourTasks, .benchmarks, .setup, .compare, .lessons])
    }

    // MARK: §1 Stamp

    static let stampJSON = #"""
    {"recorded": true, "layer": "agent_model", "agent": "claude_code", "agent_name": "Claude Code", "agent_version": "2.1.31",
     "model": "claude-opus-5-5", "model_requested": null, "model_source": "cli_default_resolved", "runs_on": "seat:C1",
     "rules": "off", "rules_hash": null, "rules_commit": null, "rules_files": [], "permission_mode": "read-only",
     "task": "own_oneroof", "task_version": 2, "task_commit": "f4318921ae4d", "seed": 42}
    """#

    func test_LAB2242_stamp_decodes_contract_fields() throws {
        let s = try snake(EvalStamp.self, Self.stampJSON)
        XCTAssertTrue(s.recorded)
        XCTAssertEqual(s.layer, .agentModel)
        XCTAssertEqual(s.agentName, "Claude Code"); XCTAssertEqual(s.agentVersion, "2.1.31")
        XCTAssertEqual(s.model, "claude-opus-5-5"); XCTAssertNil(s.modelRequested)
        XCTAssertEqual(s.modelSource, "cli_default_resolved"); XCTAssertEqual(s.runsOn, "seat:C1")
        XCTAssertEqual(s.rules, "off"); XCTAssertEqual(s.rulesFiles, []); XCTAssertEqual(s.permissionMode, "read-only")
        XCTAssertEqual(s.task, "own_oneroof"); XCTAssertEqual(s.taskVersion, 2); XCTAssertEqual(s.taskCommit, "f4318921ae4d"); XCTAssertEqual(s.seed, 42)
        XCTAssertEqual(s.line, "The agent using a model · claude-opus-5-5 · Claude Code 2.1.31 · rules off · v2")
        XCTAssertFalse(s.hasGaps)
    }

    func test_LAB2242_stamp_rules_on_is_the_full_setup_with_its_hash() throws {
        let s = try snake(EvalStamp.self, #"{"recorded": true, "layer": "full", "agent": "codex_cli", "agent_name": "Codex", "agent_version": "0.9.1", "model": "gpt-5", "rules": "on", "rules_hash": "a1b2c3d", "rules_commit": "7b0b2bd", "rules_files": ["CLAUDE.md", "AGENTS.md"], "task_version": 1}"#)
        XCTAssertEqual(s.effectiveLayer, .full)
        XCTAssertEqual(s.derivedLayer, .full)
        XCTAssertTrue(s.line.contains("rules on @ a1b2c3d"))
        XCTAssertEqual(s.rulesFiles, ["CLAUDE.md", "AGENTS.md"])
    }

    func test_LAB2242_old_run_stamp_is_derived_and_shows_not_recorded() throws {
        // Runs before 2.0.4: recorded false, most parts null.
        let s = try snake(EvalStamp.self, #"{"recorded": false, "layer": "agent_model", "agent": "claude_code", "agent_name": "Claude Code", "agent_version": null, "model": null, "model_requested": null, "model_source": "cli_default_unknown", "runs_on": "seat:C1", "rules": "off", "rules_hash": null, "rules_commit": null, "rules_files": null, "permission_mode": null, "task": "own_oneroof", "task_version": null, "task_commit": null, "seed": null}"#)
        XCTAssertFalse(s.recorded)
        XCTAssertTrue(s.hasGaps)
        XCTAssertEqual(s.parts.first { $0.label == "CLI version" }?.text, "not recorded")
        XCTAssertEqual(s.parts.first { $0.label == "task version" }?.text, "not recorded")
        XCTAssertEqual(s.parts.first { $0.label == "model" }?.text, "CLI default")
        // A model-layer stamp has no agent or rules parts; an empty stamp derives model and is all gaps.
        let m = try snake(EvalStamp.self, #"{"recorded": true, "layer": "model", "model": "claude-opus-5-5", "model_source": "api", "runs_on": "api:anthropic", "rules": null, "task_version": 2}"#)
        XCTAssertEqual(m.parts.map(\.label), ["layer", "model", "task version"])
        let empty = try snake(EvalStamp.self, "{}")
        XCTAssertFalse(empty.recorded); XCTAssertEqual(empty.effectiveLayer, .model)
        XCTAssertEqual(empty.parts.first?.text, "not recorded")
        // An unknown layer string falls back to the derived layer.
        XCTAssertEqual(try snake(EvalStamp.self, #"{"layer": "galaxy", "agent": "claude_code"}"#).effectiveLayer, .agentModel)
    }

    // MARK: §3 Leaderboard by setup

    static let leaderboardJSON = #"""
    { "task": "own_oneroof", "version": 2, "title": "Find the files a bug fix needs", "n": 10, "checked_by": "code",
      "floor": { "right": 5, "of": 10, "rule": "a blind guess: the three most-fixed files" },
      "cases": [ { "id": "LAB-2088-4e2a7a8", "issue": "LAB-2088", "title": "Public repo clean for 2.0.0" },
                 { "id": "LAB-2090-1b2c3d4", "issue": "LAB-2090", "title": "Another" } ],
      "rows": [
        { "setup_id": "claude_code:default:off", "label": "Claude Code on its CLI default model", "stamp": null,
          "status": "waiting", "status_note": "seat use unknown", "run": "20261104-x", "started": null,
          "right": null, "n": null, "lo": null, "hi": null, "cost": null, "cost_per_right": null, "per_case": [] },
        { "setup_id": "model:claude-opus-5-5", "label": "Opus, on its own", "stamp": { "recorded": true, "layer": "model", "model": "claude-opus-5-5" },
          "status": "done", "status_note": null, "run": "20261101-083058-own_oneroof_v2-k8dy", "started": "2026-11-01T16:31:03Z",
          "right": 8, "n": 10, "lo": 0.4902, "hi": 0.9433, "cost": 0.2558, "cost_per_right": 0.032,
          "per_case": [ { "id": "LAB-2088-4e2a7a8", "right": false }, { "id": "LAB-2090-1b2c3d4", "right": null } ] } ],
      "stand_in": { "right": 0, "n": 20 } }
    """#

    func test_LAB2242_setup_leaderboard_decodes_and_ranks() throws {
        let lb = try snake(EvalSetupLeaderboard.self, Self.leaderboardJSON)
        XCTAssertEqual(lb.title, "Find the files a bug fix needs"); XCTAssertEqual(lb.version, 2); XCTAssertEqual(lb.checkedBy, "code")
        XCTAssertEqual(lb.floor?.share, 0.5); XCTAssertEqual(lb.floor?.text, "a blind guess gets 5")
        XCTAssertEqual(lb.cases.map(\.issue), ["LAB-2088", "LAB-2090"])
        XCTAssertEqual(lb.standIn, EvalSetupLeaderboard.StandIn(right: 0, n: 20))
        XCTAssertEqual(lb.ranked.map(\.label), ["Opus, on its own", "Claude Code on its CLI default model"])   // done first
        let opus = lb.ranked[0]
        XCTAssertEqual(opus.layer, .model); XCTAssertEqual(opus.scoreText, "8 of 10")
        XCTAssertEqual(opus.expectText, "On new bugs, expect 5 to 9")
        XCTAssertEqual(opus.perCase.map(\.right), [false, nil])
        XCTAssertEqual(opus.costPerRight, 0.032)
        let waiting = lb.ranked[1]
        XCTAssertTrue(waiting.isActive); XCTAssertNil(waiting.stamp); XCTAssertNil(waiting.scoreText); XCTAssertNil(waiting.expectText)
        XCTAssertEqual(waiting.statusNote, "seat use unknown")
        XCTAssertEqual(waiting.layer, .agentModel)   // derived from the setup id
        // No floor / no stand-in: null.
        let bare = try snake(EvalSetupLeaderboard.self, #"{"task": "t", "floor": null, "cases": [], "rows": [], "stand_in": null}"#)
        XCTAssertNil(bare.floor); XCTAssertNil(bare.standIn)
        XCTAssertEqual(EvalSetupLeaderboard.Floor(right: 3, of: 10, rule: "a simple rule with no AI: most-changed files").text,
                       "a simple rule with no AI gets 3")
    }

    // MARK: §4 Per-case evidence

    func test_LAB2242_samples_carry_named_and_changed_files() throws {
        let json = #"[{"id": "LAB-2088-4e2a7a8", "epoch": 1, "score": 0, "named": ["app/a/V2Layout.swift", "app/b.swift"], "changed": ["app/a/V2Chrome.swift", "app/b.swift"]}, {"id": "q2", "epoch": 1, "score": 1}, {"id": "q3", "epoch": 1}]"#
        let s = try JSONDecoder().decode([EvalSample].self, from: Data(json.utf8))
        let c = s.map(EvalCaseResult.init)
        XCTAssertEqual(c[0].right, false); XCTAssertEqual(c[0].named, ["app/a/V2Layout.swift", "app/b.swift"])
        XCTAssertEqual(c[0].changed, ["app/a/V2Chrome.swift", "app/b.swift"]); XCTAssertEqual(c[0].hits, ["app/b.swift"])
        XCTAssertEqual(c[1].right, true); XCTAssertEqual(c[1].named, [])   // other tasks: []
        XCTAssertNil(c[2].right)                                         // not answered
    }

    // MARK: §5 Changes

    func test_LAB2242_changes_decode_and_empty_is_valid() throws {
        let json = #"""
        [ { "at": "2026-11-04T18:22:00Z", "who": "you", "what": "CLAUDE.md changed", "path": "CLAUDE.md", "commit": "7b0b2bd",
            "tested": { "before": "20261101-a", "after": null } },
          { "at": "2026-11-03T10:00:00Z", "who": "vendor", "what": "Claude Code 2.1.30 → 2.1.31", "path": null, "commit": null,
            "tested": { "before": null, "after": null } } ]
        """#
        let c = try snake([EvalChange].self, json)
        XCTAssertEqual(c.map(\.who), [.you, .vendor])
        XCTAssertEqual(c[0].path, "CLAUDE.md"); XCTAssertEqual(c[0].tested?.before, "20261101-a"); XCTAssertFalse(c[0].testedBoth)
        XCTAssertNil(c[1].commit); XCTAssertNotNil(c[0].date)
        XCTAssertEqual(try snake([EvalChange].self, "[]"), [])
    }

    // MARK: §6 Real history

    func test_LAB2242_history_rows_followed_by_a_fix_from_fixup() throws {
        let rows = try snake([EvalHistoryRow].self, #"[{"agent": "Claude Code", "commits": 690, "lines": 120000, "churn": 0.21, "self": 0.6, "revert": 0.001, "fixup": 0.188}, {"agent": "unattributed", "commits": 10, "lines": null, "churn": null, "self": null, "revert": null, "fixup": null}]"#)
        XCTAssertEqual(rows[0].followedByFix, 130)                    // 0.188 × 690 = 129.7
        XCTAssertEqual(EvalHistoryRow.pct(rows[0].fixup), "18.8 %")
        XCTAssertEqual(EvalHistoryRow.pct(rows[0].revert), "0.1 %")
        XCTAssertEqual(rows[0].selfShare, 0.6)
        XCTAssertNil(rows[1].followedByFix); XCTAssertTrue(rows[1].isUntagged)
        // Today's xray shape maps onto the same rows.
        let x = try snake(EvalXRay.self, #"{"window_days": 60, "agents": {"Codex": {"commits": 4, "lines_added": 10, "fixup_rate": 0.5, "revert_rate": 0.0}}}"#)
        let h = EvalHistoryRow.from(x)
        XCTAssertEqual(h.first?.agent, "Codex"); XCTAssertEqual(h.first?.followedByFix, 2); XCTAssertEqual(h.first?.lines, 10)
    }

    // MARK: §7 Overview layers

    func test_LAB2242_overview_layers_are_additive() throws {
        let json = #"""
        {"evals": [], "changes": [], "running": [], "suggestion": null, "finished_runs": 3, "grader_runs": 2,
         "layers": [ { "layer": "model", "inside_runs": 4, "inside_stand_in": 1, "outside_runs": 33, "outside_benchmarks": 129 },
                     { "layer": "agent_model", "inside_runs": 0, "inside_waiting": 1, "outside_runs": 3, "outside_benchmarks": 48 },
                     { "layer": "full", "inside_runs": 0, "outside_runs": 0, "outside_benchmarks": 0 } ]}
        """#
        let o = try snake(EvalOverview.self, json)
        XCTAssertEqual(o.layers?.map(\.layer), [.model, .agentModel, .full])
        XCTAssertEqual(o.layers?[0].insideStandIn, 1); XCTAssertEqual(o.layers?[1].insideWaiting, 1); XCTAssertNil(o.layers?[2].insideWaiting)
        XCTAssertEqual(o.layers?[0].outsideBenchmarks, 129); XCTAssertEqual(o.graderRuns, 2)
        // A 2.0.3 engine (no layers) still decodes.
        let old = try snake(EvalOverview.self, #"{"evals": [], "changes": [], "running": [], "suggestion": null, "finished_runs": 0}"#)
        XCTAssertNil(old.layers); XCTAssertNil(old.graderRuns)
    }

    // MARK: Verdicts (EV-9)

    private let opus = EvalVerdicts.Side(label: "Opus, on its own", right: 8, n: 10, lo: 0.4902, hi: 0.9433)

    func test_LAB2242_expect_L_to_H_in_counts() {
        XCTAssertEqual(EvalVerdicts.expect(lo: 0.4902, hi: 0.9433, n: 10), "On new bugs, expect 5 to 9")
        XCTAssertEqual(EvalVerdicts.expect(lo: 0.0, hi: 0.161, n: 20), "On new bugs, expect 0 to 3")
        XCTAssertEqual(EvalPower.mirror(n: 10, epochs: 1).plusMinusPoints.rounded(), 26)   // 10 → ±26
    }

    func test_LAB2242_against_the_floor() {
        // Opus 8/10 vs a blind guess 5: the range 49–94 % touches 50 %.
        XCTAssertEqual(EvalVerdicts.againstFloor(opus, floor: 0.5)?.text, "Too few bugs to be sure it beats a blind guess")
        XCTAssertEqual(EvalVerdicts.againstFloor(opus, floor: 0.3)?.text, "Opus, on its own is better: +50 points (19 to 64)")
        XCTAssertEqual(EvalVerdicts.againstFloor(EvalVerdicts.Side(label: "X", right: nil, n: nil, lo: nil, hi: nil, done: false), floor: 0.5)?.text,
                       "Not run yet")
        XCTAssertNil(EvalVerdicts.againstFloor(opus, floor: nil))
    }

    func test_LAB2242_compare_sentences() {
        let a = EvalVerdicts.Side(label: "Claude Code using Opus", right: 18, n: 20, lo: 0.699, hi: 0.972)
        let b = EvalVerdicts.Side(label: "Opus, on its own", right: 8, n: 20, lo: 0.219, hi: 0.613)
        func v(_ p: EvalVerdicts.Paired?, floor: Double? = 0.2, _ x: EvalVerdicts.Side? = nil, _ y: EvalVerdicts.Side? = nil) -> String {
            EvalVerdicts.compare(x ?? a, y ?? b, paired: p, floor: floor).text
        }
        XCTAssertEqual(v(.init(diff: 0.5, lo: 0.3, hi: 0.7, shared: 20)), "Claude Code using Opus is better: +50 points (30 to 70)")
        XCTAssertEqual(v(.init(diff: -0.3, lo: -0.45, hi: -0.15, shared: 20)), "Opus, on its own is better: +30 points (15 to 45)")
        // Real, but the winner's own range touches the floor.
        XCTAssertEqual(v(.init(diff: -0.3, lo: -0.45, hi: -0.15, shared: 20), floor: 0.3),
                       "Opus, on its own is better, but only matches a blind guess")
        // Never a winner under 10 shared bugs, even when the range excludes 0; unpaired runs share none.
        XCTAssertEqual(v(.init(diff: 0.5, lo: 0.3, hi: 0.7, shared: 9)), "Never a winner under 10 shared bugs")
        let unpaired = EvalStats.Comparison(diff: 0.5, lo: 0.3, hi: 0.7, n: 20, paired: false, verdict: .aBetter)
        XCTAssertEqual(v(EvalVerdicts.Paired(unpaired)), "Never a winner under 10 shared bugs")
        // Not run yet: no comparison, or a side not finished.
        XCTAssertEqual(v(nil), "Not run yet")
        XCTAssertEqual(v(.init(diff: 0.5, lo: 0.3, hi: 0.7, shared: 20), nil,
                         EvalVerdicts.Side(label: "Q", right: nil, n: nil, lo: nil, hi: nil, done: false)), "Not run yet")
        // Can't tell yet: N from power (the smallest n whose ± is at most the difference).
        let n = EvalVerdicts.bugsToSettle(diff: 0.1)
        XCTAssertLessThanOrEqual(EvalPower.mirror(n: n, epochs: 1).plusMinusPoints, 10)
        XCTAssertGreaterThan(EvalPower.mirror(n: n - 1, epochs: 1).plusMinusPoints, 10)
        XCTAssertEqual(v(.init(diff: 0.1, lo: -0.1, hi: 0.3, shared: 10)), "Can't tell yet: about \(n) bugs would settle it")
        XCTAssertEqual(EvalVerdicts.compare(a, b, paired: .init(diff: 0.1, lo: -0.1, hi: 0.3, shared: 10), settle: 40).text,
                       "Can't tell yet: about 40 bugs would settle it")
        XCTAssertEqual(EvalVerdicts.bugsToSettle(diff: 0), 1000)
        XCTAssertGreaterThan(EvalVerdicts.bugsToSettle(diff: 0.1, epochs: 1), EvalVerdicts.bugsToSettle(diff: 0.1, epochs: 3))
    }

    func test_LAB2242_verdicts_from_setup_rows() throws {
        let lb = try snake(EvalSetupLeaderboard.self, Self.leaderboardJSON)
        let sides = lb.rows.map(EvalVerdicts.Side.init)
        XCTAssertFalse(sides[0].done); XCTAssertTrue(sides[1].done)
        XCTAssertEqual(EvalVerdicts.compare(sides[1], sides[0], paired: .init(diff: 0.3, lo: 0.1, hi: 0.5, shared: 10)).kind, .notRun)
        XCTAssertEqual(EvalVerdicts.againstFloor(sides[1], floor: lb.floor?.share)?.kind, .tooFewVsFloor)
    }
}
