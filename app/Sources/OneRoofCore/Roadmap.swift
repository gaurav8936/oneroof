import Foundation

/// LAB-2101 · a project page's roadmap: tickets grouped by phase (milestone, in the project's order; tickets without
/// one last), with what is done counted. A Completed or Canceled project, or one whose every ticket is closed, opens
/// with its done tickets shown (2.0.0 hid them, so a finished project's page looked empty); the Show done switch is
/// always there and the owner's choice wins, per project.
public enum Roadmap {
    public struct Phase: Identifiable, Equatable, Sendable {
        public var id: String          // milestone id, or "" for "Not in a phase"
        public var name: String
        public var tickets: [LinearIssue]
        public var open: [LinearIssue]
        public var doneCount: Int { tickets.count - open.count }
        /// The tickets to list: every one with Show done on, else the open ones.
        public func shown(showDone: Bool) -> [LinearIssue] { showDone ? tickets : open }
        /// The line under an empty list.
        public func emptyLine(showDone: Bool) -> String? {
            guard shown(showDone: showDone).isEmpty else { return nil }
            return tickets.isEmpty ? "No tickets" : "All done · Show done lists them"
        }
    }

    public static let loosePhase = "Not in a phase"

    /// Done or canceled.
    public static func isClosed(_ i: LinearIssue) -> Bool { i.stateType == "completed" || i.stateType == "canceled" }

    /// Phases in milestone order (empty milestones kept: they are part of the plan), then the tickets with no phase.
    /// One pass over the tickets (a project can hold 1000).
    public static func phases(milestones: [LinearMilestone], tickets: [LinearIssue]) -> [Phase] {
        var byMilestone: [String: [LinearIssue]] = [:]
        var loose: [LinearIssue] = []
        let known = Set(milestones.map(\.id))
        for t in tickets {
            if let m = t.milestoneId, known.contains(m) { byMilestone[m, default: []].append(t) } else { loose.append(t) }
        }
        var out = milestones.map { m -> Phase in
            let list = byMilestone[m.id] ?? []
            return Phase(id: m.id, name: m.name, tickets: list, open: list.filter { !isClosed($0) })
        }
        if !loose.isEmpty { out.append(Phase(id: "", name: loosePhase, tickets: loose, open: loose.filter { !isClosed($0) })) }
        return out
    }

    /// Show done when the owner has not chosen: on for a Completed or Canceled project, and for one whose tickets are
    /// all closed (nothing would be listed otherwise); off while work is open.
    public static func showDoneByDefault(status: ProjectStatus, tickets: [LinearIssue]) -> Bool {
        if status == .completed || status == .canceled { return true }
        return !tickets.isEmpty && tickets.allSatisfy(isClosed)
    }

    /// The switch's state: the owner's choice for this project, else the default.
    public static func showDone(choice: Bool?, status: ProjectStatus, tickets: [LinearIssue]) -> Bool {
        choice ?? showDoneByDefault(status: status, tickets: tickets)
    }
}

/// LAB-2103 · how fresh the Projects data is: "Updated N min ago" while Linear answers, and, when it does not, the error
/// with the time of the last good read (never stale data shown as current).
public enum LinearFreshness {
    /// Projects (list and open page) are read again this often while visible.
    public static let refreshInterval: TimeInterval = 300

    public struct Line: Equatable, Sendable {
        public var text: String
        public var isError: Bool
    }

    /// "just now", "1 min ago", "12 min ago", "2 h ago", "on Oct 30".
    public static func ago(_ d: Date, now: Date) -> String {
        let s = max(0, now.timeIntervalSince(d))
        if s < 60 { return "just now" }
        let m = Int(s / 60)
        if m < 60 { return "\(m) min ago" }
        let h = m / 60
        if h < 24 { return "\(h) h ago" }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "MMM d"
        return "on " + f.string(from: d)
    }

    public static func line(fetchedAt: Date?, error: String?, loading: Bool, now: Date = Date()) -> Line {
        if let error, !error.isEmpty {
            let last = fetchedAt.map { "last read " + ago($0, now: now) } ?? "never read"
            let what = error.contains("not connected") ? "Linear is not connected" : "Couldn't reach Linear"
            return Line(text: "\(what) · \(last)", isError: true)
        }
        if let fetchedAt { return Line(text: (loading ? "Refreshing · updated " : "Updated ") + ago(fetchedAt, now: now), isError: false) }
        return Line(text: loading ? "Reading Linear…" : "Not read from Linear yet", isError: false)
    }
}
