import XCTest
@testable import OneRoofCore

/// LAB-523: the issue picker's order and state filters.
final class IssuePickTests: XCTestCase {
    func issue(_ key: String, _ state: String, _ type: String, title: String = "t", body: String = "") -> LinearIssue {
        LinearIssue(id: key, identifier: key, title: title, description: body, state: state, stateType: type,
                    type: nil, milestoneId: nil, milestone: nil, url: "")
    }

    lazy var list = [
        issue("LAB-9", "In Review", "started"), issue("LAB-8", "Backlog", "backlog"), issue("LAB-7", "In Progress", "started"),
        issue("LAB-6", "Todo", "unstarted"), issue("LAB-5", "In Review", "started"), issue("LAB-4", "Backlog", "backlog", title: "Resize the panel"),
    ]

    func testInProgressToDoBacklogAndInReviewLast() {
        XCTAssertEqual(IssuePick.rows(list, picked: []).map(\.identifier), ["LAB-7", "LAB-6", "LAB-8", "LAB-4", "LAB-9", "LAB-5"])
    }

    /// LAB-527: ticking never moves a row (picked rows used to jump to the top and the list scrolled under the pointer).
    func testPickingDoesNotReorderRows() {
        let none = IssuePick.rows(list, picked: []).map(\.identifier)
        XCTAssertEqual(IssuePick.rows(list, picked: ["LAB-4", "LAB-9"]).map(\.identifier), none)
        XCTAssertEqual(IssuePick.rows(list, picked: ["LAB-4"], state: "Backlog").map(\.identifier), ["LAB-8", "LAB-4"])
    }

    func testPickedFilterShowsOnlyPickedInPickOrder() {
        XCTAssertEqual(IssuePick.rows(list, picked: ["LAB-4", "LAB-9"], state: IssuePick.pickedFilter).map(\.identifier), ["LAB-4", "LAB-9"])
        XCTAssertEqual(IssuePick.rows(list, picked: ["LAB-4", "LAB-9"], state: IssuePick.pickedFilter, query: "resize").map(\.identifier), ["LAB-4"])
    }

    func testStateFilterAndQuery() {
        XCTAssertEqual(IssuePick.rows(list, picked: ["LAB-9"], state: "Backlog").map(\.identifier), ["LAB-8", "LAB-4"])
        XCTAssertEqual(IssuePick.rows(list, picked: [], query: "resize").map(\.identifier), ["LAB-4"])
        let withBody = [issue("LAB-1", "Backlog", "backlog", body: "the popover is fixed width")]
        XCTAssertEqual(IssuePick.rows(withBody, picked: [], query: "popover").count, 1, "the description is searched too")
    }

    func testChipsAreAllThenStatesInRankOrderWithCounts() {
        let chips = IssuePick.states(list)
        XCTAssertEqual(chips.map(\.label), ["All", "In Progress", "Todo", "Backlog", "In Review"])
        XCTAssertEqual(chips.map(\.count), [6, 1, 1, 2, 2])
        XCTAssertNil(chips[0].state)
        let withPicked = IssuePick.states(list, picked: 2)
        XCTAssertEqual(withPicked.map(\.label), ["All", "Picked", "In Progress", "Todo", "Backlog", "In Review"])
        XCTAssertEqual(withPicked[1].count, 2)
        XCTAssertEqual(withPicked[1].state, IssuePick.pickedFilter)
    }

    // LAB-547: sortable columns.
    func testSortByKeyIsNumericNotText() {
        let rows = [issue("LAB-90", "Backlog", "backlog"), issue("LAB-547", "Backlog", "backlog"), issue("LAB-100", "Backlog", "backlog")]
        XCTAssertEqual(IssuePick.sorted(rows, by: [KeyPathComparator(\LinearIssue.number)]).map(\.identifier), ["LAB-90", "LAB-100", "LAB-547"])
        XCTAssertEqual(IssuePick.sorted(rows, by: [KeyPathComparator(\LinearIssue.number, order: .reverse)]).map(\.identifier),
                       ["LAB-547", "LAB-100", "LAB-90"])
    }

    func testNoSortKeepsDefaultOrderAndTiesBreakByNumber() {
        let rows = IssuePick.rows(list, picked: [])
        XCTAssertEqual(IssuePick.sorted(rows, by: []), rows)
        let byState = IssuePick.sorted(list, by: [KeyPathComparator(\LinearIssue.pickRank)]).map(\.identifier)
        XCTAssertEqual(byState, ["LAB-7", "LAB-6", "LAB-4", "LAB-8", "LAB-5", "LAB-9"])
    }

    func testSortByCreatedNewestFirstMissingDatesLast() {
        var a = issue("LAB-1", "Backlog", "backlog"), b = issue("LAB-2", "Backlog", "backlog"), c = issue("LAB-3", "Backlog", "backlog")
        a.createdAt = Date(timeIntervalSince1970: 100); b.createdAt = Date(timeIntervalSince1970: 300)
        let newest = IssuePick.sorted([a, b, c], by: [KeyPathComparator(\LinearIssue.created, order: .reverse)]).map(\.identifier)
        XCTAssertEqual(newest, ["LAB-2", "LAB-1", "LAB-3"])
        XCTAssertEqual(c.updated, .distantPast)
        b.updatedAt = Date(timeIntervalSince1970: 900)
        XCTAssertEqual(b.updated, Date(timeIntervalSince1970: 900))
        XCTAssertEqual(a.updated, a.created)
    }

    func testLinearTimestampsParse() {
        XCTAssertEqual(LinearClient.date("2026-10-22T22:47:26.859Z")?.timeIntervalSince1970 ?? 0, 1_792_709_246.859, accuracy: 0.001)
        XCTAssertEqual(LinearClient.date("2026-10-22T22:47:26Z")?.timeIntervalSince1970, 1_792_709_246)
        XCTAssertNil(LinearClient.date(nil))
        XCTAssertNil(LinearClient.date("yesterday"))
    }
}
