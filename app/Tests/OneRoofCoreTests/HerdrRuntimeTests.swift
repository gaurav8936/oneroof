import XCTest
@testable import OneRoofCore

/// A scripted herdr: replies come from the test, every call is recorded.
class FakeHerdr: HerdrTransport, @unchecked Sendable {
    let herdrPath = "/opt/homebrew/bin/herdr"
    var proto: Int? = 22
    var leaks: [String: String] = [:]
    var snap = HerdrSnapshot()
    /// Errors `startAgent` throws, one per call, before it succeeds.
    var startErrors: [Error] = []
    /// Applied to `snap` when an agent starts (herdr now reports it).
    var onStart: ((String, String) -> Void)?
    var promptError: Error?
    var paneRC: Int32 = 0
    private(set) var calls: [String] = []
    private var ws = 0

    func ping() -> Int? { proto }
    func ensureServer() throws { calls.append("ensureServer"); if proto == nil { throw HerdrClient.Failure.notRunning("sock") } }
    func serverLeaks() -> [String: String] { leaks }
    func stopServer() { calls.append("stopServer"); leaks = [:] }
    func snapshot() throws -> HerdrSnapshot { snap }
    func createWorkspace(cwd: String, env: [String: String], label: String) throws -> (workspace: String, pane: String) {
        ws += 1
        calls.append("createWorkspace \(cwd) \(label)")
        let w = "w\(ws)", p = "w\(ws):p1"
        snap.panes.append(HerdrPane(pane_id: p, terminal_id: "term_\(ws)", workspace_id: w, cwd: cwd, foreground_cwd: nil, agent_status: nil))
        return (w, p)
    }
    func startAgent(name: String, kind: String, paneId: String, args: [String], timeoutMs: Int) throws {
        calls.append("startAgent \(name) \(kind) \(args.joined(separator: " "))")
        if !startErrors.isEmpty { throw startErrors.removeFirst() }
        onStart?(name, paneId)
    }
    func prompt(agent: String, text: String) throws {
        calls.append("prompt \(agent) \(text)")
        if let promptError { throw promptError }
    }
    func processInfo(paneId: String) throws -> HerdrProcessInfo {
        try JSONDecoder().decode(HerdrProcessInfo.self, from: Data(#"{"shell_pid":10,"foreground_processes":[{"pid":11,"name":"claude","argv":["claude","--resume"]}]}"#.utf8))
    }
    func closeWorkspace(_ id: String) throws { calls.append("closeWorkspace \(id)") }
    func attachCommand(agent: String) -> String { HerdrClient(herdrPath: herdrPath).attachCommand(agent: agent) }
    func paneCommand(_ args: [String], timeout: TimeInterval) -> (Int32, String) {
        calls.append("pane " + args.joined(separator: " "))
        return (paneRC, args.first == "read" ? "screen text" : "")
    }
}

final class HerdrRuntimeTests: XCTestCase {
    func runtime(_ h: FakeHerdr) -> HerdrRuntime { HerdrRuntime(client: h, busyRetryDelay: 1_000, typeCommandDelay: 0.05) }
    func spec(_ agent: AgentKind = .claude, id: String = "roof-1a2b3c4d") -> LaunchSpec {
        LaunchSpec(id: id, label: "Fix login", cwd: "/p/repo", env: ["CLAUDE_CONFIG_DIR": "/c2"], agent: agent, args: ["--model", "haiku"],
                   adoptOrphan: agent.isAgent)
    }
    func runtimeId(_ name: String, ws: String = "w0") -> HerdrAgent {
        HerdrAgent(name: name, agent: "claude", agent_status: "idle", cwd: "/p", pane_id: ws + ":p1", workspace_id: ws)
    }

    func testHerdrStatusMapping() {
        XCTAssertEqual(SessionStatus.fromHerdr("working"), .running)
        XCTAssertEqual(SessionStatus.fromHerdr("blocked"), .needsYou)
        XCTAssertEqual(SessionStatus.fromHerdr("done"), .done)
        XCTAssertEqual(SessionStatus.fromHerdr("idle"), .idle)
        XCTAssertEqual(SessionStatus.fromHerdr(nil), .idle)
    }


    func testConvertAgentsThenShellsWithoutDuplicates() {
        var a = runtimeId("term:term_2", ws: "w2"); a.revision = 7; a.foreground_cwd = "/p/sub"
        let snap = HerdrSnapshot(panes: [
            HerdrPane(pane_id: "w1:p1", terminal_id: "term_1", workspace_id: "w1", cwd: "/p", foreground_cwd: nil, agent_status: nil),
            HerdrPane(pane_id: "w2:p1", terminal_id: "term_2", workspace_id: "w2", cwd: "/p", foreground_cwd: nil, agent_status: nil),
            HerdrPane(pane_id: "w3:p1", terminal_id: nil, workspace_id: "w3", cwd: "/p", foreground_cwd: nil, agent_status: nil),
        ], agents: [a])
        let r = HerdrRuntime.convert(snap)
        XCTAssertEqual(r.sessions.map(\.id), ["term:term_2", "term:term_1"])
        XCTAssertEqual(r.sessions[0].seq, 7)
        XCTAssertEqual(r.sessions[0].cwd, "/p/sub")
        XCTAssertEqual(r.sessions[0].agent, .claude)
        XCTAssertFalse(r.sessions[1].isAgent)
        XCTAssertEqual(r.agents.count, 1)
    }

    func testStartsAnAgentInANewWorkspace() throws {
        let h = FakeHerdr()
        let ref = try runtime(h).start(spec())
        XCTAssertEqual(ref, RuntimeSessionRef(id: "roof-1a2b3c4d", groupId: "w1"))
        XCTAssertEqual(h.calls, ["ensureServer", "createWorkspace /p/repo Fix login", "startAgent roof-1a2b3c4d claude --model haiku"])
    }

    func testNamesAreMadeUniqueAndTheOldWorkspaceIsClosed() throws {
        let h = FakeHerdr()
        h.snap.agents = [runtimeId("roof-1a2b3c4d"), runtimeId("roof-1a2b3c4d-2")]
        var s = spec(); s.previousGroup = "w0"; s.claimed = ["roof-1a2b3c4d", "roof-1a2b3c4d-2"]
        let ref = try runtime(h).start(s)
        XCTAssertEqual(ref.id, "roof-1a2b3c4d-3")
        XCTAssertTrue(h.calls.contains("closeWorkspace w0"))
    }

    func testAnUnclaimedAgentWithTheSessionsNameIsAdopted() throws {
        let h = FakeHerdr()
        h.snap.agents = [runtimeId("roof-1a2b3c4d", ws: "w7")]
        let ref = try runtime(h).start(spec())
        XCTAssertEqual(ref, RuntimeSessionRef(id: "roof-1a2b3c4d", groupId: "w7", adopted: true))
        XCTAssertFalse(h.calls.contains { $0.hasPrefix("createWorkspace") })
    }

    func testRetriesWhileThePaneIsBusyAndStopsOnNotReady() throws {
        let h = FakeHerdr()
        h.startErrors = [HerdrClient.Failure.api(code: "agent_pane_busy", message: ""), HerdrClient.Failure.api(code: "agent_pane_busy", message: "")]
        _ = try runtime(h).start(spec())
        XCTAssertEqual(h.calls.filter { $0.hasPrefix("startAgent") }.count, 3)

        let h2 = FakeHerdr()
        h2.startErrors = [HerdrClient.Failure.api(code: "agent_not_ready", message: "trust")]
        XCTAssertEqual(try runtime(h2).start(spec()).id, "roof-1a2b3c4d")
        XCTAssertEqual(h2.calls.filter { $0.hasPrefix("startAgent") }.count, 1)
    }

    func testAnErrorAfterTheAgentAppearedStillCountsAsStarted() throws {
        var s = spec(); s.adoptOrphan = false
        let h = FakeHerdr()
        h.startErrors = [HerdrClient.Failure.io("timeout")]
        XCTAssertThrowsError(try runtime(h).start(s))      // no agent: the error stands
        let late = LateAgentHerdr(runtimeId("roof-1a2b3c4d", ws: "w1"))
        late.startErrors = [HerdrClient.Failure.io("timeout")]
        XCTAssertEqual(try runtime(late).start(s), RuntimeSessionRef(id: "roof-1a2b3c4d", groupId: "w1"))
    }

    func testALeakyServerIsRestartedWhenIdleAndRefusedWhenBusy() throws {
        let h = FakeHerdr()
        h.leaks = ["CLAUDE_CONFIG_DIR": "/c2"]
        _ = try runtime(h).start(spec())
        XCTAssertTrue(h.calls.contains("stopServer"))

        let busy = FakeHerdr()
        busy.leaks = ["CLAUDE_CONFIG_DIR": "/c2"]
        busy.snap.agents = [runtimeId("other")]
        XCTAssertThrowsError(try runtime(busy).start(spec())) { e in
            XCTAssertTrue("\(e)".contains("wrong account"))
        }
        XCTAssertFalse(busy.calls.contains("stopServer"))
    }

    func testAPlainTerminalIsLinkedByItsTerminalIdAndRunsItsCommand() throws {
        let h = FakeHerdr()
        var s = spec(.shell); s.command = "brew install herdr"
        let ref = try runtime(h).start(s)
        XCTAssertEqual(ref, RuntimeSessionRef(id: "term:term_1", groupId: "w1"))
        XCTAssertFalse(h.calls.contains { $0.hasPrefix("startAgent") })
        let ran = expectation(description: "command typed")
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.3) {
            if h.calls.contains("pane run w1:p1 brew install herdr") { ran.fulfill() }
        }
        wait(for: [ran], timeout: 2)
    }

    func testIOGoesToTheRightHerdrCalls() throws {
        let h = FakeHerdr()
        let r = runtime(h)
        try r.keys(pane: "w1:p1", [.escape, .enter, .ctrlC])
        try r.type(pane: "w1:p1", text: "/skill ")
        XCTAssertEqual(try r.read(pane: "w1:p1", lines: 300), "screen text")
        try r.close("roof-1", group: "w1")
        try r.close("roof-2", group: nil)
        XCTAssertEqual(h.calls, ["pane send-keys w1:p1 esc", "pane send-keys w1:p1 enter", "pane send-keys w1:p1 ctrl-c",
                                 "pane send-text w1:p1 /skill ", "pane read w1:p1 --source recent --lines 300", "closeWorkspace w1"])
        let procs = try r.processes(pane: "w1:p1")
        XCTAssertEqual(procs.shellPid, 10)
        XCTAssertEqual(procs.foreground.first?.argv, ["claude", "--resume"])
        h.paneRC = 1
        XCTAssertThrowsError(try r.read(pane: "w1:p1", lines: 1))
    }

    func testSubmitMapsNotReady() {
        let h = FakeHerdr()
        h.promptError = HerdrClient.Failure.api(code: "agent_not_ready", message: "starting")
        XCTAssertThrowsError(try runtime(h).submit("roof-1", text: "hi")) { e in
            XCTAssertEqual(e as? RuntimeError, .notReady("starting"))
        }
        h.promptError = HerdrClient.Failure.api(code: "agent_not_found", message: "")
        XCTAssertThrowsError(try runtime(h).submit("roof-1", text: "hi")) { e in XCTAssertNil(e as? RuntimeError) }
    }

    func testHealthAndStatusLine() {
        let h = FakeHerdr()
        XCTAssertEqual(runtime(h).health().level, .ok)
        h.leaks = ["CODEX_HOME": "/x"]
        XCTAssertEqual(runtime(h).health().level, .warn)
        h.proto = nil
        XCTAssertEqual(runtime(h).health().level, .fail)
        XCTAssertEqual(Foundations.runtimeCheck(runtime(h)).id, "herdr")
        XCTAssertEqual(Foundations.runtimeCheck(nil).level, .warn)

        let r = runtime(FakeHerdr())
        XCTAssertEqual(r.statusLine(RuntimeSnapshot(version: "0.9.5", protocolVersion: 22, sessions: [
            RuntimeSessionState(id: "a", isAgent: true, pane: "1"), RuntimeSessionState(id: "term:t", isAgent: false, pane: "2")])),
            "herdr 0.9.5 · 1 agent")
        XCTAssertEqual(r.statusLine(RuntimeSnapshot(version: "1.0", protocolVersion: 23)), "herdr 1.0 · protocol 23 (One Roof expects 22)")
    }

    func testTerminalAttachCommand() {
        let r = HerdrRuntime(client: HerdrClient())
        XCTAssertTrue(r.attachCommand("term:term_9").hasSuffix("terminal attach term_9"))
        XCTAssertTrue(r.attachCommand("roof-1").hasSuffix("agent attach roof-1"))
    }
}

/// herdr creates the agent but `agent.start` still errors (seen with slow MCP start-ups).
final class LateAgentHerdr: FakeHerdr, @unchecked Sendable {
    let agent: HerdrAgent
    init(_ agent: HerdrAgent) { self.agent = agent }
    override func startAgent(name: String, kind: String, paneId: String, args: [String], timeoutMs: Int) throws {
        snap.agents.append(agent)
        try super.startAgent(name: name, kind: kind, paneId: paneId, args: args, timeoutMs: timeoutMs)
    }
}

final class HerdrSnapshotDecodingTests: XCTestCase {
    func testUnnamedAgentDoesNotBreakTheSnapshot() throws {
        let json = """
        {"version":"0.9.5","protocol":22,"workspaces":[{"workspace_id":"w1"},{"bad":1}],"panes":[],
         "agents":[{"name":"roof-1","agent":"claude","pane_id":"w1:p1","agent_status":"idle"},
                   {"agent":"claude","pane_id":"w2:p1","terminal_id":"term_9","agent_status":"done"},
                   {"agent":"claude"}]}
        """
        let s = try JSONDecoder().decode(HerdrSnapshot.self, from: Data(json.utf8))
        XCTAssertEqual(s.agents.map(\.name), ["roof-1", "term:term_9"])
        XCTAssertEqual(s.workspaces.count, 1)
    }

    /// LAB-22: the caption engine's "new output" signal comes from `revision`.
    func testAgentRevisionIsDecoded() throws {
        let json = #"{"agents":[{"name":"roof-1","agent":"claude","pane_id":"w1:p1","revision":41}]}"#
        let s = try JSONDecoder().decode(HerdrSnapshot.self, from: Data(json.utf8))
        XCTAssertEqual(s.agents.first?.revision, 41)
    }
}

