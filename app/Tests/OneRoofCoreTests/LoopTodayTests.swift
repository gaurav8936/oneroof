import XCTest
@testable import OneRoofCore

/// LAB-1919 · LAB-1941 · LAB-1866 · LAB-1867 · LAB-1369 · LAB-1865 · LAB-1843 · LAB-1921 · LAB-1922: the morning
/// approval view's data, decisions in the ledger, loop items in Needs you, harvest to a PR (fake gh, fake judge, a
/// local bare remote), the quiet and event triggers, `.loop.yaml` loops in the store, and the plain-words drafter.
final class LoopTodayTests: XCTestCase {
    var dir: String!
    var cal: Calendar = { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; return c }()

    override func setUp() {
        dir = NSTemporaryDirectory() + "loop-today-\(UUID().uuidString.prefix(8))"
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
    }
    override func tearDown() { try? FileManager.default.removeItem(atPath: dir) }

    func ledger() throws -> LoopLedger { try LoopLedger(path: dir + "/ledger.sqlite") }

    // MARK: Ledger decisions (LAB-1941)

    func test_decide_recordsStatusByAndReason_sameRowTheKitReads() throws {
        let l = try ledger()
        try l.recordRun(loop: "oneroof-nightly-bugs", runId: "r1", started: Date(), ended: Date(), result: "done", summary: "ok")
        try l.addOutcome(loop: "oneroof-nightly-bugs", runId: "r1", kind: "commit", title: "fix toolbar", link: "commit:abc1234@loop/oneroof-nightly-bugs")
        let o = try XCTUnwrap(l.outcomes(status: "staged").first)
        XCTAssertEqual(o.target, .commit(sha: "abc1234", branch: "loop/oneroof-nightly-bugs"))
        let d = try l.decide(o.id, status: "rejected", by: "owner", reason: "not this way")
        XCTAssertEqual(d.status, "rejected"); XCTAssertEqual(d.decidedBy, "owner"); XCTAssertNotNil(d.decidedAt)
        XCTAssertEqual(d.detailValue("reason"), "not this way")
        XCTAssertTrue(l.outcomes(status: "staged").isEmpty)
        XCTAssertThrowsError(try l.decide(o.id, status: "staged"))
        XCTAssertThrowsError(try l.decide(9999, status: "approved"))
        XCTAssertEqual(l.runs(loop: "oneroof-nightly-bugs").first?.result, "done")
    }

    func test_decision_visibleToKitLedgerJson() throws {
        // The kit reads the same file (`ae loops ledger --json`): the decision is in the row it selects.
        let l = try ledger()
        try l.addOutcome(loop: "x", runId: "r", kind: "proposal", title: "a rule", link: "")
        let id = try XCTUnwrap(l.outcomes().first?.id)
        try l.decide(id, status: "approved", by: "owner")
        let (rc, out) = Foundations.run("/usr/bin/sqlite3", [dir + "/ledger.sqlite", "SELECT status, decided_by FROM outcomes WHERE id=\(id)"])
        XCTAssertEqual(rc, 0); XCTAssertEqual(out.trimmingCharacters(in: .whitespacesAndNewlines), "approved|owner")
    }

    // MARK: Today + Needs you items (LAB-1919 · LAB-1866)

    func outcome(_ id: Int, loop: String, run: String, kind: String, created: String, title: String = "t") -> LoopLedger.Outcome {
        LoopLedger.Outcome(id: id, runId: run, loop: loop, kind: kind, link: "", title: title, status: "staged", decidedBy: nil,
                           decidedAt: nil, created: created, detail: "{}")
    }

    func test_today_oldestFirst_groupedByLoop_commitsOfOneRunAreOneItem() {
        let os = [
            outcome(1, loop: "a", run: "r1", kind: "commit", created: "2026-10-31T03:10:00Z", title: "c1"),
            outcome(2, loop: "b", run: "r9", kind: "issue", created: "2026-10-31T03:20:00Z"),
            outcome(3, loop: "a", run: "r1", kind: "commit", created: "2026-10-31T03:30:00Z", title: "c2"),
            outcome(4, loop: "a", run: "r2", kind: "proposal", created: "2026-10-31T04:00:00Z"),
            outcome(5, loop: "b", run: "r9", kind: "report", created: "2026-10-31T02:00:00Z"),
        ]
        let items = LoopInbox.today(os, titles: ["a": "Nightly bugs"])
        XCTAssertEqual(items.map(\.loopId), ["b", "b", "a", "a"])
        XCTAssertEqual(items[2].outcomeIds, [1, 3])
        XCTAssertEqual(items[2].headline, "2 commits on the loop branch, ready to become a PR")
        XCTAssertEqual(items[2].loopTitle, "Nightly bugs")
        XCTAssertEqual(LoopInbox.actions(for: items[2]), [.approvePR, .open, .dismiss])
        XCTAssertEqual(LoopInbox.actions(for: items[0]), [.open, .dismiss])          // the report
        XCTAssertEqual(LoopInbox.actions(for: items[3]), [.approve, .open, .dismiss]) // the proposal
    }

    func test_needs_failedUntilSeen_asksWithItsSession_notCountedAsSessions() {
        var failed = Loop(id: "nightly", name: "nightly", repoPath: "/p", state: .failed, createdAt: Date(timeIntervalSince1970: 0))
        failed.lastRunAt = Date(timeIntervalSince1970: 100); failed.stopReason = "The same failure twice"
        var asks = Loop(id: "fix", name: "fix", repoPath: "/p", state: .needsYou)
        asks.run = LoopRun(id: "r", started: Date(timeIntervalSince1970: 50), active: LoopActiveRound(n: 2, sessionId: "s2", runtimeId: "roof-2", started: Date(timeIntervalSince1970: 60)))
        let quiet = Loop(id: "ok", name: "ok", repoPath: "/p", state: .done)
        var items = LoopInbox.needs([failed, asks, quiet])
        XCTAssertEqual(items.map(\.kind), [.asks, .failed])
        XCTAssertEqual(items[0].sessionId, "s2")
        XCTAssertEqual(items[1].detail, "The same failure twice")
        failed.failureSeenAt = Date(timeIntervalSince1970: 200)                    // marked seen
        items = LoopInbox.needs([failed, asks])
        XCTAssertEqual(items.map(\.kind), [.asks])
        failed.lastRunAt = Date(timeIntervalSince1970: 300)                        // failed again later
        XCTAssertTrue(failed.failureUnseen)
        // The shared badge: loop items add to it; a loop's round session never counts as a session.
        XCTAssertEqual(SessionScope.needsYouCount(openAsks: 1, plansWaiting: 0, items: [], loopItems: 3), 4)
        XCTAssertEqual(SessionScope.needsYouCount(openAsks: 0, plansWaiting: 0, items: []), 0)
    }

    // MARK: Harvest (LAB-1867): fake gh, fake judge, local bare remote; never a real PR

    func sh(_ cmd: String, in folder: String? = nil) -> (Int32, String) {
        Foundations.run("/bin/zsh", ["-c", cmd], cwd: folder ?? dir, timeout: 60)
    }

    /// A repo with a bare origin (develop + main), a loop branch with one commit, and its worktree.
    func harvestRepo(check: String = "test -f fix.txt") throws -> Loop {
        let repo = dir + "/repo", origin = dir + "/origin.git"
        XCTAssertEqual(sh("git init -q --bare \(origin) && git init -q -b main \(repo) && cd \(repo) && git config user.email t@t && git config user.name t && echo a > a.txt && git add . && git commit -qm init && git remote add origin \(origin) && git push -q origin main && git branch develop && git push -q origin develop && git fetch -q origin").0, 0)
        let l = Loop(id: "nightly-bugs", name: "nightly-bugs", goal: "fix.txt exists", check: check, repoPath: repo)
        let wt = try LoopWorktree.ensure(repo: repo, id: l.id)
        XCTAssertEqual(sh("git config user.email t@t && git config user.name t && echo fixed > fix.txt && git add . && git commit -qm 'fix the bug'", in: wt).0, 0)
        return l
    }

    func script(_ name: String, _ body: String) -> String {
        let p = dir + "/" + name
        FileManager.default.createFile(atPath: p, contents: Data(("#!/bin/zsh\n" + body + "\n").utf8))
        chmod(p, 0o755)
        return p
    }

    func test_harvest_gatePasses_pushesWithApprovalKey_opensPRWithFakeGh_recordsInLedger() throws {
        let l = try harvestRepo()
        let ghLog = dir + "/gh.log"
        let gh = script("gh", "print -r -- \"$@\" > \(ghLog); print -r -- \"AE=$AE_LOOP_PUSH_APPROVED\" >> \(ghLog); echo https://github.com/x/y/pull/7")
        let judge = script("judge", "print PASS\nprint 'small, on goal'")
        let led = try ledger()
        try led.addOutcome(loop: l.id, runId: "r1", kind: "commit", title: "fix the bug", link: "commit:abc@loop/nightly-bugs")
        let os = led.outcomes(status: "staged")
        let r = LoopHarvest.approveAndOpen(loop: l, outcomes: os, ledger: led, tools: .init(gh: gh, judge: [judge]), by: "owner")
        guard case .opened(let url, let gate) = r else { return XCTFail("\(r)") }
        XCTAssertEqual(url, "https://github.com/x/y/pull/7")
        XCTAssertTrue(gate.testsPassed); XCTAssertTrue(gate.judgePassed); XCTAssertEqual(gate.judgeReason, "small, on goal")
        let log = try String(contentsOfFile: ghLog, encoding: .utf8)
        XCTAssertTrue(log.contains("pr create --head loop/nightly-bugs --base develop"), log)
        XCTAssertTrue(log.contains("AE=\(os[0].id)"), log)
        // The branch reached the (local) remote.
        XCTAssertEqual(sh("git --git-dir=\(dir!)/origin.git rev-parse --verify -q refs/heads/loop/nightly-bugs").0, 0)
        let after = led.outcomes(loop: l.id)
        XCTAssertEqual(after.first { $0.kind == "commit" }?.status, "approved")
        XCTAssertEqual(after.first { $0.kind == "commit" }?.detailValue("pr"), url)
        let pr = try XCTUnwrap(after.first { $0.kind == "pr" })
        XCTAssertEqual(pr.status, "applied"); XCTAssertEqual(pr.link, url)
    }

    func test_harvest_judgeSaysNo_noPushNoPR_backToStagedWithReason() throws {
        let l = try harvestRepo()
        let gh = script("gh", "touch \(dir!)/gh-ran; echo https://x")
        let judge = script("judge", "print 'FAIL: deletes a test'")
        let led = try ledger()
        try led.addOutcome(loop: l.id, runId: "r1", kind: "commit", title: "fix", link: "")
        let r = LoopHarvest.approveAndOpen(loop: l, outcomes: led.outcomes(status: "staged"), ledger: led, tools: .init(gh: gh, judge: [judge]))
        guard case .refused(let why, _) = r else { return XCTFail("\(r)") }
        XCTAssertTrue(why.contains("deletes a test"), why)
        XCTAssertFalse(FileManager.default.fileExists(atPath: dir + "/gh-ran"))
        XCTAssertNotEqual(sh("git --git-dir=\(dir!)/origin.git rev-parse --verify -q refs/heads/loop/nightly-bugs").0, 0)
        let o = try XCTUnwrap(led.outcomes(loop: l.id).first)
        XCTAssertEqual(o.status, "staged")
        XCTAssertTrue(o.detailValue("gate")?.contains("judge ✕") == true)
    }

    func test_harvest_failingTests_or_noJudge_refuses() throws {
        let l = try harvestRepo(check: "test -f missing.txt")
        let gh = script("gh", "touch \(dir!)/gh-ran")
        let judge = script("judge", "print PASS")
        if case .opened = LoopHarvest.harvest(loop: l, approvedIds: [1], title: "t", tools: .init(gh: gh, judge: [judge])) { XCTFail("tests fail") }
        var ok = l; ok.check = "test -f fix.txt"
        if case .refused(let why, let gate) = LoopHarvest.harvest(loop: ok, approvedIds: [1], title: "t", tools: .init(gh: gh, judge: nil)) {
            XCTAssertTrue(gate?.judgeReason.contains("no judge") == true, why)
        } else { XCTFail("no judge = no PR") }
        XCTAssertFalse(FileManager.default.fileExists(atPath: dir + "/gh-ran"))
        XCTAssertEqual(LoopHarvest.verdict(rc: 0, output: "Thinking…\nPASS — fine").0, true)
        XCTAssertEqual(LoopHarvest.verdict(rc: 0, output: "looks ok").0, false)
        XCTAssertEqual(LoopHarvest.verdict(rc: 1, output: "PASS").0, false)
    }

    // MARK: Triggers (LAB-1369 · LAB-1865)

    func test_quiet_noStartWhileBusy_startsAfterQuietTime_insideWindow_oncePerNight() {
        let night = Date(timeIntervalSince1970: 1_800_000_000)   // 2027-01-15 08:00 UTC
        let at2 = cal.date(bySettingHour: 2, minute: 0, second: 0, of: night)!
        var l = Loop(id: "q", name: "q", repoPath: "/p", trigger: .whenQuiet(quietMinutes: 15, fromHour: 1, toHour: 6), state: .waiting,
                     createdAt: at2.addingTimeInterval(-86_400))
        XCTAssertEqual(LoopController.next(l, rounds: [], now: at2, round: .none, calendar: cal, context: .init(quietFor: nil)), .wait)        // busy
        XCTAssertEqual(LoopController.next(l, rounds: [], now: at2, round: .none, calendar: cal, context: .init(quietFor: 600)), .wait)        // 10 min
        XCTAssertEqual(LoopController.next(l, rounds: [], now: at2, round: .none, calendar: cal, context: .init(quietFor: 900)), .runCheck)    // 15 min
        let noon = cal.date(bySettingHour: 12, minute: 0, second: 0, of: night)!
        XCTAssertEqual(LoopController.next(l, rounds: [], now: noon, round: .none, calendar: cal, context: .init(quietFor: 9000)), .wait)    // outside 1–6
        l.lastRunAt = at2                                                                                                                      // ran tonight
        XCTAssertEqual(LoopController.next(l, rounds: [], now: at2.addingTimeInterval(3600), round: .none, calendar: cal, context: .init(quietFor: 9000)), .wait)
        XCTAssertEqual(LoopController.next(l, rounds: [], now: at2.addingTimeInterval(86_400), round: .none, calendar: cal, context: .init(quietFor: 9000)), .runCheck)
        l.state = .stopped
        XCTAssertEqual(LoopController.next(l, rounds: [], now: at2.addingTimeInterval(86_400), round: .none, calendar: cal, context: .init(quietFor: 9000)), .wait)
        // Window that wraps midnight.
        XCTAssertNotNil(LoopController.quietWindowStart(from: 22, to: 6, now: at2, calendar: cal))
        XCTAssertNil(LoopController.quietWindowStart(from: 22, to: 6, now: noon, calendar: cal))
        XCTAssertTrue(LoopTrigger.whenQuiet(quietMinutes: 15, fromHour: nil, toHour: nil).isArmed)
    }

    func test_quietFor_fromProbes() {
        let now = Date(timeIntervalSince1970: 10_000)
        let busy = LoopQuiet.quietFor(now: now, probes: [.init(status: "idle", active: now), .init(status: "blocked", active: .distantPast)], lastBusy: .distantPast)
        XCTAssertNil(busy.0); XCTAssertEqual(busy.1, now)
        let q = LoopQuiet.quietFor(now: now, probes: [.init(status: "done", active: now.addingTimeInterval(-600))], lastBusy: now.addingTimeInterval(-1200))
        XCTAssertEqual(q.0, 600)
        XCTAssertEqual(LoopQuiet.quietFor(now: now, probes: [], lastBusy: now.addingTimeInterval(-60)).0, 60)
    }

    func test_event_firesOncePerEventAfterLastRun_filesRoundTrip() throws {
        var l = Loop(id: "triage", name: "triage", repoPath: "/p", trigger: .onEvent("linear.issue.created"), state: .waiting,
                     createdAt: Date(timeIntervalSince1970: 1000))
        try LoopEvents.fire("git.push", root: dir, at: Date(timeIntervalSince1970: 2000))
        XCTAssertEqual(LoopController.next(l, rounds: [], now: Date(timeIntervalSince1970: 3000), round: .none, context: .init(events: LoopEvents.read(root: dir))), .wait)
        try LoopEvents.fire("linear.issue.created", root: dir, at: Date(timeIntervalSince1970: 2500), detail: "LAB-1")
        let events = LoopEvents.read(root: dir)
        XCTAssertEqual(events.map(\.event), ["git.push", "linear.issue.created"])
        XCTAssertEqual(LoopController.next(l, rounds: [], now: Date(timeIntervalSince1970: 3000), round: .none, context: .init(events: events)), .runCheck)
        l = LoopController.begin(l, now: Date(timeIntervalSince1970: 3000))
        l.run = nil; l.state = .done
        XCTAssertEqual(LoopController.next(l, rounds: [], now: Date(timeIntervalSince1970: 3100), round: .none, context: .init(events: events)), .wait)
        // A file written by the kit (ISO time) reads too; old ones are pruned.
        try Data(#"{"event": "oneroof.release", "at": "2026-10-31T03:00:00+00:00"}"#.utf8).write(to: URL(fileURLWithPath: LoopEvents.folder(dir) + "/1761879600000-oneroof.release.json"))
        XCTAssertTrue(LoopEvents.read(root: dir).contains { $0.event == "oneroof.release" })
        LoopEvents.prune(root: dir, now: Date(timeIntervalSince1970: 1_761_879_600 + 2 * 86_400))
        XCTAssertFalse(LoopEvents.read(root: dir).contains { $0.event == "oneroof.release" })
        // Codable round trip keeps the new triggers (and the kit's `at` stays readable).
        for t in [LoopTrigger.whenQuiet(quietMinutes: 20, fromHour: 1, toHour: 6), .onEvent("git.push"), .at(hour: 3, minute: 0)] {
            let d = try JSONEncoder().encode(t)
            XCTAssertEqual(try JSONDecoder().decode(LoopTrigger.self, from: d), t)
        }
        let kitShape = try JSONSerialization.jsonObject(with: try JSONEncoder().encode(LoopTrigger.at(hour: 3, minute: 0))) as? [String: [String: Int]]
        XCTAssertEqual(kitShape, ["at": ["hour": 3, "minute": 0]])   // what the kit's read_oneroof_loop reads
    }

    // MARK: .loop.yaml loops (LAB-1843)

    let weekly = """
    # my-weekly-review: yours
    name: my-weekly-review
    origin: user
    version: 1
    title: My weekly review
    kind: reporter
    goal: Stale issues are re-planned and the week's numbers are recorded,
      with every proposal waiting for my OK.
    check:
      run: ae journal verify --loop {loop} --run {run}
      pass: exit 0
    stop:
      when: check passes
      max_iterations: 1
      max_minutes: 30
    schedule:
      cron: 0 17 * * 5
    act:
      by: issue
      min_severity: medium
    writes:
    - runs
    - proposals
    """

    func test_yamlLoop_isMine_readOnlySpec_neverArmed_runStateInItsFolder() throws {
        try weekly.write(toFile: dir + "/my-weekly-review.loop.yaml", atomically: true, encoding: .utf8)
        try "name: Bad Name\n".write(toFile: dir + "/bad.loop.yaml", atomically: true, encoding: .utf8)
        let s = LoopStore(root: dir, builtIns: [], fileLoops: LoopFiles.load(folder: dir, repoPath: "/p/ae"))
        let all = s.all()
        XCTAssertEqual(all.map(\.id), ["my-weekly-review"])
        let l = try XCTUnwrap(all.first)
        XCTAssertEqual(l.origin, .mine); XCTAssertEqual(l.displayTitle, "My weekly review")
        XCTAssertEqual(l.goal, "Stale issues are re-planned and the week's numbers are recorded, with every proposal waiting for my OK.")
        XCTAssertEqual(l.check, "python3 -m ae.loops run my-weekly-review --no-agent")
        XCTAssertEqual(l.externalSchedule, "cron 0 17 * * 5")
        XCTAssertEqual(l.kind, "reporter"); XCTAssertEqual(l.act, "issue")
        XCTAssertEqual(l.limits.maxDuration, 1800)
        XCTAssertEqual(l.state, .stopped); XCTAssertFalse(l.trigger.isArmed)      // ae schedules it, never roofd
        XCTAssertTrue(l.isKitFile); XCTAssertTrue(s.isFileLoop(l.id))
        // Run now writes run state in its folder; the file stays the spec and is never rewritten.
        let before = try String(contentsOfFile: dir + "/my-weekly-review.loop.yaml", encoding: .utf8)
        try s.update(l.id) { $0 = LoopController.runNow($0); $0.goal = "changed here" }
        let again = try XCTUnwrap(s.load(l.id))
        XCTAssertTrue(again.runRequested); XCTAssertEqual(again.goal, l.goal); XCTAssertEqual(again.origin, .mine)
        XCTAssertEqual(try String(contentsOfFile: dir + "/my-weekly-review.loop.yaml", encoding: .utf8), before)
        XCTAssertEqual(s.newId(for: "my weekly review"), "my-weekly-review-2")
    }

    func test_miniYAML_blockScalarAndQuotes() {
        let y = MiniYAML.parse("name: 'x-y'\nprompt: |\n  line one\n  line two\ntitle: \"A: B\" # c\n")
        XCTAssertEqual(y.string("name"), "x-y")
        XCTAssertEqual(y.string("prompt"), "line one\nline two")
        XCTAssertEqual(y.string("title"), "A: B")
    }

    func test_builtInCatalog_carriesKindAndAct() throws {
        let cat = #"{"version": 1, "loops": [{"id": "docs-drift", "name": "docs-drift", "title": "Docs drift", "origin": "built-in", "goal": "g", "check": "c", "cron": "0 6 * * *", "hour": 6, "minute": 0, "maxRounds": 1, "maxMinutes": 10, "costCapUsd": 0, "roundPrompt": "", "kind": "auditor", "act": "pr", "trigger": "clock", "writes": ["runs"]}]}"#
        try cat.write(toFile: dir + "/catalog.json", atomically: true, encoding: .utf8)
        let l = try XCTUnwrap(LoopBuiltIns.load(catalogPath: dir + "/catalog.json", repoPath: "/p").first)
        XCTAssertEqual(l.kind, "auditor"); XCTAssertEqual(l.act, "pr")
        XCTAssertEqual(LoopKinds.kind("auditor")?.title, "Auditor")
        XCTAssertTrue(LoopKinds.destination(act: "pr").contains("after you approve"))
    }

    // MARK: Drafting (LAB-1921)

    func test_rules_readTheWords() {
        var d = LoopDrafter.rules("every night at 3:30 fix the failing swift test, at most 5 rounds")
        XCTAssertEqual(d.trigger, .at(hour: 3, minute: 30)); XCTAssertEqual(d.check, "swift test"); XCTAssertEqual(d.limits.maxRounds, 5)
        d = LoopDrafter.rules("when quiet between 1 and 6, tidy the docs; check `bash tools/docs-check.sh`")
        XCTAssertEqual(d.trigger, .whenQuiet(quietMinutes: 15, fromHour: 1, toHour: 6)); XCTAssertEqual(d.check, "bash tools/docs-check.sh")
        d = LoopDrafter.rules("when a new bug comes in, write repeatable steps")
        XCTAssertEqual(d.trigger, .onEvent("linear.issue.created"))
        XCTAssertTrue(d.notes.contains { $0.contains("Set the check") })
        d = LoopDrafter.rules("every Monday tell me which dependencies are outdated")
        XCTAssertTrue(d.trigger.isNightly); XCTAssertTrue(d.notes.contains { $0.contains("Mondays") })
        XCTAssertEqual(d.name, "tell-me-which-dependencies-are")
        XCTAssertEqual(d.goal, "Tell me which dependencies are outdated")
        XCTAssertEqual(LoopDrafter.rules("when quiet between 1 and 6, tidy the docs until `true` passes").name, "tidy-the-docs-until-true")
        XCTAssertEqual(LoopDrafter.rules("at 11 pm run it").trigger, .at(hour: 23, minute: 0))
    }

    func test_agentDraft_parsed_fallsBackToRules() {
        let out = """
        Here you go:
        {"name": "Deps Watch", "goal": "No outdated dependency is older than a week.", "check": "│ bash tools/deps-check.sh",
         "trigger": {"when": "nightly", "hour": 7, "minute": 15}, "maxRounds": 2, "maxMinutes": 30, "roundPrompt": "Group updates.", "notes": ["weekly not possible"]}
        """
        let d = LoopDrafter.parse(agentOutput: out)
        XCTAssertEqual(d?.name, "deps-watch"); XCTAssertEqual(d?.check, "bash tools/deps-check.sh")
        XCTAssertEqual(d?.trigger, .at(hour: 7, minute: 15)); XCTAssertEqual(d?.limits.maxRounds, 2); XCTAssertEqual(d?.source, "agent")
        XCTAssertNil(LoopDrafter.parse(agentOutput: "no json"))
        let fake = script("drafter", "print 'not json'")
        let r = LoopDrafter.draft("nightly at 2 tidy up", repo: dir, command: [fake])
        XCTAssertEqual(r.source, "rules"); XCTAssertTrue(r.notes.first?.contains("could not be read") == true)
        let good = script("drafter2", "print -r -- '{\"goal\": \"Docs are tidy.\", \"check\": \"true\", \"trigger\": {\"when\": \"quiet\", \"quietMinutes\": 30}}'")
        XCTAssertEqual(LoopDrafter.draft("x", repo: dir, command: [good]).trigger, .whenQuiet(quietMinutes: 30, fromHour: nil, toHour: nil))
        XCTAssertEqual(LoopDrafter.draft("x", repo: dir, command: nil).source, "rules")
    }

    func test_preview_saysWhatTheFirstRunDoes() {
        let l = Loop(id: "", name: "deps watch", goal: "deps fresh", check: "bash tools/deps-check.sh", repoPath: "/p/acme",
                     trigger: .whenQuiet(quietMinutes: 15, fromHour: 1, toHour: 6))
        let p = LoopDrafter.preview(l)
        XCTAssertTrue(p[0].contains("between 1:00 AM and 6:00 AM") || p[0].contains("between 01:00 and 06:00"), p[0])
        XCTAssertTrue(p.contains { $0.contains("Runs the check first: `bash tools/deps-check.sh`") })
        XCTAssertTrue(p.contains { $0.contains("Goal: deps fresh") })
        XCTAssertTrue(p.last!.contains("Nothing is pushed or merged"))
    }
}
