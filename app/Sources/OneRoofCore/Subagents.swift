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
    }

    /// The subagent tree from transcript JSONL (main file and/or subagent files, concatenated), in start order.
    public static func subagents(jsonl: String, sessionId: String) -> [Subagent] {
        var tasks: [String: TaskInfo] = [:]
        var taskOrder: [String] = []
        var uuidGroup: [String: String] = [:]

        for line in jsonl.split(separator: "\n") {
            guard line.first == "{", let obj = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any] else { continue }
            let at = (obj["timestamp"] as? String).flatMap(date) ?? Date(timeIntervalSince1970: 0)
            let message = obj["message"] as? [String: Any]
            let content = message?["content"] as? [[String: Any]] ?? []

            // Which subagent this entry belongs to (nil = the session itself).
            var group: String?
            if obj["isSidechain"] as? Bool == true {
                if let p = (obj["parentToolUseID"] ?? obj["parent_tool_use_id"]) as? String, tasks[p] != nil { group = p }
                else if let pu = obj["parentUuid"] as? String, let g = uuidGroup[pu] { group = g }
                else { group = taskOrder.first { tasks[$0]!.ended == nil && !tasks[$0]!.assigned } }
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
            }

            for c in content {
                switch c["type"] as? String {
                case "tool_use":
                    guard let name = c["name"] as? String, let id = c["id"] as? String else { continue }
                    let input = c["input"] as? [String: Any] ?? [:]
                    if taskTools.contains(name) {
                        let label = (input["description"] as? String) ?? (input["subagent_type"] as? String) ?? "subagent"
                        tasks[id] = TaskInfo(id: id, owner: group, name: label, asked: input["prompt"] as? String ?? "",
                                             model: input["model"] as? String ?? "", started: at)
                        taskOrder.append(id)
                    } else if let g = group, let t = tasks[g], let path = (input["file_path"] ?? input["notebook_path"]) as? String {
                        switch name {
                        case "Read": t.touch(path, read: true)
                        case "Write": t.touch(path, added: lineCount(input["content"] as? String))
                        case "Edit": t.touch(path, added: lineCount(input["new_string"] as? String), removed: lineCount(input["old_string"] as? String))
                        case "MultiEdit":
                            for e in input["edits"] as? [[String: Any]] ?? [] {
                                t.touch(path, added: lineCount(e["new_string"] as? String), removed: lineCount(e["old_string"] as? String))
                            }
                        default: break
                        }
                    }
                case "tool_result":
                    if let id = c["tool_use_id"] as? String, let t = tasks[id], t.ended == nil { t.ended = at }
                default: break
                }
            }
        }

        func depth(_ t: TaskInfo) -> Int {
            var d = 1, cur = t.owner, guardN = 0
            while let o = cur, let p = tasks[o], guardN < 32 { d += 1; cur = p.owner; guardN += 1 }
            return d
        }
        return taskOrder.compactMap { tasks[$0] }.map { t in
            Subagent(id: t.id, parentId: t.owner, sessionId: sessionId, name: t.name, model: t.model, asked: t.asked,
                     tokens: t.tokens, started: t.started, ended: t.ended, status: t.ended == nil ? .running : .done,
                     touched: t.order.compactMap { t.touched[$0] }, depth: depth(t), lastText: t.lastText)
        }
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
