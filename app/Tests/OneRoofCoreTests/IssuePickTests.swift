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

    func testPickedFirstThenInProgressToDoBacklogAndInReviewLast() {
        XCTAssertEqual(IssuePick.rows(list, picked: []).map(\.identifier), ["LAB-7", "LAB-6", "LAB-8", "LAB-4", "LAB-9", "LAB-5"])
        XCTAssertEqual(IssuePick.rows(list, picked: ["LAB-4", "LAB-9"]).map(\.identifier),
                       ["LAB-4", "LAB-9", "LAB-7", "LAB-6", "LAB-8", "LAB-5"], "picked keep their pick order")
    }

    func testStateFilterAndQueryKeepPickedVisible() {
        XCTAssertEqual(IssuePick.rows(list, picked: ["LAB-9"], state: "Backlog").map(\.identifier), ["LAB-9", "LAB-8", "LAB-4"])
        XCTAssertEqual(IssuePick.rows(list, picked: [], query: "resize").map(\.identifier), ["LAB-4"])
        let withBody = [issue("LAB-1", "Backlog", "backlog", body: "the popover is fixed width")]
        XCTAssertEqual(IssuePick.rows(withBody, picked: [], query: "popover").count, 1, "the description is searched too")
    }

    func testChipsAreAllThenStatesInRankOrderWithCounts() {
        let chips = IssuePick.states(list)
        XCTAssertEqual(chips.map(\.label), ["All", "In Progress", "Todo", "Backlog", "In Review"])
        XCTAssertEqual(chips.map(\.count), [6, 1, 1, 2, 2])
        XCTAssertNil(chips[0].state)
    }
}
