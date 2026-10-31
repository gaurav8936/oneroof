import Foundation

/// LAB-1600: how much an agent may do without asking, set once per agent in Settings › Permissions and used by every
/// new session (default Auto, owner 2026-10-29: "auto by default and manual only if I need to").
///
/// Each mode maps to the agent CLI's own flags, checked against each CLI's `--help` (10-29):
/// - Claude Code: `--permission-mode manual | plan | auto` (auto = the classifier-gated mode).
/// - Codex: `--ask-for-approval on-request` · `--sandbox read-only --ask-for-approval on-request` · `--approve-for-me`
///   (approval requests reviewed for you inside the workspace-write sandbox). Codex has no plan mode: "Read only".
/// - Kimi: no flag (asks) · `--plan` · `--yolo` (Ask When Needed: routine edits and commands run, risky ones still ask).
/// - Gemini: `--approval-mode default | plan | yolo`.
/// - Antigravity: no flag (asks) · `--mode plan` · `--mode auto`.
/// Loops and objective steps keep their own auto behaviour (`AgentKind.autoApproveArgs`).
public enum PermissionMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case manual, plan, auto

    public var id: String { rawValue }

    /// The mode every agent starts in until the owner picks another.
    public static let defaultMode: PermissionMode = .auto

    /// Short name shown on sessions and in pickers.
    public var label: String {
        switch self {
        case .manual: return "Manual"
        case .plan: return "Plan"
        case .auto: return "Auto"
        }
    }

    /// The agent's own name for the mode, where it differs (Codex has no plan mode, only a read-only sandbox).
    public func label(for agent: AgentKind) -> String {
        if agent == .codex, self == .plan { return "Read only" }
        return label
    }

    /// One plain line on what the mode does for that agent.
    public func meaning(for agent: AgentKind) -> String {
        switch (self, agent) {
        case (.manual, _): return "Asks you before each edit or command."
        case (.plan, .codex): return "Reads and suggests; asks before anything that writes."
        case (.plan, _): return "Plans first and changes nothing until you approve the plan."
        case (.auto, .claude): return "Works on its own; a safety check stops risky actions."
        case (.auto, .codex): return "Works on its own in the workspace sandbox; approvals are reviewed for you."
        case (.auto, .kimi): return "Routine edits and commands run; risky actions still ask."
        case (.auto, .gemini): return "Approves every tool on its own."
        case (.auto, .agy): return "Works on its own in the CLI's auto mode."
        case (.auto, .opencode), (.auto, .goose): return "Requires a configured guarded launcher; unattended approval is unavailable here."
        case (.auto, .shell): return ""
        }
    }

    /// The CLI flags that start `agent` in this mode. Empty = the CLI's own default (it asks).
    public func args(for agent: AgentKind) -> [String] {
        switch (agent, self) {
        case (.claude, _): return ["--permission-mode", rawValue]
        case (.codex, .manual): return ["--ask-for-approval", "on-request"]
        case (.codex, .plan): return ["--sandbox", "read-only", "--ask-for-approval", "on-request"]
        case (.codex, .auto): return ["--approve-for-me"]
        case (.kimi, .manual): return []
        case (.kimi, .plan): return ["--plan"]
        case (.kimi, .auto): return ["--yolo"]
        case (.gemini, .manual): return ["--approval-mode", "default"]
        case (.gemini, .plan): return ["--approval-mode", "plan"]
        case (.gemini, .auto): return ["--approval-mode", "yolo"]
        case (.agy, .manual): return []
        case (.agy, .plan): return ["--mode", "plan"]
        case (.agy, .auto): return ["--mode", "auto"]
        case (.opencode, _), (.goose, _): return [] // supervised launcher owns approval mode
        case (.shell, _): return []
        }
    }

    /// Flags (bare or `--flag=value`) that already set how `agent` asks for permission. When a session's own arguments
    /// carry one, the chosen mode adds nothing: the explicit arguments win and no flag is doubled.
    public static func modeFlags(for agent: AgentKind) -> [String] {
        switch agent {
        case .claude: return ["--permission-mode", "--dangerously-skip-permissions"]
        case .codex: return ["-a", "--ask-for-approval", "-s", "--sandbox", "--approve-for-me", "--full-auto",
                             "--dangerously-bypass-approvals-and-sandbox", "--yolo"]
        case .kimi: return ["-y", "--yolo", "--auto", "--plan"]
        case .gemini: return ["--approval-mode", "-y", "--yolo"]
        case .agy: return ["--mode", "--dangerously-skip-permissions"]
        case .opencode, .goose: return []
        case .shell: return []
        }
    }

    /// Whether `args` already choose a permission mode for `agent`.
    public static func hasExplicit(_ args: [String], agent: AgentKind) -> Bool {
        let flags = modeFlags(for: agent)
        return args.contains { a in flags.contains { a == $0 || a.hasPrefix($0 + "=") } }
    }

    /// The mode `args` start `agent` in, when they match one of the modes exactly; nil otherwise.
    public static func detect(_ args: [String], agent: AgentKind) -> PermissionMode? {
        guard agent.isAgent else { return nil }
        let joined = args.map { $0.replacingOccurrences(of: "=", with: " ") }.joined(separator: " ")
        // Most specific first: Codex's read-only line contains its manual line.
        for m in [PermissionMode.plan, .auto, .manual] {
            let flags = m.args(for: agent)
            if flags.isEmpty { continue }
            let needle = flags.joined(separator: " ")
            if (" " + joined + " ").contains(" " + needle + " ") { return m }
        }
        if agent == .claude, (" " + joined + " ").contains(" --permission-mode default ") { return .manual }
        return nil
    }

    /// The arguments a session launches with: the chosen mode's flags after its own arguments, unless those already
    /// set a mode (or there is no mode: rows made before LAB-1600 launch exactly as before).
    public static func launchArgs(_ args: [String], mode: PermissionMode?, agent: AgentKind) -> [String] {
        guard agent.isAgent, let mode, !hasExplicit(args, agent: agent) else { return args }
        return args + mode.args(for: agent)
    }
}

/// What a session shows for its permission mode (LAB-1600): the mode its arguments set, else the mode it was given,
/// else "Custom" when its arguments set a mode of their own; nil for terminals and older rows with neither.
public enum PermissionBadge {
    public static func label(for s: Session) -> String? {
        guard s.agent.isAgent else { return nil }
        if let m = PermissionMode.detect(s.agentArgs, agent: s.agent) { return m.label(for: s.agent) }
        if PermissionMode.hasExplicit(s.agentArgs, agent: s.agent) { return "Custom" }
        return s.permissionMode?.label(for: s.agent)
    }
}
