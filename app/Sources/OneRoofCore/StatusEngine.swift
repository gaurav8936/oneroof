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
    /// A hook's "working" with nothing on screen to back it, after this long, is stale.
    public static let staleHook: TimeInterval = 8

    public private(set) var status: RuntimeStatus = .unknown
    public private(set) var ready = false
    private var agent: AgentKind?
    private var agentSince: Date?
    private var hookStatus: RuntimeStatus?
    private var hookAt: Date?
    private var workedSinceInput = false
    private var lastInput: Date?
    /// When the CLI first drew and went quiet; output before it is start-up, not work.
    private var readyAt: Date?

    public init() {}

    // MARK: Signals

    /// A Claude hook (`roofd report claude`): the strongest signal there is.
    public mutating func hook(_ event: String, message: String? = nil, at now: Date) {
        switch event {
        case "SessionStart": hookStatus = .idle; ready = true; readyAt = readyAt ?? now
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
            hookStatus = nil; hookAt = nil; workedSinceInput = false; ready = false; readyAt = nil
        }
        guard let kind = o.agent else { status = .unknown; ready = false; return status }

        let quietFor = o.lastOutput.map { o.now.timeIntervalSince($0) } ?? .infinity
        let outputSinceReady = readyAt.map { (o.lastOutput ?? .distantPast) > $0 } ?? true
        let busy = quietFor < Self.busyWindow && outputSinceReady
        let bottom = StatusEngine.bottomLines(o.screen, 40)
        let menu = StatusEngine.selectionMenu(bottom)
        let permission = quietFor >= 0.3 ? DecisionMatcher.match(bottom, agent: kind).flatMap { StatusEngine.isLive($0, in: bottom) ? $0 : nil } : nil
        // A permission prompt, or any choice menu the CLI is waiting on (folder trust, login, update): needs the owner.
        let prompt: Bool = permission != nil || (quietFor >= 0.3 && menu)
        let spinner = !menu && StatusEngine.workingLine(bottom)

        // Ready: the CLI has drawn its screen and gone quiet (its input box is waiting), or a hook said so. Output
        // before that is the CLI starting up, not a turn.
        if !ready, let since = agentSince, o.now.timeIntervalSince(since) >= 1, o.lastOutput != nil, quietFor >= 1,
           !prompt, !spinner {
            ready = true
            readyAt = o.now
            status = .idle
            return status
        }
        var next: RuntimeStatus
        if prompt {
            next = .blocked                                    // a permission or question prompt is on screen
        } else if let h = hookStatus {
            // Hooks decide (UserPromptSubmit / PreToolUse → working, Stop → done): screen repaints after a Stop are
            // not a new turn; a new turn sends its own hook. Only a prompt on screen overrides them (above).
            // Safety net: "working" from a hook with no spinner and no screen change for 8 s is stale (a hook
            // without its Stop): the CLI is at its prompt. Long tool runs keep a spinner line, so they stay working.
            next = h == .working && !spinner && quietFor >= Self.staleHook ? (workedSinceInput ? .done : .idle) : h
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

    /// A choice menu waiting at the bottom of the screen: a selection marker plus the CLI's confirm / cancel hint.
    public static func selectionMenu(_ screen: String) -> Bool {
        let tail = bottomLines(screen.trimmingCharacters(in: .whitespacesAndNewlines), 14).lowercased()
        // ❯ › (Claude, Codex) or ● ○ (Gemini's radio list); only counts together with a confirm/select hint below.
        let marker = tail.contains("❯") || tail.contains("›") || tail.contains("> 1.") || tail.contains("●") || tail.contains("○")
        let hint = ["enter to confirm", "enter to select", "space to select", "esc to reject", "to navigate", "↑/↓",
                    "use arrow keys", "press enter"].contains { tail.contains($0) }
        return marker && hint
    }

    /// The screen without its bottom status area, so a repaint of the status bar alone is not activity: everything
    /// from the CLI's input-box border down (a ─── / ╭──╮ line among the last 12), else the last 5 non-empty lines.
    public static func contentKey(_ screen: String) -> String {
        var lines = screen.split(separator: "\n", omittingEmptySubsequences: false).map { $0.trimmingCharacters(in: .whitespaces) }
        while lines.last?.isEmpty == true { lines.removeLast() }
        let window = max(0, lines.count - 12)
        let border = lines[window...].firstIndex { l in
            l.count >= 10 && (l.hasPrefix("╭") || l.hasPrefix("╰") || l.allSatisfy { "─━═-▔▁".contains($0) })
        }
        if let b = border { return lines[..<b].joined(separator: "\n") }
        var dropped = 0
        while dropped < 5, !lines.isEmpty { if !(lines.removeLast().isEmpty) { dropped += 1 } }
        return lines.joined(separator: "\n")
    }

    /// The "I am busy" line each CLI draws while a turn runs.
    public static func workingLine(_ screen: String) -> Bool {
        let tail = bottomLines(screen, 12)
        let lower = tail.lowercased()
        if ["esc to interrupt", "esc to cancel", "ctrl+c to interrupt", "ctrl-c to interrupt", "press esc to stop"]
            .contains(where: { lower.contains($0) }) { return true }
        // Gemini / Antigravity spinners: a line that starts with a braille frame ("⣻  Generating..."); it can sit
        // still while the model thinks, so it counts even when the screen does not change.
        // Only one frame, then a space and words: Codex's start-up logo is drawn in braille too (whole rows of it) and
        // kept a wide Codex session "working", so its opening message never went (found in the visual pass).
        return tail.split(separator: "\n").contains { line in
            let u = Array(line.trimmingCharacters(in: .whitespaces).unicodeScalars)
            guard u.count >= 3, (0x2801...0x28FF).contains(u[0].value), u[1] == " " else { return false }
            return u.dropFirst(2).contains { CharacterSet.letters.contains($0) && !(0x2800...0x28FF).contains($0.value) }
        }
    }

    /// The agent behind a process: its name or argv (node-based CLIs run as `node …/codex`).
    public static func agentKind(processName: String?, argv: [String]) -> AgentKind? {
        for candidate in [processName] + argv.prefix(3).map { ($0 as NSString).lastPathComponent } + argv.prefix(3).map { $0 } {
            guard let c = candidate?.lowercased(), !c.isEmpty else { continue }
            if c.hasSuffix("zsh") || c.hasSuffix("bash") || c == "-zsh" || c == "login" { continue }
            if let k = AgentKind(detectedName: c), k.isAgent { return k }
            if c.contains("antigravity") { return .agy }
        }
        return nil
    }
}
