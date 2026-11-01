import XCTest
@testable import OneRoofCore

/// LAB-2098: Home's morning front page — findings (not counts) from real inputs, Decide now from the Inbox, the
/// overnight river, and the ledger's runs-in-a-window query.
final class HomeFrontPageTests: XCTestCase {
    var cal: Calendar = { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; return c }()
    func at(_ h: Int, _ m: Int = 0) -> Date { cal.date(from: DateComponents(year: 2026, month: 11, day: 1, hour: h, minute: m))! }

    func test_LAB2098_mastheadAndWindow() {
        var i = HomeFrontPage.Inputs(now: at(8, 55))
        i.version = "2.0.1"
        let p = HomeFrontPage.build(i, calendar: cal)
        XCTAssertEqual(p.masthead, "THE MORNING · SUNDAY 1 NOVEMBER")
        XCTAssertTrue(p.windowLine.hasPrefix("since midnight 00:00 → 08:55"), p.windowLine)
        XCTAssertTrue(p.ticker.contains { $0.label == "One Roof" && $0.value == "2.0.1 running" })
        // Before 06:00 the window is the last 12 hours.
        XCTAssertEqual(HomeFrontPage.window(now: at(3), calendar: cal).start, at(3).addingTimeInterval(-12 * 3600))
    }

    func test_LAB2098_quietNightSaysSoPlainly() {
        let p = HomeFrontPage.build(HomeFrontPage.Inputs(now: at(8)), calendar: cal)
        XCTAssertTrue(p.lead.headline.contains("quiet night"))
        XCTAssertTrue(p.side.isEmpty)
        XCTAssertTrue(p.decide.isEmpty)
        XCTAssertTrue(p.river.isEmpty)
    }

    func test_LAB2098_failedLoopLeadsAsAFinding() {
        var i = HomeFrontPage.Inputs(now: at(8, 55))
        i.runs = [.init(loop: "nightly-bugs", title: "Nightly bugs", started: at(3), result: "failed", summary: "Saw 18 bugs in Backlog; gave up after two rounds."),
                  .init(loop: "docs-drift", title: "Docs drift", started: at(6), result: "done", summary: "ok"),
                  .init(loop: "sweep", title: "Fleet sweep", started: at(8), result: "noop", summary: "nothing configured")]
        let p = HomeFrontPage.build(i, calendar: cal)
        XCTAssertEqual(p.lead.headline, "Nightly bugs failed overnight")
        XCTAssertTrue(p.lead.body.hasPrefix("Saw 18 bugs"))
        XCTAssertEqual(p.lead.tone, .bad)
        XCTAssertEqual(p.lead.actions.first?.target, .runLoopAgain("nightly-bugs"))
        XCTAssertTrue(p.side.contains { $0.headline == "Fleet sweep ran and did nothing" })
        let loops = p.river.lanes.first { $0.name == "Loops" }!
        XCTAssertEqual(loops.marks.count, 3)
        XCTAssertEqual(loops.marks.first?.tone, .bad)
    }

    func test_LAB2098_decideNowFollowsTheInbox() {
        var i = HomeFrontPage.Inputs(now: at(9))
        i.asks = (0..<6).map { .init(id: "a\($0)", kind: $0 == 0 ? .permission : .loopStaged, title: "S\($0)", detail: "run the tests", at: at(7), loopId: "l") }
        let p = HomeFrontPage.build(i, calendar: cal)
        XCTAssertEqual(p.decide.count, 4)
        XCTAssertEqual(p.moreWaiting, 2)
        XCTAssertEqual(p.decide[0].tag, "GO?")
        XCTAssertEqual(p.decide[0].action.target, .inbox)
        XCTAssertTrue(p.lead.headline.contains("for your approval"))   // staged loop work becomes a story
    }

    func test_LAB2098_storiesFromReleasesProjectsSeatsAndMac() {
        var i = HomeFrontPage.Inputs(now: at(9))
        i.moments = [.init(at: at(5), kind: .releaseFinished, text: "release.sh 2.0.0 · 7/7 green", session: "release"),
                     .init(at: at(4), kind: .finding, text: "The memory file was cutting 13 lines", session: "docs")]
        i.issues = [.init(identifier: "ABC-1", title: "Fix the rail", state: "In Review")]
        i.seats = [SeatUsage(seat: "Claude1", fiveHour: 20, fiveHourResets: nil, sevenDay: 91, sevenDayResets: at(9).addingTimeInterval(2 * 86_400), updated: at(9))]
        i.mac = MacMemory(total: 16 << 30, used: 15 << 30, swapUsed: 6 << 30, pressure: .warn)
        let p = HomeFrontPage.build(i, calendar: cal)
        let all = [p.lead] + p.side
        XCTAssertEqual(p.lead.kicker, "SHIPPED OVERNIGHT")
        XCTAssertTrue(all.contains { $0.kicker == "PROJECTS" && $0.headline == "1 in review wait on you" })
        XCTAssertEqual(p.side.count, 3)   // at most three side stories; the rest stay out of the way
        XCTAssertEqual(p.river.lanes.first { $0.name == "Releases" }?.marks.first?.label, "release 2.0.0")
        XCTAssertEqual(p.ticker.first { $0.label == "Seats" }?.tone, .bad)
        XCTAssertEqual(p.ticker.first { $0.label == "Mac" }?.tone, .warn)
    }

    func test_LAB2098_riverMergesCrowdedMarks() {
        let m = HomeFrontPage.merge([.init(id: "1", x: 0.10, label: "a", tone: .good, count: 1),
                                     .init(id: "2", x: 0.12, label: "b", tone: .bad, count: 1),
                                     .init(id: "3", x: 0.13, label: "c", tone: .good, count: 1),
                                     .init(id: "4", x: 0.60, label: "d", tone: .good, count: 1)])
        XCTAssertEqual(m.count, 2)
        XCTAssertEqual(m[0].label, "a +2")
        XCTAssertEqual(m[0].tone, .bad)
        XCTAssertEqual(m[0].count, 3)
        let r = HomeFrontPage.makeRiver(start: at(0), end: at(9), runs: [], moments: [], asks: [], calendar: cal)
        XCTAssertEqual(r.ticks.map(\.label), ["00:00", "02:00", "04:00", "06:00", "08:00"])
    }

    func test_LAB2098_ledgerRunsInAWindow() throws {
        let path = NSTemporaryDirectory() + "home-ledger-\(UUID().uuidString.prefix(8))/ledger.sqlite"
        let led = try LoopLedger(path: path)
        let base = Date(timeIntervalSince1970: 1_800_000_000)
        try led.recordRun(loop: "a", runId: "1", started: base - 7200, ended: base - 7100, result: "done", summary: "early")
        try led.recordRun(loop: "a", runId: "2", started: base + 60, ended: base + 120, result: "failed", summary: "in")
        try led.recordRun(loop: "b", runId: "3", started: base + 600, ended: base + 700, result: "done", summary: "in too")
        let rs = led.runs(from: base, to: base + 3600)
        XCTAssertEqual(rs.map(\.summary), ["in", "in too"])   // oldest first, outside the window left out
    }
}

extension HomeFrontPageTests {
    func test_LAB2098_riverLeavesCrowdedAndRepeatedLabelsOff() {
        let marks: [HomeFrontPage.Mark] = [.init(id: "1", x: 0.10, label: "s", tone: .info, count: 1),
                                           .init(id: "2", x: 0.20, label: "s", tone: .info, count: 1),   // same session again
                                           .init(id: "3", x: 0.23, label: "t", tone: .info, count: 1),   // too close
                                           .init(id: "4", x: 0.24, label: "u", tone: .bad, count: 1),    // bad: always labelled
                                           .init(id: "5", x: 0.50, label: "s", tone: .info, count: 1)]
        XCTAssertEqual(HomeFrontPage.declutter(marks).map(\.shown), [true, false, true, true, true])
        XCTAssertEqual(HomeFrontPage.sentence("needs a new approach"), "needs a new approach.")
        XCTAssertEqual(HomeFrontPage.sentence("done!"), "done!")
    }
}
