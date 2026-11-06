import XCTest
@testable import OneRoofCore

/// LAB-2287–2290 · Loops v7 Lane A: 7b a kind's page, 7c one loop, 7d Needs you (types, questions first, stale, By kind,
/// the title), 7l the question card and the loop's allow rule. Uses the 7a fixture (LoopsV7LandingTests).
final class LoopsV7NeedsYouTests: XCTestCase {
    let base = LoopsV7LandingTests()
    var cal: Calendar { base.cal }
    var now: Date { base.now }

    // MARK: 7b

    func test_7b_watchHeadCardsAndGroups() {
        let f = base.fixture()
        let p = LoopsV7.kindPage(family: "watch", rows: f.rows, items: f.items, weekRuns: f.rows.compactMap(\.lastRun), now: now, calendar: cal)
        XCTAssertEqual(p.family.title, "Watch")
        XCTAssertEqual(p.on, 2)
        XCTAssertEqual(p.all, 3)
        XCTAssertEqual(p.subtypes, "Sentinel · Prober")
        XCTAssertEqual(p.offRows.map(\.id), ["perf-guard"])
        XCTAssertTrue(p.status.contains("The live one passed its last run."), p.status)
        XCTAssertTrue(p.status.contains("fleet-sweep, in its trial, hasn't run since Nov 1."), p.status)
        // For you: the missed runs, with Run now; the gap: the off loop, ready to turn on.
        XCTAssertEqual(p.forYou.asks.first?.action, .runNow("fleet-sweep"))
        XCTAssertEqual(p.gap.asks.first?.action, .turnOn("perf-guard"))
        XCTAssertEqual(p.gap.asks.first?.button, "Turn on perf-guard")
        XCTAssertEqual(p.gap.title, "Off: watch app speed")
        XCTAssertFalse(p.ready)
    }

    func test_7b_needsSetupGapAndChips() {
        let f = base.fixture()
        let p = LoopsV7.kindPage(family: "watch", rows: f.rows, items: f.items, weekRuns: [], setupMissing: ["perf-guard"], now: now, calendar: cal)
        XCTAssertEqual(p.gap.asks.first?.action, .setUp("perf-guard"))
        XCTAssertEqual(p.gap.asks.first?.button, "Set up perf-guard")
        let all = p.onRows + p.offRows
        XCTAssertEqual(LoopsV7.kindChip(all, .needsSetup, setupMissing: ["perf-guard"]).map(\.id), ["perf-guard"])
        XCTAssertEqual(LoopsV7.kindChip(all, .on, setupMissing: []).count, 2)
        XCTAssertEqual(LoopsV7.kindChip(all, .off, setupMissing: []).map(\.id), ["perf-guard"])
        // Search: what it watches (the goal) and the subtype.
        XCTAssertEqual(LoopsV7.kindSearch(all, "speed").map(\.id), ["perf-guard"])
        XCTAssertEqual(LoopsV7.kindSearch(all, "sentinel").count, 3)
        XCTAssertTrue(LoopsV7.kindSearch(all, "nothing-like-this").isEmpty)
        XCTAssertEqual(LoopsV7.offRuns(p.offRows[0], calendar: cal), "never run")
    }

    func test_7b_weekCardCountsFindingsFromRunSummaries() {
        let f = base.fixture()
        let week = f.rows.compactMap(\.lastRun) + [base.run("docs-drift", "2026-11-05 06:00", summary: "Docs drift: pass, 3 finding(s)")]
        let p = LoopsV7.kindPage(family: "check", rows: f.rows, items: f.items, weekRuns: week, now: now, calendar: cal)
        XCTAssertEqual(p.week.label, "Caught this week")
        XCTAssertEqual(p.week.title, "5 findings from 1 loop")   // the newest run with findings counts
        XCTAssertEqual(LoopsV7.findings("Docs drift: pass, 5 finding(s)"), 5)
        XCTAssertNil(LoopsV7.findings("check passed"))
        XCTAssertEqual(LoopsV7.kindWeekLabel("report"), "Written this week")
        XCTAssertEqual(p.ready, true)   // every Check loop of the fixture is on
        // An off loop's old trial runs are not what the kind caught this week.
        let w = LoopsV7.kindPage(family: "watch", rows: f.rows, items: f.items,
                                 weekRuns: [base.run("perf-guard", "2026-11-04 19:38", .trial, summary: "Perf guard: dry, 9 finding(s)")], now: now, calendar: cal)
        XCTAssertEqual(w.week.title, "No runs this week")
    }

    // MARK: 7c

    func test_7c_stateAndFactsChips() {
        let f = base.fixture()
        let refl = f.rows.first { $0.id == "nightly-reflection" }!
        XCTAssertEqual(LoopsV7.stateChip(refl).text, "failing · 2 nights")
        XCTAssertEqual(LoopsV7.stateChip(refl).tone, .failing)
        let bugs = f.rows.first { $0.id == "oneroof-nightly-bugs" }!
        XCTAssertEqual(LoopsV7.factsChip(bugs), "Built-in · One Roof (roofd) · nightly 3:00 · live")
        let mac = f.rows.first { $0.id == "my-mac-resource-watch" }!
        XCTAssertEqual(LoopsV7.factsChip(mac), "Built-in · kit (ae, launchd) · every 10 min · live")
        XCTAssertEqual(LoopsV7.factsChip(mac, kitKnown: false), "Built-in · kit (ae, launchd) · every 10 min · kit state unknown")
        let fleet = f.rows.first { $0.id == "fleet-sweep" }!
        XCTAssertTrue(LoopsV7.stateChip(fleet).text.hasPrefix("missed · "))
    }

    func test_7c_runGroupsFoldTheSameFailureAndKeepTimePerRun() {
        let f = base.fixture()
        let bugsRuns = ["2026-11-04 03:00", "2026-11-05 03:00", "2026-11-06 03:00"].map {
            LoopRun7(id: $0, loop: "b", engine: .oneRoof, started: base.at($0), ended: base.at($0).addingTimeInterval(840), result: .failed, cost: nil, summary: "Same failure twice")
        } + [LoopRun7(id: "ok", loop: "b", engine: .oneRoof, started: base.at("2026-11-03 03:00"), ended: nil, result: .passed, cost: nil, summary: "4 commits staged")]
        let g = LoopsV7.runGroups(bugsRuns, calendar: cal)
        XCTAssertEqual(g.count, 2)
        XCTAssertEqual(g[0].result, "failed ×3")
        XCTAssertEqual(g[0].dates, "Nov 6 … Nov 4")
        XCTAssertEqual(g[0].time, "14 min avg")
        XCTAssertEqual(g[1].result, "passed")
        XCTAssertEqual(g[1].dates, "Nov 3 3:00")
        XCTAssertEqual(g[1].time, "")   // not recorded: the view says so
        // Runs of one day fold to "Nov 6 10:05–13:05".
        let mac = LoopsV7.runGroups(f.rows.first { $0.id == "my-mac-resource-watch" }.map { r in
            stride(from: 0, through: 180, by: 60).map { base.run(r.id, String(format: "2026-11-06 %02d:05", 10 + $0 / 60)) } } ?? [], calendar: cal)
        XCTAssertEqual(mac.map(\.dates), ["Nov 6 10:05–13:05"])
        XCTAssertEqual(mac[0].result, "passed ×4")
    }

    func test_7c_stepsForAKitLoopAndWhatYouCanDo() {
        let f = base.fixture()
        let refl = f.rows.first { $0.id == "nightly-reflection" }!
        let waiting = f.items.filter { $0.loopId == "nightly-reflection" }
        let s = LoopsV7.steps(row: refl, agent: "Claude", branch: "loop/x", rounds: [], waiting: waiting, now: now, calendar: cal)
        XCTAssertEqual(s.map(\.label), ["When", "Work", "Check", "Stop", "You"])
        XCTAssertEqual(s[0].who, .kit)
        XCTAssertEqual(s[1].title, "The kit's own check")
        XCTAssertEqual(s[2].tint, .failed)
        XCTAssertEqual(s[4].tint, .you)
        XCTAssertEqual(s[4].title, "2 proposals waiting")
        let bugs = f.rows.first { $0.id == "oneroof-nightly-bugs" }!
        let todo = LoopsV7.whatYouCanDo(bugs, waiting: f.items.filter { $0.loopId == "oneroof-nightly-bugs" }, needsSetup: false, engine: .oneRoof, calendar: cal)
        XCTAssertEqual(todo.map(\.title), ["Review the 2 commits from Nov 4", "Run it again", "Pause it"])
        XCTAssertEqual(LoopsV7.whyStopped("Same failure twice in a row")?.hasPrefix("A loop stops when the same check fails"), true)
        XCTAssertNil(LoopsV7.whyStopped("Stopped by you"))
    }

    func test_7c_stepsFromRoundsOfAOneRoofLoop() {
        let f = base.fixture()
        let bugs = f.rows.first { $0.id == "oneroof-nightly-bugs" }!
        let run = bugs.lastRun!.id
        func line(_ k: LoopRound.Kind, _ n: Int, passed: Bool? = nil, note: String? = nil) -> LoopRound {
            var r = LoopRound(kind: k, runId: run, n: n, started: now, ended: now)
            r.checkPassed = passed; r.exitCode = passed == false ? 1 : nil; r.failureKey = passed == false ? "8972283f" : nil; r.note = note
            return r
        }
        let rounds = [line(.round, 1), line(.round, 2), line(.check, 2, passed: false), line(.stop, 2, note: "Same failure twice in a row.")]
        let s = LoopsV7.steps(row: bugs, agent: "Claude", branch: "loop/oneroof-nightly-bugs", rounds: rounds, waiting: [], now: now, calendar: cal)
        XCTAssertEqual(s[1].title, "Claude, rounds 1–2")
        XCTAssertEqual(s[1].who, .agent)
        XCTAssertEqual(s[2].title, "exit 1 · 8972283f")
        XCTAssertEqual(s[3].title, "Stop rule hit")
        // roofd's own failure key ("exit 1 · 8972283f") is not doubled; a long stop note is cut to its first part.
        var keyed = rounds
        keyed[2].failureKey = "exit 1 · 8972283f"
        keyed[3].note = "The same failure twice in a row (exit 1 · 8972283f): a new approach is needed. Tried: #1 ✕ exit 1"
        let s2 = LoopsV7.steps(row: bugs, agent: "Claude", branch: "b", rounds: keyed, waiting: [], now: now, calendar: cal)
        XCTAssertEqual(s2[2].title, "exit 1 · 8972283f")
        XCTAssertTrue(s2[3].text.hasPrefix("The same failure twice in a row (exit 1 · 8972283f). Ended"), s2[3].text)
        XCTAssertEqual(s[4].title, "Nothing waits")
    }

    func test_7c_nextRunCard() {
        let f = base.fixture()
        let mac = f.rows.first { $0.id == "my-mac-resource-watch" }!
        XCTAssertEqual(LoopsV7.nextRunCard(mac, maxRounds: nil, maxHours: nil, now: now, calendar: cal).title, "Today 10:40")
        let bugs = f.rows.first { $0.id == "oneroof-nightly-bugs" }!
        let n = LoopsV7.nextRunCard(bugs, maxRounds: 10, maxHours: 4, now: now, calendar: cal)
        XCTAssertEqual(n.title, "Tonight 3:00")
        XCTAssertTrue(n.text.hasSuffix("Up to 10 rounds or 4 h."), n.text)
    }

    // MARK: 7d

    func test_7d_typesCountsAndTheOneCount() {
        let f = base.fixture()
        let c = LoopsV7.needsCounts(f.items)
        XCTAssertEqual(c[.all], LoopsV7.needsCount(items: f.items))   // the tab's All = the badge's N
        XCTAssertEqual(c[.commits], 1)
        XCTAssertEqual(c[.proposals], 4)
        XCTAssertEqual(c[.reports], 1)
        XCTAssertEqual(c[.missed], 1)
        XCTAssertEqual(LoopsV7.needsHeadline(count: LoopsV7.needsCount(items: f.items), seconds: LoopsV7.estimateSeconds(f.items)),
                       "7 things wait for you. About 10 minutes.")
        XCTAssertEqual(LoopsV7.needsHeadline(count: 1, seconds: 30), "1 thing waits for you. About 1 minute.")
        XCTAssertEqual(LoopsV7.needsHeadline(count: 0, seconds: 0), "Nothing waits for you.")
    }

    func test_7d_questionsFirstFiltersAndByKind() {
        var f = base.fixture()
        let ask = LoopInbox.Item(id: "asks-x", kind: .asks, loopId: "oneroof-nightly-bugs", loopTitle: "oneroof-nightly-bugs",
                                 headline: "Loop oneroof-nightly-bugs: round 3 asks something", detail: "", when: now, sessionId: "s1")
        f.items.append(ask)
        let l = LoopsV7.needsList(f.items, rows: f.rows, now: now)
        XCTAssertEqual(l.fresh.first?.id, "asks-x")
        XCTAssertEqual(l.fresh.last?.kind, .missed)
        XCTAssertEqual(LoopsV7.needsList(f.items, type: .questions, rows: f.rows, now: now).fresh.map(\.id), ["asks-x"])
        XCTAssertEqual(LoopsV7.needsList(f.items, family: "check", rows: f.rows, now: now).fresh.count, 3)
        XCTAssertEqual(LoopsV7.needsList(f.items, loop: "nightly-reflection", rows: f.rows, now: now).fresh.count, 2)
        XCTAssertEqual(LoopsV7.needsList(f.items, query: "fleet", rows: f.rows, now: now).fresh.map(\.kind), [.missed])
        let by = Dictionary(uniqueKeysWithValues: LoopsV7.needsByKind(f.items, rows: f.rows).map { ($0.family, ($0.count, $0.words)) })
        XCTAssertEqual(by["other"]?.0, 2)
        XCTAssertEqual(by["other"]?.1, "1 PR, 1 question")
        XCTAssertEqual(by["check"]?.1, "2 proposals, 1 report")
        XCTAssertEqual(by["report"]?.0, 0)   // every kind listed, 0 included
        XCTAssertEqual(LoopsV7.needsDot(ask), .needsYou)
        XCTAssertEqual(LoopsV7.needsTitle(f.items.first { $0.outcomeKind == "commit" }!), "Review a PR of 2 commits")
    }

    func test_7d_staleAfter7DaysFoldsOnlyStagedItems_LP5() {
        let old = LoopLedger.Outcome(id: 99, runId: "r", loop: "docs-drift", kind: "proposal", link: "", title: "old", status: "staged",
                                     decidedBy: nil, decidedAt: nil, created: "2026-10-28T06:00:00-08:00", detail: "")
        let items = LoopInbox.today([old]) + [LoopInbox.Item(id: "failed-x", kind: .failed, loopId: "x", loopTitle: "x", headline: "h", detail: "d",
                                                               when: base.at("2026-10-20 10:00"))]
        XCTAssertTrue(LoopsV7.isStale(items[0], now: now))
        XCTAssertFalse(LoopsV7.isStale(items[1], now: now))   // a failure never folds
        let l = LoopsV7.needsList(items, now: now)
        XCTAssertEqual(l.stale.map(\.id), [items[0].id])
        XCTAssertEqual(l.fresh.map(\.id), ["failed-x"])
        XCTAssertFalse(LoopsV7.isStale(items[0], now: base.at("2026-11-04 06:00")))
        XCTAssertEqual(LoopsV7.age(base.at("2026-11-03 10:35"), now: now), "3 days")
        XCTAssertEqual(LoopsV7.age(base.at("2026-11-06 10:33"), now: now), "2 min")
    }

    // MARK: 7l

    func test_7l_questionFromThePromptAndTheScreen() {
        let item = LoopInbox.Item(id: "asks-b", kind: .asks, loopId: "oneroof-nightly-bugs", loopTitle: "One Roof nightly bugs",
                                  headline: "Loop One Roof nightly bugs: round 3 asks something", detail: "", when: now, sessionId: "s1")
        let screen = [" Bash command", "", "   swift package resolve", "   Fetch the package the fix needs", "", " Do you want to proceed?", " ❯ 1. Yes"]
        XCTAssertEqual(LoopQuestion.command(fromScreen: screen), "swift package resolve")
        XCTAssertNil(LoopQuestion.command(fromScreen: [" Do you want to proceed?", " ❯ 1. Yes"]))
        let d = Decision(sessionId: "s1", agent: .claude, kind: .runCommand, why: "the fix needs a package the worktree hasn't fetched",
                         touches: "", risk: .low, ifNo: "", pattern: "swift package", repo: "labs/oneroof", askedAt: now, screen: screen)
        let loop = Loop(id: "oneroof-nightly-bugs", name: "oneroof-nightly-bugs", repoPath: "/r/labs/oneroof")
        let q = LoopQuestion.make(item: item, loop: loop, prompt: d)
        XCTAssertEqual(q.round, 3)
        XCTAssertEqual(q.command, "swift package resolve")
        XCTAssertEqual(q.reason, "the fix needs a package the worktree hasn't fetched")
        XCTAssertEqual(q.title, "One Roof nightly bugs, round 3, wants to run a command it isn't allowed to run yet")
        XCTAssertEqual(q.rowTitle, "Round 3 asks to run a command")
        XCTAssertEqual(q.worktree, loop.worktreePath)
        // No prompt read: no command invented.
        let bare = LoopQuestion.make(item: item, loop: nil, prompt: nil)
        XCTAssertNil(bare.command)
        XCTAssertEqual(bare.title, "One Roof nightly bugs, round 3, asks you something")
    }

    func test_7l_alwaysForThisLoopWritesOneExactRuleForClaudeOnly() throws {
        XCTAssertEqual(LoopAllowRule.rule(agent: .claude, command: "swift package resolve"), "Bash(swift package resolve)")
        XCTAssertNil(LoopAllowRule.rule(agent: .codex, command: "swift package resolve"))
        XCTAssertNil(LoopAllowRule.rule(agent: .claude, command: nil))
        XCTAssertNotNil(LoopAllowRule.unavailable(agent: .codex, command: "ls", worktree: "/w"))
        XCTAssertNotNil(LoopAllowRule.unavailable(agent: .claude, command: nil, worktree: "/w"))
        XCTAssertNil(LoopAllowRule.unavailable(agent: .claude, command: "ls", worktree: "/w"))
        let existing = #"{"model":"opus","permissions":{"allow":["Bash(ls)"],"deny":["Bash(git push:*)"]}}"#.data(using: .utf8)
        let out = try LoopAllowRule.merged(existing: existing, adding: "Bash(swift package resolve)")
        let again = try LoopAllowRule.merged(existing: out, adding: "Bash(swift package resolve)")
        let j = try JSONSerialization.jsonObject(with: again) as! [String: Any]
        let perms = j["permissions"] as! [String: Any]
        XCTAssertEqual(perms["allow"] as? [String], ["Bash(ls)", "Bash(swift package resolve)"])
        XCTAssertEqual(perms["deny"] as? [String], ["Bash(git push:*)"])
        XCTAssertEqual(j["model"] as? String, "opus")
        XCTAssertThrowsError(try LoopAllowRule.merged(existing: "[1]".data(using: .utf8), adding: "x"))
        // Written into the worktree's .claude/settings.local.json, created when missing.
        let wt = NSTemporaryDirectory() + "loopallow-\(UUID().uuidString)"
        try FileManager.default.createDirectory(atPath: wt, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: wt) }
        try LoopAllowRule.write(rule: "Bash(swift package resolve)", worktree: wt)
        let written = try JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: wt + "/.claude/settings.local.json"))) as! [String: Any]
        XCTAssertEqual((written["permissions"] as? [String: Any])?["allow"] as? [String], ["Bash(swift package resolve)"])
        XCTAssertThrowsError(try LoopAllowRule.write(rule: "x", worktree: wt + "/missing"))
    }
}
