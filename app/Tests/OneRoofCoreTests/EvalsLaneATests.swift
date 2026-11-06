import XCTest
@testable import OneRoofCore

/// LAB-2242 · Evals v2 screen lane A (Overview · Compare · One test · All results · Changes · Real history): the pure parts in
/// EvalsA_Models.swift. Fixtures follow CONTRACT §3/§5/§6/§7 and the engine's real answers on this Mac (Nov 5): fix locator
/// v2 = Opus on its own 8 of 10 (49–94 %), Claude Code on its CLI default model waiting (seat use unknown); bug triage v1 =
/// Haiku 8 of 20, gpt-5-nano 4 of 20; floor 5 of 10 / 8 of 20.
final class EvalsLaneATests: XCTestCase {
    private func snake<T: Decodable>(_ t: T.Type, _ json: String) throws -> T {
        let d = JSONDecoder(); d.keyDecodingStrategy = .convertFromSnakeCase
        return try d.decode(T.self, from: Data(json.utf8))
    }
    private func plain<T: Decodable>(_ t: T.Type, _ json: String) throws -> T { try JSONDecoder().decode(T.self, from: Data(json.utf8)) }

    static let cases = ["LAB-2094-56aa1af", "LAB-2088-4e2a7a8", "LAB-1931-a7c9c8c", "LAB-1829-e826106", "LAB-1828-a81fbcb",
                        "LAB-1826-7604c8c", "LAB-1783-9e0f262", "LAB-1758-412b52f", "LAB-1620-64e0e83", "LAB-1612-713d2c2"]

    static var fixJSON: String {
        let cs = cases.map { #"{"id": "\#($0)", "issue": "\#($0.split(separator: "-").prefix(2).joined(separator: "-"))", "title": "t \#($0)"}"# }.joined(separator: ",")
        let opus = cases.enumerated().map { #"{"id": "\#($0.element)", "right": \#($0.offset >= 2)}"# }.joined(separator: ",")
        let wait = cases.map { #"{"id": "\#($0)", "right": null}"# }.joined(separator: ",")
        return #"""
        {"task": "own_oneroof", "version": 2, "title": "Find the files a bug fix needs", "n": 10, "checked_by": "code",
         "floor": {"right": 5, "of": 10, "rule": "a blind guess: the three most-fixed files"},
         "cases": [\#(cs)],
         "rows": [
          {"setup_id": "claude_code:default:off", "label": "Claude Code on its CLI default model",
           "stamp": {"recorded": false, "layer": "agent_model", "agent": "claude_code", "agent_name": "Claude Code", "model": null,
                     "model_source": "cli_default_unknown", "runs_on": "seat:C1", "rules": "off", "task_version": 2},
           "status": "waiting", "status_note": "seat use unknown", "run": "20261101-083058-own_oneroof_v2-slju",
           "started": "2026-11-01T16:30:58Z", "right": null, "n": null, "lo": null, "hi": null, "cost": 0.0, "cost_per_right": null,
           "per_case": [\#(wait)]},
          {"setup_id": "model:claude-opus-5-5", "label": "Opus, on its own",
           "stamp": {"recorded": false, "layer": "model", "model": "claude-opus-5-5", "model_source": "api", "runs_on": "api:anthropic",
                     "task_version": 2, "seed": 42},
           "status": "done", "status_note": null, "run": "20261101-083058-own_oneroof_v2-k8dy", "started": "2026-11-01T16:31:03+00:00",
           "right": 8, "n": 10, "lo": 0.4902, "hi": 0.9433, "cost": 0.2558, "cost_per_right": 0.032, "per_case": [\#(opus)]}
         ],
         "stand_in": null}
        """#
    }

    static let triJSON = #"""
    {"task": "own_oneroof_triage", "version": 1, "title": "Write a useful note on a new bug", "n": 20, "checked_by": "code",
     "floor": {"right": 8, "of": 20, "rule": "a blind guess: the three most-fixed files"}, "cases": [],
     "rows": [
      {"setup_id": "model:claude-haiku-5-5", "label": "Haiku, on its own", "stamp": {"recorded": false, "layer": "model", "model": "claude-haiku-5-5", "runs_on": "api:anthropic", "task_version": 1},
       "status": "done", "run": "20261031-195953-own_oneroof_triage_v1-t7mw", "right": 8, "n": 20, "lo": 0.2188, "hi": 0.6134, "per_case": []},
      {"setup_id": "model:gpt-5-nano", "label": "gpt-5-nano, on its own", "stamp": {"recorded": false, "layer": "model", "model": "gpt-5-nano", "runs_on": "api:openai", "task_version": 1},
       "status": "done", "run": "20261031-200005-own_oneroof_triage_v1-45zu", "right": 4, "n": 20, "lo": 0.0807, "hi": 0.416, "per_case": []}
     ]}
    """#

    private func fix() throws -> EvalSetupLeaderboard { try snake(EvalSetupLeaderboard.self, Self.fixJSON) }
    private func tri() throws -> EvalSetupLeaderboard { try snake(EvalSetupLeaderboard.self, Self.triJSON) }

    // MARK: Words

    func test_LAB2242_A_words() {
        XCTAssertEqual(EvalsAWords.day("2026-11-01T16:31:03+00:00"), "Nov 1")
        XCTAssertEqual(EvalsAWords.day("2026-11-01T16:30:58Z"), "Nov 1")
        XCTAssertEqual(EvalsAWords.day(nil), "–")
        XCTAssertEqual(EvalsAWords.list(["a"]), "a")
        XCTAssertEqual(EvalsAWords.list(["a", "b", "c"]), "a, b and c")
        XCTAssertEqual(EvalsAWords.count(1, "run"), "1 run")
        XCTAssertEqual(EvalsAWords.count(4, "run"), "4 runs")
        XCTAssertEqual(EvalsAWords.dollars(0.2558), "$0.256")
        XCTAssertEqual(EvalsAWords.dollars(0.0002), "$0.0002")
        XCTAssertEqual(EvalsAWords.dollars(nil), "–")
        XCTAssertEqual(EvalsAWords.seatAgents.map(\.key), ["claude_code", "codex_cli"])   // OpenCode/Goose never offered
    }

    // MARK: E1 · layers

    static let layersJSON = #"""
    [{"layer": "model", "inside_runs": 4, "inside_stand_in": 1, "inside_waiting": 0, "outside_runs": 30, "outside_stand_in": 10, "outside_benchmarks": 129},
     {"layer": "agent_model", "inside_runs": 0, "inside_stand_in": 0, "inside_waiting": 1, "outside_runs": 2, "outside_benchmarks": 48},
     {"layer": "full", "inside_runs": 0, "inside_stand_in": 0, "inside_waiting": 0, "outside_runs": 0, "outside_benchmarks": 0}]
    """#

    func test_LAB2242_A_layer_bands_split_inside_and_outside() throws {
        let b = EvalsALayers.bands(try snake([EvalOverviewLayer].self, Self.layersJSON))
        XCTAssertEqual(b.map(\.layer), [.model, .agentModel, .full])
        XCTAssertEqual(b[0].inside, "4 runs · 1 stand-in"); XCTAssertEqual(b[0].insideTone, .measured)
        XCTAssertEqual(b[0].outside, "129 benchmarks"); XCTAssertEqual(b[0].outsideNote, "30 runs here, for context")
        XCTAssertEqual(b[1].inside, "0 finished · 1 waiting"); XCTAssertEqual(b[1].insideTone, .waiting)
        XCTAssertEqual(b[1].outside, "48 agent tasks")
        XCTAssertEqual(b[2].inside, "not recorded yet · LAB-2240"); XCTAssertEqual(b[2].insideTone, .gap)
        XCTAssertEqual(b[2].outside, "none"); XCTAssertEqual(b[2].outsideNote, "only your own work can test this")
        XCTAssertFalse(b.contains { $0.inside.contains("39") })   // never every finished run as the model layer (review §2 #1)
    }

    func test_LAB2242_A_layer_bands_missing_layer_is_a_gap() {
        let b = EvalsALayers.bands([])
        XCTAssertEqual(b.map(\.insideTone), [.gap, .gap, .gap])
        XCTAssertEqual(b[0].inside, "not run yet")
    }

    func test_LAB2242_A_grader_runs_counted_apart() {
        XCTAssertEqual(EvalsALayers.graderLine(2), "Grader runs: 2, counted apart: they study our notes, they are not a setup.")
        XCTAssertNil(EvalsALayers.graderLine(0)); XCTAssertNil(EvalsALayers.graderLine(nil))
    }

    func test_LAB2242_A_layers_derived_from_the_run_store_before_2_0_4() throws {
        let results = try plain([EvalResult].self, #"""
        [{"id": "a", "task": "own_oneroof_v2", "model": "anthropic/claude-opus-5-5", "status": "done", "metrics": [], "set_name": "oneroof", "set_version": 2},
         {"id": "b", "task": "own_oneroof_triage_v1", "model": "mockllm/model", "status": "done", "metrics": [], "set_name": "oneroof_triage", "set_version": 1},
         {"id": "c", "task": "gsm8k", "model": "anthropic/claude-haiku-5-5", "status": "done", "metrics": []},
         {"id": "d", "task": "swe_bench", "model": "anthropic/claude-haiku-5-5", "agent": "codex_cli", "status": "done", "metrics": []},
         {"id": "e", "task": "judge_oneroof_triage_v1", "model": "openai/gpt-5-mini", "status": "done", "metrics": []},
         {"id": "f", "task": "gsm8k", "model": "anthropic/claude-haiku-5-5", "status": "failed", "metrics": []}]
        """#)
        let runs = try plain([EvalRunRow].self, #"[{"id": "w", "task": "own_oneroof_v2", "status": "waiting", "progress": "0/10", "agent": "claude_code", "set_name": "oneroof"}]"#)
        let d = EvalsALayers.derive(results: results, runs: runs, benchmarks: 129, agentBenchmarks: 48)
        XCTAssertEqual(d.graders, 1)
        XCTAssertEqual(d.layers[0].insideRuns, 1); XCTAssertEqual(d.layers[0].insideStandIn, 1); XCTAssertEqual(d.layers[0].outsideRuns, 1)
        XCTAssertEqual(d.layers[1].insideRuns, 0); XCTAssertEqual(d.layers[1].insideWaiting, 1); XCTAssertEqual(d.layers[1].outsideRuns, 1)
        XCTAssertEqual(d.layers[1].outsideBenchmarks, 48)
        XCTAssertEqual(d.layers[2].insideRuns, 0)
    }

    // MARK: E1 · the three questions

    func test_LAB2242_A_q1_cant_tell_for_agents_from_real_rows() throws {
        let q = EvalsAQuestions.whichSetup([try fix(), try tri()])
        XCTAssertEqual(q.answer.tone, .gap)
        XCTAssertEqual(q.answer.headline, "Can't tell yet for agents")
        XCTAssertTrue(q.answer.body.hasPrefix("Every finished test on our tasks is a model on its own."))
        XCTAssertTrue(q.answer.body.contains("Claude Code on its CLI default model has waited since Nov 1 (seat use unknown)."), q.answer.body)
        XCTAssertTrue(q.answer.body.contains("Best so far: Opus, on its own, 8 of 10 on “Find the files a bug fix needs”; a blind guess gets 5."), q.answer.body)
        XCTAssertTrue(q.answer.body.contains("Too few bugs to be sure it beats a blind guess."))   // 49–94 % touches 50 %
        XCTAssertFalse(q.answer.body.contains("Sonnet"))                                          // never "using Sonnet"
        XCTAssertEqual(q.title, "Find the files a bug fix needs · 10 bugs · tick = a blind guess gets 5")
        XCTAssertEqual(q.bars.map(\.label), ["Opus, on its own", "Claude Code on its CLI default model"])
        XCTAssertEqual(q.bars[0].text, "8 of 10"); XCTAssertEqual(q.bars[0].floor, 0.5)
        XCTAssertTrue(q.bars[1].muted); XCTAssertNil(q.bars[1].value)
    }

    func test_LAB2242_A_q1_not_run_and_agent_rule() throws {
        XCTAssertEqual(EvalsAQuestions.whichSetup([]).answer.headline, "Not run yet")
        var lb = try fix()
        lb.rows = lb.rows.filter { !$0.isDone }
        XCTAssertEqual(EvalsAQuestions.whichSetup([lb]).answer.headline, "Not run yet")
        // An agent finished 10 of 10 (range above the floor): a call, by rule.
        var done = try fix()
        done.rows[0].status = "done"; done.rows[0].right = 10; done.rows[0].n = 10; done.rows[0].lo = 0.7225; done.rows[0].hi = 1.0
        let q = EvalsAQuestions.whichSetup([done])
        XCTAssertEqual(q.answer.tone, .call)
        XCTAssertEqual(q.answer.headline, "Claude Code on its CLI default model beats a blind guess")
    }

    func test_LAB2242_A_q2_not_recorded_until_stamps() throws {
        let you = try snake([EvalChange].self, #"[{"at": "2026-10-31T18:30:55Z", "who": "you", "what": "app/CLAUDE.md changed", "path": "app/CLAUDE.md", "commit": "89d9cc4", "tested": {"before": null, "after": null}}]"#)
        let a = EvalsAQuestions.didMyChangeHelp([try fix()], changes: you)
        XCTAssertEqual(a.tone, .gap); XCTAssertEqual(a.headline, "Can't answer: not recorded")
        XCTAssertTrue(a.body.hasSuffix("1 change in the last 60 days (1 yours, 0 from the vendor)."), a.body)
        XCTAssertTrue(EvalsAQuestions.didMyChangeHelp([try fix()], changes: []).body.hasSuffix("No change to your rules, skills or agents in the last 60 days."))
        // A recorded agent stamp, no change tested on both sides: can't tell yet.
        var lb = try fix(); lb.rows[0].stamp?.recorded = true
        XCTAssertEqual(EvalsAQuestions.didMyChangeHelp([lb], changes: nil).headline, "Can't tell yet")
        // A change tested on both sides.
        var both = you; both[0].tested = EvalChange.Tested(before: "r1", after: "r2")
        XCTAssertEqual(EvalsAQuestions.didMyChangeHelp([try fix()], changes: both).headline, "Tested before and after")
    }

    func test_LAB2242_A_records_read_from_stamps() throws {
        let r = EvalsAQuestions.records([try fix()])
        XCTAssertEqual(r.map(\.state), [.yes, .yes, .no, .no, .no])
        var lb = try fix()
        lb.rows[0].stamp = EvalStamp(recorded: true, layer: .agentModel, agent: "claude_code", agentName: "Claude Code", agentVersion: "2.1.31",
                                     model: "claude-opus-5-5", rules: "off", taskVersion: 2)
        XCTAssertEqual(EvalsAQuestions.records([lb]).map(\.state), [.yes, .yes, .yes, .yes, .yes])
    }

    static let history = [EvalHistoryRow(agent: "Claude", commits: 657, lines: 89202, churn: 0.1091, selfShare: 0.7479, revert: 0.0015, fixup: 0.1872),
                          EvalHistoryRow(agent: "unattributed", commits: 111, lines: 113820, churn: 0.0675, selfShare: 0.7669, revert: 0, fixup: 0.4234)]

    func test_LAB2242_A_q3_real_history_count_and_percent() {
        let q = EvalsAQuestions.realHistory(Self.history, repos: 3, days: 60)
        XCTAssertEqual(q.answer.tone, .call)
        XCTAssertEqual(q.answer.headline, "123 of Claude's 657 commits (18.7 %) were followed by a fix")   // fixup × commits, not "~130"
        XCTAssertTrue(q.answer.body.hasPrefix("Last 60 days, 3 repos. Reverted: 0.1 %."), q.answer.body)
        XCTAssertTrue(q.answer.body.contains("111 more commits carry no agent name, so they can't be compared yet (LAB-2241)."))
        XCTAssertEqual(q.bars.map(\.label), ["Claude · 657 commits", "No agent name · 111 commits"])
        XCTAssertTrue(q.bars[1].muted)
        XCTAssertEqual(EvalsAQuestions.realHistory(nil, repos: 1, days: 60).answer.tone, .reading)
        XCTAssertEqual(EvalsAQuestions.realHistory(nil, repos: 1, days: 60, error: "not a git repo").answer.headline, "Can't read git")
        XCTAssertEqual(EvalsAQuestions.realHistory([Self.history[1]], repos: 1, days: 60).answer.headline, "No agent commits found")
    }

    // MARK: E2 · Compare

    func test_LAB2242_A_leaderboard_decodes_and_ranks() throws {
        let lb = try fix()
        XCTAssertEqual(lb.ranked.map(\.label), ["Opus, on its own", "Claude Code on its CLI default model"])
        XCTAssertEqual(lb.rows[0].stamp?.modelSource, "cli_default_unknown")
        XCTAssertNil(lb.rows[0].costPerRight)
        XCTAssertEqual(lb.rows[1].expectText, "On new bugs, expect 5 to 9")
    }

    func test_LAB2242_A_squares_right_first_in_set_order() throws {
        let lb = try fix()
        let sq = EvalsASquares.ordered(cases: lb.cases, perCase: lb.rows[1].perCase)
        XCTAssertEqual(sq.count, 10)
        XCTAssertEqual(sq.prefix(8).map { $0.right }, Array(repeating: true, count: 8))
        XCTAssertEqual(sq.suffix(2).map(\.issue), ["LAB-2094", "LAB-2088"])       // wrong ones last, set order kept
        XCTAssertEqual(sq.first?.issue, "LAB-1931")
        XCTAssertEqual(sq.first?.title, "t LAB-1931-a7c9c8c")
        // Not answered goes last; in set order the squares line up with the cases.
        let wait = EvalsASquares.ordered(cases: lb.cases, perCase: lb.rows[0].perCase)
        XCTAssertTrue(wait.allSatisfy { $0.right == nil })
        XCTAssertEqual(EvalsASquares.inCaseOrder(cases: lb.cases, perCase: lb.rows[1].perCase).map(\.id), Self.cases)
        XCTAssertEqual(EvalsASquares.issue("LAB-2088-4e2a7a8"), "LAB-2088")
    }

    func test_LAB2242_A_guess_tick_at_the_floor() throws {
        XCTAssertEqual(EvalsASquares.guessIndex(floor: try fix().floor, n: 10), 5)
        XCTAssertEqual(EvalsASquares.guessIndex(floor: try tri().floor, n: 20), 8)
        XCTAssertEqual(EvalsASquares.guessIndex(floor: try tri().floor, n: 10), 4)   // scaled when a row has fewer bugs
        XCTAssertNil(EvalsASquares.guessIndex(floor: nil, n: 10))
    }

    func test_LAB2242_A_squares_from_samples_first_attempt() throws {
        let xs = try plain([EvalSample].self, #"""
        [{"id": "B-2-x", "epoch": 1, "score": 0.0}, {"id": "A-1-x", "epoch": 2, "score": 0.0}, {"id": "A-1-x", "epoch": 1, "score": 1.0},
         {"id": "C-3-x", "epoch": 1, "score": null}]
        """#)
        let sq = EvalsASquares.fromSamples(xs)
        // review fix 4 (one attempts policy): A-1 is right on 1 of its 2 attempts = 0.5 (part filled), not "right"
        XCTAssertEqual(sq.map(\.id), ["A-1-x", "B-2-x", "C-3-x"])
        XCTAssertEqual(sq.map(\.right), [false, false, nil])
        XCTAssertEqual(sq.map(\.score), [0.5, 0, nil])
        let s = EvalsAOneTest.score(sq)!
        XCTAssertEqual(s.right, 0.5); XCTAssertEqual(s.n, 2)
        XCTAssertNil(EvalsAOneTest.score([]))
    }

    func test_LAB2242_A_compare_headline_by_rule() throws {
        XCTAssertEqual(EvalsACompare.headline(try fix()),
                       "Opus, on its own, got 8 of 10 bugs right; a blind guess gets 5. Too few bugs to be sure it beats a blind guess. No agent has finished this task yet.")
        var lb = try fix(); lb.rows = [lb.rows[0]]
        XCTAssertEqual(EvalsACompare.headline(lb), "No setup has finished this task yet. Claude Code on its CLI default model is waiting: seat use unknown.")
        let t = try tri()
        XCTAssertTrue(EvalsACompare.headline(t).hasPrefix("Haiku, on its own, got 8 of 20 bugs right; a blind guess gets 8."))
    }

    func test_LAB2242_A_missed_and_status() throws {
        let lb = try fix()
        XCTAssertEqual(EvalsACompare.missedText(lb.rows[1], in: lb), "Missed LAB-2094 and LAB-2088: nobody has solved those yet.")
        XCTAssertNil(EvalsACompare.missedText(lb.rows[0], in: lb))
        XCTAssertEqual(EvalsACompare.statusText(lb.rows[0]), "Waiting since Nov 1: seat use unknown")
        var stuck = lb.rows[0]; stuck.statusNote = "stuck: waiting since 2026-11-01 without knowing the seat use"
        XCTAssertEqual(EvalsACompare.statusText(stuck), "Stuck: waiting since 2026-11-01 without knowing the seat use")   // QA #6: the date once
        var r = lb.rows[0]; r.status = "expired"; r.statusNote = nil
        XCTAssertEqual(EvalsACompare.statusText(r), "Expired: waited 6 hours with seat use unknown")
    }

    func test_LAB2242_A_untested_setups_and_their_plan() throws {
        let lb = try fix()
        let xs = EvalsACompare.untested(lb, others: [lb, try tri()])
        XCTAssertEqual(xs.map(\.label), ["Codex, on your CX seat", "Haiku, on its own", "gpt-5-nano, on its own"])   // Claude Code waits: not untested
        XCTAssertEqual(xs.compactMap(\.model), ["anthropic/claude-haiku-5-5", "openai/gpt-5-nano"])
        let p = EvalsACompare.plan(xs, taskFile: "/sets/oneroof/v2/own_oneroof_v2.py", cases: 10)
        XCTAssertEqual(p.tasks, ["/sets/oneroof/v2/own_oneroof_v2.py"]); XCTAssertEqual(p.agents, ["codex_cli"])
        XCTAssertEqual(p.models, ["anthropic/claude-haiku-5-5", "openai/gpt-5-nano"]); XCTAssertEqual(p.limit, 10)
        // An expired run does not count as tested.
        var ex = lb; ex.rows[0].status = "expired"
        XCTAssertEqual(EvalsACompare.untested(ex, others: []).map(\.agent), ["claude_code", "codex_cli"])
    }

    func test_LAB2242_A_paired_verdict_wiring() throws {
        let a = EvalVerdicts.Side(label: "Haiku", right: 8, n: 20, lo: 0.2188, hi: 0.6134)
        let b = EvalVerdicts.Side(label: "gpt-5-nano", right: 4, n: 20, lo: 0.0807, hi: 0.416)
        let c = try snake(EvalCompareResult.self, #"{"diff": 0.2, "ci95": [0.02, 0.38], "n": 20, "paired": true, "verdict": "a", "only_a": ["LAB-1829-e826106", "LAB-1828-a81fbcb", "LAB-1826-7604c8c", "LAB-1758-412b52f"], "only_b": [], "tied": 16}"#)
        let p = EvalsACompare.paired(c)
        XCTAssertEqual(p.shared, 20)
        XCTAssertEqual(EvalVerdicts.compare(a, b, paired: p, floor: 0.4).text, "Haiku is better, but only matches a blind guess")
        XCTAssertEqual(EvalVerdicts.compare(a, b, paired: p, floor: nil).text, "Haiku is better: +20 points (2 to 38)")
        XCTAssertEqual(EvalsACompare.onlyLine(c, a: "Haiku", b: "gpt-5-nano"),
                       "Only Haiku solved LAB-1829, LAB-1828, LAB-1826 and LAB-1758 · only gpt-5-nano solved none · 16 tied")
        let unpaired = EvalCompareResult(diff: 0.3, ci95: [0.1, 0.5], n: 20, paired: false, verdict: "a", onlyA: [], onlyB: [], tied: 0)
        XCTAssertEqual(EvalsACompare.paired(unpaired).shared, 0)
        XCTAssertEqual(EvalVerdicts.compare(a, b, paired: EvalsACompare.paired(unpaired)).text, "Never a winner under 10 shared bugs")
    }

    func test_LAB2242_A_agent_by_model_grid() throws {
        let g = EvalsAGrid.build(try fix())
        XCTAssertEqual(g.columns, ["claude-opus-5-5", "CLI default"])
        XCTAssertEqual(g.rows.map(\.title), ["Model on its own", "Claude Code", "Codex"])
        XCTAssertEqual(g.rows[0].cells["claude-opus-5-5"]?.label, "Opus, on its own")
        XCTAssertEqual(g.rows[1].cells["CLI default"]?.status, "waiting")
        XCTAssertTrue(g.rows[2].cells.isEmpty)
    }

    // MARK: E2.2 · one test

    func test_LAB2242_A_one_test_evidence_and_mark_line() throws {
        let s = try plain(EvalSample.self, #"{"id": "LAB-2094-56aa1af", "epoch": 1, "score": 0.0, "named": ["a/V2Layout.swift", "b/MainWindowController+V2.swift", "c/V2Places.swift"], "changed": ["a/V2Chrome.swift"]}"#)
        let e = EvalsAOneTest.evidence(s)
        XCTAssertEqual(e.named.count, 3); XCTAssertEqual(e.changed, ["a/V2Chrome.swift"])
        XCTAssertEqual(EvalsAOneTest.markLine(named: e.named, changed: e.changed, right: false),
                       "None of the 3 is a file the fix changed, so it's marked wrong. Checked automatically, no model involved.")
        XCTAssertEqual(EvalsAOneTest.markLine(named: ["x/A.swift", "x/B.swift"], changed: ["x/B.swift"], right: true),
                       "B.swift is a file the fix changed, so it's marked right. Checked automatically, no model involved.")
        // Before 2.0.4's named / changed: the code check's own lists.
        let old = try plain(EvalSample.self, #"{"id": "x", "epoch": 1, "score": 1.0, "code": {"verdict": "pass", "named": ["n.swift"], "changed": ["n.swift"]}}"#)
        XCTAssertEqual(EvalsAOneTest.evidence(old).named, ["n.swift"])
        let none = try plain(EvalSample.self, #"{"id": "y", "epoch": 1, "score": 1.0}"#)
        XCTAssertTrue(EvalsAOneTest.evidence(none).named.isEmpty)   // no sample text, ever
    }

    func test_LAB2242_A_run_stamp_rows_decode() throws {
        let xs = try snake([EvalsARunStamp].self, #"[{"id": "r1", "setup_id": "model:claude-opus-5-5", "stamp": {"recorded": false, "layer": "model", "model": "claude-opus-5-5", "task_version": 2}, "metrics": []}, {"id": "r2"}]"#)
        XCTAssertEqual(xs[0].setupId, "model:claude-opus-5-5"); XCTAssertEqual(xs[0].stamp?.taskVersion, 2)
        XCTAssertNil(xs[1].stamp)
    }

    // MARK: E2.3 · all results

    func test_LAB2242_A_all_results_our_tasks_first_grader_is_agreement() throws {
        let results = try plain([EvalResult].self, #"""
        [{"id": "1", "task": "gsm8k", "model": "anthropic/claude-haiku-5-5", "status": "done", "started": "2026-11-04T21:00:00Z", "metrics": []},
         {"id": "2", "task": "gsm8k", "model": "anthropic/claude-haiku-5-5", "status": "done", "started": "2026-10-31T21:00:00Z", "metrics": []},
         {"id": "3", "task": "own_oneroof_v2", "model": "anthropic/claude-opus-5-5", "status": "done", "metrics": [], "set_name": "oneroof", "set_version": 2},
         {"id": "4", "task": "judge_oneroof_triage_v1", "model": "anthropic/claude-sonnet-5-5", "status": "done", "metrics": []},
         {"id": "5", "task": "humaneval", "model": "mockllm/model", "status": "done", "metrics": []},
         {"id": "6", "task": "humaneval", "model": "anthropic/claude-haiku-5-5", "status": "failed", "metrics": []}]
        """#)
        let sets = try plain([EvalSetList.Entry].self, #"[{"name": "oneroof", "version": 2, "kind": "fix-locator", "repo": "oneroof", "count": 10, "built": "", "versions": 2, "taskFile": "/x.py"}]"#)
        let g = EvalsAAllGrid.build(results, sets: sets)
        XCTAssertEqual(g.columns.map(\.key), ["oneroof@v2", "judge_oneroof_triage_v1", "gsm8k", "humaneval"])
        XCTAssertEqual(g.columns.map(\.title), ["fix locator v2", "triage grader · agreement", "gsm8k", "humaneval"])
        XCTAssertEqual(g.columns.map(\.own), [true, true, false, false])
        XCTAssertEqual(g.columns.map(\.grader), [false, true, false, false])
        XCTAssertEqual(g.rows, ["claude-opus-5-5", "claude-sonnet-5-5", "claude-haiku-5-5", "mockllm/model"])   // who answered our tasks (or graded our notes) first
        XCTAssertEqual(g.cell("claude-haiku-5-5", "gsm8k")?.id, "1")   // the latest finished
        XCTAssertNil(g.cell("claude-haiku-5-5", "humaneval"))          // failed runs are not results
        XCTAssertEqual(g.finished, 5); XCTAssertEqual(g.tasks, 4)
    }

    func test_LAB2242_A_all_results_labeller_is_ours_but_not_agreement() throws {
        let results = try plain([EvalResult].self, #"[{"id": "l", "task": "labeller_oneroof_triage", "model": "anthropic/claude-sonnet-5-5", "status": "done", "metrics": []}]"#)
        let g = EvalsAAllGrid.build(results, sets: [])
        XCTAssertEqual(g.columns.map(\.title), ["triage labeller · share passed"])
        let mixed = try plain([EvalResult].self, #"""
        [{"id": "l", "task": "labeller_oneroof_triage", "model": "anthropic/claude-sonnet-5-5", "status": "done", "metrics": []},
         {"id": "s", "task": "own_oneroof_v1", "model": "anthropic/claude-haiku-5-5", "status": "done", "metrics": [], "set_name": "oneroof", "set_version": 1},
         {"id": "a", "task": "swe", "model": "anthropic/claude-haiku-5-5", "agent": "codex_cli", "status": "done", "metrics": [],
          "contestant": {"kind": "agent", "id": "codex_cli@x", "name": "Codex · claude-haiku-5-5 · claude-haiku-5-5", "agent": "codex_cli"}}]
        """#)
        let m = EvalsAAllGrid.build(mixed, sets: [])
        XCTAssertEqual(m.columns.map(\.key), ["oneroof@v1", "labeller_oneroof_triage", "swe"])   // our sets before the labeller
        XCTAssertTrue(m.rows.contains("Codex · claude-haiku-5-5"))
        XCTAssertEqual(g.columns.map(\.own), [true]); XCTAssertEqual(g.columns.map(\.grader), [false])
    }

    // MARK: E3 · Changes

    func test_LAB2242_A_changes_words_and_flips() throws {
        let cs = try snake([EvalChange].self, #"""
        [{"at": "2026-11-04T18:22:00Z", "who": "vendor", "what": "Claude Code's default model: claude-sonnet-5-5 → claude-opus-5-5", "path": null, "commit": null, "tested": {"before": "r1", "after": null}},
         {"at": "2026-11-02T10:00:00Z", "who": "you", "what": "CLAUDE.md changed", "path": "CLAUDE.md", "commit": "7b0b2bd", "tested": null}]
        """#)
        XCTAssertEqual(cs.map(EvalsAChanges.who), ["Vendor", "You"])
        XCTAssertEqual(cs.map(EvalsAChanges.status), ["tested before only", "no comparable before/after tests"])
        XCTAssertFalse(EvalsAChanges.canTell([try fix()]))   // no stamped agent test yet: "We can't tell yet"
        var lb = try fix(); lb.rows[0].stamp?.recorded = true; lb.rows[0].status = "done"
        XCTAssertTrue(EvalsAChanges.canTell([lb]))

        let before = ["A", "B", "C", "D"].map { EvalsASquare(id: $0, issue: $0, right: $0 == "A" || $0 == "B") }
        let after = ["A", "B", "C", "D"].map { EvalsASquare(id: $0, issue: $0, right: $0 != "B") }
        let f = EvalsASquares.flips(before: before, after: after)
        XCTAssertEqual(f.toRight, ["C", "D"]); XCTAssertEqual(f.toWrong, ["B"])
        XCTAssertEqual(f.after.map(\.flipped), [false, true, true, true]); XCTAssertEqual(f.before.map(\.flipped), [false, true, true, true])
        XCTAssertEqual(EvalsAChanges.flipLine(toRight: 2, toWrong: 1), "2 bugs flipped to right, 1 flipped to wrong.")
        XCTAssertEqual(EvalsAChanges.flipLine(toRight: 0, toWrong: 0), "No bug flipped.")

        let cant = EvalVerdicts.Verdict(kind: .cantTell, text: "Can't tell yet: about 50 bugs would settle it", winner: nil)
        XCTAssertEqual(EvalsAChanges.lead(diff: 0.2, verdict: cant), "Probably helped, not proven")
        XCTAssertEqual(EvalsAChanges.lead(diff: -0.1, verdict: cant), "Probably hurt, not proven")
        XCTAssertEqual(EvalsAChanges.lead(diff: 0.3, verdict: EvalVerdicts.Verdict(kind: .better, text: "", winner: "After")), "Helped")
        XCTAssertEqual(EvalsAChanges.lead(diff: 0, verdict: EvalVerdicts.Verdict(kind: .notRun, text: "", winner: nil)), "Not run yet")
    }

    // MARK: E4 · Real history

    func test_LAB2242_A_history_headline_split_and_untagged() {
        XCTAssertEqual(EvalsAHistory.top(Self.history)?.agent, "Claude")
        XCTAssertEqual(EvalsAHistory.pageHeadline(Self.history),
                       "123 of Claude's 657 commits (18.7 %) were followed by a fix. 1 was reverted (0.1 %). 111 commits carry no agent name, so other agents can't be read yet.")
        let s = EvalsAHistory.split(Self.history[0])
        XCTAssertEqual(s.fix, 123); XCTAssertEqual(s.rest, 534)
        XCTAssertNil(EvalsAHistory.top([Self.history[1]]))   // unattributed is never credited to an agent
        XCTAssertEqual(EvalsAHistory.pageHeadline([Self.history[1]]), "No commit names an agent yet, so no agent can be read.")
        XCTAssertEqual(EvalsAHistory.pageHeadline([]), "No commits in this window.")
        let one = EvalHistoryRow(agent: "Claude", commits: 385, fixup: 0.2857)
        XCTAssertTrue(EvalsAHistory.pageHeadline([one]).hasPrefix("110 of Claude's 385 commits (28.6 %) were followed by a fix."))
    }

    func test_LAB2242_A_history_rows_from_xray_json() throws {
        let x = try snake(EvalXRay.self, #"""
        {"window_days": 60, "horizon_days": 14, "computed": "2026-11-05T10:15:39Z", "repos": 3,
         "agents": {"Claude": {"commits": 657, "lines_added": 89202, "churn": 0.1091, "self_churn_share": 0.7479, "revert_rate": 0.0015, "fixup_rate": 0.1872},
                    "unattributed": {"commits": 111, "lines_added": 113820, "churn": 0.0675, "self_churn_share": 0.7669, "revert_rate": 0.0, "fixup_rate": 0.4234}}}
        """#)
        let rows = EvalHistoryRow.from(x)
        XCTAssertEqual(rows.map(\.agent), ["Claude", "unattributed"])
        XCTAssertEqual(rows[0].followedByFix, 123)
    }

    func test_LAB2242_A_test_vs_history_join() throws {
        let j = EvalsAHistory.join(try fix(), history: Self.history)
        XCTAssertEqual(j.map(\.setup), ["Claude Code · any model", "Codex · any model"])
        XCTAssertEqual(j[0].test, "Waiting since Nov 1: seat use unknown")
        XCTAssertEqual(j[0].history, "18.7 % followed by a fix · all models together")
        XCTAssertEqual(j[0].reading, "needs a finished test on this task")
        XCTAssertEqual(j[1].test, "not run"); XCTAssertEqual(j[1].history, "unsigned commits")
        XCTAssertEqual(j[1].reading, "needs signed commits (LAB-2241)")
        XCTAssertEqual(EvalsAHistory.join(nil, history: []).count, 2)
    }
}
