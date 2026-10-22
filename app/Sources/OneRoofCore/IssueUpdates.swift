import Foundation

/// LAB-518: an agent in a session asks One Roof to update one of the session's own Linear issues
/// (`"$ONEROOF_ROOFD_BIN" issue KEY --state "In Progress" --comment "…"`). roofd queues the request in the session's
/// holder; the app applies it with the owner's Linear key and answers, so the agent never needs Linear access itself.
public struct IssueRequest: Equatable, Sendable {
    public var seq: Int
    public var key: String
    public var state: String?
    public var comment: String?

    public init(seq: Int, key: String, state: String? = nil, comment: String? = nil) {
        self.seq = seq; self.key = key; self.state = state; self.comment = comment
    }

    /// One entry of a holder's `issues` list; nil when it is malformed.
    public init?(json j: [String: Any]) {
        guard let seq = j["seq"] as? Int, let key = j["key"] as? String, !key.isEmpty else { return nil }
        let state = (j["state"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        let comment = (j["comment"] as? String).flatMap { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0 }
        self.init(seq: seq, key: key, state: state, comment: comment)
    }

    /// States an agent may set. Done and Canceled stay with the owner (humans stay in the loop).
    public static let agentStates = ["In Progress", "In Review"]

    /// The session issue this request may change, or why it may not: only the session's own issues, only the states
    /// above, and it must change something.
    public func check(against session: Session) -> Result<SessionIssue, IssueRequestError> {
        guard state != nil || comment != nil else { return .failure(.nothingToDo) }
        if let s = state, !Self.agentStates.contains(where: { $0.caseInsensitiveCompare(s) == .orderedSame }) {
            return .failure(.stateNotAllowed(s))
        }
        guard let issue = session.allTickets.first(where: { $0.key.caseInsensitiveCompare(key) == .orderedSame }) else {
            return .failure(.notOnSession(key, session.allTickets.map(\.key)))
        }
        guard issue.id != nil, issue.team != nil else { return .failure(.notLinked(issue.key)) }
        return .success(issue)
    }

    /// The state with the team's own spelling ("in review" → "In Review").
    public var canonicalState: String? {
        state.map { s in Self.agentStates.first { $0.caseInsensitiveCompare(s) == .orderedSame } ?? s }
    }
}

public enum IssueRequestError: Error, Equatable, CustomStringConvertible {
    case nothingToDo
    case stateNotAllowed(String)
    case notOnSession(String, [String])
    case notLinked(String)

    public var description: String {
        switch self {
        case .nothingToDo: return "give --state and/or --comment"
        case .stateNotAllowed(let s):
            return "an agent can set \(IssueRequest.agentStates.joined(separator: " or ")), not \"\(s)\" (Done and Canceled are the owner's)"
        case .notOnSession(let k, let all):
            return "\(k) is not on this session" + (all.isEmpty ? " (it has no issues)" : " (its issues: \(all.joined(separator: ", ")))")
        case .notLinked(let k): return "\(k) has no Linear id on this session, so One Roof cannot update it"
        }
    }
}

/// One issue as the New session sheet picked it (LAB-518).
public struct PickedIssue: Equatable, Sendable {
    public var key: String
    public var title: String
    public var state: String
    public var url: String?
    public init(key: String, title: String, state: String, url: String? = nil) {
        self.key = key; self.title = title; self.state = state; self.url = url
    }
}

extension Intake {
    /// A session on several issues is named with every key: "LAB-1, LAB-2, LAB-3 · title" (LAB-518). The title is
    /// what the owner typed, else "N issues".
    public static func sessionName(keys: [String], title: String) -> String {
        guard keys.count > 1 else { return keys.first.map { sessionName(key: $0, title: title) } ?? title }
        let t = title.trimmingCharacters(in: .whitespaces)
        return keys.joined(separator: ", ") + " · " + (t.isEmpty ? "\(keys.count) issues" : t)
    }

    /// The opening message for a session on several issues (LAB-518): read them all, plan one order that resolves them
    /// best, post the plan on each issue, then work them in that order and keep each issue up to date through One Roof.
    public static func multiTicketOpening(_ issues: [PickedIssue], project: String?, roofd: String = "\"$ONEROOF_ROOFD_BIN\"") -> String {
        let where_ = project.map { " in project \($0)" } ?? ""
        let tag = project.map { " · [\(Workspace.commitTag($0))]" } ?? ""
        var lines = ["This session works on \(issues.count) issues\(where_):"]
        for i in issues {
            lines.append("- \(i.key): \(i.title) (\(i.state))" + (i.url.map { " — \($0)" } ?? ""))
        }
        let first = issues.first?.key ?? "KEY"
        lines += [
            "",
            "1. Read every issue\(project == nil ? "" : " and the project docs") first. Look for shared root causes, overlaps and dependencies.",
            "2. Write ONE plan that resolves all of them in the best order (what goes first and why, what can be done together). Show me the plan, then carry on without waiting unless an issue needs my decision.",
            "3. Post the plan on each issue: \(roofd) issue <KEY> --comment \"<the plan, and where this issue sits in it>\"",
            "4. Then, one issue at a time, in plan order:",
            "   - when you start it: \(roofd) issue <KEY> --state \"In Progress\"",
            "   - commit its work as `<KEY>\(tag) …` (one issue key per commit)",
            "   - when it is done: \(roofd) issue <KEY> --state \"In Review\" --comment \"<what changed, the commit, how to check it>\"",
            "Only these \(issues.count) issues can be updated this way, and only to In Progress or In Review; Done stays with me. For example: \(roofd) issue \(first) --state \"In Progress\"",
        ]
        return lines.joined(separator: "\n")
    }
}

extension Intake {
    /// LAB-528: keep the issue part of an edited opening message in step with the picks. The owner's own words stay; the
    /// generated block (the multi-issue list and steps, or the one-issue "Work on KEY …" line) is replaced with the one
    /// for `issues`, appended when there is none, and removed when nothing is picked. Before, editing the message froze
    /// it: a session picked on 20 issues was told about the first 3.
    public static func syncIssueBlock(_ text: String, issues: [PickedIssue], project: String?) -> String {
        let block = issues.count > 1 ? multiTicketOpening(issues, project: project)
            : issues.first.map { ticketOpening(key: $0.key, title: $0.title, url: $0.url, project: project) } ?? ""
        var lines = text.components(separatedBy: "\n")
        var range: Range<Int>?
        if let a = lines.firstIndex(where: { $0.hasPrefix("This session works on ") }),
           let b = lines[a...].firstIndex(where: { $0.hasPrefix("Only these ") }) {
            range = a..<(b + 1)
        } else if let a = lines.firstIndex(where: { $0.hasPrefix("Work on ") && $0.contains("; commit as `") && !$0.contains(newIssueKey) }) {
            range = a..<(a + 1)
        }
        if let r = range {
            lines.replaceSubrange(r, with: block.isEmpty ? [] : block.components(separatedBy: "\n"))
            // A removed block leaves one blank line between the words around it, not two.
            if block.isEmpty, r.lowerBound > 0, r.lowerBound < lines.count,
               lines[r.lowerBound - 1].trimmingCharacters(in: .whitespaces).isEmpty, lines[r.lowerBound].trimmingCharacters(in: .whitespaces).isEmpty {
                lines.remove(at: r.lowerBound)
            }
            return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard !block.isEmpty else { return text }
        let mine = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return mine.isEmpty ? block : mine + "\n\n" + block
    }
}

extension Intake {
    /// LAB-491: every opening message starts by orienting the agent: run Where Are We (no transcript), anchor in the team
    /// and project, and stay in that team. `body` is what to do next. Left alone when empty or when it already asks for
    /// Where Are We (an owner's own message often does).
    public static func anchored(_ body: String, team: String?, project: String?) -> String {
        let b = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !b.isEmpty, b.range(of: "where are we", options: .caseInsensitive) == nil else { return body }
        let t = team.flatMap { $0.isEmpty ? nil : $0 }
        let scope: String
        switch (project, t) {
        case let (p?, t?): scope = "project \(p) (team \(t))"
        case let (p?, nil): scope = "project \(p)"
        case let (nil, t?): scope = "team \(t)"
        default: scope = "this repo"
        }
        let stay = t == nil ? "" : " and do not switch to another team in this session"
        return "Invoke the \"Where Are We\" skill from agentic engineering (no transcript needed). Anchor yourself in \(scope)\(stay)."
            + " Once anchored, this is what I would like you to do next:\n\n" + body
    }
}

extension Session {
    /// Issues moved to In Progress when the session launches: its one issue. A session on several issues leaves them
    /// as they are; its agent moves each one when it starts on it (LAB-518).
    public var ticketsToStartOnLaunch: [SessionIssue] { allTickets.count > 1 ? [] : allTickets }
}
