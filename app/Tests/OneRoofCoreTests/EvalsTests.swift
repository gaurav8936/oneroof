import XCTest
@testable import OneRoofCore

/// LAB-EVALS (LAB-1991): the Evals place's pure logic, fed with JSON shaped exactly as `roof_eval.py --json` prints it.
final class EvalsTests: XCTestCase {
    private func decode<T: Decodable>(_ t: T.Type, _ json: String) throws -> T { try JSONDecoder().decode(T.self, from: Data(json.utf8)) }

    private let catalogJSON = """
    {"benchmarks": [
      {"arxiv": "https://arxiv.org/abs/2110.14168", "assets": ["huggingface"], "category": "Math", "description": "Grade-school math.",
       "extra": null, "folder": "gsm8k", "group": "Mathematics", "internet": false, "sandbox": false,
       "starter": [{"rank": 5, "task": "gsm8k", "teaches": "Exact-match parsing."}], "supports_k8s": false, "tags": [],
       "tasks": [{"human_baseline": {"metric": "accuracy", "score": 0.89, "source": "x"}, "name": "gsm8k", "samples": 1319}],
       "title": "GSM8K: Grade School Math Word Problems", "version": "2-A"},
      {"arxiv": null, "assets": [], "category": "Software engineering", "description": "Real GitHub issues.", "extra": "swe_bench",
       "folder": "swe_bench", "group": "Coding", "internet": true, "sandbox": true,
       "starter": [{"milestone": "M6", "rank": 16, "task": "swe_bench_verified_mini", "teaches": "Agent harness vs model."}],
       "supports_k8s": true, "tags": ["Agent"],
       "tasks": [{"human_baseline": null, "name": "swe_bench", "samples": 500}, {"human_baseline": null, "name": "swe_bench_verified_mini", "samples": 50}],
       "title": "SWE-bench Verified", "version": "6-D"},
      {"category": "Writing", "description": "Writing tasks.", "folder": "writingbench", "group": "Writing", "internet": false,
       "sandbox": false, "starter": [], "supports_k8s": false, "tags": [], "tasks": [{"name": "writingbench", "samples": 1000}], "title": "WritingBench"}
    ], "categories": ["Knowledge", "Math", "Software engineering"], "count": 129, "inspect_ai": "0.3.287", "inspect_evals": "0.27.0", "tasks": 239}
    """

    func test_catalog_decodes_engine_output() throws {
        let c = try decode(EvalCatalog.self, catalogJSON)
        XCTAssertEqual(c.count, 129)
        XCTAssertEqual(c.inspectEvals, "0.27.0")
        XCTAssertEqual(c.benchmarks.map(\.id), ["gsm8k", "swe_bench", "writingbench"])
        let swe = c.benchmarks[1]
        XCTAssertTrue(swe.sandbox && swe.internet && swe.supportsK8s)
        XCTAssertEqual(swe.defaultTask, "swe_bench_verified_mini")   // the shelf pick, not the 500-question set
        XCTAssertEqual(c.benchmarks[0].tasks[0].humanBaseline?.score, 0.89)
        XCTAssertEqual(c.allCategories, ["Math", "Software engineering", "Writing"])   // shelf order, then the rest
    }

    func test_own_eval_set_shows_by_name_under_your_evals() throws {
        let json = """
        {"benchmarks": [{"category": "Your evals", "description": "20 real bugs.", "folder": "own-oneroof", "group": "Your evals",
          "sandbox": false, "internet": false, "starter": [], "tags": ["own", "fix-locator"], "version": "1",
          "tasks": [{"name": "/data/evals/sets/oneroof/v1/own_oneroof_v1.py", "samples": 20}], "title": "oneroof · fix locator (your work)"}],
         "categories": ["Your evals", "Math"], "count": 1, "tasks": 1}
        """
        let c = try decode(EvalCatalog.self, json)
        let b = c.benchmarks[0]
        XCTAssertEqual(c.allCategories, ["Your evals"])
        XCTAssertEqual(b.defaultTask, "/data/evals/sets/oneroof/v1/own_oneroof_v1.py")   // the engine runs the file
        XCTAssertEqual(EvalBenchmark.taskLabel(b.defaultTask), "own_oneroof_v1")          // people read its name
        XCTAssertEqual(EvalBenchmark.taskLabel("gsm8k"), "gsm8k")
        XCTAssertEqual(b.firstRunLimit, 20)                                                 // priced and run at 20, not 50
        XCTAssertEqual(try decode(EvalCatalog.self, catalogJSON).benchmarks[0].firstRunLimit, 50)
    }

    func test_judged_score_carries_its_agreement_with_the_owner() throws {
        let json = """
        [{"id": "r1", "task": "judge_t_v1", "status": "done", "metrics": [],
          "judge_agreement": {"mode": "single", "n": 20, "agreement": 0.85, "tpr": 0.9, "tnr": 0.78, "judged_pass_rate": 0.6}},
         {"id": "r2", "task": "judge_p_v1", "status": "done", "metrics": [],
          "judge_agreement": {"mode": "pairwise", "n": 4, "agreement": 0.5, "position_consistency": 0.67,
                              "self_preference": "the judge model also wrote answers it grades"}},
         {"id": "r3", "task": "gsm8k", "status": "done", "metrics": []}]
        """
        let rs = try decode([EvalResult].self, json)
        XCTAssertEqual(rs[0].judgeAgreement?.short, "agrees with you 85 % (n=20) · good 90 % · bad 78 %")
        XCTAssertEqual(rs[1].judgeAgreement?.short,
                       "agrees with you 50 % (n=4) · same winner both orders 67 % · too few labels · grades its own answers")
        XCTAssertNil(rs[2].judgeAgreement)
        let silver = try decode(EvalJudgeAgreement.self, """
        {"mode": "single", "n": 30, "agreement": 0.8, "tpr": 0.75, "tnr": 0.85, "reference": "model:anthropic/claude-sonnet-5-5",
         "code": {"n": 30, "fails_what_code_fails": 0.9, "code_fail": 20}}
        """)
        XCTAssertEqual(silver.short, "agrees with claude-sonnet-5-5's labels 80 % (n=30) · good 75 % · bad 85 % · fails 90 % of 20 wrong-file notes")
    }

    func test_catalog_filter() throws {
        let bs = try decode(EvalCatalog.self, catalogJSON).benchmarks
        XCTAssertEqual(EvalCatalogFilter(starterOnly: true).apply(bs).map(\.id), ["gsm8k", "swe_bench"])
        XCTAssertEqual(EvalCatalogFilter(noSandbox: true).apply(bs).map(\.id), ["gsm8k", "writingbench"])
        XCTAssertEqual(EvalCatalogFilter(category: "Math").apply(bs).map(\.id), ["gsm8k"])
        XCTAssertEqual(EvalCatalogFilter(search: "github").apply(bs).map(\.id), ["swe_bench"])
        XCTAssertEqual(EvalCatalogFilter(search: "verified_mini").apply(bs).map(\.id), ["swe_bench"])   // task names too
        XCTAssertEqual(EvalCatalogFilter().apply(bs).count, 3)
    }

    private let resultsJSON = """
    [{"cost": 0.4, "dataset": "openai/gsm8k", "epochs": null, "error": null, "est_cost": 0.47, "finished": "2026-10-31T21:41:00+00:00",
      "id": "r2", "input_tokens": 107800, "inspect_evals": "0.27.0", "limit_n": 50, "model": "anthropic/claude-haiku-5-5", "output_tokens": 9000,
      "samples_done": 50, "samples_total": 50, "seed": 42, "started": "2026-10-31T21:40:00+00:00", "status": "done", "task": "gsm8k",
      "metrics": [{"ci95": [0.69, 0.89], "ci_method": "wilson", "metric": "accuracy", "n": 50, "scorer": "match", "stderr": 0.05, "value": 0.8}]},
     {"cost": null, "id": "r1", "model": "anthropic/claude-haiku-5-5", "task": "gsm8k", "status": "done", "started": "2026-10-31T20:00:00+00:00",
      "samples_done": 5, "metrics": [{"ci95": [0.0, 0.434], "ci_method": "wilson", "metric": "accuracy", "n": 5, "scorer": "match", "stderr": 0.0, "value": 0.0}]},
     {"id": "r3", "model": "mockllm/model", "task": "niah", "status": "done", "started": "2026-10-31T21:00:00+00:00", "samples_done": 3,
      "metrics": [{"ci95": null, "ci_method": "none", "metric": "subset_accuracy_combinations", "n": 3, "scorer": "s", "stderr": null, "value": null,
                   "note": "not computable on these samples"}]},
     {"id": "r4", "model": "openai/gpt-5-nano", "task": "gsm8k", "status": "failed", "samples_done": 0, "metrics": [],
      "error": "Error code: 401 - Incorrect [redacted]"}]
    """

    func test_results_decode_and_derived_numbers() throws {
        let rs = try decode([EvalResult].self, resultsJSON)
        let r = rs[0]
        XCTAssertEqual(r.primary?.value, 0.8)
        XCTAssertEqual(r.primary?.ci95, [0.69, 0.89])
        XCTAssertEqual(r.duration, 60)
        XCTAssertEqual(r.costPerCorrect!, 0.4 / 40, accuracy: 1e-12)   // $0.40 for 40 right
        XCTAssertFalse(r.isFree)
        XCTAssertNil(rs[2].primary)                                      // n/a metric is not a headline
        XCTAssertEqual(rs[2].metrics.first?.note, "not computable on these samples")
        XCTAssertTrue(rs[2].isFree)
        XCTAssertEqual(rs[3].error, "Error code: 401 - Incorrect [redacted]")
    }

    func test_matrix_keeps_the_latest_finished_run_per_cell() throws {
        let m = EvalStats.matrix(try decode([EvalResult].self, resultsJSON))
        XCTAssertEqual(m["anthropic/claude-haiku-5-5"]?["gsm8k"]?.id, "r2")   // r1 is older
        XCTAssertNil(m["openai/gpt-5-nano"])                                   // failed runs are not cells
        XCTAssertEqual(m["mockllm/model"]?["niah"]?.id, "r3")
        XCTAssertTrue(EvalStats.isSmall(5))
        XCTAssertFalse(EvalStats.isSmall(50))
    }

    func test_wilson_matches_the_engine() {
        let (lo, hi) = EvalStats.wilson(0, n: 5)
        XCTAssertEqual(lo, 0)
        XCTAssertEqual(hi, 0.4345, accuracy: 0.0005)            // engine: 0/5 → [0, 0.434]
        let (lo2, hi2) = EvalStats.wilson(0.125, n: 3)
        XCTAssertEqual(lo2, 0.0104, accuracy: 0.0005)          // engine ifeval final_acc ci95
        XCTAssertEqual(hi2, 0.6608, accuracy: 0.0005)
        XCTAssertEqual(EvalStats.wilson(0.5, n: 0).hi, 1)
    }

    private func s(_ id: String, _ score: Double, epoch: Int = 1) -> EvalSample {
        EvalSample(sampleID: id, epoch: epoch, score: score, answer: nil, target: nil, input: nil, output: nil,
                   explanation: nil, time: nil, inputTokens: nil, outputTokens: nil, error: nil)
    }

    func test_paired_compare_finds_a_real_difference() {
        let ids = (0..<60).map { "q\($0)" }
        let a = ids.map { s($0, 1) }
        let b = ids.enumerated().map { i, id in s(id, i % 3 == 0 ? 0 : 1) }   // B misses every third question
        let c = EvalStats.compare(a, b)!
        XCTAssertTrue(c.paired)
        XCTAssertEqual(c.n, 60)
        XCTAssertEqual(c.diff, 20.0 / 60, accuracy: 1e-9)
        XCTAssertEqual(c.verdict, .aBetter)
        XCTAssertEqual(EvalStats.compare(b, a)?.verdict, .bBetter)
    }

    func test_compare_says_noise_when_it_is_noise() {
        let ids = (0..<10).map { "q\($0)" }
        let a = ids.enumerated().map { i, id in s(id, i < 6 ? 1 : 0) }
        let b = ids.enumerated().map { i, id in s(id, i < 5 ? 1 : 0) }        // 60 % vs 50 % on 10 questions
        XCTAssertEqual(EvalStats.compare(a, b)?.verdict, .noise)
        XCTAssertEqual(EvalStats.compare(a, a)?.verdict, .noise)               // a run against itself
    }

    func test_compare_averages_attempts_and_falls_back_to_unpaired() {
        let a = [s("q1", 1, epoch: 1), s("q1", 0, epoch: 2), s("q2", 1), s("q3", 1)]
        let b = [s("x1", 0), s("x2", 0), s("x3", 1)]
        let c = EvalStats.compare(a, b)!
        XCTAssertFalse(c.paired)                                                // no shared questions
        XCTAssertEqual(c.diff, (0.5 + 1 + 1) / 3 - 1.0 / 3, accuracy: 1e-9)    // q1's two attempts averaged
        XCTAssertNil(EvalStats.compare([s("q1", 1)], [s("q2", 0)]))             // too few to say anything
    }

    func test_samples_and_transcript_decode() throws {
        let ss = try decode([EvalSample].self, """
        [{"answer": "", "epoch": 1, "error": null, "explanation": "Default output", "id": "gsm8k_e5531f73", "input": "Mimi…",
          "input_tokens": 2150, "output": "Default output", "output_tokens": 33, "raw": {"match": "I"}, "score": 0.0,
          "scores": {"match": 0.0}, "target": "16", "time": 0.26}]
        """)
        XCTAssertEqual(ss[0].id, "gsm8k_e5531f73#1")
        XCTAssertEqual(ss[0].target, "16")
        let tr = try decode(EvalTranscript.self, """
        {"id": "q", "epoch": 1, "target": "16", "time": 0.2, "error": null,
         "messages": [{"role": "user", "text": "How many?", "tool_calls": []},
                      {"role": "assistant", "text": "", "tool_calls": [{"function": "bash", "arguments": "{\\"cmd\\": \\"ls\\"}"}]}],
         "scores": {"match": {"value": "I", "answer": "", "explanation": "no number"}}}
        """)
        XCTAssertEqual(tr.messages.count, 2)
        XCTAssertEqual(tr.messages[1].toolCalls.first?.function, "bash")
        XCTAssertEqual(tr.scores["match"]?.value, "I")
    }

    func test_engine_errors_and_doctor_decode() throws {
        let err = EvalEngine.decode([EvalRunRow].self, EvalEngine.Output(code: 3, stdout: Data(#"{"error": "estimate $50 is over the cap $2.00", "code": 3}"#.utf8), stderr: ""))
        guard case .failure(let e) = err else { return XCTFail("expected the engine's error") }
        XCTAssertEqual(e.code, 3)
        XCTAssertTrue(e.message.contains("over the cap"))
        let bad = EvalEngine.decode([EvalRunRow].self, EvalEngine.Output(code: 1, stdout: Data(), stderr: "roof eval: no key for anthropic"))
        guard case .failure(let e2) = bad else { return XCTFail() }
        XCTAssertEqual(e2.message, "no key for anthropic")
        let d = try decode(EvalDoctor.self, """
        {"docker": "running 29.8.2", "engine": {"dir": "/x", "inspect_ai": "0.3.287", "inspect_evals": "0.27.0", "ready": true},
         "prices_checked": "2026-10-31T21:31:42Z", "runs": 3, "uv": "/opt/homebrew/bin/uv",
         "providers": {"anthropic": {"env": "ANTHROPIC_API_KEY", "key_file": "/k", "ready": true, "source": "key file"},
                       "openai": {"env": "OPENAI_API_KEY", "key_file": null, "ready": false, "source": null}}}
        """)
        XCTAssertTrue(d.engine.ready)
        XCTAssertEqual(d.readyProviders, ["anthropic"])
        XCTAssertEqual(d.places, ["local": true])   // older engines send no "where"
        let d2 = try decode(EvalDoctor.self, #"{"docker": "x", "engine": {"ready": true}, "providers": {}, "where": {"local": false, "daytona": true, "modal": false}}"#)
        XCTAssertEqual(d2.places["daytona"], true)
        XCTAssertEqual(EvalDoctor.placeTitle("modal"), "Modal (cloud)")
    }

    func test_estimate_breakdown() throws {
        let e = try decode(EvalEstimate.self, """
        {"task": "hle", "model": "mockllm/model", "calls": 50, "tokens_per_sample": {"input": 782, "output": 500},
         "token_basis": "prompt measured", "usd": 0.0306, "model_usd": 0.0, "cap_check_usd": 0.0459,
         "grader": {"usd": 0.0306, "basis": "measured on this Mac", "models": ["openrouter/z-ai/glm-5.3-flash"]},
         "sandbox": {"usd": 0.0004, "basis": "guess", "where": "daytona", "seconds_per_question": 120}}
        """)
        XCTAssertEqual(e.capCheckUSD, 0.0459)
        XCTAssertEqual(e.breakdown, "model $0.0000 · grader $0.0306 · sandbox $0.0004")
        let plain = try decode(EvalEstimate.self, #"{"task": "gsm8k", "model": "m", "calls": 5, "tokens_per_sample": {"input": 1, "output": 1}, "token_basis": "x", "usd": 0.01, "model_usd": 0.01, "grader": {"usd": 0, "basis": "none seen", "models": []}}"#)
        XCTAssertEqual(plain.breakdown, "model $0.0100")
    }

    func test_run_rows() throws {
        let rows = try decode([EvalRunRow].self, """
        [{"created": "2026-10-31T21:31:42Z", "epochs": 1, "finished": null, "id": "a", "limit": 40, "model": "mockllm/model", "progress": "10/40", "status": "running", "task": "gsm8k"},
         {"created": "2026-10-31T21:31:42Z", "epochs": null, "finished": null, "id": "b", "limit": 40, "model": "mockllm/model", "progress": "", "status": "interrupted", "task": "gsm8k"}]
        """)
        XCTAssertEqual(rows[0].fraction, 0.25)
        XCTAssertTrue(rows[0].isActive)
        XCTAssertNil(rows[1].fraction)
        XCTAssertTrue(rows[1].canResume)
    }

    func test_models_and_glossary() {
        XCTAssertTrue(EvalModels.isFree("mockllm/model"))
        XCTAssertTrue(EvalModels.isFree("ollama/qwen3:1.7b"))
        XCTAssertFalse(EvalModels.isFree("anthropic/claude-haiku-5-5"))
        XCTAssertEqual(EvalModels.short("openrouter/qwen/qwen3-coder"), "qwen/qwen3-coder")
        XCTAssertEqual(EvalModels.short("mockllm/model"), "mockllm/model")
        XCTAssertEqual(EvalModels.when("not a date"), "not a date")
        XCTAssertFalse(EvalModels.when("2026-10-31T22:28:07Z").contains("T"))
        XCTAssertEqual(EvalModels.provider("openrouter/qwen/qwen3-coder"), "openrouter")
        for id in ["accuracy", "interval", "stderr", "compare", "passk", "epochs", "contamination", "judge", "harness", "cost", "chance"] {
            XCTAssertNotNil(EvalGlossary.entry(id), id)
        }
        XCTAssertEqual(Set(EvalGlossary.all.map(\.id)).count, EvalGlossary.all.count)
    }

    func test_launcher_is_found_in_the_checkout() {
        XCTAssertNotNil(EvalEngine.script, "app/Resources/evals/roof_eval.py should resolve in a debug build")
        XCTAssertTrue(EvalEngine.dataDir.hasSuffix("evals"))
    }
}
