import XCTest
@testable import OneRoofCore

/// LAB-2242 · Evals v2 screen lane B: Set up a test's engine arguments (agent + model + seat + rules → argv, CONTRACT §2),
/// power and estimate wiring, Our tasks / One task / Check the grader view models (real numbers from this Mac's engine,
/// 2026-11-05), Public benchmarks' summary, and the coverage map (every 2.0.3 feature and self-test name has a home).
final class EvalsLaneBTests: XCTestCase {
    private func snake<T: Decodable>(_ t: T.Type, _ json: String) throws -> T {
        let d = JSONDecoder(); d.keyDecodingStrategy = .convertFromSnakeCase
        return try d.decode(T.self, from: Data(json.utf8))
    }
    private let set2 = "/x/evals/sets/oneroof/v2/own_oneroof_v2.py"

    // MARK: Set up a test: argv (CONTRACT §2)

    func test_LAB2242_seat_on_cli_default_passes_no_model_and_no_rules_flag() {
        let plan = EvalRunPlan(tasks: [set2], models: [], limit: 10)
        let c = EvalSetupChoice.seat("claude_code")
        XCTAssertEqual(c.runArguments(task: set2, plan: plan, seatLimit: 90),
                       ["run", set2, "--agent", "claude_code", "--seat", "C1", "--seat-limit", "90", "--limit", "10", "--background", "--json"])
        XCTAssertEqual(c.label, "Claude Code on its CLI default model")
        XCTAssertEqual(c.layer, .agentModel)
        XCTAssertEqual(c.id, "claude_code:default:off")
    }

    func test_LAB2242_seat_with_a_chosen_model_passes_it_to_the_cli_without_the_provider() {
        let plan = EvalRunPlan(tasks: [set2], models: [], limit: 10, epochs: 3)
        let c = EvalSetupChoice.seat("claude_code", model: "anthropic/claude-opus-5-5")
        let a = c.runArguments(task: set2, plan: plan, seatLimit: 85)
        XCTAssertEqual(a, ["run", set2, "--agent", "claude_code", "--seat", "C1", "--seat-limit", "85", "--limit", "10",
                           "--model", "claude-opus-5-5", "--epochs", "3", "--background", "--json"])
        XCTAssertEqual(c.label, "Claude Code using Opus")
        XCTAssertEqual(c.id, "claude_code:claude-opus-5-5:off")
    }

    func test_LAB2242_rules_on_is_the_full_setup_and_passes_rules_on() {
        let plan = EvalRunPlan(tasks: [set2], models: [], limit: 10)
        let c = EvalSetupChoice.seat("codex_cli", model: "openai/gpt-5-mini", rules: true)
        XCTAssertEqual(c.runArguments(task: set2, plan: plan),
                       ["run", set2, "--agent", "codex_cli", "--seat", "CX", "--seat-limit", "90", "--limit", "10",
                        "--model", "gpt-5-mini", "--rules", "on", "--background", "--json"])
        XCTAssertEqual(c.layer, .full)
        XCTAssertEqual(c.label, "Codex using GPT-5 mini, with our rules")
        XCTAssertEqual(c.id, "codex_cli:gpt-5-mini:on")
        XCTAssertEqual(c.runsOnText, "seat CX")
        XCTAssertEqual(c.runsOnStamp, "seat:CX")
    }

    func test_LAB2242_rules_are_never_on_for_a_model_or_an_agent_on_an_api_key() {
        XCTAssertFalse(EvalSetupChoice(agent: nil, model: "anthropic/claude-opus-5-5", runsOn: .api, rules: true).rules)
        XCTAssertFalse(EvalSetupChoice(agent: "claude_code", model: "anthropic/claude-haiku-5-5", runsOn: .api, rules: true).rules)
    }

    func test_LAB2242_models_and_api_agents_keep_2_0_3_arguments_exactly() {
        let plan = EvalRunPlan(tasks: ["gsm8k"], models: [], limit: 5, epochs: 2, seed: 7, temperature: 0.2, cap: 0.5, place: "modal", sampleID: "q1")
        let m = EvalSetupChoice.model("anthropic/claude-opus-5-5")
        XCTAssertEqual(m.runArguments(task: "gsm8k", plan: plan), plan.arguments(task: "gsm8k", contestant: .model("anthropic/claude-opus-5-5")))
        XCTAssertEqual(m.estimateArguments(task: "gsm8k", plan: plan), plan.estimateArguments(task: "gsm8k", contestant: .model("anthropic/claude-opus-5-5")))
        let api = EvalSetupChoice.apiAgent("codex_cli", model: "anthropic/claude-haiku-5-5")
        XCTAssertEqual(api.runArguments(task: "gsm8k", plan: plan),
                       plan.arguments(task: "gsm8k", contestant: .apiAgent(agent: "codex_cli", model: "anthropic/claude-haiku-5-5")))
        XCTAssertEqual(m.label, "Opus, on its own")
        XCTAssertEqual(m.id, "model:claude-opus-5-5")
        XCTAssertEqual(m.layer, .model)
        XCTAssertEqual(api.id, "codex_cli:claude-haiku-5-5:off@api")
        XCTAssertEqual(api.runsOnText, "API key · anthropic")
        XCTAssertEqual(EvalSetupChoice.model("mockllm/model").runsOnStamp, "stand-in")
        XCTAssertEqual(EvalSetupChoice.model("ollama/qwen3:1.7b").runsOnText, "this Mac")
    }

    func test_LAB2242_seat_sample_id_and_estimate_arguments() {
        let plan = EvalRunPlan(tasks: [set2], models: [], limit: 1, sampleID: "LAB-2088-4e2a7a8")
        let c = EvalSetupChoice.seat("claude_code", model: "claude-sonnet-5-5")
        XCTAssertEqual(Array(c.runArguments(task: set2, plan: plan).suffix(4)), ["--sample-id", "LAB-2088-4e2a7a8", "--background", "--json"])
        XCTAssertEqual(c.estimateArguments(task: set2, plan: plan),
                       ["estimate", set2, "--limit", "1", "--epochs", "1", "--agent", "claude_code", "--seat", "C1", "--seat-limit", "90",
                        "--model", "claude-sonnet-5-5", "--json"])
        XCTAssertFalse(EvalSetupChoice.seat("claude_code").estimateArguments(task: set2, plan: plan).contains("--model"))
    }

    func test_LAB2242_setups_from_a_2_0_3_plan_and_models_per_agent() {
        let p = EvalRunPlan(tasks: [set2], models: ["openai/gpt-5"], agents: ["claude_code", "codex_cli"], apiAgents: ["claude_code@anthropic/claude-haiku-5-5"])
        XCTAssertEqual(EvalSetupChoice.from(p).map(\.id),
                       ["claude_code:default:off", "codex_cli:default:off", "claude_code:claude-haiku-5-5:off@api", "model:gpt-5"])
        XCTAssertNil(EvalSetupChoice.models(for: "claude_code").first!)   // CLI default first
        XCTAssertTrue(EvalSetupChoice.models(for: "claude_code").contains("anthropic/claude-opus-5-5"))
        XCTAssertTrue(EvalSetupChoice.models(for: "codex_cli").contains("openai/gpt-5"))
        XCTAssertTrue(EvalSetupChoice.notYetLine.contains("Kimi") && EvalSetupChoice.notYetLine.contains("Gemini CLI")
                      && EvalSetupChoice.notYetLine.contains("Antigravity") && EvalSetupChoice.notYetLine.contains("OpenCode"))
    }

    func test_LAB2242_stamp_preview_names_every_part() {
        let off = EvalSetupChoice.seat("claude_code").stampPreview(taskVersion: 2, rulesHash: nil)
        XCTAssertTrue(off.hasPrefix("The agent using a model · CLI default"))
        XCTAssertTrue(off.contains("Claude Code (its version is read at start)"))
        XCTAssertTrue(off.contains("rules off"))
        XCTAssertTrue(off.hasSuffix("· v2"))
        let on = EvalSetupChoice.seat("claude_code", model: "claude-opus-5-5", rules: true)
            .stampPreview(taskVersion: 2, rulesHash: "a1b2c3d", rulesFiles: ["app/CLAUDE.md", "templates/shared/AGENTS.md"])
        XCTAssertTrue(on.contains("rules on @ a1b2c3d (app/CLAUDE.md, templates/shared/AGENTS.md)"))
        XCTAssertTrue(on.hasPrefix("Your full setup · claude-opus-5-5"))
        XCTAssertEqual(EvalSetupChoice.model("anthropic/claude-haiku-5-5").stampPreview(taskVersion: nil, rulesHash: nil),
                       "The model · claude-haiku-5-5 · task version")
    }

    func test_LAB2242_start_stays_off_for_the_right_reason() {
        let own: (String) -> Bool = EvalRunPlan.isOwnSet
        XCTAssertEqual(EvalSetupCheck.reason(tasks: [], choices: [.seat("claude_code")], isOwn: own, missingKeys: []), "Pick a task")
        XCTAssertEqual(EvalSetupCheck.reason(tasks: [set2], choices: [], isOwn: own, missingKeys: []), "Pick at least one setup")
        XCTAssertEqual(EvalSetupCheck.reason(tasks: ["gsm8k"], choices: [.seat("claude_code")], isOwn: own, missingKeys: []),
                       "Agents on your seats answer your own tasks: untick \(EvalBenchmark.taskLabel("gsm8k")) or the agents")
        XCTAssertNil(EvalSetupCheck.reason(tasks: ["gsm8k"], choices: [.apiAgent("claude_code", model: "anthropic/claude-haiku-5-5")], isOwn: own, missingKeys: []))
        let ch: [EvalSetupChoice] = [.model("openai/gpt-5"), .model("mockllm/model"), .seat("codex_cli")]
        XCTAssertEqual(EvalSetupCheck.missingKeys(ch, ready: ["anthropic"]), ["openai"])
        XCTAssertEqual(EvalSetupCheck.reason(tasks: [set2], choices: ch, isOwn: own, missingKeys: ["openai"]),
                       "No key for openai: roof eval providers set openai --key-file PATH")
        XCTAssertEqual(EvalSetupCheck.reason(tasks: [set2], choices: [.seat("claude_code")], isOwn: own, missingKeys: [], fullSeats: ["C1"]),
                       "C1 is too full for this test: wait for its 5-hour window")
        XCTAssertEqual(EvalSetupCheck.reason(tasks: [set2], choices: [.model("openai/gpt-5")], isOwn: own, missingKeys: [], overCap: true),
                       "Over the cap: lower the bugs or raise Stop at")
    }

    // MARK: Power before cost, estimate wiring

    func test_LAB2242_what_this_test_can_tell_you_comes_from_power() throws {
        let p = try snake(EvalPower.self, #"{"epochs": 1, "method": "wilson", "n": 10, "p": 0.5, "paired": false, "plus_minus_points": 26.3}"#)
        XCTAssertEqual(EvalCanTell.line(p, own: true, setups: 2).prefix(31), "10 bugs × 1 try ≈ ±26 points, s")
        XCTAssertTrue(EvalCanTell.line(p, own: true, setups: 2).contains("Everyone gets the same bugs"))
        XCTAssertEqual(EvalPower.mirror(n: 10, epochs: 1).plusMinusPoints.rounded(), 26)   // the mirror matches the engine
        XCTAssertEqual(EvalPower.mirror(n: 52, epochs: 1).plusMinusPoints.rounded(), 13)
        XCTAssertTrue(EvalCanTell.line(EvalPower.mirror(n: 5, epochs: 3), own: false, setups: 1).hasPrefix("5 questions × 3 tries"))
    }

    func test_LAB2242_seat_estimate_never_shows_a_guessed_share() throws {
        let guess = try snake(EvalSetupEstimate.self, #"{"agent": "claude_code", "api_cost": 0.0, "cases": 10, "runs_on": "seat:C1", "seat": "C1", "seat_basis": "guess", "seat_share": 0.03, "seat_note": "No API cost. It uses your C1 seat; its share of the 5-hour window is not measured yet."}"#)
        XCTAssertNil(guess.measuredShare)
        XCTAssertEqual(guess.runsOn, "seat:C1")
        XCTAssertEqual(guess.apiCost, 0)
        XCTAssertEqual(guess.cases, 10)
        XCTAssertTrue(guess.seatNote?.contains("not measured yet") == true)
        let measured = try snake(EvalSetupEstimate.self, #"{"seat_basis": "measured", "seat_share": 0.061}"#)
        XCTAssertEqual(measured.measuredShare, 0.061)
    }

    func test_LAB2242_rules_hash_matches_the_engine() {
        let ls = "README.md\napp/CLAUDE.md\ntemplates/workspace/CLAUDE.md\ntemplates/shared/AGENTS.md\nAGENTS.md.bak\ndocs/CLAUDE.local.md\n"
        XCTAssertEqual(EvalRulesHash.files(lsTree: ls), ["app/CLAUDE.md", "docs/CLAUDE.local.md", "templates/shared/AGENTS.md", "templates/workspace/CLAUDE.md"])
        // sha256 over the files' bytes in path order, first 7 hex (python: hashlib.sha256(b"# A\n" + b"# B\n").hexdigest()[:7])
        XCTAssertEqual(EvalRulesHash.short([Data("# A\n".utf8), Data("# B\n".utf8)]), "ffae83f")
        XCTAssertNil(EvalRulesHash.short([]))
    }

    // MARK: Our tasks · One task

    func test_LAB2242_task_words_are_plain_and_both_kinds_are_checked_by_code() {
        XCTAssertEqual(EvalTaskWords.title(kind: "fix-locator"), "Find the files a bug fix needs")
        XCTAssertEqual(EvalTaskWords.title(kind: "triage"), "Write a useful note on a new bug")
        XCTAssertTrue(EvalTaskWords.howItWorks(kind: "triage").contains("Checked by code"))
        XCTAssertFalse(EvalTaskWords.howItWorks(kind: "triage").lowercased().contains("grading model reads"))
        XCTAssertTrue(EvalTaskWords.howItWorks(kind: "fix-locator").contains("Right if one is a file the fix changed"))
        XCTAssertEqual(EvalTaskWords.meta(kind: "fix-locator", version: 2, frozen: "2026-11-01T16:30:28Z"), "fix locator · version 2, frozen Nov 1")
        XCTAssertEqual(EvalTaskWords.guessText(right: 5, of: 10), "5 of 10 · 50 %")
        XCTAssertEqual(EvalTaskWords.contestant("claude-opus-5-5"), "Opus, on its own")
        XCTAssertEqual(EvalTaskWords.contestant("Claude Code · C1"), "Claude Code · C1")
        XCTAssertEqual(EvalTaskWords.model("openai/gpt-5-nano"), "GPT-5 nano")
    }

    func test_LAB2242_layer_chips_count_this_version_only() throws {
        let results = try JSONDecoder().decode([EvalResult].self, from: Data(#"""
        [{"id": "a", "task": "own_oneroof_v2", "status": "done", "model": "anthropic/claude-opus-5-5", "metrics": [], "contestant": {"kind": "model", "id": "anthropic/claude-opus-5-5", "name": "claude-opus-5-5"}},
         {"id": "b", "task": "own_oneroof_v1", "status": "done", "model": "anthropic/claude-haiku-5-5", "metrics": [], "contestant": {"kind": "model", "id": "h", "name": "h"}},
         {"id": "c", "task": "own_oneroof_v2", "status": "done", "model": "mockllm/model", "metrics": [], "contestant": {"kind": "baseline", "id": "m", "name": "m"}}]
        """#.utf8))
        let runs = try JSONDecoder().decode([EvalRunRow].self, from: Data(#"""
        [{"id": "w", "task": "own_oneroof_v2", "status": "waiting", "progress": "0/10", "agent": "claude_code", "seat": "C1", "contestant": {"kind": "agent", "id": "seat:claude_code", "name": "Claude Code · C1"}}]
        """#.utf8))
        let chips = EvalTaskCoverage.chips(name: "oneroof", version: 2, results: results, runs: runs)
        XCTAssertEqual(chips.map(\.text), ["1 tested", "1 waiting", "not recorded"])
        XCTAssertEqual(chips.map(\.title), ["The model", "Agent using a model", "Full setup"])
        XCTAssertTrue(chips[2].isGap)
        let full = EvalTaskCoverage.chips(name: "oneroof", version: 2, results: results, runs: [], rulesOn: ["a"])
        XCTAssertEqual(full[0].text, "1 tested")   // a model run is never the full setup
        XCTAssertEqual(EvalTaskCoverage.chips(name: "oneroof", version: 1, results: results, runs: runs).map(\.text), ["1 tested", "not tested", "not recorded"])
    }

    func test_LAB2242_next_version_uses_the_dry_runs_real_counts() throws {
        let fresh = try snake(EvalBuildPreview.self, #"{"name": "oneroof", "next_version": 3, "repo": "/r", "days": 120, "kind": "fix-locator", "report_source": "commit subjects", "kept": 0, "new": [], "total": 52, "written": false, "left_out": {"leak": 11, "not_a_fix": 50, "not_fixed": 0, "too_many_files": 115}, "considered": 114}"#)
        XCTAssertEqual(EvalNextVersion.headline(fresh, extend: false), "52 usable fixes in the last 120 days.")
        XCTAssertEqual(fresh.leftOutText, "Left out on purpose: 11 reports that already name the file (too easy), 115 fixes touching more than 3 source files, 50 commits that are not a fix.")
        XCTAssertEqual(EvalNextVersion.sourceNote(fresh, current: 2, currentSource: "Linear issues"),
                       "Bug reports for v3 come from commit subjects (v2's came from Linear issues). It is a new version of the same task: v2 stays frozen and results never mix versions.")
        XCTAssertEqual(EvalNextVersion.powerNote(current: 2, currentN: 10, next: 3, nextN: 52), "v2's 10 bugs tell setups apart to about ±26 points; v3's 52 would give ±13.")
        let ext = try snake(EvalBuildPreview.self, #"{"name": "oneroof", "base_version": 2, "next_version": 3, "repo": "/r", "days": 120, "report_source": "commit subjects", "kept": 10, "new": [{"id": "LAB-2199-1999607", "issue": "LAB-2199", "report": "r", "files": ["a.py"]}], "total": 11, "left_out": {}, "considered": 59, "written": false}"#)
        XCTAssertEqual(EvalNextVersion.headline(ext, extend: true), "1 bug fixed since v2.")
        XCTAssertEqual(EvalNextVersion.source(linear: 0, subject: 10), "commit subjects")
        XCTAssertNil(EvalNextVersion.source(linear: nil, subject: nil))
        XCTAssertEqual(EvalNextVersion.buildArguments(name: "oneroof", repo: "/r", kind: "fix-locator", days: 120, extend: true, count: nil, keyFile: nil, dryRun: true),
                       ["evalset", "build", "--name", "oneroof", "--extend", "--days", "120", "--repo", "/r", "--dry-run"])
        XCTAssertEqual(EvalNextVersion.buildArguments(name: "oneroof", repo: "/r", kind: "fix-locator", days: 120, extend: false, count: 52, keyFile: "/k", dryRun: false),
                       ["evalset", "build", "--name", "oneroof", "--kind", "fix-locator", "--count", "52", "--days", "120", "--repo", "/r", "--linear-key-file", "/k"])
    }

    func test_LAB2242_best_so_far_against_the_blind_guess() {
        // Opus 8 of 10 vs a guess of 5: range 49–94 % touches 50 % → too few bugs to be sure (BRIEF).
        let w = EvalStats.wilson(0.8, n: 10)
        let v = EvalVerdicts.againstFloor(.init(label: "Opus, on its own", right: 8, n: 10, lo: w.lo, hi: w.hi), floor: 0.5)
        XCTAssertEqual(v?.text, "Too few bugs to be sure it beats a blind guess")
        // Triage v1: Haiku 8 of 20 = a blind guess of 8 of 20.
        let h = EvalStats.wilson(0.4, n: 20)
        XCTAssertEqual(EvalVerdicts.againstFloor(.init(label: "Haiku, on its own", right: 8, n: 20, lo: h.lo, hi: h.hi), floor: 0.4)?.kind, .tooFewVsFloor)
    }

    // MARK: Check the grader

    private let trustJSON = #"{"name": "oneroof_triage", "mode": "single", "items": 40, "labelled": 0, "to_label": 40, "examples": 10, "run": "20261031-203836-judge_oneroof_triage_v1-oepe", "judge_model": "openai/gpt-5-mini", "version": 1, "min_held": 10, "reference": "model", "n": 30, "agreement": 0.7, "tpr": 0.8667, "tnr": 0.5333, "label_pass": 15, "label_fail": 15, "held_back_yours": 0, "judged_pass_rate": 0.575, "ready": false, "reading": "It's lenient."}"#

    func test_LAB2242_grader_tiles_and_verdict_from_real_numbers() throws {
        let tr = try snake(EvalJudgeTrust.self, trustJSON)
        XCTAssertEqual(EvalJudgeTrust.pct(tr.agreement), "70 %")
        XCTAssertEqual(EvalJudgeTrust.pct(tr.tpr), "87 %")
        XCTAssertEqual(EvalJudgeTrust.pct(tr.tnr), "53 %")
        XCTAssertEqual(EvalGraderWords.ofText(tr.agreement, tr.n), "21 of 30")
        XCTAssertEqual(EvalGraderWords.ofText(tr.tpr, tr.labelPass ?? 0), "13 of 15")
        XCTAssertEqual(EvalGraderWords.ofText(tr.tnr, tr.labelFail ?? 0), "8 of 15")
        XCTAssertEqual(EvalGraderWords.verdictTitle(tr), "Not trusted yet")
        XCTAssertEqual(EvalGraderWords.verdictBody(tr),
                       "It's lenient: it passes 47 % of the notes that should fail, so its scores read high. And these labels came from another model, not you. Label 10 notes yourself to check it.")
        XCTAssertEqual(EvalGraderWords.subtitle(items: 40, model: tr.judgeModel, version: 1, n: 30),
                       "Grades 40 notes · grading model gpt-5-mini · v1 · checked against 30 held-back labels")
        let b = try XCTUnwrap(EvalGraderWords.banner(tr))
        XCTAssertTrue(b.hasPrefix("It passes 47 % of notes that should fail."))
        XCTAssertTrue(b.contains("still checked by code"))
        XCTAssertTrue(b.hasSuffix("Label 10 notes yourself to check it."))
    }

    func test_LAB2242_a_trusted_grader_has_no_banner_and_an_unmeasured_one_says_so() throws {
        var tr = try snake(EvalJudgeTrust.self, trustJSON)
        tr.ready = true; tr.tnr = 0.9; tr.reference = "you"; tr.heldBackYours = 12
        XCTAssertNil(EvalGraderWords.banner(tr))
        XCTAssertEqual(EvalGraderWords.verdictTitle(tr), "Trusted for now")
        XCTAssertEqual(EvalGraderWords.verdictBody(tr), "It agrees with the labels 70 % of the time.")
        tr.run = nil
        XCTAssertTrue(EvalGraderWords.verdictBody(tr).hasPrefix("Not measured yet"))
    }

    // MARK: Public benchmarks

    private func bench(_ folder: String, title: String, madeOf: String, shelf: String? = nil) throws -> EvalBenchmark {
        var o: [String: Any] = ["folder": folder, "title": title, "category": "Knowledge", "description": "d", "sandbox": false, "tags": [],
                                "tasks": [["name": folder, "samples": 100]], "starter": [], "made_of": madeOf]
        if let s = shelf { o["shelf"] = s }
        return try JSONDecoder().decode(EvalBenchmark.self, from: JSONSerialization.data(withJSONObject: o))
    }

    func test_LAB2242_public_benchmarks_table_uses_this_macs_runs() throws {
        let cat = [try bench("gsm8k", title: "GSM8K", madeOf: "Grade-school maths word problems"),
                   try bench("hle", title: "Humanity's Last Exam", madeOf: "Expert questions"),
                   try bench("mmlu_pro", title: "MMLU-Pro", madeOf: "Exam questions"),
                   try bench("swe_bench_verified_mini", title: "SWE-bench Verified mini", madeOf: "Fix real GitHub issues", shelf: "agent")]
        let results = try JSONDecoder().decode([EvalResult].self, from: Data(#"""
        [{"id": "g1", "task": "gsm8k", "status": "done", "model": "anthropic/claude-haiku-5-5", "metrics": [{"scorer": "match", "metric": "accuracy", "value": 1.0, "n": 5, "ci_method": "wilson"}], "contestant": {"kind": "model", "id": "anthropic/claude-haiku-5-5", "name": "claude-haiku-5-5"}},
         {"id": "g0", "task": "gsm8k", "status": "done", "model": "mockllm/model", "metrics": [{"scorer": "match", "metric": "accuracy", "value": 0.0, "n": 5, "ci_method": "wilson"}], "contestant": {"kind": "baseline", "id": "m", "name": "m"}},
         {"id": "h1", "task": "hle", "status": "done", "model": "anthropic/claude-haiku-5-5", "metrics": [{"scorer": "j", "metric": "accuracy", "value": 1.0, "n": 2, "ci_method": "wilson"}], "contestant": {"kind": "model", "id": "h", "name": "claude-haiku-5-5", "model": "anthropic/claude-haiku-5-5"}},
         {"id": "s1", "task": "swe_bench_verified_mini", "status": "failed", "model": "anthropic/claude-haiku-5-5", "metrics": [], "contestant": {"kind": "agent", "id": "a", "name": "Claude Code · claude-haiku-5-5"}},
         {"id": "s2", "task": "swe_bench_verified_mini", "status": "done", "model": "anthropic/claude-haiku-5-5", "metrics": [{"scorer": "t", "metric": "accuracy", "value": 0.0, "n": 2, "ci_method": "wilson"}], "contestant": {"kind": "agent", "id": "b", "name": "Codex · claude-haiku-5-5"}}]
        """#.utf8))
        let rows = EvalBenchmarkSummaryRow.rows(catalog: cat, results: results)
        XCTAssertEqual(rows.map(\.name), ["GSM8K", "Humanity's Last Exam", "SWE-bench Verified mini"])   // not run: left out
        XCTAssertEqual(rows.map(\.bestRun), ["Haiku 5 of 5", "Haiku 2 of 2", "2 runs"])
        XCTAssertEqual(rows.map(\.layer), [.model, .model, .agentModel])
        XCTAssertEqual(rows[0].tests, "Grade-school maths word problems")
        XCTAssertEqual(EvalBenchmarkSummaryRow.smallNote(rows),
                       "Your runs used 2–5 questions: too few to mean much. A score on 5 questions could be anything from 57 to 100 %.")
        let pub = try snake(EvalPublishedScores.self, #"{"benchmark": "gsm8k", "has_source": true, "source": {"name": "Meta", "url": "u"}, "rows": [{"checked": "2026-11-01", "contestant": "Llama 3.1 405B Instruct", "kind": "model", "score": 0.968, "source_name": "Meta", "source_url": "u"}]}"#)
        XCTAssertEqual(EvalBenchmarkSummaryRow.published(pub), "97 % (Llama 3.1 405B Instruct)")
        XCTAssertEqual(EvalBenchmarkSummaryRow.published(nil), "—")
        // A score that is not a proportion (NIAH's 9.9 on 10) never reads as "99 of 10".
        let niah = try JSONDecoder().decode([EvalResult].self, from: Data(#"[{"id": "n1", "task": "niah", "status": "done", "model": "anthropic/claude-haiku-5-5", "metrics": [{"scorer": "s", "metric": "mean", "value": 9.9, "n": 10, "ci_method": "t"}], "contestant": {"kind": "model", "id": "h", "name": "claude-haiku-5-5"}}]"#.utf8))
        XCTAssertEqual(EvalBenchmarkSummaryRow.rows(catalog: [try bench("niah", title: "NIAH", madeOf: "m")], results: niah).map(\.bestRun), ["1 run"])
    }

    // MARK: Coverage map

    /// NO_REGRESSION.md (handover, 2026-11-05): every row.
    private let noRegression = [
        "How to: 8 scenes, narration, read marks", "Overview scorecards per eval", "Hover card on every number + Lesson ›",
        "Overview: what changed since last time", "Overview: running now", "Overview: one suggested next eval",
        "Setup card: install engine with uv, uv/Docker status", "Busy and error lines", "Subtitle counts", "Your evals: set page facts",
        "Cases table, solved by, sort", "Build next version: settings, left out on purpose, preview, freeze", "Versions list",
        "Start a new one: from fixed bugs (+ CLI)", "Judge: Label queue, P/F/S, Why, undo", "Judge: How far to trust it, what would help, also checked",
        "Judge: Rubric, Agreement, Versions, Rebuild v2", "Explore: shelves, topics, more topics, graded by, filters, search, rescan",
        "Benchmark: facts, how one question is scored, on this Mac, teaches, watch out, needs, cost, paper, source",
        "Benchmark: Questions (load prompt, gated sets)", "Benchmark: Published scores, Check now", "Benchmark: Your runs",
        "Run: What (sets, benchmarks, tasks, any benchmark)", "Run: Who (agents with seat %, API models, on this Mac, any model id, agent on API model)",
        "Run: How much (questions, attempts, temperature, seed, cap, advanced)", "Run: What this run can tell you",
        "Run: Cost before you start, seat share, cap ×1.5, Start N", "Run: Queue (two at a time, Run anyway, Cancel, Resume, Results, show all)",
        "Results: By eval leaderboard, version switch", "Results: Compare A vs B, paired verdict, see the N cases",
        "Results: Over time, possible drop, re-run ×3", "Results: All × all + every run", "Results: X-ray", "Results: Export CSV · JSON",
        "Run detail: facts, score strip, answers list, filters, sort",
        "Run detail: code check · judge · you, add to regression set, compare with, run again",
        "Learn: 16 lessons, Try it, In your runs, first eval steps, where this shows up", "Keys, Hugging Face sign-in, providers",
        "Second Draft banner on drill-downs",
    ]

    func test_LAB2242_every_no_regression_row_has_a_home() {
        let features = Set(EvalsCoverage.rows.map(\.feature))
        for f in noRegression { XCTAssertTrue(features.contains(f), f) }
        XCTAssertEqual(EvalsCoverage.rows.count, Set(EvalsCoverage.rows.map(\.id)).count, "one row per feature")
        XCTAssertEqual(EvalsCoverage.rows.filter { $0.status == .removed }.map(\.feature), ["Second Draft banner on drill-downs"])
        for r in EvalsCoverage.rows { XCTAssertFalse(r.home.isEmpty, r.feature) }
    }

    func test_LAB2242_every_screen_is_some_features_home_and_v1_additions_are_mapped() {
        let homes = Set(EvalsCoverage.rows.compactMap(\.screen))
        for s in EvalsScreen.allCases { XCTAssertTrue(homes.contains(s), s.rawValue) }
        let added = EvalsCoverage.rows.filter { $0.status == .added }.map(\.feature).joined(separator: " | ")
        for k in ["stamp", "rules on/off", "Agent and model picked together", "Verdicts by rule", "power"] {
            XCTAssertTrue(added.lowercased().contains(k.lowercased()), k)
        }
    }

    func test_LAB2242_every_old_selftest_name_still_opens_a_screen() {
        for n in EvalsCoverage.oldSelfTestNames { XCTAssertNotNil(EvalsScreen.selfTest(n), n) }
        for s in EvalsScreen.allCases { XCTAssertNotNil(EvalsScreen.selfTest(s.selfTestName), s.selfTestName) }
    }

    func test_LAB2242_the_coverage_doc_lists_every_row() throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("docs/evals-v2-coverage.md")
        let doc = try String(contentsOf: url, encoding: .utf8)
        for r in EvalsCoverage.rows {
            XCTAssertTrue(doc.contains("| \(r.feature) | \(r.was) | \(r.home) | \(r.status.rawValue) |"), r.feature)
        }
        for n in EvalsCoverage.oldSelfTestNames { XCTAssertTrue(doc.contains("`\(n)`"), n) }
        XCTAssertFalse(doc.contains("/Users/"), "public repo: no private paths")
    }
}
