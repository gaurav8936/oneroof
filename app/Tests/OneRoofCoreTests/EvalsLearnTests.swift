import XCTest
@testable import OneRoofCore

/// LAB-2070 · Learn (HP E5.1, EV-12) and the hover explanations; plus the M9 stage-2 QA fixes (compare needs 10 shared
/// questions; a seat run waiting on unknown use). Numbers locked to the engine are copied from roof_eval.py's own output.
final class EvalsLearnTests: XCTestCase {
    private var book: EvalLessonBook {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Resources/evals/lessons.json")
        return EvalLessonBook.decode(try! Data(contentsOf: url))!
    }

    private func result(_ id: String, task: String = "gsm8k", model: String = "anthropic/claude-haiku-5-5", score: Double, n: Int,
                        status: String = "done", cost: Double? = nil, epochs: Int? = nil, metric: String = "accuracy") -> EvalResult {
        let ci = EvalStats.wilson(score, n: n)
        let json = """
        {"id": "\(id)", "task": "\(task)", "model": "\(model)", "status": "\(status)", "samples_done": \(n), "cost": \(cost.map { String($0) } ?? "null"),
         "epochs": \(epochs.map(String.init) ?? "null"),
         "metrics": [{"scorer": "match", "metric": "\(metric)", "value": \(score), "stderr": null, "n": \(n), "ci95": [\(ci.lo), \(ci.hi)], "ci_method": "wilson"}]}
        """
        return try! JSONDecoder().decode(EvalResult.self, from: Data(json.utf8))
    }

    // MARK: Lessons (HP EV-12)

    func test_LAB2070_sixteen_lessons_in_six_groups_in_the_handover_order() {
        let b = book
        XCTAssertEqual(b.lessons.count, 16)   // agent decision 2026-11-01: the handover lists 16
        XCTAssertEqual(b.sections.map(\.title), ["Start", "Reading a score", "How answers are marked", "Agents vs models",
                                                 "Your own evals", "Reading leaderboards"])
        XCTAssertEqual(b.lessons.map(\.title), [
            "Your first eval, free", "Accuracy and chance", "The 95 % range", "Standard error", "Is the difference real?",
            "pass@1 and pass@k", "Attempts per question", "Exact match and parsing", "Model judges and their limits",
            "Your labels as ground truth", "What the harness adds", "Cost per solved task", "Golden sets from repo history",
            "Why versions are frozen", "Saturation and headroom", "Contamination"])
        XCTAssertEqual(Set(b.lessons.map(\.id)).count, 16)
        XCTAssertEqual(b.position("range"), "Reading a score · 2 of 6")
        XCTAssertEqual(b.next(after: "range")?.title, "Standard error")
        XCTAssertNil(b.next(after: "contamination"))
        XCTAssertEqual(b.subtitle(done: ["range", "stderr", "nope"]), "16 lessons · 2 done · each one opens in the app where it applies")
    }

    func test_LAB2070_lessons_keep_todays_glossary_text_every_entry_once() {
        let b = book
        let used = b.lessons.flatMap(\.glossary)
        XCTAssertEqual(used.sorted(), EvalGlossary.all.map(\.id).sorted())   // all 12 of 1.9.37's cards, none twice
        for l in b.lessons {
            if let first = l.glossary.first, let g = EvalGlossary.entry(first) {
                XCTAssertEqual(l.body, g.body, l.id)
                XCTAssertEqual(l.example, g.example, l.id)
            }
            XCTAssertLessThanOrEqual(l.body.split(separator: " ").count, 120, l.id)
            XCTAssertFalse(l.links.isEmpty, l.id)
            for k in l.links { XCTAssertTrue(EvalLessons.knownRoutes.contains(k.route), "\(l.id) → \(k.route)") }
        }
        let widgets = Set(b.lessons.map(\.widget))
        XCTAssertEqual(widgets.count, 16)                                      // one Try it per lesson
        XCTAssertLessThanOrEqual(b.lessons.filter { ["harness", "golden", "frozen"].contains($0.widget) }.count, 3)   // ≤ 3 static
    }

    // MARK: Try it maths

    func test_LAB2070_range_explorer_equals_the_engines_wilson() {
        // roof_eval.interval(0.8, n, None, True) for each n (copied from the engine's output).
        let engine: [Int: (Double, Double)] = [5: (0.3755282641185388, 0.9637768390302125), 10: (0.49015684672072335, 0.9433190520193067),
                                               20: (0.5839782779742401, 0.9193436467288), 50: (0.6696262789551477, 0.8875637005402612),
                                               200: (0.7391436038882958, 0.8495487925607118), 1000: (0.7740805389094014, 0.8236233219387643)]
        for n in EvalLessonMath.rangeNs {
            let r = EvalLessonMath.range(n: n)
            XCTAssertEqual(r.lo, engine[n]!.0, accuracy: 1e-12); XCTAssertEqual(r.hi, engine[n]!.1, accuracy: 1e-12)
        }
        XCTAssertEqual(EvalLessonMath.rangeText(EvalLessonMath.range(n: 50)), "67–89 %")   // HP: 80 % at n = 50
        XCTAssertEqual(EvalLessonMath.rangeNote(n: 50), "One Roof's default first run on a benchmark.")
        XCTAssertEqual(EvalLessonMath.rangeText(EvalStats.wilson(0, n: 5)), "0–43 %")       // the first eval's "up to 43 %"
    }

    func test_LAB2070_widget_maths() {
        XCTAssertEqual(EvalLessonMath.chance(options: 4), 0.25)
        XCTAssertEqual(EvalLessonMath.aboveChance(score: 0.5, options: 4), 1.0 / 3, accuracy: 1e-12)
        XCTAssertEqual(EvalLessonMath.stderr(p: 0.7, n: 233), 0.0300, accuracy: 0.0002)      // glossary: 0.70 with stderr 0.03
        XCTAssertEqual(EvalLessonMath.passAtK(p: 0.3, k: 5), 1 - pow(0.7, 5), accuracy: 1e-12)
        XCTAssertEqual(EvalLessonMath.judged(p: 0.5, tpr: 0.9, tnr: 0.7), 0.6, accuracy: 1e-12)
        XCTAssertEqual(EvalLessonMath.costPerSolved(costPerTry: 0.01, rate: 0.5)!, 0.02, accuracy: 1e-12)
        XCTAssertNil(EvalLessonMath.costPerSolved(costPerTry: 0.01, rate: 0))
        XCTAssertEqual(EvalPower.mirror(n: 20, epochs: 3).plusMinusPoints, 12.3)              // engine: power(20, 3)
        XCTAssertEqual(["saturated", "some", "lots"], [0.92, 0.75, 0.6].map(EvalLessonMath.headroomLevel))   // published_scores.headroom
    }

    func test_LAB2070_compare_widget_is_EvalStats_compare() {
        let paired = EvalLessonMath.compare(a: 0.8, b: 0.7, n: 50, paired: true)!
        XCTAssertTrue(paired.paired); XCTAssertEqual(paired.verdict, .aBetter); XCTAssertEqual(paired.diff, 0.1, accuracy: 1e-12)
        let unpaired = EvalLessonMath.compare(a: 0.8, b: 0.7, n: 50, paired: false)!
        XCTAssertFalse(unpaired.paired); XCTAssertEqual(unpaired.verdict, .noise)
        let tiny = EvalLessonMath.compare(a: 0.8, b: 0.2, n: 5, paired: true)!
        XCTAssertTrue(tiny.tooFew); XCTAssertEqual(tiny.verdict, .noise)
    }

    func test_LAB2070_exact_match_reads_like_inspect_gsm8k() {
        // Each case checked against inspect_ai.scorer._common.match_str(reply, "72", location="end", numeric=True).
        let cases: [(String, String, Bool)] = [("ANSWER: 72", "72", true), ("ANSWER: $72", "72", true), ("72 clips (48 + 24)", "24", false),
                                               ("seventy-two", "", false), ("The answer is 72.", "72", true), ("ANSWER: 72.0", "72", true),
                                               ("ANSWER: 1,072", "1072", false), ("ANSWER: **72**", "72", true), ("ANSWER: 72%", "", false),
                                               ("(72)", "72", true), ("72!", "72", true), ("ANSWER: 7.2e1", "72", true), ("ANSWER: 72 clips", "72", true)]
        for (reply, read, right) in cases {
            let m = EvalExactMatch.gsm8k(reply, target: "72")
            XCTAssertEqual(m.read, read, reply); XCTAssertEqual(m.right, right, reply)
        }
        XCTAssertEqual(EvalExactMatch.gsm8k("ANSWER: 123456", target: "123456").read, "1.2346e+05")
    }

    // MARK: In your runs, first eval, hover

    func test_LAB2070_in_your_runs_picks_small_n_and_a_large_n() {
        let rs = [result("a", task: "hle", score: 1, n: 2), result("b", score: 1, n: 2), result("c", task: "arc", score: 0.72, n: 100),
                  result("d", task: "arc", model: "openai/gpt-5-mini", score: 0.7, n: 40), result("e", score: 0.5, n: 3, status: "failed")]
        let ex = EvalLessonExamples.pick("range", results: rs)
        XCTAssertEqual(ex.rows.map(\.run), ["a", "b", "c"])
        XCTAssertEqual(ex.rows[0].rangeText, "34–100 % · n=2")
        XCTAssertEqual(ex.sentence, "The 2 runs on fewer than 30 questions say almost nothing: each one's range is 34–100 %. The 72 % on 100 questions is a real measurement.")
        XCTAssertTrue(EvalLessonExamples.pick("contamination", results: rs).rows.isEmpty)   // empty state
        let cmp = EvalLessonExamples.pick("compare", results: rs)
        XCTAssertEqual(cmp.rows.count, 2)
    }

    func test_LAB2070_first_eval_checklist_ticks_from_real_state() {
        var s = EvalFirstEval.steps(results: [], openedResults: true, openedQuestion: true, compared: true)
        XCTAssertEqual(s.map(\.done), [false, false, false, false]); XCTAssertEqual(EvalFirstEval.current(s), 1)
        let free = result("f", model: "mockllm/model", score: 0, n: 5)
        s = EvalFirstEval.steps(results: [free], openedResults: true, openedQuestion: false, compared: false)
        XCTAssertEqual(s.map(\.done), [true, true, false, false]); XCTAssertEqual(EvalFirstEval.current(s), 3)
        s = EvalFirstEval.steps(results: [free, result("p", score: 0.8, n: 5, cost: 0.001)], openedResults: true, openedQuestion: true, compared: true)
        XCTAssertNil(EvalFirstEval.current(s))
        // Today's two buttons, unchanged.
        XCTAssertEqual(EvalFirstEval.freePlan.models, ["mockllm/model"]); XCTAssertEqual(EvalFirstEval.freePlan.limit, 5)
        XCTAssertEqual(EvalFirstEval.freePlan.cap, 0)
        XCTAssertEqual(EvalFirstEval.cheapPlan.models, ["anthropic/claude-haiku-5-5"]); XCTAssertEqual(EvalFirstEval.cheapPlan.cap, 0.05)
    }

    func test_LAB2070_every_hover_opens_a_lesson_that_exists() {
        let ids = Set(book.lessons.map(\.id))
        for k in EvalHover.Kind.allCases { XCTAssertTrue(ids.contains(EvalHover.lesson(k)), k.rawValue) }
        XCTAssertEqual(EvalHover.lesson(.range), "range"); XCTAssertEqual(EvalHover.lesson(.passK), "passk")
        // The spec's example: "75 % on 20 cases: the true score is probably between 53 % and 89 %".
        let r = EvalStats.wilson(0.75, n: 20)
        XCTAssertEqual(EvalHover.range(score: 0.75, n: 20, lo: r.lo, hi: r.hi, unit: "case"),
                       "75 % on 20 cases: the true score is probably between 53 % and 89 %. Under 30: read it as a rough guide.")
        XCTAssertEqual(EvalHover.compare(diff: 0.08, lo: -0.03, hi: 0.19, paired: true),
                       "+8 points, 95 % range -3 to +19 (paired). The range includes 0: not distinguishable.")
        XCTAssertEqual(EvalHover.canTell(points: 12.3), "About ±12 points: two contestants closer than that cannot be told apart on this run.")
        XCTAssertEqual(EvalLessons.forMarking("A model grades it: judges have biases"), "judges")
        XCTAssertEqual(EvalLessons.forMarking("The last number is compared"), "exact-match")
    }

    // MARK: M9 stage-2 QA fixes

    func test_QA_compare_calls_no_winner_on_fewer_than_ten_shared_questions() {
        func s(_ id: String, _ v: Double) -> EvalSample { EvalSample(sampleID: id, epoch: 1, score: v) }
        let c = EvalStats.compare([s("q1", 1), s("q2", 1)], [s("q1", 0), s("q2", 0)])!   // zero spread: a zero-width range
        XCTAssertEqual(c.verdict, .noise); XCTAssertTrue(c.tooFew); XCTAssertEqual(c.n, 2)
        let ids = (0..<10).map { "q\($0)" }
        XCTAssertEqual(EvalStats.compare(ids.map { s($0, 1) }, ids.map { s($0, 0) })?.verdict, .aBetter)   // 10 is enough
        let r = EvalCompareResult(diff: 1, ci95: [1, 1], n: 2, paired: true, verdict: "noise", onlyA: ["q1", "q2"], onlyB: [], tied: 0, tooFew: true)
        XCTAssertEqual(r.headline(a: "A", b: "B"), "Can't tell them apart yet — too few shared questions (2)")
        XCTAssertTrue(r.sentence(a: "A", b: "B").contains("too few to call"))
    }

    func test_QA_a_seat_run_waiting_on_unknown_use_offers_run_anyway() throws {
        let row = try JSONDecoder().decode(EvalRunRow.self, from: Data("""
        {"id": "r", "status": "waiting", "progress": "0/4", "seat": "C1", "waiting": "seat use unknown: One Roof cannot see how much of C1's 5-hour window is used, so it waits until it can (under 90 %), or press Run anyway"}
        """.utf8))
        XCTAssertTrue(row.waitsForUnknownSeat)
        let pressed = try JSONDecoder().decode(EvalRunRow.self, from: Data("""
        {"id": "r", "status": "waiting", "progress": "0/4", "seat": "C1", "waiting": "seat use unknown: …", "seat_unknown_ok": true}
        """.utf8))
        XCTAssertFalse(pressed.waitsForUnknownSeat)
        let full = try JSONDecoder().decode(EvalRunRow.self, from: Data("""
        {"id": "r", "status": "waiting", "progress": "0/4", "seat": "C1", "waiting": "waiting for seat C1: 93 % of its 5-hour window used (limit 90 %)"}
        """.utf8))
        XCTAssertFalse(full.waitsForUnknownSeat)
    }
}
