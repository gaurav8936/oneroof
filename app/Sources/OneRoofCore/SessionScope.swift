import Foundation

/// LAB-1933 · "Session" means a session a person started. Loop rounds are sessions too (roofd's loop engine starts
/// each one, tagged `loop:<loop id>`), but they belong to the Loops area only: the session rail (This window / All
/// sessions), Needs you, the All · Active · Exited counts, the session catalog and search show manual sessions only.
/// A loop round's terminal still opens from its loop's page (its Runs list).
public enum SessionScope {
    /// The loop a session's round belongs to, nil for a manual session.
    public static func loopId(_ tags: [String]) -> String? {
        tags.first { $0.hasPrefix("loop:") }.map { String($0.dropFirst("loop:".count)) }
    }
    public static func isLoop(_ s: Session) -> Bool { loopId(s.tags) != nil }
    /// The sessions a person started, in order.
    public static func manual(_ sessions: [Session]) -> [Session] { sessions.filter { !isLoop($0) } }
}

public extension SessionScope {
    /// The rows a person started (every session list, count, search and the Needs you badge use these).
    static func sessions(_ items: [BoardItem]) -> [BoardItem] { items.filter { !isLoop($0.session) } }

    /// Needs you: open asks of manual sessions only, oldest first. A question or permission prompt waits while its
    /// session needs you; a finished turn (LAB-1827) while its session is Ready or Idle. A loop round's asks go to its
    /// loop (the Loops area and the loop alert), never here.
    static func openDecisions(_ decisions: [Decision], item: (String) -> BoardItem?) -> [Decision] {
        decisions.filter { d in
            guard d.isOpen, let i = item(d.sessionId), !isLoop(i.session) else { return false }
            return d.isFinished ? [.done, .idle].contains(i.status) : i.status == .needsYou
        }
        .sorted { $0.askedAt < $1.askedAt }
    }

    /// The Needs you badge (rail, toolbar row, menu bar, Dock): open asks plus plans waiting, or the sessions that need
    /// you when the engine has not filed their ask yet, whichever is more.
    static func needsYouCount(openAsks: Int, plansWaiting: Int, items: [BoardItem]) -> Int {
        max(openAsks + plansWaiting, sessions(items).filter { $0.status == .needsYou }.count)
    }
}
