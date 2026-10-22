import XCTest
@testable import OneRoofCore

final class CaptionHeuristicTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let plan = CaptionPlan(titles: ["Read the spec", "Write the engines", "Write tests", "Commit"], current: 3)

    struct Case {
        var name: String
        var agent: AgentKind = .claude
        var status: SessionStatus = .running
        var text: String
        var plan: CaptionPlan? = nil
        var schedule: Schedule? = nil
        var lastResult: String? = nil
        var idleFor: TimeInterval? = nil
        var expected: String?
    }

    var cases: [Case] {
        [
            // Claude
            Case(name: "claude update", text: "⏺ I'll update the parser.\n\n⏺ Update(Sources/OneRoofCore/Captions.swift)\n  ⎿  Updated Sources/OneRoofCore/Captions.swift with 3 additions", expected: "Editing Captions.swift"),
            Case(name: "claude edit bullet", text: "● Edit(Sources/App/App.swift)", expected: "Editing App.swift"),
            Case(name: "claude bash", text: "⏺ Bash(swift test --filter CaptionTests)\n  ⎿  Running…", expected: "Running swift"),
            Case(name: "claude bash cd prefix", text: "⏺ Bash(cd app && swift build)", expected: "Running swift"),
            Case(name: "claude bash env prefix", text: "⏺ Bash(ONEROOF_SELFTEST=1 npm run e2e)", expected: "Running npm"),
            Case(name: "claude read", text: "⏺ Read(README.md)\n  ⎿  Read 120 lines", expected: "Reading README.md"),
            Case(name: "claude read labelled", text: "● Read(file_path: \"/Users/x/Projects/a/b.py\")", expected: "Reading b.py"),
            Case(name: "claude task", text: "⏺ Task(Explore the codebase)\n  ⎿  Initializing…", expected: "Waiting on subagent Explore the codebase"),
            Case(name: "claude write", text: "⏺ Write(docs/notes.md)", expected: "Editing notes.md"),
            Case(name: "claude last tool wins", text: "⏺ Read(package.json)\n  ⎿  Read 40 lines\n\n⏺ Bash(npm ci)\n  ⎿  added 300 packages", expected: "Running npm"),
            Case(name: "claude todo ignored", text: "⏺ Bash(make lint)\n\n⏺ TodoWrite(3 todos)", expected: "Running make"),
            Case(name: "claude plan step", text: "⏺ Bash(swift test)", plan: plan, expected: "Step 3 of 4 · Write tests"),
            Case(name: "claude xctest count", text: "⏺ Bash(swift test)\n  ⎿  Executed 63 tests, with 0 failures (0 unexpected) in 1.2 (1.3) seconds", expected: "Running swift · tests 63/63"),
            Case(name: "claude xctest failures", text: "⏺ Bash(swift test)\n  ⎿  Executed 64 tests, with 2 failures (0 unexpected) in 1.0 (1.1) seconds", expected: "Running swift · tests 62/64"),
            Case(name: "claude pytest", text: "⏺ Bash(pytest -q)\n  ⎿  ===== 2 failed, 40 passed in 3.1s =====", expected: "Running pytest · tests 40/42"),
            Case(name: "plan + tests", text: "⏺ Bash(swift test)\n  ⎿  Executed 10 tests, with 0 failures", plan: plan, expected: "Step 3 of 4 · Write tests · tests 10/10"),
            Case(name: "ansi escapes", text: "\u{1B}[1m⏺\u{1B}[0m Bash(ls -la)", expected: "Running ls"),
            Case(name: "prose is not a tool", text: "⏺ Fix(the bug) is what I'll do next.", expected: nil),
            // Codex
            Case(name: "codex vitest", agent: .codex, text: "• Ran npm test\n      Tests  42 passed (42)", expected: "Running npm · tests 42/42"),
            Case(name: "codex jest", agent: .codex, text: "• Ran npx jest\nTests:       1 failed, 41 passed, 42 total", expected: "Running npx · tests 41/42"),
            Case(name: "codex cargo", agent: .codex, text: "• Ran cargo test\ntest result: ok. 12 passed; 0 failed; 0 ignored", expected: "Running cargo · tests 12/12"),
            Case(name: "codex edited", agent: .codex, text: "• Edited Sources/main.rs (+3 -1)", expected: "Editing main.rs"),
            Case(name: "codex explored", agent: .codex, text: "• Explored\n  └ Read config.toml", expected: "Reading config.toml"),
            Case(name: "codex ran git", agent: .codex, text: "• Ran git status --short", expected: "Running git"),
            // Kimi
            Case(name: "kimi shell", agent: .kimi, text: "• Used Shell (make build)", expected: "Running make"),
            Case(name: "kimi read", agent: .kimi, text: "Used ReadFile (src/app.ts)", expected: "Reading app.ts"),
            Case(name: "kimi replace", agent: .kimi, text: "• Used StrReplaceFile (src/app.ts)", expected: "Editing app.ts"),
            // Gemini
            Case(name: "gemini shell boxed", agent: .gemini, text: "│ ✔ Shell npm run lint (Lint the code) │", expected: "Running npm"),
            Case(name: "gemini read", agent: .gemini, text: "✔ ReadFile src/index.ts", expected: "Reading index.ts"),
            Case(name: "gemini write", agent: .gemini, text: "✔ WriteFile docs/plan.md", expected: "Editing plan.md"),
            // Blocked
            Case(name: "blocked claude bash", status: .needsYou, text: Fixture.claudeBashPrompt, expected: "Needs you · run swift test --filter CaptionTests"),
            Case(name: "blocked codex push", agent: .codex, status: .needsYou, text: Fixture.codexPushPrompt, expected: "Needs you · run git push origin work"),
            Case(name: "blocked claude edit", status: .needsYou, text: Fixture.claudeEditPrompt, expected: "Needs you · Do you want to make this edit to Feed.swift?"),
            Case(name: "blocked plain question", status: .needsYou, text: "⏺ Two options fit.\n\nWhich database should I use, Postgres or SQLite?", expected: "Needs you · Which database should I use, Postgres or SQLite?"),
            // Done
            Case(name: "done claude", status: .done, text: "⏺ Bash(swift test)\n  ⎿  ok\n\n⏺ All 63 tests pass. The caption engine is ready for review.\n\n╭────╮\n│ >  │\n╰────╯\n  ? for shortcuts", expected: "Ready · The caption engine is ready for review."),
            Case(name: "done codex long", agent: .codex, status: .done, text: "• I rewrote the scheduler so that every session gets a fair turn even when one is very chatty and noisy.", expected: "Ready · I rewrote the scheduler so that every session gets a fair t…"),
            Case(name: "done silent", status: .done, text: "", expected: "Ready"),
            // Idle
            Case(name: "idle with command", status: .idle, text: "⏺ Bash(git status)\n  ⎿  clean", idleFor: 12 * 60, expected: "Idle 12m · last: git status"),
            Case(name: "idle no command", status: .idle, text: "", idleFor: 3 * 3600, expected: "Idle 3h"),
            // Scheduled
            Case(name: "scheduled with result", status: .planned, text: "", schedule: .tonight(hour: 2, minute: 0), lastResult: "4 of 4 done", expected: "Runs at 2:00 AM · last night 4 of 4 done"),
            Case(name: "scheduled nightly", status: .next, text: "", schedule: .nightly(hour: 23, minute: 30), expected: "Runs at 11:30 PM"),
            // Nothing true to say
            Case(name: "running nothing yet", text: "Welcome to Claude Code", expected: nil),
            Case(name: "planned", status: .planned, text: "", expected: nil),
        ]
    }

    func testFixtures() {
        XCTAssertGreaterThanOrEqual(cases.count, 30)
        for c in cases {
            let input = CaptionInput(text: c.text, agent: c.agent, status: c.status, plan: c.plan, schedule: c.schedule,
                                     lastScheduledResult: c.lastResult, lastActivity: c.idleFor.map { now.addingTimeInterval(-$0) }, now: now)
            let cap = CaptionEngine.heuristic(input)
            XCTAssertEqual(cap?.text, c.expected, c.name)
            if let cap {
                XCTAssertLessThanOrEqual(cap.text.count, Caption.maxText, c.name)
                XCTAssertLessThanOrEqual(cap.now?.count ?? 0, Caption.maxNow, c.name)
                XCTAssertEqual(cap.source, .heuristic)
            }
        }
    }

    func testNowCarriesTheFullAction() {
        let cap = CaptionEngine.heuristic(CaptionInput(text: "⏺ Bash(cd app && swift test --filter CaptionTests)", status: .running, plan: plan, now: now))
        XCTAssertEqual(cap?.now, "Running swift test --filter CaptionTests")
        XCTAssertEqual(cap?.step, 3)
        XCTAssertEqual(cap?.steps, 4)
    }

    func testLongCaptionIsClippedTo72() {
        let name = String(repeating: "a", count: 80) + ".swift"
        let cap = CaptionEngine.heuristic(CaptionInput(text: "⏺ Edit(\(name))", status: .running, now: now))
        XCTAssertEqual(cap?.text.count, 72)
        XCTAssertTrue(cap?.text.hasSuffix("…") ?? false)
    }

    func testInputKeepsLast6000Chars() {
        let input = CaptionInput(text: String(repeating: "x", count: 10_000), status: .running)
        XCTAssertEqual(input.text.count, 6_000)
    }

    func testAgeText() {
        XCTAssertEqual(CaptionEngine.ageText(30), "<1m")
        XCTAssertEqual(CaptionEngine.ageText(125), "2m")
        XCTAssertEqual(CaptionEngine.ageText(7200), "2h")
        XCTAssertEqual(CaptionEngine.ageText(3 * 86_400), "3d")
    }
}

final class CaptionModelTests: XCTestCase {
    let input = CaptionInput(text: "⏺ Bash(swift test)\n  ⎿  Executed 63 tests, with 0 failures", status: .running,
                             plan: CaptionPlan(titles: ["Spec", "Build", "Test", "Ship"], current: 3), now: Date(timeIntervalSince1970: 0))

    func testValidReplyReplacesHeuristic() {
        let raw = #"{"caption":"Running the 63 tests for the engines","step":3,"steps":4,"now":"swift test","events":[{"kind":"step finished","text":"Build done"},{"kind":"weather","text":"x"}]}"#
        let h = CaptionEngine.heuristic(input)
        let (cap, events) = CaptionEngine.resolve(heuristic: h, modelReply: raw, input: input, sessionId: "s1")
        XCTAssertEqual(cap?.source, .model)
        XCTAssertEqual(cap?.text, "Running the 63 tests for the engines")
        XCTAssertEqual(events.map(\.kind), [.stepDone])   // unknown kinds dropped
        XCTAssertEqual(events.first?.sessionId, "s1")
    }

    func testFencedReplyParses() {
        let raw = "Here you go:\n```json\n{\"caption\": \"Running tests\", \"now\": \"swift test\"}\n```"
        XCTAssertEqual(CaptionEngine.parseModelReply(raw)?.caption, "Running tests")
        XCTAssertNil(CaptionEngine.validationError(CaptionEngine.parseModelReply(raw)!, input: input))
    }

    func testInvalidJSONKeepsHeuristic() {
        let h = CaptionEngine.heuristic(input)
        let (cap, events) = CaptionEngine.resolve(heuristic: h, modelReply: "{caption: running", input: input, sessionId: "s")
        XCTAssertEqual(cap, h)
        XCTAssertTrue(events.isEmpty)
        XCTAssertNil(CaptionEngine.parseModelReply("no json here"))
        XCTAssertNil(CaptionEngine.parseModelReply(#"{"step": 2}"#))   // caption is required
    }

    func testRejectsLongCaptionAndNow() {
        let long = CaptionEngine.ModelReply(caption: String(repeating: "x", count: 73))
        XCTAssertNotNil(CaptionEngine.validationError(long, input: input))
        let longNow = CaptionEngine.ModelReply(caption: "ok", now: String(repeating: "y", count: 91))
        XCTAssertNotNil(CaptionEngine.validationError(longNow, input: input))
        XCTAssertNotNil(CaptionEngine.validationError(CaptionEngine.ModelReply(caption: "  "), input: input))
    }

    func testRejectsInventedNumbers() {
        let r = CaptionEngine.ModelReply(caption: "Running 120 tests")
        XCTAssertEqual(CaptionEngine.validationError(r, input: input), "invented number 120")
        XCTAssertNil(CaptionEngine.validationError(CaptionEngine.ModelReply(caption: "Running 63 tests"), input: input))
    }

    func testRejectsBadSteps() {
        XCTAssertNotNil(CaptionEngine.validationError(CaptionEngine.ModelReply(caption: "x", step: 5, steps: 4), input: input))
        XCTAssertNotNil(CaptionEngine.validationError(CaptionEngine.ModelReply(caption: "x", step: 0), input: input))
        XCTAssertNotNil(CaptionEngine.validationError(CaptionEngine.ModelReply(caption: "x", step: 1, steps: 3), input: input))
    }

    func testPromptCarriesPlanToolsAndText() throws {
        let p = CaptionEngine.userPrompt(input)
        XCTAssertTrue(p.contains("current step 3 of 4"))
        XCTAssertTrue(p.contains("Bash(swift test)"))
        XCTAssertTrue(p.contains("Executed 63 tests"))
        let body = try JSONSerialization.jsonObject(with: CaptionEngine.requestBody(input)) as? [String: Any]
        let messages = body?["messages"] as? [[String: String]]
        XCTAssertEqual(messages?.first?["content"], CaptionEngine.systemPrompt)
        XCTAssertEqual(body?["temperature"] as? Int, 0)
    }
}

extension CaptionEngine.ModelReply {
    init(caption: String, step: Int? = nil, steps: Int? = nil, now: String? = nil) {
        self.init(caption: caption, step: step, steps: steps, now: now, events: nil)
    }
}

final class CaptionSchedulerTests: XCTestCase {
    let t0 = Date(timeIntervalSince1970: 1000)

    func testDebounceThenThrottle() {
        var s = CaptionScheduler()
        s.noteOutput("a", at: t0)
        XCTAssertEqual(s.take(now: t0.addingTimeInterval(1)), [])          // still typing
        XCTAssertEqual(s.take(now: t0.addingTimeInterval(2)), ["a"])
        s.finish("a")
        s.noteOutput("a", at: t0.addingTimeInterval(3))
        XCTAssertEqual(s.take(now: t0.addingTimeInterval(5.5)), [])        // < 5 s since the last run
        XCTAssertEqual(s.nextWake(now: t0.addingTimeInterval(5.5)), t0.addingTimeInterval(7))
        XCTAssertEqual(s.take(now: t0.addingTimeInterval(7)), ["a"])
    }

    func testStatusChangeIsImmediate() {
        var s = CaptionScheduler()
        s.noteOutput("a", at: t0); _ = s.take(now: t0.addingTimeInterval(2)); s.finish("a")
        s.noteStatusChange("a", at: t0.addingTimeInterval(2.5))
        XCTAssertEqual(s.take(now: t0.addingTimeInterval(2.5)), ["a"])
    }

    func testAtMostTwoInFlight() {
        var s = CaptionScheduler()
        for id in ["a", "b", "c"] { s.noteStatusChange(id, at: t0) }
        XCTAssertEqual(s.take(now: t0), ["a", "b"])
        XCTAssertEqual(s.inFlightCount, 2)
        XCTAssertEqual(s.take(now: t0), [])
        s.finish("a")
        XCTAssertEqual(s.take(now: t0), ["c"])
    }

    func testRoundRobinIsFair() {
        var s = CaptionScheduler(maxConcurrent: 1)
        for id in ["a", "b", "c"] { s.noteStatusChange(id, at: t0) }
        var served: [String] = []
        for _ in 0..<3 {
            let got = s.take(now: t0); served += got; got.forEach { s.finish($0) }
            s.noteStatusChange("a", at: t0)   // "a" is chatty
        }
        XCTAssertEqual(served, ["a", "b", "c"])
    }

    func testNothingPendingNoWake() {
        var s = CaptionScheduler()
        XCTAssertNil(s.nextWake(now: t0))
        s.noteOutput("a", at: t0)
        s.remove("a")
        XCTAssertNil(s.nextWake(now: t0))
        XCTAssertFalse(s.isDue("a", now: t0.addingTimeInterval(10)))
    }
}
