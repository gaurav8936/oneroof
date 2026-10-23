import XCTest
@testable import OneRoofCore

/// LAB-595: in the Overview, subagents hang under the session (and subagent) that started them.
final class SubagentTreeTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_000_000)
    private func sub(_ id: String, parent: String? = nil, at: Double, ended: Double? = nil, status: SessionStatus? = nil) -> Subagent {
        Subagent(id: id, parentId: parent, sessionId: "s", name: id, started: t0.addingTimeInterval(at),
                 ended: ended.map { t0.addingTimeInterval($0) }, status: status ?? (ended == nil ? .running : .done))
    }

    func test_LAB595_childrenHangUnderTheirParentWithConnectors() {
        let subs = [sub("a", at: 0), sub("a1", parent: "a", at: 1), sub("a2", parent: "a", at: 2, ended: 5), sub("b", at: 3)]
        let (rows, hidden) = SubagentTree.branches(subs)
        XCTAssertEqual(rows.map(\.sub.id), ["a", "a1", "a2", "b"])
        XCTAssertEqual(rows.map(\.level), [1, 2, 2, 1])
        XCTAssertEqual(rows.map(\.isLast), [false, false, true, true])
        XCTAssertEqual(rows[1].rails, [true], "a's line carries on to b below")
        XCTAssertEqual(rows[3].rails, [])
        XCTAssertEqual(hidden, 0)
    }

    func test_LAB595_runningBranchesStayFinishedOnesAreTrimmed() {
        let subs = [sub("old1", at: 0, ended: 1), sub("old2", at: 1, ended: 2), sub("old3", at: 2, ended: 3),
                    sub("live", at: 3), sub("waits", at: 4, ended: nil, status: .needsYou)]
        let (rows, hidden) = SubagentTree.branches(subs, keepFinished: 1)
        XCTAssertEqual(rows.map(\.sub.id), ["old3", "live", "waits"])
        XCTAssertEqual(hidden, 2)
    }

    func test_LAB595_finishedParentWithRunningChildStays() {
        let subs = [sub("p", at: 0, ended: 9), sub("c", parent: "p", at: 1), sub("x", at: 2, ended: 3), sub("y", at: 3, ended: 4)]
        XCTAssertEqual(SubagentTree.branches(subs, keepFinished: 0).rows.map(\.sub.id), ["p", "c"])
    }

    func test_LAB595_rowLimitAndOrphans() {
        let subs = (0..<8).map { sub("r\($0)", at: Double($0)) } + [sub("orphan", parent: "gone", at: 9)]
        let (rows, hidden) = SubagentTree.branches(subs, limit: 4)
        XCTAssertEqual(rows.count, 4)
        XCTAssertTrue(rows.last!.isLast)
        XCTAssertEqual(hidden, 5)
        XCTAssertTrue(SubagentTree.branches(subs, limit: 20).rows.contains { $0.sub.id == "orphan" && $0.level == 1 })
    }

    func test_LAB595_summary() {
        let subs = [sub("a", at: 0), sub("b", at: 1, ended: 2), sub("c", at: 2, ended: nil, status: .needsYou), sub("d", at: 3)]
        XCTAssertEqual(SubagentTree.summary(subs), "1 needs you · 2 running · 1 done")
        XCTAssertEqual(SubagentTree.summary([]), "")
    }
}
