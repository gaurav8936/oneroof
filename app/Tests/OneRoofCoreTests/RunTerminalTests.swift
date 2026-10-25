import XCTest
@testable import OneRoofCore

/// LAB-598: Right-click › Run in Terminal — the command cleanup, what is typed, and which terminal gets it.
final class RunTerminalTests: XCTestCase {
    func testPromptMarksAndIndentationGo() {
        XCTAssertEqual(RunTerminal.clean("$ swift test"), "swift test")
        XCTAssertEqual(RunTerminal.clean("  ❯ git status  \n"), "git status")
        XCTAssertEqual(RunTerminal.clean("➜  make build"), "make build")
        XCTAssertEqual(RunTerminal.clean("\n\n   cd app && swift build -j 4\n\n"), "cd app && swift build -j 4")
        XCTAssertEqual(RunTerminal.clean("echo '$ not a prompt'"), "echo '$ not a prompt'")
        XCTAssertEqual(RunTerminal.clean("# a comment stays"), "# a comment stays")
        XCTAssertEqual(RunTerminal.clean("│ $ swift test --filter X   │\n│                            │"), "swift test --filter X", "a TUI box's borders go")
    }

    func testWrappedLinesFromAnAgentScreenJoin() {
        // Claude Code wraps a long command and indents the tail.
        let sel = """
          cd ~/Projects/labs/oneroof/app && swift build -j 4 &&
          swift test --filter NotificationTests
        """
        XCTAssertEqual(RunTerminal.clean(sel), "cd ~/Projects/labs/oneroof/app && swift build -j 4 && swift test --filter NotificationTests")
        let wrapped = """
        python3 scripts/linear/lt.py status --team LAB
            --project LAB-ONEROOF-v0.50
        """
        XCTAssertEqual(RunTerminal.clean(wrapped), "python3 scripts/linear/lt.py status --team LAB --project LAB-ONEROOF-v0.50")
        XCTAssertEqual(RunTerminal.clean("git log --oneline\n  | head -5"), "git log --oneline | head -5")
    }

    func testRealMultiLineCommandsStayMultiLine() {
        XCTAssertEqual(RunTerminal.clean("$ git fetch\n$ git status"), "git fetch\ngit status")
        let block = """
        for f in *.md; do
          wc -l "$f"
        done
        """
        XCTAssertEqual(RunTerminal.clean(block), "for f in *.md; do\n  wc -l \"$f\"\ndone")
        XCTAssertEqual(RunTerminal.clean("swift build \\\n  -j 4"), "swift build \\\n  -j 4")
    }

    func testTypedTextNeverPressesReturn() {
        XCTAssertEqual(RunTerminal.typed("swift test"), "swift test")
        let multi = RunTerminal.typed("git fetch\ngit status")
        XCTAssertEqual(multi, "\u{1B}[200~git fetch\ngit status\u{1B}[201~", "one bracketed paste: zsh waits for Return")
        XCTAssertFalse(multi.hasSuffix("\n") || multi.hasSuffix("\r"))
        XCTAssertEqual(RunTerminal.typed("git fetch\ngit status", bracketedPaste: false), "git fetch; git status")
        XCTAssertEqual(RunTerminal.typed("swift build \\\n  -j 4", bracketedPaste: false), "swift build -j 4")
        XCTAssertEqual(RunTerminal.typed("for f in *; do\n  echo $f\ndone", bracketedPaste: false), "for f in *; do echo $f; done")
        XCTAssertEqual(RunTerminal.typed(""), "")
    }

    func testOneRunTerminalPerParent() {
        let t = Date(timeIntervalSince1970: 1_800_000_000)
        let list = [
            RunTerminal.Candidate(id: "old", parentSessionId: "a", alive: true, createdAt: t),
            RunTerminal.Candidate(id: "new", parentSessionId: "a", alive: true, createdAt: t.addingTimeInterval(60)),
            RunTerminal.Candidate(id: "gone", parentSessionId: "b", alive: false, createdAt: t),
            RunTerminal.Candidate(id: "plain", parentSessionId: nil, alive: true, createdAt: t),
        ]
        XCTAssertEqual(RunTerminal.target(parent: "a", among: list), .reuse("new"))
        XCTAssertEqual(RunTerminal.target(parent: "b", among: list), .create, "an exited run terminal is not reused")
        XCTAssertEqual(RunTerminal.target(parent: "c", among: list), .create)
    }

    func testRunTerminalSitsUnderItsParentInTheList() {
        var agent = Session(id: "a", name: "Fix login", repoPath: "/p/r")
        agent.lifecycle = .idle
        var run = Session(id: "r", name: RunTerminal.name(parent: "Fix login"), agent: .shell, repoPath: "/p/r", lifecycle: .idle)
        run.parentSessionId = "a"
        let other = Session(id: "b", name: "Another", repoPath: "/p/r", lifecycle: .idle)
        let rows = [run, other, agent].map { BoardItem(id: $0.id, session: $0, status: .idle, adopted: false) }
        let g = Board.group(rows, by: .agent)
        XCTAssertEqual(g.count, 1, "the shell joins its parent's group (Claude), not Terminal")
        XCTAssertEqual(g[0].items.map(\.id), ["b", "a", "r"])
        // Pinned parent: the run terminal goes to Pinned with it.
        agent.pinned = true
        let p = Board.group([run, other, agent].map { BoardItem(id: $0.id, session: $0, status: .idle, adopted: false) }, by: .status)
        XCTAssertEqual(p.first?.title, "Pinned")
        XCTAssertEqual(p.first?.items.map(\.id), ["a", "r"])
    }

    /// LAB-726: an exited run terminal (or plain terminal) goes to Exited, not Active under its working parent.
    func test_LAB726_exitedTerminalsLeaveTheActiveGroup() {
        let agent = Session(id: "a", name: "Building v0.50", repoPath: "/p/r", lifecycle: .idle)
        var run = Session(id: "r", name: RunTerminal.name(parent: "Building v0.50"), agent: .shell, repoPath: "/p/r", lifecycle: .idle)
        run.parentSessionId = "a"
        let term = Session(id: "t", name: "TERMINAL", agent: .shell, repoPath: "/p", lifecycle: .idle)
        let rows = [BoardItem(id: "a", session: agent, status: .running, adopted: false),
                    BoardItem(id: "r", session: run, status: .exited, adopted: false),
                    BoardItem(id: "t", session: term, status: .exited, adopted: false)]
        let g = Board.group(rows, by: .status)
        XCTAssertEqual(g.map(\.title), ["Active", "Exited"])
        XCTAssertEqual(g[0].items.map(\.id), ["a"])
        XCTAssertEqual(Set(g[1].items.map(\.id)), ["r", "t"])
        // Still running: it stays right under its parent.
        let live = Board.group([rows[0], BoardItem(id: "r", session: run, status: .idle, adopted: false)], by: .status)
        XCTAssertEqual(live.map(\.title), ["Active"])
        XCTAssertEqual(live[0].items.map(\.id), ["a", "r"])
        // Other groupings keep it with its parent whatever its state.
        XCTAssertEqual(Board.group(Array(rows.prefix(2)), by: .agent).count, 1)
    }

    func testParentSurvivesSaveAndOldRowsLoad() throws {
        var s = Session(name: "Run · x", agent: .shell, repoPath: "/p")
        s.parentSessionId = "parent-1"
        let d = try JSONEncoder().encode(s)
        XCTAssertEqual(try JSONDecoder().decode(Session.self, from: d).parentSessionId, "parent-1")
        let old = #"{"id":"1","name":"n","agent":"claude","repoPath":"/p"}"#
        XCTAssertNil(try JSONDecoder().decode(Session.self, from: Data(old.utf8)).parentSessionId)
    }
}
