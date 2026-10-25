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

/// LAB-638: what a new session's opening message is built from: the team, project and issues picked in the sheet,
/// what should happen (the owner's words) and done when.
public struct OpeningFocus: Equatable, Sendable {
    public var team: String?
    public var teamName: String?
    public var project: String?
    public var projectTitle: String?
    public var issues: [PickedIssue]
    /// A Ticket or Bug the sheet will create: its title (the key is filled in once Linear assigns it).
    public var newIssueTitle: String?
    public var ask: String
    public var doneWhen: String

    public init(team: String? = nil, teamName: String? = nil, project: String? = nil, projectTitle: String? = nil,
                issues: [PickedIssue] = [], newIssueTitle: String? = nil, ask: String = "", doneWhen: String = "") {
        func clean(_ s: String?) -> String? { s.flatMap { let t = $0.trimmingCharacters(in: .whitespacesAndNewlines); return t.isEmpty ? nil : t } }
        self.team = clean(team); self.teamName = clean(teamName); self.project = clean(project); self.projectTitle = clean(projectTitle)
        self.issues = issues; self.newIssueTitle = newIssueTitle.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        self.ask = ask.trimmingCharacters(in: .whitespacesAndNewlines); self.doneWhen = doneWhen.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

extension Intake {
    static let focusHeading = "Focus of this session:"
    static let focusEnd = "Stay on this focus"

    /// The focus lines: team, project, issues, and the stay-in-scope rule. Empty when nothing is picked.
    static func focusBlock(_ f: OpeningFocus) -> [String] {
        var lines: [String] = []
        if let t = f.team { lines.append("- Team: " + t + (f.teamName.map { " · " + $0 } ?? "")) }
        if let p = f.project { lines.append("- Project: " + p + (f.projectTitle.map { " · " + $0 } ?? "")) }
        if f.issues.count == 1, let i = f.issues.first { lines.append("- Issue: \(i.key) · \(i.title)") }
        else if f.issues.count > 1 {
            lines.append("- Issues (\(f.issues.count), listed with their titles below): " + f.issues.map(\.key).joined(separator: ", "))
        } else if let n = f.newIssueTitle { lines.append("- Issue: a new one, \"\(n)\" (its key is added when Linear creates it)") }
        guard !lines.isEmpty else { return [] }
        let scope = [f.team.map { _ in "team" }, f.project.map { _ in "project" }, (f.issues.isEmpty && f.newIssueTitle == nil) ? nil : "these issues"]
            .compactMap { $0 }.joined(separator: ", ")
        return [focusHeading] + lines + ["\(focusEnd) (\(scope)) for the whole session\(f.team == nil ? "" : "; do not switch to another team").",]
    }

    /// LAB-638: the opening message of a new session, always built from what is picked now. It runs Where Are We
    /// (no transcript), states the focus (team, project, the issues by key and title), then what should happen in the
    /// owner's words, done when, and the issue steps (one issue: read it and the commit format; several: one plan for
    /// all of them). Before, the owner's "What should happen" was dropped as soon as an issue was picked, and the
    /// focus was one generic "Anchor yourself in project X (team Y)" line. Empty when there is nothing to say.
    public static func sessionOpening(_ f: OpeningFocus) -> String {
        let focus = focusBlock(f)
        let issueBlock: String
        if f.issues.count > 1 { issueBlock = multiTicketOpening(f.issues, project: f.project) }
        else if let i = f.issues.first { issueBlock = ticketOpening(key: i.key, title: i.title, url: i.url, project: f.project) }
        else if let n = f.newIssueTitle { issueBlock = ticketOpening(key: newIssueKey, title: n, project: f.project) }
        else { issueBlock = "" }
        var ask = f.ask
        if ask.isEmpty, !issueBlock.isEmpty { ask = f.issues.count > 1 ? "Resolve these \(f.issues.count) issues." : "Resolve this issue." }
        guard !ask.isEmpty || !focus.isEmpty else { return "" }
        var parts = ["Invoke the \"Where Are We\" skill from agentic engineering (no transcript needed)."]
        if !focus.isEmpty { parts.append(focus.joined(separator: "\n")) }
        if !ask.isEmpty { parts.append("What I would like you to do:\n" + ask) }
        if !f.doneWhen.isEmpty {
            parts.append("Done when: \(f.doneWhen)\nWhen that is true, tell me and stop there; I review the work and decide when the session ends.")
        }
        if !issueBlock.isEmpty { parts.append(issueBlock) }
        return parts.joined(separator: "\n\n")
    }

    /// An opening message the owner edited: their words stay; the focus block and the issue block follow the picks.
    public static func syncOpening(_ text: String, focus f: OpeningFocus) -> String {
        var out = syncIssueBlock(text, issues: f.issues, project: f.project)
        var lines = out.components(separatedBy: "\n")
        if let a = lines.firstIndex(of: focusHeading), let b = lines[a...].firstIndex(where: { $0.hasPrefix(focusEnd) }) {
            let block = focusBlock(f)
            lines.replaceSubrange(a...b, with: block)
            out = lines.joined(separator: "\n").replacingOccurrences(of: "\n\n\n", with: "\n\n")
        }
        return out
    }
}

extension Session {
    /// Issues moved to In Progress when the session launches: its one issue. A session on several issues leaves them
    /// as they are; its agent moves each one when it starts on it (LAB-518).
    public var ticketsToStartOnLaunch: [SessionIssue] { allTickets.count > 1 ? [] : allTickets }
}
