import Foundation

/// LAB-1509 · the session catalog: every session One Roof knows (live and history, every window, open or closed),
/// grouped by repo, newest first, each with what Resume would do. Pure: the app hands in what the board knows.
public enum SessionCatalog {
    /// Where a session is now. `history` = a saved row with nothing running (LAB-1514 calls these History).
    public enum State: String, CaseIterable, Sendable {
        case working, waiting, finishedShell, history, planned
        public var label: String {
            switch self {
            case .working: return "Working"
            case .waiting: return "Waiting"
            case .finishedShell: return "Finished"
            case .history: return "History"
            case .planned: return "Planned"
            }
        }
    }

    /// What Resume does for a row (LAB-1513), said plainly; never a new session dressed up as a resume.
    public enum Resume: Equatable, Sendable {
        case open                       // it is running: bring it forward
        case launch                     // planned, never started: start it
        case claude(id: String)         // claude --resume <id> in a new terminal, same folder and account
        case terminal                   // a shell: open a new one in the same folder
        case noConversation             // a Claude row whose conversation id was never seen (LAB-1511 may find it)
        case unsupported(agent: String) // the agent's CLI has no resume One Roof can drive yet

        public var buttonTitle: String? {
            switch self {
            case .open: return "Open"
            case .launch: return "Launch"
            case .claude: return "Resume"
            case .terminal: return "New terminal here"
            case .noConversation, .unsupported: return nil
            }
        }
        public var why: String? {
            switch self {
            case .noConversation: return "No conversation saved for this session yet, so it cannot be resumed."
            case .unsupported(let a): return "\(a) sessions cannot be resumed from One Roof yet."
            default: return nil
            }
        }
    }

    public struct Entry: Identifiable, Equatable, Sendable {
        public let id: String
        public let name: String
        public let agent: String
        public let account: String?
        public let repo: String          // the repo path it worked in (lastRepo, else its launch folder)
        public let ticket: String?
        public let window: String?
        public let started: Date
        public let lastActive: Date?
        public let state: State
        public let resume: Resume
        /// LAB-1537: removed from its window, kept here.
        public var archived: Bool = false
        public var when: Date { lastActive ?? started }
        /// Something runs for it (an agent, or the shell an agent left): Close ends it.
        public var running: Bool { [.working, .waiting, .finishedShell].contains(state) }

        public init(id: String, name: String, agent: String, account: String?, repo: String, ticket: String?, window: String?,
                    started: Date, lastActive: Date?, state: State, resume: Resume) {
            self.id = id; self.name = name; self.agent = agent; self.account = account; self.repo = repo; self.ticket = ticket
            self.window = window; self.started = started; self.lastActive = lastActive; self.state = state; self.resume = resume
        }
    }

    public struct Group: Identifiable, Equatable, Sendable {
        public let repo: String
        public let entries: [Entry]
        public var id: String { repo }
        public init(repo: String, entries: [Entry]) { self.repo = repo; self.entries = entries }
    }

    /// A session's state from what the board knows.
    public static func state(liveAgent: Bool, endedShell: Bool, status: SessionStatus, launched: Bool = true) -> State {
        if liveAgent { return status == .running ? .working : .waiting }
        if endedShell { return .finishedShell }
        return launched ? .history : .planned   // never started: a plan, not history
    }

    /// What Resume does for a session in a given state.
    public static func resume(for s: Session, state: State) -> Resume {
        if state == .planned { return .launch }
        if state != .history { return .open }
        switch s.agent {
        case .claude: return s.conversationId.map { .claude(id: $0) } ?? .noConversation
        default: return s.agent.isAgent ? .unsupported(agent: s.agent.displayName) : .terminal
        }
    }

    public static func entry(_ s: Session, state: State, window: String?, lastActive: Date?) -> Entry {
        var e = Entry(id: s.id, name: s.name, agent: s.agent.displayName, account: s.account, repo: s.lastRepo ?? s.repoPath,
              ticket: s.ticket, window: window, started: s.launchedAt ?? s.createdAt, lastActive: state == .planned ? nil : lastActive,
              state: state, resume: resume(for: s, state: state))
        e.archived = s.archived
        return e
    }

    /// Grouped by repo; each group newest first; groups ordered by their newest session. `query` matches name, repo,
    /// issue, agent, account and window (case-insensitive); `states` keeps only those states (empty = all).
    /// LAB-1584: `order` (id → place, from when the page opened) keeps every row where it was while the page is open,
    /// so a row you act on does not jump; rows new since then come first. `keep` rows stay listed whatever the state
    /// filter says (a History row you resumed is still there, now Working).
    public static func groups(_ entries: [Entry], query: String = "", states: Set<State> = [], order: [String: Int] = [:],
                              keep: Set<String> = []) -> [Group] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        let kept = entries.filter { e in
            (states.isEmpty || states.contains(e.state) || keep.contains(e.id)) &&
            (q.isEmpty || [e.name, e.repo, e.ticket ?? "", e.agent, e.account ?? "", e.window ?? ""].contains { $0.lowercased().contains(q) })
        }
        func before(_ a: Entry, _ b: Entry) -> Bool {
            switch (order[a.id], order[b.id]) {
            case let (x?, y?): return x < y
            case (nil, _?): return true
            case (_?, nil): return false
            case (nil, nil): return a.when > b.when
            }
        }
        return Dictionary(grouping: kept, by: \.repo)
            .map { Group(repo: $0.key, entries: $0.value.sorted(by: before)) }
            .sorted { a, b in
                guard let x = a.entries.first, let y = b.entries.first else { return false }
                return before(x, y)
            }
    }

    /// The order rows are in now (for `groups(order:)`).
    public static func order(of groups: [Group]) -> [String: Int] {
        Dictionary(uniqueKeysWithValues: groups.flatMap(\.entries).enumerated().map { ($1.id, $0) })
    }
}

/// LAB-1511 · find the Claude conversation of a session saved before One Roof kept its id. Only a confident match is
/// written: the transcript's first message within 10 minutes of the launch, and the opening message when there was one.
public enum ConversationBackfill {
    public struct Candidate: Equatable, Sendable {
        public let id: String
        public let path: String
        public let firstAt: Date
        public let firstAsked: String
        public init(id: String, path: String, firstAt: Date, firstAsked: String) {
            self.id = id; self.path = path; self.firstAt = firstAt; self.firstAsked = firstAsked
        }
    }
    public enum Match: Equatable, Sendable { case found(Candidate), ambiguous(Int), none }

    public static let window: TimeInterval = 10 * 60

    public static func match(_ s: Session, _ candidates: [Candidate]) -> Match {
        guard let launched = s.launchedAt else { return .none }
        let near = candidates.filter { abs($0.firstAt.timeIntervalSince(launched)) <= window }
        let opening = s.openingMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        if !opening.isEmpty {
            let key = String(opening.prefix(80))
            let said = near.filter { $0.firstAsked.contains(key) }
            if said.count == 1 { return .found(said[0]) }
            return said.count > 1 ? .ambiguous(said.count) : .none
        }
        if near.count == 1 { return .found(near[0]) }
        return near.isEmpty ? .none : .ambiguous(near.count)
    }

    /// Claude's config folders on this Mac (~/.claude, ~/.claude-2, ~/.claude-max-N …) that hold conversations.
    public static func configDirs(home: String = NSHomeDirectory()) -> [String] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: home)) ?? []
        return names.filter { $0 == ".claude" || $0.hasPrefix(".claude-") }
            .map { home + "/" + $0 }
            .filter { FileManager.default.fileExists(atPath: $0 + "/projects") }
            .sorted()
    }

    /// Transcripts in the folders a session could have run in (its launch folder and last repo, every account),
    /// created within the match window of its launch. Reads only the first entry of each candidate.
    public static func candidates(for s: Session, configDirs: [String]) -> [Candidate] {
        guard let launched = s.launchedAt else { return [] }
        let fm = FileManager.default
        var seen = Set<String>(), out: [Candidate] = []
        let folders = Set([s.repoPath, s.lastRepo].compactMap { $0 }.flatMap { dir in
            configDirs.map { ConversationIndex.folder(forLaunchDirectory: dir, configDir: $0) }
        })
        for folder in folders.sorted() {
            let real = (folder as NSString).resolvingSymlinksInPath
            guard !seen.contains(real), let names = try? fm.contentsOfDirectory(atPath: folder) else { continue }
            seen.insert(real)
            for n in names where n.hasSuffix(".jsonl") {
                let p = folder + "/" + n
                guard let a = try? fm.attributesOfItem(atPath: p), let born = (a[.creationDate] as? Date) ?? (a[.modificationDate] as? Date),
                      abs(born.timeIntervalSince(launched)) <= window * 3,
                      let head = readHead(p), let first = firstUserMessage(head) else { continue }
                out.append(Candidate(id: String(n.dropLast(6)), path: p, firstAt: first.at, firstAsked: first.asked))
            }
        }
        return out
    }

    /// When the conversation started (its first timestamped entry) and the first thing the user typed (the first user
    /// entry with text; the first entries are often snapshots or system lines, so `firstEntry` alone would miss it).
    static func firstUserMessage(_ jsonl: String) -> (at: Date, asked: String)? {
        var at: Date?
        for line in jsonl.split(separator: "\n") where line.first == "{" {
            guard let o = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any] else { continue }
            if at == nil, let t = o["timestamp"] as? String { at = ClaudeTranscript.date(t) }
            guard o["type"] as? String == "user", let m = o["message"] as? [String: Any], m["role"] as? String == "user" else { continue }
            let text: String
            if let c = m["content"] as? String { text = c }
            else { text = (m["content"] as? [[String: Any]] ?? []).filter { $0["type"] as? String == "text" }.compactMap { $0["text"] as? String }.joined(separator: "\n") }
            if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, let at { return (at, text) }
        }
        return at.map { ($0, "") }
    }

    static func readHead(_ path: String, bytes: Int = 256 * 1024) -> String? {
        guard let h = FileHandle(forReadingAtPath: path) else { return nil }
        defer { try? h.close() }
        return String(decoding: h.readData(ofLength: bytes), as: UTF8.self)
    }
}
