import Foundation

// File claims and attribution (v2, ENGINES §5). A session claims a file while its current chapter edits it
// (`Edit(path)` / `Write(path)` in the stream); the claim clears when the chapter ends. The editor uses claims to hold
// the owner's save until the agent's step is over. Attribution colours diff lines by the session whose tool calls
// changed them; lines nobody claimed are yours.

public struct FileClaim: Codable, Equatable, Sendable {
    public var path: String
    public var sessionId: String
    public var step: Int?
    public var since: Date
    public init(path: String, sessionId: String, step: Int? = nil, since: Date = Date()) {
        self.path = path; self.sessionId = sessionId; self.step = step; self.since = since
    }
}

public enum Author: Codable, Equatable, Hashable, Sendable {
    /// An agent, by its badge code ("C1", "CX", "KM").
    case agent(String)
    case you

    /// Stored as "agent:C1" / "you".
    public var stored: String { switch self { case .agent(let c): return "agent:" + c; case .you: return "you" } }
    public init(stored: String) { self = stored.hasPrefix("agent:") ? .agent(String(stored.dropFirst(6))) : .you }
}

public struct Attribution: Codable, Equatable, Sendable {
    public var path: String
    public var lines: ClosedRange<Int>
    public var sessionId: String?
    public var author: Author
    public var at: Date
    public init(path: String, lines: ClosedRange<Int>, sessionId: String?, author: Author, at: Date) {
        self.path = path; self.lines = lines; self.sessionId = sessionId; self.author = author; self.at = at
    }
}

/// Live claims, one per path (the latest editor wins). A value type: the app keeps one and persists it if it likes.
public struct FileClaims: Equatable, Sendable {
    public private(set) var byPath: [String: FileClaim] = [:]
    /// Every path each session's tool calls edited (kept after claims clear, for attribution of the uncommitted diff).
    public private(set) var editedBy: [String: [String: Date]] = [:]

    public init() {}

    /// Absolute, standardised path (relative paths resolve against the session's repo).
    public static func normalise(_ path: String, repo: String) -> String {
        let p = path.hasPrefix("/") ? path : path.hasPrefix("~") ? (path as NSString).expandingTildeInPath : (repo as NSString).appendingPathComponent(path)
        return (p as NSString).standardizingPath
    }

    /// Reads a chapter's terminal text for edit tool calls; claims each edited file. Returns the new claims.
    @discardableResult
    public mutating func observe(text: String, sessionId: String, repo: String, step: Int? = nil, at: Date = Date()) -> [FileClaim] {
        observe(calls: CaptionEngine.toolCalls(in: text), sessionId: sessionId, repo: repo, step: step, at: at)
    }

    @discardableResult
    public mutating func observe(calls: [ToolCall], sessionId: String, repo: String, step: Int? = nil, at: Date = Date()) -> [FileClaim] {
        var added: [FileClaim] = []
        for c in calls where c.kind == .edit && !c.path.isEmpty {
            let p = Self.normalise(c.path, repo: repo)
            editedBy[sessionId, default: [:]][p] = at
            if byPath[p]?.sessionId == sessionId { continue }
            let claim = FileClaim(path: p, sessionId: sessionId, step: step, since: at)
            byPath[p] = claim
            added.append(claim)
        }
        return added
    }

    /// `roof swarm` claims arrive as they are.
    public mutating func importClaims(_ claims: [FileClaim]) { for c in claims { byPath[c.path] = c } }

    /// The chapter (step) ended: its claims clear.
    public mutating func endChapter(sessionId: String) { byPath = byPath.filter { $0.value.sessionId != sessionId } }

    /// The session ended: claims and edit records go.
    public mutating func endSession(sessionId: String) {
        endChapter(sessionId: sessionId)
        editedBy[sessionId] = nil
    }

    public func claim(for path: String) -> FileClaim? { byPath[(path as NSString).standardizingPath] }

    /// The claim the editor must respect: held by someone other than `me` (nil = the owner).
    public func blockingClaim(for path: String, me: String? = nil) -> FileClaim? {
        guard let c = claim(for: path), c.sessionId != me else { return nil }
        return c
    }

    public func claims(of sessionId: String) -> [FileClaim] { byPath.values.filter { $0.sessionId == sessionId }.sorted { $0.path < $1.path } }
}

public enum Attributor {
    /// Added-line runs in a file's uncommitted diff → the session that last edited the file (by tool calls), else you.
    /// `badge` maps a session id to its agent code for the gutter colour.
    public static func attribute(diff: FileDiff, repo: String, claims: FileClaims, badge: (String) -> String, at: Date = Date()) -> [Attribution] {
        let abs = FileClaims.normalise(diff.path, repo: repo)
        let editor = claims.editedBy.compactMap { sid, paths in paths[abs].map { (sid, $0) } }.max { $0.1 < $1.1 }?.0
        var out: [Attribution] = []
        for h in diff.hunks {
            for run in runs(h.lines.compactMap { $0.kind == .added ? $0.newNo : nil }) {
                out.append(Attribution(path: diff.path, lines: run, sessionId: editor, author: editor.map { .agent(badge($0)) } ?? .you, at: at))
            }
        }
        return out
    }

    /// [3,4,5,9,10] → [3...5, 9...10].
    public static func runs(_ lines: [Int]) -> [ClosedRange<Int>] {
        var out: [ClosedRange<Int>] = []
        for n in lines.sorted() {
            if let last = out.last, last.upperBound + 1 == n { out[out.count - 1] = last.lowerBound...n }
            else if out.last?.contains(n) != true { out.append(n...n) }
        }
        return out
    }

    /// Committed lines (`git log -L`): the session whose ticket key or workstream tag is in the commit message.
    public static func session(forCommitMessage message: String, sessions: [Session]) -> Session? {
        let upper = message.uppercased()
        if let s = sessions.first(where: { ($0.ticket.map { upper.contains($0.uppercased()) }) ?? false }) { return s }
        guard let ws = Workspace.workstream(in: message) else { return nil }
        return sessions.first { $0.workstream?.uppercased() == ws }
    }

    /// The attribution covering `line`, if any.
    public static func attribution(at line: Int, in list: [Attribution]) -> Attribution? { list.first { $0.lines.contains(line) } }
}
