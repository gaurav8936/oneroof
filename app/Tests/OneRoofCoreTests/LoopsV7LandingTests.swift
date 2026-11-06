import XCTest
@testable import OneRoofCore

/// LAB-2286 · Loops v7 7a (kinds as lanes), the shell's lines, the one filter, the one Needs you count, and the kind
/// and state colours.
final class LoopsV7LandingTests: XCTestCase {
    var cal: Calendar = { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "America/Los_Angeles")!; return c }()
    func at(_ s: String) -> Date { var c = cal; c.locale = Locale(identifier: "en_US_POSIX")
        let f = DateFormatter(); f.calendar = c; f.timeZone = c.timeZone; f.dateFormat = "yyyy-MM-dd HH:mm"; return f.date(from: s)! }
    var now: Date { at("2026-11-06 10:35") }   // a Friday

    func loop(_ id: String, kind: String?, state: LoopState = .stopped, kitFile: Bool = true, goal: String = "g") -> Loop {
        Loop(id: id, name: id, origin: .builtIn, goal: goal, check: "c", repoPath: "/r", agent: .claude, trigger: .untilDone(everyMinutes: 0),
             limits: LoopLimits(maxRounds: 1, maxDuration: 60, sameFailureStop: 2), pinned: false, state: state, createdAt: Date())
            .with { $0.kind = kind; $0.specFile = kitFile ? "/k/\(id).loop.yaml" : nil }
    }
    func run(_ loop: String, _ t: String, _ r: LoopRun7.Result = .passed, summary: String = "") -> LoopRun7 {
        LoopRun7(id: loop + t, loop: loop, engine: .kit, started: at(t), ended: at(t).addingTimeInterval(5), result: r, cost: 0.01, summary: summary)
    }
    func outcome(_ id: Int, _ loop: String, _ run: String, _ kind: String, status: String = "staged") -> LoopLedger.Outcome {
        LoopLedger.Outcome(id: id, runId: run, loop: loop, kind: kind, link: "", title: "t\(id)", status: status, decidedBy: nil, decidedAt: nil,
                           created: "2026-11-04T06:00:00-08:00", detail: "")
    }

    /// Mac resource watch (every 10 min, live), Fleet sweep (trial, missed), Docs drift (check, staged), Nightly
    /// reflection (improve, failing), nightly bugs (One Roof, Other, failing, commits), Perf guard (off), Agent X-ray (trial, no run).
    func fixture() -> (rows: [LoopRow], items: [LoopInbox.Item], loops: [Loop]) {
        let loops = [loop("my-mac-resource-watch", kind: "sentinel"), loop("fleet-sweep", kind: "sentinel"), loop("perf-guard", kind: "sentinel", goal: "Watch app speed. More."),
                     loop("docs-drift", kind: "auditor"), loop("nightly-reflection", kind: "learner"),
                     loop("oneroof-nightly-bugs", kind: nil, state: .waiting, kitFile: false), loop("agent-xray", kind: nil)]
        let kit = [KitLoopStatus(name: "my-mac-resource-watch", on: true, mode: "live", schedule: "*/10 * * * *", scheduler: "launchd"),
                   KitLoopStatus(name: "fleet-sweep", on: true, mode: "shadow", schedule: "0 1 * * *", scheduler: "launchd"),
                   KitLoopStatus(name: "perf-guard", on: false, schedule: "0 4 * * *"),
                   KitLoopStatus(name: "docs-drift", on: true, mode: "live", schedule: "0 6 * * *", scheduler: "launchd"),
                   KitLoopStatus(name: "nightly-reflection", on: true, mode: "live", schedule: "30 2 * * *", scheduler: "launchd"),
                   KitLoopStatus(name: "oneroof-nightly-bugs", on: true, mode: "", schedule: "0 3 * * *", scheduler: "roofd"),
                   KitLoopStatus(name: "agent-xray", on: true, mode: "shadow", schedule: "30 16 * * 5", scheduler: "launchd")]
        var runs: [String: [LoopRun7]] = [:]
        runs["my-mac-resource-watch"] = stride(from: 0, through: 150, by: 10).map { m in
            run("my-mac-resource-watch", String(format: "2026-11-06 %02d:%02d", 8 + (m + 5) / 60, (m + 5) % 60), summary: "Mac resource watch: pass, 0 finding(s)") }
        runs["fleet-sweep"] = [run("fleet-sweep", "2026-11-01 08:51", .trial)]
        runs["docs-drift"] = ["2026-11-04 06:00", "2026-11-05 06:00", "2026-11-06 06:00"].map { run("docs-drift", $0, summary: "Docs drift: pass, 5 finding(s)") }
        runs["nightly-reflection"] = [run("nightly-reflection", "2026-11-05 02:30", .failed), run("nightly-reflection", "2026-11-06 02:30", .failed)]
        runs["oneroof-nightly-bugs"] = ["2026-11-04 03:00", "2026-11-05 03:00", "2026-11-06 03:00"].map { LoopRun7(id: $0, loop: "oneroof-nightly-bugs", engine: .oneRoof, started: at($0), ended: nil, result: .failed, cost: nil, summary: "The same failure twice in a row") }
        let rows = LoopsV7.rows(loops: loops, kit: kit, runs: runs, now: now, calendar: cal)
        let staged = [outcome(1, "oneroof-nightly-bugs", "rb", "commit"), outcome(2, "oneroof-nightly-bugs", "rb", "commit"),
                      outcome(3, "docs-drift", "r1", "proposal"), outcome(4, "docs-drift", "r1", "report"), outcome(5, "docs-drift", "r2", "proposal"),
                      outcome(6, "nightly-reflection", "r3", "proposal"), outcome(7, "nightly-reflection", "r3", "proposal"),
                      outcome(8, "docs-drift", "r1", "report", status: "applied")]
        let items = LoopInbox.items(loops: loops, staged: staged, rows: rows)
        return (rows, items, loops)
    }

    // D · one Needs you count everywhere
    func testNeedsCountIsTheItemsAndAgreesWithTheLedgerCount() {
        let f = fixture()
        // 1 PR (two commits of one run) + 3 docs-drift + 2 reflection + 1 missed loop (Fleet sweep).
        XCTAssertEqual(LoopsV7.needsCount(items: f.items), 7)
        XCTAssertEqual(f.items.filter { $0.kind == .missed }.map(\.loopId), ["fleet-sweep"])
        let staged = f.items.flatMap(\.outcomes)
        XCTAssertEqual(LoopsV7.needsCount(staged: staged, questions: 0, failures: 0, missedLoops: f.rows.filter { $0.state == .missed }.count),
                       LoopsV7.needsCount(items: f.items), "the landing chip and the rail badge read the same number")
        XCTAssertEqual(LoopsV7.statusCounts(rows: f.rows, items: f.items).needYou, LoopsV7.needsCount(items: f.items))
        // The Inbox badge counts the same loop items (no manual sessions here): the rail's Loops badge, the landing
        // chip and the Inbox agree.
        XCTAssertEqual(SessionScope.needsYouCount(openAsks: 0, plansWaiting: 0, items: [], loopItems: f.items.count), LoopsV7.needsCount(items: f.items))
    }

    func testStagedPromotionIsOneDecisionAppliedOneIsNot() {
        let staged = [outcome(1, "x", "r", "promotion"), outcome(2, "y", "s", "promotion", status: "applied")]
        let items = LoopInbox.items(loops: [], staged: staged)
        XCTAssertEqual(LoopsV7.needsCount(items: items), 1)
        XCTAssertEqual(LoopsV7.needsCount(staged: staged, questions: 0, failures: 0, missedLoops: 0), 1)
    }

    func testEstimateIsLabelledPerKind() {
        let f = fixture()
        // 1 PR 5 min + 4 proposals 1 min + 1 report 30 s + 1 missed 30 s = 600 s.
        XCTAssertEqual(LoopsV7.estimateSeconds(f.items), 300 + 4 * 60 + 30 + 30)
        XCTAssertEqual(LoopsV7.estimateLabel(600), "~10 min")
        XCTAssertEqual(LoopsV7.estimateLabel(0), "")
    }

    // C · lanes
    func testLanesCountOnAndAllAndListOnlyLoopsThatAreOn() {
        let lanes = LoopsV7.lanes(rows: fixture().rows, items: fixture().items, now: now, calendar: cal)
        XCTAssertEqual(lanes.map(\.id), ["watch", "check", "improve", "report", "other"])
        let watch = lanes[0]
        XCTAssertEqual(watch.on, 2); XCTAssertEqual(watch.all, 3)
        XCTAssertEqual(watch.rows.map(\.id), ["my-mac-resource-watch", "fleet-sweep"], "the next to run first; the off loop is not listed")
        XCTAssertEqual(lanes[3].on, 0); XCTAssertEqual(lanes[3].all, 0)
        XCTAssertEqual(lanes[4].on, 2, "One Roof's nightly bugs and the trial X-ray")
    }

    func testForYouAsksAndGaps() {
        let f = fixture()
        let lanes = LoopsV7.lanes(rows: f.rows, items: f.items, setupMissing: [], now: now, calendar: cal)
        let watch = lanes[0], check = lanes[1], improve = lanes[2], other = lanes[4]
        XCTAssertEqual(watch.asks.map(\.text), ["fleet-sweep: 5 nights missed"])
        XCTAssertEqual(watch.asks.first?.action, .runNow("fleet-sweep")); XCTAssertEqual(watch.asks.first?.primary, false)
        XCTAssertEqual(watch.gaps.first?.button, "Turn on"); XCTAssertEqual(watch.gaps.first?.text, "perf-guard is off")
        XCTAssertEqual(watch.gaps.first?.detail, "watch app speed")
        XCTAssertEqual(check.asks.first?.text, "docs-drift: 2 proposals, 1 report"); XCTAssertEqual(check.asks.first?.button, "Review 3")
        XCTAssertTrue(check.asks.first!.primary)
        XCTAssertEqual(improve.asks.first?.text, "nightly-reflection failed 2 nights in a row: 2 proposals waiting")
        XCTAssertEqual(improve.asks.first?.button, "Review 2")
        XCTAssertEqual(other.asks.map(\.button), ["Open", "Review PR", "Set kind"])
        XCTAssertEqual(other.asks[1].text, "2 commits waiting since Nov 4")
        XCTAssertEqual(other.asks.last?.action, .setKind(["oneroof-nightly-bugs", "agent-xray"]))
        let needsSetup = LoopsV7.lanes(rows: f.rows, items: f.items, setupMissing: ["perf-guard"], now: now, calendar: cal)[0]
        XCTAssertEqual(needsSetup.gaps.first?.button, "Set up")
        XCTAssertTrue(LoopsV7.lanes(rows: f.rows, items: f.items, kitKnown: false, now: now, calendar: cal)[0].gaps.isEmpty, "kit unread: off is not known")
    }

    func testLastNextByLines() {
        let rows = Dictionary(uniqueKeysWithValues: fixture().rows.map { ($0.id, $0) })
        XCTAssertEqual(LoopsV7.lastNextBy(rows["my-mac-resource-watch"]!, now: now, calendar: cal).text, "10:35 · every 10 min · by kit")
        XCTAssertEqual(LoopsV7.lastNextBy(rows["docs-drift"]!, now: now, calendar: cal).text, "6:00 · 6:00 tmrw · by kit")
        let fs = LoopsV7.lastNextBy(rows["fleet-sweep"]!, now: now, calendar: cal)
        XCTAssertEqual(fs.text, "missed · 1:00 tmrw · by kit"); XCTAssertEqual(fs.tone, .missed)
        let nr = LoopsV7.lastNextBy(rows["nightly-reflection"]!, now: now, calendar: cal)
        XCTAssertEqual(nr.text, "fail 2:30 · 2:30 tmrw · by kit"); XCTAssertEqual(nr.tone, .failed)
        XCTAssertEqual(LoopsV7.lastNextBy(rows["oneroof-nightly-bugs"]!, now: now, calendar: cal).text, "fail 3:00 · 3:00 tmrw · by One Roof")
        XCTAssertEqual(LoopsV7.lastNextBy(rows["agent-xray"]!, now: now, calendar: cal).text, "first trial 16:30 · by kit")
        XCTAssertEqual(LoopsV7.lastNextBy(rows["docs-drift"]!, kitKnown: false, now: now, calendar: cal).text, "6:00 · 6:00 tmrw · kit state unknown")
    }

    func testSubLinesInPlainWords() {
        let rows = Dictionary(uniqueKeysWithValues: fixture().rows.map { ($0.id, $0) })
        XCTAssertEqual(LoopsV7.subLine(rows["my-mac-resource-watch"]!, calendar: cal), "no finding")
        XCTAssertEqual(LoopsV7.subLine(rows["docs-drift"]!, calendar: cal), "5 findings")
        XCTAssertEqual(LoopsV7.subLine(rows["fleet-sweep"]!, calendar: cal), "no run since Nov 1 · 5 missed")
        XCTAssertEqual(LoopsV7.subLine(rows["agent-xray"]!, calendar: cal), "trial runs before going live")
        XCTAssertEqual(LoopsV7.subLine(rows["oneroof-nightly-bugs"]!, calendar: cal), "The same failure twice in a row")
    }

    // B · shell lines
    func testWeekLineAndStatusBar() {
        let f = fixture()
        let runs = [run("a", "2026-11-05 10:00"), run("a", "2026-11-06 09:00", .failed), run("b", "2026-11-06 09:30", .failed), run("c", "2026-10-29 09:00")]
        XCTAssertEqual(LoopsV7.weekLine(runs: runs, now: now), "This week: 3 runs · $0.03 · 2 failed (2 loops)")
        XCTAssertEqual(LoopsV7.statusBar(rows: f.rows, now: now, calendar: cal), "6 loops on · next: my-mac-resource-watch 10:40")
        XCTAssertEqual(LoopsV7.statusBar(rows: [], now: now, calendar: cal), "no loops on")
        XCTAssertEqual(LoopsV7.when(at("2026-11-07 07:30"), now: now, calendar: cal), "7:30 tmrw")
        XCTAssertEqual(LoopsV7.when(at("2026-11-10 08:00"), now: now, calendar: cal), "Tue 8:00")
        XCTAssertEqual(LoopsV7.when(at("2026-11-20 08:00"), now: now, calendar: cal), "Nov 20")
    }

    // B · the one filter
    func testFilterSearchKindStateAndEmptyLine() {
        let rows = fixture().rows
        XCTAssertEqual(LoopsV7.filter(rows, LoopFilter(query: "app speed")).map(\.id), ["perf-guard"], "search reads what it does")
        XCTAssertEqual(Set(LoopsV7.filter(rows, LoopFilter(query: "sentinel")).map(\.id)), ["my-mac-resource-watch", "fleet-sweep", "perf-guard"], "and its kind")
        XCTAssertEqual(LoopsV7.filter(rows, LoopFilter(family: "check")).map(\.id), ["docs-drift"])
        XCTAssertEqual(Set(LoopsV7.filter(rows, LoopFilter(state: .failing)).map(\.id)), ["nightly-reflection", "oneroof-nightly-bugs"])
        XCTAssertEqual(Set(LoopsV7.filter(rows, LoopFilter(state: .trial)).map(\.id)), ["fleet-sweep", "agent-xray"])
        XCTAssertEqual(LoopsV7.filter(rows, LoopFilter(state: .off)).map(\.id), ["perf-guard"])
        XCTAssertEqual(LoopsV7.filter(rows, LoopFilter()).count, rows.count)
        let none = LoopFilter(query: "zzz", family: "watch", state: .failing)
        XCTAssertTrue(LoopsV7.filter(rows, none).isEmpty)
        XCTAssertEqual(LoopsV7.emptyLine(none), "No loop matches “zzz” · Watch · failing.")
        XCTAssertTrue(LoopFilter(query: "  ").isEmpty)
    }

    // LP-1 · LAB-2278: on/off and mode words from the engine
    func testOnLabelsFromTheEngine() {
        let rows = Dictionary(uniqueKeysWithValues: fixture().rows.map { ($0.id, $0) })
        XCTAssertEqual(LoopLook.onLabel(rows["my-mac-resource-watch"]!, kitKnown: true), "On · live")
        XCTAssertEqual(LoopLook.onLabel(rows["fleet-sweep"]!, kitKnown: true), "On · trial")
        XCTAssertEqual(LoopLook.onLabel(rows["perf-guard"]!, kitKnown: true), "Off")
        XCTAssertEqual(LoopLook.onLabel(rows["docs-drift"]!, kitKnown: false), "kit state unknown")
        XCTAssertNil(LoopLook.onLabel(rows["oneroof-nightly-bugs"]!, kitKnown: true), "a One Roof loop keeps its own state chip")
        XCTAssertEqual(LoopLook.onTone(rows["fleet-sweep"]!, kitKnown: true), .needsYou)
        XCTAssertEqual(LoopLook.onTone(rows["agent-xray"]!, kitKnown: true), .trial)
    }

    func testKitCacheReadsAtMostOncePerWindow() {
        final class Counter: @unchecked Sendable { var n = 0 }
        let c = Counter()
        let cache = KitLoopsCache { c.n += 1; return [KitLoopStatus(name: "a", on: true)] }
        let t0 = Date()
        _ = cache.get(maxAge: 30, now: t0); _ = cache.get(maxAge: 30, now: t0.addingTimeInterval(10))
        XCTAssertEqual(c.n, 1)
        _ = cache.get(maxAge: 30, now: t0.addingTimeInterval(31)); XCTAssertEqual(c.n, 2)
        cache.invalidate(); _ = cache.get(maxAge: 30, now: t0.addingTimeInterval(32)); XCTAssertEqual(c.n, 3)
        let unknown = KitLoopsCache { nil }
        XCTAssertNil(unknown.get())
    }

    // Colours: kind text on its fill and on the card 4.5:1; state text on its fill 4.5:1; strip marks 3:1 on the card.
    func testKindAndStateColoursReadInEveryLook() {
        for theme in [ThemeName.daylight, .graphite, .midnight, .sky, .mint, .lavender, .peach] {
            let card = theme.tokens.surface
            for f in LoopsV7.laneOrder {
                let p = LoopLook.kind(f, theme: theme)
                XCTAssertGreaterThanOrEqual(RGB.contrast(p.text, p.fill), 4.5, "\(theme) \(f) on fill")
                XCTAssertGreaterThanOrEqual(RGB.contrast(p.text, card), 4.5, "\(theme) \(f) on card")
            }
            for s in LoopLook.Tone.allCases {
                let p = LoopLook.tone(s, theme: theme)
                XCTAssertGreaterThanOrEqual(RGB.contrast(p.text, p.fill), 4.5, "\(theme) \(s)")
            }
            for r in [LoopRun7.Result.passed, .failed] {
                XCTAssertGreaterThanOrEqual(RGB.contrast(LoopLook.strip(r, theme: theme).fill!, card), 3, "\(theme) \(r) mark")
            }
            if case .dashed(let c) = LoopLook.strip(.missed, theme: theme).edge { XCTAssertGreaterThanOrEqual(RGB.contrast(c, card), 3, "\(theme) missed") }
        }
    }
}
