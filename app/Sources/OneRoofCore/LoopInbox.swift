import Foundation

/// LAB-1866 · LAB-1919: what the loops need from you, as loop items (never as sessions, LAB-1933).
///
/// - a loop that stopped at a limit (until you mark it seen, run it again or change it),
/// - a loop whose round asks something (its round's terminal opens from the item),
/// - "Today": what loops staged for your approval (ledger outcomes with status `staged`), oldest first, grouped by
///   loop; the commits one run left on its loop branch are one item (they become one PR when you approve them).
///
/// Pure: the app reads the loop files and the ledger off the main thread and hands them in.
public enum LoopInbox {
    public enum Kind: String, Equatable, Sendable { case failed, asks, staged }

    public struct Item: Identifiable, Equatable, Sendable {
        public var id: String
        public var kind: Kind
        public var loopId: String
        public var loopTitle: String
        /// One line: why it is here.
        public var headline: String
        /// The stop reason, or the staged outcomes' titles.
        public var detail: String
        /// Oldest first ordering (the ledger's ISO time or the loop's last run).
        public var when: Date
        /// For `.staged`: the outcomes this item decides together (one, or every commit of one run).
        public var outcomes: [LoopLedger.Outcome]
        /// For `.asks`: the round's session.
        public var sessionId: String?

        /// The outcome kind of a staged item (commit · pr · issue · report · proposal · file · slack · promotion).
        public init(id: String, kind: Kind, loopId: String, loopTitle: String, headline: String, detail: String, when: Date,
                    outcomes: [LoopLedger.Outcome] = [], sessionId: String? = nil) {
            self.id = id; self.kind = kind; self.loopId = loopId; self.loopTitle = loopTitle; self.headline = headline
            self.detail = detail; self.when = when; self.outcomes = outcomes; self.sessionId = sessionId
        }

        public var outcomeKind: String { outcomes.first?.kind ?? "" }
        public var outcomeIds: [Int] { outcomes.map(\.id) }
    }

    /// Loop items for Needs you: failures and asks of loops, then staged outcomes (Today), each oldest first.
    public static func items(loops: [Loop], staged: [LoopLedger.Outcome]) -> [Item] {
        needs(loops) + today(staged, titles: Dictionary(loops.map { ($0.id, $0.displayTitle) }, uniquingKeysWith: { a, _ in a }))
    }

    /// Loops that stopped at a limit (not seen yet) or whose round asks you something, oldest first.
    public static func needs(_ loops: [Loop]) -> [Item] {
        loops.compactMap { l -> Item? in
            if l.failureUnseen {
                return Item(id: "failed-" + l.id, kind: .failed, loopId: l.id, loopTitle: l.displayTitle,
                            headline: "Loop \(l.displayTitle) stopped at a limit", detail: l.stopReason ?? "Stopped at a limit",
                            when: l.lastRunAt ?? l.createdAt, outcomes: [], sessionId: nil)
            }
            if l.state == .needsYou {
                return Item(id: "asks-" + l.id, kind: .asks, loopId: l.id, loopTitle: l.displayTitle,
                            headline: "Loop \(l.displayTitle): round \(l.run?.active?.n ?? 0) asks something",
                            detail: "The round's agent waits for an answer in its terminal.",
                            when: l.run?.active?.started ?? l.lastRunAt ?? l.createdAt, outcomes: [], sessionId: l.run?.active?.sessionId)
            }
            return nil
        }
        .sorted { $0.when < $1.when }
    }

    /// Today (LAB-1919): staged outcomes, grouped by loop (loops in the order of their oldest item), oldest first in a
    /// loop; the commits of one run are one item.
    public static func today(_ staged: [LoopLedger.Outcome], titles: [String: String] = [:]) -> [Item] {
        let open = staged.filter { $0.status == "staged" }
        var groups: [String: [LoopLedger.Outcome]] = [:]
        var order: [String] = []
        for o in open.sorted(by: { ($0.created, $0.id) < ($1.created, $1.id) }) {
            let key = o.kind == "commit" ? "commit-\(o.loop)-\(o.runId)" : "o-\(o.id)"
            if groups[key] == nil { order.append(key) }
            groups[key, default: []].append(o)
        }
        let items = order.map { key -> Item in
            let os = groups[key]!
            let first = os[0]
            let title = titles[first.loop] ?? first.loop
            let headline: String
            switch first.kind {
            case "commit": headline = "\(os.count) commit\(os.count == 1 ? "" : "s") on the loop branch, ready to become a PR"
            case "pr": headline = "A PR is staged for your approval"
            case "issue": headline = "An issue is staged"
            case "proposal": headline = "A proposal waits for your decision"
            case "report": headline = "A report"
            case "file": headline = "A data or file update"
            case "promotion": headline = "Loop goes live"
            default: headline = "A \(first.kind) waits for you"
            }
            return Item(id: "staged-" + key, kind: .staged, loopId: first.loop, loopTitle: title, headline: headline,
                        detail: os.map(\.title).filter { !$0.isEmpty }.joined(separator: "\n"),
                        when: iso(first.created) ?? .distantPast, outcomes: os, sessionId: nil)
        }
        // Grouped by loop, loops ordered by their oldest item.
        var firstSeen: [String: Int] = [:]
        for (i, it) in items.enumerated() where firstSeen[it.loopId] == nil { firstSeen[it.loopId] = i }
        return items.enumerated().sorted { a, b in
            let la = firstSeen[a.element.loopId]!, lb = firstSeen[b.element.loopId]!
            return la != lb ? la < lb : a.offset < b.offset
        }.map(\.element)
    }

    /// What each staged kind lets you do from its row (LAB-1919: approve, apply, merge, open, dismiss).
    public enum Action: String, CaseIterable, Sendable {
        case approvePR      // commits / a staged PR: gate (tests + judge), then the PR opens (LAB-1867)
        case approve        // a proposal, issue or promotion: recorded as approved
        case apply          // a data or file update: recorded as applied
        case open           // the commit, branch, link or file
        case dismiss        // rejected, with your reason

        public var label: String {
            switch self {
            case .approvePR: return "Approve → open PR"
            case .approve: return "Approve"
            case .apply: return "Apply"
            case .open: return "Open"
            case .dismiss: return "Dismiss"
            }
        }
    }

    public static func actions(for item: Item) -> [Action] {
        switch item.kind {
        case .failed, .asks: return []
        case .staged:
            switch item.outcomeKind {
            case "commit", "pr": return [.approvePR, .open, .dismiss]
            case "file": return [.apply, .open, .dismiss]
            case "report", "slack": return [.open, .dismiss]
            default: return [.approve, .open, .dismiss]
            }
        }
    }

    static func iso(_ s: String) -> Date? {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        if let d = f.date(from: s) { return d }
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.date(from: s)
    }
}

/// LAB-1922: the kinds of loops (the kit's `KINDS`), in plain words: what a loop of that kind is for and what it
/// produces. The samples on the gallery come from the ledger, never from here.
public enum LoopKinds {
    public struct Kind: Identifiable, Equatable, Sendable {
        public var id: String
        public var title: String
        public var purpose: String
        public var produces: String
        public init(id: String, title: String, purpose: String, produces: String) {
            self.id = id; self.title = title; self.purpose = purpose; self.produces = produces
        }
    }

    public static let all: [Kind] = [
        Kind(id: "auditor", title: "Auditor", purpose: "Measures something against a limit or a rule (docs size, links, security, secrets).", produces: "Findings, and a fix PR or an issue for each gap"),
        Kind(id: "reporter", title: "Reporter", purpose: "Sums up what happened over a day, a week or a month.", produces: "A report in the journal, and a message"),
        Kind(id: "sentinel", title: "Sentinel", purpose: "Watches a number (cost, usage, health) and speaks up when it crosses a line.", produces: "An alert when the line is crossed, otherwise a quiet record"),
        Kind(id: "judge", title: "Judge", purpose: "Reads new work (issues, changes) and gives a verdict or a triage.", produces: "A comment or an issue update"),
        Kind(id: "prober", title: "Prober", purpose: "Tries the real thing (a site, a release, a backup) the way a person would.", produces: "Pass or fail with evidence, an issue on a failure"),
        Kind(id: "researcher", title: "Researcher", purpose: "Looks outside the workspace for what changed (releases, papers, tools).", produces: "A short digest with links"),
        Kind(id: "writer", title: "Writer", purpose: "Drafts text from what happened (a week in review, release notes).", produces: "A draft for you to approve"),
        Kind(id: "refresher", title: "Refresher", purpose: "Keeps data or dependencies current (datasets, upstream branches).", produces: "A data update or a PR to approve"),
        Kind(id: "fixer", title: "Fixer", purpose: "Works until a check passes (tests, a bug list), in its own worktree.", produces: "Commits on its loop branch, a PR after your approval"),
        Kind(id: "learner", title: "Learner", purpose: "Turns repeated corrections into proposed rules and hooks.", produces: "Proposals you approve or reject"),
    ]

    public static func kind(_ id: String?) -> Kind? { all.first { $0.id == id } }

    /// Where a loop's output goes, from how it acts.
    public static func destination(act: String?) -> String {
        switch act {
        case "pr": return "Commits stay on the loop branch; a PR opens only after you approve it in Today"
        case "issue": return "One tracker issue per run with what it found"
        default: return "The journal and the outcome ledger only"
        }
    }
}
