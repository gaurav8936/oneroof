import XCTest
@testable import OneRoofCore

/// LAB-2311 · relaunching, removing and deleting a session leave no orphan holder, and the sweep closes only One Roof's
/// own shells that no row claims. Everything runs on FakeRuntime or on roofd `list` dictionaries: never the live roofd.
final class OrphanSessionsTests: XCTestCase {
    private func launched(_ r: FakeRuntime, _ s: inout Session, replaces: RuntimeID? = nil) throws {
        guard case .success(var spec) = LaunchPlan.spec(s, stored: [s], deliverOpening: true) else { return XCTFail("refused") }
        spec.replaces = replaces
        s.runtimeId = try r.start(spec).id
        s.launchedAt = Date(timeIntervalSinceNow: -60)
    }

    /// The agent exits and leaves its shell (roofd runs `claude …; exec zsh`): the session is a plain shell now.
    private func agentExits(_ r: FakeRuntime, _ id: RuntimeID) {
        r.update(id) { $0.isAgent = false; $0.agentName = nil }
    }

    /// Every live runtime session is some stored row's.
    private func orphans(_ r: FakeRuntime, _ stored: [Session]) throws -> [RuntimeID] {
        let claimed = Set(stored.compactMap(\.runtimeId))
        return try r.snapshot().sessions.map(\.id).filter { !claimed.contains($0) }
    }

    // MARK: Relaunch

    func test_LAB2311_relaunchOverAnEndedShellClosesItFirst() throws {
        let r = FakeRuntime()
        var s = Session(name: "x", agent: .claude, repoPath: Workspace.projectsRoot, lifecycle: .idle)
        try launched(r, &s)
        let first = try XCTUnwrap(s.runtimeId)
        agentExits(r, first)
        let item = try XCTUnwrap(Board.merge(stored: [s], snapshot: r.snapshot()).first)
        XCTAssertEqual(item.endedShell, first, "an ended shell, as in the ticket")
        try launched(r, &s, replaces: OrphanSessions.replaced(liveAgent: item.liveAgent, runtimeId: s.runtimeId))
        XCTAssertEqual(s.runtimeId, first, "the name is free again: no -2")
        XCTAssertEqual(try orphans(r, [s]), [])
        XCTAssertEqual(r.sessions.count, 1)
    }

    func test_LAB2311_relaunchWithoutReplacingWouldOrphanTheShell() throws {
        // The bug as it was: the row moves to `-2` and the old shell has no row.
        let r = FakeRuntime()
        var s = Session(name: "x", agent: .claude, repoPath: Workspace.projectsRoot, lifecycle: .idle)
        try launched(r, &s)
        let first = try XCTUnwrap(s.runtimeId)
        agentExits(r, first)
        try launched(r, &s)
        XCTAssertEqual(s.runtimeId, first + "-2")
        XCTAssertEqual(try orphans(r, [s]), [first])
    }

    func test_LAB2311_launchReplacesNothingWhileTheAgentRuns() {
        XCTAssertNil(OrphanSessions.replaced(liveAgent: "roof-1", runtimeId: "roof-1"))
        XCTAssertNil(OrphanSessions.replaced(liveAgent: nil, runtimeId: nil), "a first launch")
        XCTAssertEqual(OrphanSessions.replaced(liveAgent: nil, runtimeId: "roof-1-2"), "roof-1-2")
    }

    func test_LAB2311_roofdLaunchPlanClosesTheReplacedSessionAndPicksAFreeName() {
        var spec = LaunchSpec(id: "roof-ab12cd34", label: "x", cwd: "/p", agent: .claude)
        spec.replaces = "roof-ab12cd34"
        // The ended shell is still in the list (and would be for a moment after the close): the new one takes -2.
        let ended: [[String: Any]] = [["id": "roof-ab12cd34"]]
        let p = RoofdRuntime.launchPlan(spec, list: ended)
        XCTAssertFalse(p.adopt)
        XCTAssertEqual(p.close, "roof-ab12cd34")
        XCTAssertEqual(p.name, "roof-ab12cd34-2")
        // The next relaunch replaces -2; the first name left roofd once it was closed, so it is used again.
        spec.replaces = "roof-ab12cd34-2"
        let next = RoofdRuntime.launchPlan(spec, list: [["id": "roof-ab12cd34-2", "exited": 1.0]])
        XCTAssertEqual(next.close, "roof-ab12cd34-2", "an exited holder winding down is closed too")
        XCTAssertEqual(next.name, "roof-ab12cd34")
        // Never a session another row owns, never one that is not there.
        spec.claimed = ["roof-ab12cd34-2"]
        XCTAssertNil(RoofdRuntime.launchPlan(spec, list: [["id": "roof-ab12cd34-2"]]).close)
        spec.claimed = []
        XCTAssertNil(RoofdRuntime.launchPlan(spec, list: []).close)
    }

    func test_LAB2311_roofdLaunchPlanStillAdoptsAnEarlierLaunch() {
        var spec = LaunchSpec(id: "roof-1", label: "x", cwd: "/p", agent: .claude, adoptOrphan: true)
        XCTAssertTrue(RoofdRuntime.launchPlan(spec, list: [["id": "roof-1"]]).adopt)
        spec.claimed = ["roof-1"]
        let p = RoofdRuntime.launchPlan(spec, list: [["id": "roof-1"]])
        XCTAssertFalse(p.adopt)
        XCTAssertEqual(p.name, "roof-1-2")
    }

    // MARK: Remove and Delete forever

    func test_LAB2311_removeClosesTheEndedShellByRuntimeId() throws {
        let r = FakeRuntime()
        var s = Session(name: "x", agent: .claude, repoPath: Workspace.projectsRoot, lifecycle: .idle)
        try launched(r, &s)
        agentExits(r, s.runtimeId!)
        let item = try XCTUnwrap(Board.merge(stored: [s], snapshot: r.snapshot()).first)
        XCTAssertNil(s.runtimeGroup, "under roofd there is no group: closing by group closed nothing")
        let id = try XCTUnwrap(OrphanSessions.removeTarget(liveAgent: item.liveAgent, endedShell: item.endedShell,
                                                           runtimeId: s.runtimeId, forever: false))
        try r.close(id, group: s.runtimeGroup)
        XCTAssertEqual(r.sessions.count, 0)
    }

    func test_LAB2311_deleteForeverClosesTheSessionEvenWhileItsAgentRuns() throws {
        let r = FakeRuntime()
        var s = Session(name: "x", agent: .claude, repoPath: Workspace.projectsRoot, lifecycle: .idle)
        try launched(r, &s)
        let item = try XCTUnwrap(Board.merge(stored: [s], snapshot: r.snapshot()).first)
        XCTAssertNotNil(item.liveAgent)
        XCTAssertNil(OrphanSessions.removeTarget(liveAgent: item.liveAgent, endedShell: nil, runtimeId: s.runtimeId, forever: false),
                     "Remove keeps a running agent (the archived row still owns it)")
        let id = try XCTUnwrap(OrphanSessions.removeTarget(liveAgent: item.liveAgent, endedShell: item.endedShell,
                                                           runtimeId: s.runtimeId, forever: true))
        try r.close(id, group: s.runtimeGroup)
        // The row is gone: nothing may be left running for it.
        XCTAssertEqual(try orphans(r, []), [])
    }

    func test_LAB2311_removeTargetFallsBackToTheRuntimeId() {
        XCTAssertEqual(OrphanSessions.removeTarget(liveAgent: nil, endedShell: nil, runtimeId: "roof-1", forever: false), "roof-1",
                       "an exited holder still in roofd's list")
        XCTAssertNil(OrphanSessions.removeTarget(liveAgent: nil, endedShell: nil, runtimeId: nil, forever: true), "never ran")
        XCTAssertEqual(OrphanSessions.removeTarget(liveAgent: nil, endedShell: "roof-1-2", runtimeId: "roof-1-2", forever: true), "roof-1-2")
    }

    // MARK: Sweep

    private let now = Date(timeIntervalSince1970: 1_000_000)
    private func shell(_ id: String, quietFor: TimeInterval = 600, attached: Bool = false, agent: Bool = false) -> RuntimeSessionState {
        var s = RuntimeSessionState(id: id, isAgent: agent, agentName: agent ? "claude" : nil, pane: id,
                                    activeAt: now.addingTimeInterval(-quietFor))
        s.attached = attached
        return s
    }

    func test_LAB2311_sweepClosesOnlyUnclaimedQuietOneRoofShells() {
        var row = Session(name: "x", agent: .claude, repoPath: "/p", lifecycle: .idle)
        row.runtimeId = "roof-aaaa1111-3"
        let snap = RuntimeSnapshot(sessions: [
            shell("roof-aaaa1111-3"),                    // the row's own
            shell("roof-aaaa1111-2"),                    // orphaned by a relaunch
            shell("roof-bbbb2222"),                      // its row was removed
            shell("roof-cccc3333", quietFor: 30),        // touched a moment ago
            shell("roof-dddd4444", attached: true),      // someone is looking at it
            shell("roof-eeee5555", agent: true),         // an agent: Board.merge adopts it as a row
            shell("term:owner"),                         // not One Roof's
        ])
        XCTAssertEqual(OrphanSessions.sweep(snapshot: snap, stored: [row], now: now).sorted(), ["roof-aaaa1111-2", "roof-bbbb2222"])
    }

    func test_LAB2311_sweepNeverTouchesALoopRound() {
        var round = Session(id: "1234abcd-0000-0000-0000-000000000000", name: "loop · round 2", agent: .claude, repoPath: "/p",
                            tags: ["loop:nightly"], lifecycle: .idle)
        round.runtimeId = "roof-1234abcd-2"
        let snap = RuntimeSnapshot(sessions: [shell("roof-1234abcd"), shell("roof-1234abcd-3")])
        XCTAssertEqual(OrphanSessions.sweep(snapshot: snap, stored: [round], now: now), [])
    }

    func test_LAB2311_sweepNeedsAnActiveTime() {
        let s = RuntimeSessionState(id: "roof-1", isAgent: false, pane: "roof-1")
        XCTAssertEqual(OrphanSessions.sweep(snapshot: RuntimeSnapshot(sessions: [s]), stored: [], now: now), [])
    }

    func test_LAB2311_baseName() {
        XCTAssertEqual(OrphanSessions.baseName("roof-ab12cd34-3"), "roof-ab12cd34")
        XCTAssertEqual(OrphanSessions.baseName("roof-ab12cd34"), "roof-ab12cd34")
        XCTAssertEqual(OrphanSessions.baseName("roof-ab12cd34-"), "roof-ab12cd34-")
        XCTAssertEqual(OrphanSessions.baseName("term:x-2"), "term:x-2")
    }

    func test_LAB2311_roofdListCarriesAttached() {
        XCTAssertEqual(RoofdRuntime.sessionState(["id": "roof-1", "attached": true])?.attached, true)
        XCTAssertEqual(RoofdRuntime.sessionState(["id": "roof-2", "agent": "claude", "attached": true])?.attached, true)
        XCTAssertEqual(RoofdRuntime.sessionState(["id": "roof-3"])?.attached, false)
    }
}
