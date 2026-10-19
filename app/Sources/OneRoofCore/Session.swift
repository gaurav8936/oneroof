import Foundation

/// The CLI agents One Roof can start. `herdrKind` is the value herdr's `agent start --kind` expects.
public enum AgentKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case claude, codex, gemini, agy, kimi
    /// A plain shell, no agent: One Roof as an ordinary terminal (kept by herdr like any session).
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

    public var herdrKind: String { rawValue }

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

    /// Map herdr's detected agent name (e.g. "claude") to a kind.
    public init?(herdrName: String?) {
        guard let n = herdrName?.lowercased() else { return nil }
        if let k = AgentKind(rawValue: n) { self = k; return }
        if n.contains("claude") { self = .claude; return }
        if n.contains("codex") { self = .codex; return }
        if n.contains("gemini") { self = .gemini; return }
        if n.contains("kimi") { self = .kimi; return }
        return nil
    }
}

/// Where a session is in its life. One Roof owns planned / next / do-not-use;
/// herdr's live agent state drives running / needs-you / done / idle / exited.
public enum SessionStatus: String, Codable, CaseIterable, Sendable {
    case planned        // written ahead of time, not started
    case next           // planned and up next
    case running        // herdr: working
    case needsYou       // herdr: blocked (permission prompt, question)
    case done           // herdr: finished a turn you have not looked at yet
    case idle           // herdr: at its prompt, nothing new
    case exited         // was launched; herdr no longer has it
    case doNotUse       // parked by the owner (the old "(DNU)" prefix)

    public var label: String {
        switch self {
        case .planned: return "Planned"
        case .next: return "Next"
        case .running: return "Running"
        case .needsYou: return "Needs you"
        case .done: return "Done"
        case .idle: return "Idle"
        case .exited: return "Exited"
        case .doNotUse: return "Do not use"
        }
    }

    /// Sort order in the "status" grouping: what needs attention first.
    public var rank: Int {
        switch self {
        case .needsYou: return 0
        case .done: return 1
        case .running: return 2
        case .idle: return 3
        case .next: return 4
        case .planned: return 5
        case .exited: return 6
        case .doNotUse: return 7
        }
    }

    public var isLive: Bool { [.running, .needsYou, .done, .idle].contains(self) }

    /// Map herdr's `agent_status` (idle · working · blocked · done · unknown).
    public static func fromHerdr(_ s: String?) -> SessionStatus {
        switch s {
        case "working": return .running
        case "blocked": return .needsYou
        case "done": return .done
        default: return .idle
        }
    }
}

/// A session: planned work and/or a live agent in herdr.
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
    /// Owner-set lifecycle (planned / next / doNotUse). Live status comes from herdr.
    public var lifecycle: SessionStatus
    /// herdr agent name once launched (unique, e.g. "roof-1a2b3c").
    public var herdrAgent: String?
    /// herdr workspace the agent was started in (closed on relaunch so no empty shells pile up).
    public var herdrWorkspace: String?
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

    /// Everything after the agent command: the model flag, then any extra arguments.
    public var launchArgs: [String] {
        guard agent.isAgent else { return [] }
        let m = model?.trimmingCharacters(in: .whitespaces) ?? ""
        return (m.isEmpty ? [] : ["--model", m]) + agentArgs
    }

    /// A plain terminal's herdr link is stored as "term:<terminal_id>" in `herdrAgent`.
    public static let terminalPrefix = "term:"

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
        herdrAgent: String? = nil,
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
        self.herdrAgent = herdrAgent
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
             herdrAgent, herdrWorkspace, createdAt, launchedAt, startInRepo, openingSent, agentArgs, model, icon, color, pinned, ticket, ticketId, ticketTeam
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
        herdrAgent = try c.decodeIfPresent(String.self, forKey: .herdrAgent)
        herdrWorkspace = try c.decodeIfPresent(String.self, forKey: .herdrWorkspace)
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
    }

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

    /// The herdr agent name One Roof uses for a session it launches.
    public static func herdrName(for id: String) -> String {
        "roof-" + id.replacingOccurrences(of: "-", with: "").prefix(8).lowercased()
    }
}
