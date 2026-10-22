import XCTest
@testable import OneRoofCore

final class SubagentTests: XCTestCase {
    func iso(_ s: String) -> Date { ClaudeTranscript.date(s)! }

    func testTreeFromTranscript() throws {
        let subs = ClaudeTranscript.subagents(jsonl: Fixture.transcript, sessionId: "s1")
        XCTAssertEqual(subs.map(\.id), ["toolu_A", "toolu_B", "toolu_C"])

        let a = subs[0]
        XCTAssertNil(a.parentId)
        XCTAssertEqual(a.depth, 1)
        XCTAssertEqual(a.name, "Explore the store")
        XCTAssertEqual(a.asked, "Find how SessionStore migrates tables.")
        XCTAssertEqual(a.model, "claude-haiku-4-5")
        XCTAssertEqual(a.tokens, 100 + 50 + 25 + 10 + 5)   // cache reads not counted
        XCTAssertEqual(a.started, iso("2026-10-18T10:00:05.000Z"))
        XCTAssertEqual(a.ended, iso("2026-10-18T10:02:00.000Z"))
        XCTAssertEqual(a.status, .done)
        XCTAssertEqual(a.touched, [FileTouch(path: "/r/app/Sources/OneRoofCore/SessionStore.swift", read: true)])
        XCTAssertEqual(a.lastText, "Looking at SessionStore.")

        let b = subs[1]
        XCTAssertEqual(b.parentId, "toolu_A")
        XCTAssertEqual(b.depth, 2)
        XCTAssertEqual(b.model, "claude-sonnet-4-5")
        XCTAssertEqual(b.touched, [FileTouch(path: "/r/app/Sources/OneRoofCore/Feed.swift", added: 2, removed: 1)])
        XCTAssertEqual(b.ended, iso("2026-10-18T10:01:00.000Z"))

        let c = subs[2]
        XCTAssertNil(c.parentId)
        XCTAssertTrue(c.isRunning)
        XCTAssertEqual(c.tokens, 10)                         // matched without parentToolUseID
        XCTAssertEqual(c.lastText, "Writing thirty fixtures now.")
        XCTAssertFalse(c.inferred)
    }

    func testTreeOrderIsDepthFirst() {
        let t = Date()
        let subs = [Subagent(id: "a", sessionId: "s", name: "a", started: t), Subagent(id: "c", sessionId: "s", name: "c", started: t),
                    Subagent(id: "b", parentId: "a", sessionId: "s", name: "b", started: t, depth: 2)]
        XCTAssertEqual(ClaudeTranscript.treeOrder(subs).map(\.id), ["a", "b", "c"])
    }

    func testTranscriptPaths() {
        XCTAssertEqual(ClaudeTranscript.path(configDir: "/Users/x/.claude-2", cwd: "/Users/x/Projects/acme/web", sessionId: "abc"),
                       "/Users/x/.claude-2/projects/-Users-x-Projects-acme-web/abc.jsonl")
        XCTAssertEqual(ClaudeTranscript.subagentsFolder(configDir: "/Users/x/.claude", cwd: "/Users/x/Projects", sessionId: "abc"),
                       "/Users/x/.claude/projects/-Users-x-Projects/abc/subagents")
    }

    func testInferredChildren() {
        let t0 = Date(timeIntervalSince1970: 1000)
        let panes = [
            PaneObservation(paneId: "p1", workspaceId: "w1", agent: "codex", firstSeen: t0),                       // the parent
            PaneObservation(paneId: "p2", workspaceId: "w1", agent: "codex", title: "worker 1", status: "working", firstSeen: t0.addingTimeInterval(30)),
            PaneObservation(paneId: "p3", workspaceId: "w2", agent: "kimi", firstSeen: t0.addingTimeInterval(30)),  // other window
            PaneObservation(paneId: "p4", workspaceId: "w1", firstSeen: t0.addingTimeInterval(-60)),               // older than launch
            PaneObservation(paneId: "p5", workspaceId: "w1", agent: "claude", status: "done", firstSeen: t0.addingTimeInterval(40)),
            PaneObservation(paneId: "p6", workspaceId: "w1", firstSeen: t0.addingTimeInterval(50)),                // another session's
        ]
        let kids = InferredSubagents.children(sessionId: "s", parentPane: "p1", workspaceId: "w1", parentPid: nil, launchedAt: t0,
                                              panes: panes, ownedByOthers: ["p6"])
        XCTAssertEqual(kids.map(\.id), ["pane:p2", "pane:p5"])
        XCTAssertTrue(kids.allSatisfy(\.inferred))
        XCTAssertEqual(kids[0].name, "worker 1")
        XCTAssertEqual(kids[1].status, .done)
    }

    func testInferredChildrenByProcessTree() {
        let t0 = Date(timeIntervalSince1970: 1000)
        let panes = [PaneObservation(paneId: "p2", workspaceId: "w", firstSeen: t0, ancestorPids: [1, 500]),
                     PaneObservation(paneId: "p3", workspaceId: "w", firstSeen: t0, ancestorPids: [1, 900])]
        let kids = InferredSubagents.children(sessionId: "s", parentPane: "p1", workspaceId: "w", parentPid: 500, launchedAt: t0, panes: panes)
        XCTAssertEqual(kids.map(\.id), ["pane:p2"])
    }
}

final class FileClaimTests: XCTestCase {
    let repo = "/r/app"
    let t = Date(timeIntervalSince1970: 1000)

    func testClaimsFromToolCallsClearOnChapterEnd() {
        var c = FileClaims()
        let added = c.observe(text: "⏺ Read(README.md)\n⏺ Update(Sources/a.swift)\n⏺ Write(/r/app/docs/b.md)", sessionId: "s1", repo: repo, step: 2, at: t)
        XCTAssertEqual(added.map(\.path), ["/r/app/Sources/a.swift", "/r/app/docs/b.md"])
        XCTAssertEqual(c.claim(for: "/r/app/Sources/a.swift")?.step, 2)
        XCTAssertNil(c.claim(for: "/r/app/README.md"))                 // reads don't claim
        XCTAssertNotNil(c.blockingClaim(for: "/r/app/Sources/a.swift"))
        XCTAssertNil(c.blockingClaim(for: "/r/app/Sources/a.swift", me: "s1"))
        // The same file again is not a new claim.
        XCTAssertTrue(c.observe(text: "⏺ Edit(Sources/a.swift)", sessionId: "s1", repo: repo).isEmpty)
        c.endChapter(sessionId: "s1")
        XCTAssertNil(c.claim(for: "/r/app/Sources/a.swift"))
        XCTAssertNotNil(c.editedBy["s1"]?["/r/app/Sources/a.swift"])     // kept for attribution
        c.endSession(sessionId: "s1")
        XCTAssertNil(c.editedBy["s1"])
    }

    func testLatestEditorWinsAndSwarmImport() {
        var c = FileClaims()
        c.observe(text: "● Edit(x.swift)", sessionId: "s1", repo: repo, at: t)
        c.observe(text: "• Edited x.swift (+1 -0)", sessionId: "s2", repo: repo, at: t.addingTimeInterval(5))
        XCTAssertEqual(c.claim(for: "/r/app/x.swift")?.sessionId, "s2")
        c.importClaims([FileClaim(path: "/r/app/y.swift", sessionId: "swarm-1", step: 1, since: t)])
        XCTAssertEqual(c.claims(of: "swarm-1").count, 1)
    }

    func testAttributionOfDiffRuns() {
        var c = FileClaims()
        c.observe(text: "⏺ Edit(Sources/a.swift)", sessionId: "s1", repo: repo, at: t)
        let lines: [DiffLine] = [
            DiffLine(kind: .context, text: "a", oldNo: 1, newNo: 1),
            DiffLine(kind: .added, text: "b", oldNo: nil, newNo: 2),
            DiffLine(kind: .added, text: "c", oldNo: nil, newNo: 3),
            DiffLine(kind: .removed, text: "d", oldNo: 2, newNo: nil),
            DiffLine(kind: .added, text: "e", oldNo: nil, newNo: 7),
        ]
        let diff = FileDiff(path: "Sources/a.swift", oldPath: nil, change: .modified,
                            hunks: [DiffHunk(file: "Sources/a.swift", header: "@@ -1,2 +1,4 @@", lines: lines, patch: "")])
        let attr = Attributor.attribute(diff: diff, repo: repo, claims: c, badge: { _ in "C1" }, at: t)
        XCTAssertEqual(attr.map(\.lines), [2...3, 7...7])
        XCTAssertEqual(attr.first?.author, .agent("C1"))
        XCTAssertEqual(Attributor.attribution(at: 3, in: attr)?.sessionId, "s1")
        // A file no session touched is yours.
        let other = FileDiff(path: "b.swift", oldPath: nil, change: .modified, hunks: [DiffHunk(file: "b.swift", header: "", lines: lines, patch: "")])
        XCTAssertEqual(Attributor.attribute(diff: other, repo: repo, claims: c, badge: { _ in "C1" }).first?.author, .you)
    }

    func testRunsAndAuthorStorage() {
        XCTAssertEqual(Attributor.runs([9, 3, 4, 5, 10, 4]), [3...5, 9...10])
        XCTAssertEqual(Author(stored: Author.agent("CX").stored), .agent("CX"))
        XCTAssertEqual(Author(stored: "you"), .you)
    }

    func testCommitMessageMapsToSession() {
        var a = Session(name: "a", repoPath: "/r"); a.ticket = "ENG-569"
        let b = Session(name: "b", repoPath: "/r", workstream: "WS-API-21")
        XCTAssertEqual(Attributor.session(forCommitMessage: "ENG-569 · [ws-web-12] engines", sessions: [a, b])?.name, "a")
        XCTAssertEqual(Attributor.session(forCommitMessage: "API-1 · [ws-api-21] planner", sessions: [a, b])?.name, "b")
        XCTAssertNil(Attributor.session(forCommitMessage: "typo fix", sessions: [a, b]))
    }
}

final class ChapterTests: XCTestCase {
    let transcript = """
     ✻ Welcome to Claude Code!

    > Add the caption engine
    ⏺ I'll start by reading the spec. Then the code.
    ⏺ Read(ENGINES.md)
      ⎿  Read 47 lines
    ⏺ Write(Captions.swift)
    > Now write the tests
    ⏺ Writing tests for the heuristics.
    ⏺ Bash(swift test)
    ╭──────╮
    │ >    │
    ╰──────╯
    """

    func testSplitsAtPrompts() {
        let d = ChapterSplitter.drafts(transcript)
        XCTAssertEqual(d.map(\.title), ["Start", "Add the caption engine", "Now write the tests"])
        XCTAssertEqual(d.map(\.toolCalls), [0, 2, 1])
        XCTAssertEqual(d[1].summary, "I'll start by reading the spec.")
        XCTAssertEqual(d[0].range, 0..<2)
        XCTAssertEqual(d[1].range, 2..<7)
        XCTAssertEqual(d.last?.range.upperBound, TerminalText.lines(transcript).count)
    }

    func testStepMarkersAndOptionRowsAreNotPrompts() {
        let text = "Step 1 of 2: Read the spec\n● Read(a.md)\n## Step 2 — Write code\n● Edit(b.swift)\n❯ 1. Yes"
        let d = ChapterSplitter.drafts(text)
        XCTAssertEqual(d.map(\.title), ["Step 1 of 2: Read the spec", "Step 2 — Write code"])
        XCTAssertEqual(d[1].summary, "Editing b.swift")
    }

    func testCodexAndKimiPrompts() {
        XCTAssertEqual(ChapterSplitter.boundary("› Fix the flaky test"), .prompt("Fix the flaky test"))
        XCTAssertEqual(ChapterSplitter.boundary("✨ Summarise the logs"), .prompt("Summarise the logs"))
        XCTAssertNil(ChapterSplitter.boundary("> "))
        XCTAssertNil(ChapterSplitter.boundary("plain output"))
    }

    func testTimesKeepKnownStartsAndEndAllButLast() {
        let t0 = Date(timeIntervalSince1970: 0), t1 = Date(timeIntervalSince1970: 100), t2 = Date(timeIntervalSince1970: 200)
        let first = ChapterSplitter.chapters("> one\n⏺ ok", sessionStarted: t0, now: t1)
        XCTAssertEqual(first.count, 1)
        XCTAssertNil(first[0].ended)
        XCTAssertTrue(first[0].isCurrent)
        let second = ChapterSplitter.chapters("> one\n⏺ ok\n> two\n⏺ fine", previous: first, sessionStarted: t0, now: t2)
        XCTAssertEqual(second.map(\.started), [t0, t2])
        XCTAssertEqual(second[0].ended, t2)
        XCTAssertNil(second[1].ended)
        let finished = ChapterSplitter.chapters("> one\n⏺ ok", previous: first, sessionStarted: t0, now: t2, finished: true)
        XCTAssertEqual(finished[0].ended, t2)
        XCTAssertEqual(ChapterSplitter.chapter(containing: 3, in: second)?.index, 1)
    }
}

final class FeedTests: XCTestCase {
    let t = Date(timeIntervalSince1970: 1000)

    func testDedupSameKindAndSessionWithin60s() {
        var f = FeedBuffer()
        XCTAssertTrue(f.add(FeedEvent(at: t, sessionId: "a", kind: .done, text: "x")))
        XCTAssertFalse(f.add(FeedEvent(at: t.addingTimeInterval(59), sessionId: "a", kind: .done, text: "y")))
        XCTAssertTrue(f.add(FeedEvent(at: t.addingTimeInterval(30), sessionId: "a", kind: .finding, text: "z")))
        XCTAssertTrue(f.add(FeedEvent(at: t.addingTimeInterval(30), sessionId: "b", kind: .done, text: "z")))
        XCTAssertTrue(f.add(FeedEvent(at: t.addingTimeInterval(61), sessionId: "a", kind: .done, text: "w")))
        XCTAssertEqual(f.events.count, 4)
        XCTAssertEqual(f.events.first?.text, "w")   // newest first
    }

    func testCapacity200() {
        var f = FeedBuffer()
        for i in 0..<250 { f.add(FeedEvent(at: t.addingTimeInterval(Double(i)), sessionId: "s\(i)", kind: .stepDone, text: "\(i)")) }
        XCTAssertEqual(f.events.count, 200)
        XCTAssertEqual(f.events.first?.text, "249")
        XCTAssertEqual(f.events.last?.text, "50")
    }

    func testMuteSessionAndWindow() {
        var f = FeedBuffer()
        f.add(FeedEvent(at: t, sessionId: "a", kind: .done, text: "a"))
        f.add(FeedEvent(at: t, sessionId: "b", kind: .done, text: "b"))
        f.add(FeedEvent(at: t, sessionId: "c", kind: .done, text: "c"))
        let windows = ["a": "w1", "b": "w2", "c": "w2"]
        f.mute(session: "a")
        XCTAssertEqual(f.visible(windowOf: { windows[$0] }).map(\.sessionId).sorted(), ["b", "c"])
        f.mute(window: "w2")
        XCTAssertTrue(f.visible(windowOf: { windows[$0] }).isEmpty)
        f.unmute(session: "a"); f.unmute(window: "w2")
        XCTAssertEqual(f.visible(windowOf: { windows[$0] }).count, 3)
    }

    func testStatusChangeEvents() {
        let cap = Caption(text: "Ready · All tests pass.")
        let done = FeedSignals.statusChange(from: .running, to: .done, sessionId: "s", name: "Engines", caption: cap, at: t)
        XCTAssertEqual(done.map(\.kind), [.done])
        XCTAssertEqual(done.first?.text, "Engines finished: All tests pass.")
        XCTAssertEqual(FeedSignals.statusChange(from: .running, to: .exited, sessionId: "s", name: "E").map(\.kind), [.error])
        XCTAssertTrue(FeedSignals.statusChange(from: .running, to: .needsYou, sessionId: "s", name: "E").isEmpty)   // a Decision instead
        XCTAssertTrue(FeedSignals.statusChange(from: .done, to: .done, sessionId: "s", name: "E").isEmpty)
        XCTAssertEqual(FeedSignals.subagentsStarted(sessionId: "s", names: ["a", "b", "c", "d"])?.text, "Started 4 subagents: a, b, c +1")
        XCTAssertEqual(FeedKind(modelName: "subagents started"), .subagents)
        XCTAssertNil(FeedKind(modelName: "weather"))
    }
}

final class ScheduleTests: XCTestCase {
    var cal: Calendar = { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; return c }()
    func d(_ s: String) -> Date { ISO8601DateFormatter().date(from: s)! }

    func testTonightFiresOnceAndCanBeMissed() {
        let r = ScheduleRecord(sessionId: "s", schedule: .tonight(hour: 2, minute: 0), armedAt: d("2026-10-18T20:00:00Z"))
        XCTAssertEqual(ScheduleClock.nextFire(r, now: d("2026-10-18T21:00:00Z"), calendar: cal), d("2026-10-19T02:00:00Z"))
        XCTAssertEqual(ScheduleClock.action(r, now: d("2026-10-18T23:00:00Z"), calendar: cal), .nothing)
        XCTAssertEqual(ScheduleClock.action(r, now: d("2026-10-19T02:03:00Z"), calendar: cal), .run)
        XCTAssertEqual(ScheduleClock.action(r, now: d("2026-10-19T07:30:00Z"), calendar: cal), .missed(d("2026-10-19T02:00:00Z")))
        XCTAssertTrue(ScheduleClock.isMissed(r, now: d("2026-10-19T07:30:00Z"), calendar: cal))
        XCTAssertNil(ScheduleClock.nextFire(r, now: d("2026-10-19T07:30:00Z"), calendar: cal))
        var ran = r; ran.lastRun = d("2026-10-19T02:00:05Z")
        XCTAssertEqual(ScheduleClock.action(ran, now: d("2026-10-19T07:30:00Z"), calendar: cal), .nothing)
        XCTAssertNil(ScheduleClock.nextFire(ran, now: d("2026-10-19T01:00:00Z"), calendar: cal))
    }

    func testNightly() {
        var r = ScheduleRecord(sessionId: "s", schedule: .nightly(hour: 23, minute: 30), armedAt: d("2026-10-17T09:00:00Z"),
                               lastRun: d("2026-10-17T23:31:00Z"))
        XCTAssertEqual(ScheduleClock.nextFire(r, now: d("2026-10-18T12:00:00Z"), calendar: cal), d("2026-10-18T23:30:00Z"))
        XCTAssertEqual(ScheduleClock.action(r, now: d("2026-10-18T12:00:00Z"), calendar: cal), .nothing)
        XCTAssertEqual(ScheduleClock.action(r, now: d("2026-10-18T23:35:00Z"), calendar: cal), .run)
        XCTAssertEqual(ScheduleClock.action(r, now: d("2026-10-19T08:00:00Z"), calendar: cal), .missed(d("2026-10-18T23:30:00Z")))
        r.lastRun = d("2026-10-18T23:30:10Z")
        XCTAssertEqual(ScheduleClock.action(r, now: d("2026-10-19T08:00:00Z"), calendar: cal), .nothing)
    }

    func testOnDemandNeverFires() {
        let r = ScheduleRecord(sessionId: "s", schedule: .onDemand, armedAt: d("2026-10-18T00:00:00Z"))
        XCTAssertNil(ScheduleClock.nextFire(r, now: d("2026-10-18T12:00:00Z"), calendar: cal))
        XCTAssertEqual(ScheduleClock.action(r, now: d("2026-10-18T12:00:00Z"), calendar: cal), .nothing)
    }

    func testLabelsAndStorage() {
        XCTAssertEqual(Schedule.tonight(hour: 2, minute: 0).label, "Tonight 2:00 AM")
        XCTAssertEqual(Schedule.nightly(hour: 0, minute: 5).label, "Nightly 12:05 AM")
        XCTAssertEqual(Schedule.nightly(hour: 12, minute: 0).timeText, "12:00 PM")
        XCTAssertEqual(Schedule.onDemand.label, "On demand")
        for s in [Schedule.tonight(hour: 2, minute: 0), .nightly(hour: 23, minute: 30), .onDemand] {
            XCTAssertEqual(Schedule(kind: s.kind, hour: s.time?.hour, minute: s.time?.minute), s)
        }
        XCTAssertNil(Schedule(kind: "weekly", hour: 1, minute: 1))
    }

    func testLaunchdPlist() throws {
        let xml = SchedulerAgent.plist(executable: "/Applications/One Roof.app/Contents/MacOS/OneRoof",
                                       schedules: [.tonight(hour: 2, minute: 0), .nightly(hour: 2, minute: 0), .nightly(hour: 23, minute: 30), .onDemand])
        let obj = try PropertyListSerialization.propertyList(from: Data(xml.utf8), format: nil) as? [String: Any]
        XCTAssertEqual(obj?["Label"] as? String, "com.oneroof.scheduler")
        XCTAssertEqual(obj?["ProgramArguments"] as? [String], ["/Applications/One Roof.app/Contents/MacOS/OneRoof", "--run-scheduled"])
        let times = obj?["StartCalendarInterval"] as? [[String: Int]]
        XCTAssertEqual(times ?? [], [["Hour": 2, "Minute": 0], ["Hour": 23, "Minute": 30]])
        XCTAssertEqual(obj?["RunAtLoad"] as? Bool, false)
        XCTAssertTrue(SchedulerAgent.plistPath.hasSuffix("Library/LaunchAgents/com.oneroof.scheduler.plist"))
    }
}
