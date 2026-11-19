import Foundation

// LAB-2313 · Resources, summary first (owner option A, 2026-11-19): one page with a row of six tiles on top (Sessions,
// One Roof, This Mac, Swap, roofd, Needs action), then today's full detail, every card folding. The pure parts live
// here: what the Sessions and Needs action tiles count, the swap line, which cards start open, and the names of
// roofd sessions no One Roof row owns (from what roofd already says: agent, folder, start time).

extension MacMemory {
    /// LAB-2313: the swap line Home's MAC story warns above ("The Mac is using a lot of swap") and the Swap tile turns
    /// amber above. One constant, so the two never disagree.
    public static let heavySwapBytes: UInt64 = 4 << 30
    public var heavySwap: Bool { swapUsed > Self.heavySwapBytes }
}

/// LAB-2313 · what the Sessions and Needs action tiles say, from the page's window groups.
public struct ResourcesSummary: Equatable, Sendable {
    public struct StateCount: Equatable, Sendable {
        public var status: SessionStatus
        public var count: Int
        public init(status: SessionStatus, count: Int) { self.status = status; self.count = count }
    }
    public struct WindowCount: Equatable, Sendable {
        public var id: String
        public var name: String
        public var count: Int
        public init(id: String, name: String, count: Int) { self.id = id; self.name = name; self.count = count }
    }
    /// The session closest to its holder limit, once one is at roofd's warning line or past it.
    public struct Nearest: Equatable, Sendable {
        public var name: String
        public var holder: UInt64
        public var limit: UInt64
        public var level: Headroom.Level
        public init(name: String, holder: UInt64, limit: UInt64, level: Headroom.Level) {
            self.name = name; self.holder = holder; self.limit = limit; self.level = level
        }
    }

    public var running: Int
    /// One Roof windows with running sessions (Other is not a window).
    public var windows: Int
    /// One Roof rows by status, in `stateOrder`, only the states that have any.
    public var states: [StateCount]
    /// Running roofd sessions that no One Roof row owns (the amber pill).
    public var notOneRoofRow: Int
    /// Every card with its count, in page order ("Evals 2 · Other 3").
    public var byWindow: [WindowCount]
    /// The Other card: sessions no window owns (closed windows and rows that are not One Roof rows).
    public var otherCount: Int
    public var otherMemory: UInt64
    public var nearest: Nearest?
    /// Sessions whose holder is at roofd's warning line or past it.
    public var atWarn: Int

    /// The order of the state pills: the status palette's names as the sidebar filters use them.
    public static let stateOrder: [SessionStatus] = [.running, .done, .idle, .needsYou, .exited]

    /// The Needs action tile shows only when something needs action: sessions no window owns, or a holder at its
    /// warning line or past it. Otherwise the slot is not drawn and the row reflows.
    public var needsAction: Bool { otherCount > 0 || nearest != nil }

    /// "Evals 2 · Other 3".
    public var windowsLine: String { byWindow.map { "\($0.name) \($0.count)" }.joined(separator: " · ") }

    /// - Parameter status: a row's One Roof status; nil = not a One Roof row (a roofd session no row owns).
    public static func make(_ groups: [ResourceWindowGroup], status: (ResourceRow) -> SessionStatus?) -> ResourcesSummary {
        let rows = groups.flatMap(\.rows)
        var counts: [SessionStatus: Int] = [:]
        var orphans = 0
        for r in rows {
            if let s = status(r) { counts[s, default: 0] += 1 } else { orphans += 1 }
        }
        let order = stateOrder + SessionStatus.allCases.filter { !stateOrder.contains($0) }
        let states = order.compactMap { s in counts[s].map { StateCount(status: s, count: $0) } }
        let other = groups.first { $0.id == ResourceBoard.otherId }
        let warned = rows.filter { $0.usage.holderPid != nil && $0.usage.level >= .warn }
        let near = warned.max { a, b in
                let fa = a.usage.headroom.fraction(a.usage.holderFootprint), fb = b.usage.headroom.fraction(b.usage.holderFootprint)
                return fa != fb ? fa < fb : a.name > b.name
            }
        return ResourcesSummary(
            running: rows.count,
            windows: groups.filter { $0.id != ResourceBoard.otherId }.count,
            states: states, notOneRoofRow: orphans,
            byWindow: groups.map { WindowCount(id: $0.id, name: $0.name, count: $0.rows.count) },
            otherCount: other?.rows.count ?? 0, otherMemory: other?.footprint ?? 0,
            nearest: near.map { Nearest(name: $0.name, holder: $0.usage.holderFootprint, limit: $0.usage.headroom.limitBytes, level: $0.usage.level) },
            atWarn: warned.count)
    }
}

/// LAB-2313 · which cards start open, and the keys each card's open / folded choice is remembered under (in
/// `Prefs.viewState`, next to `resources.browserTabs.*`).
public enum ResourcesFold {
    public enum Card: Equatable, Hashable, Sendable {
        case mac, own, window(String), other
    }

    public static func key(_ c: Card) -> String {
        switch c {
        case .mac: return "resources.fold.mac"
        case .own: return "resources.fold.own"
        case .other: return "resources.fold.other"
        case .window(let id): return "resources.fold.window." + id
        }
    }
    /// The Other rows seen when the owner last folded Other (a new one opens it again).
    public static let otherSeenKey = "resources.fold.other.seen"

    /// The proposal (owner, 2026-11-19): this window's session card and Other start open; This Mac by app, One Roof
    /// itself and other windows' cards start folded.
    public static func startsOpen(_ c: Card, thisWindow: String?) -> Bool {
        switch c {
        case .mac, .own: return false
        case .other: return true
        case .window(let id): return id == thisWindow
        }
    }

    /// The owner's remembered choice, else the default.
    public static func isOpen(_ c: Card, stored: Bool?, thisWindow: String?) -> Bool { stored ?? startsOpen(c, thisWindow: thisWindow) }

    /// Other opens by itself whenever it has rows: folded by the owner, it opens again when a session joins it that
    /// was not there when it was folded.
    public static func reopensOther(seen: Set<String>, now: Set<String>) -> Bool { !now.subtracting(seen).isEmpty }

    /// VoiceOver for a card's header: "{card}, folded, {summary}" / "{card}, opened, {summary}".
    public static func label(_ card: String, open: Bool, summary: String) -> String {
        "\(card), \(open ? "opened" : "folded")" + (summary.isEmpty ? "" : ", " + summary)
    }
}

/// LAB-2313 · a roofd session that no One Roof row owns, named from what roofd says about it instead of a bare id:
/// "roof-15e2b579-2 · Claude in ~/Projects", with its age and the row that replaced it on the line below.
/// Nothing roofd does not report is guessed; an unknown part is left out.
public enum ResourceOrphanName {
    /// `~/Projects` for a folder under the home folder.
    public static func folder(_ path: String, home: String = NSHomeDirectory()) -> String {
        let h = home.hasSuffix("/") ? String(home.dropLast()) : home
        guard !h.isEmpty else { return path }
        if path == h { return "~" }
        if path.hasPrefix(h + "/") { return "~" + path.dropFirst(h.count) }
        return path
    }

    /// What runs in it: the agent roofd detected, "shell" when roofd says it is no agent, nil when roofd says nothing.
    public static func what(isAgent: Bool?, agentName: String?) -> String? {
        guard let isAgent else { return nil }
        guard isAgent else { return "shell" }
        if let k = AgentKind(detectedName: agentName), k != .shell { return k.displayName }
        if let n = agentName, !n.isEmpty { return n.prefix(1).uppercased() + n.dropFirst() }
        return "agent"
    }

    /// "<runtime id> · <agent or shell> in <folder>"; falls back to roofd's title, else the bare id.
    public static func name(runtimeId: String, isAgent: Bool?, agentName: String?, cwd: String?, title: String?,
                            home: String = NSHomeDirectory()) -> String {
        let w = what(isAgent: isAgent, agentName: agentName)
        let f = cwd.flatMap { $0.isEmpty ? nil : folder($0, home: home) }
        switch (w, f) {
        case let (w?, f?): return "\(runtimeId) · \(w) in \(f)"
        case let (w?, nil): return "\(runtimeId) · \(w)"
        case let (nil, f?): return "\(runtimeId) · \(f)"
        default:
            if let title, !title.isEmpty, title != runtimeId { return "\(runtimeId) · \(title)" }
            return runtimeId
        }
    }

    /// `roof-ab12cd34-3` → 3; a name with no suffix is the first (1).
    static func generation(_ id: String) -> Int {
        let base = OrphanSessions.baseName(id)
        guard base != id else { return 1 }
        return Int(id.dropFirst(base.count + 1)) ?? 1
    }

    /// "relaunched as -2 (Evals)": a One Roof row runs a later session of the same launch name (a relaunch took
    /// `-2` and repointed the row, LAB-2311). nil when no row does.
    /// - Parameters:
    ///   - rows: the page's rows.
    ///   - owned: whether a row is a One Roof row (default: its id is a board row's, not "runtime:…").
    ///   - windowName: the card a row sits in, by its window id (nil = Other).
    public static func replacement(of runtimeId: String, rows: [ResourceRow], owned: (ResourceRow) -> Bool = { !$0.id.hasPrefix("runtime:") },
                                   windowName: (String?) -> String?) -> String? {
        let base = OrphanSessions.baseName(runtimeId)
        let gen = generation(runtimeId)
        let later = rows.filter { r in
            owned(r) && r.usage.runtimeId != runtimeId
                && OrphanSessions.baseName(r.usage.runtimeId) == base && generation(r.usage.runtimeId) > gen
        }
        guard let r = later.max(by: { generation($0.usage.runtimeId) < generation($1.usage.runtimeId) }) else { return nil }
        let rid = r.usage.runtimeId
        let short = rid.hasPrefix(base + "-") ? String(rid.dropFirst(base.count)) : rid
        return "relaunched as \(short)" + (windowName(r.windowId).map { " (\($0))" } ?? "")
    }

    /// The parts after "session total, N processes" on an orphan's sub-line: "not a One Roof row", the row that
    /// replaced it, its age (from its holder's start).
    public static func subline(started: Date?, now: Date = Date(), replacedBy: String?) -> [String] {
        var out = ["not a One Roof row"]
        if let replacedBy { out.append(replacedBy) }
        if let started { out.append("up " + ResourceFormat.uptime(now.timeIntervalSince(started))) }
        return out
    }
}
