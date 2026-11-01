import XCTest
@testable import OneRoofCore

/// LAB-2061 stage 2 · Run (LAB-2067), Results (LAB-2068), one run (LAB-2069): the plan's engine arguments, why Start is
/// disabled, the ± points (locked to the engine's `power`), compare parity with the engine, the words of a verdict, the
/// Results index, and the per-answer verdicts. JSON is shaped exactly as the engine prints it (captured, trimmed).
final class EvalsRunResultsTests: XCTestCase {
    private func snake<T: Decodable>(_ t: T.Type, _ json: String) throws -> T {
        let d = JSONDecoder(); d.keyDecodingStrategy = .convertFromSnakeCase
        return try d.decode(T.self, from: Data(json.utf8))
    }
    private let fixLocator = "/Users/x/Library/Application Support/One Roof/evals/sets/oneroof/v1/own_oneroof_v1.py"

    // MARK: Run (LAB-2067)

    func test_LAB2067_agents_first_then_api_agents_then_models() {
        let p = EvalRunPlan(tasks: [fixLocator], models: ["anthropic/claude-haiku-5-5", "openai/gpt-5-mini"],
                            agents: ["claude_code", "codex_cli"], apiAgents: ["claude_code@anthropic/claude-haiku-5-5"])
        XCTAssertEqual(p.contestants.map(\.name), ["Claude Code", "Codex", "Claude Code · claude-haiku-5-5", "claude-haiku-5-5", "gpt-5-mini"])
        XCTAssertEqual(p.runCount, 5)   // Claude Code + Codex + two models (+ one agent on an API model) on fix locator in one go
    }

    func test_LAB2067_plan_to_engine_arguments() {
        var p = EvalRunPlan(tasks: ["gsm8k"], models: ["openai/gpt-5-mini"], limit: 20, epochs: 3, seed: 7, temperature: 0.5, cap: 1.5,
                            taskArgs: "fewshot=0", place: "daytona", agents: ["claude_code"])
        XCTAssertEqual(p.arguments(task: "gsm8k", contestant: .model("openai/gpt-5-mini")),
                       ["run", "gsm8k", "--model", "openai/gpt-5-mini", "--limit", "20", "--max-cost", "1.5", "--epochs", "3", "--seed", "7",
                        "--temperature", "0.5", "--task-args", "fewshot=0", "--where", "daytona", "--background", "--json"])
        XCTAssertEqual(p.arguments(task: fixLocator, contestant: .seat(agent: "claude_code"), seatLimit: 90),
                       ["run", fixLocator, "--agent", "claude_code", "--seat", "C1", "--seat-limit", "90", "--limit", "20", "--epochs", "3",
                        "--background", "--json"])   // a seat: no dollars, no seed/temperature (the CLI decides), no sandbox
        XCTAssertEqual(p.arguments(task: "swe_bench_verified_mini", contestant: .apiAgent(agent: "codex_cli", model: "openai/gpt-5")).prefix(6),
                       ["run", "swe_bench_verified_mini", "--model", "openai/gpt-5", "--agent", "codex_cli"])
        p.sampleID = "q7"
        XCTAssertTrue(p.arguments(task: "gsm8k", contestant: .model("m/x")).contains("--sample-id"))
        XCTAssertEqual(p.estimateArguments(task: fixLocator, contestant: .seat(agent: "codex_cli")),
                       ["estimate", fixLocator, "--limit", "20", "--epochs", "3", "--agent", "codex_cli", "--seat", "CX", "--seat-limit", "90", "--json"])
    }

    func test_LAB2067_start_is_disabled_with_the_reason() {
        let ok = EvalRunPlan(tasks: ["gsm8k"], models: ["openai/gpt-5-mini"])
        func why(_ p: EvalRunPlan, overCap: Bool = false, keys: [String] = [], sandbox: Bool = false, ready: Bool = true, full: [String] = []) -> String? {
            EvalStartCheck.reason(plan: p, overCap: overCap, missingKeys: keys, sandbox: sandbox, placeReady: ready, place: "local", fullSeats: full)
        }
        XCTAssertNil(why(ok))
        XCTAssertEqual(why(EvalRunPlan(tasks: [], models: ["m/x"])), "Pick what and who")
        XCTAssertEqual(why(EvalRunPlan(tasks: ["gsm8k"], models: [])), "Pick what and who")
        XCTAssertEqual(why(ok, overCap: true), "Over the cap: lower the questions or raise the cap")
        XCTAssertEqual(why(ok, keys: ["openai"]), "No key for openai: roof eval providers set openai --key-file PATH")
        XCTAssertEqual(why(ok, sandbox: true, ready: false), "Docker is stopped: start Docker first")
        XCTAssertEqual(why(EvalRunPlan(tasks: [fixLocator], models: [], agents: ["claude_code"]), full: ["C1"]),
                       "C1 is too full for this run: wait for its 5-hour window")
        XCTAssertEqual(why(EvalRunPlan(tasks: ["gsm8k"], models: [], agents: ["claude_code"])),
                       "Agents on your seats answer your own sets: untick gsm8k or the agents")
    }

    func test_LAB2067_power_mirror_matches_the_engine() {
        // `roof eval power --n 20 --epochs 3 --json` → plus_minus_points 12.3; --n 5 → 33.0 (tests/test_eval_engine.py RunPlanning)
        XCTAssertEqual(EvalPower.mirror(n: 20, epochs: 3).plusMinusPoints, 12.3, accuracy: 0.001)
        XCTAssertEqual(EvalPower.mirror(n: 5, epochs: 1).plusMinusPoints, 33.0, accuracy: 0.001)
        let p = try? snake(EvalPower.self, #"{"epochs": 3, "method": "wilson", "n": 20, "p": 0.5, "paired": false, "plus_minus_points": 12.3}"#)
        XCTAssertEqual(p?.plusMinusPoints, 12.3)
        XCTAssertEqual(EvalPower.mirror(n: 20, epochs: 3).sentence(own: true, contestants: 4),
                       "20 cases × 3 attempts gives about ±12 points per contestant, so differences smaller than that are noise. Same cases for everyone, so they can be compared question by question (paired).")
    }

    func test_LAB2067_doctor_agents_and_seat_lines() throws {
        let json = #"{"engine": {"ready": true}, "docker": "running 28", "providers": {}, "agents": [{"id": "claude_code", "name": "Claude Code", "seat": "C1", "installed": true, "available": true, "why": null, "five_hour": 9.0, "stale": false}, {"id": "codex_cli", "name": "Codex", "seat": "CX", "installed": true, "available": true, "why": null, "five_hour": 25.0, "stale": true}, {"id": "kimi_code", "name": "Kimi", "seat": null, "installed": true, "available": false, "why": "no headless mode", "five_hour": null, "stale": true}]}"#
        let d = try JSONDecoder().decode(EvalDoctor.self, from: Data(json.utf8))
        XCTAssertEqual(d.agents.map(\.line), ["C1 · 9 % used", "CX · seat usage unknown", "no headless mode"])
        XCTAssertEqual(try JSONDecoder().decode(EvalDoctor.self, from: Data(#"{"engine": {"ready": false}, "docker": "x", "providers": {}}"#.utf8)).agents, [])
    }

    func test_LAB2067_status_rows_say_why_and_who() throws {
        let json = #"[{"agent": "claude_code", "contestant": {"id": "claude_code@seat/C1", "kind": "agent", "model": "seat/C1", "name": "Claude Code · C1", "agent": "claude_code"}, "created": null, "epochs": null, "error": null, "finished": null, "hint": null, "id": "r1", "limit": 20, "model": "seat/C1", "progress": "3/20", "seat": "C1", "set_name": "oneroof", "set_version": 1, "status": "waiting", "task": "own_oneroof_v1", "task_ref": "/x/sets/oneroof/v1/own_oneroof_v1.py", "waiting": "waiting for seat C1: 92 % of its 5-hour window used (limit 90 %)", "where": "local"}, {"id": "r2", "task": "swe_bench_verified_mini", "model": "anthropic/claude-haiku-5-5", "status": "failed", "progress": "10/10", "error": "failed: Docker stopped", "hint": "start Docker"}]"#
        let rows = try JSONDecoder().decode([EvalRunRow].self, from: Data(json.utf8))
        XCTAssertTrue(rows[0].isActive)                       // waiting for a seat is still in the queue, never failed
        XCTAssertEqual(rows[0].contestant?.name, "Claude Code · C1")
        XCTAssertEqual(rows[0].setName, "oneroof"); XCTAssertEqual(rows[0].setVersion, 1)
        XCTAssertEqual(rows[1].error, "failed: Docker stopped"); XCTAssertEqual(rows[1].hint, "start Docker"); XCTAssertTrue(rows[1].canResume)
    }

    // MARK: Results (LAB-2068)

    func test_LAB2068_engine_compare_equals_the_app() {
        // The same fixture as tests/test_eval_engine.py CompareAndHistory: 20 cases, A right on 0…14, B right on 0…9, 18, 19.
        func s(_ right: (Int) -> Bool) -> [EvalSample] {
            (0..<20).map { n in try! JSONDecoder().decode(EvalSample.self, from: Data(#"{"id": "XYZ-\#(n + 1)-abc", "epoch": 1, "score": \#(right(n) ? 1.0 : 0.0)}"#.utf8)) }
        }
        let c = EvalStats.compare(s { $0 < 15 }, s { ($0 + 2) % 20 < 12 })!
        XCTAssertTrue(c.paired)
        XCTAssertEqual(c.diff, 0.15, accuracy: 1e-9)
        XCTAssertEqual(c.lo, -0.1073, accuracy: 1e-4)            // engine: ci95 [-0.1073, 0.4073]
        XCTAssertEqual(c.hi, 0.4073, accuracy: 1e-4)
        XCTAssertEqual(c.verdict, .noise)
        let e = try? snake(EvalCompareResult.self, #"{"a": "a", "b": "b", "ci95": [-0.1073, 0.4073], "diff": 0.15, "n": 20, "only_a": ["XYZ-11-abc", "XYZ-12-abc", "XYZ-13-abc", "XYZ-14-abc", "XYZ-15-abc"], "only_b": ["XYZ-19-abc", "XYZ-20-abc"], "paired": true, "tied": 13, "verdict": "noise"}"#)
        XCTAssertEqual(e?.onlyA.count, 5)
        XCTAssertEqual(e?.headline(a: "Claude Code", b: "Codex"), "Can't tell them apart yet")
        XCTAssertEqual(e?.sentence(a: "Claude Code", b: "Codex"),
                       "Claude Code is ahead by 15 points, but the range crosses zero: 5 cases only it solved, 2 only Codex solved, 13 tied.")
        XCTAssertEqual(e?.discordant.count, 7)
    }

    func test_LAB2068_verdict_words() {
        let b = EvalCompareResult(diff: -0.3, ci95: [-0.5, -0.1], n: 20, paired: true, verdict: "b", onlyA: [], onlyB: ["x", "y"], tied: 18)
        XCTAssertEqual(b.headline(a: "haiku", b: "Codex"), "Codex is better")
        XCTAssertEqual(b.sentence(a: "haiku", b: "Codex"), "Codex is ahead by 30 points, and the range stays clear of zero: 2 cases only it solved, 0 only haiku solved, 18 tied.")
        let u = EvalCompareResult(diff: 0.1, ci95: [-0.2, 0.4], n: 5, paired: false, verdict: "noise", onlyA: [], onlyB: [], tied: 0)
        XCTAssertTrue(u.sentence(a: "A", b: "B").contains("unpaired"))
    }

    func test_LAB2068_leaderboard_decodes_with_floor_judge_and_baseline_last() throws {
        let json = #"{"cases": 20, "floor": 0.4, "floor_kind": "no-model floor", "judge": {"agreement": 0.7, "n": 30, "name": "oneroof_triage", "ready": false, "reference": "model", "tnr": 0.5333, "tpr": 0.8667}, "judged": true, "key": "oneroof_triage@v1", "kind": "triage", "latest_failed": null, "rows": [{"agent": "claude_code", "ci95": [0.5, 0.9], "ci_method": "wilson", "contestant": "Claude Code · C1", "cost": 0.0, "date": "2026-11-01T02:59:58+00:00", "epochs": null, "free": false, "kind": "agent", "metric": "accuracy", "model": "seat/C1", "n": 20, "run": "ra", "score": 0.75, "seat": true, "usd_per_right": null}, {"agent": null, "ci95": [0.2188, 0.6134], "ci_method": "wilson", "contestant": "claude-haiku-5-5", "cost": 0.0162231, "date": "2026-11-01T02:59:58+00:00", "epochs": null, "free": false, "kind": "model", "metric": "accuracy", "model": "anthropic/claude-haiku-5-5", "n": 20, "run": "rm", "score": 0.4, "seat": false, "usd_per_right": 0.002028}, {"agent": null, "ci95": [0.0, 0.16], "ci_method": "wilson", "contestant": "mockllm/model", "cost": null, "date": null, "epochs": null, "free": true, "kind": "baseline", "metric": "accuracy", "model": "mockllm/model", "n": 20, "run": "rb", "score": 0.0, "seat": false, "usd_per_right": null}], "runs": 3, "set": "oneroof_triage", "task_file": "/x/own_oneroof_triage_v1.py", "title": "oneroof · bug triage v1", "version": 1, "versions": [1]}"#
        let lb = try snake(EvalLeaderboard.self, json)
        XCTAssertEqual(lb.ranked.map(\.rank), [1, 2, nil])     // the baseline is unranked, last
        XCTAssertEqual(lb.rows.map(\.costText), ["seat", "$0.016", "free"])
        XCTAssertEqual(lb.judge?.badge, "judge 70 % agree")
        XCTAssertEqual(lb.subtitle, "latest run per contestant · 20 cases · bar = 95 % range · dashed line = no-model floor")
        XCTAssertEqual(lb.floor, 0.4)
    }

    func test_LAB2068_history_drops_line() throws {
        let json = #"{"drops": [{"contestant": "gpt-5-mini", "delta": -0.1, "id": "openai/gpt-5-mini", "possible": true, "prev_run": "h1", "run": "h2", "text": "gpt-5-mini dropped 10 points on Oct 31, inside its range. Re-run with 3 attempts to check."}], "first": "2026-10-06T00:00:00Z", "floor": 0.4, "key": "demo@v1", "last": "2026-10-31T00:00:00Z", "series": [{"contestant": "gpt-5-mini", "kind": "model", "points": [{"ci95": [0.4, 0.8], "date": "2026-10-06T00:00:00Z", "epochs": null, "n": 20, "run": "h1", "score": 0.7}]}]}"#
        let h = try snake(EvalHistory.self, json)
        XCTAssertEqual(h.dropsLine, "1 possible drop")
        XCTAssertEqual(h.drops.first?.prevRun, "h1")
    }

    func test_LAB2068_results_index_own_first_with_counts_and_failed() throws {
        let json = #"[{"id": "a", "task": "own_oneroof_v1", "set_name": "oneroof", "set_version": 1, "status": "done", "started": "2026-10-31T10:00:00Z", "metrics": []}, {"id": "b", "task": "own_oneroof_v1", "set_name": "oneroof", "set_version": 1, "status": "done", "started": "2026-10-31T11:00:00Z", "metrics": []}, {"id": "c", "task": "swe_bench_verified_mini", "status": "failed", "started": "2026-10-31T12:00:00Z", "metrics": []}, {"id": "d", "task": "gsm8k", "status": "done", "started": "2026-10-31T09:00:00Z", "metrics": []}, {"id": "e", "task": "judge_oneroof_triage_v1", "status": "done", "started": "2026-10-31T08:00:00Z", "metrics": []}, {"id": "f", "task": "labeller_oneroof_triage", "status": "done", "metrics": []}]"#
        let es = EvalResultsEntry.from(try JSONDecoder().decode([EvalResult].self, from: Data(json.utf8)))
        XCTAssertEqual(es.map(\.key), ["oneroof@v1", "judge_oneroof_triage_v1", "swe_bench_verified_mini", "gsm8k"])   // labeller runs hidden
        XCTAssertEqual(es.map(\.runs), [2, 1, 0, 1])
        XCTAssertEqual(es.map(\.failed), [false, false, true, false])
    }

    // MARK: One run (LAB-2069)

    private let samplesJSON = #"[{"id": "LAB-1874-a", "epoch": 1, "score": 0.0, "answer": "Handoff.swift", "target": "app/CodexAdapter.swift", "issue": "LAB-1874", "title": "Handoff drops last turn on Codex", "code": {"verdict": "fail", "why": "The fix changed app/CodexAdapter.swift", "named": ["app/Handoff.swift"], "changed": ["app/CodexAdapter.swift"]}, "judge": {"verdict": "pass", "why": "Identifies truncation as the likely cause."}, "you": {"verdict": "fail", "why": "Codex-only means the adapter."}, "judge_item": {"judge": "oneroof_triage", "item": "t7mw:LAB-1874-a:1"}, "disagree": true, "labelled": true}, {"id": "LAB-1880-b", "epoch": 1, "score": 0.0, "code": {"verdict": "fail", "why": "x", "named": [], "changed": ["a.py"]}, "judge_item": {"judge": "oneroof_triage", "item": "t7mw:LAB-1880-b:1"}, "disagree": false, "labelled": false}, {"id": "LAB-1900-c", "epoch": 1, "score": 1.0, "time": 9.0, "code": {"verdict": "pass", "why": "names a.py", "named": ["src/a.py"], "changed": ["src/a.py"]}, "disagree": false}, {"id": "gsm8k_1", "epoch": 1, "score": 1.0, "answer": "52", "target": "52", "time": 2.0}]"#

    func test_LAB2069_judge_differs_from_you_count_and_filters() throws {
        let xs = try JSONDecoder().decode([EvalSample].self, from: Data(samplesJSON.utf8))
        let c = EvalSample.counts(xs)
        XCTAssertEqual([c.all, c.wrong, c.disagree], [4, 2, 1])   // Judge ≠ you = the answers whose verdicts disagree
        XCTAssertEqual(EvalSample.filtered(xs, .wrong).map(\.sampleID), ["LAB-1874-a", "LAB-1880-b"])
        XCTAssertEqual(EvalSample.filtered(xs, .disagree).map(\.sampleID), ["LAB-1874-a"])
        XCTAssertEqual(EvalSample.filtered(xs, .all, only: ["gsm8k_1"]).count, 1)   // Compare's "See the N cases"
        XCTAssertEqual(EvalSample.sorted(xs, .wrongFirst).map(\.isRight), [false, false, true, true])
        XCTAssertEqual(EvalSample.sorted(xs, .slowest).first?.sampleID, "LAB-1900-c")
        XCTAssertEqual(xs[0].judgeItem?.item, "t7mw:LAB-1874-a:1")
    }

    func test_LAB2069_row_summaries_and_takeaway() throws {
        let xs = try JSONDecoder().decode([EvalSample].self, from: Data(samplesJSON.utf8))
        XCTAssertEqual(xs[0].summary, "named Handoff.swift · fix in CodexAdapter.swift")
        XCTAssertEqual(xs[1].summary, "vague: no file named")
        XCTAssertEqual(xs[2].summary, "named a.py")
        XCTAssertEqual(xs[3].summary, "answer 52 · expected 52")
        XCTAssertEqual(xs[0].takeaway, "A case like this, where the judge passes what you failed, is why the judge's score reads high.")
        XCTAssertNil(xs[1].takeaway)
    }

    func test_LAB2069_trust_line() throws {
        let a = try JSONDecoder().decode(EvalJudgeAgreement.self, from: Data(#"{"mode": "single", "n": 30, "agreement": 0.7, "tpr": 0.87, "tnr": 0.53, "reference": "you"}"#.utf8))
        let l = EvalTrustLine.text(a)
        XCTAssertEqual(l.body, "Agrees with your labels 70 % (n=30), but fails only 53 % of bad answers. Read this score as an upper bound.")
        XCTAssertFalse(l.trusted)
        let good = try JSONDecoder().decode(EvalJudgeAgreement.self, from: Data(#"{"mode": "single", "n": 30, "agreement": 0.9, "tpr": 0.9, "tnr": 0.9, "reference": "you"}"#.utf8))
        XCTAssertTrue(EvalTrustLine.text(good).trusted)
    }

    func test_LAB2069_run_again_keeps_the_settings() throws {
        let r = try JSONDecoder().decode(EvalResult.self, from: Data(#"{"id": "x", "task": "own_oneroof_v1", "task_ref": "/x/sets/oneroof/v1/own_oneroof_v1.py", "model": "openai/gpt-5-mini", "limit_n": 20, "epochs": 3, "seed": 42, "temperature": 0.2, "metrics": []}"#.utf8))
        let p = EvalRunPlan.again(r)
        XCTAssertEqual(p.tasks, ["/x/sets/oneroof/v1/own_oneroof_v1.py"]); XCTAssertEqual(p.models, ["openai/gpt-5-mini"])
        XCTAssertEqual(p.limit, 20); XCTAssertEqual(p.epochs, 3); XCTAssertEqual(p.seed, 42); XCTAssertEqual(p.temperature, 0.2)
        let seat = try JSONDecoder().decode(EvalResult.self, from: Data(#"{"id": "y", "task": "own_oneroof_v1", "model": "seat/C1", "agent": "claude_code", "limit_n": 20, "metrics": []}"#.utf8))
        XCTAssertEqual(EvalRunPlan.again(seat).agents, ["claude_code"]); XCTAssertEqual(EvalRunPlan.again(seat).models, [])
        let api = try JSONDecoder().decode(EvalResult.self, from: Data(#"{"id": "z", "task": "swe", "model": "anthropic/claude-haiku-5-5", "agent": "codex_cli", "metrics": []}"#.utf8))
        XCTAssertEqual(EvalRunPlan.again(api).apiAgents, ["codex_cli@anthropic/claude-haiku-5-5"])
    }

    func test_LAB2061_selftest_values_for_stage_two() {
        XCTAssertEqual(EvalsTabV2.selfTest("run-detail")?.drill, "rundetail")
        XCTAssertEqual(EvalsTabV2.selfTest("all-by-all")?.drill, "allbyall")
        XCTAssertEqual(EvalsTabV2.selfTest("xray")?.tab, .results)
    }

    func test_QA_subtitle_and_explore_footer_count_the_same_benchmarks() throws {
        let json = #"{"count": 3, "tasks": 3, "categories": [], "benchmarks": [{"folder": "gsm8k", "tasks": [{"name": "gsm8k"}]}, {"folder": "hle", "tasks": [{"name": "hle"}]}, {"folder": "own-oneroof", "category": "Your evals", "tasks": [{"name": "/x.py"}]}]}"#
        let c = try JSONDecoder().decode(EvalCatalog.self, from: Data(json.utf8))
        XCTAssertEqual(c.benchmarkCount, 2)
        XCTAssertEqual(EvalCatalog.footer(shown: c.benchmarks, total: c, ownShelf: false), "2 of 2")
        XCTAssertEqual(EvalCatalog.footer(shown: c.benchmarks, total: c, ownShelf: true), "1 of your evals")
        XCTAssertTrue(EvalsSubtitle.text(benchmarks: c.benchmarkCount, ownEvals: 1, judges: 0, finished: 0, running: 0).hasPrefix("2 benchmarks"))
    }
}
