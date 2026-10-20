import Foundation

/// What a session's agent is doing (T14 §3f), worked out by roofd from the strongest signal down:
/// Claude hooks → screen (permission / question prompts, "esc to interrupt" lines) → output activity.
/// Pure and clock-free (every call takes `now`), so the rules are unit-tested; roofd runs one per session (Q4).
public struct StatusEngine: Sendable {
    public struct Observation: Sendable {
        public var now: Date
        /// The agent in the foreground; nil when the session is a plain shell (or the agent has exited).
        public var agent: AgentKind?
        public var lastOutput: Date?
        /// The bottom of the screen (plain text), read once output has paused.
        public var screen: String

        public init(now: Date, agent: AgentKind?, lastOutput: Date?, screen: String) {
            self.now = now; self.agent = agent; self.lastOutput = lastOutput; self.screen = screen
        }
    }

    /// Output within this window means the agent is working.
    public static let busyWindow: TimeInterval = 1.5
    /// Quiet this long after working means a turn finished.
    public static let doneAfter: TimeInterval = 3

    public private(set) var status: RuntimeStatus = .unknown
    public private(set) var ready = false
    private var agent: AgentKind?
    private var agentSince: Date?
    private var hookStatus: RuntimeStatus?
    private var hookAt: Date?
    private var workedSinceInput = false
    private var lastInput: Date?

    public init() {}

    // MARK: Signals

    /// A Claude hook (`roofd report claude`): the strongest signal there is.
    public mutating func hook(_ event: String, message: String? = nil, at now: Date) {
        switch event {
        case "SessionStart": hookStatus = .idle; ready = true
        case "UserPromptSubmit", "PreToolUse", "PostToolUse": hookStatus = .working; workedSinceInput = true
        case "Notification":
            // Permission and question notifications block; "waiting for your input" is just idle.
            let m = (message ?? "").lowercased()
            if m.contains("permission") || m.contains("approve") || m.contains("needs your") { hookStatus = .blocked }
            else { return }
        case "Stop": hookStatus = .done; ready = true
        case "SessionEnd": hookStatus = nil; status = .unknown; ready = false; return
        default: return
        }
        hookAt = now
    }

    /// Someone typed into the session: a finished turn is no longer news.
    public mutating func input(at now: Date) {
        lastInput = now
        workedSinceInput = false
        if status == .done { status = .idle }
        if hookStatus == .done { hookStatus = .idle }
    }

    /// The owner looked at the session.
    public mutating func seen() {
        if status == .done { status = .idle }
        if hookStatus == .done { hookStatus = .idle }
        workedSinceInput = false
    }

    // MARK: Evaluate

    @discardableResult
    public mutating func evaluate(_ o: Observation) -> RuntimeStatus {
        if o.agent != agent {
            agent = o.agent
            agentSince = o.agent == nil ? nil : o.now
            hookStatus = nil; hookAt = nil; workedSinceInput = false; ready = false
        }
        guard let kind = o.agent else { status = .unknown; ready = false; return status }

        let quietFor = o.lastOutput.map { o.now.timeIntervalSince($0) } ?? .infinity
        let busy = quietFor < Self.busyWindow
        let bottom = StatusEngine.bottomLines(o.screen, 40)
        let prompt = quietFor >= 0.3 ? DecisionMatcher.match(bottom, agent: kind).flatMap { StatusEngine.isLive($0, in: bottom) ? $0 : nil } : nil
        let spinner = StatusEngine.workingLine(bottom)

        // Ready: the CLI has drawn its screen and gone quiet (its input box is waiting), or a hook said so. Output
        // before that is the CLI starting up, not a turn.
        if !ready, let since = agentSince, o.now.timeIntervalSince(since) >= 1, o.lastOutput != nil, quietFor >= 1,
           prompt == nil, !spinner {
            ready = true
            status = .idle
            return status
        }
        var next: RuntimeStatus
        if prompt != nil {
            next = .blocked                                    // a permission or question prompt is on screen
        } else if let h = hookStatus {
            // Hooks lead. Fresh output after the last hook (a new turn, or a prompt answered in the terminal)
            // means working until the next hook says otherwise.
            let outputSinceHook = (o.lastOutput ?? .distantPast) > (hookAt ?? .distantPast).addingTimeInterval(0.5)
            next = h != .working && busy && outputSinceHook ? .working : h
        } else if busy || spinner {
            next = .working
        } else if workedSinceInput && quietFor >= Self.doneAfter {
            next = .done
        } else if status == .working && quietFor < Self.doneAfter {
            next = .working
        } else {
            next = status == .done ? .done : .idle
        }
        if next == .working && ready { workedSinceInput = true }
        status = next
        return status
    }

    // MARK: Screen rules

    static func bottomLines(_ s: String, _ n: Int) -> String {
        let lines = s.split(separator: "\n", omittingEmptySubsequences: false)
        return lines.suffix(n).joined(separator: "\n")
    }

    /// A prompt is waiting only while it is the last thing on screen: after its question come its options and at most
    /// one hint line. An answered prompt that is still visible higher up (the agent moved on) does not block.
    static func isLive(_ m: PromptMatch, in screen: String) -> Bool {
        let lines = TerminalText.lines(screen).map(TerminalText.unboxed)
        guard let q = lines.lastIndex(of: m.question) else { return true }
        let after = lines[(q + 1)...].filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty && !TerminalText.isChrome($0) }
        return after.count <= m.options.count + 1
    }

    /// The "I am busy" line each CLI draws while a turn runs.
    public static func workingLine(_ screen: String) -> Bool {
        let tail = bottomLines(screen, 12).lowercased()
        return ["esc to interrupt", "esc to cancel", "ctrl+c to interrupt", "ctrl-c to interrupt", "press esc to stop"]
            .contains { tail.contains($0) }
    }

    /// The agent behind a process: its name or argv (node-based CLIs run as `node …/codex`).
    public static func agentKind(processName: String?, argv: [String]) -> AgentKind? {
        for candidate in [processName] + argv.prefix(3).map { ($0 as NSString).lastPathComponent } + argv.prefix(3).map { $0 } {
            guard let c = candidate?.lowercased(), !c.isEmpty else { continue }
            if c.hasSuffix("zsh") || c.hasSuffix("bash") || c == "-zsh" || c == "login" { continue }
            if let k = AgentKind(herdrName: c), k.isAgent { return k }
            if c.contains("antigravity") { return .agy }
        }
        return nil
    }
}
