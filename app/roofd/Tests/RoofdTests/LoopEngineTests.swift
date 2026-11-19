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

    /// LAB-1865 · LAB-1369: a fired event starts a loop that listens for it, once; a quiet loop waits while busy.
    func testAnEventStartsItsLoopOnceAndQuietWaitsForQuiet() throws {
        let store = LoopStore()
        let ev = Loop(id: "on-push", name: "on-push", goal: "g", check: "true", repoPath: projects + "/acme/web", agent: .shell,
                      trigger: .onEvent("git.push"), state: .waiting, createdAt: Date().addingTimeInterval(-60))
        let quiet = Loop(id: "quiet", name: "quiet", goal: "g", check: "true", repoPath: projects + "/acme/web", agent: .shell,
                         trigger: .whenQuiet(quietMinutes: 15, fromHour: nil, toHour: nil), state: .waiting, createdAt: Date().addingTimeInterval(-60))
        try store.save(ev); try store.save(quiet)
        var ctx = LoopEngine.context(store: store, ids: ["on-push", "quiet"], sessions: nil, now: Date())
        XCTAssertTrue(ctx.events.isEmpty)
        XCTAssertNotNil(ctx.quietFor)                       // no session at all: quiet since roofd started
        ctx.quietFor = 60                                   // one minute: not yet
        LoopEngine.step("on-push", store: store, sessions: nil, again: true, context: ctx)
        LoopEngine.step("quiet", store: store, sessions: nil, again: true, context: ctx)
        XCTAssertEqual(store.rounds("on-push").count, 0)
        XCTAssertEqual(store.rounds("quiet").count, 0)
        try LoopEvents.fire("git.push", root: store.root)
        ctx = LoopEngine.context(store: store, ids: ["on-push", "quiet"], sessions: nil, now: Date())
        XCTAssertEqual(ctx.events.map(\.event), ["git.push"])
        ctx.quietFor = 16 * 60
        LoopEngine.step("on-push", store: store, sessions: nil, again: true, context: ctx)
        LoopEngine.step("quiet", store: store, sessions: nil, again: true, context: ctx)
        XCTAssertEqual(store.load("on-push")?.state, .done)
        XCTAssertEqual(store.load("quiet")?.state, .done)
        XCTAssertEqual(store.rounds("on-push").map(\.kind), [.check, .stop])
        // The same event does not start it again; nor does quiet the same day.
        LoopEngine.step("on-push", store: store, sessions: nil, again: true, context: ctx)
        LoopEngine.step("quiet", store: store, sessions: nil, again: true, context: ctx)
        XCTAssertEqual(store.rounds("on-push").count, 2)
        XCTAssertEqual(store.rounds("quiet").count, 2)
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
        // LAB-1917: the ended run is in the outcome ledger next to the loops (engine roofd).
        let ledger = try LoopLedger(path: LoopLedger.defaultPath(loopsRoot: store.root))
        XCTAssertEqual(ledger.summary().first(where: { $0.loop == "green" })?.lastResult, "done")
        XCTAssertEqual(ledger.summary().first(where: { $0.loop == "green" })?.engine, "roofd")
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

    /// LAB-677 as it happened: the loop run by the daemon itself (its first scheduler tick), not by this test process.
    /// In 0.5.2 the daemon ignored SIGCHLD, so git's exit codes all read 0: the worktree was never made, the first
    /// check said "Folder not found" and round 1 started in a folder that did not exist. Here the check must run in
    /// the worktree (its real exit code 3 recorded) and the round must start inside it.
    func testTheDaemonMakesTheWorktreeBeforeTheFirstCheckAndRound() throws {
        // A daemon configured as the app configures it, with a loop waiting to run.
        daemon?.terminate()
        daemon?.waitUntilExit()
        let repo = projects + "/acme/web"
        let storePath = dir + "/sessions.sqlite"
        _ = try SessionStore(path: storePath)
        try Scheduler.save(Scheduler.Config(enabled: false, store: storePath, projects: projects, shared: projects + "/_common"))
        let store = LoopStore()
        var l = Loop(id: "loop-ci", name: "ci", goal: "g", check: "test -e .git || exit 9; exit 3", repoPath: repo, agent: .shell)
        l.limits = LoopLimits(maxRounds: 1)
        l = LoopController.runNow(l)
        try store.save(l)
        let p = Process()
        p.executableURL = URL(fileURLWithPath: roofd)
        p.arguments = ["daemon"]
        p.environment = ProcessInfo.processInfo.environment.merging(["ROOFD_DIR": dir, "ROOFD_LINGER": "1"]) { $1 }
        try p.run()
        daemon = p
        var cur = l
        for _ in 0..<150 {
            usleep(100_000)
            cur = store.load("loop-ci") ?? cur
            if cur.run?.active != nil || !cur.state.isActive { break }
        }
        let rounds = store.rounds("loop-ci")
        let check = try XCTUnwrap(rounds.first { $0.kind == .check }, "the daemon ran the first check")
        XCTAssertEqual(check.exitCode, 3, "the check ran in the worktree and its real exit code was read: \(check.checkOutput)")
        XCTAssertFalse(check.checkOutput.contains("Folder not found"))
        let wt = repo + "/.worktrees/loop-ci"
        XCTAssertTrue(FileManager.default.fileExists(atPath: wt + "/.git"), "made by roofd, before the check")
        XCTAssertEqual(Foundations.run("/usr/bin/git", ["-C", wt, "branch", "--show-current"]).1
            .trimmingCharacters(in: .whitespacesAndNewlines), "loop/ci")
        XCTAssertEqual(Foundations.run("/usr/bin/git", ["-C", repo, "branch", "--show-current"]).1
            .trimmingCharacters(in: .whitespacesAndNewlines), "main")
        let active = try XCTUnwrap(cur.run?.active, "round 1 started: \(cur.stopReason ?? "")")
        let row = try XCTUnwrap(try SessionStore(path: storePath).all().first { $0.id == active.sessionId })
        XCTAssertEqual(row.repoPath, wt)
    }

    /// LAB-2310: start round 1 of a loop whose check fails, then record the round as checked (as the engine does once
    /// the agent is back at its prompt) while its session is still alive at that prompt.
    func startAndCheckRound(_ id: String, passed: Bool, store: LoopStore, sessions: SessionStore) throws -> String {
        var l = Loop(id: id, name: id, goal: "g", check: "false", repoPath: projects + "/acme/web", agent: .shell)
        l.limits = LoopLimits(maxRounds: 1)
        l = LoopController.runNow(l)
        try store.save(l)
        LoopEngine.step(id, store: store, sessions: sessions, again: true)
        let active = try XCTUnwrap(store.load(id)?.run?.active, "round 1 started")
        XCTAssertEqual(LoopEngine.probe(active.runtimeId, now: Date()), .working)
        var line: LoopRound?
        _ = try store.update(id) { cur in
            let (next, ln) = LoopController.checked(cur, result: LoopCheckResult(passed: passed, exitCode: passed ? 0 : 1, output: "x"), now: Date())
            cur = next; line = ln
        }
        try store.append(XCTUnwrap(line), to: id)
        return active.runtimeId
    }

    func waitGone(_ runtimeId: String) -> Bool {
        for _ in 0..<50 where LoopEngine.probe(runtimeId, now: Date()) != .gone { usleep(100_000) }
        return LoopEngine.probe(runtimeId, now: Date()) == .gone
    }

    /// LAB-2310: a run that ends done closes its last round's session (it used to sit at its prompt for days).
    func testARunThatEndsDoneClosesItsLastRound() throws {
        let store = LoopStore()
        let sessions = try SessionStore(path: dir + "/sessions.sqlite")
        let rid = try startAndCheckRound("ends-done", passed: true, store: store, sessions: sessions)
        LoopEngine.step("ends-done", store: store, sessions: sessions, again: true)
        XCTAssertEqual(store.load("ends-done")?.state, .done)
        XCTAssertTrue(waitGone(rid), "the last round's session was closed")
    }

    /// LAB-2310: a run that stops on a limit closes its last round's session too.
    func testARunThatStopsClosesItsLastRound() throws {
        let store = LoopStore()
        let sessions = try SessionStore(path: dir + "/sessions.sqlite")
        let rid = try startAndCheckRound("ends-stop", passed: false, store: store, sessions: sessions)
        LoopEngine.step("ends-stop", store: store, sessions: sessions, again: true)
        XCTAssertEqual(store.load("ends-stop")?.state, .failed)
        XCTAssertEqual(store.rounds("ends-stop").map(\.kind), [.check, .round, .stop])
        XCTAssertTrue(waitGone(rid), "the last round's session was closed")
    }

    /// LAB-2310: with One Roof closed, roofd's own pass closes a loop round left idle at its prompt for
    /// idleRoundClose, and leaves one that is newer, and the round a loop still waits on.
    func testTheSweepClosesALoopRoundIdleForHours() throws {
        let store = LoopStore()
        let sessions = try SessionStore(path: dir + "/sessions.sqlite")
        let rid = try startAndCheckRound("left-open", passed: false, store: store, sessions: sessions)
        // A round the engine still owns (in flight) is never swept.
        var other = Loop(id: "in-flight", name: "in-flight", goal: "g", check: "false", repoPath: projects + "/acme/web", agent: .shell)
        other = LoopController.runNow(other)
        try store.save(other)
        LoopEngine.step("in-flight", store: store, sessions: sessions, again: true)
        let owned = try XCTUnwrap(store.load("in-flight")?.run?.active?.runtimeId)
        // Wait until the shell is at its prompt.
        for _ in 0..<50 where !LoopEngine.idleAtPrompt((try? Sock.holderRequest(Paths.session(rid), ["op": "info"], timeout: 1)) ?? [:],
                                                         now: Date(), after: 0) { usleep(100_000) }
        let ids = ["left-open", "in-flight"]
        LoopEngine.sweepIdleRounds(store: store, ids: ids, sessions: sessions, now: Date().addingTimeInterval(60))
        XCTAssertNotEqual(LoopEngine.probe(rid, now: Date()), .gone, "a minute idle: kept")
        LoopEngine.sweepIdleRounds(store: store, ids: ids, sessions: sessions, now: Date().addingTimeInterval(LoopEngine.idleRoundClose + 60))
        XCTAssertTrue(waitGone(rid), "idle past idleRoundClose: closed")
        XCTAssertNotEqual(LoopEngine.probe(owned, now: Date()), .gone, "the round a loop waits on is the engine's")
    }

    /// LAB-2310: what counts as idle at the prompt for the sweep; a round that asks something, or that you watch, stays.
    func testIdleAtPromptKeepsRoundsThatNeedYou() {
        let now = Date()
        let old = now.addingTimeInterval(-3 * 3600).timeIntervalSince1970
        let idle: [String: Any] = ["status": "idle", "opening": "done", "attached": false, "active": old]
        XCTAssertTrue(LoopEngine.idleAtPrompt(idle, now: now, after: LoopEngine.idleRoundClose))
        XCTAssertFalse(LoopEngine.idleAtPrompt(idle, now: now, after: 4 * 3600), "not idle long enough")
        XCTAssertFalse(LoopEngine.idleAtPrompt(idle.merging(["status": "blocked"]) { $1 }, now: now, after: 0), "asks something")
        XCTAssertFalse(LoopEngine.idleAtPrompt(idle.merging(["status": "working"]) { $1 }, now: now, after: 0))
        XCTAssertFalse(LoopEngine.idleAtPrompt(idle.merging(["opening": "failed"]) { $1 }, now: now, after: 0))
        XCTAssertFalse(LoopEngine.idleAtPrompt(idle.merging(["attached": true]) { $1 }, now: now, after: 0), "you are looking at it")
        XCTAssertFalse(LoopEngine.idleAtPrompt(idle.merging(["exited": 0]) { $1 }, now: now, after: 0))
    }

    func testAnUnconfiguredDaemonRunsNoLoops() {
        LoopEngine.tick(config: nil)   // returns at once; nothing to assert beyond not touching the shared folder
        XCTAssertFalse(FileManager.default.fileExists(atPath: projects + "/_common/loops"))
    }
}
