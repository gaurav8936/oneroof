import Foundation

// LAB-2339 · Inbox v4.0 shell (IB-4, IB-9, IB-10): one list for sessions and loops, a source filter on top
// (All · Active sessions · Loops), a postmark (who sent it) and a tier (how soon) on every row. The view draws what
// this builds; order, grouping, counts and the default filter live here so they can be tested.

/// The source filter at the top of the list (⌘1 · ⌘2 · ⌘3).
public enum InboxFilter: String, CaseIterable, Sendable {
    case all, sessions, loops

    public var title: String {
        switch self {
        case .all: return "All"
        case .sessions: return "Sessions"   // LAB-2351: "Active" means alive, on the Sessions page only
        case .loops: return "Loops"
        }
    }

    /// Sessions (and plans, which come from a session's planner) vs loop items.
    public func admits(_ b: InboxBlock) -> Bool {
        switch self {
        case .all: return true
        case .sessions: return b.kind != .loop
        case .loops: return b.kind == .loop
        }
    }

    /// IB-10: open on Active sessions when a session item is blocked on you, else All.
    public static func defaultFilter(_ blocks: [InboxBlock], tier: (InboxBlock) -> InboxTier) -> InboxFilter {
        blocks.contains { $0.kind != .loop && tier($0) == .p0 } ? .sessions : .all
    }
}

/// Who sent a row: the stamp on it ("⌁ SESSION · Claude1", "↻ PROPOSAL · docs-drift · ×17").
public enum Postmark: String, Sendable, CaseIterable {
    case session, plan, roundAsks, loopFailed, proposal, commits, fileUpdate, report, missed, finished, waiting

    public var glyph: String {
        switch self {
        case .session: return "⌁"
        case .plan: return "▤"
        case .roundAsks: return "?"
        case .loopFailed: return "✕"
        case .proposal: return "↻"
        case .commits: return "⎇"
        case .fileUpdate: return "◇"
        case .report: return "≡"
        case .missed: return "◌"
        case .finished, .waiting: return "●"
        }
    }

    public var word: String {
        switch self {
        case .session: return "SESSION"
        case .plan: return "PLAN"
        case .roundAsks: return "ROUND ASKS"
        case .loopFailed: return "LOOP FAILED"
        case .proposal: return "PROPOSAL"
        case .commits: return "COMMITS"
        case .fileUpdate: return "FILE UPDATE"
        case .report: return "REPORT"
        case .missed: return "MISSED"
        case .finished: return "FINISHED"
        case .waiting: return "WAITING"
        }
    }

    /// Ink family: the agent's colour, the plan blue, loop violet, stopped red, or the quiet system grey.
    public enum Ink: Sendable { case agent, plan, loop, stopped, system }
    public var ink: Ink {
        switch self {
        case .session: return .agent
        case .plan: return .plan
        case .roundAsks, .loopFailed: return .stopped
        case .finished, .waiting: return .system
        default: return .loop
        }
    }

    /// The postmark of a block; a loop block's staged outcome kind picks the loop postmark.
    public static func of(_ b: InboxBlock, loopItem: LoopInbox.Item? = nil) -> Postmark {
        switch b.kind {
        case .permission, .menu, .question: return .session
        case .finished: return .finished
        case .waiting: return .waiting
        case .plan: return .plan
        case .loop:
            let kind = loopItem?.kind ?? InboxTier.loopKind(ofItemId: b.loopItemId ?? "")
            switch kind {
            case .asks: return .roundAsks
            case .failed: return .loopFailed
            case .missed: return .missed
            case .staged:
                switch loopItem?.outcomeKind ?? "" {
                case "commit", "pr": return .commits
                case "file": return .fileUpdate
                case "report", "slack": return .report
                default: return .proposal
                }
            }
        }
    }

    /// "⌁ SESSION · Claude1", "↻ PROPOSAL · docs-drift · ×17".
    public static func line(_ p: Postmark, sender: String, copies: Int = 1) -> String {
        var s = p.glyph + " " + p.word
        if !sender.isEmpty { s += " · " + sender }
        if copies > 1 { s += " · ×\(copies)" }
        return s
    }
}

/// The counts the filter chips, the rail badge and the status pill all read (IB-9: one count everywhere).
public struct InboxCounts: Equatable, Sendable {
    public var all = 0, sessions = 0, loops = 0
    /// Items blocked on you (P0), from both sources: the red badge.
    public var p0 = 0, p0Sessions = 0, p0Loops = 0
    /// Session items that are blocked on you vs only finished or waiting (the header sub line).
    public var waitingOnYou = 0, finished = 0

    public init() {}

    public func count(_ f: InboxFilter) -> Int { f == .all ? all : f == .sessions ? sessions : loops }
    public func p0(_ f: InboxFilter) -> Int { f == .all ? p0 : f == .sessions ? p0Sessions : p0Loops }
}

/// A section of the list: WAITING ON YOU / NOT WAITING ON YOU for sessions, LOOPS · N on All, or one group per loop.
public struct InboxSection: Equatable, Sendable, Identifiable {
    public enum Kind: Equatable, Sendable { case waitingOnYou, notWaitingOnYou, loops, loop(id: String, title: String) }
    public var kind: Kind
    public var blocks: [InboxBlock]
    public var id: String {
        switch kind {
        case .waitingOnYou: return "waiting"
        case .notWaitingOnYou: return "not-waiting"
        case .loops: return "loops"
        case .loop(let id, _): return "loop-" + id
        }
    }
}

public enum InboxFeed {
    /// Page order: tier first; P0 oldest first (it has waited longest), then newest first.
    public static func ordered(_ blocks: [InboxBlock], tier: (InboxBlock) -> InboxTier) -> [InboxBlock] {
        blocks.sorted { a, b in
            let ta = tier(a), tb = tier(b)
            if ta != tb { return ta < tb }
            if a.at != b.at { return ta == .p0 ? a.at < b.at : a.at > b.at }
            return a.id < b.id
        }
    }

    public static func counts(_ blocks: [InboxBlock], tier: (InboxBlock) -> InboxTier) -> InboxCounts {
        var c = InboxCounts()
        for b in blocks {
            let t = tier(b)
            c.all += 1
            if b.kind == .loop { c.loops += 1; if t == .p0 { c.p0Loops += 1 } }
            else {
                c.sessions += 1
                if t == .p0 { c.p0Sessions += 1 }
                if t == .p2 { c.finished += 1 } else { c.waitingOnYou += 1 }
            }
            if t == .p0 { c.p0 += 1 }
        }
        return c
    }

    /// The list's sections for a filter. Sessions: WAITING ON YOU (P0 + P1) then NOT WAITING ON YOU (P2).
    /// Loops: one group per loop, loops in the order of their most urgent item. All: the session sections, then LOOPS.
    public static func sections(_ blocks: [InboxBlock], filter: InboxFilter, tier: (InboxBlock) -> InboxTier,
                                loopOf: (InboxBlock) -> (id: String, title: String)) -> [InboxSection] {
        let shown = ordered(blocks.filter(filter.admits), tier: tier)
        let sessions = shown.filter { $0.kind != .loop }, loops = shown.filter { $0.kind == .loop }
        var out: [InboxSection] = []
        if filter != .loops {
            let waiting = sessions.filter { tier($0) != .p2 }, rest = sessions.filter { tier($0) == .p2 }
            if !waiting.isEmpty { out.append(InboxSection(kind: .waitingOnYou, blocks: waiting)) }
            if !rest.isEmpty { out.append(InboxSection(kind: .notWaitingOnYou, blocks: rest)) }
        }
        if filter == .all, !loops.isEmpty { out.append(InboxSection(kind: .loops, blocks: loops)) }
        if filter == .loops {
            var order: [String] = [], groups: [String: [InboxBlock]] = [:], titles: [String: String] = [:]
            for b in loops {
                let l = loopOf(b)
                if groups[l.id] == nil { order.append(l.id); titles[l.id] = l.title }
                groups[l.id, default: []].append(b)
            }
            out += order.map { InboxSection(kind: .loop(id: $0, title: titles[$0] ?? $0), blocks: groups[$0] ?? []) }
        }
        return out
    }

    /// The header's sub line: "3 waiting on you · 2 finished" (Active sessions and All), "15 items from 6 loops" (Loops).
    public static func subLine(_ c: InboxCounts, filter: InboxFilter, loopCount: Int) -> String {
        if c.all == 0 { return "Nothing waits for you" }
        if filter == .loops, c.loops == 0 { return "No loop items · \(c.sessions) session\(c.sessions == 1 ? "" : "s") waiting" }
        if filter == .sessions, c.sessions == 0 { return "No session needs you · \(c.loops) loop item\(c.loops == 1 ? "" : "s")" }
        if filter == .loops {
            return "\(c.loops) item\(c.loops == 1 ? "" : "s") from \(loopCount) loop\(loopCount == 1 ? "" : "s")"
                + (c.p0Loops > 0 ? " · \(c.p0Loops) stopped" : "")
        }
        var parts: [String] = []
        if c.waitingOnYou > 0 { parts.append("\(c.waitingOnYou) waiting on you") }
        if c.finished > 0 { parts.append("\(c.finished) finished") }
        if filter == .all, c.loops > 0 { parts.append("\(c.loops) loop item\(c.loops == 1 ? "" : "s")") }
        return parts.isEmpty ? "Nothing waiting on you" : parts.joined(separator: " · ")
    }

    /// The fold line under the Active sessions list: "15 loop items · 2 stopped".
    public static func loopsFoldLine(_ c: InboxCounts) -> String? {
        c.loops == 0 ? nil : "\(c.loops) loop item\(c.loops == 1 ? "" : "s")" + (c.p0Loops > 0 ? " · \(c.p0Loops) stopped" : "")
    }
}

/// LAB-2339 · the one line a list row and the panel strip show for an item.
public enum InboxRowText {
    /// A session ask in a few words: the command ("swift test"), the file, or the question.
    public static func ask(_ d: Decision) -> String {
        if d.isFinished { return "waiting for you" }
        // The pattern history and rules match on ("swift test", "git push") is the command in two words.
        if !d.isQuestion, !d.isMenu, !d.pattern.isEmpty, !d.pattern.contains(":") { return d.pattern }
        if let c = d.command, !c.isEmpty, !d.isQuestion, !d.isMenu { return short(CaptionEngine.mainCommand(c), 40) }
        if let p = d.path, !p.isEmpty { return (p as NSString).lastPathComponent }
        let q = d.headline.replacingOccurrences(of: "\(d.agent.displayName) is asking: ", with: "")
            .replacingOccurrences(of: "\(d.agent.displayName) asked: ", with: "")
        return short(q)
    }

    /// A loop item's title: the outcome's own title when it has one (not a bare id like "p-d0ae"), else the item's
    /// headline without the "Loop <name>: " prefix.
    public static func loopTitle(_ i: LoopInbox.Item) -> String {
        if let t = i.doc?.title, !t.isEmpty { return short(t, 90) }   // LAB-2341 (IB-1): the outcome's own title
        if i.kind == .staged, let t = i.outcomes.first?.title, !t.isEmpty, !isBareId(t) {
            return short(t.replacingOccurrences(of: "[\(i.loopId)] ", with: ""), 90)
        }
        var h = i.headline
        if h.hasPrefix("Loop \(i.loopTitle): ") { h.removeFirst("Loop \(i.loopTitle): ".count) }
        if h.hasPrefix("Loop \(i.loopTitle) ") { h.removeFirst("Loop \(i.loopTitle) ".count) }
        return short(h.prefix(1).uppercased() + h.dropFirst(), 90)
    }

    /// The kind tag in the panel strip for a loop item: "Proposal", "Report", "Commits → PR", "Stopped" …
    public static func kindTag(_ i: LoopInbox.Item) -> String {
        switch i.kind {
        case .failed: return "Stopped"
        case .asks: return "Permission"
        case .missed: return "Missed runs"
        case .staged:
            switch i.outcomeKind {
            case "commit", "pr": return "Commits → PR"
            case "report": return "Report"
            case "slack": return "Note"
            case "file": return "File update"
            case "issue": return "Issue"
            case "promotion": return "Goes live"
            default: return "Proposal"
            }
        }
    }

    /// "p-d0ae": a proposal id, not a title.
    public static func isBareId(_ s: String) -> Bool {
        s.range(of: #"^p-[0-9a-f]{4,}$"#, options: .regularExpression) != nil
    }

    static func short(_ s: String, _ n: Int = 60) -> String {
        let one = s.split(separator: "\n").first.map(String.init) ?? s
        return one.count <= n ? one : String(one.prefix(n - 1)) + "…"
    }
}
