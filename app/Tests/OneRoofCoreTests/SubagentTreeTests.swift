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

    /// LAB-635: Overview › Agents shows each live session under its account, and the lanes (subagents) a session is
    /// running under it, instead of "Claude1 · 4 live".
    func test_LAB635_agentsTabListsSessionsWithTheirRunningSubagents() {
        let subs = ["build": [sub("laneB", at: 2), sub("laneA", at: 1), sub("research", at: 0, ended: 1)]]
        let g = AgentsAtWork.groups([(id: "quiet", key: "Claude1"), (id: "build", key: "Claude1"), (id: "k", key: "Kimi")], subagents: subs)
        XCTAssertEqual(g.map(\.key), ["Claude1", "Kimi"])
        XCTAssertEqual(g[0].sessions.map(\.sessionId), ["build", "quiet"], "a session running lanes comes first")
        XCTAssertEqual(g[0].sessions[0].running.map(\.id), ["laneA", "laneB"], "running only, in start order")
        XCTAssertEqual(g[0].runningSubagents, 2)
        XCTAssertEqual(g[1].runningSubagents, 0)
    }
}

/// LAB-694: the Subagents timeline's labels never overlap.
final class TimelineTickTests: XCTestCase {
    func test_LAB694_tickStepFitsTheWidth() {
        // The owner's case: 159 min on ~780 pt drew a label every 2 min (4.9 pt apart).
        let s = TimelineTicks.step(span: 159 * 60, width: 780)
        XCTAssertEqual(s, 15)
        let ticks = TimelineTicks.ticks(span: 159 * 60, width: 780)
        XCTAssertEqual(ticks.first, 0)
        for (a, b) in zip(ticks, ticks.dropFirst()) { XCTAssertGreaterThanOrEqual(780 * Double(b - a) / 159, 56) }
        XCTAssertEqual(TimelineTicks.step(span: 14 * 60, width: 900), 1, "a short span keeps every minute")
        XCTAssertEqual(TimelineTicks.step(span: 48 * 3600, width: 600), 360)
        XCTAssertEqual(TimelineTicks.label(0), "0m")
        XCTAssertEqual(TimelineTicks.label(90), "1h30")
        XCTAssertEqual(TimelineTicks.label(120), "2h")
        XCTAssertFalse(TimelineTicks.ticks(span: 60 * 60, width: 300).contains(60), "no label hanging off the right edge")
    }
}

/// LAB-695: the Subagents detail card says what each part means, with a real summary instead of "no caption yet".
final class SubagentDetailTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_000_000)

    func test_LAB695_detailCardSaysStatusAndSummaryInPlainWords() {
        var s = Subagent(id: "a", sessionId: "p", name: "R1 lane A: window identity", asked: "You are Lane A …",
                         started: t0, ended: t0.addingTimeInterval(480), status: .done)
        let now = t0.addingTimeInterval(480 + 7200)
        XCTAssertEqual(SubagentDetail.status(s, now: now), "Finished 2h ago · ran 8m")
        XCTAssertEqual(SubagentDetail.summary(s).text, "It finished without a written report")
        s.lastText = "Lane A done: window names show in every window. Tests 7/7."
        XCTAssertEqual(SubagentDetail.summary(s).label, "Its final report")
        XCTAssertEqual(SubagentDetail.summary(s).text, "Lane A done: window names show in every window. Tests 7/7.")
        s.caption = "Writing tests"
        XCTAssertEqual(SubagentDetail.summary(s).text, "Writing tests")
        let running = Subagent(id: "b", sessionId: "p", name: "b", started: t0)
        XCTAssertEqual(SubagentDetail.status(running, now: t0.addingTimeInterval(180)), "Running for 3m")
        XCTAssertEqual(SubagentDetail.summary(running).text, "Working · it has not written a message yet")
        XCTAssertTrue(SubagentDetail.isLong(String(repeating: "x", count: 500)))
        XCTAssertFalse(SubagentDetail.isLong("short"))
    }
}
