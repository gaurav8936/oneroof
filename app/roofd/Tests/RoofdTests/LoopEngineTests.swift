import Darwin
import OneRoofCore
import XCTest
@testable import roofd

/// LAB-677: the loop engine against a real daemon in a temp folder, with a plain-shell "agent" (no model needed):
/// the check before round 1, the round's session in the loop's own worktree, the probe, and the round line.
final class LoopEngineTests: XCTestCase {
    var dir = ""
    var projects = ""
    var daemon: Process?
    var rootBefore = ""

    var roofd: String { Bundle(for: Self.self).bundleURL.deletingLastPathComponent().appendingPathComponent("roofd").path }

    override func setUpWithError() throws {
        dir = "/tmp/roofd-loop-\(UUID().uuidString.prefix(6))"
        projects = "/tmp/roofd-loopp-\(UUID().uuidString.prefix(6))"
        for d in [dir, projects + "/_common", projects + "/acme/web"] {
            try FileManager.default.createDirectory(atPath: d, withIntermediateDirectories: true)
        }
        setenv("ROOFD_DIR", dir, 1)
        let p = Process()
        p.executableURL = URL(fileURLWithPath: roofd)
        p.arguments = ["daemon"]
        p.environment = ProcessInfo.processInfo.environment.merging(["ROOFD_DIR": dir, "ROOFD_LINGER": "1"]) { $1 }
        try p.run()
        daemon = p
        for _ in 0..<50 where (try? Sock.request(Paths.control, ["method": "hello"], timeout: 1)) == nil { usleep(50_000) }
        rootBefore = Workspace.projectsRoot
        Workspace.configure(root: projects, shared: projects + "/_common")
        LoopEngine.roofdPath = roofd
        let repo = projects + "/acme/web"
        XCTAssertEqual(Foundations.run("/usr/bin/git", ["-C", repo, "init", "-q", "-b", "main"]).0, 0)
        _ = Foundations.run("/usr/bin/git", ["-C", repo, "-c", "user.email=t@t", "-c", "user.name=t", "commit", "-q", "--allow-empty", "-m", "init"])
    }

    override func tearDown() {
        Workspace.configure(root: rootBefore)
        LoopEngine.roofdPath = nil
        if let ids = try? Sock.request(Paths.control, ["method": "list"])["sessions"] as? [[String: Any]] {
            for s in ids { _ = try? Sock.request(Paths.control, ["method": "close", "params": ["id": s["id"] as? String ?? ""]]) }
        }
        daemon?.terminate()
        try? FileManager.default.removeItem(atPath: dir)
        try? FileManager.default.removeItem(atPath: projects)
    }

    func testAPassingCheckEndsTheRunWithoutARound() throws {
        let store = LoopStore()
        var l = Loop(id: "green", name: "green", goal: "g", check: "true", repoPath: projects + "/acme/web", agent: .shell)
        l = LoopController.runNow(l)
        try store.save(l)
        LoopEngine.step("green", store: store, sessions: nil, again: true)
        let after = try XCTUnwrap(store.load("green"))
        XCTAssertEqual(after.state, .done)
        XCTAssertEqual(store.rounds("green").map(\.kind), [.check, .stop])
        XCTAssertTrue(FileManager.default.fileExists(atPath: projects + "/acme/web/.worktrees/loop-green/.git"))
        // The live checkout is untouched: still on main.
        XCTAssertEqual(Foundations.run("/usr/bin/git", ["-C", projects + "/acme/web", "branch", "--show-current"]).1
            .trimmingCharacters(in: .whitespacesAndNewlines), "main")
    }

    func testAFailingCheckStartsARoundInTheWorktreeAndRecordsIt() throws {
        let store = LoopStore()
        let sessions = try SessionStore(path: dir + "/sessions.sqlite")
        // Passes once the round has written the file (the check runs in the worktree).
        var l = Loop(id: "red", name: "red", goal: "make done.txt", check: "test -f done.txt", repoPath: projects + "/acme/web", agent: .shell)
        l = LoopController.runNow(l)
        try store.save(l)
        LoopEngine.step("red", store: store, sessions: sessions, again: true)
        var cur = try XCTUnwrap(store.load("red"))
        XCTAssertEqual(cur.state, .running)
        let active = try XCTUnwrap(cur.run?.active)
        XCTAssertEqual(active.n, 1)
        let row = try XCTUnwrap(sessions.all().first { $0.id == active.sessionId })
        XCTAssertEqual(row.repoPath, projects + "/acme/web/.worktrees/loop-red")
        XCTAssertEqual(row.tags, ["loop:red"])
        XCTAssertEqual(row.runtimeId, active.runtimeId)
        XCTAssertEqual(LoopEngine.probe(active.runtimeId, now: Date()), .working)
        // The "agent" does the work, then the session ends: the check runs and passes.
        FileManager.default.createFile(atPath: projects + "/acme/web/.worktrees/loop-red/done.txt", contents: Data())
        _ = try Sock.request(Paths.control, ["method": "close", "params": ["id": active.runtimeId]])
        for _ in 0..<50 where LoopEngine.probe(active.runtimeId, now: Date()) != .gone { usleep(100_000) }
        LoopEngine.step("red", store: store, sessions: sessions, again: true)
        cur = try XCTUnwrap(store.load("red"))
        XCTAssertEqual(cur.state, .done)
        let kinds = store.rounds("red").map(\.kind)
        XCTAssertEqual(kinds, [.check, .round, .stop])
        XCTAssertEqual(store.rounds("red")[1].checkPassed, true)
        XCTAssertFalse(FileManager.default.fileExists(atPath: projects + "/acme/web/done.txt"), "never the live checkout")
    }

    func testAnUnconfiguredDaemonRunsNoLoops() {
        LoopEngine.tick(config: nil)   // returns at once; nothing to assert beyond not touching the shared folder
        XCTAssertFalse(FileManager.default.fileExists(atPath: projects + "/_common/loops"))
    }
}
