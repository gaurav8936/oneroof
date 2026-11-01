import Foundation

// LAB-2047 · LAB-2048 · the Action log (Inbox › Action log): what you decided, and the always-allow rules One Roof
// notes. Two tabs, Decisions and Rules; only Rules has a remove, worded "Stop noting this rule", with Undo. The rules
// for the copy, the answer kinds and the filters live here; UI/V2/V2ActionLog.swift draws them.

public enum ActionLogTab: String, Codable, CaseIterable, Sendable {
    case decisions, rules
    public var title: String { self == .decisions ? "Decisions" : "Rules" }
}

/// What you answered, as the Answer filter names it.
public enum ActionLogAnswer: String, Codable, CaseIterable, Sendable {
    case allowedOnce, alwaysAllowed, denied, replied, choseOption, answeredInTerminal, setAside
    public var title: String {
        switch self {
        case .allowedOnce: return "Allowed once"; case .alwaysAllowed: return "Always allowed"; case .denied: return "Denied"
        case .replied: return "Replied"; case .choseOption: return "Chose an option"; case .answeredInTerminal: return "Answered in the terminal"
        case .setAside: return "Set aside"
        }
    }

    public static func of(_ d: Decision) -> ActionLogAnswer? {
        guard let a = d.answer else { return nil }
        let reply = d.replyText?.trimmingCharacters(in: .whitespacesAndNewlines)
        if reply == "answered in the terminal" { return .answeredInTerminal }
        if reply == "set aside" { return .setAside }
        if d.chosen != nil || (d.isMenu && a == .reply) { return .choseOption }
        switch a {
        case .allowOnce: return reply.map { _ in .choseOption } ?? .allowedOnce
        case .always: return .alwaysAllowed
        case .deny: return .denied
        case .reply: return .replied
        }
    }

    /// The glyph before the answer: ✓ allowed, ✕ denied, ↩ replied or chose.
    public var glyph: String {
        switch self {
        case .allowedOnce, .alwaysAllowed: return "✓"
        case .denied: return "✕"
        case .replied, .choseOption, .answeredInTerminal: return "↩"
        case .setAside: return "–"
        }
    }
    public var colour: HistoryColour {
        switch self {
        case .allowedOnce, .alwaysAllowed: return .done
        case .denied: return .needs
        case .replied, .choseOption, .answeredInTerminal: return .accent
        case .setAside: return .text2
        }
    }
}

public struct ActionLogRow: Identifiable, Equatable, Sendable {
    public var decision: Decision
    /// The session's name now, or the one stored with the ask.
    public var sessionName: String?
    /// The session is gone (closed or deleted).
    public var closed: Bool
    public var id: UUID { decision.id }
    public init(decision: Decision, sessionName: String?, closed: Bool) { self.decision = decision; self.sessionName = sessionName; self.closed = closed }
    public var shownName: String {
        let n = sessionName ?? "Session"
        return closed ? HistoryFormat.closedName(n) : n
    }
}

public struct ActionLogQuery: Equatable, Codable, Sendable {
    public var text: String = ""
    public var range: HistoryRange = .last7
    public var sessions: Set<String> = []
    public var answers: Set<ActionLogAnswer> = []
    public init(text: String = "", range: HistoryRange = .last7, sessions: Set<String> = [], answers: Set<ActionLogAnswer> = []) {
        self.text = text; self.range = range; self.sessions = sessions; self.answers = answers
    }
    enum CodingKeys: String, CodingKey { case range, sessions, answers }

    public var isFiltered: Bool { !sessions.isEmpty || !answers.isEmpty || !range.isDefault }
    public mutating func clearFilters() { sessions = []; answers = []; range = .last7 }

    /// Session, answer and text (the date range and order are the store's). Search matches the ask, its command, the
    /// answer, the reply and the session's name.
    public func apply(_ rows: [ActionLogRow]) -> [ActionLogRow] {
        let needle = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return rows.filter { r in
            let d = r.decision
            if !sessions.isEmpty, !sessions.contains(d.sessionId) { return false }
            if !answers.isEmpty { guard let a = ActionLogAnswer.of(d), answers.contains(a) else { return false } }
            if !needle.isEmpty {
                let hay = [ScrollFeed.askText(d), d.command ?? "", ScrollFeed.answerText(d) ?? "", d.replyText ?? "", d.chosen ?? "", r.sessionName ?? ""]
                    .joined(separator: "\n").lowercased()
                if !hay.contains(needle) { return false }
            }
            return true
        }
    }

    /// In-memory rows (the self-test's asks, or the app's newest) by the full query, newest answer first.
    public func applyAll(_ rows: [ActionLogRow], now: Date = Date()) -> [ActionLogRow] {
        apply(rows.filter { r in r.decision.answeredAt.map { range.contains($0, now: now) } ?? false })
            .sorted { ($0.decision.answeredAt ?? .distantPast) > ($1.decision.answeredAt ?? .distantPast) }
    }

    public func chips(session: (String) -> String) -> [(label: String, remove: ActionLogChip)] {
        var out: [(String, ActionLogChip)] = []
        for s in sessions.sorted(by: { session($0) < session($1) }) { out.append(("Session: " + session(s), .session(s))) }
        for a in ActionLogAnswer.allCases where answers.contains(a) { out.append(("Answer: " + a.title, .answer(a))) }
        if !range.isDefault { out.append(("Date: " + range.title, .range)) }
        return out
    }
    public mutating func remove(_ c: ActionLogChip) {
        switch c {
        case .session(let s): sessions.remove(s)
        case .answer(let a): answers.remove(a)
        case .range: range = .last7
        }
    }
}

public enum ActionLogChip: Equatable, Sendable { case session(String), answer(ActionLogAnswer), range }

public enum ActionLog {
    public static let pageSize = 200

    /// LAB-2047: the Inbox header's entry point. "Action log" leads; then "555 decided today · 74 rules ›".
    /// Singulars "1 decided today", "1 rule"; zero "nothing decided today". `compact` (narrower than 1100 pt) drops the counts.
    public static func entry(decidedToday n: Int, rules r: Int, compact: Bool = false) -> (lead: String, decided: String, rules: String) {
        if compact { return ("Action log ›", "", "") }
        let decided = n == 0 ? "nothing decided today" : "\(n) decided today"
        return ("Action log", decided, "\(r) rule\(r == 1 ? "" : "s") ›")
    }
    /// The whole entry as one line (for the empty Inbox and tests).
    public static func entryLine(decidedToday n: Int, rules r: Int) -> String {
        let e = entry(decidedToday: n, rules: r)
        return e.lead + " · " + e.decided + " · " + e.rules
    }
    public static let entryTooltip = "What you decided and the always-allow rules One Roof notes (Action log)"
    public static func entryAccessibility(decidedToday n: Int, rules r: Int) -> String {
        "Action log, \(n == 0 ? "nothing" : String(n)) decided today, \(r) rule\(r == 1 ? "" : "s"). Opens the action log."
    }
    public static func rulesAccessibility(rules r: Int) -> String { "\(r) rule\(r == 1 ? "" : "s"). Opens the action log on Rules." }

    public static let subtitle = "What you decided, and the always-allow rules One Roof notes."
    public static let rulesExplainer = "One Roof notes when a new ask in the same repo matches one of these; it never answers for you. Always allow also told the agent not to ask again, and the agent keeps that in its own settings: Stop noting this rule only removes One Roof's note."
    public static let stopRule = "Stop noting this rule"
    public static func stopped(_ r: DecisionRule) -> String { "Stopped noting \(r.pattern) in \(Workspace.repoLabel(for: r.repo))" }
    public static func stopAccessibility(_ r: DecisionRule) -> String { "\(stopRule): \(r.pattern) in \(Workspace.repoLabel(for: r.repo))" }
    public static let notRecorded = "The options weren't recorded for asks before One Roof 2.0.0."
    public static let emptyDecisions = "Nothing decided in this range."
    public static let emptyRules = "No rules yet. Always allow on an ask adds one."

    /// "Decisions · 555" / "Rules · 74".
    public static func tabTitle(_ t: ActionLogTab, count: Int) -> String { t.title + " · \(count)" }
    public static func resultLine(_ n: Int) -> String { "\(n) decision\(n == 1 ? "" : "s")" }

    /// What you chose, in words, with its glyph.
    public static func answerLine(_ d: Decision) -> String {
        if let c = d.chosen, !c.isEmpty { return "Chose: " + c }
        return ScrollFeed.answerText(d) ?? "Waiting"
    }

    /// VoiceOver: "<date time>, <session>, asked <ask>, you <answer>".
    public static func rowAccessibility(_ r: ActionLogRow) -> String {
        let d = r.decision
        return "\(HistoryFormat.stamp(d.answeredAt ?? d.askedAt)), \(r.shownName), asked \(ScrollFeed.askText(d)), you \(answerLine(d).lowercased())"
    }

    /// The opened entry's options in order, the one you chose marked. nil when the ask's options weren't recorded.
    public static func options(_ d: Decision) -> [(label: String, chosen: Bool)]? {
        guard let cs = d.choices, !cs.isEmpty else { return nil }
        let picked = d.chosen ?? d.replyText
        return cs.map { ($0.label, $0.label == picked) }
    }

    /// The previous / next row of the filtered list (↑ / ↓ in an opened entry).
    public static func step(from id: UUID, by delta: Int, in rows: [ActionLogRow]) -> UUID? {
        guard let i = rows.firstIndex(where: { $0.id == id }) else { return nil }
        let j = i + delta
        return rows.indices.contains(j) ? rows[j].id : nil
    }
}
