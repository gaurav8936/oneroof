import Foundation

// LAB-2338 · Inbox v4.0 (IB-3, IB-5): how soon an Inbox item needs you, from one function, never from the view.
// P0 = stopped until you act (red), P1 = staged for a yes or no, P2 = to read. Only P0 is red: a report, a proposal,
// commits or a file update are never red, whatever their age.

public enum InboxTier: Int, Comparable, Sendable, CaseIterable {
    case p0 = 0, p1, p2

    public static func < (a: InboxTier, b: InboxTier) -> Bool { a.rawValue < b.rawValue }

    /// The mark on a row and in the panel strip.
    public var label: String { "P\(rawValue)" }

    /// A session ask: a permission or menu blocks the agent (P0); a question at the end of a turn waits for a reply
    /// (P1); a finished turn is to read (P2) unless its last message has halt words (P0).
    public static func of(_ d: Decision) -> InboxTier {
        if d.isQuestion { return .p1 }
        if d.isFinished { return InboxUrgency.of(d) == .critical ? .p0 : .p2 }
        return .p0
    }

    /// A loop item: a round that asks or a loop that stopped at a limit is blocked on you (P0); missed runs and every
    /// staged outcome wait for a decision (P1), except reports and slack notes, which are to read (P2).
    public static func of(loopKind: LoopInbox.Kind, outcomeKind: String = "") -> InboxTier {
        switch loopKind {
        case .failed, .asks: return .p0
        case .missed: return .p1
        case .staged: return outcomeKind == "report" || outcomeKind == "slack" ? .p2 : .p1
        }
    }

    public static func of(_ item: LoopInbox.Item) -> InboxTier { of(loopKind: item.kind, outcomeKind: item.outcomeKind) }

    /// The loop item kind from its id ("failed-…", "asks-…", "missed-…", "staged-…"), for a block that only holds the id.
    public static func loopKind(ofItemId id: String) -> LoopInbox.Kind {
        for k in [LoopInbox.Kind.failed, .asks, .missed] where id.hasPrefix(k.rawValue + "-") { return k }
        return .staged
    }

    /// A block: plans wait for approval (P0); waiting sessions (prompt not read yet) are P2; a loop block uses its
    /// item when known, else the kind in its id (staged then counts as P1).
    public static func of(_ b: InboxBlock, loopItem: LoopInbox.Item? = nil) -> InboxTier {
        switch b.kind {
        case .plan: return .p0
        case .waiting: return .p2
        case .loop:
            if let i = loopItem { return of(i) }
            return of(loopKind: loopKind(ofItemId: b.loopItemId ?? ""))
        default: return b.decision.map(of) ?? .p2
        }
    }
}
