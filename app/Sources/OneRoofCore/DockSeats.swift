import Foundation

// LAB-1998 · the agents the bottom bar (dock seat chips, the compact dock line and the rail's seat bars) shows. It was a
// fixed list (C1 · C2 · CX · KM · GM), so agents added later (Antigravity, OpenCode, Goose) never appeared. Now: every
// agent that is set up on this Mac, in one order, minus the ones the owner turned off in Settings › Seats & accounts.
// One list for every place that draws seats. LAB-1999: a seat is an agent on one account (SeatMark), so accounts added
// in Settings (Codex2, Gemini3 …) follow their agent's first seat.
public enum DockSeats {
    /// The order seats are drawn in.
    public static let order: [AgentMark] = [.claude1, .claude2, .codex, .gemini, .kimi, .antigravity, .opencode, .goose]

    /// What decides "set up": the Claude accounts on this Mac, whether a CLI is installed, and whether the hosted runtime
    /// can start OpenCode / Goose with at least one saved connection. Passed in, so tests need no real Mac.
    public struct Facts: Equatable, Sendable {
        public var claudeAccounts: [String]
        public var installed: Set<AgentKind>
        public var hostedReady: Set<AgentKind>
        /// LAB-1999: every account in One Roof (Settings › Seats & accounts); added ones show after their agent's first.
        public var accounts: [AgentAccount]
        public init(claudeAccounts: [String], installed: Set<AgentKind>, hostedReady: Set<AgentKind>, accounts: [AgentAccount] = []) {
            self.claudeAccounts = claudeAccounts; self.installed = installed; self.hostedReady = hostedReady; self.accounts = accounts
        }
    }

    /// The usage feed's seat name for a seat (`SeatUsage.seat`): Claude1 · Claude2 · ClaudeN · Codex · CodexN · Kimi ·
    /// Gemini …; nil for agents that have no usage feed.
    public static func usageName(_ m: SeatMark) -> String? {
        switch m.mark {
        case .claude1, .claude2: return "Claude\(m.number)"
        case .codex, .kimi, .gemini: return m.number == 1 ? m.agent.displayName : AgentAccounts.id(m.agent, m.number)
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
    public static func setUp(_ f: Facts, usageSeats: Set<String> = []) -> [SeatMark] {
        var out: [SeatMark] = []
        for m in order {
            let first = SeatMark(m)
            let used = usageName(first).map(usageSeats.contains) ?? false
            let on: Bool
            switch m {
            case .claude1: on = f.claudeAccounts.contains("Claude1") || f.installed.contains(.claude)
            case .claude2: on = f.claudeAccounts.contains("Claude2")
            case .opencode, .goose: on = f.hostedReady.contains(agent(m))
            default: on = f.installed.contains(agent(m))
            }
            if used || on { out.append(first) }
            // LAB-1999: the agent's added accounts, after its last first seat (Claude: after C2).
            guard m != .claude1 else { continue }
            let k = agent(m), firstNumbers = k == .claude ? 2 : 1
            var extra = Set(f.accounts.filter { $0.agent == k && $0.number > firstNumbers }.map(\.number))
            if k == .claude { for a in f.claudeAccounts { let n = AgentAccounts.number(a, agent: .claude); if n > 2 { extra.insert(n) } } }
            for n in extra.sorted() {
                let seat = SeatMark(agent: k, number: n)
                if f.installed.contains(k) || f.claudeAccounts.contains(AgentAccounts.id(k, n)) || (usageName(seat).map(usageSeats.contains) ?? false) {
                    out.append(seat)
                }
            }
        }
        return out
    }

    /// The bar: set up, minus what the owner hid.
    public static func shown(_ f: Facts, hidden: [String], usageSeats: Set<String> = []) -> [SeatMark] {
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
        let accounts = settings.agentAccounts(home: home)
        return Facts(claudeAccounts: accounts.filter { $0.agent == .claude }.map(\.id), installed: installed, hostedReady: hosted,
                     accounts: accounts)
    }
}
