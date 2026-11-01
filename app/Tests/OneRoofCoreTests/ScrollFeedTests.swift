import XCTest
@testable import OneRoofCore

/// LAB-1831 · Scroll (one feed of every session's important moments, newest at the bottom) and Needs you's history
/// of what you decided.
final class ScrollFeedTests: XCTestCase {
    private func row(_ name: String, live: Bool = true, tags: [String] = []) -> BoardItem {
        let s = Session(name: name, agent: .claude, repoPath: "/tmp/repo", tags: tags)
        var i = BoardItem(id: s.id, session: s, status: live ? .running : .exited, adopted: false)
        if live { i.liveAgent = "rt-" + s.id }
        return i
    }
    private func ask(_ i: BoardItem, at: Date, answered: Answer? = nil, reply: String? = nil, question: String? = nil) -> Decision {
        Decision(sessionId: i.id, agent: .claude, kind: question == nil ? .runCommand : .other, command: question == nil ? "swift test" : nil,
                 why: question ?? "run the tests", touches: "repo", risk: .low, ifNo: "it stops",
                 pattern: question.map { Decision.questionPrefix + $0 } ?? "swift test", repo: "/tmp/repo",
                 askedAt: at, answeredAt: answered == nil ? nil : at.addingTimeInterval(30), answer: answered, replyText: reply)
    }

    func test_LAB1831_feedIsOneTimelineAcrossSessionsNewestLast() {
        let a = row("Checkout"), b = row("Docs"), loop = row("nightly · round 1", tags: ["loop:nightly"])
        let rows = Dictionary(uniqueKeysWithValues: [a, b, loop].map { ($0.id, $0) })
        let t0 = Date(timeIntervalSince1970: 1_000_000)
        let feed = [FeedEvent(at: t0.addingTimeInterval(50), sessionId: b.id, kind: .finding, text: "the index is stale"),
                    FeedEvent(at: t0.addingTimeInterval(10), sessionId: a.id, kind: .error, text: "build failed"),
                    FeedEvent(at: t0.addingTimeInterval(5), sessionId: loop.id, kind: .done, text: "round done")]
        let chapters = [a.id: [Chapter(index: 0, title: "Fix the cart", summary: "totals rounded", toolCalls: 3, started: t0, ended: t0.addingTimeInterval(20), scrollbackRange: 0..<10),
                               Chapter(index: 1, title: "Still going", summary: "", toolCalls: 1, started: t0.addingTimeInterval(20), ended: nil, scrollbackRange: 10..<12)]]
        let decisions = [ask(b, at: t0.addingTimeInterval(70)), ask(a, at: t0.addingTimeInterval(30), answered: .allowOnce)]
        let e = ScrollFeed.entries(feed: feed, chapters: chapters, decisions: decisions) { rows[$0] }
        XCTAssertEqual(e.map(\.text), ["build failed", "Fix the cart · totals rounded", "Run swift test", "the index is stale", "Run swift test"])
        XCTAssertEqual(e.map(\.at), e.map(\.at).sorted(), "oldest first, newest at the bottom")
        XCTAssertFalse(e.contains { $0.sessionId == loop.id }, "loop rounds stay in Loops (LAB-1933)")
        XCTAssertEqual(e[2].answer, "Allowed once")
        XCTAssertFalse(e[2].needsInput)
        XCTAssertTrue(e[4].needsInput, "an open ask is answered in place")
        XCTAssertEqual(Set(e.map(\.sessionId)), [a.id, b.id], "each entry says which session it is from")
    }

    func test_LAB1831_stepLinesComeFromChaptersWhenThereAreAny() {
        let a = row("A"), b = row("B")
        let rows = [a.id: a, b.id: b]
        let t0 = Date()
        let feed = [FeedEvent(at: t0, sessionId: a.id, kind: .stepDone, text: "step done"),
                    FeedEvent(at: t0, sessionId: b.id, kind: .stepDone, text: "B step done")]
        let ch = [a.id: [Chapter(index: 0, title: "Tests", summary: "12 pass", toolCalls: 1, started: t0, ended: t0, scrollbackRange: 0..<1)]]
        let e = ScrollFeed.entries(feed: feed, chapters: ch, decisions: []) { rows[$0] }
        XCTAssertEqual(Set(e.map(\.text)), ["Tests · 12 pass", "B step done"])
        XCTAssertEqual(ScrollFeed.entries(feed: Array(repeating: feed[1], count: 3), chapters: [:], decisions: [], item: { rows[$0] }, limit: 2).count, 2)
    }

    func test_LAB1831_needsYouKeepsDecidedWhileTheSessionIsAlive() {
        let live = row("Live"), gone = row("Gone", live: false), loop = row("round", tags: ["loop:x"])
        let rows = Dictionary(uniqueKeysWithValues: [live, gone, loop].map { ($0.id, $0) })
        let t0 = Date(timeIntervalSince1970: 2_000_000)
        let ds = [ask(live, at: t0, answered: .deny), ask(live, at: t0.addingTimeInterval(100), answered: .reply, reply: "use main", question: "Which branch?"),
                  ask(live, at: t0.addingTimeInterval(200)), ask(gone, at: t0, answered: .allowOnce), ask(loop, at: t0, answered: .allowOnce)]
        let d = ScrollFeed.decided(ds) { rows[$0] }
        XCTAssertEqual(d.map { ScrollFeed.answerText($0) }, ["Replied: use main", "Denied"], "newest answer first; open, ended and loop asks left out")
        XCTAssertEqual(ScrollFeed.askText(d[0]), "Which branch?")
        XCTAssertEqual(ScrollFeed.answerText(ask(live, at: t0, answered: .reply, reply: "answered in the terminal")), "Answered in its terminal")
    }

    /// LAB-2044: Scroll left the Single · Grid · Wall switch (it is the History place); a saved "scroll" opens as Single.
    func test_LAB2044_scrollLeftTheLayoutSwitchAndASavedScrollOpensSingle() {
        XCTAssertEqual(SessionLayout.allCases, [.single, .grid, .wall], "the switch reads Single · Grid · Wall")
        XCTAssertEqual(SessionLayout(stored: "scroll"), .single, "a window saved with layout scroll opens as Single")
        XCTAssertEqual(SessionLayout(stored: "grid"), .grid)
        XCTAssertNil(SessionLayout(stored: "nonsense"))
        XCTAssertNil(SessionLayout(rawValue: "scroll"))
        XCTAssertEqual(V2Layout.page(for: .wall), "All windows")
        XCTAssertNil(V2Layout.page(for: .grid))
        XCTAssertNil(V2Layout.page(for: .single))
        XCTAssertNil(V2Layout.layout(forPage: "Scroll"), "no Scroll page any more")
        XCTAssertNil(V2Layout.layout(forPage: "Settings"))
        XCTAssertFalse(V2Layout.showsLayoutControl(inSessions: true, page: "Scroll"))
    }

    /// LAB-2044: the feed in both orders (History shows newest first; the oldest-first order stays for tests).
    func test_LAB2044_feedNewestFirstIsTheOldestFirstReversed() {
        let a = row("A"), b = row("B")
        let rows = [a.id: a, b.id: b]
        let t0 = Date(timeIntervalSince1970: 3_000_000)
        let feed = (0..<5).map { FeedEvent(at: t0.addingTimeInterval(Double($0) * 10), sessionId: $0 % 2 == 0 ? a.id : b.id, kind: .finding, text: "f\($0)") }
        let old = ScrollFeed.entries(feed: feed, chapters: [:], decisions: []) { rows[$0] }
        let new = ScrollFeed.entries(feed: feed, chapters: [:], decisions: [], item: { rows[$0] }, order: .newestFirst)
        XCTAssertEqual(new.map(\.text), ["f4", "f3", "f2", "f1", "f0"], "newest on top")
        XCTAssertEqual(new, old.reversed())
        XCTAssertEqual(ScrollFeed.entries(feed: feed, chapters: [:], decisions: [], item: { rows[$0] }, limit: 2, order: .newestFirst).map(\.text), ["f4", "f3"],
                       "the limit keeps the newest")
    }
}
