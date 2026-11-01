import XCTest
@testable import OneRoofCore

/// LAB-2101 (a finished project's roadmap lists its done tickets; Show done always there) and LAB-2103 (Projects says
/// when it was last read from Linear, and shows an error with the last good read when Linear cannot be reached).
final class RoadmapTests: XCTestCase {
    private func issue(_ n: Int, _ type: String, milestone: String? = nil) -> LinearIssue {
        LinearIssue(id: "i\(n)", identifier: "LAB-\(n)", title: "Ticket \(n)", description: "",
                    state: type == "completed" ? "Done" : type == "canceled" ? "Canceled" : "Todo",
                    stateType: type, type: nil, milestoneId: milestone, milestone: nil, url: "")
    }

    func test_LAB2101_completedProjectShowsDoneTicketsByDefault() {
        let all = (1...32).map { issue($0, "completed") }
        XCTAssertTrue(Roadmap.showDoneByDefault(status: .completed, tickets: all))
        let phases = Roadmap.phases(milestones: [], tickets: all)
        XCTAssertEqual(phases.count, 1)
        XCTAssertEqual(phases[0].name, Roadmap.loosePhase)
        XCTAssertEqual(phases[0].doneCount, 32)
        let on = Roadmap.showDone(choice: nil, status: .completed, tickets: all)
        XCTAssertEqual(phases[0].shown(showDone: on).count, 32, "2.0.0 listed none of them")
        XCTAssertNil(phases[0].emptyLine(showDone: on))
    }

    func test_LAB2101_canceledAndAllClosedProjectsDefaultOn_openProjectDefaultsOff() {
        XCTAssertTrue(Roadmap.showDoneByDefault(status: .canceled, tickets: []))
        XCTAssertTrue(Roadmap.showDoneByDefault(status: .inProgress, tickets: [issue(1, "completed"), issue(2, "canceled")]))
        XCTAssertFalse(Roadmap.showDoneByDefault(status: .inProgress, tickets: [issue(1, "completed"), issue(2, "started")]))
        XCTAssertFalse(Roadmap.showDoneByDefault(status: .backlog, tickets: []), "no tickets: nothing to show either way")
    }

    func test_LAB2101_ownerChoiceWins() {
        let all = [issue(1, "completed")]
        XCTAssertFalse(Roadmap.showDone(choice: false, status: .completed, tickets: all))
        XCTAssertTrue(Roadmap.showDone(choice: true, status: .inProgress, tickets: [issue(2, "started")]))
    }

    func test_LAB2101_phasesInMilestoneOrderWithLooseLast() {
        let ms = [LinearMilestone(id: "m1", name: "Phase 1", sortOrder: 0), LinearMilestone(id: "m2", name: "Phase 2", sortOrder: 1)]
        let t = [issue(1, "completed", milestone: "m2"), issue(2, "started", milestone: "m1"), issue(3, "backlog"),
                 issue(4, "canceled", milestone: "gone")]
        let p = Roadmap.phases(milestones: ms, tickets: t)
        XCTAssertEqual(p.map(\.name), ["Phase 1", "Phase 2", Roadmap.loosePhase])
        XCTAssertEqual(p[1].shown(showDone: false).count, 0)
        XCTAssertEqual(p[1].emptyLine(showDone: false), "All done · Show done lists them")
        XCTAssertEqual(p[2].tickets.map(\.identifier), ["LAB-3", "LAB-4"], "a ticket in an unknown milestone is not lost")
        XCTAssertEqual(p[2].open.map(\.identifier), ["LAB-3"])
    }

    func test_LAB2103_updatedLine() {
        let now = Date(timeIntervalSince1970: 2_000_000)
        XCTAssertEqual(LinearFreshness.line(fetchedAt: now.addingTimeInterval(-20), error: nil, loading: false, now: now).text, "Updated just now")
        XCTAssertEqual(LinearFreshness.line(fetchedAt: now.addingTimeInterval(-61), error: nil, loading: false, now: now).text, "Updated 1 min ago")
        XCTAssertEqual(LinearFreshness.line(fetchedAt: now.addingTimeInterval(-12 * 60), error: nil, loading: false, now: now).text, "Updated 12 min ago")
        XCTAssertEqual(LinearFreshness.line(fetchedAt: now.addingTimeInterval(-3 * 3600), error: nil, loading: false, now: now).text, "Updated 3 h ago")
        XCTAssertEqual(LinearFreshness.line(fetchedAt: now.addingTimeInterval(-60), error: nil, loading: true, now: now).text, "Refreshing · updated 1 min ago")
        XCTAssertEqual(LinearFreshness.line(fetchedAt: nil, error: nil, loading: true, now: now).text, "Reading Linear…")
    }

    func test_LAB2103_offlineShowsErrorAndLastRead() {
        let now = Date(timeIntervalSince1970: 2_000_000)
        let l = LinearFreshness.line(fetchedAt: now.addingTimeInterval(-7 * 60), error: "The Internet connection appears to be offline.", loading: false, now: now)
        XCTAssertTrue(l.isError)
        XCTAssertEqual(l.text, "Couldn't reach Linear · last read 7 min ago")
        XCTAssertFalse(l.text.hasPrefix("Updated"), "stale data is never shown as current")
        XCTAssertEqual(LinearFreshness.line(fetchedAt: nil, error: "\(LinearClient.Failure.noKey)", loading: false, now: now).text,
                       "Linear is not connected · never read")
    }

    func test_LAB2103_refreshIntervalIsAFewMinutes() {
        XCTAssertEqual(LinearFreshness.refreshInterval, 300)
        // A copy read 5 minutes ago is stale for the timer's forced read and for any 30 s maxAge reader.
        let now = Date()
        XCTAssertTrue(LinearClient.isStale(loaded: true, fetchedAt: now.addingTimeInterval(-LinearFreshness.refreshInterval), maxAge: 30, now: now))
    }
}
