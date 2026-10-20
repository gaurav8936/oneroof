import XCTest
@testable import OneRoofCore

/// The session life cycle on `FakeRuntime`: launch, opening delivery, close and reopen, as `AppModel` drives them.
final class FakeRuntimeTests: XCTestCase {
    let t0 = Date(timeIntervalSince1970: 1_000_000)

    func launch(_ s: inout Session, on r: FakeRuntime) throws {
        let ref = try r.start(LaunchSpec(id: Session.herdrName(for: s.id), label: s.name, cwd: s.launchDirectory, agent: s.agent,
                                         args: s.launchArgs, previousGroup: s.runtimeGroup,
                                         adoptOrphan: s.agent.isAgent && s.runtimeId == nil))
        s.runtimeId = ref.id
        s.runtimeGroup = ref.groupId
        s.lifecycle = .idle
    }

    func testLaunchShowsTheSessionLive() throws {
        let r = FakeRuntime()
        var s = Session(name: "Fix login", agent: .claude, repoPath: "/p", lifecycle: .planned)
        try launch(&s, on: r)
        let items = Board.merge(stored: [s], snapshot: try r.snapshot())
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items.first?.status, .idle)
        XCTAssertEqual(items.first?.liveAgent, Session.herdrName(for: s.id))
        XCTAssertEqual(items.first?.ready, true)
        XCTAssertFalse(items.first?.adopted ?? true)
    }

    func testOpeningIsSentOnlyAfterTheSettleTimeAndOnce() throws {
        let r = FakeRuntime()
        var s = Session(name: "Fix login", agent: .claude, repoPath: "/p", openingMessage: "Read the plan.", lifecycle: .planned)
        try launch(&s, on: r)
        var gate = OpeningGate()
        var items = Board.merge(stored: [s], snapshot: try r.snapshot())
        gate.observe(items, now: t0)
        XCTAssertTrue(gate.due(items, now: t0.addingTimeInterval(1), sending: [], retryAfter: [:]).isEmpty, "settle time is 2 s")
        XCTAssertTrue(gate.due(items, now: t0.addingTimeInterval(3), sending: [s.id], retryAfter: [:]).isEmpty, "already sending")
        XCTAssertTrue(gate.due(items, now: t0.addingTimeInterval(3), sending: [], retryAfter: [s.id: t0.addingTimeInterval(5)]).isEmpty)
        let due = gate.due(items, now: t0.addingTimeInterval(3), sending: [], retryAfter: [:])
        XCTAssertEqual(due.map(\.id), [s.id])

        try r.submit(due[0].liveAgent!, text: s.openingMessage)
        s.openingSent = true
        XCTAssertEqual(r.submitted.map(\.text), ["Read the plan."])
        items = Board.merge(stored: [s], snapshot: try r.snapshot())
        XCTAssertEqual(items.first?.status, .running)
        gate.observe(items, now: t0.addingTimeInterval(4))
        XCTAssertTrue(gate.due(items, now: t0.addingTimeInterval(60), sending: [], retryAfter: [:]).isEmpty)
    }

    func testSlowAgentsSettleLongerAndBusyAgentsNeverGetTheOpening() throws {
        let r = FakeRuntime()
        var k = Session(name: "Research", agent: .kimi, repoPath: "/p", openingMessage: "Go.", lifecycle: .planned)
        try launch(&k, on: r)
        var gate = OpeningGate()
        gate.observe(Board.merge(stored: [k], snapshot: try r.snapshot()), now: t0)
        let items = Board.merge(stored: [k], snapshot: try r.snapshot())
        XCTAssertTrue(gate.due(items, now: t0.addingTimeInterval(5), sending: [], retryAfter: [:]).isEmpty)
        XCTAssertEqual(gate.due(items, now: t0.addingTimeInterval(10), sending: [], retryAfter: [:]).count, 1)

        r.update(k.runtimeId!) { $0.status = .blocked }
        let blocked = Board.merge(stored: [k], snapshot: try r.snapshot())
        gate.observe(blocked, now: t0.addingTimeInterval(11))
        XCTAssertTrue(gate.due(blocked, now: t0.addingTimeInterval(30), sending: [], retryAfter: [:]).isEmpty)
    }

    func testNotReadyIsReportedSoTheAppRetries() throws {
        let r = FakeRuntime()
        var s = Session(name: "x", agent: .claude, repoPath: "/p", lifecycle: .planned)
        try launch(&s, on: r)
        r.notReady = [s.runtimeId!]
        XCTAssertThrowsError(try r.submit(s.runtimeId!, text: "hi")) { XCTAssertEqual($0 as? RuntimeError, .notReady(s.runtimeId!)) }
    }

    func testCloseLeavesTheRowExited() throws {
        let r = FakeRuntime()
        var s = Session(name: "x", agent: .claude, repoPath: "/p", lifecycle: .planned)
        try launch(&s, on: r)
        try r.close(s.runtimeId!, group: s.runtimeGroup)
        let items = Board.merge(stored: [s], snapshot: try r.snapshot())
        XCTAssertEqual(items.first?.status, .exited)
        XCTAssertNil(items.first?.liveAgent)
    }

    func testReopenStartsAgainUnderTheSameNameOnceTheOldOneIsGone() throws {
        let r = FakeRuntime()
        var s = Session(name: "x", agent: .claude, repoPath: "/p", lifecycle: .planned)
        try launch(&s, on: r)
        let first = s.runtimeId!
        try r.close(first, group: s.runtimeGroup)
        // reopenClosed: the row forgets its runtime link, then launches.
        s.runtimeId = nil; s.runtimeGroup = nil; s.openingSent = false
        try launch(&s, on: r)
        XCTAssertEqual(s.runtimeId, first)
        XCTAssertEqual(Board.merge(stored: [s], snapshot: try r.snapshot()).first?.status, .idle)
    }

    func testRelaunchWhileTheOldAgentLivesGetsASuffixAndClosesTheOldGroup() throws {
        let r = FakeRuntime()
        var s = Session(name: "x", agent: .claude, repoPath: "/p", lifecycle: .planned)
        try launch(&s, on: r)
        let first = s.runtimeId!
        // Another stored session owns the old name, so it is not adopted back.
        let ref = try r.start(LaunchSpec(id: first, label: "x", cwd: "/p", agent: .claude, adoptOrphan: true, claimed: [first]))
        XCTAssertEqual(ref.id, first + "-2")
        let adopted = try r.start(LaunchSpec(id: first, label: "x", cwd: "/p", agent: .claude, adoptOrphan: true))
        XCTAssertTrue(adopted.adopted, "an unclaimed agent with the session's name is linked, not started twice")
    }

    func testAPlainTerminalRunsItsCommand() throws {
        let r = FakeRuntime()
        let ref = try r.start(LaunchSpec(id: "roof-t", label: "Fix", cwd: "/p", agent: .shell, command: "brew install herdr"))
        XCTAssertTrue(ref.id.hasPrefix(Session.terminalPrefix))
        XCTAssertEqual(r.typed.last?.text, "brew install herdr\n")
        XCTAssertFalse(try r.snapshot().sessions[0].isAgent)
    }

    func testSeenTurnsDoneIntoIdle() throws {
        let r = FakeRuntime()
        var s = Session(name: "x", agent: .claude, repoPath: "/p", lifecycle: .planned)
        try launch(&s, on: r)
        r.update(s.runtimeId!) { $0.status = .done }
        r.markSeen(s.runtimeId!)
        XCTAssertEqual(try r.snapshot().session(s.runtimeId!)?.status, .idle)
    }

    func testStoppedRuntimeFails() {
        let r = FakeRuntime()
        r.running = false
        XCTAssertThrowsError(try r.snapshot())
        XCTAssertEqual(r.health().level, .fail)
        XCTAssertEqual(Foundations.runtimeCheck(r).title, "fake")
    }
}
