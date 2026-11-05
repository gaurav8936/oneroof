import XCTest
@testable import OneRoofCore

/// LAB-2258 · Evals v3 core: job kind, loop placement (D1), loop runs from the ledger, evidence counts (EV-13), routes.
final class EvalsV3Tests: XCTestCase {
    private func plain<T: Decodable>(_ t: T.Type, _ json: String) throws -> T { try JSONDecoder().decode(T.self, from: Data(json.utf8)) }

    // D1: by definition, never by name.
    func test_LAB2258_loop_place_by_definition() {
        XCTAssertEqual(EvalLoopPlace.classify(isKitLoop: true, hasPrompt: true, act: "none"), .oneShot)    // morning-brief
        XCTAssertEqual(EvalLoopPlace.classify(isKitLoop: true, hasPrompt: true, act: "pr"), .oneShot)      // week-in-review: the kit acts
        XCTAssertEqual(EvalLoopPlace.classify(isKitLoop: true, hasPrompt: false, act: "pr"), .noModel)     // security-audit, docs-drift
        XCTAssertEqual(EvalLoopPlace.classify(isKitLoop: false, hasPrompt: false, act: nil), .agent)       // oneroof-nightly-bugs
        XCTAssertEqual(EvalLoopPlace.classify(isKitLoop: false, hasPrompt: false, act: "none"), .oneShot)  // my-morning-brief
    }

    func test_LAB2258_loop_place_from_a_Loop() {
        var kit = Loop(id: "docs-drift", name: "docs-drift", check: "python3 -m ae.loops run docs-drift --no-agent", repoPath: "/r")
        kit.act = "pr"; kit.kind = "auditor"
        XCTAssertEqual(EvalLoopPlace.classify(kit), .noModel)
        kit.roundPrompt = "Write the brief."
        XCTAssertEqual(EvalLoopPlace.classify(kit), .oneShot)
        let bugs = Loop(id: "oneroof-nightly-bugs", name: "oneroof-nightly-bugs", check: "bash tools/loop-checks/x.sh", repoPath: "/r",
                        roundPrompt: "Fix the oldest bug.")
        XCTAssertEqual(EvalLoopPlace.classify(bugs), .agent)
    }

    func test_LAB2258_kit_prompt_read_from_spec_file() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("evalsv3-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let f = dir.appendingPathComponent("x.loop.yaml").path
        try "name: x\nkind: judge\nprompt: x.prompt.md\nact:\n  by: issue\n".write(toFile: f, atomically: true, encoding: .utf8)
        var l = Loop(id: "x", name: "x", check: "python3 -m ae.loops run x --no-agent", repoPath: "/r"); l.specFile = f
        XCTAssertEqual(EvalLoopPlace.classify(l), .oneShot)
    }

    func test_LAB2258_good_run_rule_by_kind() {
        XCTAssertEqual(EvalLoopPlace.goodRun(kind: "reporter", place: .oneShot), "it was right and you read it")
        XCTAssertEqual(EvalLoopPlace.goodRun(kind: "judge", place: .oneShot), "its verdicts matched yours")
        XCTAssertEqual(EvalLoopPlace.goodRun(kind: nil, place: .agent), "the fix passed its check and stayed in")
    }

    func test_LAB2258_loop_runs_from_ledger_never_invent_good() {
        let l = Loop(id: "morning-brief", name: "morning-brief", title: "Morning brief", check: "python3 -m ae.loops run morning-brief --no-agent",
                     repoPath: "/r", roundPrompt: "brief")
        let idle = Loop(id: "triage-inbox", name: "triage-inbox", check: "python3 -m ae.loops run triage-inbox --no-agent", repoPath: "/r", roundPrompt: "t")
        func run(_ r: String, _ m: String = "live") -> LoopLedger.Run {
            LoopLedger.Run(id: UUID().uuidString, loop: "morning-brief", engine: "ae", mode: m, started: "2026-11-0\(Int.random(in: 1...5))T04:30:00-08:00",
                           ended: "", result: r, cost: nil, summary: "")
        }
        let rows = EvalLoopRuns.summarize(loops: [l, idle], runs: [run("pass"), run("pass"), run("fail"), run("dry", "dry")])
        XCTAssertEqual(rows.count, 2)
        XCTAssertEqual(rows[0].runs, 3); XCTAssertEqual(rows[0].finished, 2); XCTAssertEqual(rows[0].failed, 1); XCTAssertEqual(rows[0].dry, 1)
        XCTAssertNil(rows[0].good)
        XCTAssertEqual(rows[0].countLine, "3 runs · 1 failed · 1 dry")
        XCTAssertEqual(rows[1].runs, 0); XCTAssertEqual(rows[1].countLine, "no live runs")
        let a = EvalLoopRuns.answer(rows, kind: .oneShot)
        XCTAssertTrue(a.contains("not recorded yet")); XCTAssertTrue(a.contains("Morning brief is the one to look at: 1 of its 3 runs failed"))
        XCTAssertTrue(EvalLoopRuns.answer([], kind: .agent).hasPrefix("None of our agent loops"))
    }

    func test_LAB2258_evidence_counts_by_kind() throws {
        let results = try plain([EvalResult].self, #"""
        [{"id": "a", "task": "own_oneroof_v2", "model": "anthropic/claude-opus-5-5", "status": "done", "metrics": [], "set_name": "oneroof"},
         {"id": "b", "task": "own_oneroof_v2", "model": "mockllm/model", "status": "done", "metrics": [], "set_name": "oneroof"},
         {"id": "c", "task": "gsm8k", "model": "anthropic/claude-haiku-5-5", "status": "done", "metrics": []},
         {"id": "d", "task": "swe_bench", "model": "anthropic/claude-haiku-5-5", "status": "done", "metrics": [], "agent": "claude_code"},
         {"id": "e", "task": "judge_oneroof_triage", "model": "anthropic/claude-sonnet-5-5", "status": "done", "metrics": []},
         {"id": "f", "task": "own_oneroof_v2", "model": "x", "status": "done", "metrics": [], "set_name": "oneroof", "agent": "codex"}]
        """#)
        let runs = try plain([EvalRunRow].self, #"[{"id": "w", "task": "own_oneroof_v2", "status": "waiting", "progress": "0/10", "agent": "claude_code", "set_name": "oneroof"}]"#)
        let loops = [EvalLoopRuns(loop: "mb", title: "Morning brief", kind: "reporter", place: .oneShot, runs: 7, finished: 6, failed: 1, dry: 0),
                     EvalLoopRuns(loop: "nb", title: "nightly-bugs", kind: nil, place: .agent, runs: 6, finished: 0, failed: 6, dry: 0),
                     EvalLoopRuns(loop: "cw", title: "cost-watch", kind: "sentinel", place: .noModel, runs: 68, finished: 60, failed: 0, dry: 8)]
        let one = EvalEvidence.count(results: results, runs: runs, loops: loops, kind: .oneShot)
        XCTAssertEqual(one, EvalEvidence(publicTests: 1, ours: 1, loopRuns: 7, waiting: 0, standIn: 1))
        let ag = EvalEvidence.count(results: results, runs: runs, loops: loops, kind: .agent)
        XCTAssertEqual(ag.publicTests, 0, "the agent bar never has a public segment")
        XCTAssertEqual(ag.ours, 1); XCTAssertEqual(ag.loopRuns, 6); XCTAssertEqual(ag.waiting, 1)
        XCTAssertEqual(EvalEvidence.publicAgentRuns(results), 1)
        XCTAssertEqual(EvalEvidence.graderRuns(results), 1)
        XCTAssertEqual(EvalEvidenceSource.sources(.agent), [.ours, .loopRuns])
    }

    func test_LAB2258_segment_widths_keep_a_minimum_and_fill() {
        let w = EvalEvidence.widths(shares: [0.9, 0.05, 0.05], total: 400, gap: 4, minimum: 60)
        XCTAssertEqual(w.reduce(0, +), 392, accuracy: 0.01)
        XCTAssertTrue(w.allSatisfy { $0 >= 59.99 })
        let empty = EvalEvidence().shares(.agent)
        XCTAssertEqual(empty[.ours]!, 0.5, accuracy: 0.001)
    }

    func test_LAB2258_selftest_names_old_and_new() {
        XCTAssertEqual(EvalsV3Screen.selfTest("launch")?.screen, .launch)
        XCTAssertEqual(EvalsV3Screen.selfTest("overview")?.screen, .launch)
        XCTAssertEqual(EvalsV3Screen.selfTest("compare")?.screen, .oneShotOurs)
        XCTAssertEqual(EvalsV3Screen.selfTest("agent-ours")?.screen, .agentOurs)
        XCTAssertEqual(EvalsV3Screen.selfTest("x-ray")?.screen, .realHistory)
        XCTAssertEqual(EvalsV3Screen.selfTest("questions")?.part, "questions")
        XCTAssertEqual(EvalsV3Screen.selfTest("how-to")?.part, "how-to")
        // Every 2.0.3 / 2.0.4 name still opens something.
        for n in EvalsCoverage.oldSelfTestNames { XCTAssertNotNil(EvalsV3Screen.selfTest(n), n) }
        for s in EvalsScreen.allCases { XCTAssertNotNil(EvalsV3Screen.selfTest(s.selfTestName), s.selfTestName) }
        XCTAssertEqual(Set(EvalsV3Screen.allCases.compactMap(\.keyDigit)).count, 9)
    }
}

final class EvalsV3ColourTests: XCTestCase {
    /// Rule 2: the three evidence colours read in every look (label ≥ 3:1 on its fill), and stay three different colours.
    func test_LAB2258_evidence_colours_read_in_every_look() {
        for name in ThemeName.panelChoices {
            let t = name.tokens
            var fills: [RGB] = []
            for s in EvalEvidenceSource.allCases {
                let e = t.evidence(s)
                XCTAssertGreaterThanOrEqual(RGB.contrast(e.fill, e.ink), 3, "\(name) \(s)")
                fills.append(e.fill)
            }
            XCTAssertEqual(Set(fills.map(\.hex)).count, 3, "\(name): three different colours")
            for k in EvalJobKind.allCases { XCTAssertGreaterThanOrEqual(RGB.contrast(t.jobTag(k).fill, t.jobTag(k).ink), 3, "\(name) \(k)") }
        }
    }
}

final class EvalsV3AnswerTests: XCTestCase {
    func test_LAB2258_ours_answer_by_kind_never_invents() throws {
        let d = JSONDecoder(); d.keyDecodingStrategy = .convertFromSnakeCase
        let lb = try d.decode(EvalSetupLeaderboard.self, from: Data(#"""
        {"task": "own_oneroof_v2", "title": "Find the files a bug fix needs", "n": 10, "cases": [],
         "floor": {"right": 5, "of": 10},
         "rows": [{"setup_id": "model:anthropic/claude-opus-5-5", "label": "Opus, on its own", "status": "done", "right": 8, "n": 10},
                  {"setup_id": "claude_code:", "label": "Claude Code on its CLI default model", "status": "waiting"}]}
        """#.utf8))
        let one = EvalsV3Answers.ours([lb], kind: .oneShot)
        XCTAssertTrue(one.hasPrefix("Opus, on its own got 8 of 10 on \u{201C}Find the files a bug fix needs\u{201D} (a blind guess gets 5)"), one)
        let ag = EvalsV3Answers.ours([lb], kind: .agent)
        XCTAssertEqual(ag, "No agent has finished one of our tasks yet. 1 test waiting: open the queue to see why.")
        XCTAssertEqual(EvalsV3Answers.ours([], kind: .oneShot), "No model has finished one of our tasks yet.")
    }

    func test_LAB2258_crumbs() {
        let s = EvalsCrumbs.steps(page: .changes, trail: [.agentOurs], drill: nil)
        XCTAssertEqual(s.map(\.title), ["Evals", "Agent jobs", "Our tests", "Changes"])
        XCTAssertEqual(s.last?.target, nil); XCTAssertEqual(s[2].target, .agentOurs)
        let d = EvalsCrumbs.steps(page: .oneShotOurs, trail: [], drill: "One test")
        XCTAssertEqual(d.map(\.title), ["Evals", "One-shot jobs", "Our tests", "One test"])
        XCTAssertEqual(d[2].target, .oneShotOurs)
    }
}

final class EvalsHFTokenScopeTests: XCTestCase {
    /// LAB-2246 (reopened): only commands that read gated data get the token (and so read the Keychain).
    func test_LAB2246_token_only_for_gated_commands() {
        // Only a gated dataset, never our tasks or open benchmarks (2.0.5 review P1).
        XCTAssertTrue(EvalEngine.needsHFToken(["run", "inspect_evals/hle", "--model", "x"], gated: ["hle", "xstest"]))
        XCTAssertTrue(EvalEngine.needsHFToken(["items", "hle"], gated: ["hle"]))
        XCTAssertTrue(EvalEngine.needsHFToken(["item", "xstest_v1", "3"], gated: ["xstest"]))
        XCTAssertFalse(EvalEngine.needsHFToken(["items", "gsm8k"], gated: ["hle"]))
        XCTAssertFalse(EvalEngine.needsHFToken(["run", "/x/own_oneroof_v2.py", "--agent", "claude_code"], gated: ["hle"]))
        XCTAssertTrue(EvalEngine.needsHFToken(["resume", "r1"], gated: ["hle"], taskOfRun: { $0 == "r1" ? "hle" : nil }))
        XCTAssertFalse(EvalEngine.needsHFToken(["run-anyway", "r2"], gated: ["hle"], taskOfRun: { _ in "own_oneroof_v2" }))
        for c in ["doctor", "catalog", "results", "overview", "leaderboard", "samples", "estimate", "power", "xray", "changes"] {
            XCTAssertFalse(EvalEngine.needsHFToken([c, "hle"], gated: ["hle"]), c)
        }
        XCTAssertFalse(EvalEngine.needsHFToken([]))
        XCTAssertFalse(EvalSources.gatedFolders.isEmpty)
    }

    /// 2.0.5 review P2: an older own_<set> run with no set name is ours, not public.
    func test_review_legacy_own_run_is_not_public_evidence() throws {
        let rs = try JSONDecoder().decode([EvalResult].self, from: Data(#"[{"id": "o", "task": "own_oneroof_v1", "model": "a/b", "status": "done", "metrics": []}]"#.utf8))
        let e = EvalEvidence.count(results: rs, runs: [], loops: [], kind: .oneShot)
        XCTAssertEqual(e.publicTests, 0); XCTAssertEqual(e.ours, 1)
    }
}
