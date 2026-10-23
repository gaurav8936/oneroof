import XCTest
@testable import OneRoofCore

/// LAB-652: subagents found from the exact conversation (the claude process's sessions file) and from the
/// subagents/agent-*.jsonl + .meta.json files, even when the parent's Agent call is far outside the main file's tail.
final class SubagentFilesTests: XCTestCase {
    func iso(_ s: String) -> Date { ClaudeTranscript.date(s)! }

    // MARK: Meta files

    func testMetaParse() {
        let json = #"{"agentType":"Explore","description":"Subagent for Overview check","toolUseId":"toolu_017K","spawnDepth":1,"requestShape":"background","requestNonInteractive":true,"model":"haiku"}"#
        let m = SubagentMeta.parse(Data(json.utf8))
        XCTAssertEqual(m, SubagentMeta(toolUseId: "toolu_017K", agentType: "Explore", description: "Subagent for Overview check",
                                       model: "haiku", spawnDepth: 1, background: true))
        let fg = SubagentMeta.parse(Data(#"{"agentType":"general-purpose","toolUseId":"toolu_X"}"#.utf8))
        XCTAssertEqual(fg?.background, false)
        XCTAssertNil(fg?.description)
        XCTAssertNil(SubagentMeta.parse(Data(#"{"agentType":"Explore"}"#.utf8)))   // no tool use id: cannot place it
        XCTAssertNil(SubagentMeta.parse(Data("not json".utf8)))
    }

    func testMetaPath() {
        XCTAssertEqual(SubagentMeta.metaPath(forTranscript: "/p/s/subagents/agent-abc.jsonl"), "/p/s/subagents/agent-abc.meta.json")
    }

    // MARK: Done signals

    func testTaskNotifications() {
        let text = "<task-notification>\n<task-id>ae6</task-id>\n<tool-use-id>toolu_A</tool-use-id>\n<status>completed</status>\n<summary>Agent done</summary>\n</task-notification>"
            + " noise <task-notification><tool-use-id>toolu_B</tool-use-id><status>killed</status></task-notification>"
            + "<task-notification><task-id>x</task-id></task-notification>"   // no tool use id: ignored
        let n = ClaudeTranscript.taskNotifications(text)
        XCTAssertEqual(n.map(\.toolUseId), ["toolu_A", "toolu_B"])
        XCTAssertEqual(n.map(\.status), ["completed", "killed"])
        XCTAssertTrue(ClaudeTranscript.taskNotifications("a <task-notification> arrives when the workflow completes").isEmpty)
    }

    /// A background Agent's tool_result only says it launched: not its end. The task-notification is.
    func testBackgroundLaunchIsNotTheEnd() {
        let launched = ClaudeTranscript.subagents(jsonl: Fixture.backgroundMain, sessionId: "s")
        XCTAssertEqual(launched.count, 1)
        XCTAssertNil(launched[0].ended)
        XCTAssertEqual(launched[0].status, .running)

        let finished = ClaudeTranscript.subagents(jsonl: Fixture.backgroundMain + "\n" + Fixture.backgroundNotice, sessionId: "s")
        XCTAssertEqual(finished[0].ended, iso("2026-10-23T19:39:27.468Z"))
        XCTAssertEqual(finished[0].status, .done)
    }

    // MARK: Meta-seeded tree

    func testTreeSeededFromMetaFiles() {
        let now = iso("2026-10-23T22:00:00.000Z")
        let subs = ClaudeTranscript.subagents(main: Fixture.mainTailWithoutAgentCalls, files: Fixture.agentFiles(now: now), sessionId: "s1", now: now)
        XCTAssertEqual(subs.map(\.id), ["toolu_LANE_A", "toolu_LANE_B", "toolu_NESTED", "toolu_STALE", "toolu_RUN", "toolu_QUIET"])
        let byId = Dictionary(uniqueKeysWithValues: subs.map { ($0.id, $0) })

        // Ended by the task-notification in the main file's tail.
        let a = byId["toolu_LANE_A"]!
        XCTAssertEqual(a.name, "R1 lane A: window identity")
        XCTAssertEqual(a.asked, "You are Lane A.")
        XCTAssertEqual(a.started, iso("2026-10-23T19:31:09.409Z"))   // the file's first line (from the head read)
        XCTAssertEqual(a.ended, iso("2026-10-23T19:39:27.468Z"))
        XCTAssertEqual(a.model, "claude-opus-5-5")
        XCTAssertEqual(a.touched, [FileTouch(path: "/r/app/Toolbar.swift", added: 1, removed: 1)])
        XCTAssertNil(a.parentId)
        XCTAssertEqual(a.depth, 1)

        // Ended by its SubagentHandback result; started a nested agent.
        let b = byId["toolu_LANE_B"]!
        XCTAssertEqual(b.ended, iso("2026-10-23T19:48:13.671Z"))
        XCTAssertEqual(b.model, "haiku")                                // from the meta
        XCTAssertEqual(b.tokens, 30)

        let nested = byId["toolu_NESTED"]!
        XCTAssertEqual(nested.parentId, "toolu_LANE_B")
        XCTAssertEqual(nested.depth, 2)
        XCTAssertEqual(nested.name, "Check one file")
        XCTAssertEqual(nested.asked, "Read Toolbar.swift")
        XCTAssertEqual(nested.ended, iso("2026-10-23T19:45:00.000Z"))  // the foreground result in B's file
        XCTAssertEqual(nested.lastText, "Toolbar is fine.")

        // Still running: a tool call is waiting, and the file changed 10 minutes ago (less than the stale hour).
        let run = byId["toolu_RUN"]!
        XCTAssertNil(run.ended)
        XCTAssertTrue(run.isRunning)

        // Its own words last, nothing waiting, quiet for 10 minutes: done at that line.
        XCTAssertEqual(byId["toolu_QUIET"]!.ended, iso("2026-10-23T21:40:00.000Z"))
        XCTAssertEqual(byId["toolu_QUIET"]!.lastText, "All done, report below.")

        // A pending tool call but no write for two hours: stopped.
        XCTAssertEqual(byId["toolu_STALE"]!.ended, iso("2026-10-23T19:50:00.000Z"))

        XCTAssertEqual(SubagentTree.summary(subs), "1 running · 5 done")
    }

    /// The quiet rule waits: the same agent words-only last line, written two minutes ago, is still running.
    func testQuietRuleWaitsFiveMinutes() {
        let now = iso("2026-10-23T21:42:00.000Z")
        let file = SubagentFile(meta: SubagentMeta(toolUseId: "toolu_QUIET", description: "Quiet"),
                                tail: Fixture.quietTail, modified: iso("2026-10-23T21:40:00.000Z"))
        let subs = ClaudeTranscript.subagents(main: "", files: [file], sessionId: "s", now: now)
        XCTAssertNil(subs[0].ended)
    }

    /// The parent's Agent call in the main tail (normal case) and the meta agree: one task, the call's prompt kept.
    func testMetaAndParentCallMerge() {
        let now = iso("2026-10-23T20:00:00.000Z")
        let file = SubagentFile(meta: SubagentMeta(toolUseId: "toolu_A", description: "R1 lane A: window identity"),
                                tail: Fixture.laneATail, modified: now)
        let subs = ClaudeTranscript.subagents(main: Fixture.backgroundMain, files: [file], sessionId: "s", now: now)
        XCTAssertEqual(subs.count, 1)
        XCTAssertEqual(subs[0].id, "toolu_A")
        XCTAssertEqual(subs[0].started, iso("2026-10-23T19:31:00.000Z"))   // the Agent call, earlier than the file
        XCTAssertNil(subs[0].ended)                                        // launch ack only, file just written
    }

    /// Files without a meta still go through the old concatenated reading.
    func testFilesWithoutMetaUseTheOldMatching() {
        let now = Date()
        let subs = ClaudeTranscript.subagents(main: Fixture.transcript, files: [], sessionId: "s1", now: now)
        XCTAssertEqual(subs, ClaudeTranscript.subagents(jsonl: Fixture.transcript, sessionId: "s1"))
        let split = Fixture.transcript.components(separatedBy: "\n")
        let main = split.filter { !$0.contains("\"isSidechain\":true") }.joined(separator: "\n")
        let side = split.filter { $0.contains("\"isSidechain\":true") }.joined(separator: "\n")
        let viaFile = ClaudeTranscript.subagents(main: main, files: [SubagentFile(meta: nil, tail: side)], sessionId: "s1", now: now)
        XCTAssertEqual(viaFile.map(\.id), ["toolu_A", "toolu_B", "toolu_C"])
        XCTAssertEqual(viaFile.first { $0.id == "toolu_C" }?.lastText, "Writing thirty fixtures now.")
    }

    // MARK: Which conversation

    func testIsClaude() {
        XCTAssertTrue(ClaudeSessionLocator.isClaude(name: "claude", argv: ["claude"]))
        XCTAssertTrue(ClaudeSessionLocator.isClaude(name: nil, argv: ["/opt/homebrew/Caskroom/claude-code/2.1.287/claude", "--resume"]))
        XCTAssertTrue(ClaudeSessionLocator.isClaude(name: "node", argv: ["node", "/usr/local/lib/node_modules/@anthropic-ai/claude-code/cli.js"]))
        XCTAssertTrue(ClaudeSessionLocator.isClaude(name: "node", argv: ["/usr/local/bin/node", "/Users/x/.local/bin/claude"]))
        XCTAssertFalse(ClaudeSessionLocator.isClaude(name: "zsh", argv: ["-zsh"]))
        XCTAssertFalse(ClaudeSessionLocator.isClaude(name: "node", argv: ["node", "server.js"]))
        XCTAssertFalse(ClaudeSessionLocator.isClaude(name: "codex", argv: ["codex", "--model", "claude"]))
        XCTAssertFalse(ClaudeSessionLocator.isClaude(name: "claude-monitor", argv: ["claude-monitor"]))
    }

    func testClaudePidPicksTheOutermostClaude() {
        typealias P = ClaudeSessionLocator.Proc
        // Shell → claude → a claude it started (e.g. `claude -p` in a Bash tool) → git.
        let tree = [P(pid: 100, ppid: 1, name: "zsh", argv: ["-zsh"]), P(pid: 300, ppid: 200, name: "claude", argv: ["claude", "-p"]),
                    P(pid: 200, ppid: 100, name: "claude", argv: ["claude"]), P(pid: 400, ppid: 300, name: "git", argv: ["git"])]
        XCTAssertEqual(ClaudeSessionLocator.claudePid(in: tree), 200)
        // The foreground group (no parent pids known): lowest claude pid.
        XCTAssertEqual(ClaudeSessionLocator.claudePid(in: [P(pid: 900, name: "rg"), P(pid: 512, name: "claude"), P(pid: 700, name: "claude")]), 512)
        XCTAssertNil(ClaudeSessionLocator.claudePid(in: [P(pid: 5, name: "zsh", argv: ["-zsh"])]))
        XCTAssertNil(ClaudeSessionLocator.claudePid(in: []))
    }

    func testSessionFile() {
        XCTAssertEqual(ClaudeSessionLocator.sessionFile(configDir: "/Users/x/.claude-2", pid: 69974), "/Users/x/.claude-2/sessions/69974.json")
        let json = #"{"pid":69974,"sessionId":"dd6b80d8-d858","cwd":"/Users/x/Projects","startedAt":1792783213100,"version":"2.1.287","kind":"interactive","status":"busy"}"#
        XCTAssertEqual(ClaudeSessionLocator.parseSessionFile(Data(json.utf8), pid: 69974),
                       ClaudeSessionLocator.Live(pid: 69974, sessionId: "dd6b80d8-d858", cwd: "/Users/x/Projects"))
        XCTAssertEqual(ClaudeSessionLocator.parseSessionFile(Data(json.utf8))?.pid, 69974)
        XCTAssertNil(ClaudeSessionLocator.parseSessionFile(Data(json.utf8), pid: 1234))   // a reused file name for another pid
        XCTAssertNil(ClaudeSessionLocator.parseSessionFile(Data(#"{"pid":1}"#.utf8)))
        XCTAssertNil(ClaudeSessionLocator.parseSessionFile(Data("[]".utf8)))
    }

    func testConfigDirsOrder() {
        XCTAssertEqual(ClaudeSessionLocator.configDirs(processEnv: ["CLAUDE_CONFIG_DIR": "/h/.claude-2"], account: nil, home: "/h"),
                       ["/h/.claude-2", "/h/.claude"])
        XCTAssertEqual(ClaudeSessionLocator.configDirs(processEnv: nil, account: "/h/.claude-2", home: "/h"), ["/h/.claude-2", "/h/.claude"])
        XCTAssertEqual(ClaudeSessionLocator.configDirs(processEnv: ["CLAUDE_CONFIG_DIR": "/h/.claude"], account: "/h/.claude", home: "/h"),
                       ["/h/.claude"])
        XCTAssertEqual(ClaudeSessionLocator.configDirs(processEnv: [:], account: nil, home: "/h"), ["/h/.claude"])
    }

    func testTitleIsOnlyTheFallback() {
        let convs = [Conversation(id: "a", title: "LAB-ONEROOF v0.50 backlog analysis", lastPrompt: nil, modified: Date()),
                     Conversation(id: "b", title: "Building v0.50", lastPrompt: nil, modified: Date())]
        XCTAssertEqual(ClaudeSessionLocator.byTitle(" Building v0.50 ", in: convs)?.id, "b")
        XCTAssertNil(ClaudeSessionLocator.byTitle("Misc", in: convs))
        XCTAssertNil(ClaudeSessionLocator.byTitle(nil, in: convs))
        XCTAssertNil(ClaudeSessionLocator.byTitle("  ", in: convs))
    }
}

extension Fixture {
    /// The main file around a background Agent call: the call, then its launch ack (real shape from Claude Code 2.1.287).
    static let backgroundMain = """
    {"parentUuid":"p0","isSidechain":false,"type":"assistant","uuid":"m1","timestamp":"2026-10-23T19:31:00.000Z","message":{"role":"assistant","model":"claude-opus-5-5","content":[{"type":"tool_use","id":"toolu_A","name":"Agent","input":{"description":"R1 lane A: window identity","subagent_type":"general-purpose","prompt":"You are Lane A."}}]}}
    {"parentUuid":"m1","isSidechain":false,"type":"user","uuid":"m2","timestamp":"2026-10-23T19:31:09.500Z","toolUseResult":{"isAsync":true,"status":"async_launched","agentId":"ae6"},"message":{"role":"user","content":[{"tool_use_id":"toolu_A","type":"tool_result","content":[{"type":"text","text":"Async agent launched successfully.\\nagentId: ae6"}]}]}}
    """

    static let backgroundNotice = """
    {"type":"queue-operation","operation":"enqueue","timestamp":"2026-10-23T19:39:27.468Z","sessionId":"s","content":"<task-notification>\\n<task-id>ae6</task-id>\\n<tool-use-id>toolu_A</tool-use-id>\\n<status>completed</status>\\n<summary>Agent \\"R1 lane A\\" completed</summary>\\n</task-notification>"}
    {"parentUuid":"m9","isSidechain":false,"type":"attachment","timestamp":"2026-10-23T19:39:31.700Z","attachment":{"type":"queued_command","prompt":"<task-notification>\\n<task-id>ae6</task-id>\\n<tool-use-id>toolu_A</tool-use-id>\\n<status>completed</status>\\n</task-notification>"}}
    """

    /// 3 MB of a long session: the Agent calls are far back, only the end notice for lane A is in view.
    static let mainTailWithoutAgentCalls = """
    ":"partial line cut by the tail read"}
    {"parentUuid":"x1","isSidechain":false,"type":"assistant","uuid":"x2","timestamp":"2026-10-23T19:39:00.000Z","message":{"role":"assistant","content":[{"type":"text","text":"Waiting on the lanes."}]}}
    """ + "\n" + backgroundNotice.replacingOccurrences(of: "toolu_A", with: "toolu_LANE_A")

    static let laneATail = """
    {"parentUuid":null,"isSidechain":true,"agentId":"ae6","type":"user","uuid":"a1","timestamp":"2026-10-23T19:31:09.409Z","message":{"role":"user","content":"You are Lane A."}}
    {"parentUuid":"a1","isSidechain":true,"agentId":"ae6","type":"assistant","uuid":"a2","timestamp":"2026-10-23T19:35:00.000Z","message":{"role":"assistant","model":"claude-opus-5-5","content":[{"type":"tool_use","id":"toolu_e1","name":"Edit","input":{"file_path":"/r/app/Toolbar.swift","old_string":"a","new_string":"b"}}],"usage":{"input_tokens":5,"output_tokens":5}}}
    """

    static let quietTail = """
    {"parentUuid":"q1","isSidechain":true,"type":"assistant","uuid":"q2","timestamp":"2026-10-23T21:39:00.000Z","message":{"role":"assistant","content":[{"type":"tool_use","id":"toolu_q","name":"Bash","input":{"command":"swift test"}}]}}
    {"parentUuid":"q2","isSidechain":true,"type":"user","uuid":"q3","timestamp":"2026-10-23T21:39:30.000Z","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"toolu_q","content":"ok"}]}}
    {"parentUuid":"q3","isSidechain":true,"type":"assistant","uuid":"q4","timestamp":"2026-10-23T21:40:00.000Z","message":{"role":"assistant","content":[{"type":"text","text":"All done, report below."}]}}
    """

    /// The subagents folder of that session: five files with metas (one nested), as read for one scan at `now`.
    static func agentFiles(now: Date) -> [SubagentFile] {
        func ago(_ s: TimeInterval) -> Date { now.addingTimeInterval(-s) }
        let laneAHead = #"{"parentUuid":null,"isSidechain":true,"agentId":"ae6","type":"user","uuid":"a1","timestamp":"2026-10-23T19:31:09.409Z","message":{"role":"user","content":"You are Lane A."}}"#
        let laneA = SubagentFile(meta: SubagentMeta(toolUseId: "toolu_LANE_A", agentType: "general-purpose", description: "R1 lane A: window identity", background: true),
                                 head: laneAHead,
                                 tail: "{\"cut\n" + laneATail.components(separatedBy: "\n").dropFirst().joined(separator: "\n"),
                                 modified: ago(2 * 3600))
        let laneB = SubagentFile(meta: SubagentMeta(toolUseId: "toolu_LANE_B", description: "R1 lane B: viewer", model: "haiku", background: true), tail: """
        {"parentUuid":null,"isSidechain":true,"type":"user","uuid":"b1","timestamp":"2026-10-23T19:31:09.425Z","message":{"role":"user","content":"You are Lane B."}}
        {"parentUuid":"b1","isSidechain":true,"type":"assistant","uuid":"b2","timestamp":"2026-10-23T19:40:00.000Z","message":{"role":"assistant","model":"claude-haiku-4-5","content":[{"type":"tool_use","id":"toolu_NESTED","name":"Agent","input":{"description":"Check one file","subagent_type":"Explore","prompt":"Read Toolbar.swift"}}],"usage":{"input_tokens":10,"output_tokens":10}}}
        {"parentUuid":"b2","isSidechain":true,"type":"user","uuid":"b3","timestamp":"2026-10-23T19:45:00.000Z","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"toolu_NESTED","content":"Toolbar is fine."}]}}
        {"parentUuid":"b3","isSidechain":true,"type":"assistant","uuid":"b4","timestamp":"2026-10-23T19:48:13.173Z","message":{"role":"assistant","content":[{"type":"tool_use","id":"toolu_hb","name":"SubagentHandback","input":{"message":"Lane B done."}}],"usage":{"input_tokens":5,"output_tokens":5}}}
        {"parentUuid":"b4","isSidechain":true,"type":"user","uuid":"b5","timestamp":"2026-10-23T19:48:13.671Z","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"toolu_hb","content":[{"type":"text","text":"{\\"success\\":true}"}]}]}}
        """, modified: ago(2 * 3600))
        let nested = SubagentFile(meta: SubagentMeta(toolUseId: "toolu_NESTED", agentType: "Explore", description: "Check one file", spawnDepth: 2), tail: """
        {"parentUuid":null,"isSidechain":true,"type":"user","uuid":"n1","timestamp":"2026-10-23T19:40:01.000Z","message":{"role":"user","content":"Read Toolbar.swift"}}
        {"parentUuid":"n1","isSidechain":true,"type":"assistant","uuid":"n2","timestamp":"2026-10-23T19:44:00.000Z","message":{"role":"assistant","content":[{"type":"text","text":"Toolbar is fine."}]}}
        """, modified: ago(2 * 3600))
        let running = SubagentFile(meta: SubagentMeta(toolUseId: "toolu_RUN", description: "Run the full suite", background: true), tail: """
        {"parentUuid":null,"isSidechain":true,"type":"user","uuid":"r1","timestamp":"2026-10-23T21:30:00.000Z","message":{"role":"user","content":"Run swift test."}}
        {"parentUuid":"r1","isSidechain":true,"type":"assistant","uuid":"r2","timestamp":"2026-10-23T21:50:00.000Z","message":{"role":"assistant","content":[{"type":"tool_use","id":"toolu_long","name":"Bash","input":{"command":"swift test"}}]}}
        """, modified: ago(10 * 60))
        let quiet = SubagentFile(meta: SubagentMeta(toolUseId: "toolu_QUIET", description: "Quiet one"),
                                 tail: #"{"parentUuid":null,"isSidechain":true,"type":"user","uuid":"q1","timestamp":"2026-10-23T21:38:00.000Z","message":{"role":"user","content":"Go."}}"# + "\n" + quietTail,
                                 modified: ago(20 * 60))
        let stale = SubagentFile(meta: SubagentMeta(toolUseId: "toolu_STALE", description: "Interrupted one"), tail: """
        {"parentUuid":null,"isSidechain":true,"type":"user","uuid":"t1","timestamp":"2026-10-23T19:45:30.000Z","message":{"role":"user","content":"Go."}}
        {"parentUuid":"t1","isSidechain":true,"type":"assistant","uuid":"t2","timestamp":"2026-10-23T19:50:00.000Z","message":{"role":"assistant","content":[{"type":"tool_use","id":"toolu_s","name":"Bash","input":{"command":"sleep 99999"}}]}}
        """, modified: ago(2 * 3600))
        return [laneB, stale, quiet, running, laneA, nested]
    }
}
