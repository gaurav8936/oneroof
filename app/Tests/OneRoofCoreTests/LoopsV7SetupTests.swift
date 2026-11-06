import XCTest
@testable import OneRoofCore

/// LAB-2294 · LAB-2295 · Loops v7 lane C: 7h Library rows, filter and order; 7i kind guess and trial plan; 7m Set kind
/// (per engine, owner suggestions, the kit command) and the delete copy; 7n setup items, config line and banners.
final class LoopsV7SetupTests: XCTestCase {
    var cal: Calendar = { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "America/Los_Angeles")!; return c }()
    func at(_ s: String) -> Date {
        let f = DateFormatter(); f.calendar = cal; f.timeZone = cal.timeZone; f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd HH:mm"; return f.date(from: s)!
    }
    var now: Date { at("2026-11-06 10:35") }   // a Friday

    func loop(_ id: String, kind: String?, origin: LoopOrigin = .builtIn, kitFile: Bool = false, state: LoopState = .stopped,
              act: String? = nil, goal: String = "Keeps watch on swap. More words.") -> Loop {
        Loop(id: id, name: id, origin: origin, goal: goal, check: "c", repoPath: "/r", state: state, createdAt: at("2026-11-01 09:00"))
            .with { $0.kind = kind; $0.specFile = kitFile ? "/k/\(id).loop.yaml" : nil; $0.act = act }
    }

    func row(_ id: String, family: String, kind: String?, engine: LoopEngine = .kit, on: Bool, mode: LoopMode? = nil,
             state: LoopRow.State = .fine, schedule: String = "nightly 2:00", mine: Bool = false, goal: String = "Watches swap. More.") -> LoopRow {
        LoopRow(id: id, name: id, family: family, kind: kind, mine: mine, engine: engine, on: on, mode: mode, state: on ? state : .off,
                schedule: schedule, goal: goal, lastRun: nil, nextRun: nil, strip: [], missed: 0, firstMissed: nil)
    }

    // MARK: 7h

    func test_7h_STATE_words() {
        let live = row("a", family: "watch", kind: "sentinel", on: true, mode: .live)
        XCTAssertEqual(LoopsV7Setup.state(live, needsSetup: false, kitKnown: true).label, "on · live")
        XCTAssertEqual(LoopsV7Setup.state(row("b", family: "watch", kind: "sentinel", on: true, mode: .shadow, state: .trial), needsSetup: false, kitKnown: true).label, "on · trial")
        XCTAssertEqual(LoopsV7Setup.state(row("c", family: "watch", kind: "sentinel", on: true, mode: .live, state: .failing), needsSetup: false, kitKnown: true).tone, .failing)
        XCTAssertEqual(LoopsV7Setup.state(row("d", family: "watch", kind: "sentinel", on: false), needsSetup: false, kitKnown: true).label, "off")
        XCTAssertEqual(LoopsV7Setup.state(row("e", family: "watch", kind: "sentinel", on: false), needsSetup: true, kitKnown: true).label, "needs setup")
        // The kit could not be read: never a guessed off.
        XCTAssertEqual(LoopsV7Setup.state(row("f", family: "watch", kind: "sentinel", on: false), needsSetup: false, kitKnown: false).label, "kit state unknown")
        // One Roof's own loop: its first runs are labelled trial (LP-12, label only).
        let mine = row("g", family: "other", kind: nil, engine: .oneRoof, on: true, mode: .live)
        XCTAssertEqual(LoopsV7Setup.state(mine, needsSetup: false, kitKnown: false, oneRoofTrial: true).label, "on · trial")
        XCTAssertTrue(LoopsV7Setup.oneRoofTrial(on: true, runsSinceCreated: 2))
        XCTAssertFalse(LoopsV7Setup.oneRoofTrial(on: true, runsSinceCreated: 3))
        XCTAssertFalse(LoopsV7Setup.oneRoofTrial(on: false, runsSinceCreated: 0))
    }

    func test_7h_VIEW_columns() {
        let r = LoopsV7Setup.libraryRow(row("my-mac", family: "watch", kind: "sentinel", on: true, mode: .live, schedule: "every 10 min", mine: true),
                                        loop: nil, act: "prompt", needsSetup: false, kitKnown: true, file: "/k/my-mac.loop.yaml")
        XCTAssertEqual(r.kindWords, "Watch · Sentinel")
        XCTAssertEqual(r.originLine, "mine · by kit")
        XCTAssertEqual(r.watches, "watches swap")
        XCTAssertEqual(r.when, "every 10 min")
        XCTAssertEqual(r.mayAct, "prompt you")
        XCTAssertEqual(LoopsV7Setup.kindWords(family: "other", kind: nil), "Other · no kind")
        XCTAssertEqual(LoopsV7Setup.mayAct(act: "pr", kind: "auditor", engine: .kit), "proposals")
        XCTAssertEqual(LoopsV7Setup.mayAct(act: "none", kind: "learner", engine: .kit), "proposals")
        XCTAssertEqual(LoopsV7Setup.mayAct(act: "none", kind: "reporter", engine: .kit), "report")
        XCTAssertEqual(LoopsV7Setup.mayAct(act: nil, kind: nil, engine: .oneRoof), "commits")
        XCTAssertEqual(LoopsV7Setup.whoRuns(when: "nightly 3:00", engine: .oneRoof), "nightly 3:00, by One Roof (roofd), with the app open or closed.")
    }

    func test_7h_VIEW_whenForTriggersACronCannotSay() {
        let ev = loop("x", kind: nil, origin: .mine).with { $0.trigger = .onEvent("git.push") }
        XCTAssertEqual(LoopsV7Setup.when(row("x", family: "other", kind: nil, engine: .oneRoof, on: true, schedule: "manual"), loop: ev), "on git.push")
        let kit = loop("y", kind: nil, kitFile: true).with { $0.externalSchedule = "on linear.issue.created" }
        XCTAssertEqual(LoopsV7Setup.when(row("y", family: "other", kind: nil, on: false, schedule: "manual"), loop: kit), "on linear.issue.created")
        XCTAssertEqual(LoopsV7Setup.when(row("z", family: "watch", kind: nil, on: false, schedule: "manual"), loop: loop("z", kind: nil)), "manual")
    }

    func lib() -> [LoopsV7Setup.LibraryRow] {
        [LoopsV7Setup.libraryRow(row("cost-watch", family: "watch", kind: "sentinel", on: true, mode: .live), loop: nil, act: "issue", needsSetup: false, kitKnown: true, file: nil),
         LoopsV7Setup.libraryRow(row("perf-guard", family: "watch", kind: "sentinel", on: false, goal: "App speed vs recorded medians."), loop: nil, act: "issue", needsSetup: true, kitKnown: true, file: nil),
         LoopsV7Setup.libraryRow(row("docs-drift", family: "check", kind: "auditor", on: true, mode: .live), loop: nil, act: "pr", needsSetup: false, kitKnown: true, file: "/k/docs-drift.loop.yaml"),
         LoopsV7Setup.libraryRow(row("nightly-reflection", family: "improve", kind: "learner", on: true, mode: .live, state: .failing), loop: nil, act: "none", needsSetup: false, kitKnown: true, file: nil),
         LoopsV7Setup.libraryRow(row("oneroof-nightly-bugs", family: "other", kind: nil, engine: .oneRoof, on: true, mode: .live), loop: nil, act: nil, needsSetup: false, kitKnown: true, file: nil)]
    }

    func test_7h_SELECT_filterAndCounts() {
        let rows = lib()
        let counts = LoopsV7Setup.kindCounts(rows)
        XCTAssertEqual(counts.map(\.title), ["All", "Watch", "Check", "Improve", "Report", "Other"])
        XCTAssertEqual(counts.map(\.count), [5, 2, 1, 1, 0, 1])
        XCTAssertEqual(LoopsV7Setup.filter(rows, query: "", family: "watch", state: nil).map(\.id), ["cost-watch", "perf-guard"])
        XCTAssertEqual(LoopsV7Setup.filter(rows, query: "", family: nil, state: .needsSetup).map(\.id), ["perf-guard"])
        XCTAssertEqual(LoopsV7Setup.filter(rows, query: "", family: nil, state: .failing).map(\.id), ["nightly-reflection"])
        XCTAssertEqual(LoopsV7Setup.filter(rows, query: "", family: nil, state: .off).map(\.id), [], "needs setup is its own chip")
        XCTAssertEqual(LoopsV7Setup.filter(rows, query: "", family: nil, state: .on).count, 3 + 0 + 1 - 0)
        // Search matches name, what it watches, subtype and file.
        XCTAssertEqual(LoopsV7Setup.filter(rows, query: "medians", family: nil, state: nil).map(\.id), ["perf-guard"])
        XCTAssertEqual(LoopsV7Setup.filter(rows, query: "Learner", family: nil, state: nil).map(\.id), ["nightly-reflection"])
        XCTAssertEqual(LoopsV7Setup.filter(rows, query: "docs-drift.loop", family: nil, state: nil).map(\.id), ["docs-drift"])
        XCTAssertEqual(LoopsV7Setup.countLine(shown: 2, all: 31), "2 of 31")
        XCTAssertEqual(LoopsV7Setup.emptyLine(query: "zzz", family: "check", state: .off), "No loop matches “zzz” · Check · off.")
        // Order: kinds in lane order, on before off inside a kind.
        XCTAssertEqual(LoopsV7Setup.ordered(rows.reversed()).map(\.id), ["cost-watch", "perf-guard", "docs-drift", "nightly-reflection", "oneroof-nightly-bugs"])
    }

    // MARK: 7i

    func test_7i_ACTION_guessKind() {
        XCTAssertEqual(LoopsV7Setup.guessKind("Every weekday at 8, check that main is green on acme/web. If it isn't, open an issue."), "auditor")
        XCTAssertEqual(LoopsV7Setup.guessKind("every night fix one bug per round until the check passes"), "fixer")
        XCTAssertEqual(LoopsV7Setup.guessKind("a morning brief of what changed"), "reporter")
        XCTAssertEqual(LoopsV7Setup.guessKind("alert me when spend crosses $20"), "sentinel")
        XCTAssertNil(LoopsV7Setup.guessKind("hello"))
    }

    func test_7i_VIEW_trialPlan() {
        let p = LoopsV7Setup.trialPlan(.at(hour: 3, minute: 0), now: now, calendar: cal)
        XCTAssertEqual(p.map(\.when), ["Sat 7", "Sun 8", "Mon 9", "Tue 10"])
        XCTAssertEqual(p.map(\.what), ["trial 1: checks, says what it would do", "trial 2", "trial 3", "goes live if you say so"])
        let manual = LoopsV7Setup.trialPlan(.untilDone(everyMinutes: 0), now: now, calendar: cal)
        XCTAssertEqual(manual.map(\.when), ["run 1", "run 2", "run 3", "run 4"])
        XCTAssertEqual(LoopsV7Setup.trialPlan(.onEvent("git.push"), now: now).first?.when, "event 1")
        let rows = [row("a", family: "check", kind: "auditor", on: true), row("b", family: "check", kind: "judge", on: false)]
        XCTAssertEqual(LoopsV7Setup.laneChange(family: "check", rows: rows, turnsOn: true), "Check goes from 1 / 2 to 2 / 3 on.")
    }

    // MARK: 7m

    func test_7m_ACTION_setKindPerEngine() {
        XCTAssertEqual(LoopsV7Setup.kindEdit(loop("docs-drift", kind: "auditor")), .builtIn("auditor"))
        XCTAssertEqual(LoopsV7Setup.kindEdit(loop("my-agent-xray", kind: nil, origin: .mine, kitFile: true)), .kitFile("/k/my-agent-xray.loop.yaml"))
        XCTAssertEqual(LoopsV7Setup.kindEdit(loop("oneroof-nightly-bugs", kind: nil, origin: .mine)), .oneRoof)
        XCTAssertEqual(LoopsV7Setup.setKindCommand(name: "my-agent-xray", kind: "reporter"),
                       ["python3", "-m", "ae.loops", "edit", "my-agent-xray", "--set", "kind=reporter"])
    }

    func test_7m_VIEW_ownerSuggestionsArePreselectedOnly() {
        XCTAssertEqual(LoopsV7Setup.suggestedKind(loop("oneroof-nightly-bugs", kind: nil, origin: .mine)), "fixer")
        XCTAssertEqual(LoopsV7Setup.suggestedKind(loop("my-agent-xray", kind: nil, origin: .mine, kitFile: true)), "reporter")
        XCTAssertEqual(LoopsV7Setup.suggestedKind(loop("my-weekly-review", kind: nil, origin: .mine, kitFile: true)), "reporter")
        XCTAssertEqual(LoopsV7Setup.suggestedKind(loop("oneroof-nightly-compare", kind: nil, origin: .mine, kitFile: true)), "judge")
        XCTAssertEqual(LoopsV7Setup.suggestedKind(loop("docs-drift", kind: "auditor")), "auditor", "a loop's own kind wins")
        XCTAssertNil(LoopsV7Setup.suggestedKind(loop("other", kind: nil, origin: .mine)))
        XCTAssertEqual(LoopsV7Setup.suggestionLine(loop("oneroof-nightly-bugs", kind: nil, origin: .mine)), "Set one to move it into a lane: Improve · Fixer fits.")
        XCTAssertNil(LoopsV7Setup.suggestionLine(loop("my-mac", kind: "sentinel", origin: .mine)))
    }

    func test_7m_ACTION_kitSetKindRunsTheKitAndRefusesBadKinds() throws {
        var calls: [[String]] = []
        try KitLoops.setKind("my-agent-xray", kind: "reporter", repo: "/kit") { exe, args, cwd in
            XCTAssertEqual(exe, "/usr/bin/env"); XCTAssertEqual(cwd, "/kit"); calls.append(args); return (0, "ok")
        }
        XCTAssertEqual(calls, [["python3", "-m", "ae.loops", "edit", "my-agent-xray", "--set", "kind=reporter"]])
        XCTAssertThrowsError(try KitLoops.setKind("my-agent-xray", kind: "wizard", repo: "/kit") { _, _, _ in XCTFail("never runs"); return (0, "") })
        XCTAssertThrowsError(try KitLoops.setKind("../x", kind: "reporter", repo: "/kit") { _, _, _ in XCTFail("never runs"); return (0, "") })
        XCTAssertThrowsError(try KitLoops.setKind("my-agent-xray", kind: "reporter", repo: "/kit") { _, _, _ in (1, "kind: not allowed\nerror: invalid") }) { e in
            XCTAssertTrue("\(e)".contains("error: invalid"))
        }
    }

    func test_7m_VIEW_deleteCopy() {
        XCTAssertEqual(LoopsV7Setup.deleteMessage(worktree: "labs/oneroof/.worktrees/loop-x", branch: "loop/x"),
                       "Its loop.json, state.json and round log are removed. Its worktree labs/oneroof/.worktrees/loop-x and branch loop/x stay, with any work in them.")
        func o(_ kind: String, _ status: String = "staged") -> LoopLedger.Outcome {
            LoopLedger.Outcome(id: 1, runId: "r", loop: "x", kind: kind, link: "", title: "", status: status, decidedBy: nil, decidedAt: nil, created: "", detail: "")
        }
        XCTAssertEqual(LoopsV7Setup.stagedWarning([o("commit"), o("commit"), o("commit"), o("commit")]),
                       "4 commits on that branch are still waiting for you. They stay, but leave Needs you.")
        XCTAssertEqual(LoopsV7Setup.stagedWarning([o("commit"), o("report")]),
                       "1 commit on that branch is and 1 other item is still waiting for you. They stay, but leave Needs you.")
        XCTAssertNil(LoopsV7Setup.stagedWarning([o("commit", "approved")]))
    }

    // MARK: 7n

    func test_7n_STATE_setupItemsWithKeys() {
        let cfg = "loops:\n  settings:\n    cost-watch:\n      limits:\n        anthropic: 20\n"
        let items = LoopsV7Setup.setupItems(loops: [loop("fleet-sweep", kind: "sentinel"), loop("cost-watch", kind: "sentinel"),
                                                    loop("security-audit", kind: "auditor"), loop("docs-drift", kind: "auditor")],
                                            config: cfg) { _ in false }
        XCTAssertEqual(items.map(\.loop), ["fleet-sweep", "cost-watch", "security-audit"])
        XCTAssertEqual(items[0].key, "loops.settings.fleet-sweep.commands")
        XCTAssertEqual(items[0].need, "Needs the commands to run")
        XCTAssertEqual(items[1].key, "loops.settings.cost-watch.usd_per_mtok")
        XCTAssertEqual(items[2].tool, "osv-scanner")
        XCTAssertEqual(items[2].button, "Install")
        XCTAssertEqual(items[0].button, "Set up")
        XCTAssertEqual(LoopsV7Setup.setupTitle(items), "3 loops need a setting before they can run")
        XCTAssertEqual(LoopsV7Setup.setupTitle([items[0]]), "1 loop needs a setting before it can run")
    }

    func test_7n_ACTION_configLineFindsTheKey() {
        let cfg = "agent: claude\nloops:\n  enabled: [a]\n  settings:\n    cost-watch:\n      limits:\n        anthropic: 20\n    fleet-sweep:\n      x: 1\n"
        XCTAssertEqual(LoopsV7Setup.configLine("loops.settings.cost-watch.limits", in: cfg), 6)
        XCTAssertEqual(LoopsV7Setup.configLine("loops.settings.fleet-sweep.commands", in: cfg), 8, "the deepest part that exists")
        XCTAssertEqual(LoopsV7Setup.configLine("loops.settings.perf-guard.commands", in: cfg), 4)
        XCTAssertNil(LoopsV7Setup.configLine("loops.settings.x", in: "agent: claude\n"))
    }

    func test_7n_STATE_banners() {
        let mine = loop("oneroof-nightly-bugs", kind: nil, origin: .mine, state: .paused)
        let brief = loop("my-morning-brief", kind: "reporter", origin: .mine, state: .paused)
        let rows = [row("oneroof-nightly-bugs", family: "other", kind: nil, engine: .oneRoof, on: true),
                    row("cost-watch", family: "watch", kind: "sentinel", on: true)]
        let b = LoopsV7Setup.banners(roofdOK: false, roofdLine: "roofd not running: connection refused", loops: [mine, brief], rows: rows,
                                     kitKnown: false, error: "Save: could not save /x/loop.json")
        XCTAssertEqual(b, [.writeFailed(action: "Save", reason: "could not save /x/loop.json"),
                           .roofdDown(line: "roofd not running: connection refused", waiting: ["oneroof-nightly-bugs"]),
                           .paused(count: 2, skipped: ["my-morning-brief", "oneroof-nightly-bugs"]),
                           .kitUnknown])
        // One loop still running: not "everything paused"; the kit read and roofd fine: nothing else.
        let running = loop("x", kind: nil, origin: .mine, state: .running)
        XCTAssertEqual(LoopsV7Setup.banners(roofdOK: true, roofdLine: "", loops: [mine, running], rows: [], kitKnown: true, error: nil), [])
        XCTAssertEqual(LoopsV7Setup.splitError("no colon").action, "A change")
        XCTAssertEqual(LoopsV7Setup.splitError("Set kind: the kit refused").reason, "the kit refused")
        XCTAssertEqual(LoopsV7Setup.names(["a", "b", "c", "d", "e"]), "a, b, c +2")
    }
}
