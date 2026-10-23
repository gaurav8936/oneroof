import Foundation

// The subagent tracker (v2, ENGINES §4, decision D6). Claude is exact: its transcript JSONL marks subagent entries
// `isSidechain: true`, tied to the parent's `Task` tool call; the Task input is what was asked, the tool result is the
// end. Codex, Kimi and Gemini have no such record: their "children" are new processes under the session,
// labelled inferred.

public struct FileTouch: Codable, Equatable, Sendable {
    public var path: String
    public var added: Int
    public var removed: Int
    public var read: Bool
    public init(path: String, added: Int = 0, removed: Int = 0, read: Bool = false) {
        self.path = path; self.added = added; self.removed = removed; self.read = read
    }
}

public struct Subagent: Codable, Equatable, Identifiable, Sendable {
    /// The Task tool_use id (Claude) or "pane:<id>" (inferred).
    public var id: String
    /// The subagent that started this one; nil = started by the session itself.
    public var parentId: String?
    public var sessionId: String
    public var name: String
    public var model: String
    /// The parent's prompt to it (Task input).
    public var asked: String
    public var caption: String
    public var tokens: Int
    public var started: Date
    public var ended: Date?
    public var status: SessionStatus
    public var inferred: Bool
    public var touched: [FileTouch]
    /// 1 = started by the session, 2 = by a subagent, …
    public var depth: Int
    /// Its own latest words, for its caption.
    public var lastText: String?

    public init(id: String, parentId: String? = nil, sessionId: String, name: String, model: String = "", asked: String = "",
                caption: String = "", tokens: Int = 0, started: Date, ended: Date? = nil, status: SessionStatus = .running,
                inferred: Bool = false, touched: [FileTouch] = [], depth: Int = 1, lastText: String? = nil) {
        self.id = id; self.parentId = parentId; self.sessionId = sessionId; self.name = name; self.model = model; self.asked = asked
        self.caption = caption; self.tokens = tokens; self.started = started; self.ended = ended; self.status = status
        self.inferred = inferred; self.touched = touched; self.depth = depth; self.lastText = lastText
    }

    public var isRunning: Bool { ended == nil && status == .running }

    public func duration(now: Date = Date()) -> TimeInterval { (ended ?? now).timeIntervalSince(started) }
}

public enum ClaudeTranscript {
    /// ~/.claude/projects/<mangled cwd>/<session id>.jsonl (configDir = the account's ~/.claude or ~/.claude-2).
    public static func path(configDir: String, cwd: String, sessionId: String) -> String {
        ConversationIndex.folder(forLaunchDirectory: cwd, configDir: configDir) + "/\(sessionId).jsonl"
    }

    /// Newer Claude Code writes each subagent to <project folder>/<session id>/subagents/*.jsonl.
    public static func subagentsFolder(configDir: String, cwd: String, sessionId: String) -> String {
        ConversationIndex.folder(forLaunchDirectory: cwd, configDir: configDir) + "/\(sessionId)/subagents"
    }

    static let taskTools: Set<String> = ["Task", "Agent"]
    /// The tool a background subagent calls last to hand its report back (its tool_result = the agent is finished).
    static let handbackTools: Set<String> = ["SubagentHandback"]

    /// LAB-652 done rule, quiet part: a subagent file whose last entry is the agent's own words (no tool call waiting)
    /// and that has not grown for this long is finished.
    public static let quietDone: TimeInterval = 5 * 60
    /// …and a subagent file that has not grown at all for this long is treated as stopped, whatever its last line
    /// (an agent interrupted with Esc, or whose end notice scrolled out of the main file's tail).
    public static let staleDone: TimeInterval = 60 * 60

    private final class TaskInfo {
        var id: String
        var owner: String?
        var name: String
        var asked: String
        var model: String
        var started: Date
        var ended: Date?
        var tokens = 0
        var assigned = false
        var lastText: String?
        var touched: [String: FileTouch] = [:]
        var order: [String] = []
        init(id: String, owner: String?, name: String, asked: String, model: String, started: Date) {
            self.id = id; self.owner = owner; self.name = name; self.asked = asked; self.model = model; self.started = started
        }
        func touch(_ path: String, added: Int = 0, removed: Int = 0, read: Bool = false) {
            if touched[path] == nil { touched[path] = FileTouch(path: path); order.append(path) }
            touched[path]!.added += added; touched[path]!.removed += removed; touched[path]!.read = touched[path]!.read || read
        }
        func end(_ at: Date) { if ended == nil || at < ended! { ended = at } }
    }

    /// What the last event line of a subagent file says (for the quiet rule).
    private struct LastEntry { var at: Date; var agentWordsOnly: Bool }

    /// One pass over transcript lines, shared by the main file and every subagent file.
    private final class Builder {
        var tasks: [String: TaskInfo] = [:]
        var taskOrder: [String] = []
        var uuidGroup: [String: String] = [:]
        var handbacks: [String: String] = [:]   // handback tool_use id → the task whose file it is in

        @discardableResult
        func task(id: String, owner: String?, name: String, asked: String, model: String, started: Date) -> TaskInfo {
            if let t = tasks[id] {
                // Seeded from its meta file first: the parent's tool_use fills in what the meta does not carry.
                if t.owner == nil, let owner, owner != id { t.owner = owner }
                if t.asked.isEmpty { t.asked = asked }
                if t.model.isEmpty { t.model = model }
                if started < t.started { t.started = started }
                return t
            }
            let t = TaskInfo(id: id, owner: owner, name: name, asked: asked, model: model, started: started)
            tasks[id] = t
            taskOrder.append(id)
            return t
        }

        /// Parse lines; `forced` = every line belongs to this task (a subagent file with its meta).
        /// Returns the last user/assistant entry seen.
        @discardableResult
        func consume(_ jsonl: String, forced: String? = nil) -> LastEntry? {
            var last: LastEntry?
            for line in jsonl.split(separator: "\n") {
                guard line.first == "{", let obj = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any] else { continue }
                let at = (obj["timestamp"] as? String).flatMap(ClaudeTranscript.date) ?? Date(timeIntervalSince1970: 0)
                let message = obj["message"] as? [String: Any]
                let content = message?["content"] as? [[String: Any]] ?? []
                notifications(obj, at: at)

                // Which subagent this entry belongs to (nil = the session itself).
                var group: String?
                if let f = forced, tasks[f] != nil {
                    group = f
                } else if obj["isSidechain"] as? Bool == true {
                    if let p = (obj["parentToolUseID"] ?? obj["parent_tool_use_id"]) as? String, tasks[p] != nil { group = p }
                    else if let pu = obj["parentUuid"] as? String, let g = uuidGroup[pu] { group = g }
                    else { group = taskOrder.first { tasks[$0]!.ended == nil && !tasks[$0]!.assigned } }
                }
                if let g = group, let t = tasks[g] {
                    t.assigned = true
                    if let u = obj["uuid"] as? String { uuidGroup[u] = g }
                    if let m = message?["model"] as? String, t.model.isEmpty || t.model == "inherit" { t.model = m }
                    if let u = message?["usage"] as? [String: Any] {
                        t.tokens += ["input_tokens", "output_tokens", "cache_creation_input_tokens"].reduce(0) { $0 + ((u[$1] as? Int) ?? 0) }
                    }
                    if message?["role"] as? String == "assistant",
                       let text = content.last(where: { $0["type"] as? String == "text" })?["text"] as? String, !text.isEmpty {
                        t.lastText = text
                    }
                }
                if forced != nil, let role = message?["role"] as? String {
                    let types = content.compactMap { $0["type"] as? String }
                    last = LastEntry(at: at, agentWordsOnly: role == "assistant" && types.contains("text") && !types.contains("tool_use"))
                }

                for c in content {
                    switch c["type"] as? String {
                    case "tool_use":
                        guard let name = c["name"] as? String, let id = c["id"] as? String else { continue }
                        let input = c["input"] as? [String: Any] ?? [:]
                        if ClaudeTranscript.taskTools.contains(name) {
                            let label = (input["description"] as? String) ?? (input["subagent_type"] as? String) ?? "subagent"
                            task(id: id, owner: group, name: label, asked: input["prompt"] as? String ?? "",
                                 model: input["model"] as? String ?? "", started: at)
                        } else if ClaudeTranscript.handbackTools.contains(name), let g = forced ?? group {
                            handbacks[id] = g
                        } else if let g = group, let t = tasks[g], let path = (input["file_path"] ?? input["notebook_path"]) as? String {
                            switch name {
                            case "Read": t.touch(path, read: true)
                            case "Write": t.touch(path, added: ClaudeTranscript.lineCount(input["content"] as? String))
                            case "Edit": t.touch(path, added: ClaudeTranscript.lineCount(input["new_string"] as? String),
                                                 removed: ClaudeTranscript.lineCount(input["old_string"] as? String))
                            case "MultiEdit":
                                for e in input["edits"] as? [[String: Any]] ?? [] {
                                    t.touch(path, added: ClaudeTranscript.lineCount(e["new_string"] as? String),
                                            removed: ClaudeTranscript.lineCount(e["old_string"] as? String))
                                }
                            default: break
                            }
                        }
                    case "tool_result":
                        guard let id = c["tool_use_id"] as? String else { continue }
                        if let owner = handbacks[id], let t = tasks[owner] { t.end(at); continue }
                        guard let t = tasks[id] else { continue }
                        if ClaudeTranscript.isAsyncLaunch(obj, result: c) { continue }   // a background start, not its end
                        if t.ended == nil { t.ended = at }
                    default: break
                    }
                }
            }
            return last
        }

        /// `<task-notification>` … `<tool-use-id>X</tool-use-id>` … `<status>completed</status>`: a background agent's end.
        private func notifications(_ obj: [String: Any], at: Date) {
            var texts: [String] = []
            if obj["type"] as? String == "queue-operation", let c = obj["content"] as? String { texts.append(c) }
            if let a = obj["attachment"] as? [String: Any], let p = a["prompt"] as? String { texts.append(p) }
            if let m = obj["message"] as? [String: Any], m["role"] as? String == "user", let c = m["content"] as? String { texts.append(c) }
            for text in texts {
                for n in ClaudeTranscript.taskNotifications(text) where n.status != "running" {
                    tasks[n.toolUseId]?.end(at)
                }
            }
        }
    }

    /// The subagent tree from transcript JSONL (main file and/or subagent files, concatenated), in start order.
    public static func subagents(jsonl: String, sessionId: String) -> [Subagent] {
        let b = Builder()
        b.consume(jsonl)
        return finish(b, sessionId: sessionId)
    }

    /// The subagent tree from the main transcript's tail plus each file in `<session>/subagents/` (LAB-652).
    /// A file with its `.meta.json` stands alone: it seeds its task (id = the meta's toolUseId) even when the parent's
    /// tool_use is far outside the main file's tail, and all its lines belong to that task. Files without a meta are
    /// read the old way (concatenated after the main file, matched by parentToolUseID / parentUuid / order).
    ///
    /// Done rule, first match wins (conservative: a subagent stays "running" unless one of these holds):
    /// 1. the parent's tool_result for its tool_use (a foreground agent), unless that result only says
    ///    "Async agent launched" (`toolUseResult.status == "async_launched"`);
    /// 2. a `<task-notification>` naming its tool_use id with a status other than running (a background agent);
    /// 3. its own file ends with the tool_result of its `SubagentHandback` call (it handed its report back);
    /// 4. its file's last entry is the agent's own words with no tool call waiting, and the file has not grown for
    ///    `quietDone` (5 min) — ended at that entry's time;
    /// 5. its file has not grown for `staleDone` (60 min), whatever the last line — ended at the last entry's time.
    public static func subagents(main: String, files: [SubagentFile], sessionId: String, now: Date) -> [Subagent] {
        let b = Builder()
        var seeded: [(SubagentFile, String)] = []
        for f in files {
            guard let m = f.meta, !m.toolUseId.isEmpty else { continue }
            let first = firstEntry(f.head.isEmpty ? f.tail : f.head)
            b.task(id: m.toolUseId, owner: nil, name: m.description ?? m.agentType ?? "subagent", asked: first?.asked ?? "",
                           model: m.model ?? "", started: first?.at ?? f.modified ?? now)
            seeded.append((f, m.toolUseId))
        }
        b.consume(main)
        for f in files where f.meta == nil || f.meta!.toolUseId.isEmpty { b.consume(f.tail) }
        for (f, id) in seeded {
            let last = b.consume(f.tail, forced: id)
            guard let t = b.tasks[id], t.ended == nil, let modified = f.modified else { continue }
            let quiet = now.timeIntervalSince(modified)
            if let last, last.agentWordsOnly, quiet >= quietDone { t.end(last.at) }
            else if quiet >= staleDone { t.end(last?.at ?? modified) }
        }
        return finish(b, sessionId: sessionId)
    }

    private static func finish(_ b: Builder, sessionId: String) -> [Subagent] {
        func depth(_ t: TaskInfo) -> Int {
            var d = 1, cur = t.owner, guardN = 0
            while let o = cur, let p = b.tasks[o], guardN < 32 { d += 1; cur = p.owner; guardN += 1 }
            return d
        }
        let ordered = b.taskOrder.enumerated().compactMap { i, id in b.tasks[id].map { (i, $0) } }
            .sorted { $0.1.started != $1.1.started ? $0.1.started < $1.1.started : $0.0 < $1.0 }.map(\.1)
        return ordered.map { t in
            Subagent(id: t.id, parentId: t.owner, sessionId: sessionId, name: t.name, model: t.model, asked: t.asked,
                     tokens: t.tokens, started: t.started, ended: t.ended, status: t.ended == nil ? .running : .done,
                     touched: t.order.compactMap { t.touched[$0] }, depth: depth(t), lastText: t.lastText)
        }
    }

    /// The launch tool_result of a background agent: `toolUseResult.status == "async_launched"` (or `isAsync`), or
    /// older text "Async agent launched successfully".
    static func isAsyncLaunch(_ obj: [String: Any], result: [String: Any]) -> Bool {
        if let r = obj["toolUseResult"] as? [String: Any] {
            if r["status"] as? String == "async_launched" || r["isAsync"] as? Bool == true { return true }
        }
        let text: String
        if let s = result["content"] as? String { text = s }
        else { text = (result["content"] as? [[String: Any]] ?? []).compactMap { $0["text"] as? String }.joined() }
        return text.hasPrefix("Async agent launched")
    }

    /// The `<task-notification>` blocks in a text: (tool-use id, status).
    public static func taskNotifications(_ text: String) -> [(toolUseId: String, status: String)] {
        guard text.contains("<task-notification>") else { return [] }
        func tag(_ name: String, in s: Substring) -> String? {
            guard let a = s.range(of: "<\(name)>"), let b = s.range(of: "</\(name)>", range: a.upperBound..<s.endIndex) else { return nil }
            return String(s[a.upperBound..<b.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        var out: [(toolUseId: String, status: String)] = []
        let chunks: [String] = text.components(separatedBy: "<task-notification>")
        for chunk in chunks[1...] {
            let block = Substring(chunk.components(separatedBy: "</task-notification>")[0])
            guard let id = tag("tool-use-id", in: block), !id.isEmpty else { continue }
            out.append((id, tag("status", in: block) ?? "completed"))
        }
        return out
    }

    /// The first entry of a subagent file: when it started and what it was asked (its first user message).
    static func firstEntry(_ jsonl: String) -> (at: Date, asked: String)? {
        for line in jsonl.split(separator: "\n") {
            guard line.first == "{", let obj = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
                  let at = (obj["timestamp"] as? String).flatMap(date) else { continue }
            let message = obj["message"] as? [String: Any]
            var asked = ""
            if message?["role"] as? String == "user" {
                if let s = message?["content"] as? String { asked = s }
                else { asked = (message?["content"] as? [[String: Any]] ?? []).compactMap { $0["text"] as? String }.joined(separator: "\n") }
            }
            return (at, asked)
        }
        return nil
    }

    static func lineCount(_ s: String?) -> Int {
        guard let s, !s.isEmpty else { return 0 }
        return s.split(separator: "\n", omittingEmptySubsequences: false).count
    }

    static func date(_ s: String) -> Date? {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: s) { return d }
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: s)
    }

    /// Depth-first order (parent, then its children) for the trace rows.
    public static func treeOrder(_ subs: [Subagent]) -> [Subagent] {
        var out: [Subagent] = []
        func visit(_ parent: String?) {
            for s in subs where s.parentId == parent { out.append(s); visit(s.id) }
        }
        visit(nil)
        let seen = Set(out.map(\.id))
        return out + subs.filter { !seen.contains($0.id) }   // orphans (parent outside the window read) last
    }
}

/// `<session>/subagents/agent-<id>.meta.json`, written by Claude Code next to each subagent's transcript (LAB-652).
public struct SubagentMeta: Equatable, Sendable {
    /// The parent's Agent/Task tool_use id: the subagent's id in the tree.
    public var toolUseId: String
    public var agentType: String?
    public var description: String?
    public var model: String?
    public var spawnDepth: Int?
    /// requestShape "background": the parent did not wait for it.
    public var background: Bool

    public init(toolUseId: String, agentType: String? = nil, description: String? = nil, model: String? = nil,
                spawnDepth: Int? = nil, background: Bool = false) {
        self.toolUseId = toolUseId; self.agentType = agentType; self.description = description; self.model = model
        self.spawnDepth = spawnDepth; self.background = background
    }

    public static func parse(_ data: Data) -> SubagentMeta? {
        guard let o = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let id = o["toolUseId"] as? String, !id.isEmpty else { return nil }
        func text(_ k: String) -> String? { (o[k] as? String).flatMap { $0.isEmpty ? nil : $0 } }
        return SubagentMeta(toolUseId: id, agentType: text("agentType"), description: text("description"), model: text("model"),
                            spawnDepth: o["spawnDepth"] as? Int, background: o["requestShape"] as? String == "background")
    }

    /// agent-abc.jsonl → agent-abc.meta.json
    public static func metaPath(forTranscript path: String) -> String {
        path.hasSuffix(".jsonl") ? String(path.dropLast(".jsonl".count)) + ".meta.json" : path + ".meta.json"
    }
}

/// One subagent transcript as read for a scan: its meta (nil = an older Claude Code without one), the first line (start
/// time and prompt, which a tail read of a long file misses), the tail, and when the file last changed.
public struct SubagentFile: Sendable {
    public var meta: SubagentMeta?
    public var head: String
    public var tail: String
    public var modified: Date?
    public init(meta: SubagentMeta?, head: String = "", tail: String, modified: Date? = nil) {
        self.meta = meta; self.head = head; self.tail = tail; self.modified = modified
    }
}

/// Which Claude conversation a One Roof session is showing (LAB-652). Claude Code writes
/// `<configDir>/sessions/<pid>.json` (`{"pid":…,"sessionId":…,"cwd":…}`) for every running `claude` process, so the
/// claude process inside the session's pane names its conversation exactly; titles (One Roof's name vs Claude's
/// ai-title) rarely match and several sessions often share one launch folder.
public enum ClaudeSessionLocator {
    public struct Proc: Equatable, Sendable {
        public var pid: Int32
        public var ppid: Int32?
        public var name: String?
        public var argv: [String]
        public init(pid: Int32, ppid: Int32? = nil, name: String? = nil, argv: [String] = []) {
            self.pid = pid; self.ppid = ppid; self.name = name; self.argv = argv
        }
    }

    public struct Live: Equatable, Sendable {
        public var pid: Int32
        public var sessionId: String
        public var cwd: String?
        public init(pid: Int32, sessionId: String, cwd: String? = nil) { self.pid = pid; self.sessionId = sessionId; self.cwd = cwd }
    }

    /// The Claude Code CLI: the native `claude` binary, or node/bun running `…/claude-code/cli.js` or a `claude` script.
    public static func isClaude(name: String?, argv: [String]) -> Bool {
        func base(_ s: String) -> String { (s as NSString).lastPathComponent }
        if let n = name, base(n) == "claude" { return true }
        guard let a0 = argv.first else { return false }
        if base(a0) == "claude" { return true }
        guard ["node", "bun"].contains(base(a0)) else { return false }
        return argv.dropFirst().contains { a in
            !a.hasPrefix("-") && (base(a) == "claude" || a.contains("/claude-code/"))
        }
    }

    /// The session's own claude process: of the claude processes in the list, the outermost one (its parent is not
    /// another claude in the list), lowest pid on a tie. nil when there is none.
    public static func claudePid(in procs: [Proc]) -> Int32? {
        let claudes = procs.filter { isClaude(name: $0.name, argv: $0.argv) }
        let pids = Set(claudes.map(\.pid))
        let outer = claudes.filter { p in p.ppid.map { !pids.contains($0) } ?? true }
        return (outer.isEmpty ? claudes : outer).map(\.pid).min()
    }

    /// `<configDir>/sessions/<pid>.json`
    public static func sessionFile(configDir: String, pid: Int32) -> String {
        ((configDir as NSString).appendingPathComponent("sessions") as NSString).appendingPathComponent("\(pid).json")
    }

    /// The live-session record; nil when unreadable, without a session id, or written for a different pid.
    public static func parseSessionFile(_ data: Data, pid: Int32? = nil) -> Live? {
        guard let o = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let sid = o["sessionId"] as? String, !sid.isEmpty else { return nil }
        let filePid = (o["pid"] as? Int).map { Int32($0) }
        if let pid, let filePid, pid != filePid { return nil }
        guard let p = filePid ?? pid else { return nil }
        return Live(pid: p, sessionId: sid, cwd: (o["cwd"] as? String).flatMap { $0.isEmpty ? nil : $0 })
    }

    /// Where to look for the sessions file, in order: the process's own CLAUDE_CONFIG_DIR, the account's, ~/.claude.
    public static func configDirs(processEnv: [String: String]?, account: String?, home: String) -> [String] {
        var out: [String] = []
        for d in [processEnv?["CLAUDE_CONFIG_DIR"], account, home + "/.claude"] {
            if let d, !d.isEmpty, !out.contains(d) { out.append(d) }
        }
        return out
    }

    /// The last fallback (no claude process found): the conversation whose ai-title is the session's title.
    public static func byTitle(_ title: String?, in convs: [Conversation]) -> Conversation? {
        guard let t = title?.trimmingCharacters(in: .whitespaces), !t.isEmpty else { return nil }
        return convs.first { $0.title == t }
    }
}

/// A pane as seen over time (pure input for inferring children of non-Claude agents).
public struct PaneObservation: Equatable, Sendable {
    public var paneId: String
    public var workspaceId: String?
    public var agent: String?
    public var title: String?
    public var status: String?
    public var firstSeen: Date
    /// The pane's process ancestry when known (from the runtime's process info).
    public var ancestorPids: [Int32]

    public init(paneId: String, workspaceId: String?, agent: String? = nil, title: String? = nil, status: String? = nil,
                firstSeen: Date, ancestorPids: [Int32] = []) {
        self.paneId = paneId; self.workspaceId = workspaceId; self.agent = agent; self.title = title; self.status = status
        self.firstSeen = firstSeen; self.ancestorPids = ancestorPids
    }
}

public enum InferredSubagents {
    /// New panes in the session's workspace, started from its process tree (or, without pids, after it launched),
    /// that belong to no other session.
    public static func children(sessionId: String, parentPane: String, workspaceId: String?, parentPid: Int32?, launchedAt: Date,
                                panes: [PaneObservation], ownedByOthers: Set<String> = []) -> [Subagent] {
        guard let ws = workspaceId else { return [] }
        return panes.filter { p in
            guard p.workspaceId == ws, p.paneId != parentPane, !ownedByOthers.contains(p.paneId) else { return false }
            if let pid = parentPid, !p.ancestorPids.isEmpty { return p.ancestorPids.contains(pid) }
            return p.firstSeen >= launchedAt
        }
        .sorted { $0.firstSeen < $1.firstSeen }
        .map { p in
            let kind = AgentKind(detectedName: p.agent)
            let status = SessionStatus.fromAgentStatus(p.status)
            return Subagent(id: "pane:" + p.paneId, sessionId: sessionId, name: p.title ?? kind?.displayName ?? "pane \(p.paneId)",
                            model: kind?.displayName ?? (p.agent ?? "shell"), started: p.firstSeen,
                            status: status == .done ? .done : status == .needsYou ? .needsYou : .running, inferred: true)
        }
    }
}

/// One subagent as a row hanging under its session in the Overview (LAB-595), parent → child.
public struct SubagentBranch: Equatable, Sendable, Identifiable {
    public var sub: Subagent
    /// 1 = started by the session, 2 = by a subagent, …
    public var level: Int
    /// For each ancestor level (1 ..< level): does that ancestor's line carry on below this row (draw │)?
    public var rails: [Bool]
    /// The last child of its parent (└) rather than one of several (├).
    public var isLast: Bool
    public var id: String { sub.id }
}

public enum SubagentTree {
    /// The rows to hang under a session: every branch with something still running (or needing you), plus the newest
    /// `keepFinished` finished branches, in start order, depth first, at most `limit` rows. `hidden` counts the
    /// subagents left out (the Subagents trace shows them all).
    public static func branches(_ subs: [Subagent], keepFinished: Int = 2, limit: Int = 6) -> (rows: [SubagentBranch], hidden: Int) {
        let ids = Set(subs.map(\.id))
        var children: [String: [Subagent]] = [:]
        var roots: [Subagent] = []
        for s in subs {
            if let p = s.parentId, ids.contains(p), p != s.id { children[p, default: []].append(s) } else { roots.append(s) }
        }
        func active(_ s: Subagent, _ seen: Set<String> = []) -> Bool {
            if s.ended == nil || s.status == .needsYou { return true }
            guard !seen.contains(s.id) else { return false }
            return (children[s.id] ?? []).contains { active($0, seen.union([s.id])) }
        }
        let finished = roots.filter { !active($0) }.sorted { ($0.ended ?? $0.started) > ($1.ended ?? $1.started) }
        let keep = Set(roots.filter { active($0) }.map(\.id) + finished.prefix(max(0, keepFinished)).map(\.id))
        let shown = roots.filter { keep.contains($0.id) }

        var rows: [SubagentBranch] = []
        var visited = Set<String>()
        func visit(_ list: [Subagent], level: Int, rails: [Bool]) {
            for (i, s) in list.enumerated() where visited.insert(s.id).inserted {
                let last = i == list.count - 1
                rows.append(SubagentBranch(sub: s, level: level, rails: rails, isLast: last))
                visit(children[s.id] ?? [], level: level + 1, rails: rails + [!last])
            }
        }
        visit(shown, level: 1, rails: [])
        if rows.count > limit {
            rows = Array(rows.prefix(limit))
            if var final = rows.popLast() { final.isLast = true; rows.append(final) }   // the cut row closes its line
        }
        return (rows, subs.count - rows.count)
    }

    /// "2 running · 3 done" for a session's subagents ("1 needs you" first when one does).
    public static func summary(_ subs: [Subagent]) -> String {
        let needs = subs.filter { $0.status == .needsYou }.count
        let running = subs.filter { $0.ended == nil && $0.status != .needsYou }.count
        let done = subs.count - needs - running
        return [needs > 0 ? "\(needs) need\(needs == 1 ? "s" : "") you" : nil, running > 0 ? "\(running) running" : nil, done > 0 ? "\(done) done" : nil]
            .compactMap { $0 }.joined(separator: " · ")
    }
}
