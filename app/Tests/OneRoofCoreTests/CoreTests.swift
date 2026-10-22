import XCTest
@testable import OneRoofCore

final class WorkspaceTests: XCTestCase {
    let root = "/Users/x/Projects"

    func testInsideProjects() {
        XCTAssertTrue(Workspace.isInsideProjects("/Users/x/Projects", root: root))
        XCTAssertTrue(Workspace.isInsideProjects("/Users/x/Projects/acme/web", root: root))
        XCTAssertFalse(Workspace.isInsideProjects("/Users/x", root: root))
        XCTAssertFalse(Workspace.isInsideProjects("/Users/x/ProjectsOld", root: root))
    }

    func testRepoLabel() {
        XCTAssertEqual(Workspace.repoLabel(for: "/Users/x/Projects/acme/web/app/Sources", root: root), "acme/web")
        XCTAssertEqual(Workspace.repoLabel(for: "/Users/x/Projects/_common", root: root), "_common")
        XCTAssertEqual(Workspace.repoLabel(for: "/Users/x/Projects", root: root), "/Users/x/Projects")
        let home = NSHomeDirectory() + "/Projects"
        XCTAssertEqual(Workspace.repoLabel(for: home, root: home), "~/Projects")
        XCTAssertEqual(Workspace.repoLabel(for: "/Users/x/Projects/_common/.worktrees/ws-a-unit", root: root), "_common")
        XCTAssertEqual(Workspace.repoLabel(for: "/tmp/elsewhere", root: root), "elsewhere")
    }

    func testWorkstreamId() {
        XCTAssertEqual(Workspace.workstream(in: "WIP: ws-web-12 sidebar"), "WS-WEB-12")
        XCTAssertEqual(Workspace.workstream(in: "[WS-API-21] planner"), "WS-API-21")
        XCTAssertEqual(Workspace.workstream(in: "fix ENG-233 · [ws-docs-know-01] x"), "WS-DOCS-KNOW-01")
        XCTAssertNil(Workspace.workstream(in: "no id here"))
        // Linear project codes (LAB-236): bare upper-case codes and commit tags; issue keys are not projects.
        XCTAssertEqual(Workspace.workstream(in: "TEAM-ROOFD · roofd"), "TEAM-ROOFD")
        XCTAssertEqual(Workspace.workstream(in: "ENG-12 · [eng-know-03] subject"), "ENG-KNOW-03")
        XCTAssertNil(Workspace.workstream(in: "fix ENG-235 today"))
        XCTAssertEqual(Workspace.projectCode(name: "ENG-KNOW-03 · Knowledge v3"), "ENG-KNOW-03")
        XCTAssertEqual(Workspace.projectCode(name: "WS-WEB-12 · New checkout"), "WS-WEB-12")
        XCTAssertNil(Workspace.projectCode(name: "Roadmap"))
        // LAB-519: dotted version codes keep their dot and the version's case; the commit tag drops the dot.
        XCTAssertEqual(Workspace.projectCode(name: "LAB-ONEROOF-v0.50 · Desktop command-center IDE"), "LAB-ONEROOF-v0.50")
        XCTAssertEqual(Workspace.projectCode(name: "lab-roofd · x"), "LAB-ROOFD")
        XCTAssertEqual(Workspace.commitTag("LAB-ONEROOF-v0.50"), "lab-oneroof-v050")
        XCTAssertEqual(Workspace.commitTag("LAB-ONEROOF-BUGS"), "lab-oneroof-bugs")
        XCTAssertTrue(Intake.ticketOpening(key: "LAB-1", title: "t", project: "LAB-ONEROOF-v0.50").contains("`LAB-1 · [lab-oneroof-v050] …`"))
        XCTAssertNil(Workspace.projectCode(name: "LAB-X. · trailing dot").flatMap { $0.contains(".") ? $0 : nil })
    }

    func testHandoffIsOnlyTheSessionsOwn() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("handoffs-\(UUID().uuidString)").path
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: dir) }
        for f in ["2026-10-19_0900_eng-roofd-p0_NEXT.txt", "2026-10-20_1000_eng-roofd-fixes_NEXT.txt",
                  "2026-10-20_1500_other-thing_NEXT.txt", "2026-10-20_1600_eng-roofd2-x.txt", "2026-10-20_1700_eng-247-fix.txt"] {
            FileManager.default.createFile(atPath: dir + "/" + f, contents: Data())
        }
        XCTAssertEqual(Workspace.handoff(in: dir, project: "ENG-ROOFD", ticket: nil), dir + "/2026-10-20_1000_eng-roofd-fixes_NEXT.txt")
        XCTAssertEqual(Workspace.handoff(in: dir, project: nil, ticket: "ENG-247"), dir + "/2026-10-20_1700_eng-247-fix.txt")
        XCTAssertNil(Workspace.handoff(in: dir, project: "ENG-DOCLAB-01", ticket: nil), "no other project's handoff")
        XCTAssertNil(Workspace.handoff(in: dir, project: nil, ticket: "ENG-24"), "ENG-24 is not ENG-247")
        XCTAssertNil(Workspace.handoff(in: dir, project: nil, ticket: nil))
    }

    /// LAB-250 hardening: whole id on both sides, any place in the name, every issue of the session, and which id matched.
    func testHandoffMatchesWholeIdsAnywhereAndAnyIssue() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("handoffs-\(UUID().uuidString)").path
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: dir) }
        for f in ["2026-10-20_0900_xeng-24-x.txt", "2026-10-20_1000_eng-247_eng-24_both.txt", "2026-10-20_1100_eng-9-fix.txt"] {
            FileManager.default.createFile(atPath: dir + "/" + f, contents: Data())
        }
        XCTAssertEqual(Workspace.handoff(in: dir, project: nil, ticket: "ENG-24"), dir + "/2026-10-20_1000_eng-247_eng-24_both.txt",
                       "the second place it appears counts; xeng-24 does not")
        try FileManager.default.removeItem(atPath: dir + "/2026-10-20_1000_eng-247_eng-24_both.txt")
        XCTAssertNil(Workspace.handoff(in: dir, project: nil, ticket: "ENG-24"), "xeng-24 is not eng-24")
        let m = Workspace.handoffMatch(in: dir, project: "ENG-ROOFD", tickets: ["ENG-1", "ENG-9"])
        XCTAssertEqual(m?.path, dir + "/2026-10-20_1100_eng-9-fix.txt")
        XCTAssertEqual(m?.key, "ENG-9", "the button names the issue whose handoff it is")
    }

    func testTicketOpeningNamesTheIssueNotTheProject() {
        let o = Intake.ticketOpening(key: "ENG-247", title: "test03", url: "https://x/ENG-247", project: "ENG-ROOFD")
        XCTAssertTrue(o.hasPrefix("Work on ENG-247 in project ENG-ROOFD: test03."), o)
        XCTAssertTrue(o.contains("commit as `ENG-247 · [eng-roofd] …`"), o)
        XCTAssertFalse(o.contains("new ticket"))
        XCTAssertEqual(Intake.ticketOpening(key: "ENG-9", title: "t", project: nil), "Work on ENG-9: t. Read the ticket first; commit as `ENG-9 …`.")
        XCTAssertEqual(Intake.sessionName(key: "ENG-247", title: "test03"), "ENG-247 · test03")
        XCTAssertEqual(Intake.sessionName(key: "ENG-247", title: "ENG-247 · test03"), "ENG-247 · test03")
    }

    func testWorkKindsMapToLinearTypeLabels() {
        XCTAssertEqual(WorkKind.defect.labelNames.first, "Bug")
        XCTAssertEqual(WorkKind.chore.labelNames.first, "Task")
        XCTAssertEqual(WorkKind.fromLabel("Bug"), .defect)
        XCTAssertEqual(WorkKind.fromLabel("type:deliverable"), .deliverable)
        XCTAssertNil(WorkKind.fromLabel("canary"))
        let old = LinearIssue(id: "1", identifier: "ENG-1", title: "[ws-web-12] Fix it", description: "", state: "", stateType: "",
                              type: nil, milestoneId: nil, milestone: nil, url: "")
        XCTAssertEqual(old.shortTitle, "Fix it")
        var new = old; new.title = "[eng-know-03] Fix it"
        XCTAssertEqual(new.shortTitle, "Fix it")
    }
}

final class AccountTests: XCTestCase {
    let home = "/Users/x"

    func testClaudeLabels() {
        XCTAssertEqual(AccountResolver.label(agent: .claude, env: [:], home: home), "Claude1")
        XCTAssertEqual(AccountResolver.label(agent: .claude, env: ["CLAUDE_CONFIG_DIR": "/Users/x/.claude-2"], home: home), "Claude2")
        XCTAssertEqual(AccountResolver.label(agent: .claude, env: ["CLAUDE_CONFIG_DIR": "/Users/x/.claude"], home: home), "Claude1")
        XCTAssertEqual(AccountResolver.label(agent: .claude, env: ["CLAUDE_CONFIG_DIR": "/Users/x/.claude-max-3"], home: home), ".claude-max-3")
        XCTAssertEqual(AccountResolver.label(agent: .codex, env: ["CODEX_HOME": "/Users/x/.codex-account2"], home: home), ".codex-account2")
    }

    func testLaunchEnvRoundTrip() {
        let env = AccountResolver.launchEnv(agent: .claude, account: "Claude2", home: home)
        XCTAssertEqual(AccountResolver.label(agent: .claude, env: env, home: home), "Claude2")
        XCTAssertEqual(AccountResolver.launchEnv(agent: .claude, account: "Claude1", home: home), [:])
        XCTAssertEqual(AccountResolver.label(agent: .claude, env: ["CLAUDE_CONFIG_DIR": ""], home: home), "Claude1")
        XCTAssertEqual(AccountResolver.launchEnv(agent: .codex, account: nil, home: home), [:])
    }
}

final class ProcessProbeTests: XCTestCase {
    func testParseProcargs2() {
        var buf: [UInt8] = []
        var argc: Int32 = 2
        withUnsafeBytes(of: &argc) { buf.append(contentsOf: $0) }
        func s(_ x: String) { buf.append(contentsOf: Array(x.utf8)); buf.append(0) }
        s("/usr/local/bin/claude"); buf.append(contentsOf: [0, 0, 0])
        s("claude"); s("--resume")
        s("CLAUDE_CONFIG_DIR=/Users/x/.claude-2"); s("HOME=/Users/x"); s("EMPTY=")
        let a = ProcessProbe.parse(buf)
        XCTAssertEqual(a?.executable, "/usr/local/bin/claude")
        XCTAssertEqual(a?.argv, ["claude", "--resume"])
        XCTAssertEqual(a?.env["CLAUDE_CONFIG_DIR"], "/Users/x/.claude-2")
        XCTAssertEqual(a?.env["HOME"], "/Users/x")
        XCTAssertEqual(a?.env["EMPTY"], "")
    }

    func testOwnProcessHasEnvironment() {
        // The test runner is not an Apple system binary, so its environment is readable.
        let a = ProcessProbe.args(pid: getpid())
        XCTAssertNotNil(a)
        XCTAssertNotNil(a?.env["HOME"])
    }
}

final class BoardTests: XCTestCase {
    func testGroupingByWorkstreamPutsNoneLast() {
        var a = Session(name: "a", repoPath: "/p", lifecycle: .planned); a.workstream = "WS-B-01"
        let b = Session(name: "b", repoPath: "/p", lifecycle: .planned)
        var c = Session(name: "c", repoPath: "/p", lifecycle: .planned); c.workstream = "WS-A-01"
        let groups = Board.group(Board.merge(stored: [a, b, c], snapshot: RuntimeSnapshot()), by: .workstream)
        XCTAssertEqual(groups.map(\.title), ["WS-A-01", "WS-B-01", "No project"])
    }

    func testParseArgs() {
        XCTAssertEqual(Session.parseArgs("--resume 1a2b"), ["--resume", "1a2b"])
        XCTAssertEqual(Session.parseArgs("  --model \"opus 5\"  -c "), ["--model", "opus 5", "-c"])
        XCTAssertEqual(Session.parseArgs(""), [])
    }

    func testOldRowsDecodeWithDefaults() throws {
        let json = #"{"id":"x","name":"n","agent":"claude","repoPath":"/p","lifecycle":"planned"}"#
        let s = try JSONDecoder().decode(Session.self, from: Data(json.utf8))
        XCTAssertEqual(s.agentArgs, [])
        XCTAssertFalse(s.startInRepo)
        XCTAssertFalse(s.openingSent)
        XCTAssertEqual(s.launchDirectory, Workspace.projectsRoot)
    }

    func testHerdrNameIsStable() {
        XCTAssertEqual(Session.runtimeName(for: "1A2B3C4D-0000-1111"), "roof-1a2b3c4d")
    }

    func testLaunchArgsPutModelFirst() {
        var s = Session(name: "x", agent: .claude, repoPath: "/p", agentArgs: ["--resume", "abc"], model: "haiku")
        XCTAssertEqual(s.launchArgs, ["--model", "haiku", "--resume", "abc"])
        s.model = "  "
        XCTAssertEqual(s.launchArgs, ["--resume", "abc"])
        s.agent = .shell
        XCTAssertEqual(s.launchArgs, [], "a plain terminal never gets agent arguments")
    }

    func testSettingsDecodeOldDataWithDefaults() throws {
        let st = try JSONDecoder().decode(AppSettings.self, from: Data("{\"dockBadge\":false}".utf8))
        XCTAssertFalse(st.dockBadge)
        XCTAssertTrue(st.startupCheck)
        XCTAssertEqual(st.defaults(for: .claude).account, "Claude1")
        XCTAssertEqual(st.agenticEngineeringPath, "")                 // empty = the bundled copy
        XCTAssertEqual(st.agenticEngineering.source, ProcessInfo.processInfo.environment["ONEROOF_AE_PATH"] == nil ? .bundled : .environment)
    }
}

final class StoreTests: XCTestCase {
    func testSaveLoadDelete() throws {
        let path = NSTemporaryDirectory() + "oneroof-test-\(UUID().uuidString).sqlite"
        defer { try? FileManager.default.removeItem(atPath: path) }
        let store = try SessionStore(path: path)
        var s = Session(name: "x", repoPath: "/p", workstream: "WS-WEB-12", objective: "o", tags: ["t1"])
        store.save(s)
        s.notes = "updated"
        store.save(s)
        let all = store.all()
        XCTAssertEqual(all.count, 1)
        XCTAssertEqual(all.first?.notes, "updated")
        XCTAssertEqual(all.first?.tags, ["t1"])
        store.delete(id: s.id)
        XCTAssertEqual(store.all().count, 0)
    }
}

final class ConversationTests: XCTestCase {
    func testFolderMangling() {
        XCTAssertEqual(ConversationIndex.folder(forLaunchDirectory: "/Users/x/Projects", configDir: "/Users/x/.claude"),
                       "/Users/x/.claude/projects/-Users-x-Projects")
        XCTAssertEqual(ConversationIndex.folder(forLaunchDirectory: "/Users/x/Projects/labs/one.roof", configDir: "/c"),
                       "/c/projects/-Users-x-Projects-labs-one-roof")
    }

    func testRecentReadsTitlesAndSkipsEmpty() throws {
        let dir = NSTemporaryDirectory() + "oneroof-conv-\(UUID().uuidString)"
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: dir) }
        let a = #"{"type":"user","message":{}}"# + "\n" + #"{"type":"ai-title","aiTitle":"Old title","sessionId":"a"}"# + "\n" +
                #"{"type":"ai-title","aiTitle":"One Roof overnight build","sessionId":"a"}"# + "\n" +
                #"{"type":"last-prompt","lastPrompt":"go overnight","sessionId":"a"}"# + "\n"
        try a.write(toFile: dir + "/aaaa-1111.jsonl", atomically: true, encoding: .utf8)
        try (#"{"type":"mode","mode":"x"}"# + "\n").write(toFile: dir + "/bbbb-2222.jsonl", atomically: true, encoding: .utf8)
        try "not json".write(toFile: dir + "/notes.txt", atomically: true, encoding: .utf8)
        let list = ConversationIndex.recent(in: dir)
        XCTAssertEqual(list.map(\.id), ["aaaa-1111"])
        XCTAssertEqual(list.first?.title, "One Roof overnight build")
        XCTAssertEqual(list.first?.lastPrompt, "go overnight")
        XCTAssertTrue(list.first?.maybeOpen() ?? false)
    }
}

final class StickerTests: XCTestCase {
    func testBuiltInStickersResolveByIdOrLabel() {
        XCTAssertEqual(Sticker.resolve("WIP").id, "wip")
        XCTAssertEqual(Sticker.resolve("Do not use").id, "dnu")
        XCTAssertTrue(Sticker.resolve("important").builtIn)
    }

    func testCustomStickerKeepsItsColour() {
        let a = Sticker.resolve("Data lake"), b = Sticker.resolve("data lake ")
        XCTAssertFalse(a.builtIn)
        XCTAssertEqual(a.pastel, b.pastel)
        XCTAssertEqual(a.label, "Data lake")
    }

    func testPastelTextIsReadableOnLightAndDark() {
        for p in Pastel.all {
            XCTAssertGreaterThanOrEqual(RGB.contrast(p.lightFill, p.lightInk), 4.5, p.name + " light")
            XCTAssertGreaterThanOrEqual(RGB.contrast(p.darkFill, p.darkInk), 4.5, p.name + " dark")
        }
        XCTAssertEqual(Pastel.named("red")?.name, "coral", "old Apple colour names map to pastels")
    }

    func testRowStickersPutStatusFirstWithoutDuplicates() {
        let s = Session(name: "x", repoPath: "/p", tags: ["review", "Next"], lifecycle: .next)
        XCTAssertEqual(Sticker.forSession(s, status: .next).map(\.id), ["next", "review"])
    }

    func testPinnedSessionsGroupFirst() {
        let a = Session(name: "a", repoPath: "/p", lifecycle: .planned, pinned: true)
        let b = Session(name: "b", repoPath: "/p", lifecycle: .planned)
        let groups = Board.group(Board.merge(stored: [a, b], snapshot: RuntimeSnapshot()), by: .status)
        XCTAssertEqual(groups.first?.title, "Pinned")
        XCTAssertEqual(groups.first?.items.map(\.session.name), ["a"])
        XCTAssertEqual(groups.last?.items.map(\.session.name), ["b"])
    }
}

final class FoundationsTests: XCTestCase {
    func testExpectedLinksFromDryRun() {
        let out = "x\n[DRY] ln -sfn /ae/skills/t/a /h/.claude/skills/a\n[DRY] ln -sfn /ae/skills/t/b /h/.kimi-code/skills/b\nLinked: 2"
        let l = Foundations.expectedLinks(out)
        XCTAssertEqual(l.count, 2)
        XCTAssertEqual(l[1].dest, "/h/.kimi-code/skills/b")
        XCTAssertEqual(Foundations.homeLabel(l[0].dest, home: "/h"), "Claude")
        XCTAssertEqual(Foundations.homeLabel(l[1].dest, home: "/h"), "Kimi")
    }

    func testFrontmatter() {
        let fm = Foundations.frontmatter("---\nname: where-are-we\ndescription: \"Orient: read trackers\"\n---\n# body")
        XCTAssertEqual(fm["name"], "where-are-we")
        XCTAssertEqual(fm["description"], "Orient: read trackers")
    }

    func testHookParsing() {
        let settings: [String: Any] = ["hooks": ["UserPromptSubmit": [["hooks": [["type": "command", "command": "bash /nope/guard.sh --x"]]]]]]
        let h = Foundations.parseHooks(settings)
        XCTAssertEqual(h.first?.event, "UserPromptSubmit")
        XCTAssertEqual(h.first?.script, "/nope/guard.sh")
        XCTAssertEqual(h.first?.scriptExists, false)
    }
}

final class IntakeTests: XCTestCase {
    func testSuggestKinds() {
        XCTAssertEqual(Intake.suggest("Login fails on Safari"), .defect)
        XCTAssertEqual(Intake.suggest("Should we use Postgres or SQLite"), .decision)
        XCTAssertEqual(Intake.suggest("Investigate voice latency"), .spike)
        XCTAssertEqual(Intake.suggest("Billing with Stripe end-to-end platform"), .workstream)
        XCTAssertEqual(Intake.suggest("Bump Node to 24"), .chore)
        XCTAssertEqual(Intake.suggest("Add a settings window"), .deliverable)
    }

    func testSimilarFindsDuplicates() {
        func issue(_ id: String, _ t: String) -> LinearIssue {
            LinearIssue(id: id, identifier: id, title: "[ws-x-01] " + t, description: "", state: "Backlog", stateType: "backlog",
                        type: "deliverable", milestoneId: nil, milestone: nil, url: "")
        }
        let list = [issue("ENG-1", "Settings window with themes"), issue("ENG-2", "Kanban board view")]
        XCTAssertEqual(Intake.similar("settings window", in: list).map(\.identifier), ["ENG-1"])
        XCTAssertTrue(Intake.similar("voice capture", in: list).isEmpty)
        XCTAssertEqual(list[0].shortTitle, "Settings window with themes")
    }

    func testWorkstreamTitleAndId() {
        let w = LinearWorkstream(id: "p", name: "WS-WEB-12 · New checkout", state: "started", url: "", team: "ENG", milestones: [])
        XCTAssertEqual(w.wsId, "WS-WEB-12")
        XCTAssertEqual(w.title, "New checkout")
        XCTAssertEqual(w.stateLabel, "In progress")
    }
}

final class ObjectiveTests: XCTestCase {
    let md = """
    # Plan: x
    ```oneroof-plan
    {"objective": "x", "steps": [
      {"id": "s1", "title": "Read", "kind": "research", "agent": "kimi", "depends": [], "prompt": "read"},
      {"id": "s2", "title": "Build", "kind": "code", "agent": "claude", "account": "Claude2", "model": "opus", "depends": ["s1"], "prompt": "build"},
      {"id": "s3", "title": "Review", "kind": "review", "agent": "codex", "depends": ["s2"], "prompt": "review"}],
     "risks": ["r"], "questions": []}
    ```
    """

    func testParsePlanBlock() throws {
        let p = try XCTUnwrap(PlanParser.parse(md))
        XCTAssertEqual(p.steps.map(\.id), ["s1", "s2", "s3"])
        XCTAssertEqual(p.steps[1].agentKind, .claude)
        XCTAssertEqual(p.steps[0].agentKind, .kimi)
        XCTAssertNil(PlanParser.parse("no block here"))
    }

    func testRunnerOrderAndMarkers() throws {
        var o = Objective(title: "x")
        o.plan = PlanParser.parse(md)
        XCTAssertTrue(PlanRunner.toStart(o).isEmpty, "nothing runs before approval")
        o.status = .running
        XCTAssertEqual(PlanRunner.toStart(o).map(\.id), ["s1"])
        o.stepSessions["s1"] = "sess1"
        XCTAssertTrue(PlanRunner.toStart(o).isEmpty, "s2 waits for s1")
        let dir = NSTemporaryDirectory() + "oneroof-run-" + UUID().uuidString
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        try "read it".write(toFile: dir + "/s1.done", atomically: true, encoding: .utf8)
        XCTAssertTrue(PlanRunner.collectMarkers(&o, runDir: dir))
        XCTAssertEqual(PlanRunner.toStart(o).map(\.id), ["s2"])
        try "broke".write(toFile: dir + "/s2.failed", atomically: true, encoding: .utf8)
        o.stepSessions["s2"] = "sess2"
        PlanRunner.collectMarkers(&o, runDir: dir)
        XCTAssertEqual(o.status, .failed)
        XCTAssertEqual(PlanRunner.state(of: o.plan!.steps[2], in: o), .waiting)
    }

    func testPlanPathFallsBackToCommonPlans() throws {
        let c = FileManager.default.temporaryDirectory.appendingPathComponent("shared-\(UUID().uuidString)").path
        try FileManager.default.createDirectory(atPath: c, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: c) }
        let o = Objective(title: "Write a One Roof glossary!")
        XCTAssertTrue(o.planPath(common: c).hasPrefix(c + "/docs/plans/"))
        XCTAssertTrue(o.planPath(common: c).hasSuffix("_write-a-one-roof-glossary.md"))
        XCTAssertTrue(o.runDir(common: c).hasPrefix(c + "/scratchpad/oneroof-runs/"))
    }

    func testPlanPathWithoutSharedFolderUsesAppSupport() {
        let o = Objective(title: "No shared folder")
        let missing = "/nonexistent-\(UUID().uuidString)"
        XCTAssertTrue(o.planPath(common: missing).hasPrefix(Workspace.appSupport + "/plans/"))
        XCTAssertTrue(o.runDir(common: missing).hasPrefix(Workspace.appSupport + "/runs/"))
    }
}

final class RouterTests: XCTestCase {
    let policy = RoutingPolicy.load(agenticEngineering: AEFolder.bundled ?? "")   // the bundled package's routing.json

    func testResearchGoesToKimi() {
        XCTAssertEqual(Router.suggest(kind: "research", usage: [], policy: policy).agent, .kimi)
    }

    func testCodePicksTheEmptierClaudeSeat() {
        let u = [SeatUsage(seat: "Claude1", fiveHour: 70, sevenDay: 40, updated: Date()),
                 SeatUsage(seat: "Claude2", fiveHour: 10, sevenDay: 20, updated: Date())]
        let r = Router.suggest(kind: "code", usage: u, policy: policy, claudeSeats: ["Claude1", "Claude2"])
        XCTAssertEqual(r.agent, .claude)
        XCTAssertEqual(r.account, "Claude2")
        XCTAssertTrue(r.reason.contains("Claude2"))
    }

    func testFullSeatsAreSkipped() {
        let u = [SeatUsage(seat: "Claude1", fiveHour: 95, updated: Date()), SeatUsage(seat: "Claude2", fiveHour: 99, updated: Date())]
        let r = Router.suggest(kind: "code", usage: u, policy: policy, claudeSeats: ["Claude1", "Claude2"])
        XCTAssertEqual(r.agent, .codex)
        XCTAssertTrue(r.reason.contains("skipped"))
    }

    func testLightBudgetAvoidsOpusAndReviewAvoidsAuthor() {
        XCTAssertNotEqual(Router.suggest(kind: "code", budget: "light", usage: [], policy: policy).model, "opus")
        XCTAssertNotEqual(Router.suggest(kind: "review", usage: [], policy: policy, avoid: .codex).agent, .codex)
    }

    func testClaudeUsageFileParsing() throws {
        let dir = NSTemporaryDirectory() + "oneroof-usage-" + UUID().uuidString
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        try #"{"lane":"Claude1","rate_limits":{"five_hour":{"used_percentage":24.4,"resets_at":1792280000},"seven_day":{"used_percentage":61}},"updated":1792268582}"#
            .write(toFile: dir + "/Claude1.json", atomically: true, encoding: .utf8)
        let u = Usage.claude(dir: dir)
        XCTAssertEqual(u.first?.seat, "Claude1")
        XCTAssertEqual(u.first?.fiveHour, 24.4)
        XCTAssertEqual(u.first?.worst, 61)
    }
}

final class LocalModelTests: XCTestCase {
    func testParseRoute() {
        let ok: Set<String> = ["code", "docs"]
        XCTAssertEqual(LocalModel.parseRoute(#"{"route": "code"}"#, allowed: ok), "code")
        XCTAssertEqual(LocalModel.parseRoute("{'route': 'docs'}", allowed: ok), "docs")
        XCTAssertNil(LocalModel.parseRoute(#"{"route": "other"}"#, allowed: ok))
        XCTAssertNil(LocalModel.parseRoute("no idea", allowed: ok))
    }
}

final class RoleTests: XCTestCase {
    func testRolesReadFromTheBundledPackage() throws {
        let ae = try XCTUnwrap(AEFolder.bundled, "agentic_engineering/ is next to app/ in the checkout")
        let roles = Role.load(agenticEngineering: ae)
        XCTAssertGreaterThanOrEqual(roles.count, 8)
        let review = roles.first { $0.id == "review" }
        XCTAssertEqual(review?.skill, "second-opinion")
        XCTAssertEqual(review?.agent, .codex)
        XCTAssertTrue(review?.opening(repo: "acme/web", workstream: nil).contains("acme/web") ?? false)
        // Every role names a skill that exists in the package.
        let names = Set(Foundations.skills(FoundationPaths(agenticEngineering: ae)).map(\.name))
        for r in roles { XCTAssertTrue(names.contains(r.skill), r.skill) }
    }
}

final class AEFolderTests: XCTestCase {
    func temp(_ name: String, routing: String? = nil) throws -> String {
        let d = NSTemporaryDirectory() + "oneroof-ae-\(name)-" + UUID().uuidString
        try FileManager.default.createDirectory(atPath: d + "/skills/x", withIntermediateDirectories: true)
        if let routing {
            try FileManager.default.createDirectory(atPath: d + "/skills/" + routing, withIntermediateDirectories: true)
            try #"{"kinds": {"research": [{"agent": "codex"}]}}"#.write(toFile: d + "/skills/" + routing + "/routing.json", atomically: true, encoding: .utf8)
        }
        return d
    }

    func testOrderIsEnvironmentThenSettingsThenBundled() throws {
        let env = try temp("env"), mine = try temp("mine"), bundled = try temp("bundled")
        XCTAssertEqual(AEFolder.resolve(setting: mine, environment: ["ONEROOF_AE_PATH": env], bundled: bundled).source, .environment)
        XCTAssertEqual(AEFolder.resolve(setting: mine, environment: [:], bundled: bundled), .init(path: mine, source: .settings))
        XCTAssertEqual(AEFolder.resolve(setting: "", environment: [:], bundled: bundled), .init(path: bundled, source: .bundled))
        // A setting that no longer exists falls back to the bundled copy rather than breaking routing and Learn.
        XCTAssertEqual(AEFolder.resolve(setting: "/nope/gone", environment: [:], bundled: bundled).source, .bundled)
        XCTAssertEqual(AEFolder.resolve(setting: "", environment: [:], bundled: nil).source, .missing)
    }

    func testRoutingFolderIsFoundInAnyGroupAndOldLayout() throws {
        let new = try temp("new", routing: "fleet/agent-routing"), old = try temp("old", routing: "doctrine/harness-routing")
        XCTAssertTrue(AEFolder.routingDir(new)?.hasSuffix("fleet/agent-routing") ?? false)
        XCTAssertTrue(AEFolder.routingDir(old)?.hasSuffix("doctrine/harness-routing") ?? false)
        XCTAssertEqual(Router.suggest(kind: "research", usage: [], policy: RoutingPolicy.load(agenticEngineering: new)).agent, .codex)
        XCTAssertNil(AEFolder.routingDir(try temp("none")))
    }

    func testBundledPackageIsComplete() throws {
        let ae = try XCTUnwrap(AEFolder.bundled)
        XCTAssertGreaterThanOrEqual(Foundations.skills(FoundationPaths(agenticEngineering: ae)).count, 17)
        XCTAssertEqual(RoutingPolicy.kindDescriptions(agenticEngineering: ae)["chore"]?.hasPrefix("Housekeeping"), true)
        XCTAssertEqual(CourseAudio.title(slugFile: "03-check-after-every-hop.mp3"), "Check after every hop")
    }
}


final class FoundationsPythonTests: XCTestCase {
    /// The MCP check must not fall back to a python3 without tomllib (Finder's bare PATH gives the system 3.9).
    func testPickedPythonHasTomllib() throws {
        guard let py = Foundations.python3() else { throw XCTSkip("no Python 3.11+ on this Mac") }
        XCTAssertEqual(Foundations.run(py, ["-c", "import tomllib"]).0, 0)
    }
}

/// ENG-627: One Roof's docs moved to acme/web/docs/workstreams; plans and Help must still find them.
final class DocsFolderTests: XCTestCase {
    func testFindsRepoDocsWorkstreamsAndPrefersCommon() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("docsfolder-\(UUID().uuidString)").path
        defer { try? FileManager.default.removeItem(atPath: root) }
        let fm = FileManager.default
        try fm.createDirectory(atPath: root + "/acme/web/docs/workstreams/ws-x-01", withIntermediateDirectories: true)
        try fm.createDirectory(atPath: root + "/acme/acme-app/docs/workstreams/ws-y-01", withIntermediateDirectories: true)
        let shared = root + "/_common"
        XCTAssertEqual(Trackers.docsFolder(for: "WS-X-01", root: root, shared: shared), root + "/acme/web/docs/workstreams/ws-x-01")
        XCTAssertEqual(Trackers.docsFolder(for: "WS-Y-01", root: root, shared: shared), root + "/acme/acme-app/docs/workstreams/ws-y-01")
        try fm.createDirectory(atPath: shared + "/docs/workstreams/ws-x-01", withIntermediateDirectories: true)
        XCTAssertEqual(Trackers.docsFolder(for: "WS-X-01", root: root, shared: shared), shared + "/docs/workstreams/ws-x-01")
        XCTAssertNil(Trackers.docsFolder(for: "WS-NONE-01", root: root, shared: shared))
        // A docs-only repo (<domain>/<name>-docs/workstreams/<id>) comes before a code repo's docs/ folder.
        try fm.createDirectory(atPath: root + "/acme/acme-docs/workstreams/ws-y-01", withIntermediateDirectories: true)
        XCTAssertEqual(Trackers.docsFolder(for: "WS-Y-01", root: root, shared: shared), root + "/acme/acme-docs/workstreams/ws-y-01")
        // Any shared folder, not just one named _common.
        try fm.createDirectory(atPath: root + "/team-rules/docs/workstreams/ws-y-01", withIntermediateDirectories: true)
        XCTAssertEqual(Trackers.docsFolder(for: "WS-Y-01", root: root, shared: root + "/team-rules"), root + "/team-rules/docs/workstreams/ws-y-01")
    }
}
