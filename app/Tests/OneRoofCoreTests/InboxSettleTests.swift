import XCTest
@testable import OneRoofCore

/// LAB-ONEROOF-v2.0.10 · Inbox words (LAB-2351) and settling rows (LAB-2352), mockup design/20261121_inbox-active-and-settling.
final class InboxSettleTests: XCTestCase {
    let now = Date()

    private func done(_ id: String, index: Int, verb: String = "replied", folded: Bool = false, ago: TimeInterval = 0) -> InboxDone {
        InboxDone(id: id, title: id, postmark: "p", tier: 0, outcome: "✓ x", verb: verb, isLoop: false,
                  at: now.addingTimeInterval(-ago), index: index, folded: folded)
    }

    // MARK: LAB-2351 · Part 1 A

    func test_LAB2351_tabSaysSessions() {
        XCTAssertEqual(InboxFilter.sessions.title, "Sessions", "'Active' stays on the Sessions page, where it means alive")
    }

    func test_LAB2351_headerSaysWhatOpenSessionsDo() {
        XCTAssertEqual(InboxSettle.sessionsLine(working: 0, ready: 0, idle: 3, other: false), "3 sessions open, all idle")
        XCTAssertEqual(InboxSettle.sessionsLine(working: 1, ready: 0, idle: 0, other: false), "1 session open, working")
        XCTAssertEqual(InboxSettle.sessionsLine(working: 1, ready: 0, idle: 2, other: false), "3 open · 1 working · 2 idle")
        XCTAssertEqual(InboxSettle.sessionsLine(working: 0, ready: 0, idle: 2, other: true), "2 other sessions open, all idle")
        XCTAssertNil(InboxSettle.sessionsLine(working: 0, ready: 0, idle: 0, other: false))
        XCTAssertEqual(InboxSettle.bucket(.running), "working")
        XCTAssertEqual(InboxSettle.bucket(.idle), "idle")
        XCTAssertNil(InboxSettle.bucket(.exited))
    }

    // MARK: LAB-2352 · Part 2 A

    func test_LAB2352_settledRowStaysWhereItWas() {
        let o = InboxSettle.order(live: ["a", "c"], settled: [done("b", index: 1)])
        XCTAssertEqual(o.map(\.id), ["a", "b", "c"], "nothing below the handled row moves")
        XCTAssertEqual(o.map(\.settled), [false, true, false])
        XCTAssertEqual(InboxSettle.order(live: ["a"], settled: [done("z", index: 9)]).map(\.id), ["a", "z"], "an index past the end goes last")
        XCTAssertEqual(InboxSettle.order(live: ["a"], settled: [done("b", index: 0, folded: true)]).map(\.id), ["a"], "folded rows are in Done today")
        XCTAssertEqual(InboxSettle.order(live: ["b"], settled: [done("b", index: 0)]).map(\.id), ["b"], "a row that came back is live")
    }

    func test_LAB2352_foldsWhenYouLeaveOrAfterTenMinutes() {
        let rows = [done("new", index: 0), done("old", index: 1, ago: InboxSettle.foldAfter + 1)]
        XCTAssertEqual(InboxSettle.fold(rows, now: now, leaving: false).map(\.folded), [false, true])
        XCTAssertEqual(InboxSettle.fold(rows, now: now, leaving: true).map(\.folded), [true, true])
    }

    func test_LAB2352_doneTodayKeepsTodayNewestFirst() {
        var rows: [InboxDone] = []
        rows = InboxSettle.add(done("a", index: 0), to: rows, now: now)
        rows = InboxSettle.add(done("b", index: 0), to: rows, now: now)
        rows = InboxSettle.add(done("a", index: 2, verb: "approved"), to: rows, now: now)
        XCTAssertEqual(rows.map(\.id), ["a", "b"], "newest first; a row settling again replaces its old entry")
        let yesterday = done("y", index: 0, ago: 86_400 * 2)
        XCTAssertTrue(InboxSettle.today([yesterday], now: now).isEmpty, "yesterday's rows are only in Decided")
    }

    func test_LAB2352_summary() {
        let rows = [done("a", index: 0), done("b", index: 0, verb: "approved"), done("c", index: 0), done("d", index: 0, verb: "dismissed")]
        XCTAssertEqual(InboxSettle.summary(rows), "replied 2 · approved 1 · dismissed 1")
    }

    func test_LAB2352_outcomeWords() {
        var d = Decision(sessionId: "s", agent: .claude, kind: .other, why: "w", touches: "t", risk: .low, ifNo: "n",
                         pattern: "p", repo: "r", askedAt: now)
        d.answer = .reply; d.replyText = "ship it"
        XCTAssertEqual(InboxSettle.outcome(d).line, "✓ Replied: ship it")
        XCTAssertEqual(InboxSettle.outcome(d).verb, "replied")
        d.replyText = "set aside"
        XCTAssertEqual(InboxSettle.outcome(d).line, "✓ Set aside")
        d.answer = .allowOnce; d.replyText = nil
        XCTAssertEqual(InboxSettle.outcome(d).verb, "allowed")
        XCTAssertEqual(InboxSettle.loopOutcome(status: "approved", reason: "seen").line, "✓ Marked seen")
        XCTAssertEqual(InboxSettle.loopOutcome(status: "rejected").line, "✓ Dismissed")
        XCTAssertEqual(InboxSettle.loopOutcome(status: "rejected", reason: "stop re-filing").line, "✓ Dismissed · stops re-filing")
        XCTAssertEqual(InboxSettle.line(.answeredInTerminal), "Answered in the terminal")
        XCTAssertEqual(InboxSettle.line(.expired), "Expired after 7 days")
    }

    func test_LAB2352_doneRoundTripsThroughJSON() throws {
        let rows = [done("a", index: 3, folded: true)]
        XCTAssertEqual(try JSONDecoder().decode([InboxDone].self, from: JSONEncoder().encode(rows)), rows)
    }
}
