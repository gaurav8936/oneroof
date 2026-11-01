import Foundation

/// LAB-2110: the Inbox's second tab — the one paged record of what you decided (the Action log is gone; its rules
/// moved to Settings › Permissions). Paged in SQL (`SessionStore.decided`, LAB-2082).
public enum Decided {
    public static let pageSize = 50

    /// The tab's title: "Decided" with today's count when there is one.
    public static func tabTitle(today: Int) -> String { today > 0 ? "Decided · \(today) today" : "Decided" }

    /// What you answered, in your words (LAB-2106): your reply or the option you chose; what you typed in the agent's
    /// own terminal when One Roof could read it; otherwise how it was answered.
    public static func answer(_ d: Decision) -> String {
        if let typed = TerminalReply.typed(d.replyText) { return "You replied in its terminal: " + typed }
        return ScrollFeed.answerText(d) ?? "Waiting"
    }
}

/// LAB-2106: a reply typed in the agent's own terminal, recorded with the ask ("answered in the terminal: <words>").
public enum TerminalReply {
    public static let marker = "answered in the terminal"

    public static func record(_ typed: String?) -> String {
        guard let t = typed?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty else { return marker }
        return marker + ": " + t
    }

    /// The words, when the record holds them.
    public static func typed(_ reply: String?) -> String? {
        guard let r = reply, r.hasPrefix(marker + ": ") else { return nil }
        let t = String(r.dropFirst(marker.count + 2)).trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }

    /// Answered in the terminal, with or without the words.
    public static func isTerminal(_ reply: String?) -> Bool {
        guard let r = reply?.trimmingCharacters(in: .whitespacesAndNewlines) else { return false }
        return r == marker || r.hasPrefix(marker + ": ")
    }

    /// The last message you typed into an agent CLI, read from its screen: the newest prompt line ("> words" in
    /// Claude Code, "› words" in Codex, "❯ words"), outside the live input box, with its wrapped continuation lines.
    /// nil when there is none. Only used for a finished turn or a question (where you answer by typing).
    public static func lastTyped(in text: String) -> String? {
        let lines = TerminalText.lines(text)
        var i = lines.count - 1
        while i >= 0 {
            let raw = lines[i]
            let boxed = raw.trimmingCharacters(in: .whitespaces).hasPrefix("│")
            let l = raw.trimmingCharacters(in: .whitespaces)
            for p in ["> ", "› ", "❯ "] where l.hasPrefix(p) && !boxed {
                var words = String(l.dropFirst(p.count)).trimmingCharacters(in: .whitespaces)
                var j = i + 1
                // Wrapped lines of the same message are indented under it, until a blank line or the agent's reply.
                while j < lines.count, lines[j].hasPrefix("  "), !lines[j].trimmingCharacters(in: .whitespaces).isEmpty,
                      !"⏺●•⎿".contains(lines[j].trimmingCharacters(in: .whitespaces).first ?? " ") {
                    words += " " + lines[j].trimmingCharacters(in: .whitespaces); j += 1
                }
                if !words.isEmpty, !TerminalText.isChrome(words) { return String(words.prefix(500)) }
            }
            i -= 1
        }
        return nil
    }
}

/// LAB-2112: every Inbox block (and Decided row) is critical — the agent is blocked until you act — or informational.
public enum InboxUrgency: String, Sendable {
    case critical, informational

    /// Words in a finished turn that mean the agent stopped and needs a call (an error that halted it, a gate or loop
    /// that stopped, a sign-in), not a turn that only keeps the conversation going.
    static let haltWords = ["error:", "failed", "✗", "blocked", "cannot continue", "can't continue", "needs your approval",
                            "need your approval", "sign in", "log in", "permission denied", "gate fail", "stopped:"]

    public static func of(_ d: Decision) -> InboxUrgency {
        if d.isFinished {
            let w = d.why.lowercased()
            return haltWords.contains { w.contains($0) } ? .critical : .informational
        }
        if d.isQuestion { return .informational }   // a question at the end of a turn keeps the conversation going
        return .critical   // a permission prompt or a menu it can't pass: it waits for you
    }

    public static func of(_ b: InboxBlock) -> InboxUrgency {
        switch b.kind {
        case .plan, .loop: return .critical   // a plan waits for approval; a loop item is a stop that needs a call
        case .waiting: return .informational
        default: return b.decision.map(of) ?? .informational
        }
    }

    /// Critical blocks first, each class newest first (the page and keyboard order).
    public static func sorted(_ blocks: [InboxBlock]) -> [InboxBlock] {
        let c = blocks.filter { of($0) == .critical }, i = blocks.filter { of($0) != .critical }
        return c + i
    }
}
