import Foundation

/// LAB-1831 · one continuous feed of every session's important moments (its finished steps, findings, choices,
/// errors, the asks it put to you and what you answered, a finished turn), never its code, diffs or tool output.
/// LAB-2044: the History place shows it newest first (History.swift); the Inbox keeps what you decided while the
/// session is alive. Manual sessions only (LAB-1933: loop rounds live in Loops).
public struct ScrollEntry: Identifiable, Equatable, Sendable {
    public enum Kind: String, Codable, CaseIterable, Sendable {
        case step, finding, choice, subagents, done, rotated, error   // what the agent did (feed + chapters)
        case ask, question, finished                                   // what it asked you (decisions)
        // LAB-2046: handovers (rotated above is "Handed off").
        case sessionStarted, sessionClosed, handoffWritten, releaseStarted, releaseFinished, releaseFailed
    }
    public var id: String
    public var at: Date
    public var sessionId: String
    public var kind: Kind
    public var text: String
    /// Decisions: the ask behind the entry, whether it still waits, and what you answered (nil while open).
    public var decisionId: UUID?
    public var open: Bool
    public var answer: String?
    public var answeredAt: Date?

    public var needsInput: Bool { open && [.ask, .question, .finished].contains(kind) }
}

public enum ScrollFeed {
    /// The default length of the feed (the newest entries).
    public static let limit = 400

    /// What you answered, in words ("Allowed once", "Replied: …").
    public static func answerText(_ d: Decision) -> String? {
        guard let a = d.answer else { return nil }
        let reply = d.replyText?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let typed = TerminalReply.typed(reply) { return "Replied in its terminal: " + typed }   // LAB-2106: your words
        if reply == TerminalReply.marker { return "Answered in its terminal" }   // the engine's note, not your words
        switch a {
        case .allowOnce: return reply.map { "Chose: " + $0 } ?? "Allowed once"
        case .always: return "Always allowed"
        case .deny: return reply.map { "Denied: " + $0 } ?? "Denied"
        case .reply: return "Replied: " + (reply ?? "")
        }
    }

    /// The words of an ask, as Needs you shows it.
    public static func askText(_ d: Decision) -> String {
        if let c = d.command { return "Run " + c }
        if d.isFinished && TerminalText.isChrome(d.why) { return d.title }   // QA M4 · LAB-2108: never the CLI's furniture
        if d.isQuestion || d.isFinished { return d.why }
        if d.pattern.hasPrefix("ask:") { return "\(d.agent.displayName) is asking: " + d.pattern.dropFirst(4) }
        return d.title
    }

    static func kind(_ k: FeedKind) -> ScrollEntry.Kind {
        switch k {
        case .stepDone: return .step
        case .finding: return .finding
        case .choice: return .choice
        case .subagents: return .subagents
        case .done: return .done
        case .rotated: return .rotated
        case .error: return .error
        }
    }

    /// The feed across sessions, oldest first (or newest first: `order`, LAB-2044). `item` resolves a session id (nil =
    /// gone: its entries go too; History reads the store instead, which keeps them). A session with step chapters shows
    /// those (title and summary) instead of the feed's shorter "step done" lines. `limit` keeps the newest entries.
    public static func entries(feed: [FeedEvent], chapters: [String: [Chapter]], decisions: [Decision],
                               item: (String) -> BoardItem?, limit: Int = limit, order: HistoryOrder = .oldestFirst) -> [ScrollEntry] {
        var known: [String: Bool] = [:]
        func shown(_ id: String) -> Bool {
            if let k = known[id] { return k }
            let ok = item(id).map { !SessionScope.isLoop($0.session) } ?? false
            known[id] = ok
            return ok
        }
        var out: [ScrollEntry] = []
        for e in feed where shown(e.sessionId) {
            if e.kind == .stepDone, chapters[e.sessionId]?.isEmpty == false { continue }
            out.append(ScrollEntry(id: "feed-" + e.id.uuidString, at: e.at, sessionId: e.sessionId, kind: kind(e.kind),
                                   text: e.text, open: false))
        }
        for (sid, chs) in chapters where shown(sid) {
            for c in chs {
                guard let ended = c.ended else { continue }   // a step still running is not a moment yet
                let summary = c.summary.trimmingCharacters(in: .whitespacesAndNewlines)
                out.append(ScrollEntry(id: "step-\(sid)-\(c.index)", at: ended, sessionId: sid, kind: .step,
                                       text: summary.isEmpty ? c.title : c.title + " · " + summary, open: false))
            }
        }
        for d in decisions where shown(d.sessionId) {
            let k: ScrollEntry.Kind = d.isFinished ? .finished : d.isQuestion || d.isMenu ? .question : .ask
            out.append(ScrollEntry(id: "ask-" + d.id.uuidString, at: d.askedAt, sessionId: d.sessionId, kind: k,
                                   text: askText(d), decisionId: d.id, open: d.isOpen, answer: answerText(d), answeredAt: d.answeredAt))
        }
        out.sort { $0.at == $1.at ? $0.id < $1.id : $0.at < $1.at }
        let kept = Array(out.suffix(limit))
        return order == .newestFirst ? kept.reversed() : kept
    }

    /// Needs you's history (LAB-1831 part 1): the asks you answered whose session is still alive (running, or its
    /// terminal still open), newest answer first. Loop rounds never (LAB-1933).
    public static func decided(_ decisions: [Decision], item: (String) -> BoardItem?) -> [Decision] {
        decisions.filter { d in
            guard !d.isOpen, let i = item(d.sessionId), !SessionScope.isLoop(i.session) else { return false }
            return i.liveAgent != nil || i.endedShell != nil
        }
        .sorted { ($0.answeredAt ?? $0.askedAt) > ($1.answeredAt ?? $1.askedAt) }
    }
}
