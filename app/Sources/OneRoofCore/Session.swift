import Foundation

/// The CLI agents One Roof can start. `cliName` is the command that starts it.
public enum AgentKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case claude, codex, gemini, agy, kimi
    /// A plain shell, no agent: One Roof as an ordinary terminal (kept by roofd like any session).
    case shell

    public var id: String { rawValue }

    public var isAgent: Bool { self != .shell }

    /// The least dangerous mode in which each CLI works without asking per command (objective steps only):
    /// Claude's classifier-gated auto mode, Codex approving for you inside its sandbox, Kimi asking only when needed;
    /// Gemini and Antigravity have only an approve-everything mode.
    public var autoApproveArgs: [String] {
        switch self {
        case .claude: return ["--permission-mode", "auto"]
        case .codex: return ["--approve-for-me"]
        case .kimi: return ["--yolo"]
        case .gemini: return ["--approval-mode", "yolo"]
        case .agy: return ["--dangerously-skip-permissions"]
        case .shell: return []
        }
    }

    /// Model names offered in the picker (the CLI also accepts any other name). Empty = free text only.
    public var suggestedModels: [String] {
        switch self {
        case .claude: return ["opus", "sonnet", "haiku"]
        case .kimi: return ["kimi-code/kimi-for-coding", "kimi-code/kimi-for-coding-highspeed"]
        default: return []
        }
    }

    public var cliName: String { rawValue }

    public var displayName: String {
        switch self {
        case .claude: return "Claude"
        case .codex: return "Codex"
        case .gemini: return "Gemini"
        case .agy: return "Antigravity"
        case .kimi: return "Kimi"
        case .shell: return "Terminal"
        }
    }

    /// Short badge shown in the sidebar.
    public var badge: String {
        switch self {
        case .claude: return "CL"
        case .codex: return "CX"
        case .gemini: return "GM"
        case .agy: return "AG"
        case .kimi: return "KM"
        case .shell: return ">_"
        }
    }

    /// Map a detected agent or process name (e.g. "claude", "kimi-code") to a kind.
    public init?(detectedName: String?) {
        guard let n = detectedName?.lowercased() else { return nil }
        if let k = AgentKind(rawValue: n) { self = k; return }
        if n.contains("claude") { self = .claude; return }
        if n.contains("codex") { self = .codex; return }
        if n.contains("gemini") { self = .gemini; return }
        if n.contains("kimi") { self = .kimi; return }
        return nil
    }
}

/// Where a session is in its life. One Roof owns planned / next / do-not-use;
/// The runtime's live agent state drives running / needs-you / done / idle / exited.
public enum SessionStatus: String, Codable, CaseIterable, Sendable {
    case planned        // written ahead of time, not started
    case next           // planned and up next
    case running        // runtime: working
    case needsYou       // runtime: blocked (permission prompt, question)
    case done           // runtime: finished a turn you have not looked at yet
    case idle           // runtime: at its prompt, nothing new
    case exited         // was launched; the runtime no longer has it
    case doNotUse       // parked by the owner (the old "(DNU)" prefix)

    public var label: String {
        switch self {
        case .planned: return "Planned"
        case .next: return "Next"
        case .running: return "Working"
        case .needsYou: return "Needs you"
        case .done: return "Ready"
        case .idle: return "Idle"
        case .exited: return "Exited"
        case .doNotUse: return "Do not use"
        }
    }

    /// One line on what the status means (LAB-241), for tooltips and help. The filter chips and the group headings use
    /// the same names: Needs you · Working · Ready · Idle · Exited.
    public var meaning: String {
        switch self {
        case .planned: return "Written ahead of time, not started."
        case .next: return "Planned and up next."
        case .running: return "Busy right now: thinking, running a tool or writing. It goes back to Ready or Idle a few seconds after it stops."
        case .needsYou: return "Stopped on a question or a permission prompt. It waits for you."
        case .done: return "Finished a turn you have not looked at yet. It turns Idle as soon as you open the session or type in it."
        case .idle: return "Alive at its prompt with nothing new for you; not executing. Plain terminals are always Idle (they have no agent)."
        case .exited: return "The agent's process has ended. Relaunch it or remove it."
        case .doNotUse: return "Parked by you: kept, but not to be used."
        }
    }

    /// Sort order in the "status" grouping (LAB-256): blocked first, then live work, then finished turns, then the rest.
    /// Matches the chip order: Needs you · Working · Ready · Idle · Exited.
    public var rank: Int {
        switch self {
        case .needsYou: return 0
        case .running: return 1
        case .done: return 2
        case .idle: return 3
        case .next: return 4
        case .planned: return 5
        case .exited: return 6
        case .doNotUse: return 7
        }
    }

    public var isLive: Bool { [.running, .needsYou, .done, .idle].contains(self) }

    /// Map an `agent_status` string (idle · working · blocked · done · unknown).
    public static func fromAgentStatus(_ s: String?) -> SessionStatus {
        switch s {
        case "working": return .running
        case "blocked": return .needsYou
        case "done": return .done
        default: return .idle
        }
    }
}

/// A session: planned work and/or a live agent in roofd.
public struct Session: Codable, Identifiable, Equatable, Sendable {
    public var id: String
    public var name: String
    public var agent: AgentKind
    /// Account slot label, e.g. "Claude1" / "Claude2". Nil = default account.
    public var account: String?
    /// Absolute repo or worktree path. Agents only ever start inside ~/Projects (RULE ZERO).
    public var repoPath: String
    public var workstream: String?
    public var objective: String
    public var openingMessage: String
    public var tags: [String]
    public var notes: String
    /// Owner-set lifecycle (planned / next / doNotUse). Live status comes from roofd.
    public var lifecycle: SessionStatus
    /// Runtime id once launched (unique, e.g. "roof-1a2b3c").
    public var runtimeId: String?
    /// Runtime group the session was started in (herdr-era workspaces; roofd nil).
    public var runtimeGroup: String?
    public var createdAt: Date
    public var launchedAt: Date?
    /// Start the agent inside `repoPath` (true) or in ~/Projects, the owner's usual launch folder (false).
    public var startInRepo: Bool
    /// The opening message has been delivered to the running agent.
    public var openingSent: Bool
    /// Extra arguments for the agent CLI, e.g. ["--resume", "<conversation-id>"] to bring a session over from another terminal.
    public var agentArgs: [String]
    /// Model for the agent CLI (`--model <name>`); nil = the CLI's own default.
    public var model: String?
    /// An emoji shown instead of the agent logo.
    public var icon: String?
    /// Row colour from `Sticker.palette`, e.g. "blue".
    public var color: String?
    /// Pinned sessions sit in a "Pinned" group at the top of every grouping.
    public var pinned: Bool
    /// The Linear ticket this session works on (e.g. "ENG-281"), and its Linear id + team key for status updates.
    public var ticket: String?
    public var ticketId: String?
    public var ticketTeam: String?
    /// More issues the same session works on, attached after it started (LAB-474); `ticket` stays the first one.
    public var moreTickets: [SessionIssue] = []
    /// The repo the session was last seen working in (learnt from its agent's hooks or its terminal's folder); sessions
    /// start at the workspace root, so this is what "Group by repo" uses.
    public var lastRepo: String?

    /// Everything after the agent command: the model flag, then any extra arguments.
    public var launchArgs: [String] {
        guard agent.isAgent else { return [] }
        let m = model?.trimmingCharacters(in: .whitespaces) ?? ""
        return (m.isEmpty ? [] : ["--model", m]) + agentArgs
    }

    /// A plain terminal's runtime id; herdr-era rows hold "term:<terminal_id>".
    public static let terminalPrefix = "term:"
    /// Id prefix of rows adopted from live sessions the store did not know. The herdr-era spelling is kept: saved rows use it.
    public static let adoptedPrefix = "herdr:"

    public init(
        id: String = UUID().uuidString,
        name: String,
        agent: AgentKind = .claude,
        account: String? = nil,
        repoPath: String,
        workstream: String? = nil,
        objective: String = "",
        openingMessage: String = "",
        tags: [String] = [],
        notes: String = "",
        lifecycle: SessionStatus = .planned,
        runtimeId: String? = nil,
        createdAt: Date = Date(),
        launchedAt: Date? = nil,
        startInRepo: Bool = false,
        openingSent: Bool = false,
        agentArgs: [String] = [],
        model: String? = nil,
        icon: String? = nil,
        color: String? = nil,
        pinned: Bool = false,
        ticket: String? = nil,
        ticketId: String? = nil,
        ticketTeam: String? = nil
    ) {
        self.id = id
        self.name = name
        self.agent = agent
        self.account = account
        self.repoPath = repoPath
        self.workstream = workstream
        self.objective = objective
        self.openingMessage = openingMessage
        self.tags = tags
        self.notes = notes
        self.lifecycle = lifecycle
        self.runtimeId = runtimeId
        self.createdAt = createdAt
        self.launchedAt = launchedAt
        self.startInRepo = startInRepo
        self.openingSent = openingSent
        self.agentArgs = agentArgs
        self.model = model
        self.icon = icon
        self.color = color
        self.pinned = pinned
        self.ticket = ticket
        self.ticketId = ticketId
        self.ticketTeam = ticketTeam
    }

    enum CodingKeys: String, CodingKey {
        case id, name, agent, account, repoPath, workstream, objective, openingMessage, tags, notes, lifecycle,
             createdAt, launchedAt, startInRepo, openingSent, agentArgs, model, icon, color, pinned, ticket, ticketId, ticketTeam,
             moreTickets, lastRepo
        // Renamed in LAB-15 (herdr → runtime); the stored keys stay, so old rows load unchanged.
        case runtimeId = "herdrAgent", runtimeGroup = "herdrWorkspace"
    }

    // Decode older rows that lack the newer fields.
    public init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        agent = try c.decode(AgentKind.self, forKey: .agent)
        account = try c.decodeIfPresent(String.self, forKey: .account)
        repoPath = try c.decode(String.self, forKey: .repoPath)
        workstream = try c.decodeIfPresent(String.self, forKey: .workstream)
        objective = try c.decodeIfPresent(String.self, forKey: .objective) ?? ""
        openingMessage = try c.decodeIfPresent(String.self, forKey: .openingMessage) ?? ""
        tags = try c.decodeIfPresent([String].self, forKey: .tags) ?? []
        notes = try c.decodeIfPresent(String.self, forKey: .notes) ?? ""
        lifecycle = try c.decodeIfPresent(SessionStatus.self, forKey: .lifecycle) ?? .planned
        runtimeId = try c.decodeIfPresent(String.self, forKey: .runtimeId)
        runtimeGroup = try c.decodeIfPresent(String.self, forKey: .runtimeGroup)
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        launchedAt = try c.decodeIfPresent(Date.self, forKey: .launchedAt)
        startInRepo = try c.decodeIfPresent(Bool.self, forKey: .startInRepo) ?? false
        openingSent = try c.decodeIfPresent(Bool.self, forKey: .openingSent) ?? false
        agentArgs = try c.decodeIfPresent([String].self, forKey: .agentArgs) ?? []
        model = try c.decodeIfPresent(String.self, forKey: .model)
        icon = try c.decodeIfPresent(String.self, forKey: .icon)
        color = try c.decodeIfPresent(String.self, forKey: .color)
        pinned = try c.decodeIfPresent(Bool.self, forKey: .pinned) ?? false
        ticket = try c.decodeIfPresent(String.self, forKey: .ticket)
        ticketId = try c.decodeIfPresent(String.self, forKey: .ticketId)
        ticketTeam = try c.decodeIfPresent(String.self, forKey: .ticketTeam)
        moreTickets = try c.decodeIfPresent([SessionIssue].self, forKey: .moreTickets) ?? []
        lastRepo = try c.decodeIfPresent(String.self, forKey: .lastRepo)
    }

    /// Every issue this session works on, the first one first (LAB-474).
    public var allTickets: [SessionIssue] {
        (ticket.map { [SessionIssue(key: $0, id: ticketId, team: ticketTeam)] } ?? []) + moreTickets
    }

    public func hasTicket(_ key: String) -> Bool { allTickets.contains { $0.key.caseInsensitiveCompare(key) == .orderedSame } }

    /// The row chip: "LAB-1", or "LAB-1 +2" when the session carries more.
    public var ticketChip: String? { ticket.map { moreTickets.isEmpty ? $0 : "\($0) +\(moreTickets.count)" } }

    /// Split an arguments string on whitespace, keeping "quoted parts" together.
    public static func parseArgs(_ text: String) -> [String] {
        var out: [String] = [], cur = "", quote: Character? = nil
        for ch in text {
            if let q = quote {
                if ch == q { quote = nil } else { cur.append(ch) }
            } else if ch == "\"" || ch == "'" {
                quote = ch
            } else if ch.isWhitespace {
                if !cur.isEmpty { out.append(cur); cur = "" }
            } else {
                cur.append(ch)
            }
        }
        if !cur.isEmpty { out.append(cur) }
        return out
    }

    /// Folder the agent process starts in.
    public var launchDirectory: String { startInRepo ? repoPath : Workspace.projectsRoot }

    /// True when an opening message is waiting to be sent.
    public var openingPending: Bool {
        !openingSent && !openingMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// The runtime id One Roof uses for a session it launches.
    public static func runtimeName(for id: String) -> String {
        "roof-" + id.replacingOccurrences(of: "-", with: "").prefix(8).lowercased()
    }
}

/// One Linear issue a session works on (LAB-474): key (LAB-474), Linear id and team key for state moves.
public struct SessionIssue: Codable, Equatable, Hashable, Sendable {
    public var key: String
    public var id: String?
    public var team: String?
    public init(key: String, id: String?, team: String?) { self.key = key; self.id = id; self.team = team }
}
