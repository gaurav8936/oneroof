import XCTest
@testable import OneRoofCore

/// LAB-1509 session catalog · LAB-1511 backfill · LAB-1513 resume rules.
final class SessionCatalogTests: XCTestCase {
    private func s(_ name: String, agent: AgentKind = .claude, repo: String = "/p/a", last: String? = nil, launched: Date? = nil, conv: String? = nil, opening: String = "") -> Session {
        var x = Session(name: name, repoPath: repo, lifecycle: .idle)
        x.agent = agent; x.lastRepo = last; x.launchedAt = launched; x.conversationId = conv; x.openingMessage = opening
        return x
    }

    func test_LAB1509_groupedByRepoNewestFirst() {
        let now = Date()
        let e = [
            SessionCatalog.entry(s("old a", repo: "/p/a"), state: .history, window: nil, lastActive: now.addingTimeInterval(-900)),
            SessionCatalog.entry(s("new b", repo: "/p/b"), state: .working, window: "Main", lastActive: now),
            SessionCatalog.entry(s("new a", repo: "/p/x", last: "/p/a"), state: .finishedShell, window: nil, lastActive: now.addingTimeInterval(-60)),
        ]
        let g = SessionCatalog.groups(e)
        XCTAssertEqual(g.map(\.repo), ["/p/b", "/p/a"])                  // lastRepo wins over the launch folder
        XCTAssertEqual(g[1].entries.map(\.name), ["new a", "old a"])
    }

    func test_LAB1509_queryAndStateFilters() {
        let e = [
            SessionCatalog.entry(s("Pitch Deck"), state: .finishedShell, window: "Blogs", lastActive: nil),
            SessionCatalog.entry(s("Bug Fixes"), state: .history, window: nil, lastActive: nil),
        ]
        XCTAssertEqual(SessionCatalog.groups(e, query: "pitch").flatMap(\.entries).map(\.name), ["Pitch Deck"])
        XCTAssertEqual(SessionCatalog.groups(e, query: "blogs").flatMap(\.entries).map(\.name), ["Pitch Deck"])   // by window
        XCTAssertEqual(SessionCatalog.groups(e, states: [.history]).flatMap(\.entries).map(\.name), ["Bug Fixes"])
    }

    func test_LAB1513_resumeRules() {
        XCTAssertEqual(SessionCatalog.resume(for: s("live"), state: .working), .open)
        XCTAssertEqual(SessionCatalog.resume(for: s("shell open"), state: .finishedShell), .open)
        XCTAssertEqual(SessionCatalog.resume(for: s("saved", conv: "abc"), state: .history), .claude(id: "abc"))
        XCTAssertEqual(SessionCatalog.resume(for: s("saved"), state: .history), .noConversation)
        XCTAssertEqual(SessionCatalog.resume(for: s("t", agent: .shell), state: .history), .terminal)
        if case .unsupported = SessionCatalog.resume(for: s("c", agent: .codex), state: .history) {} else { XCTFail("codex") }
        XCTAssertNil(SessionCatalog.Resume.noConversation.buttonTitle)
        XCTAssertNotNil(SessionCatalog.Resume.noConversation.why)
    }

    func test_LAB1509_state() {
        XCTAssertEqual(SessionCatalog.state(liveAgent: true, endedShell: false, status: .running), .working)
        XCTAssertEqual(SessionCatalog.state(liveAgent: true, endedShell: false, status: .needsYou), .waiting)
        XCTAssertEqual(SessionCatalog.state(liveAgent: false, endedShell: true, status: .exited), .finishedShell)
        XCTAssertEqual(SessionCatalog.state(liveAgent: false, endedShell: false, status: .exited), .history)
        XCTAssertEqual(SessionCatalog.state(liveAgent: false, endedShell: false, status: .planned, launched: false), .planned)
        XCTAssertEqual(SessionCatalog.resume(for: s("plan"), state: .planned), .launch)
    }

    func test_LAB1511_backfillMatchesOnlyWhenConfident() {
        let t0 = Date(timeIntervalSince1970: 1_800_000_000)
        typealias C = ConversationBackfill.Candidate
        let near1 = C(id: "a", path: "/x/a.jsonl", firstAt: t0.addingTimeInterval(20), firstAsked: "Fix the close dialog please")
        let near2 = C(id: "b", path: "/x/b.jsonl", firstAt: t0.addingTimeInterval(90), firstAsked: "something else")
        let far = C(id: "c", path: "/x/c.jsonl", firstAt: t0.addingTimeInterval(3600), firstAsked: "Fix the close dialog please")
        // with an opening message: the one that said it, inside the window
        XCTAssertEqual(ConversationBackfill.match(s("o", launched: t0, opening: "Fix the close dialog"), [near1, near2, far]), .found(near1))
        // without one: only a single conversation near the launch counts
        XCTAssertEqual(ConversationBackfill.match(s("n", launched: t0), [near1, far]), .found(near1))
        XCTAssertEqual(ConversationBackfill.match(s("n", launched: t0), [near1, near2]), .ambiguous(2))
        XCTAssertEqual(ConversationBackfill.match(s("n", launched: t0), [far]), .none)
        XCTAssertEqual(ConversationBackfill.match(s("never launched"), [near1]), .none)
    }
}

/// LAB-1511: the first thing the user typed, past snapshot and system lines.
final class FirstUserMessageTests: XCTestCase {
    func test_LAB1511_firstUserMessageSkipsSnapshots() {
        let jsonl = """
        {"type":"file-history-snapshot","timestamp":"2026-10-28T10:00:00.000Z"}
        {"type":"system","timestamp":"2026-10-28T10:00:01.000Z","message":{"role":"system","content":"x"}}
        {"type":"user","timestamp":"2026-10-28T10:00:02.000Z","message":{"role":"user","content":[{"type":"text","text":"Fix the close dialog"}]}}
        """
        let f = ConversationBackfill.firstUserMessage(jsonl)
        XCTAssertEqual(f?.asked, "Fix the close dialog")
        XCTAssertEqual(f?.at, ClaudeTranscript.date("2026-10-28T10:00:00.000Z"))
    }
}
