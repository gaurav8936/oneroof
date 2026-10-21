import XCTest
@testable import OneRoofCore

/// `Board.merge` on the runtime's snapshot (moved from CoreTests when herdr went behind `SessionRuntime`, LAB-5).
final class BoardMergeTests: XCTestCase {
    func agent(_ id: String, _ kind: String?, _ status: RuntimeStatus, cwd: String = "/p", pane: String, group: String? = nil,
               title: String? = nil, ready: Bool = false) -> RuntimeSessionState {
        RuntimeSessionState(id: id, isAgent: true, agentName: kind, status: status, ready: ready, title: title, cwd: cwd,
                            pane: pane, groupId: group)
    }

    func shell(_ id: String, pane: String, group: String) -> RuntimeSessionState {
        RuntimeSessionState(id: id, isAgent: false, ready: true, cwd: "/p", pane: pane, groupId: group)
    }

    func testRuntimeStatusMapping() {
        XCTAssertEqual(SessionStatus(.working), .running)
        XCTAssertEqual(SessionStatus(.blocked), .needsYou)
        XCTAssertEqual(SessionStatus(.done), .done)
        XCTAssertEqual(SessionStatus(.idle), .idle)
        XCTAssertEqual(SessionStatus(.unknown), .idle)
        XCTAssertEqual(RuntimeStatus("blocked"), .blocked)
        XCTAssertEqual(RuntimeStatus(nil), .unknown)
        XCTAssertEqual(RuntimeStatus("something new"), .unknown)
    }

    func testMergeStoredLiveExitedAndAdopted() {
        let planned = Session(name: "plan it", repoPath: "/p/a/b", lifecycle: .planned)
        var launched = Session(name: "live one", repoPath: "/p/a/b", lifecycle: .idle)
        launched.runtimeId = "roof-1"
        var gone = Session(name: "gone", repoPath: "/p/a/b", lifecycle: .idle)
        gone.runtimeId = "roof-2"
        var parked = Session(name: "parked", repoPath: "/p/a/b", lifecycle: .doNotUse)
        parked.runtimeId = "roof-3"

        let items = Board.merge(
            stored: [planned, launched, gone, parked],
            snapshot: RuntimeSnapshot(sessions: [
                agent("roof-1", "claude", .working, cwd: "/p/a/b", pane: "w1:p1", group: "w1"),
                agent("roof-3", "claude", .blocked, cwd: "/p/a/b", pane: "w3:p1"),
                agent("stray", "codex", .blocked, cwd: "/p/x/y", pane: "w9:p1", title: "WS-API-21 work"),
            ]),
            accounts: ["roof-1": "Claude2"])

        let by = Dictionary(uniqueKeysWithValues: items.map { ($0.session.name, $0) })
        XCTAssertEqual(by["plan it"]?.status, .planned)
        XCTAssertEqual(by["live one"]?.status, .running)
        XCTAssertEqual(by["live one"]?.account, "Claude2")
        XCTAssertEqual(by["live one"]?.liveAgent, "roof-1")
        XCTAssertEqual(by["live one"]?.paneId, "w1:p1")
        XCTAssertEqual(by["live one"]?.workspaceId, "w1")
        XCTAssertEqual(by["gone"]?.status, .exited)
        XCTAssertEqual(by["parked"]?.status, .doNotUse)
        XCTAssertEqual(by["stray"]?.status, .needsYou)
        XCTAssertEqual(by["stray"]?.adopted, true)
        XCTAssertEqual(by["stray"]?.session.agent, .codex)
        XCTAssertEqual(by["stray"]?.session.repoPath, "/p/x/y")
        XCTAssertEqual(by["stray"]?.session.workstream, "WS-API-21")
        XCTAssertEqual(items.count, 5)
    }

    /// Owner 10-20: right after a launch the pane said "This agent has exited" until the next poll.
    func testJustLaunchedSessionIsStartingNotExited() {
        let now = Date()
        var s = Session(name: "new", repoPath: "/p", lifecycle: .idle)
        s.runtimeId = "roof-9"
        s.launchedAt = now.addingTimeInterval(-2)
        var t = Session(name: "term", agent: .shell, repoPath: "/p", lifecycle: .idle, runtimeId: "roof-10")
        t.launchedAt = now.addingTimeInterval(-1)
        let fresh = Board.merge(stored: [s, t], snapshot: RuntimeSnapshot(), now: now)
        XCTAssertEqual(fresh.map(\.status), [.idle, .idle])
        XCTAssertEqual(fresh.map(\.starting), [true, true])
        let later = Board.merge(stored: [s, t], snapshot: RuntimeSnapshot(), now: now.addingTimeInterval(30))
        XCTAssertEqual(later.map(\.status), [.exited, .exited], "still missing after 10 s: it has exited")
        XCTAssertEqual(later.map(\.starting), [false, false])
    }

    /// Owner 10-20: sessions start at the workspace root, which is not a repo; group by the repo they work in.
    func testRepoComesFromWhereTheAgentWorks() throws {
        let root = Workspace.projectsRoot
        let base = root + "/.oneroof-test-\(UUID().uuidString.prefix(6))"
        let repo = base + "/dom/repo-a"
        try FileManager.default.createDirectory(atPath: repo + "/.git", withIntermediateDirectories: true)
        try FileManager.default.createDirectory(atPath: repo + "/src", withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: base) }
        XCTAssertEqual(Workspace.repoRoot(for: repo + "/src/x.swift"), repo)
        XCTAssertNil(Workspace.repoRoot(for: root))

        var a = Session(name: "a", repoPath: root, lifecycle: .idle); a.runtimeId = "r1"
        var b = Session(name: "b", repoPath: root, lifecycle: .idle); b.runtimeId = "r2"
        var c = Session(name: "c", repoPath: root, lifecycle: .idle); c.runtimeId = "r3"; c.lastRepo = repo
        let items = Board.merge(stored: [a, b, c], snapshot: RuntimeSnapshot(sessions: [
            RuntimeSessionState(id: "r1", isAgent: true, agentName: "claude", status: .idle, cwd: root, pane: "r1",
                                workPath: repo + "/src/x.swift"),
            RuntimeSessionState(id: "r2", isAgent: true, agentName: "codex", status: .idle, cwd: root, pane: "r2"),
        ]))
        let by = Dictionary(uniqueKeysWithValues: items.map { ($0.session.name, $0) })
        XCTAssertEqual(by["a"]?.workRepo, repo)
        XCTAssertNil(by["b"]?.repoPath, "only at the root so far: no repo")
        XCTAssertEqual(by["c"]?.repoPath, repo, "exited, but remembered")
        let groups = Board.group(items, by: .repo)
        XCTAssertEqual(groups.last?.title, Board.noRepo, "the root group goes last")
        XCTAssertEqual(groups.first { $0.title != Board.noRepo }?.items.map(\.session.name), ["a", "c"])
        let dom = repo.dropFirst(root.count + 1).split(separator: "/").first.map(String.init)
        XCTAssertEqual(Board.group(items, by: .domain).first?.title, dom)
    }

    func testUnknownAgentIsAdoptedAsClaude() {
        let items = Board.merge(stored: [], snapshot: RuntimeSnapshot(sessions: [agent("x", "mystery", .idle, pane: "1")]))
        XCTAssertEqual(items.first?.session.agent, .claude)
        XCTAssertEqual(items.first?.adopted, true)
    }

    func testUnnamedAgentShowsItsTitle() {
        let items = Board.merge(stored: [], snapshot: RuntimeSnapshot(sessions: [
            agent("term:term_9", "claude", .done, pane: "w2:p1", title: "fix the build"),
        ]))
        XCTAssertEqual(items.first?.session.name, "fix the build (unnamed)")
        XCTAssertEqual(items.first?.id, "herdr:term:term_9")
    }

    func testGroupingByStatusPutsNeedsYouFirst() {
        let items = Board.merge(
            stored: [Session(name: "q", repoPath: "/p", lifecycle: .next)],
            snapshot: RuntimeSnapshot(sessions: [agent("a", "claude", .idle, pane: "1"), agent("b", "claude", .blocked, pane: "2"),
                                                 agent("c", "claude", .done, pane: "3"), agent("d", "claude", .working, pane: "4")]))
        // LAB-256: Working sits above Ready, the same order as the chips.
        XCTAssertEqual(Board.group(items, by: .status).map(\.title), ["Needs you", "Working", "Ready", "Idle", "Next"])
    }

    func testEveryBuiltInStickerSaysWhatItMeans() {
        // LAB-257: menus show each sticker with a short meaning; custom stickers get a generic one.
        for s in Sticker.catalog { XCTAssertNotEqual(s.meaning, "your own sticker", s.id) }
        XCTAssertEqual(Sticker.resolve("deploy-day").meaning, "your own sticker")
    }

    func testPlainTerminalRowIsLiveWhileItsShellExists() {
        let s = Session(name: "Terminal 1", agent: .shell, repoPath: "/p", lifecycle: .idle, runtimeId: "term:term_1")
        let live = Board.merge(stored: [s], snapshot: RuntimeSnapshot(sessions: [shell("term:term_1", pane: "w1:p1", group: "w1")]))
        XCTAssertEqual(live.first?.status, .idle)
        XCTAssertEqual(live.first?.liveAgent, "term:term_1")
        XCTAssertEqual(live.first?.paneId, "w1:p1")
        XCTAssertEqual(live.first?.ready, true)
        let gone = Board.merge(stored: [s], snapshot: RuntimeSnapshot())
        XCTAssertEqual(gone.first?.status, .exited)
        XCTAssertNil(gone.first?.liveAgent)
    }

    /// Owner 10-18: typing `claude` in a One Roof terminal shows the row as Claude, with no second "unnamed" row.
    func testAgentStartedInsideTerminalShowsAsThatAgent() {
        let s = Session(name: "Terminal 6", agent: .shell, repoPath: "/p", lifecycle: .idle, runtimeId: "term:term_6")
        let items = Board.merge(stored: [s], snapshot: RuntimeSnapshot(sessions: [
            agent("term:term_6", "claude", .working, pane: "w1:p1", group: "w1"),
        ]))
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items.first?.session.agent, .claude)
        XCTAssertEqual(items.first?.status, .running)
        XCTAssertEqual(items.first?.liveAgent, "term:term_6")
        XCTAssertTrue(items.first?.agentInTerminal ?? false)
        XCTAssertEqual(items.first?.id, s.id)
    }

    /// LAB-15: rows saved before the rename (JSON keys herdrAgent / herdrWorkspace) load into runtimeId / runtimeGroup,
    /// and save under the same keys.
    func testRenamedFieldsKeepTheirStoredKeys() throws {
        let json = #"{"id":"x","name":"n","agent":"claude","repoPath":"/p","lifecycle":"idle","herdrAgent":"roof-1","herdrWorkspace":"w7"}"#
        let s = try JSONDecoder().decode(Session.self, from: Data(json.utf8))
        XCTAssertEqual(s.runtimeId, "roof-1")
        XCTAssertEqual(s.runtimeGroup, "w7")
        let out = String(decoding: try JSONEncoder().encode(s), as: UTF8.self)
        XCTAssertTrue(out.contains("\"herdrAgent\":\"roof-1\""))
        XCTAssertTrue(out.contains("\"herdrWorkspace\":\"w7\""))
    }
}
