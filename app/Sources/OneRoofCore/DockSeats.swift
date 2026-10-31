import Foundation

// LAB-1998 · the agents the bottom bar (dock seat chips, the compact dock line and the rail's seat bars) shows. It was a
// fixed list (C1 · C2 · CX · KM · GM), so agents added later (Antigravity, OpenCode, Goose) never appeared. Now: every
// agent that is set up on this Mac, in one order, minus the ones the owner turned off in Settings › Seats & accounts.
// One list for every place that draws seats; LAB-1999 (more accounts per agent) extends `setUp` with its accounts.
public enum DockSeats {
    /// The order seats are drawn in.
    public static let order: [AgentMark] = [.claude1, .claude2, .codex, .gemini, .kimi, .antigravity, .opencode, .goose]

    /// What decides "set up": the Claude accounts on this Mac, whether a CLI is installed, and whether the hosted runtime
    /// can start OpenCode / Goose with at least one saved connection. Passed in, so tests need no real Mac.
    public struct Facts: Equatable, Sendable {
        public var claudeAccounts: [String]
        public var installed: Set<AgentKind>
        public var hostedReady: Set<AgentKind>
        public init(claudeAccounts: [String], installed: Set<AgentKind>, hostedReady: Set<AgentKind>) {
            self.claudeAccounts = claudeAccounts; self.installed = installed; self.hostedReady = hostedReady
        }
    }

    /// The usage feed's seat name for a mark (`SeatUsage.seat`); nil for agents that have no usage feed.
    public static func usageName(_ m: AgentMark) -> String? {
        switch m {
        case .claude1: return "Claude1"
        case .claude2: return "Claude2"
        case .codex: return "Codex"
        case .kimi: return "Kimi"
        case .gemini: return "Gemini"
        default: return nil
        }
    }

    public static func agent(_ m: AgentMark) -> AgentKind {
        switch m {
        case .claude1, .claude2: return .claude
        case .codex: return .codex
        case .kimi: return .kimi
        case .gemini: return .gemini
        case .antigravity: return .agy
        case .opencode: return .opencode
        case .goose: return .goose
        case .shell: return .shell
        }
    }

    /// Every agent mark that is set up here, in `order`; a mark with usage is always set up (it is clearly in use).
    public static func setUp(_ f: Facts, usageSeats: Set<String> = []) -> [AgentMark] {
        order.filter { m in
            if let n = usageName(m), usageSeats.contains(n) { return true }
            switch m {
            case .claude1: return f.claudeAccounts.contains("Claude1") || f.installed.contains(.claude)
            case .claude2: return f.claudeAccounts.contains("Claude2")
            case .opencode, .goose: return f.hostedReady.contains(agent(m))
            default: return f.installed.contains(agent(m))
            }
        }
    }

    /// The bar: set up, minus what the owner hid.
    public static func shown(_ f: Facts, hidden: [String], usageSeats: Set<String> = []) -> [AgentMark] {
        setUp(f, usageSeats: usageSeats).filter { !hidden.contains($0.rawValue) }
    }

    /// The facts for this Mac (file checks only; call off the main thread or cache the answer).
    public static func facts(settings: AppSettings, home: String = NSHomeDirectory()) -> Facts {
        let fm = FileManager.default
        var installed: Set<AgentKind> = []
        for k in AgentKind.allCases where k.isAgent && !k.isHosted && AccountResolver.installed(k.cliName, home: home) { installed.insert(k) }
        var hosted: Set<AgentKind> = []
        if let r = settings.hostedRuntime, !settings.hostedConnections.isEmpty {
            for k in [AgentKind.opencode, .goose] {
                if let exe = r.nativeExecutables[k.rawValue], !exe.isEmpty, fm.isExecutableFile(atPath: exe) { hosted.insert(k) }
            }
        }
        return Facts(claudeAccounts: AccountResolver.claudeAccounts(home: home), installed: installed, hostedReady: hosted)
    }
}
