import Foundation

// What runs sessions (T14 §4): roofd in the app, FakeRuntime in tests. The app talks only to `SessionRuntime`.

/// A session's address in its runtime: roofd session id ("roof-1a2b3c4d"); old rows may hold herdr's "term:<id>".
public typealias RuntimeID = String

public enum RuntimeKind: String, Codable, Sendable {
    case roofd, fake
    public var displayName: String { rawValue }
}

/// Live agent state as the runtime reports it.
public enum RuntimeStatus: String, Sendable, Equatable {
    case idle, working, blocked, done, unknown

    public init(_ raw: String?) { self = raw.flatMap(RuntimeStatus.init(rawValue:)) ?? .unknown }

    /// The agent has picked up work (used to confirm an opening message landed).
    public var started: Bool { [.working, .blocked, .done].contains(self) }
}

extension SessionStatus {
    public init(_ s: RuntimeStatus) {
        switch s {
        case .working: self = .running
        case .blocked: self = .needsYou
        case .done: self = .done
        case .idle, .unknown: self = .idle
        }
    }
}

/// One live session (an agent, or a plain shell) in the runtime's latest snapshot.
public struct RuntimeSessionState: Sendable, Equatable {
    public var id: RuntimeID
    /// The runtime detected an agent here. `agentName` is what it calls it; `agent` is nil when that name is unknown.
    public var isAgent: Bool
    public var agentName: String?
    public var agent: AgentKind? { AgentKind(detectedName: agentName) }
    public var status: RuntimeStatus
    public var ready: Bool
    public var title: String?
    public var cwd: String?
    /// Where pane-level I/O goes (`type`, `keys`, `read`, `processes`): roofd the session id.
    public var pane: String
    /// Runtime group (herdr-era workspace); roofd nil.
    public var groupId: String?
    /// Bumps when the session's output changes (the caption engine's "new output" signal).
    public var seq: Int?
    /// Where the agent last worked (a file or folder its tools touched), when its hooks report it.
    public var workPath: String?
    /// When the runtime last saw the session do something (LAB-258); nil from runtimes that do not say.
    public var activeAt: Date?
    /// The process the runtime started for the session (roofd: the shell or agent under the holder), for Resources
    /// (LAB-493); nil from runtimes that do not say.
    public var pid: Int32?
    /// roofd's memory guard says the holder is past its warning line (LAB-310).
    public var memoryWarning: Bool = false
    /// Issue updates the session's agent asked for and the app has not answered yet (LAB-518).
    public var issueRequests: [IssueRequest] = []
    /// LAB-1606: the question the agent's turn ended with, while it waits for your reply (roofd).
    public var question: String?

    public init(id: RuntimeID, isAgent: Bool, agentName: String? = nil, status: RuntimeStatus = .unknown, ready: Bool = false,
                title: String? = nil, cwd: String? = nil, pane: String, groupId: String? = nil, seq: Int? = nil,
                workPath: String? = nil, activeAt: Date? = nil, pid: Int32? = nil, memoryWarning: Bool = false,
                issueRequests: [IssueRequest] = []) {
        self.id = id; self.isAgent = isAgent; self.agentName = agentName; self.status = status; self.ready = ready
        self.title = title; self.cwd = cwd; self.pane = pane; self.groupId = groupId; self.seq = seq; self.workPath = workPath
        self.activeAt = activeAt; self.pid = pid; self.memoryWarning = memoryWarning; self.issueRequests = issueRequests
    }
}

public struct RuntimeSnapshot: Sendable, Equatable {
    public var version: String?
    public var protocolVersion: Int?
    /// Agents first (in the runtime's order), then plain shells.
    public var sessions: [RuntimeSessionState]

    public init(version: String? = nil, protocolVersion: Int? = nil, sessions: [RuntimeSessionState] = []) {
        self.version = version; self.protocolVersion = protocolVersion; self.sessions = sessions
    }

    public var agents: [RuntimeSessionState] { sessions.filter(\.isAgent) }
    public func session(_ id: RuntimeID) -> RuntimeSessionState? { sessions.first { $0.id == id } }
}

/// What to start. `id` is the preferred name; the runtime makes it unique (`-2`, `-3` …) and returns the one it used.
public struct LaunchSpec: Sendable {
    public var id: RuntimeID
    public var label: String
    public var cwd: String
    public var env: [String: String]
    public var agent: AgentKind              // .shell = plain terminal
    public var args: [String]
    /// A command to type into a plain terminal once its shell is up (a Fix button).
    public var command: String?
    /// The session's previous group (relaunch): closed before the new one starts.
    public var previousGroup: String?
    /// Link a live agent already named `id` (an earlier launch that reported an error but worked) instead of
    /// starting a second, unless another stored session owns that name.
    public var adoptOrphan: Bool
    public var claimed: Set<RuntimeID>
    /// The opening message, for a runtime that delivers it itself once the agent is ready (roofd); nil = the app does.
    public var opening: String?
    /// Trusted supervised launcher; hosted sessions bypass the owner login shell.
    public var executableOverride: String? = nil

    public init(id: RuntimeID, label: String, cwd: String, env: [String: String] = [:], agent: AgentKind, args: [String] = [],
                command: String? = nil, previousGroup: String? = nil, adoptOrphan: Bool = false, claimed: Set<RuntimeID> = []) {
        self.id = id; self.label = label; self.cwd = cwd; self.env = env; self.agent = agent; self.args = args
        self.command = command; self.previousGroup = previousGroup; self.adoptOrphan = adoptOrphan; self.claimed = claimed
    }
}

public struct RuntimeSessionRef: Sendable, Equatable {
    public var id: RuntimeID
    public var groupId: String?
    /// An existing agent was linked rather than started (see `LaunchSpec.adoptOrphan`).
    public var adopted: Bool

    public init(id: RuntimeID, groupId: String? = nil, adopted: Bool = false) {
        self.id = id; self.groupId = groupId; self.adopted = adopted
    }
}

public enum RuntimeKey: String, Sendable { case escape, enter, ctrlC }

public struct RuntimeProcesses: Sendable, Equatable {
    public struct Proc: Sendable, Equatable {
        public var pid: Int32
        public var name: String?
        public var argv: [String]
        public init(pid: Int32, name: String? = nil, argv: [String] = []) { self.pid = pid; self.name = name; self.argv = argv }
    }
    public var shellPid: Int32?
    public var foreground: [Proc]
    public init(shellPid: Int32? = nil, foreground: [Proc] = []) { self.shellPid = shellPid; self.foreground = foreground }
}

/// The Foundations row for the runtime.
public struct RuntimeHealth: Sendable, Equatable {
    public var level: CheckLevel
    public var detail: String
    public var fix: String?
    public init(level: CheckLevel, detail: String, fix: String? = nil) { self.level = level; self.detail = detail; self.fix = fix }
}

public enum RuntimeError: Error, Equatable, CustomStringConvertible {
    /// The agent exists but is not accepting input yet (still starting, or waiting on a prompt).
    case notReady(String)
    case failed(String)

    public var description: String {
        switch self {
        case .notReady(let m): return "agent not ready: \(m)"
        case .failed(let m): return m
        }
    }
}

/// What runs sessions. All calls block; the app calls them off the main thread.
public protocol SessionRuntime: AnyObject, Sendable {
    var kind: RuntimeKind { get }
    /// The protocol this build of One Roof speaks (nil = no version check).
    var expectedProtocol: Int? { get }
    func health() -> RuntimeHealth
    /// Start the runtime if it is not answering.
    func ensureRunning() throws
    func snapshot() throws -> RuntimeSnapshot

    func start(_ spec: LaunchSpec) throws -> RuntimeSessionRef
    /// End a session (its agent or shell process).
    func close(_ id: RuntimeID, group: String?) throws
    /// Type text into an agent and press Enter. Callers send only when the agent is idle.
    func submit(_ id: RuntimeID, text: String) throws
    /// Type text without Enter.
    func type(pane: String, text: String) throws
    func keys(pane: String, _ keys: [RuntimeKey]) throws
    /// Recent text on screen and in scrollback.
    func read(pane: String, lines: Int) throws -> String
    func processes(pane: String) throws -> RuntimeProcesses
    /// What a terminal surface runs to show a session.
    func attachCommand(_ id: RuntimeID) -> String
    /// The owner has looked at a finished session: its "done" becomes "idle".
    func markSeen(_ id: RuntimeID)
}

extension SessionRuntime {
    public func markSeen(_ id: RuntimeID) {}
}

extension SessionRuntime {
    /// One line for the status bar: "roofd 0.1.0 · 3 agents", or a protocol mismatch.
    public func statusLine(_ snap: RuntimeSnapshot) -> String {
        let proto = snap.protocolVersion ?? 0
        if let want = expectedProtocol, proto != 0, proto != want {
            return "\(kind.displayName) \(snap.version ?? "?") · protocol \(proto) (One Roof expects \(want))"
        }
        let n = snap.agents.count
        return "\(kind.displayName) \(snap.version ?? "") · \(n) agent\(n == 1 ? "" : "s")"
    }
}

/// The runtime One Roof uses: roofd, its own session manager (LAB-ROOFD; herdr removed in LAB-20).
public enum Runtimes {
    public static func make() -> SessionRuntime { RoofdRuntime() }
}
