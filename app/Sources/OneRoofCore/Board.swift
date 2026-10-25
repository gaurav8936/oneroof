import Foundation

/// One row in the sidebar: a stored session, a live runtime session, or both.
public struct BoardItem: Identifiable, Equatable, Sendable {
    public var id: String
    public var session: Session
    public var status: SessionStatus
    /// Runtime id when live (what a terminal attaches to).
    public var liveAgent: String?
    public var paneId: String?
    public var workspaceId: String?
    /// Account read from the live process (wins over the planned account).
    public var detectedAccount: String?
    /// True when the row came from the runtime only (started outside One Roof).
    public var adopted: Bool
    public var title: String?
    /// The runtime says the agent is ready for input.
    public var ready: Bool = false
    /// A plain terminal in which the owner started an agent (typed `claude`): the row shows that agent while it runs,
    /// but the stored session stays a terminal.
    public var agentInTerminal: Bool = false
    /// Launched a moment ago and not in the runtime's list yet: starting, not exited.
    public var starting: Bool = false
    /// The status the list groups and orders by (LAB-490): the live status once it has held for a moment, so rows do
    /// not jump on every flicker. Nil = the live status.
    public var settledStatus: SessionStatus?
    public var listStatus: SessionStatus { settledStatus ?? status }

    /// The repo seen live this poll (from the agent's hooks or the terminal's folder), resolved to its git root.
    public var workRepo: String?

    public var account: String? { detectedAccount ?? session.account }
    /// The repo this session works in: seen live, else last seen, else the one it was planned for. Nil: it has only
    /// worked at the workspace root so far (not a repo).
    public var repoPath: String? {
        if let r = workRepo ?? session.lastRepo { return r }
        return Workspace.isProjectsRoot(session.repoPath) ? nil : session.repoPath
    }
    public var repoLabel: String { repoPath.map { Workspace.repoLabel(for: $0) } ?? Workspace.rootLabel }
}

/// How the sidebar groups rows — automatic, never drag-and-drop.
public enum Grouping: String, CaseIterable, Identifiable, Sendable {
    case status, repo, workstream, agent, account, domain   // new ones go last: ⌘1…⌘5 keep their meaning
    public var id: String { rawValue }
    public var label: String {
        switch self {
        case .status: return "Status"
        case .repo: return "Repo"
        case .domain: return "Folder"
        case .workstream: return "Project"
        case .agent: return "Agent"
        case .account: return "Account"
        }
    }
}

public struct BoardGroup: Identifiable, Equatable, Sendable {
    public var id: String { title }
    public var title: String
    public var items: [BoardItem]
}

public enum Board {
    /// The repo/folder group for sessions that have only worked at the workspace root: it is not a repo.
    public static let noRepo = "Workspace root · no repo yet"

    /// Merge stored sessions with the runtime's live sessions.
    /// - A stored session whose agent is live takes the runtime's status.
    /// - A stored session that was launched but whose agent is gone is `exited` (unless parked as do-not-use).
    /// - A live agent with no stored session is adopted as its own row (started from a shell or another tool).
    public static func merge(
        stored: [Session],
        snapshot: RuntimeSnapshot,
        accounts: [String: String] = [:],
        now: Date = Date()
    ) -> [BoardItem] {
        // A launch lands in the runtime's list on the next poll; until then (up to 10 s) the row is starting. It showed
        // "This agent has exited" for a moment after every launch (owner 10-20), and could be swept as exited.
        func justLaunched(_ s: Session) -> Bool { s.launchedAt.map { now.timeIntervalSince($0) < 10 } ?? false }
        var byAgent: [RuntimeID: RuntimeSessionState] = [:]
        var byShell: [RuntimeID: RuntimeSessionState] = [:]
        for r in snapshot.sessions { if r.isAgent { byAgent[r.id] = r } else { byShell[r.id] = r } }
        var used = Set<String>()
        var items: [BoardItem] = []

        for s in stored {
            // A plain terminal: live while its shell exists; it has no agent state, so it shows as idle.
            if !s.agent.isAgent {
                // An agent started inside the terminal: the runtime reports it under the terminal's own name.
                if let name = s.runtimeId, let a = byAgent[name], let kind = a.agent, kind.isAgent {
                    used.insert(name)
                    var shown = s
                    shown.agent = kind
                    var item = BoardItem(
                        id: s.id, session: shown, status: s.lifecycle == .doNotUse ? .doNotUse : SessionStatus(a.status),
                        liveAgent: name, paneId: a.pane, workspaceId: a.groupId,
                        detectedAccount: accounts[name], adopted: false, title: a.title, ready: a.ready)
                    item.agentInTerminal = true
                    items.append(item)
                    continue
                }
                let shell = s.runtimeId.flatMap { byShell[$0] ?? byAgent[$0] }
                let starting = shell == nil && s.runtimeId != nil && s.lifecycle != .doNotUse && justLaunched(s)
                let status: SessionStatus = shell != nil ? (s.lifecycle == .doNotUse ? .doNotUse : .idle)
                    : starting ? .idle : (s.runtimeId != nil && s.lifecycle != .doNotUse ? .exited : s.lifecycle)
                var item = BoardItem(
                    id: s.id, session: s, status: status,
                    liveAgent: shell != nil ? s.runtimeId : nil, paneId: shell?.pane, workspaceId: shell?.groupId,
                    detectedAccount: nil, adopted: false, title: nil, ready: shell != nil)
                item.starting = starting
                items.append(item)
                continue
            }
            var status = s.lifecycle
            var starting = false
            var live: RuntimeSessionState?
            if let name = s.runtimeId, let a = byAgent[name] {
                live = a
                used.insert(name)
                status = s.lifecycle == .doNotUse ? .doNotUse : SessionStatus(a.status)
            } else if let name = s.runtimeId, let sh = byShell[name], s.lifecycle != .doNotUse, justLaunched(s) {
                // LAB-299: roofd has the session but the agent is not in the foreground yet (the login shell's setup
                // runs first, ~1.5 s, then the CLI starts). Show its terminal now, marked starting, instead of a
                // placeholder until the agent is seen: the pane was blank for 2-3 s after every launch.
                live = sh
                used.insert(name)
                status = .idle
                starting = true
            } else if s.runtimeId != nil, s.lifecycle != .doNotUse {
                if justLaunched(s) { status = .idle; starting = true } else { status = .exited }
            }
            var item = BoardItem(
                id: s.id, session: s, status: status,
                liveAgent: live?.id, paneId: live?.pane, workspaceId: live?.groupId,
                detectedAccount: live.flatMap { accounts[$0.id] },
                adopted: false, title: live?.title, ready: starting ? false : live?.ready ?? false)
            item.starting = starting
            items.append(item)
        }

        for a in snapshot.agents where !used.contains(a.id) {
            let kind = a.agent ?? .claude
            let cwd = a.cwd ?? Workspace.projectsRoot
            let title = a.title
            // Agents started without a name show their terminal title instead of "term:<id>".
            let display = a.id.hasPrefix(Session.terminalPrefix) || a.id.hasPrefix("pane:")
                ? ((title?.isEmpty == false ? title! : kind.displayName) + " (unnamed)") : a.id
            let s = Session(
                id: Session.adoptedPrefix + a.id, name: display, agent: kind, repoPath: cwd,
                workstream: Workspace.workstream(in: [a.id, title ?? ""].joined(separator: " ")),
                lifecycle: .idle, runtimeId: a.id)
            items.append(BoardItem(
                id: s.id, session: s, status: SessionStatus(a.status),
                liveAgent: a.id, paneId: a.pane, workspaceId: a.groupId,
                detectedAccount: accounts[a.id], adopted: true, title: title, ready: a.ready))
        }
        // Where each live session is working now (its agent's last file or `cd`, or its terminal's folder).
        let live = Dictionary(snapshot.sessions.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        for i in items.indices {
            guard let id = items[i].liveAgent ?? items[i].session.runtimeId, let st = live[id],
                  let where_ = st.workPath ?? st.cwd else { continue }
            items[i].workRepo = Workspace.repoRoot(for: where_)
        }
        return items
    }

    public static func group(_ items: [BoardItem], by g: Grouping) -> [BoardGroup] {
        func key(_ i: BoardItem) -> String {
            switch g {
            case .status: return i.listStatus.groupLabel
            case .repo: return i.repoPath.map { Workspace.repoLabel(for: $0) } ?? Board.noRepo
            case .domain: return i.repoPath.map(Workspace.domainLabel) ?? Board.noRepo
            case .workstream: return i.session.workstream ?? "No project"
            case .agent: return i.session.agent.displayName
            case .account: return i.account ?? i.session.agent.displayName
            }
        }
        // LAB-598: a run terminal sits with its parent agent session (same group, right under it).
        // LAB-726: …while it runs. By status, an exited run terminal goes to Exited like any other row; it stayed in
        // Active under its working parent.
        let byId = Dictionary(items.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        func parent(_ i: BoardItem) -> BoardItem? {
            if g == .status, i.listStatus.groupLabel != byId[i.session.parentSessionId ?? ""]?.listStatus.groupLabel,
               [.exited, .doNotUse].contains(i.listStatus) { return nil }
            return i.session.parentSessionId.flatMap { byId[$0] }
        }
        func groupKey(_ i: BoardItem) -> String { parent(i).map(key) ?? key(i) }
        func isPinned(_ i: BoardItem) -> Bool { parent(i)?.session.pinned ?? i.session.pinned }
        var dict: [String: [BoardItem]] = [:]
        // LAB-490: Working, Ready and Idle rank the same, so a row keeps its place while its agent works and rests;
        // only Needs you comes first. Then by name (stable).
        let rowOrder: (BoardItem, BoardItem) -> Bool = { a, b in
            if a.listStatus.groupRank != b.listStatus.groupRank { return a.listStatus.groupRank < b.listStatus.groupRank }
            return a.session.name.localizedCaseInsensitiveCompare(b.session.name) == .orderedAscending
        }
        // Pinned sessions leave their group and sit together at the top.
        let pinned = items.filter(isPinned)
        dict = [:]
        for i in items where !isPinned(i) { dict[groupKey(i), default: []].append(i) }
        var groups = dict.map { BoardGroup(title: $0.key, items: RunTerminal.nest($0.value.sorted(by: rowOrder))) }
        if g == .status {
            let rank = Dictionary(SessionStatus.allCases.map { ($0.groupLabel, $0.groupRank) }, uniquingKeysWith: { a, _ in a })
            groups.sort { (rank[$0.title] ?? 99) < (rank[$1.title] ?? 99) }
        } else {
            groups.sort { a, b in
                let an = a.title.hasPrefix("No ") || a.title == Board.noRepo, bn = b.title.hasPrefix("No ") || b.title == Board.noRepo
                if an != bn { return bn }
                return a.title.localizedCaseInsensitiveCompare(b.title) == .orderedAscending
            }
        }
        if !pinned.isEmpty { groups.insert(BoardGroup(title: "Pinned", items: RunTerminal.nest(pinned.sorted(by: rowOrder))), at: 0) }
        return groups
    }

    /// Counts for the sidebar header: what needs attention.
    public static func counts(_ items: [BoardItem]) -> (needsYou: Int, done: Int, running: Int, queued: Int) {
        (items.filter { $0.status == .needsYou }.count,
         items.filter { $0.status == .done }.count,
         items.filter { $0.status == .running }.count,
         items.filter { $0.status == .planned || $0.status == .next }.count)
    }
}

/// LAB-490: the sidebar moved rows on every status flicker (Working ↔ Idle every few seconds). A new status takes
/// effect in the list only once it has held: `toNeedsYou` for Needs you (it wants you, so sooner), `other` for the rest.
/// A session seen for the first time shows its status at once.
public struct StatusSmoother: Sendable {
    public var toNeedsYou: TimeInterval
    public var other: TimeInterval
    private var shown: [String: SessionStatus] = [:]
    private var pending: [String: (status: SessionStatus, since: Date)] = [:]

    public init(toNeedsYou: TimeInterval = 2, other: TimeInterval = 6) { self.toNeedsYou = toNeedsYou; self.other = other }

    /// The status to list each row under now; updates its memory.
    public mutating func settle(_ items: [BoardItem], now: Date = Date()) -> [BoardItem] {
        var out = items
        let ids = Set(items.map(\.id))
        shown = shown.filter { ids.contains($0.key) }
        pending = pending.filter { ids.contains($0.key) }
        for k in out.indices {
            let id = out[k].id, live = out[k].status
            guard let was = shown[id] else { shown[id] = live; out[k].settledStatus = live; continue }
            // Same group already (e.g. Working → Idle, both Active): nothing moves, take it at once.
            if was == live || was.groupLabel == live.groupLabel { shown[id] = live; pending[id] = nil; out[k].settledStatus = live; continue }
            if let p = pending[id], p.status == live {
                if now.timeIntervalSince(p.since) >= (live == .needsYou ? toNeedsYou : other) {
                    shown[id] = live; pending[id] = nil
                }
            } else {
                pending[id] = (live, now)
            }
            out[k].settledStatus = shown[id]
        }
        return out
    }
}
