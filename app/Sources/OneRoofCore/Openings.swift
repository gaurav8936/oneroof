import Foundation

/// When a pending opening message may be sent: the agent has been ready and idle for its settle time, it is not
/// already being sent, and no retry wait is running. Never into a busy, blocked or still-starting agent.
public struct OpeningGate: Sendable {
    public private(set) var idleSince: [RuntimeID: Date] = [:]

    public init() {}

    /// Some CLIs report ready before they accept input (Kimi connects its MCP servers first and drops what is
    /// typed meanwhile), so each agent gets its own settle time.
    public static func settle(_ a: AgentKind) -> TimeInterval {
        switch a { case .kimi: return 10; case .agy, .gemini: return 6; default: return 2 }
    }

    /// Track how long each live agent has been ready and idle.
    public mutating func observe(_ items: [BoardItem], now: Date) {
        for item in items {
            guard let agent = item.liveAgent else { continue }
            if item.status == .idle && item.ready {
                if idleSince[agent] == nil { idleSince[agent] = now }
            } else {
                idleSince[agent] = nil
            }
        }
    }

    /// Start the settle wait again (a resend after a message that did not land).
    public mutating func restart(_ agent: RuntimeID, at date: Date) { idleSince[agent] = date }

    public func due(_ items: [BoardItem], now: Date, sending: Set<String>, retryAfter: [String: Date]) -> [BoardItem] {
        items.filter { item in
            guard item.session.agent.isAgent, item.session.openingPending, !sending.contains(item.id),
                  let agent = item.liveAgent, let since = idleSince[agent],
                  now.timeIntervalSince(since) >= Self.settle(item.session.agent) else { return false }
            if let next = retryAfter[item.id], now < next { return false }
            return true
        }
    }
}
