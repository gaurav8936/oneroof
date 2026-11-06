import XCTest
@testable import OneRoofCore

/// LAB-ONEROOF-v2.0.6 · M1 (LP-1, LP-3, LP-4, LP-8/9, LP-10): the data the Loops v7 screens read.
final class LoopsV7DataTests: XCTestCase {
    var cal: Calendar = { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "America/Los_Angeles")!; return c }()
    func at(_ s: String) -> Date { var c = cal; c.locale = Locale(identifier: "en_US_POSIX")
        let f = DateFormatter(); f.calendar = c; f.timeZone = c.timeZone; f.dateFormat = "yyyy-MM-dd HH:mm"; return f.date(from: s)! }

    // LP-1
    func testKitListJSONParses() {
        let json = #"{"loops":[{"name":"cost-watch","origin":"Built-in","on":true,"mode":"live","schedule":"0 9-23 * * *","scheduler":"launchd","last":"2026-11-06T10:00","result":"pass","title":"Cost watch"},{"name":"perf-guard","on":false,"mode":""},{"nope":1}]}"#
        let k = KitLoops.parse(Data(json.utf8))
        XCTAssertEqual(k.map(\.name), ["cost-watch", "perf-guard"])
        XCTAssertTrue(k[0].on); XCTAssertEqual(k[0].mode, "live"); XCTAssertEqual(k[0].scheduler, "launchd")
        XCTAssertFalse(k[1].on)
        XCTAssertEqual(KitLoops.parse(Data("not json".utf8)), [])
    }

    func testKitLoopOnLiveIsNotOff() {
        let l = Loop(id: "my-mac-resource-watch", name: "my-mac-resource-watch", origin: .mine, goal: "g", check: "c", repoPath: "/r",
                     agent: .claude, trigger: .untilDone(everyMinutes: 0), limits: LoopLimits(maxRounds: 1, maxDuration: 60, sameFailureStop: 2),
                     pinned: false, state: .stopped, createdAt: Date()).with { $0.specFile = "/x.loop.yaml" }
        let on = LoopsV7.engineState(l, kit: KitLoopStatus(name: l.id, on: true, mode: "live", schedule: "*/10 * * * *", scheduler: "launchd"))
        XCTAssertEqual(on.engine, .kit); XCTAssertTrue(on.on); XCTAssertEqual(on.mode, .live)
        let sh = LoopsV7.engineState(l, kit: KitLoopStatus(name: l.id, on: true, mode: "shadow", scheduler: "launchd"))
        XCTAssertEqual(sh.mode, .shadow)
        let off = LoopsV7.engineState(l, kit: KitLoopStatus(name: l.id, on: false))
        XCTAssertFalse(off.on); XCTAssertNil(off.mode)
        let roofd = LoopsV7.engineState(l.with { $0.specFile = nil; $0.state = .waiting }, kit: KitLoopStatus(name: l.id, on: true, scheduler: "roofd"))
        XCTAssertEqual(roofd.engine, .oneRoof); XCTAssertTrue(roofd.on)
        XCTAssertFalse(LoopsV7.engineState(l, kit: nil).on, "kit state unknown: never guessed on")
    }

    // LP-3
    func testCronFields() {
        let c = CronSpec("*/10 * * * *")!
        XCTAssertEqual(c.minutes, [0, 10, 20, 30, 40, 50]); XCTAssertEqual(c.hours.count, 24)
        XCTAssertEqual(CronSpec("0 9-23 * * *")!.hours, Set(9...23))
        XCTAssertEqual(CronSpec("0 */4 * * *")!.hours, [0, 4, 8, 12, 16, 20])
        XCTAssertEqual(CronSpec("0 2 * * 2,5")!.weekdays, [2, 5])
        XCTAssertEqual(CronSpec("0 2 * * 7")!.weekdays, [0], "7 is Sunday")
        XCTAssertNil(CronSpec("manual")); XCTAssertNil(CronSpec("61 * * * *")); XCTAssertNil(CronSpec("* * *"))
        XCTAssertNotNil(CronSpec("cron 0 17 * * 5"), "LoopFiles' 'cron …' prefix is accepted")
    }

    func testCronTimes() {
        let day = CronSpec("30 2 * * *")!.times(from: at("2026-11-01 00:00"), to: at("2026-11-08 00:00"), calendar: cal)
        XCTAssertEqual(day.count, 7)
        XCTAssertEqual(CronSpec("*/10 * * * *")!.times(from: at("2026-11-06 10:00"), to: at("2026-11-06 11:00"), calendar: cal).count, 6)
        let fri = CronSpec("0 17 * * 5")!.times(from: at("2026-11-01 00:00"), to: at("2026-11-08 00:00"), calendar: cal)
        XCTAssertEqual(fri, [at("2026-11-06 17:00")], "Nov 6 2026 is a Friday")
        XCTAssertEqual(CronSpec("0 9 1 * *")!.times(from: at("2026-10-15 00:00"), to: at("2026-12-15 00:00"), calendar: cal).count, 2)
    }

    func testScheduleWords() {
        XCTAssertEqual(LoopSchedule.words(CronSpec("*/10 * * * *")), "every 10 min")
        XCTAssertEqual(LoopSchedule.words(CronSpec("0 9-23 * * *")), "hourly 9–23")
        XCTAssertEqual(LoopSchedule.words(CronSpec("0 */4 * * *")), "every 4 h")
        XCTAssertEqual(LoopSchedule.words(CronSpec("30 2 * * *")), "nightly 2:30")
        XCTAssertEqual(LoopSchedule.words(CronSpec("0 17 * * 5")), "Fri 17:00")
        XCTAssertEqual(LoopSchedule.words(CronSpec("0 9 1 * *")), "monthly 1st 9:00")
        XCTAssertEqual(LoopSchedule.words(nil), "manual")
        let l = Loop(id: "triage-inbox", name: "triage-inbox", origin: .builtIn, goal: "g", check: "c", repoPath: "/r", agent: .claude,
                     trigger: .at(hour: 2, minute: 0), limits: LoopLimits(maxRounds: 1, maxDuration: 60, sameFailureStop: 2), pinned: false, state: .stopped, createdAt: Date())
        XCTAssertNil(LoopSchedule.cron(l, kit: KitLoopStatus(name: l.id, on: false, schedule: "manual")), "the kit says manual: not the catalog's 2:00")
        XCTAssertNotNil(LoopSchedule.cron(l, kit: nil), "no kit state: the catalog trigger")
    }

    func run(_ loop: String, _ t: String, _ r: LoopRun7.Result = .passed) -> LoopRun7 {
        LoopRun7(id: loop + t, loop: loop, engine: .kit, started: at(t), ended: at(t).addingTimeInterval(5), result: r, cost: 0, summary: "")
    }

    /// Fleet sweep: on (trial), nightly 1:00, ran once by hand on Nov 1 and never again → 5 missed nights by Nov 6 10:35.
    func testFleetSweepMissesFiveNights() {
        let l = Loop(id: "fleet-sweep", name: "fleet-sweep", origin: .builtIn, goal: "g", check: "c", repoPath: "/r", agent: .claude,
                     trigger: .at(hour: 1, minute: 0), limits: LoopLimits(maxRounds: 1, maxDuration: 60, sameFailureStop: 2),
                     pinned: false, state: .stopped, createdAt: Date()).with { $0.kind = "sentinel" }
        let rows = LoopsV7.rows(loops: [l], kit: [KitLoopStatus(name: "fleet-sweep", on: true, mode: "shadow", schedule: "0 1 * * *", scheduler: "launchd")],
                                runs: ["fleet-sweep": [run("fleet-sweep", "2026-11-01 08:51", .trial)]], now: at("2026-11-06 10:35"), calendar: cal)
        let r = rows[0]
        XCTAssertEqual(r.missed, 5); XCTAssertEqual(r.state, .missed); XCTAssertEqual(r.family, "watch"); XCTAssertEqual(r.mode, .shadow)
        XCTAssertEqual(r.strip, [.trial, .missed, .missed, .missed, .missed, .missed])
        XCTAssertEqual(r.nextRun, at("2026-11-07 01:00"))
    }

    func testHourlyLoopWithEveryRunIsFineAndNotMissed() {
        let l = Loop(id: "cost-watch", name: "cost-watch", origin: .builtIn, goal: "g", check: "c", repoPath: "/r", agent: .claude,
                     trigger: .at(hour: 9, minute: 0), limits: LoopLimits(maxRounds: 1, maxDuration: 60, sameFailureStop: 2),
                     pinned: false, state: .stopped, createdAt: Date())
        let rs = (9...10).map { run("cost-watch", String(format: "2026-11-06 %02d:00", $0)).with5s() }
        let r = LoopsV7.rows(loops: [l], kit: [KitLoopStatus(name: "cost-watch", on: true, mode: "live", schedule: "0 9-23 * * *", scheduler: "launchd")],
                             runs: ["cost-watch": rs], now: at("2026-11-06 10:35"), calendar: cal)[0]
        XCTAssertEqual(r.missed, 0); XCTAssertEqual(r.state, .fine); XCTAssertEqual(r.schedule, "hourly 9–23"); XCTAssertEqual(r.nextRun, at("2026-11-06 11:00"))
    }

    func testFailedLastRunIsFailingAndOffLoopIsOff() {
        let l = Loop(id: "nightly-reflection", name: "nightly-reflection", origin: .builtIn, goal: "g", check: "c", repoPath: "/r", agent: .claude,
                     trigger: .at(hour: 2, minute: 30), limits: LoopLimits(maxRounds: 1, maxDuration: 60, sameFailureStop: 2),
                     pinned: false, state: .stopped, createdAt: Date())
        let kit = [KitLoopStatus(name: l.id, on: true, mode: "live", schedule: "30 2 * * *", scheduler: "launchd")]
        let r = LoopsV7.rows(loops: [l], kit: kit, runs: [l.id: [run(l.id, "2026-11-05 02:30", .failed), run(l.id, "2026-11-06 02:30", .failed)]],
                             now: at("2026-11-06 10:35"), calendar: cal)[0]
        XCTAssertEqual(r.state, .failing); XCTAssertEqual(r.family, "other")
        let off = LoopsV7.rows(loops: [l], kit: [KitLoopStatus(name: l.id, on: false)], runs: [:], now: at("2026-11-06 10:35"), calendar: cal)[0]
        XCTAssertEqual(off.state, .off); XCTAssertNil(off.nextRun); XCTAssertEqual(off.missed, 0)
    }

    // LP-8 / LP-9
    func testWeekCellsCountRunsMissedAndToCome() {
        let rs = [run("w", "2026-11-05 17:00"), run("w", "2026-11-06 09:00"), run("w", "2026-11-06 10:00", .failed)]
        let row = LoopRow(id: "w", name: "w", family: "watch", kind: nil, mine: false, engine: .kit, on: true, mode: .live, state: .fine,
                          schedule: "", goal: "", lastRun: nil, nextRun: nil, strip: [], missed: 0, firstMissed: nil)
        let w = LoopsV7.week(row: row, runs: rs, cron: CronSpec("0 9-23 * * *"), now: at("2026-11-06 10:35"), calendar: cal)
        XCTAssertEqual(w.count, 7); XCTAssertEqual(w.last?.passed, 1); XCTAssertEqual(w.last?.failed, 1)
        XCTAssertEqual(w.last?.toCome, 13, "11:00 … 23:00")
        XCTAssertEqual(w[5].missed, 6, "Nov 5 18:00–23:00 had no run after the first one at 17:00")
        let d = LoopsV7.day(runs: rs, cron: CronSpec("0 9-23 * * *"), on: true, dayStart: at("2026-11-06 00:00"), dayEnd: at("2026-11-07 00:00"), now: at("2026-11-06 10:35"), calendar: cal)
        XCTAssertEqual(d.filter { $0.result == .toCome }.count, 13); XCTAssertEqual(d.first?.result, .passed)
    }

    func testNeedsCountIsOnePerDecision() {
        func o(_ id: Int, _ run: String, _ kind: String) -> LoopLedger.Outcome {
            LoopLedger.Outcome(id: id, runId: run, loop: "x", kind: kind, link: "", title: "", status: "staged", decidedBy: nil, decidedAt: nil, created: "", detail: "")
        }
        let staged = [o(1, "r1", "commit"), o(2, "r1", "commit"), o(3, "r1", "commit"), o(4, "r1", "commit"),
                      o(5, "r2", "proposal"), o(6, "r2", "proposal"), o(7, "r3", "report"), o(8, "r4", "promotion")]
        // LAB-2286: a staged promotion is the kit asking "go live?" (auto-live ones are written as applied), so it counts.
        XCTAssertEqual(LoopsV7.needsCount(staged: staged, questions: 1, failures: 0, missedLoops: 1), 1 + 2 + 1 + 1 + 1 + 1)
    }

    // LP-4 · LP-14
    func testLedgerRunMapsResultsAndDuration() {
        let r = LoopRun7(LoopLedger.Run(id: "a", loop: "l", engine: "ae", mode: "live", started: "2026-11-06T12:00:09-08:00", ended: "2026-11-06T12:00:15-08:00", result: "pass", cost: 0, summary: ""))!
        XCTAssertEqual(r.result, .passed); XCTAssertEqual(r.seconds, 6); XCTAssertEqual(r.engine, .kit)
        XCTAssertEqual(LoopRun7(LoopLedger.Run(id: "b", loop: "l", engine: "ae", mode: "shadow", started: "2026-11-03T09:00:05-08:00", ended: "", result: "dry", cost: nil, summary: ""))?.result, .trial)
        XCTAssertEqual(LoopRun7(LoopLedger.Run(id: "c", loop: "l", engine: "roofd", mode: "live", started: "2026-11-06T11:00:00Z", ended: "", result: "failed", cost: nil, summary: ""))?.engine, .oneRoof)
    }

    // LP-10
    func testReportParses() {
        let md = """
        # Mac resource watch · run

        **Loop:** my-mac-resource-watch (Mine) · **Run:** r-20261106-102107-2365 · **Agent:** none · **Result:** pass

        > Goal: This Mac keeps memory headroom.

        ## Timeline

        | t | step | what |
        |---|---|---|
        | 0.00s | trigger | by hand · schedule */10 * * * * · scheduler launchd |
        | 1.16s | check | pass (exit 0) · OK: headroom fine, no leftovers |
        | 1.16s | stop | check passed on iteration 1 |

        ## Findings

        - none

        ## Would do

        - nothing to propose
        """
        let r = LoopReport.parse(md)
        XCTAssertEqual(r.title, "Mac resource watch · run"); XCTAssertEqual(r.meta["Result"], "pass"); XCTAssertEqual(r.meta["Run"], "r-20261106-102107-2365")
        XCTAssertEqual(r.goal, "This Mac keeps memory headroom.")
        XCTAssertEqual(r.steps.count, 3); XCTAssertEqual(r.steps[0].what, "by hand · schedule */10 * * * * · scheduler launchd")
        XCTAssertEqual(r.result, "pass (exit 0) · OK: headroom fine, no leftovers")
        XCTAssertEqual(r.findings, []); XCTAssertEqual(r.sections.first?.title, "Would do")
    }
}

private extension LoopRun7 { func with5s() -> LoopRun7 { var r = self; r.started = r.started.addingTimeInterval(5); return r } }

/// Real data on this Mac (ONEROOF_V7_SMOKE=1 only): the rows the screens would draw now.
final class LoopsV7RealDataSmoke: XCTestCase {
    func testPrintRealRows() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["ONEROOF_V7_SMOKE"] == "1")
        let root = LoopStore.defaultRoot
        let store = LoopStore(root: root, builtIns: LoopBuiltIns.load(repoPath: Workspace.projectsRoot), fileLoops: LoopFiles.load(folder: root, repoPath: Workspace.projectsRoot))
        let kit = KitLoops.read()
        let led = try LoopLedger(readingOnly: LoopLedger.defaultPath(loopsRoot: root))
        let runs = Dictionary(grouping: led.runs(from: Date().addingTimeInterval(-8 * 86400), to: Date(), limit: 5000).compactMap(LoopRun7.init), by: \.loop)
        let rows = LoopsV7.rows(loops: store.all(), kit: kit, runs: runs)
        print("kit rows:", kit?.count ?? -1, "loops:", rows.count, "on:", rows.filter(\.on).count)
        for r in rows.sorted(by: { ($0.on ? 0 : 1, $0.family, $0.name) < ($1.on ? 0 : 1, $1.family, $1.name) }) {
            print(String(format: "%-34@ %-8@ %-6@ %-7@ %-8@ miss %2d  %@  %@", r.name as NSString, r.family as NSString, r.engine.rawValue as NSString,
                         (r.mode?.rawValue ?? "-") as NSString, r.state.rawValue as NSString, r.missed, r.schedule as NSString,
                         r.strip.map { ["passed": "✓", "failed": "✗", "trial": "·", "missed": "○", "toCome": "_", "notRun": "-"][$0.rawValue]! }.joined()))
        }
    }
}
