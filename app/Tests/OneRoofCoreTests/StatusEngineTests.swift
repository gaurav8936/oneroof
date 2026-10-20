import XCTest
@testable import OneRoofCore

/// LAB-14: the status engine roofd runs per session (T14 §3f).
final class StatusEngineTests: XCTestCase {
    let t0 = Date(timeIntervalSince1970: 2_000_000)
    func at(_ s: Double) -> Date { t0.addingTimeInterval(s) }

    func obs(_ s: Double, _ agent: AgentKind? = .claude, out: Double?, screen: String = "> ") -> StatusEngine.Observation {
        .init(now: at(s), agent: agent, lastOutput: out.map(at), screen: screen)
    }

    func testOutputMeansWorkingThenQuietMeansDone() {
        var e = StatusEngine()
        e.evaluate(obs(0, out: 0))
        e.evaluate(obs(1.5, out: 0.2))
        XCTAssertTrue(e.ready, "startup drawn")
        XCTAssertEqual(e.status, .idle, "startup output is not a turn")
        XCTAssertEqual(e.evaluate(obs(1.7, out: 1.6)), .working)
        XCTAssertEqual(e.evaluate(obs(2, out: 1.8)), .working)
        XCTAssertEqual(e.evaluate(obs(3.5, out: 1.8)), .working, "within doneAfter of the last output")
        XCTAssertEqual(e.evaluate(obs(5, out: 1.8)), .done)
        e.input(at: at(6))
        XCTAssertEqual(e.status, .idle, "input clears done")
        XCTAssertEqual(e.evaluate(obs(10, out: 1.8)), .idle)
    }

    /// Found by the opening-message test: start-up output must not turn into "working, then done" once ready.
    func testStartupOutputDoesNotBecomeATurnAfterReady() {
        var e = StatusEngine()
        e.evaluate(obs(0, out: 0.1))
        XCTAssertEqual(e.evaluate(obs(1.1, out: 0.1)), .idle)
        XCTAssertTrue(e.ready)
        for t in stride(from: 1.4, through: 8, by: 0.5) { XCTAssertEqual(e.evaluate(obs(t, out: 0.1)), .idle, "t=\(t)") }
        XCTAssertEqual(e.evaluate(obs(9, out: 8.9)), .working, "new output after ready is work")
    }

    func testSeenClearsDone() {
        var e = StatusEngine()
        e.evaluate(obs(0, out: 0))
        e.evaluate(obs(1.5, out: 0.2))                 // ready
        e.evaluate(obs(2, out: 1.9))                   // a turn
        e.evaluate(obs(6, out: 2.5))
        XCTAssertEqual(e.status, .done)
        e.seen()
        XCTAssertEqual(e.evaluate(obs(7, out: 2.5)), .idle)
    }

    func testReadyOnceTheCLIHasDrawnAndGoneQuiet() {
        var e = StatusEngine()
        e.evaluate(obs(0, out: 0))
        XCTAssertFalse(e.ready)
        e.evaluate(obs(0.5, out: 0.4))
        XCTAssertFalse(e.ready)
        XCTAssertEqual(e.evaluate(obs(2, out: 0.5)), .idle)
        XCTAssertTrue(e.ready)
    }

    func testSpinnerLineMeansWorkingEvenWhenQuiet() {
        var e = StatusEngine()
        XCTAssertEqual(e.evaluate(obs(10, out: 1, screen: "✻ Thinking… (12s · esc to interrupt)\n> ")), .working)
        XCTAssertTrue(StatusEngine.workingLine("• Working (3s • esc to interrupt)"))
        XCTAssertFalse(StatusEngine.workingLine("all done\n> "))
    }

    /// Every agent's permission prompt fixture reads as blocked (Needs you).
    func testPermissionPromptsBlockForEveryAgent() {
        let cases: [(AgentKind, String)] = [
            (.claude, Fixture.claudeBashPrompt), (.claude, Fixture.claudeEditPrompt),
            (.codex, Fixture.codexPushPrompt), (.kimi, Fixture.kimiInstallPrompt),
            (.gemini, Fixture.geminiDeletePrompt), (.agy, Fixture.antigravityNetworkPrompt),
        ]
        for (agent, screen) in cases {
            var e = StatusEngine()
            XCTAssertEqual(e.evaluate(obs(5, agent, out: 4, screen: screen)), .blocked, "\(agent)")
        }
    }

    func testAnAnsweredPromptStillOnScreenDoesNotBlock() {
        var e = StatusEngine()
        let answered = Fixture.claudeBashPrompt + "\npushed to origin/main\n\n> "
        XCTAssertNotEqual(e.evaluate(obs(9, out: 8, screen: answered)), .blocked)
        XCTAssertEqual(e.evaluate(obs(12, out: 11, screen: Fixture.claudeBashPrompt)), .blocked)
    }

    /// Found by the side-by-side run: Claude's first-run folder-trust screen needs the owner; its
    /// "Esc to cancel" hint is not a spinner.
    func testFolderTrustMenuNeedsYou() {
        let trust = """
         Accessing workspace:

         /Users/x/Projects/scratch

         Quick safety check: Is this a project you created or one you trust?

         ❯ No, exit
           Yes, I trust this folder

         Enter to confirm · Esc to cancel
        """
        var e = StatusEngine()
        e.evaluate(obs(0, out: 0, screen: trust))
        XCTAssertEqual(e.evaluate(obs(3, out: 0.2, screen: trust)), .blocked)
        XCTAssertFalse(e.ready)
        XCTAssertTrue(StatusEngine.selectionMenu(trust))
        XCTAssertFalse(StatusEngine.selectionMenu("✻ Thinking… (esc to interrupt)\n> "))
        let mcp = "  2 new MCP servers found in this project\n  ❯ [ ] linear\n    [✔] energy-lab\n       Enable selected\n Space to select · Esc to reject all"
        XCTAssertTrue(StatusEngine.selectionMenu(mcp))
    }

    func testStatusBarRepaintIsNotContent() {
        let a = "answer text\n\n❯ \n────\n[Claude1] 5h 20% · 7d 29%\n⏵⏵ auto mode on\nUpdate available!"
        let b = "answer text\n\n❯ \n────\n[Claude1] 5h 21% · 7d 29%\n⏵⏵ auto mode on\nUpdate available!"
        XCTAssertEqual(StatusEngine.contentKey(a), StatusEngine.contentKey(b))
        XCTAssertNotEqual(StatusEngine.contentKey(a), StatusEngine.contentKey("more answer\n" + a))
        let c = "answer text\n\n────────────────\n❯ \n────────────────\n[Claude1] 5h 20%\n⏵⏵ auto mode on"
        XCTAssertEqual(StatusEngine.contentKey(c), StatusEngine.contentKey(c + "\nUpdate available! Run: brew upgrade"),
                       "a status line appearing below the input box is not content")
    }

    /// Found by the side-by-side run (Antigravity): a still braille spinner is still working.
    func testBrailleSpinnerIsWorking() {
        XCTAssertTrue(StatusEngine.workingLine("touch sbs-marker.txt\n⣻  Generating...\n└ Tip: Use /settings\n────\n>"))
        var e = StatusEngine()
        e.evaluate(obs(0, .agy, out: 0.1)); e.evaluate(obs(1.2, .agy, out: 0.1))
        XCTAssertEqual(e.evaluate(obs(20, .agy, out: 5, screen: "⣻  Generating...\n────\n>")), .working)
    }

    /// Found by the side-by-side run (Claude): a "working" hook with no Stop and an idle screen goes stale.
    func testStaleWorkingHookFallsBackToDone() {
        var e = StatusEngine()
        e.hook("SessionStart", at: at(0))
        e.hook("UserPromptSubmit", at: at(1))
        e.evaluate(obs(2, out: 1.5))
        e.hook("Stop", at: at(10))
        e.hook("PreToolUse", at: at(12))
        XCTAssertEqual(e.evaluate(obs(14, out: 11, screen: "❯ ")), .working)
        XCTAssertEqual(e.evaluate(obs(20, out: 11, screen: "❯ ")), .done, "8 s idle screen after a lone working hook")
        XCTAssertEqual(e.evaluate(obs(20, out: 11, screen: "✻ Building… (esc to interrupt)\n❯ ")), .working, "a spinner keeps it working")
    }

    func testClaudeHooksLead() {
        var e = StatusEngine()
        e.evaluate(obs(0, out: 0))
        e.hook("SessionStart", at: at(1))
        XCTAssertTrue(e.ready)
        XCTAssertEqual(e.evaluate(obs(2, out: 0.2)), .idle)
        e.hook("UserPromptSubmit", at: at(3))
        XCTAssertEqual(e.evaluate(obs(20, out: 3, screen: "✻ Running… (12s · esc to interrupt)\n> ")), .working,
                       "a quiet tool call (spinner on screen) is still working per the hook")
        e.hook("Notification", message: "Claude needs your permission to use Bash", at: at(21))
        XCTAssertEqual(e.evaluate(obs(22, out: 21)), .blocked)
        e.hook("PreToolUse", at: at(30))
        XCTAssertEqual(e.evaluate(obs(31, out: 30)), .working)
        e.hook("Stop", at: at(40))
        XCTAssertEqual(e.evaluate(obs(41, out: 40)), .done)
        // Repaints after the Stop are not a new turn; the next turn sends its own hook.
        XCTAssertEqual(e.evaluate(obs(45, out: 44.9)), .done)
        e.hook("UserPromptSubmit", at: at(50))
        XCTAssertEqual(e.evaluate(obs(51, out: 50.5)), .working)
    }

    func testIdleNotificationDoesNotBlock() {
        var e = StatusEngine()
        e.hook("SessionStart", at: at(0))
        e.hook("Notification", message: "Claude is waiting for your input", at: at(60))
        XCTAssertEqual(e.evaluate(obs(61, out: 0)), .idle)
    }

    func testAgentLeavingResetsToAShell() {
        var e = StatusEngine()
        e.hook("SessionStart", at: at(0))
        e.evaluate(obs(1, out: 0.5))
        XCTAssertEqual(e.evaluate(obs(2, nil, out: 1.9)), .unknown)
        XCTAssertFalse(e.ready)
    }

    func testAgentKindFromProcess() {
        XCTAssertEqual(StatusEngine.agentKind(processName: "claude", argv: ["claude", "--resume"]), .claude)
        XCTAssertEqual(StatusEngine.agentKind(processName: "node", argv: ["node", "/opt/homebrew/lib/node_modules/@openai/codex/bin/codex.js"]), .codex)
        XCTAssertEqual(StatusEngine.agentKind(processName: "kimi-code", argv: ["kimi-code"]), .kimi)
        XCTAssertEqual(StatusEngine.agentKind(processName: "gemini", argv: []), .gemini)
        XCTAssertNil(StatusEngine.agentKind(processName: "zsh", argv: ["-zsh"]))
        XCTAssertNil(StatusEngine.agentKind(processName: "vim", argv: ["vim", "notes.md"]))
    }
}
