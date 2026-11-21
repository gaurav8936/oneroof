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
    public enum Kind: String, Equatable, Sendable { case failed, asks, staged, missed }

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
        /// LAB-2341 (IB-1): the outcome's own words (a proposal's title, evidence, change; a report's finding).
        public var doc: LoopDoc? = nil
        /// LAB-2341 (IB-2): when the newest folded copy was filed (`when` is the first).
        public var lastWhen: Date? = nil

        /// The outcome kind of a staged item (commit · pr · issue · report · proposal · file · slack · promotion).
        public init(id: String, kind: Kind, loopId: String, loopTitle: String, headline: String, detail: String, when: Date,
                    outcomes: [LoopLedger.Outcome] = [], sessionId: String? = nil) {
            self.id = id; self.kind = kind; self.loopId = loopId; self.loopTitle = loopTitle; self.headline = headline
            self.detail = detail; self.when = when; self.outcomes = outcomes; self.sessionId = sessionId
        }

        public var outcomeKind: String { outcomes.first?.kind ?? "" }
        /// LAB-2341: how many filings this item stands for (commits of one run count as one filing).
        public var copies: Int { outcomeKind == "commit" ? 1 : max(1, outcomes.count) }
        public var outcomeIds: [Int] { outcomes.map(\.id) }
    }

    /// Loop items for Needs you: failures and asks of loops, then staged outcomes (Today), each oldest first.
    /// LAB-2286 (v7): with the loops' rows, a loop that missed scheduled runs is one item too (after failures and asks).
    public static func items(loops: [Loop], staged: [LoopLedger.Outcome], rows: [LoopRow] = []) -> [Item] {
        needs(loops) + missed(rows) + today(staged, titles: Dictionary(loops.map { ($0.id, $0.displayTitle) }, uniquingKeysWith: { a, _ in a }))
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
        case .failed, .asks, .missed: return []
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

// MARK: - LAB-2341 · Inbox v4.0: titles, evidence, folding, related, expiry (IB-1, IB-2, IB-6, IB-12)

/// What an outcome says in its own words: a proposal file's title, evidence, change and target; a report's finding.
public struct LoopDoc: Equatable, Sendable {
    public var title: String
    public var evidence: [String] = []
    /// The proposal's kind of change ("rule", "tracker", "doc") and what it changes ("~/.claude/skills", "Linear").
    public var change: String? = nil
    public var target: String? = nil
    /// The rule it follows (the proposal's quoted line).
    public var why: String? = nil
    /// The proposal's slug (its file name after the id): the same slug = the same proposal filed again.
    public var slug: String? = nil
    public var path: String? = nil
    public var id: String? = nil

    public init(title: String, evidence: [String] = [], change: String? = nil, target: String? = nil, why: String? = nil,
                slug: String? = nil, path: String? = nil, id: String? = nil) {
        self.title = title; self.evidence = evidence; self.change = change; self.target = target; self.why = why
        self.slug = slug; self.path = path; self.id = id
    }
}

public enum LoopDocs {
    /// A proposal file as the kit writes it (`ae/journal.py`): "# Proposal: <title>", a "**Change:** x · **Target:** y"
    /// line, a quoted rule, "## Evidence" bullets.
    public static func proposal(_ text: String, path: String? = nil) -> LoopDoc {
        var title = "", evidence: [String] = [], change: String?, target: String?, why: String?
        var section = ""
        for raw in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let l = String(raw).trimmingCharacters(in: .whitespaces)
            if l.hasPrefix("# ") && title.isEmpty {
                title = String(l.dropFirst(2)).replacingOccurrences(of: "Proposal: ", with: "")
            } else if l.hasPrefix("## ") {
                section = String(l.dropFirst(3)).lowercased()
            } else if l.hasPrefix("**Loop:**") {
                change = field(l, "Change"); target = field(l, "Target")
            } else if l.hasPrefix("> "), why == nil, section.isEmpty {
                why = String(l.dropFirst(2))
            } else if section == "evidence", l.hasPrefix("- ") || l.hasPrefix("* ") {
                evidence.append(String(l.dropFirst(2)))
            }
        }
        let name = path.map { (($0 as NSString).lastPathComponent as NSString).deletingPathExtension } ?? ""
        let parts = name.split(separator: "_", maxSplits: 2).map(String.init)   // <date>_<id>_<slug>
        return LoopDoc(title: title, evidence: evidence, change: change, target: target, why: why,
                       slug: parts.count == 3 ? parts[2] : nil, path: path, id: parts.count >= 2 ? parts[1] : nil)
    }

    /// "**Loop:** x · **Run:** y · **Change:** rule · **Target:** ~/.claude/skills" → the value after `**key:**`.
    static func field(_ line: String, _ key: String) -> String? {
        guard let r = line.range(of: "**\(key):**") else { return nil }
        let rest = line[r.upperBound...]
        let v = (rest.range(of: " · ").map { rest[..<$0.lowerBound] } ?? rest).trimmingCharacters(in: .whitespaces)
        return v.isEmpty ? nil : v
    }

    /// A report, issue or slack note: the ledger title without the "[loop] " prefix; the finding is the detail's body.
    public static func note(_ o: LoopLedger.Outcome) -> LoopDoc {
        var t = o.title
        if t.hasPrefix("[\(o.loop)] ") { t.removeFirst(o.loop.count + 3) }
        let body = (o.detailValue("body") ?? o.detailValue("error") ?? "").split(separator: "\n").map(String.init)
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        return LoopDoc(title: t, evidence: Array(body.prefix(12)))
    }

    /// The proposal id of an outcome link ("journal:p-6421" → "p-6421").
    public static func proposalId(_ o: LoopLedger.Outcome) -> String? {
        if case .journal(let rel) = o.target, InboxRowText.isBareId(rel) { return rel }
        return InboxRowText.isBareId(o.title) ? o.title : nil
    }

    /// "<date>_<id>_<slug>.md" file names in a proposals folder, by id.
    public static func index(_ names: [String], folder: String) -> [String: String] {
        var out: [String: String] = [:]
        for n in names where n.hasSuffix(".md") {
            let parts = n.split(separator: "_", maxSplits: 2)
            if parts.count >= 2 { out[String(parts[1])] = (folder as NSString).appendingPathComponent(n) }
        }
        return out
    }
}

extension LoopInbox {
    /// IB-1: give each staged item its own words (proposal files by id; reports, issues and slack from the ledger).
    public static func attach(_ items: [Item], proposals: [String: LoopDoc]) -> [Item] {
        items.map { i in
            guard i.kind == .staged, let o = i.outcomes.first else { return i }
            var x = i
            switch o.kind {
            case "proposal", "promotion": if let id = LoopDocs.proposalId(o), let d = proposals[id] { x.doc = d }
            case "report", "slack", "issue": x.doc = LoopDocs.note(o)
            default: break
            }
            return x
        }
    }

    /// IB-2: the same loop filing the same thing again (same proposal slug, else the same title) is one item: its
    /// outcomes are every copy, `when` the first filing, `lastWhen` the last. A decision writes every copy.
    /// Commits keep one item per run.
    public static func fold(_ items: [Item]) -> [Item] {
        var order: [String] = [], merged: [String: Item] = [:]
        for i in items {
            let key: String
            if i.kind == .staged, i.outcomeKind != "commit", i.outcomeKind != "pr" {
                let what = i.doc?.slug ?? i.doc?.title ?? i.outcomes.first?.title ?? i.id
                key = "\(i.loopId)|\(i.outcomeKind)|\(what)"
            } else { key = i.id }
            if var m = merged[key] {
                m.outcomes += i.outcomes
                if i.when < m.when { m.when = i.when }
                let last = max(m.lastWhen ?? m.when, i.lastWhen ?? i.when)
                m.lastWhen = last
                if (i.lastWhen ?? i.when) >= last { m.doc = i.doc ?? m.doc }   // the newest copy's words
                merged[key] = m
            } else { order.append(key); merged[key] = i }
        }
        return order.compactMap { merged[$0] }
    }

    /// IB-12: the open proposal a report is about (same loop, the proposal's target named in the report's title).
    public static func relatedProposal(_ report: Item, in items: [Item]) -> Item? {
        guard ["report", "slack"].contains(report.outcomeKind), let t = report.doc?.title ?? report.outcomes.first?.title else { return nil }
        return items.first { $0.loopId == report.loopId && $0.outcomeKind == "proposal"
            && ($0.doc?.target).map { !$0.isEmpty && t.contains($0) } == true }
    }

    public static func relatedReports(_ proposal: Item, in items: [Item]) -> [Item] {
        items.filter { relatedProposal($0, in: items)?.id == proposal.id }
    }

    /// IB-6 (IBO-1: reports and slack notes after 7 days): staged outcomes that have expired.
    public static let expiryDays = 7
    public static func expired(_ staged: [LoopLedger.Outcome], now: Date = Date()) -> [LoopLedger.Outcome] {
        staged.filter { o in
            ["report", "slack"].contains(o.kind) && o.status == "staged"
                && (iso(o.created).map { now.timeIntervalSince($0) > Double(expiryDays) * 86_400 } ?? false)
        }
    }

    /// LAB-2342 (IB-11): decided outcomes folded like the Inbox folds them: the same loop, kind and proposal slug (else
    /// title), decided in the same minute, is one Decided row ("closed 17 copies"). Newest decision first.
    public struct DecidedGroup: Equatable, Sendable, Identifiable {
        public var outcomes: [LoopLedger.Outcome]
        public var doc: LoopDoc?
        public var id: String { "loopd-\(outcomes.first?.id ?? 0)" }
        public var first: LoopLedger.Outcome { outcomes[0] }
        public var at: Date { first.decidedAt.flatMap(LoopInbox.iso) ?? .distantPast }
        public var title: String {
            if let t = doc?.title, !t.isEmpty { return t }
            return LoopDocs.note(first).title
        }
        /// "Approved", "Dismissed · closed 17 copies", "Seen", "Expired after 7 days".
        public var answer: String {
            let reason = first.detailValue("reason")
            var a: String
            switch first.status {
            case "approved": a = reason == "seen" ? "Seen" : "Approved"
            case "rejected": a = reason == "stop re-filing" ? "Dismissed and stopped re-filing" : "Dismissed" + (reason.map { ": " + $0 } ?? "")
            case "applied": a = "Applied"
            case "merged": a = "Merged"
            case "expired": a = "Expired after \(LoopInbox.expiryDays) days"
            default: a = first.status.capitalized
            }
            if outcomes.count > 1 { a += " · closed \(outcomes.count) copies" }
            return a
        }
    }

    public static func foldDecided(_ os: [LoopLedger.Outcome], proposals: [String: LoopDoc] = [:]) -> [DecidedGroup] {
        var order: [String] = [], groups: [String: DecidedGroup] = [:]
        for o in os {
            let doc = LoopDocs.proposalId(o).flatMap { proposals[$0] } ?? (["report", "slack", "issue"].contains(o.kind) ? LoopDocs.note(o) : nil)
            let what = doc?.slug ?? doc?.title ?? o.title
            let key = "\(o.loop)|\(o.kind)|\(o.status)|\(what)|\((o.decidedAt ?? "").prefix(16))"
            if groups[key] == nil { order.append(key); groups[key] = DecidedGroup(outcomes: [o], doc: doc) }
            else { groups[key]!.outcomes.append(o) }
        }
        return order.compactMap { groups[$0] }
    }

    /// "Dismiss and stop re-filing": the keys of muted proposals ("loop|slug"); a muted item stays out of the Inbox.
    public static func muteKey(_ i: Item) -> String? { i.doc?.slug.map { "\(i.loopId)|\($0)" } }
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
