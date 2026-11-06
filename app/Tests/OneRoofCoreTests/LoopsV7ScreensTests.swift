import XCTest
@testable import OneRoofCore

/// LAB-2291 · LAB-2292 · LAB-2293 · Loops v7 lane B: 7e This week (range, cells, tiles, the "Is it worth it?" sentence),
/// 7f Today (lanes, headline, next up, while you slept), 7g Tonight, 7j the runs feed and a run's steps, 7k a report's
/// meaning, findings and tags.
final class LoopsV7ScreensTests: XCTestCase {
    var cal: Calendar = { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "America/Los_Angeles")!; return c }()
    func at(_ s: String) -> Date {
        let f = DateFormatter(); f.calendar = cal; f.locale = Locale(identifier: "en_US_POSIX"); f.timeZone = cal.timeZone
        f.dateFormat = "yyyy-MM-dd HH:mm"; return f.date(from: s)!
    }
    var now: Date { at("2026-11-06 10:35") }   // a Friday

    func row(_ id: String, family: String = "watch", engine: LoopEngine = .kit, on: Bool = true, mode: LoopMode? = .live,
             state: LoopRow.State = .fine, schedule: String = "nightly 2:00", strip: [LoopRun7.Result] = [], last: LoopRun7? = nil) -> LoopRow {
        LoopRow(id: id, name: id.capitalized, family: family, kind: nil, mine: false, engine: engine, on: on, mode: on ? mode : nil, state: state,
                schedule: schedule, goal: "", lastRun: last, nextRun: nil, strip: strip, missed: 0, firstMissed: nil)
    }
    func run(_ loop: String, _ t: String, _ r: LoopRun7.Result = .passed, engine: LoopEngine = .kit, cost: Double? = 0, summary: String = "",
             secs: Double = 5, id: String? = nil) -> LoopRun7 {
        LoopRun7(id: id ?? loop + t, loop: loop, engine: engine, started: at(t), ended: at(t).addingTimeInterval(secs), result: r, cost: cost, summary: summary)
    }

    // MARK: 7e

    func test_7e_weekRangeLabelAndHeads() {
        let w = LoopsV7.weekRange(offset: 0, now: now, calendar: cal)
        XCTAssertEqual(w.start, at("2026-10-31 00:00"))
        XCTAssertEqual(w.end, at("2026-11-07 00:00"))
        XCTAssertEqual(LoopsV7.weekLabel(start: w.start, end: w.end, calendar: cal), "Oct 31 – Nov 6")
        XCTAssertEqual(LoopsV7.dayHead(w.start, calendar: cal), "SAT 31")
        let back = LoopsV7.weekRange(offset: -1, now: now, calendar: cal)
        XCTAssertEqual(LoopsV7.weekLabel(start: back.start, end: back.end, calendar: cal), "Oct 24 – Oct 30")
        // Never a future week.
        XCTAssertEqual(LoopsV7.weekRange(offset: 2, now: now, calendar: cal).end, w.end)
    }

    func test_7e_cellsCountRunsMissedAndStillToCome() {
        let r = row("cost-watch")
        let cron = CronSpec("0 2,18 * * *")!
        let runs = [run("cost-watch", "2026-11-04 02:00"), run("cost-watch", "2026-11-04 18:00", .failed),
                    run("cost-watch", "2026-11-05 02:00", .trial), run("cost-watch", "2026-11-06 02:00")]
        let start = LoopsV7.weekRange(offset: 0, now: now, calendar: cal).start
        let cells = LoopsV7.weekCells(row: r, runs: runs, cron: cron, start: start, now: now, calendar: cal)
        XCTAssertEqual(cells.count, 7)
        XCTAssertEqual(cells.map { LoopsV7.ran($0) }, [0, 0, 0, 0, 2, 1, 1])
        XCTAssertEqual(cells[4].failed, 1)
        XCTAssertEqual(cells[5].trial, 1)
        XCTAssertEqual(cells[5].missed, 1, "Nov 5 18:00 had no run")
        XCTAssertEqual(cells[0].missed, 0, "before the first run seen nothing counts as missed")
        XCTAssertEqual(cells[6].toCome, 1, "18:00 today is still to come")
        // A loop that is off has no missed or to-come slots.
        let off = LoopsV7.weekCells(row: row("cost-watch", on: false), runs: runs, cron: cron, start: start, now: now, calendar: cal)
        XCTAssertEqual(off.reduce(0) { $0 + $1.missed + $1.toCome }, 0)
    }

    func test_7e_tilesAndAnswerFromRealNumbersOnly() {
        let rows = [row("a"), row("b"), row("c", on: false)]
        let runs = [run("a", "2026-11-05 02:00", cost: 0.10), run("a", "2026-11-06 02:00", cost: 0.05),
                    run("b", "2026-11-05 02:00", .failed, cost: nil), run("b", "2026-11-06 02:00", cost: nil),
                    run("c", "2026-11-03 09:00", .trial, cost: nil)]
        let cells = ["a": [LoopsV7.DayCell(day: now, missed: 2)], "b": [LoopsV7.DayCell(day: now)]]
        let s = LoopsV7.weekSummary(rows: rows, runs: runs, cells: cells, staged: 3)
        XCTAssertEqual(s.runs, 5)
        XCTAssertEqual(s.trialRuns, 1)
        XCTAssertEqual(s.offTrialRuns, 1)
        XCTAssertEqual(s.failed, 1)
        XCTAssertEqual(s.failedLoops, 1)
        XCTAssertEqual(s.missed, 2)
        XCTAssertEqual(s.missedLoops, 1)
        XCTAssertEqual(s.cost, 0.15, accuracy: 1e-9)
        XCTAssertTrue(s.costRecorded)
        XCTAssertEqual(s.answer, "Mostly: 1 loop passed every live run; B failed 1 of 2. 3 results still wait for you.")
        // Filtered to one loop: the answer follows the filter.
        let onlyA = LoopsV7.weekSummary(rows: [rows[0]], runs: runs, cells: cells, staged: 0)
        XCTAssertEqual(onlyA.answer, "Yes so far: all 2 live runs passed, but 2 scheduled runs were missed.")
        XCTAssertEqual(LoopsV7.weekSummary(rows: [rows[2]], runs: runs, cells: [:], staged: 0).answer,
                       "Too early to say: all 1 run was a trial, so nothing acted yet.")
        XCTAssertEqual(LoopsV7.weekSummary(rows: rows, runs: [], cells: [:], staged: 0).answer, "Nothing to judge yet: no runs this week.")
        let noCost = LoopsV7.weekSummary(rows: [rows[1]], runs: runs, cells: [:], staged: 0)
        XCTAssertFalse(noCost.costRecorded, "no recorded cost is never shown as $0.00")
        XCTAssertEqual(noCost.answer, "Not yet: B failed 1 of 2.")
    }

    func test_7e_gridRowsAreOnLoopsByKind() {
        let rows = [row("z", family: "other"), row("b", family: "check"), row("a", family: "watch"), row("off", on: false)]
        XCTAssertEqual(LoopsV7.weekRows(rows).map(\.id), ["a", "b", "z"])
    }

    // MARK: 7f

    func todayFixture() -> (rows: [LoopRow], runs: [String: [LoopRun7]], crons: [String: CronSpec]) {
        let rows = [row("mac", schedule: "every 10 min"), row("refl", family: "improve", state: .failing, strip: [.failed, .failed]),
                    row("sweep", mode: .shadow, state: .missed), row("xray", mode: .shadow, state: .trial), row("off", on: false)]
        let runs: [String: [LoopRun7]] = [
            "mac": [run("mac", "2026-11-06 10:10"), run("mac", "2026-11-06 10:20"), run("mac", "2026-11-06 10:30")],
            "refl": [run("refl", "2026-11-05 02:30", .failed), run("refl", "2026-11-06 02:30", .failed, summary: "Nightly reflection: fail, 4 finding(s)")],
            "sweep": [run("sweep", "2026-11-01 01:00", .trial)],
            "off": [run("off", "2026-11-06 09:00", .trial)],
        ]
        let crons = ["mac": CronSpec("*/10 * * * *")!, "refl": CronSpec("30 2 * * *")!, "sweep": CronSpec("0 1 * * *")!,
                     "xray": CronSpec("30 16 * * 5")!]
        return (rows, runs, crons)
    }

    func test_7f_lanesDotsBandMissedAndLabels() {
        let f = todayFixture()
        let day = cal.startOfDay(for: now)
        let lanes = LoopsV7.dayLanes(rows: f.rows, runs: f.runs, crons: f.crons, start: day, end: day.addingTimeInterval(86400), now: now, calendar: cal)
        XCTAssertEqual(lanes.map(\.row.id), ["mac", "sweep", "refl", "off", "xray"], "frequent first, then by first mark; an off loop that ran keeps its lane")
        XCTAssertEqual(lanes[0].band, "every 10 min →")
        XCTAssertFalse(lanes[0].marks.contains { $0.result == .toCome }, "a band instead of dots after now")
        XCTAssertEqual(lanes[1].marks.first?.result, .missed)
        XCTAssertEqual(lanes[1].marks.first?.label, "missed 1:00")
        XCTAssertEqual(lanes[2].marks.first?.label, "failed · 4 findings")
        XCTAssertNotNil(lanes[2].marks.first?.runId)
        XCTAssertEqual(lanes[4].marks.map(\.result), [.toCome])
        XCTAssertEqual(lanes[4].marks.first?.label, "16:30 first trial")
        // Last 24 h: yesterday's 2:30 failure is in the window.
        let l24 = LoopsV7.dayLanes(rows: f.rows, runs: f.runs, crons: f.crons, start: now.addingTimeInterval(-86400), end: now, now: now, calendar: cal)
        XCTAssertEqual(l24.first { $0.row.id == "refl" }?.marks.filter { $0.result == .failed }.count, 1)
        XCTAssertNil(l24.first?.band, "nothing is still to come in a window ending now")
    }

    func test_7f_headlineNextUpAndWhileYouSlept() {
        let f = todayFixture()
        let day = cal.startOfDay(for: now)
        let lanes = LoopsV7.dayLanes(rows: f.rows, runs: f.runs, crons: f.crons, start: day, end: day.addingTimeInterval(86400), now: now, calendar: cal)
        let h = LoopsV7.dayHeadline(lanes: lanes, start: day, end: day.addingTimeInterval(86400), now: now, calendar: cal)
        XCTAssertEqual(h.lead, "Friday Nov 6.")
        XCTAssertEqual(h.bold, "Overnight: 1 loop ran, 1 failed, 1 missed.")
        XCTAssertEqual(h.rest, " Since 8:00: 4 runs from Mac and Off.")
        let past = LoopsV7.dayHeadline(lanes: lanes, start: day.addingTimeInterval(-86400), end: day, now: now, calendar: cal)
        XCTAssertEqual(past.lead, "Thursday Nov 5.")

        let next = LoopsV7.departures(rows: f.rows, crons: f.crons, now: now, calendar: cal)
        XCTAssertEqual(next.map(\.loop), ["mac", "xray", "sweep", "refl"])
        XCTAssertEqual(next[0].tag, "in 5 min")
        XCTAssertEqual(next[1].tag, "trial")
        XCTAssertEqual(LoopsV7.timeToGo(at("2026-11-06 12:00"), now: now, calendar: cal), "in 1 h 25")
        XCTAssertEqual(LoopsV7.timeToGo(at("2026-11-06 17:00"), now: now, calendar: cal), "today")
        XCTAssertEqual(LoopsV7.timeToGo(at("2026-11-07 02:30"), now: now, calendar: cal), "tomorrow")

        let slept = LoopsV7.whileYouSlept(lanes: lanes, from: day, to: day.addingTimeInterval(8 * 3600), calendar: cal)
        XCTAssertEqual(slept.items.map(\.kind), [.failed, .missed])
        XCTAssertEqual(slept.items[0].line, "2 failed runs in a row: 4 findings")
        XCTAssertNotNil(slept.items[0].runId)
        XCTAssertEqual(slept.items[1].line, "missed 1:00 · on, but no run yet")
        XCTAssertEqual(slept.span.map { [$0.0, $0.1] }, [at("2026-11-06 01:00"), at("2026-11-06 02:30")])
    }

    // MARK: 7g

    func test_7g_tonightListsLoopsAndSessionsInTimeOrder() {
        let rows = [row("mac"), row("health"), row("stats", family: "report"), row("refl", state: .failing, strip: [.failed, .failed]),
                    row("sweep", mode: .shadow, state: .trial), row("off", on: false)]
        let crons = ["mac": CronSpec("*/10 * * * *")!, "health": CronSpec("30 7 * * *")!, "stats": CronSpec("30 7 * * *")!,
                     "refl": CronSpec("30 2 * * *")!, "sweep": CronSpec("0 1 * * *")!, "off": CronSpec("0 3 * * *")!]
        let w = LoopsV7.tonightWindow(now: now, calendar: cal)
        XCTAssertEqual(w.start, at("2026-11-06 18:00"))
        XCTAssertEqual(w.end, at("2026-11-07 08:00"))
        XCTAssertEqual(LoopsV7.tonightWindow(now: at("2026-11-06 02:00"), calendar: cal).end, at("2026-11-06 08:00"))
        let s = [LoopsV7.TonightSession(id: "s1", name: "tidy the changelog", line: "Claude in labs/oneroof", at: at("2026-11-07 01:30"), nightly: false)]
        let t = LoopsV7.tonight(rows: rows, crons: crons, sessions: s, now: now, calendar: cal)
        XCTAssertEqual(t.frequent, ["Mac (every 10 min)"])
        XCTAssertEqual(t.items.map(\.name), ["Sweep", "Session · tidy the changelog", "Refl", "Health · Stats"])
        XCTAssertEqual(t.items[0].tag, .trial)
        XCTAssertEqual(t.items[1].tag, .oneOff)
        XCTAssertEqual(t.items[2].tag, .failing)
        XCTAssertEqual(t.items[2].line, "failed the last 2 runs")
        XCTAssertEqual(LoopsV7.tonightHeadline(t.items, calendar: cal), "5 things run tonight, from 1:00 to 7:30.")
        XCTAssertEqual(LoopsV7.tonightHeadline([], calendar: cal), "Nothing is scheduled tonight.")
        // The scheduled session shows on the Today clock as a hollow dot.
        let lane = LoopsV7.sessionLane(s, start: at("2026-11-07 00:00"), end: at("2026-11-08 00:00"), calendar: cal)
        XCTAssertEqual(lane?.marks.map(\.result), [.toCome])
        XCTAssertEqual(lane?.marks.first?.label, "1:30 tidy the changelog")
        XCTAssertNil(LoopsV7.sessionLane(s, start: at("2026-11-06 00:00"), end: at("2026-11-07 00:00"), calendar: cal))
    }

    // MARK: 7j

    func test_7j_feedMergesKitAndRoofdRunsRoundsRunningAndMissed() {
        let rows = [row("mac"), row("bugs", family: "other", engine: .oneRoof), row("sweep", mode: .shadow)]
        let runs = [run("mac", "2026-11-06 10:30", secs: 9),
                    run("bugs", "2026-11-06 03:00", .failed, engine: .oneRoof, summary: "The same failure twice in a row (exit 1)", secs: 874, id: "roofd-bugs-feeb"),
                    run("bugs", "2026-11-05 03:00", .passed, engine: .oneRoof, summary: "Done: the check already passed", id: "roofd-bugs-aaaa"),
                    run("sweep", "2026-11-04 01:00", .trial)]
        let t0 = at("2026-11-06 03:00")
        let rounds: [String: [LoopRound]] = ["bugs": [
            LoopRound(kind: .check, runId: "feeb", n: 0, started: t0, ended: t0.addingTimeInterval(20), checkPassed: false, exitCode: 1, checkOutput: "x\nFAIL 2 tests"),
            LoopRound(kind: .round, runId: "feeb", n: 1, started: t0.addingTimeInterval(30), ended: t0.addingTimeInterval(400), sessionId: "s-1", agent: .claude, checkPassed: false),
            LoopRound(kind: .round, runId: "feeb", n: 2, started: t0.addingTimeInterval(410), ended: t0.addingTimeInterval(870), sessionId: "s-2", agent: .codex, checkPassed: false),
            LoopRound(kind: .stop, runId: "feeb", n: 0, started: t0.addingTimeInterval(874), ended: t0.addingTimeInterval(874), note: "same failure twice"),
            LoopRound(kind: .check, runId: "live", n: 0, started: at("2026-11-06 10:33"), ended: at("2026-11-06 10:34"), checkPassed: false),
        ]]
        let crons = ["sweep": CronSpec("0 1 * * *")!]
        let feed = LoopsV7.runsFeed(runs: runs, rounds: rounds, rows: rows, crons: crons, current: ["bugs": (id: "live", started: at("2026-11-06 10:33"))],
                                    from: now.addingTimeInterval(-7 * 86400), now: now, calendar: cal)
        XCTAssertEqual(feed.first?.result, .running)
        XCTAssertEqual(feed.first?.rounds, 0)
        let bugs = feed.first { $0.id == "roofd-bugs-feeb" }!
        XCTAssertEqual(bugs.result, .stopped)
        XCTAssertEqual(bugs.rounds, 2)
        XCTAssertEqual(feed.first { $0.id == "roofd-bugs-aaaa" }?.result, .done)
        XCTAssertEqual(feed.first { $0.loop == "mac" }?.result, .passed)
        XCTAssertNil(feed.first { $0.loop == "mac" }?.rounds)
        XCTAssertEqual(feed.filter { $0.result == .missed }.map { $0.started }, [at("2026-11-06 01:00"), at("2026-11-05 01:00")])
        XCTAssertEqual(LoopsV7.filterFeed(feed, rows: rows, filter: LoopFilter(), result: .failedOrStopped).map(\.id), ["roofd-bugs-feeb"])
        XCTAssertEqual(LoopsV7.filterFeed(feed, rows: rows, filter: LoopFilter(family: "other"), result: .any).count, 3)
        XCTAssertEqual(LoopsV7.filterFeed(feed, rows: rows, filter: LoopFilter(query: "swe"), result: .trial).count, 1)
        XCTAssertEqual(LoopsV7.feedCounts(feed, rounds: rounds, now: now), "1 running · 2 rounds this week · 4 runs")
        XCTAssertEqual(LoopsV7.feedLine(bugs, now: now, calendar: cal), "today · 3:00 → 3:14 · 2 rounds · by One Roof")
        XCTAssertEqual(LoopsV7.feedLine(feed.first { $0.loop == "mac" }!, now: now, calendar: cal), "today · 10:30 · 9 s · by kit")

        let steps = LoopsV7.runSteps(bugs, rounds: rounds["bugs"]!, report: nil, schedule: "nightly 3:00", calendar: cal)
        XCTAssertEqual(steps.map(\.title), ["Started on schedule", "Check before work", "Round 1 · Claude", "Round 2 · Codex", "Stopped"])
        XCTAssertEqual(steps[1].code, "FAIL 2 tests")
        XCTAssertEqual(steps[2].sessionId, "s-1")
        XCTAssertEqual(steps[1].tone, .fail)
        let running = LoopsV7.runSteps(feed[0], rounds: rounds["bugs"]!, report: nil, schedule: "nightly 3:00", check: "make test", calendar: cal)
        XCTAssertEqual(running.last?.tone, .running)
        let missed = feed.first { $0.result == .missed }!
        XCTAssertEqual(LoopsV7.runSteps(missed, rounds: [], report: nil, schedule: "nightly 1:00").map(\.title), ["Expected on schedule"])
        XCTAssertEqual(LoopsV7.roofdRunId("roofd-bugs-feeb", loop: "bugs"), "feeb")
        XCTAssertNil(LoopsV7.roofdRunId("r-20261106-1", loop: "bugs"))
    }

    // MARK: 7k

    static let perfGuard = """
    # Perf guard · dry run

    **Loop:** perf-guard (Built-in) · **Run:** r-20261104-193836-59b1 · **Agent:** none · **Result:** dry

    > Goal: The app is no slower than its recorded medians; a regression starts a fix round on the loop branch.

    ## Timeline

    | t | step | what |
    |---|---|---|
    | 0.00s | trigger | by hand (dry run) · schedule 0 4 * * * · scheduler launchd |
    | 0.00s | findings | 1 finding(s) |
    | 0.00s | would do | nothing to propose · read-only: nothing outside the journal is written |
    | 0.19s | check | pass (exit 0) · verify: pass |
    | 0.19s | stop | check passed on iteration 1 · rule: check passes, ≤ 1 iteration(s), ≤ 30 min |
    | 0.19s | notify | would send (on-breach via slack): [ae loop] perf-guard: dry · 1 finding(s) · 0 proposal(s) |

    ## Findings

    - [info] no commands configured: set loops.settings.perf-guard.commands ([{name, run, severity}]) for this workspace → recorded
    """

    static let reflection = """
    # Nightly reflection · run

    **Loop:** nightly-reflection (Built-in) · **Run:** r-1 · **Agent:** claude · **Result:** fail

    ## Timeline

    | t | step | what |
    |---|---|---|
    | 0.00s | trigger | scheduled · schedule 30 2 * * * · scheduler launchd |
    | 241.70s | agent | claude: exit None in 240.1s · cost not reported (plan) · timeout after 240s |
    | 242.89s | check | fail (exit 0) · verify: pass |
    | 487.74s | check | fail (exit 0) · verify: pass |
    | 487.74s | stop | max_iterations 2 reached; check still failing · rule: check passes |

    ## Findings

    - [info] 3 correction(s) in 24 user turn(s) → recorded
    - [medium] 'stop-or-undo' corrections happened 2 times today: a repeat → p-859b
    - [high] claude headless call failed: timeout after 240s → recorded
    """

    func test_7k_reportMeaningFindingsTagsAndIfLive() {
        let p = LoopReport.parse(Self.perfGuard)
        XCTAssertTrue(p.isTrial)
        XCTAssertEqual(p.totalTime, "0.2 s")
        XCTAssertEqual(p.parsedFindings.first?.severity, "info")
        XCTAssertEqual(p.parsedFindings.first?.outcome, "recorded")
        XCTAssertTrue(p.meaning.headline.hasPrefix("It ran, but it couldn't check anything"))
        XCTAssertTrue(p.meaning.why.contains("no commands configured"))
        XCTAssertEqual(p.ifLive.count, 2)
        XCTAssertTrue(p.ifLive[1].hasPrefix("Would send (on-breach via slack)"))
        XCTAssertEqual(p.steps.map { LoopReport.stepTag($0, trial: true) }, ["started", "info", "shadow", "pass", nil, "shadow"])
        XCTAssertEqual(LoopsV7.reportFacts(p, family: "watch", started: at("2026-11-04 19:38"), calendar: cal),
                       "Built-in · Watch · by hand · Nov 4, 19:38 · no agent")

        let r = LoopReport.parse(Self.reflection)
        XCTAssertEqual(r.resultWord, "fail")
        XCTAssertEqual(r.meaning.headline, "It failed: the agent ran out of time (timeout after 240s).")
        XCTAssertEqual(r.meaning.why, "claude headless call failed: timeout after 240s.")
        XCTAssertEqual(LoopReport.stepTag(r.steps[4], trial: false), "fail")

        let ok = LoopReport.parse(Self.reflection.replacingOccurrences(of: "**Result:** fail", with: "**Result:** pass")
            .replacingOccurrences(of: "- [high] claude headless call failed: timeout after 240s → recorded", with: "")
            .replacingOccurrences(of: "| 241.70s | agent | claude: exit None in 240.1s · cost not reported (plan) · timeout after 240s |\n", with: ""))
        XCTAssertEqual(ok.meaning.headline, "It passed, with 1 finding worth a look.")
        let clean = LoopReport.parse("# X · run\n\n**Result:** pass\n\n## Findings\n\n- [info] fine → recorded\n")
        XCTAssertEqual(clean.meaning.headline, "All clear: the check passed and nothing needs you.")

        XCTAssertNil(LoopsV7.reportPath("bugs/rounds.jsonl", roots: ["/j"], exists: { _ in true }), "roofd runs have no report file")
        XCTAssertEqual(LoopsV7.reportPath("runs/2026/11/a.md", roots: ["/j", "/k"], exists: { $0 == "/k/runs/2026/11/a.md" }), "/k/runs/2026/11/a.md")
        XCTAssertNil(LoopsV7.reportPath("runs/2026/11/a.md", roots: ["/j"], exists: { _ in false }))
    }
}
