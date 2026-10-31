import XCTest
@testable import OneRoofCore

/// LAB-1933 · "session" means a session a person started. A loop round (tagged `loop:<id>` by roofd's loop engine)
/// must never appear in the session rail, Needs you, the All · Active · Exited counts, the catalog or search.
final class LoopSessionScopeTests: XCTestCase {
    private func row(_ name: String, tags: [String] = [], status: SessionStatus = .running) -> BoardItem {
        let s = Session(name: name, agent: .claude, repoPath: "/tmp/repo", tags: tags)
        return BoardItem(id: s.id, session: s, status: status, adopted: false)
    }

    func test_LAB1933_loopRoundsNeverInTheSessionList() {
        let manual = row("1933 REVIEW"), other = row("Release notes", tags: ["wip"], status: .exited)
        let loop = row("oneroof-nightly-bugs · round 3", tags: ["loop:oneroof-nightly-bugs"])
        let list = SessionScope.sessions([manual, loop, other])
        XCTAssertEqual(list.map(\.session.name), ["1933 REVIEW", "Release notes"])
        XCTAssertFalse(list.contains { SessionScope.isLoop($0.session) }, "a loop-origin session appeared in the session list")
        // The counts the rail shows (All · Active · Exited) come from that list.
        XCTAssertEqual(list.count, 2)
        XCTAssertEqual(list.filter { $0.status.isLive }.count, 1)
        XCTAssertEqual(list.filter { $0.status == .exited }.count, 1)
        XCTAssertEqual(SessionScope.manual([manual.session, loop.session]).map(\.name), ["1933 REVIEW"])
        XCTAssertEqual(SessionScope.loopId(loop.session.tags), "oneroof-nightly-bugs")
        XCTAssertNil(SessionScope.loopId(["looping", "wip"]), "only the loop: tag marks a loop round")
    }

    func test_LAB1933_loopAsksStayOutOfNeedsYouAndItsBadge() {
        let manual = row("Fix login", status: .needsYou)
        let loop = row("nightly · round 1", tags: ["loop:nightly"], status: .needsYou)
        let rows = Dictionary(uniqueKeysWithValues: [manual, loop].map { ($0.id, $0) })
        func ask(_ i: BoardItem) -> Decision {
            Decision(sessionId: i.id, agent: .claude, kind: .runCommand, command: "swift test", why: "run the tests", touches: "repo",
                     risk: .low, ifNo: "it stops", pattern: "swift test", repo: "/tmp/repo")
        }
        let open = SessionScope.openDecisions([ask(loop), ask(manual)]) { rows[$0] }
        XCTAssertEqual(open.map(\.sessionId), [manual.id], "a loop round's ask appeared in Needs you")
        XCTAssertEqual(SessionScope.needsYouCount(openAsks: open.count, plansWaiting: 0, items: [manual, loop]), 1)
        XCTAssertEqual(SessionScope.needsYouCount(openAsks: 0, plansWaiting: 0, items: [loop]), 0, "a waiting loop round adds nothing to the badge")
    }

    /// The views read sessions through the manual-only lists (`sessionItems`, `items(in:)`, `needsYouBadge`). Every
    /// view file that reads the full `model.items` (loop rounds included) is listed here with its reason; a new one
    /// fails this test, so a loop round cannot slip back into a session list unnoticed.
    func test_LAB1933_viewsReadOnlyManualSessions() throws {
        let ui = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("Sources/OneRoof/UI").path
        let allowed: Set<String> = [
            "TerminalAreaController.swift",   // keeps every live terminal surface, a loop round's too (opened from Loops)
            "ResourcesView.swift",            // Machine: what every process uses, loop rounds included
            "LoopRunsView.swift",             // the Loops area: where loop rounds are listed
        ]
        let fm = FileManager.default
        guard let e = fm.enumerator(atPath: ui) else { return XCTFail("no UI sources at \(ui)") }
        var hits: [String] = []
        let rx = try NSRegularExpression(pattern: #"\b(model|m)\.items\b(?!\(in)"#)
        for case let f as String in e where f.hasSuffix(".swift") && !allowed.contains((f as NSString).lastPathComponent) {
            let text = try String(contentsOfFile: ui + "/" + f, encoding: .utf8)
            for (n, line) in text.components(separatedBy: "\n").enumerated()
            where rx.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) != nil {
                hits.append("\(f):\(n + 1): \(line.trimmingCharacters(in: .whitespaces))")
            }
        }
        XCTAssertEqual(hits, [], "views reading every session (loop rounds included); use sessionItems / items(in:):\n" + hits.joined(separator: "\n"))
    }
}
