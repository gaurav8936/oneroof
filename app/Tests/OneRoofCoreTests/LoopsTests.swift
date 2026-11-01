import XCTest
@testable import OneRoofCore

/// LAB-676: Loops slice 1 — the controller (clock-free), the store, the check and the worktree.
final class LoopsTests: XCTestCase {
    let t0 = Date(timeIntervalSince1970: 1_800_000_000)
    var cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()

    func loop(_ trigger: LoopTrigger = .untilDone(everyMinutes: 0), limits: LoopLimits = LoopLimits()) -> Loop {
        Loop(id: "fix-ci", name: "fix-ci", goal: "main is green", check: "make test", repoPath: "/p/acme/web",
             trigger: trigger, limits: limits, state: .waiting, createdAt: t0)
    }

    func fail(_ r: Int) -> LoopCheckResult { LoopCheckResult(passed: false, exitCode: 1, output: "FAIL test_login (\(r * 13) ms)\nexpected 200 got 500") }
    let pass = LoopCheckResult(passed: true, exitCode: 0, output: "ok")

    /// Drive a loop like the engine does: start, round, check, decide; `results` = check result per check.
    func drive(_ start: Loop, results: [LoopCheckResult], every: TimeInterval = 60) -> (Loop, [LoopRound], [LoopDecision]) {
        var l = LoopController.runNow(start)
        var rounds: [LoopRound] = []
        var decisions: [LoopDecision] = []
        var now = t0
        var checks = results[...]
        for _ in 0..<60 {
            now = now.addingTimeInterval(every)
            let status: LoopRoundStatus = l.run?.active == nil ? .none : .finished
            let d = LoopController.next(l, rounds: rounds, now: now, round: status, calendar: cal)
            decisions.append(d)
            switch d {
            case .runCheck:
                if l.run == nil { l = LoopController.begin(l, now: now, runId: "r1") }
                guard let r = checks.popFirst() else { return (l, rounds, decisions) }
                let (nl, line) = LoopController.checked(l, result: r, now: now)
                l = nl; rounds.append(line)
            case .startRound(let n):
                l = LoopController.started(l, n: n, sessionId: "s\(n)", runtimeId: "roof-\(n)", now: now)
            case .done, .stop:
                let (nl, line) = LoopController.ended(l, rounds: rounds, outcome: d, now: now)
                l = nl; rounds.append(line)
                return (l, rounds, decisions)
            case .wait, .needsYou:
                l = LoopController.settle(l, d)
            }
        }
        return (l, rounds, decisions)
    }

    // MARK: Controller

    func testConverges() {
        let (l, rounds, d) = drive(loop(), results: [fail(1), fail(2).with(output: "other error"), pass])
        XCTAssertEqual(l.state, .done)
        XCTAssertNil(l.run)
        XCTAssertEqual(d.filter { if case .startRound = $0 { return true }; return false }.count, 2)
        XCTAssertEqual(rounds.map(\.kind), [.check, .round, .round, .stop])
        XCTAssertEqual(rounds.last?.checkPassed, true)
        XCTAssertTrue(l.stopReason?.contains("after 2 rounds") == true, l.stopReason ?? "")
    }

    func testAlreadyPassingNeedsNoRound() {
        let (l, rounds, d) = drive(loop(), results: [pass])
        XCTAssertEqual(l.state, .done)
        XCTAssertFalse(d.contains { if case .startRound = $0 { return true }; return false })
        XCTAssertEqual(rounds.first?.note, "already passing: no round needed")
    }

    func testRoundLimit() {
        let distinct = (1...10).map { LoopCheckResult(passed: false, exitCode: 1, output: "error kind \(["a","b","c","d","e","f","g","h","i","j"][$0 - 1])") }
        let (l, rounds, d) = drive(loop(limits: LoopLimits(maxRounds: 3, sameFailureStop: 2)), results: distinct)
        XCTAssertEqual(l.state, .failed)
        XCTAssertEqual(rounds.filter { $0.kind == .round }.count, 3)
        guard case .stop(let why) = d.last else { return XCTFail("\(d)") }
        XCTAssertTrue(why.hasPrefix("Round limit"), why)
        XCTAssertTrue(rounds.last?.note?.contains("Tried: #1") == true)
    }

    func testSameFailureTwiceStops() {
        // Timings differ between runs ("13 ms", "26 ms"); the failure is the same.
        let (l, rounds, d) = drive(loop(), results: [fail(1), fail(2), fail(3), pass])
        XCTAssertEqual(l.state, .failed)
        XCTAssertEqual(rounds.filter { $0.kind == .round }.count, 2)
        guard case .stop(let why) = d.last else { return XCTFail("\(d)") }
        XCTAssertTrue(why.contains("same failure twice"), why)
        XCTAssertTrue(rounds.last?.note?.contains("#2 ✕ same failure") == true, rounds.last?.note ?? "")
    }

    func testTimeLimit() {
        var l = LoopController.begin(loop(limits: LoopLimits(maxDuration: 3600)), now: t0, runId: "r1")
        l = LoopController.started(l, n: 1, sessionId: "s1", runtimeId: "roof-1", now: t0)
        XCTAssertEqual(LoopController.next(l, rounds: [], now: t0.addingTimeInterval(1800), round: .working), .wait)
        guard case .stop(let why) = LoopController.next(l, rounds: [], now: t0.addingTimeInterval(3601), round: .working) else {
            return XCTFail("expected stop")
        }
        XCTAssertTrue(why.hasPrefix("Time limit"))
        let (ended, line) = LoopController.ended(l, rounds: [], outcome: .stop(why), now: t0.addingTimeInterval(3601))
        XCTAssertEqual(ended.state, .failed)
        XCTAssertTrue(line.note?.contains("left running") == true)
    }

    func testNeedsYouWaitsForTheOwner() {
        var l = LoopController.begin(loop(), now: t0, runId: "r1")
        l = LoopController.started(l, n: 1, sessionId: "s1", runtimeId: "roof-1", now: t0)
        let d = LoopController.next(l, rounds: [], now: t0.addingTimeInterval(60), round: .needsYou)
        XCTAssertEqual(d, .needsYou)
        l = LoopController.settle(l, d)
        XCTAssertEqual(l.state, .needsYou)
        // Answered: the agent goes on and finishes; the check runs.
        XCTAssertEqual(LoopController.next(l, rounds: [], now: t0.addingTimeInterval(120), round: .working), .wait)
        XCTAssertEqual(LoopController.settle(l, .wait).state, .running)
        XCTAssertEqual(LoopController.next(l, rounds: [], now: t0.addingTimeInterval(180), round: .finished), .runCheck)
    }

    func testRoundStatusFromHolderInfo() {
        let now = t0
        let quiet = now.addingTimeInterval(-30).timeIntervalSince1970
        XCTAssertEqual(LoopRoundStatus.from(info: nil, now: now), .gone)
        XCTAssertEqual(LoopRoundStatus.from(info: ["exited": 1.0], now: now), .gone)
        XCTAssertEqual(LoopRoundStatus.from(info: ["status": "blocked", "opening": "done"], now: now), .needsYou)
        XCTAssertEqual(LoopRoundStatus.from(info: ["status": "idle", "ready": true, "opening": "pending", "active": quiet], now: now), .working)
        XCTAssertEqual(LoopRoundStatus.from(info: ["status": "done", "ready": true, "opening": "done", "active": quiet], now: now), .finished)
        XCTAssertEqual(LoopRoundStatus.from(info: ["status": "done", "ready": true, "opening": "done", "active": now.timeIntervalSince1970], now: now), .working)
        XCTAssertEqual(LoopRoundStatus.from(info: ["status": "working", "ready": true, "opening": "done", "active": quiet], now: now), .working)
    }

    func testPausedDoesNothingAndResumeGoesOn() {
        var l = LoopController.begin(loop(), now: t0, runId: "r1")
        let rounds = [LoopController.checked(l, result: fail(1), now: t0).1]
        l = LoopController.pause(l)
        XCTAssertEqual(l.state, .paused)
        XCTAssertEqual(LoopController.next(l, rounds: rounds, now: t0.addingTimeInterval(60), round: .none), .wait)
        XCTAssertEqual(LoopController.settle(l, .wait).state, .paused)
        l = LoopController.resume(l)
        XCTAssertEqual(l.state, .waiting)
        XCTAssertEqual(LoopController.next(l, rounds: rounds, now: t0.addingTimeInterval(60), round: .none), .startRound(1))
    }

    func testNotStartedUntilRunNow() {
        var l = loop()
        l.state = .stopped
        XCTAssertEqual(LoopController.next(l, rounds: [], now: t0.addingTimeInterval(3600), round: .none), .wait)
        l = LoopController.runNow(l)
        XCTAssertEqual(l.state, .waiting)
        XCTAssertEqual(LoopController.next(l, rounds: [], now: t0, round: .none), .runCheck)
    }

    func testUntilDoneWaitsItsIntervalUnlessRunNow() {
        var l = LoopController.begin(loop(.untilDone(everyMinutes: 20)), now: t0, runId: "r1")
        let rounds = [LoopController.checked(l, result: fail(1), now: t0).1]
        XCTAssertEqual(LoopController.next(l, rounds: rounds, now: t0.addingTimeInterval(19 * 60), round: .none), .wait)
        XCTAssertEqual(LoopController.next(l, rounds: rounds, now: t0.addingTimeInterval(20 * 60), round: .none), .startRound(1))
        XCTAssertEqual(LoopController.nextStart(l, rounds: rounds, now: t0), t0.addingTimeInterval(20 * 60))
        l.runRequested = true
        XCTAssertEqual(LoopController.next(l, rounds: rounds, now: t0.addingTimeInterval(60), round: .none), .startRound(1))
    }

    func testNightlyTrigger() {
        // t0 = 2027-01-15 08:00 UTC. A loop at 02:00 made the day before runs at 02:00, once.
        var l = loop(.at(hour: 2, minute: 0))
        l.createdAt = t0.addingTimeInterval(-24 * 3600)
        let twoAM = cal.date(bySettingHour: 2, minute: 0, second: 0, of: t0)!
        XCTAssertEqual(LoopController.next(l, rounds: [], now: twoAM.addingTimeInterval(-60), round: .none, calendar: cal), .wait)
        XCTAssertEqual(LoopController.next(l, rounds: [], now: twoAM.addingTimeInterval(30), round: .none, calendar: cal), .runCheck)
        // Asleep at 2:00, awake at 8:00: skipped until the next night.
        XCTAssertEqual(LoopController.next(l, rounds: [], now: twoAM.addingTimeInterval(6 * 3600), round: .none, calendar: cal), .wait)
        // It ran tonight: not again until tomorrow.
        l = LoopController.begin(l, now: twoAM.addingTimeInterval(30), runId: "n1")
        let (ended, _) = LoopController.ended(l, rounds: [], outcome: .done, now: twoAM.addingTimeInterval(90))
        XCTAssertEqual(LoopController.next(ended, rounds: [], now: twoAM.addingTimeInterval(120), round: .none, calendar: cal), .wait)
        XCTAssertEqual(LoopController.next(ended, rounds: [], now: twoAM.addingTimeInterval(24 * 3600 + 30), round: .none, calendar: cal), .runCheck)
        XCTAssertEqual(LoopController.nextStart(ended, rounds: [], now: twoAM.addingTimeInterval(120), calendar: cal), twoAM.addingTimeInterval(24 * 3600))
        // Paused or stopped: never.
        var p = ended; p.state = .paused
        XCTAssertEqual(LoopController.next(p, rounds: [], now: twoAM.addingTimeInterval(24 * 3600 + 30), round: .none, calendar: cal), .wait)
    }

    func testStopByOwner() {
        var l = LoopController.begin(loop(), now: t0, runId: "r1")
        l = LoopController.started(l, n: 1, sessionId: "s1", runtimeId: "roof-1", now: t0)
        let (s, line) = LoopController.ended(l, rounds: [], outcome: .stop("Stopped by you"), now: t0, byOwner: true)
        XCTAssertEqual(s.state, .stopped)
        XCTAssertNil(s.run)
        XCTAssertEqual(line.kind, .stop)
    }

    // MARK: Prompt

    func testRoundPromptCarriesGoalCheckAndLastOutput() {
        var l = LoopController.begin(loop(), now: t0, runId: "r1")
        l.roundPrompt = "Keep the diff small."
        let r1 = LoopController.checked(l, result: fail(1), now: t0).1
        let p = LoopPrompt.render(l, round: 1, rounds: [r1])
        XCTAssertTrue(p.contains("round 1 of at most 8"))
        XCTAssertTrue(p.contains("Goal: main is green"))
        XCTAssertTrue(p.contains("make test"))
        XCTAssertTrue(p.contains("expected 200 got 500"))
        XCTAssertTrue(p.contains("loop/fix-ci"))
        XCTAssertTrue(p.contains("/p/acme/web/.worktrees/loop-fix-ci"))
        XCTAssertTrue(p.contains("Never push, merge or deploy"))
        XCTAssertTrue(p.contains("Keep the diff small."))
        XCTAssertFalse(p.contains("same failure"))
        var l2 = LoopController.started(l, n: 1, sessionId: "s1", runtimeId: "r", now: t0)
        let r2 = LoopController.checked(l2, result: fail(2), now: t0).1
        l2 = LoopController.checked(l2, result: fail(2), now: t0).0
        XCTAssertTrue(LoopPrompt.render(l2, round: 2, rounds: [r1, r2]).contains("same failure as before"))
    }

    // MARK: Check

    func testFailureKeyIgnoresTimingsButNotTheError() {
        XCTAssertEqual(LoopCheck.failureKey(fail(1)), LoopCheck.failureKey(fail(7)))
        XCTAssertNotEqual(LoopCheck.failureKey(fail(1)), LoopCheck.failureKey(fail(1).with(output: "different")))
        XCTAssertTrue(LoopCheck.failureKey(fail(1)).hasPrefix("exit 1 · "))
    }

    func testCheckRunsInTheFolderWithTimeoutAndTail() throws {
        let dir = try tempDir()
        let ok = LoopCheck.run("pwd; echo hello", in: dir, timeout: 30)
        XCTAssertTrue(ok.passed)
        XCTAssertTrue(ok.output.contains("hello"))
        XCTAssertTrue(ok.output.contains((dir as NSString).lastPathComponent))
        let bad = LoopCheck.run("echo nope >&2; exit 3", in: dir, timeout: 30)
        XCTAssertFalse(bad.passed)
        XCTAssertEqual(bad.exitCode, 3)
        XCTAssertTrue(bad.output.contains("nope"))
        let slow = LoopCheck.run("sleep 20", in: dir, timeout: 1)
        XCTAssertTrue(slow.timedOut)
        XCTAssertFalse(slow.passed)
        XCTAssertLessThan(slow.duration, 10)
        XCTAssertFalse(LoopCheck.run("", in: dir).passed)
        XCTAssertEqual(LoopCheck.tail((1...100).map(String.init).joined(separator: "\n"), lines: 3), "98\n99\n100")
    }

    // MARK: Store

    func testStoreRoundTripPinnedFirstAndRounds() throws {
        let store = LoopStore(root: try tempDir())
        var a = loop(); a.id = "b-loop"; a.name = "b-loop"
        var b = loop(); b.id = "a-loop"; b.name = "a-loop"
        var c = loop(.at(hour: 2, minute: 0)); c.id = "z-loop"; c.name = "z-loop"; c.pinned = true
        for x in [a, b, c] { try store.save(x) }
        XCTAssertEqual(store.all().map(\.id), ["z-loop", "a-loop", "b-loop"])
        XCTAssertEqual(store.load("z-loop")?.trigger, .at(hour: 2, minute: 0))
        try store.update("a-loop") { $0 = LoopController.runNow($0) }
        XCTAssertEqual(store.load("a-loop")?.runRequested, true)
        let line = LoopRound(kind: .check, runId: "r1", n: 0, started: t0, ended: t0, checkPassed: false, exitCode: 1, checkOutput: "x")
        try store.append(line, to: "a-loop")
        try store.append(line, to: "a-loop")
        XCTAssertEqual(store.rounds("a-loop").count, 2)
        XCTAssertEqual(store.rounds("a-loop").first, line)
        XCTAssertEqual(store.newId(for: "A loop!"), "a-loop-2")
        // An edit keeps the engine's run state.
        var edited = store.load("a-loop")!
        edited.runRequested = false; edited.goal = "new goal"
        let saved = try store.saveEdit(edited)
        XCTAssertEqual(saved.goal, "new goal")
        XCTAssertEqual(saved.runRequested, true)
        store.delete("a-loop")
        XCTAssertNil(store.load("a-loop"))
        XCTAssertNil(store.load("../etc"))
    }

    func testSlugAndIds() {
        XCTAssertEqual(Loop.slug("Fix CI (web)"), "fix-ci-web")
        XCTAssertEqual(Loop.slug("!!"), "loop")
        XCTAssertTrue(Loop.validId("fix-ci-2"))
        XCTAssertFalse(Loop.validId("../x"))
        XCTAssertFalse(Loop.validId("Fix"))
    }

    // MARK: Worktree

    func testWorktreeIsMadeOnItsOwnBranchAndReused() throws {
        let repo = try tempDir()
        let git = "/usr/bin/git"
        XCTAssertEqual(Foundations.run(git, ["-C", repo, "init", "-q", "-b", "main"]).0, 0)
        _ = Foundations.run(git, ["-C", repo, "-c", "user.email=t@t", "-c", "user.name=t", "commit", "-q", "--allow-empty", "-m", "init"])
        let wt = try LoopWorktree.ensure(repo: repo, id: "fix-ci")
        XCTAssertEqual(wt, repo + "/.worktrees/loop-fix-ci")
        XCTAssertEqual(Foundations.run(git, ["-C", wt, "branch", "--show-current"]).1.trimmingCharacters(in: .whitespacesAndNewlines), "loop/fix-ci")
        XCTAssertEqual(Foundations.run(git, ["-C", repo, "branch", "--show-current"]).1.trimmingCharacters(in: .whitespacesAndNewlines), "main")
        XCTAssertEqual(try LoopWorktree.ensure(repo: repo, id: "fix-ci"), wt)
        // The folder removed by hand: made again from the existing branch.
        try FileManager.default.removeItem(atPath: wt)
        XCTAssertEqual(try LoopWorktree.ensure(repo: repo, id: "fix-ci"), wt)
        XCTAssertThrowsError(try LoopWorktree.ensure(repo: try tempDir(), id: "x"))
    }

    func gitRepo() throws -> String {
        let repo = try tempDir()
        XCTAssertEqual(Foundations.run("/usr/bin/git", ["-C", repo, "init", "-q", "-b", "main"]).0, 0)
        _ = Foundations.run("/usr/bin/git", ["-C", repo, "-c", "user.email=t@t", "-c", "user.name=t", "commit", "-q", "--allow-empty", "-m", "init"])
        return repo
    }

    func currentBranch(_ dir: String) -> String {
        Foundations.run("/usr/bin/git", ["-C", dir, "branch", "--show-current"]).1.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// LAB-677: an id that already starts with "loop-" is not doubled (`loop-loop-smoke`, `loop/loop-smoke`).
    func testWorktreeNameDoesNotDoubleTheLoopPrefix() throws {
        let repo = try gitRepo()
        let wt = try LoopWorktree.ensure(repo: repo, id: "loop-smoke")
        XCTAssertEqual(wt, repo + "/.worktrees/loop-smoke")
        XCTAssertEqual(currentBranch(wt), "loop/smoke")
        let l = Loop(id: "loop-smoke", name: "s", repoPath: repo)
        XCTAssertEqual(l.worktreePath, wt)
        XCTAssertEqual(l.branch, "loop/smoke")
        XCTAssertEqual(LoopWorktree.branch("loop-"), "loop/loop-", "an id that is only the prefix keeps it")
    }

    /// Worktrees and branches made by 0.5.2 under the doubled name keep being used.
    func testAnOldDoubledWorktreeOrBranchIsStillUsed() throws {
        let repo = try gitRepo()
        let old = repo + "/.worktrees/loop-loop-old"
        XCTAssertEqual(Foundations.run("/usr/bin/git", ["-C", repo, "worktree", "add", "-b", "loop/loop-old", old, "HEAD"]).0, 0)
        XCTAssertEqual(try LoopWorktree.ensure(repo: repo, id: "loop-old"), old)
        let l = Loop(id: "loop-old", name: "o", repoPath: repo)
        XCTAssertEqual(l.worktreePath, old)
        XCTAssertEqual(l.branch, "loop/loop-old")
        XCTAssertFalse(FileManager.default.fileExists(atPath: repo + "/.worktrees/loop-old"))
        // The old folder removed by hand, its branch kept: the new folder checks out the old branch (its work stays).
        try FileManager.default.removeItem(atPath: old)
        let wt = try LoopWorktree.ensure(repo: repo, id: "loop-old")
        XCTAssertEqual(wt, repo + "/.worktrees/loop-old")
        XCTAssertEqual(currentBranch(wt), "loop/loop-old")
    }

    /// When git cannot make the worktree, ensure throws with git's words; it never hands back a folder that is not a
    /// checkout.
    func testEnsureThrowsWithGitsOutputWhenTheWorktreeCannotBeMade() throws {
        let repo = try gitRepo()
        let wt = repo + "/.worktrees/loop-blocked"
        try FileManager.default.createDirectory(atPath: wt, withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: wt + "/in-the-way.txt", contents: Data("x".utf8))
        XCTAssertThrowsError(try LoopWorktree.ensure(repo: repo, id: "blocked")) { e in
            let s = "\(e)"
            XCTAssertTrue(s.contains("git worktree add failed"), s)
            XCTAssertTrue(s.contains("already exists"), "git's own words are in the error: \(s)")
        }
    }

    /// The real cause of LAB-677: roofd (a launchd daemon) ignored SIGCHLD, so the kernel reaped every child and every
    /// Process exit code read 0. `rev-parse` "found" a branch that did not exist, the `worktree add` that followed
    /// failed with "invalid reference", that failure read as success, and round 1 started in a missing folder.
    /// With SIGCHLD ignored as roofd did: exit codes are known to be unreadable, the worktree is still made (and
    /// checked to exist), and a check never "passes" on an exit code that cannot be read.
    func testIgnoredSIGCHLDAsInTheDaemonNeverFakesTheWorktreeOrAPass() throws {
        let repo = try gitRepo()
        XCTAssertTrue(Foundations.childExitCodesReadable)
        signal(SIGCHLD, SIG_IGN)
        defer { signal(SIGCHLD, SIG_DFL) }
        XCTAssertEqual(Foundations.run("/bin/sh", ["-c", "exit 3"]).0, 0, "the hazard: a failing child reads as 0")
        XCTAssertFalse(Foundations.childExitCodesReadable)
        let wt = try LoopWorktree.ensure(repo: repo, id: "daemonlike")
        XCTAssertTrue(FileManager.default.fileExists(atPath: wt + "/.git"), "the worktree really exists")
        XCTAssertEqual(currentBranch(wt), "loop/daemonlike")
        let r = LoopCheck.run("exit 0", in: wt, timeout: 10)
        XCTAssertFalse(r.passed)
        XCTAssertEqual(r.exitCode, 125)
        // And a folder made by hand that is not a checkout is never taken for the worktree.
        let fake = repo + "/.worktrees/loop-fake"
        try FileManager.default.createDirectory(atPath: fake + "/sub", withIntermediateDirectories: true)
        XCTAssertThrowsError(try LoopWorktree.ensure(repo: repo, id: "fake"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: fake + "/.git"))
    }

    // MARK: Templates and theme

    func testTemplates() {
        XCTAssertEqual(LoopTemplates.all.count, 2)
        let base = Loop(id: "x", name: "", check: "make test", repoPath: "/p/r")
        let g = LoopTemplates.fixUntilGreen.apply(to: base)
        XCTAssertEqual(g.name, "fix-until-green")
        XCTAssertEqual(g.check, "make test")
        XCTAssertEqual(g.trigger, .untilDone(everyMinutes: 0))
        let n = LoopTemplates.nightlyTidy.apply(to: base)
        XCTAssertEqual(n.trigger, .at(hour: 2, minute: 0))
        XCTAssertFalse(n.check.isEmpty)
    }

    func testLoopStatePillsReadInEveryTheme() {
        for t in ThemeName.panelChoices {
            let k = t.tokens
            for s in LoopState.allCases {
                let p = k.pill(s.pillStatus)
                XCTAssertGreaterThanOrEqual(RGB.contrast(p.text, (p.fill ?? k.surface).over(k.surface)), 4.5, "\(t) loop pill \(s)")
                // Dots carry meaning only for live states (as for sessions); paused / not running are parked, faint
                // by design, and always shown with their labelled pill.
                guard s.pillStatus.isLive || s.pillStatus == .needsYou else { continue }
                for (n, bg) in [("window", k.window), ("surface", k.surface)] {
                    XCTAssertGreaterThanOrEqual(RGB.contrast(k.statusColor(s.pillStatus), bg), 3, "\(t) loop dot \(s)/\(n)")
                }
            }
        }
    }

    func testLoopFileDecodesWithMissingFields() throws {
        let json = #"{"id":"old","repoPath":"/p/r","trigger":{"at":{"hour":3,"minute":30}}}"#
        let l = try LoopStore.decoder.decode(Loop.self, from: Data(json.utf8))
        XCTAssertEqual(l.trigger, .at(hour: 3, minute: 30))
        XCTAssertEqual(l.limits, LoopLimits())
        XCTAssertEqual(l.state, .stopped)
        XCTAssertEqual(l.origin, .mine)
    }

    func testBuiltInAndMineLoopsUnifyInStoreAndPreserveOrigin() throws {
        let dir = try tempDir()
        let builtIns = LoopBuiltIns.load(catalogPath: nil, repoPath: "/p/agentic-engineering")
        XCTAssertEqual(builtIns.count, 8)
        XCTAssertTrue(builtIns.allSatisfy { $0.origin == .builtIn && $0.state == .stopped })

        let store = LoopStore(root: dir, builtIns: builtIns)
        var mine = loop(.at(hour: 3, minute: 0))
        mine.id = "oneroof-nightly-bugs"
        mine.name = "oneroof-nightly-bugs"
        try store.save(mine)

        let all = store.all()
        XCTAssertEqual(all.count, 9)
        XCTAssertEqual(all.first?.id, "oneroof-nightly-bugs", "Mine loops sort ahead of unpinned Built-in loops")
        XCTAssertEqual(all.first?.origin, .mine)

        // Running or pinning a Built-in loop materializes its state on disk while keeping origin == .builtIn.
        XCTAssertFalse(store.hasDiskOverride("docs-drift"))
        try store.update("docs-drift") { $0 = LoopController.runNow($0) }
        XCTAssertTrue(store.hasDiskOverride("docs-drift"))
        let updated = try XCTUnwrap(store.load("docs-drift"))
        XCTAssertEqual(updated.origin, .builtIn)
        XCTAssertEqual(updated.displayTitle, "Docs drift")
        XCTAssertTrue(updated.runRequested)

        // Resetting (deleting override) returns a Built-in loop to its default .stopped state without removing it.
        store.delete("docs-drift")
        XCTAssertFalse(store.hasDiskOverride("docs-drift"))
        let reset = try XCTUnwrap(store.load("docs-drift"))
        XCTAssertEqual(reset.origin, .builtIn)
        XCTAssertEqual(reset.state, .stopped)
        XCTAssertFalse(reset.runRequested)

        // A new user loop cannot collide with a Built-in loop id.
        XCTAssertEqual(store.newId(for: "docs-drift"), "docs-drift-2")
    }

    // MARK: Helpers

    func tempDir() throws -> String {
        let d = (NSTemporaryDirectory() as NSString).appendingPathComponent("loops-" + UUID().uuidString)
        try FileManager.default.createDirectory(atPath: d, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(atPath: d) }
        return (d as NSString).resolvingSymlinksInPath
    }
}

extension LoopCheckResult {
    func with(output: String) -> LoopCheckResult { var r = self; r.output = output; return r }
}

extension LoopsTests {
    func testPauseOnlyWhatCouldStartRounds() {
        var done = loop(); done.state = .done
        XCTAssertEqual(LoopController.pause(done).state, .done, "an until-done loop that is done has nothing to pause")
        var nightly = loop(.at(hour: 2, minute: 0)); nightly.state = .failed
        XCTAssertEqual(LoopController.pause(nightly).state, .paused, "a nightly loop still runs tomorrow: pausable")
        nightly.state = .stopped
        XCTAssertEqual(LoopController.pause(nightly).state, .stopped)
        XCTAssertEqual(LoopController.resume(nightly).state, .waiting)
    }
}

extension LoopsTests {
    /// The Loops screen's ✓ / ✕ glyphs and health bars (statusDone / needsText) on its cards, in every theme. Words on
    /// cards use text / text2 (tested in ThemeV2Tests): needsText on Graphite's surface is 4.0:1, fine for a glyph only.
    func testLoopsScreenGlyphsReadInEveryTheme() {
        for t in ThemeName.panelChoices {
            let k = t.tokens
            let done = k.isDark ? StatusPalette.dot(.done) : k.diffAddText      // ThemeTokens.statusDone in the app
            for (n, bg) in [("surface", k.surface), ("card", k.isDark ? k.surface : k.surface2), ("window", k.window)] {
                XCTAssertGreaterThanOrEqual(RGB.contrast(done, bg), 3, "\(t) ✓ on \(n)")
                XCTAssertGreaterThanOrEqual(RGB.contrast(k.needsText, bg), 3, "\(t) ✕ glyph and bars on \(n)")
                XCTAssertGreaterThanOrEqual(RGB.contrast(k.text3, bg), 3, "\(t) repo label on \(n)")
            }
        }
    }
}

extension LoopsTests {
    /// LAB-1846: oneroof-nightly-bugs failed every night on a check copied out of a terminal box.
    func testPastedCheckIsCleanedOnSaveAndRefusedWhenItCannotRun() throws {
        let pasted = "│ bash scratchpad/loop-checks/oneroof-bugs-check.sh. The script passes only when the build and tests pass."
        XCTAssertEqual(LoopSpecLint.clean("│ \"No Bug in Backlog\""), "No Bug in Backlog")
        XCTAssertEqual(LoopSpecLint.clean("$ npm test"), "npm test")
        XCTAssertEqual(LoopSpecLint.clean("⎿  make test"), "make test")
        XCTAssertEqual(LoopSpecLint.clean("echo \"a\" && echo \"b\""), "echo \"a\" && echo \"b\"", "inner quotes stay")
        XCTAssertNotNil(LoopSpecLint.checkProblem(pasted, folder: nil), "the box edge")
        XCTAssertEqual(LoopSpecLint.checkProblem(LoopSpecLint.clean(pasted), folder: nil),
                       "The check has a sentence after the command. Keep only the command; put the explanation in the goal.")
        XCTAssertNotNil(LoopSpecLint.checkProblem("bash tools/check.sh.", folder: nil), "full stop glued to the script")
        for ok in ["make test", "swift test", "npm test && npm run lint", "pytest -q", "bash tools/check.sh --perf",
                   "test -z \"$(git status --porcelain)\""] {
            XCTAssertNil(LoopSpecLint.checkProblem(ok, folder: nil), ok)
        }

        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("lint-\(UUID().uuidString)").path
        try FileManager.default.createDirectory(atPath: dir + "/tools", withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: dir) }
        XCTAssertNotNil(LoopSpecLint.checkProblem("bash tools/check.sh", folder: dir), "script not there")
        FileManager.default.createFile(atPath: dir + "/tools/check.sh", contents: Data("exit 0\n".utf8))
        XCTAssertNil(LoopSpecLint.checkProblem("bash tools/check.sh", folder: dir))

        let store = LoopStore(root: dir + "/loops", builtIns: [])
        var l = loop(); l.check = "│ make test"; l.goal = "│ \"main is green\""; l.roundPrompt = "\"One bug per round.\""
        try store.save(l)
        let saved = try XCTUnwrap(store.load(l.id))
        XCTAssertEqual([saved.check, saved.goal, saved.roundPrompt], ["make test", "main is green", "One bug per round."])
        var edit = saved; edit.check = "❯ swift test"
        XCTAssertEqual(try store.saveEdit(edit).check, "swift test")
    }
}

/// LAB-2055 · LAB-2056: the Loops page's four family cards, chip order, the Other card and the Off chip.
final class LoopFamiliesTests: XCTestCase {
    func l(_ id: String, kind: String? = nil, origin: LoopOrigin = .builtIn, state: LoopState = .stopped, pinned: Bool = false, title: String? = nil) -> Loop {
        Loop(id: id, name: id, title: title, origin: origin, repoPath: "/p/r", pinned: pinned, state: state).with { $0.kind = kind }
    }

    func test_LAB2055_VIEW_everyKindInExactlyOneOfFourFamilies() {
        XCTAssertEqual(LoopKinds.families.map(\.title), ["Watch", "Check", "Report", "Improve"])
        for k in LoopKinds.all {
            let owners = LoopKinds.families.filter { $0.kinds.contains(k.id) }
            XCTAssertEqual(owners.count, 1, "\(k.id) is in exactly one family")
            XCTAssertEqual(k.family?.id, owners.first?.id)
        }
        XCTAssertEqual(Set(LoopKinds.families.flatMap(\.kinds)), Set(LoopKinds.all.map(\.id)), "no family names an unknown kind")
        XCTAssertEqual(LoopKinds.family(ofKind: "sentinel")?.id, "watch")
        XCTAssertEqual(LoopKinds.family(ofKind: "prober")?.id, "watch")
        XCTAssertEqual(LoopKinds.family(ofKind: "auditor")?.id, "check")
        XCTAssertEqual(LoopKinds.family(ofKind: "judge")?.id, "check")
        XCTAssertEqual(LoopKinds.family(ofKind: "reporter")?.id, "report")
        XCTAssertEqual(LoopKinds.family(ofKind: "researcher")?.id, "report")
        XCTAssertEqual(LoopKinds.family(ofKind: "writer")?.id, "report")
        XCTAssertEqual(LoopKinds.family(ofKind: "fixer")?.id, "improve")
        XCTAssertEqual(LoopKinds.family(ofKind: "refresher")?.id, "improve")
        XCTAssertEqual(LoopKinds.family(ofKind: "learner")?.id, "improve")
        XCTAssertNil(LoopKinds.family(ofKind: nil)); XCTAssertNil(LoopKinds.family(ofKind: "nonsense"))
        XCTAssertEqual(LoopKinds.families[0].kindTitles, "Sentinel · Prober")
        XCTAssertFalse(LoopKinds.families.contains { $0.blurb.isEmpty })
    }

    func test_LAB2055_VIEW_groupsCountAndOtherOnlyWhenNeeded() {
        let loops = [l("cost", kind: "sentinel"), l("probe", kind: "prober"), l("audit", kind: "auditor"), l("fix", kind: "fixer")]
        let g = LoopFamilies.groups(loops)
        XCTAssertEqual(g.map(\.id), ["watch", "check", "report", "improve"], "four cards always; no Other without kind-less loops")
        XCTAssertEqual(g.map { $0.loops.count }, [2, 1, 0, 1])
        let g2 = LoopFamilies.groups(loops + [l("mine", origin: .mine), l("odd", kind: "nonsense")])
        XCTAssertEqual(g2.map(\.id), ["watch", "check", "report", "improve", "other"])
        XCTAssertEqual(g2.last?.loops.map(\.id), ["mine", "odd"], "kind-less and unknown kinds go to Other")
        XCTAssertEqual(g2.reduce(0) { $0 + $1.loops.count }, 6, "every loop is on exactly one card")
    }

    func test_LAB2055_VIEW_chipOrder() {
        let loops = [l("b-built", kind: "sentinel"), l("a-built", kind: "sentinel"), l("mine", kind: "sentinel", origin: .mine),
                     l("pin", kind: "sentinel", pinned: true), l("run", kind: "sentinel", state: .running),
                     l("ask", kind: "sentinel", state: .needsYou)]
        XCTAssertEqual(LoopFamilies.ordered(loops).map(\.id), ["ask", "run", "pin", "mine", "a-built", "b-built"])
    }

    func test_LAB2055_STATE_badgeAndVoiceOver() {
        let g = LoopFamilies.groups([l("a", kind: "sentinel", state: .needsYou), l("b", kind: "prober", state: .running), l("c", kind: "prober")])[0]
        XCTAssertEqual(g.badge, "1 needs you")
        XCTAssertEqual(g.accessibilityLabel, "Watch, 3 loops, 1 needs you")
        let r = LoopFamilies.groups([l("b", kind: "prober", state: .running), l("c", kind: "prober", state: .running)])[0]
        XCTAssertEqual(r.badge, "2 running")
        XCTAssertNil(LoopFamilies.groups([l("c", kind: "prober")])[0].badge)
    }

    func test_LAB2055_VIEW_twoColumnsBalanced() {
        let g = LoopFamilies.groups((0..<9).map { l("w\($0)", kind: "sentinel") } + (0..<8).map { l("c\($0)", kind: "auditor") }
                                    + (0..<6).map { l("r\($0)", kind: "reporter") } + (0..<3).map { l("i\($0)", kind: "fixer") }
                                    + (0..<4).map { l("o\($0)", origin: .mine) })
        let cols = LoopFamilies.columns(g, count: 2)
        XCTAssertEqual(cols.count, 2)
        XCTAssertEqual(cols.flatMap { $0 }.count, 5, "every card placed once")
        XCTAssertEqual(cols[0].first?.id, "watch"); XCTAssertEqual(cols[1].first?.id, "check")
        XCTAssertEqual(LoopFamilies.columns(g, count: 1).first?.map(\.id), ["watch", "check", "report", "improve", "other"])
    }

    func test_LAB2056_STATE_stoppedLoopIsOffAndNeverStruck() {
        let off = l("x")
        XCTAssertEqual(off.state.label, "Off")
        XCTAssertEqual(LoopLook.label(off), "Off")
        for theme in ThemeName.panelChoices {
            for s in LoopState.allCases {
                XCTAssertNotEqual(LoopLook.pill(s, theme: theme).edge, .strike, "\(theme) \(s): no strikethrough on Loops")
            }
        }
        XCTAssertEqual(LoopLook.label(Loop(id: "q", name: "q", repoPath: "/p", trigger: .whenQuiet(quietMinutes: 15, fromHour: nil, toHour: nil), state: .waiting)),
                       "Waiting for quiet")
    }

    func test_LAB2056_ACTION_disabledButtonsSayWhy() {
        let off = l("x")
        XCTAssertEqual(LoopLook.disabledReason("Stop", off), "Nothing is running")
        XCTAssertEqual(LoopLook.disabledReason("Pause", off), "Not running or scheduled")
        XCTAssertNil(LoopLook.disabledReason("Run now", off))
        XCTAssertEqual(LoopLook.disabledReason("Run now", l("r", state: .running)), "Already running")
        XCTAssertEqual(LoopLook.disabledReason("Run now", l("n", state: .needsYou)), "Waiting for you")
        XCTAssertNil(LoopLook.disabledReason("Stop", l("r", state: .running).with { $0.runRequested = true }))
    }
}
