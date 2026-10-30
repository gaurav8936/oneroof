import XCTest
@testable import OneRoofCore

/// LAB-1592: what the Needs you simulator found, with the screens captured from Claude Code 2.1.287 (2026-10-29).
final class NeedsYouSimulatorTests: XCTestCase {
    let t0 = Date(timeIntervalSince1970: 3_000_000)
    func at(_ s: Double) -> Date { t0.addingTimeInterval(s) }
    func obs(_ s: Double, out: Double, _ screen: String) -> StatusEngine.Observation {
        .init(now: at(s), agent: .claude, lastOutput: at(out), screen: screen)
    }

    /// Claude Code 2.1's permission prompt: description first, the command between dashed rules, option 2 wrapped.
    static let bashPrompt21 = """
    ⏺ Creating empty file made-by-sim.txt
      ⎿  $ touch made-by-sim.txt

    ────────────────────────────────────────────────────────────────────────────────
     Bash command
     Create empty file made-by-sim.txt
    ╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌
     touch made-by-sim.txt
    ╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌
     Do you want to proceed?
     ❯ 1. Yes
       2. Yes, and always allow access to
          /Users/x/Projects/scratch/simrepo from
          this project
       3. No

     Esc to cancel · Tab to amend
    """

    /// The idle input box Claude shows after the owner denied that prompt (no hook follows a denial).
    static let idleBox = """
    ❯ Run this exact shell command with your Bash tool: touch made-by-sim.txt

    ────────────────────────────────────────────────────────────────────────────────
    ❯
    ────────────────────────────────────────────────────────────────────────────────
      [Claude1] someone@example · Max 20x · 5h 4% · 7d 51%
      ⏸ manual mode on · ← for agents
    """

    /// Claude's question tool with four options, each with a two-line description: the selected option sits 18
    /// lines above the hint.
    static let tallQuestion = """
    ❯ Now ask which of four databases I want.
    ────────────────────────────────────────────────────────────────────────────────
     ☐ Database

    Which database do you want?

    ❯ 1. Postgres
         A powerful, open-source relational database with advanced features like JSON support and full-text search.
         Excellent for production systems requiring reliability and scalability.
      2. SQLite
         A lightweight, file-based database that requires no server setup. Perfect for development, testing, and
         applications that need portability.
      3. MySQL
         A fast, widely-used relational database with strong performance for read-heavy applications. Popular in web
         development and paired with many frameworks.
      4. DuckDB
         An in-process analytical database designed for fast OLAP queries on large datasets. Ideal for data analysis and
         reporting workloads.
      5. Type something.
    ────────────────────────────────────────────────────────────────────────────────
      6. Chat about this

    Enter to select · ↑/↓ to navigate · Esc to cancel
    """

    /// Found by the simulator, confirmed with real Claude: a denied permission sends no hook (no PostToolUse, no Stop),
    /// so the hook's "blocked" kept the session in Needs you over an idle input box until its next turn.
    func test_LAB1592_deniedPermissionLeavesNeedsYou() {
        var e = StatusEngine()
        e.evaluate(obs(0, out: 0, Self.idleBox))                      // the agent is seen first, then its hooks
        e.hook("SessionStart", at: at(0))
        e.hook("UserPromptSubmit", at: at(1))
        e.hook("PreToolUse", at: at(5))
        e.hook("Notification", message: "Claude needs your permission", at: at(5.1))
        XCTAssertEqual(e.evaluate(obs(7, out: 5, Self.bashPrompt21)), .blocked)
        XCTAssertEqual(e.evaluate(obs(20, out: 5, Self.bashPrompt21)), .blocked, "still waiting: nobody typed")
        e.input(at: at(21))                                            // "3" = No
        XCTAssertEqual(e.evaluate(obs(21.5, out: 21.3, Self.idleBox)), .blocked, "the CLI is still redrawing")
        XCTAssertEqual(e.evaluate(obs(24, out: 21.3, Self.idleBox)), .idle, "the prompt is gone and was answered")
        XCTAssertEqual(e.evaluate(obs(60, out: 21.3, Self.idleBox)), .idle)
        e.hook("UserPromptSubmit", at: at(70))
        XCTAssertEqual(e.evaluate(obs(71, out: 70.5, "✻ Thinking… (1s · esc to interrupt)\n" + Self.idleBox)), .working, "the next turn")
    }

    /// An approved command that runs a while: no PostToolUse yet, the prompt gone, a spinner on screen → working.
    func test_LAB1592_approvedLongToolIsWorkingNotNeedsYou() {
        var e = StatusEngine()
        e.evaluate(obs(0, out: 0, Self.idleBox))                      // the agent is seen first, then its hooks
        e.hook("SessionStart", at: at(0))
        e.hook("Notification", message: "Claude needs your permission to use Bash", at: at(5))
        XCTAssertEqual(e.evaluate(obs(6, out: 5, Self.bashPrompt21)), .blocked)
        e.input(at: at(10))                                            // "1" = Yes
        let running = "⏺ Bash(swift build)\n  ⎿  Running…\n\n✻ Building… (12s · esc to interrupt)\n" + Self.idleBox
        XCTAssertEqual(e.evaluate(obs(22, out: 21.8, running)), .working)
        e.hook("PostToolUse", at: at(30))
        e.hook("Stop", at: at(31))
        XCTAssertEqual(e.evaluate(obs(32, out: 31, Self.idleBox)), .done)
    }

    /// A question still on screen stays in Needs you while the owner moves through its options.
    func test_LAB1592_navigatingAQuestionStaysNeedsYou() {
        var e = StatusEngine()
        e.evaluate(obs(0, out: 0, Self.idleBox))                      // the agent is seen first, then its hooks
        e.hook("SessionStart", at: at(0))
        e.hook("PreToolUse", at: at(3))
        e.hook("Notification", message: "Claude needs your permission", at: at(3.1))
        XCTAssertEqual(e.evaluate(obs(4, out: 3, Self.tallQuestion)), .blocked)
        e.input(at: at(8))                                             // ↓
        let moved = Self.tallQuestion.replacingOccurrences(of: "❯ 1. Postgres", with: "  1. Postgres")
            .replacingOccurrences(of: "  2. SQLite", with: "❯ 2. SQLite")
        XCTAssertEqual(e.evaluate(obs(8.2, out: 8.1, moved)), .blocked)
        XCTAssertEqual(e.evaluate(obs(12, out: 8.1, moved)), .blocked)
    }

    /// The tall question is a menu even with no hook (a session whose hooks are not installed, another account).
    func test_LAB1592_tallQuestionMenuNeedsYouWithoutHooks() {
        XCTAssertTrue(StatusEngine.selectionMenu(Self.tallQuestion))
        var e = StatusEngine()
        e.evaluate(obs(0, out: 0, Self.idleBox))
        e.evaluate(obs(2, out: 0.2, Self.idleBox))                    // ready
        XCTAssertEqual(e.evaluate(obs(10, out: 9, Self.tallQuestion)), .blocked)
        XCTAssertFalse(StatusEngine.selectionMenu(Self.idleBox), "the idle input box is not a menu")
        XCTAssertFalse(StatusEngine.selectionMenu("❯ 1. fix the parser\n" + String(repeating: "text\n", count: 20) + "─────\n❯ \n─────"),
                       "a numbered line without a menu hint is not a menu")
    }

    /// Needs you shows the command Claude 2.1 asks to run (it showed the description), and Deny finds "No".
    func test_LAB1592_claude21PromptReadsTheCommand() throws {
        let m = try XCTUnwrap(DecisionMatcher.match(Self.bashPrompt21, agent: .claude))
        XCTAssertEqual(m.ask, .command)
        XCTAssertEqual(m.command, "touch made-by-sim.txt")
        XCTAssertEqual(m.options.map(\.key), ["1", "2", "3"])
        XCTAssertEqual(m.options[1].label, "Yes, and always allow access to /Users/x/Projects/scratch/simrepo from this project")
        XCTAssertEqual(AnswerKeys.keys(for: .deny, prompt: m, agent: .claude).sends, ["3"])
        XCTAssertEqual(AnswerKeys.keys(for: .always, prompt: m, agent: .claude).sends, ["2"])
        let d = try XCTUnwrap(DecisionBuilder.build(DecisionContext(sessionId: "s", agent: .claude, terminalText: Self.bashPrompt21,
                                                                    repoPath: "/Users/x/Projects/scratch/simrepo", now: t0)))
        XCTAssertEqual(d.command, "touch made-by-sim.txt")
        XCTAssertEqual(d.kind, .runCommand)
        // Without hooks too: the wrapped option made the prompt look answered, and its "Esc to cancel" hint then read
        // as a spinner, so the session showed as working.
        XCTAssertTrue(StatusEngine.isLive(m, in: Self.bashPrompt21))
        var e = StatusEngine()
        e.evaluate(obs(0, out: 0, Self.idleBox))
        e.evaluate(obs(2, out: 0.2, Self.idleBox))
        XCTAssertEqual(e.evaluate(obs(10, out: 9, Self.bashPrompt21)), .blocked)
    }
}
