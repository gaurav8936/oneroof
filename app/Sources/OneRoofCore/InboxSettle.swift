import Foundation

// LAB-2352 · Inbox rows settle, they do not vanish (owner 11-21, mockup design/20261121_inbox-active-and-settling,
// Part 2 A). A row you handled (or that left by itself) stays where it was, greyed, with what happened; nothing below it
// moves. When you leave the Inbox, or after 10 minutes, it folds into "Done today" at the bottom of the list. Counts
// and the badge drop at once: a settled row no longer needs you. The view draws what this decides.

/// One handled row, as the list keeps it (plain strings, so today's list survives a restart).
public struct InboxDone: Codable, Equatable, Identifiable, Sendable {
    public var id: String          // the block id it had
    public var title: String
    public var postmark: String
    public var tier: Int           // InboxTier raw value when it left
    public var outcome: String     // "✓ Replied: ok" · "Answered in the terminal" · "Expired after 7 days"
    public var verb: String        // for the Done today summary: "replied", "approved", "dismissed", "left on its own"
    public var isLoop: Bool
    public var at: Date            // when it settled
    public var index: Int          // where it was in the list
    public var folded: Bool

    public init(id: String, title: String, postmark: String, tier: Int, outcome: String, verb: String, isLoop: Bool,
                at: Date, index: Int, folded: Bool = false) {
        self.id = id; self.title = title; self.postmark = postmark; self.tier = tier; self.outcome = outcome
        self.verb = verb; self.isLoop = isLoop; self.at = at; self.index = index; self.folded = folded
    }
}

public enum InboxSettle {
    /// A settled row stays in place this long while you stay on the Inbox.
    public static let foldAfter: TimeInterval = 600
    /// Done today keeps at most this many rows (newest first); Decided has the full record.
    public static let keep = 200

    /// Why a row left when you did not act on it in the Inbox.
    public enum Left: Sendable { case answeredInTerminal, sessionClosed, expired, elsewhere, seenInTerminal }

    public static func line(_ l: Left) -> String {
        switch l {
        case .answeredInTerminal: return "Answered in the terminal"
        case .sessionClosed: return "Session closed"
        case .expired: return "Expired after \(LoopInbox.expiryDays) days"
        case .elsewhere: return "Handled outside the Inbox"
        case .seenInTerminal: return "Seen in the terminal"
        }
    }

    /// A session ask that was answered: "✓ Replied: ok" (your words), or the terminal note when it was answered there.
    /// The verb groups it in the Done today summary.
    public static func outcome(_ d: Decision) -> (line: String, verb: String) {
        let text = ScrollFeed.answerText(d) ?? "Answered"
        if d.replyText == "set aside" { return ("✓ Set aside", "set aside") }
        if text.hasPrefix("Answered in its terminal") || text.hasPrefix("Replied in its terminal") {
            return (text.replacingOccurrences(of: "in its terminal", with: "in the terminal"), "answered in the terminal")
        }
        let verb: String
        switch d.answer {
        case .allowOnce?, .always?: verb = "allowed"
        case .deny?: verb = "denied"
        default: verb = "replied"
        }
        return ("✓ " + text, verb)
    }

    /// A loop item you decided here: the ledger status (and reason) in words.
    public static func loopOutcome(status: String, reason: String? = nil) -> (line: String, verb: String) {
        switch status {
        case "approved" where reason == "seen": return ("✓ Marked seen", "marked seen")
        case "approved": return ("✓ Approved", "approved")
        case "applied": return ("✓ Applied", "applied")
        case "rejected" where reason == "stop re-filing": return ("✓ Dismissed · stops re-filing", "dismissed")
        case "rejected": return ("✓ Dismissed", "dismissed")
        case "pr": return ("✓ Approved · opening the PR", "approved")
        case "run": return ("✓ Run started", "ran")
        case "paused": return ("✓ Loop paused", "paused")
        case "seen": return ("✓ Marked seen", "marked seen")
        case "expired": return (line(.expired), "expired")
        default: return ("✓ " + status.capitalized, status)
        }
    }

    /// The list as shown: live rows in order, each unfolded settled row put back where it was.
    public static func order(live: [String], settled: [InboxDone]) -> [(id: String, settled: Bool)] {
        var out = live.map { (id: $0, settled: false) }
        let liveIds = Set(live)
        for s in settled.filter({ !$0.folded && !liveIds.contains($0.id) }).sorted(by: { $0.index < $1.index }) {
            out.insert((id: s.id, settled: true), at: min(max(s.index, 0), out.count))
        }
        return out
    }

    /// Add a settled row (a newer one for the same id replaces it), keep today's only, newest first, at most `keep`.
    public static func add(_ d: InboxDone, to rows: [InboxDone], now: Date = Date(), calendar: Calendar = .current) -> [InboxDone] {
        Array(([d] + rows.filter { $0.id != d.id }).filter { calendar.isDate($0.at, inSameDayAs: now) }.prefix(keep))
    }

    /// Fold rows into Done today: all of them when you leave the Inbox, else those settled `foldAfter` ago.
    public static func fold(_ rows: [InboxDone], now: Date = Date(), leaving: Bool) -> [InboxDone] {
        rows.map { r in
            var r = r
            if leaving || now.timeIntervalSince(r.at) >= foldAfter { r.folded = true }
            return r
        }
    }

    /// Only today's rows (a list read back after midnight starts empty).
    public static func today(_ rows: [InboxDone], now: Date = Date(), calendar: Calendar = .current) -> [InboxDone] {
        rows.filter { calendar.isDate($0.at, inSameDayAs: now) }
    }

    /// "replied 2 · approved 1 · dismissed 1": the most common first, at most four kinds.
    public static func summary(_ rows: [InboxDone]) -> String {
        var n: [String: Int] = [:]
        var first: [String: Int] = [:]
        for (i, r) in rows.enumerated() { n[r.verb, default: 0] += 1; if first[r.verb] == nil { first[r.verb] = i } }
        return n.sorted { $0.value != $1.value ? $0.value > $1.value : first[$0.key]! < first[$1.key]! }
            .prefix(4).map { "\($0.key) \($0.value)" }.joined(separator: " · ")
    }

    /// LAB-2351 (Part 1 A): what the open sessions with nothing for you are doing, for the Inbox header.
    /// "3 sessions open, all idle" · "1 session open, working" · "3 open · 1 working · 2 idle"; "other" when some
    /// sessions are in the list. Nil when there are none.
    public static func sessionsLine(working: Int, ready: Int, idle: Int, other: Bool) -> String? {
        let n = working + ready + idle
        guard n > 0 else { return nil }
        let parts = [(working, "working"), (ready, "ready"), (idle, "idle")].filter { $0.0 > 0 }
        let noun = (other ? "other " : "") + (n == 1 ? "session" : "sessions")
        if parts.count == 1 { return "\(n) \(noun) open, " + (n == 1 ? parts[0].1 : "all " + parts[0].1) }
        return "\(n) " + (other ? "other " : "") + "open · " + parts.map { "\($0.0) \($0.1)" }.joined(separator: " · ")
    }

    /// The status a live session counts under in `sessionsLine` (nil: not counted).
    public static func bucket(_ s: SessionStatus) -> String? {
        switch s {
        case .running: return "working"
        case .done, .needsYou: return "ready"
        case .idle: return "idle"
        default: return nil
        }
    }
}
