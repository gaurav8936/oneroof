import XCTest
@testable import OneRoofCore

/// One Roof 2.0.1 · Inbox and History walkthrough fixes: screen furniture (LAB-2108), your words from the terminal
/// (LAB-2106), session colours (LAB-2109 · LAB-2107), critical asks (LAB-2112), the paged Decided record (LAB-2110 · LAB-2082).
final class Inbox201Tests: XCTestCase {
    var path = ""
    let now = Date()
    override func setUp() { path = NSTemporaryDirectory() + "oneroof-201-\(UUID().uuidString).sqlite" }
    override func tearDown() { for ext in ["", "-wal", "-shm"] { try? FileManager.default.removeItem(atPath: path + ext) } }

    private func fin(sessionId: String, agent: AgentKind, said: String, repo: String, now: Date) -> Decision {
        Decision(sessionId: sessionId, agent: agent, kind: .other, why: said, touches: "t", risk: .low, ifNo: "n",
                 pattern: Decision.finishedPrefix + said, repo: repo, askedAt: now)
    }

    // MARK: LAB-2108

    func test_LAB2108_ownersFurnitureLinesAreChrome() {
        for l in ["main ○ general-purpose  Reviewing v3 timeline screenshots    4m 46s · ↓ 292.4k tokens",
                  "main ○ general-purpose  Running typecheck, svelte-check and tests  18m 18s · ↓ 250.7k tokens",
                  "Working (10s • esc to interrupt)",
                  "Exited… New activity · ↓ Back to bottom · esc",
                  "⎿  Done (12 tool uses · 40.1k tokens · 2m 3s)"] {
            XCTAssertTrue(TerminalText.isChrome(l), l)
        }
        for l in ["The papers timeline is ready to review.", "I pushed both branches: GREEN, 22 of 22.", "Reviewing blog draft and scoping paper"] {
            XCTAssertFalse(TerminalText.isChrome(l), l)
        }
    }

    func test_LAB2108_historyDropsFurnitureAndRepeats() {
        let t0 = now.addingTimeInterval(-3600)
        func e(_ id: String, _ m: Double, _ k: ScrollEntry.Kind, _ text: String, s: String = "a") -> ScrollEntry {
            ScrollEntry(id: id, at: t0.addingTimeInterval(m * 60), sessionId: s, kind: k, text: text, open: false)
        }
        let out = HistoryFeed.tidy([
            e("1", 0, .done, "main ○ general-purpose  Reviewing  4m 46s · ↓ 292.4k tokens"),
            e("2", 1, .done, "REVIEW & BUG FIXES finished"),
            e("3", 2, .done, "REVIEW & BUG FIXES finished"),
            e("4", 3, .done, "REVIEW & BUG FIXES finished", s: "b"),
            e("5", 30, .done, "REVIEW & BUG FIXES finished"),
            e("6", 31, .step, "Working (10s • esc to interrupt)"),
        ])
        XCTAssertEqual(out.map(\.id), ["2", "4", "5"], "furniture gone; one Done per session per 15 minutes")
    }

    // MARK: LAB-2106

    func test_LAB2106_typedReplyIsReadAndRecorded() {
        let screen = """
        ⏺ The release is out. Anything else?

        > yes — now write the handoff and
          close the session

        ⏺ Writing the handoff…
        ╭──────────────────────────────╮
        │ >                            │
        ╰──────────────────────────────╯
          ? for shortcuts
        """
        XCTAssertEqual(TerminalReply.lastTyped(in: screen), "yes — now write the handoff and close the session")
        XCTAssertNil(TerminalReply.lastTyped(in: "⏺ Done.\n│ >   │\n"), "the empty input box is not a reply")
        let rec = TerminalReply.record("ship it")
        XCTAssertEqual(TerminalReply.typed(rec), "ship it")
        XCTAssertTrue(TerminalReply.isTerminal(rec) && TerminalReply.isTerminal(TerminalReply.marker))
        XCTAssertEqual(TerminalReply.record(nil), TerminalReply.marker)
        var d = fin(sessionId: "s", agent: .claude, said: "Anything else?", repo: "r", now: now)
        d.answer = .reply; d.replyText = rec
        XCTAssertEqual(ScrollFeed.answerText(d), "Replied in its terminal: ship it")
        XCTAssertEqual(ActionLogAnswer.of(d), .answeredInTerminal)
        d.replyText = TerminalReply.marker
        XCTAssertEqual(ScrollFeed.answerText(d), "Answered in its terminal")
    }

    // MARK: LAB-2109 · LAB-2107

    func test_LAB2109_sessionColourIsStableAndReadsInEveryTheme() {
        XCTAssertEqual(SessionHue.pastel(for: "abc-123").name, SessionHue.pastel(for: "abc-123").name)
        let names = Set((0..<40).map { SessionHue.pastel(for: "session-\($0)").name })
        XCTAssertGreaterThan(names.count, 4, "sessions spread over the palette")
        for theme in [ThemeName.daylight, .graphite, .midnight] {
            let t = theme.tokens
            for i in 0..<30 {
                let h = SessionHue(sessionId: "s\(i)", on: t)
                XCTAssertGreaterThanOrEqual(RGB.contrast(h.ink, h.fill), 4.5, "\(theme) name on its card")
                XCTAssertGreaterThanOrEqual(RGB.contrast(h.ink, t.window), 3, "\(theme) edge on the page")
            }
        }
    }

    // MARK: LAB-2112

    func test_LAB2112_criticalAndInformationalClasses() {
        let permission = Decision(sessionId: "a", agent: .claude, kind: .runCommand, command: "git push", why: "w", touches: "t", risk: .high,
                                  ifNo: "n", pattern: "git push", repo: "r", askedAt: now)
        XCTAssertEqual(InboxUrgency.of(permission), .critical, "a permission prompt blocks the agent")
        let thanks = fin(sessionId: "b", agent: .claude, said: "You're welcome! Say last call when you're done.", repo: "r", now: now)
        XCTAssertEqual(InboxUrgency.of(thanks), .informational)
        let halted = fin(sessionId: "c", agent: .claude, said: "Release gate FAIL: 2 checks failed. I stopped here.", repo: "r", now: now)
        XCTAssertEqual(InboxUrgency.of(halted), .critical, "a halted gate needs a call")
        let blocks = [InboxBlock(id: "session-b", kind: .finished, at: now, sessionId: "b", decision: thanks),
                      InboxBlock(id: "session-a", kind: .permission, at: now.addingTimeInterval(-600), sessionId: "a", decision: permission)]
        XCTAssertEqual(InboxUrgency.sorted(blocks).map(\.id), ["session-a", "session-b"], "critical first even when older")
        let layout = Inbox.layout(open: [thanks, permission], plans: [], loops: [])
        XCTAssertEqual(layout.asks.first?.sessionId, "a")
    }

    // MARK: LAB-2110 · LAB-2082

    func test_LAB2110_decidedPagesInSQLNewestFirstAndSearches() throws {
        let store = try SessionStore(path: path)
        for i in 0..<120 {
            let at = now.addingTimeInterval(-Double(i) * 60)
            let d = Decision(sessionId: i % 2 == 0 ? "a" : "b", agent: .claude, kind: .runCommand, command: i == 7 ? "swift test --filter Needle" : "ls",
                             why: "w", touches: "t", risk: .low, ifNo: "n", pattern: "ls", repo: "r", askedAt: at.addingTimeInterval(-5),
                             answeredAt: at, answer: .allowOnce)
            store.save(d, sessionName: i % 2 == 0 ? "Alpha" : "Beta")
        }
        var aside = fin(sessionId: "a", agent: .claude, said: "bye", repo: "r", now: now)
        aside.answer = .reply; aside.answeredAt = now; aside.replyText = "set aside"
        store.save(aside, sessionName: "Alpha")
        store.answer(decision: aside.id, .reply, reply: "set aside")
        XCTAssertEqual(store.decidedCount(), 120, "set-aside turns are not decisions")
        let p1 = store.decided(), p3 = store.decided(offset: 100)
        XCTAssertEqual(p1.count, Decided.pageSize)
        XCTAssertEqual(p3.count, 20)
        XCTAssertTrue(zip(p1, p1.dropFirst()).allSatisfy { ($0.decision.answeredAt ?? .distantPast) >= ($1.decision.answeredAt ?? .distantPast) })
        XCTAssertEqual(store.decided(search: "needle").map(\.decision.command), ["swift test --filter Needle"])
        XCTAssertEqual(store.decidedCount(search: "Beta"), 60, "the session name matches")
        XCTAssertEqual(store.decidedCount(sessions: ["a"]), 60)
        XCTAssertEqual(store.decidedCount(search: "50%"), 0, "LIKE wildcards in a search are literal")
        XCTAssertEqual(store.decidedCount(answers: [.deny]), 0, "the Answer filter runs in SQL")
        XCTAssertEqual(store.decidedCount(answers: [.allowOnce, .always]), 120)
        XCTAssertEqual(store.decidedCount(since: now.addingTimeInterval(-10 * 60 - 1)), 11, "the date filter: the last ten minutes")
        XCTAssertEqual(store.decided(sessions: ["b"], since: now.addingTimeInterval(-3600)).count, 30)
        XCTAssertEqual(Decided.tabTitle(today: 3), "Decided · 3 today")
        XCTAssertEqual(Decided.tabTitle(today: 0), "Decided")
    }

    func test_LAB2082_decidedPageIsFastOnA100kStore() throws {
        let store = try SessionStore(path: path)
        try store.exec("BEGIN")
        do {
            for i in 0..<100_000 {
                let at = now.addingTimeInterval(-Double(i) * 30)
                store.save(Decision(sessionId: "s\(i % 50)", agent: .claude, kind: .runCommand, command: "ls", why: "w", touches: "t", risk: .low,
                                    ifNo: "n", pattern: "ls", repo: "r", askedAt: at, answeredAt: at, answer: .allowOnce))
            }
        }
        try store.exec("COMMIT")
        let t = Date()
        let page = store.decided(offset: 50)
        let ms = Date().timeIntervalSince(t) * 1000
        XCTAssertEqual(page.count, 50)
        XCTAssertLessThan(ms, 100, "one page of a 100k store reads under 100 ms (got \(Int(ms)) ms)")
    }
}
