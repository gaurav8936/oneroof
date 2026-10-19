import Foundation

/// One row in the sidebar: a stored session, a live herdr agent, or both.
public struct BoardItem: Identifiable, Equatable, Sendable {
    public var id: String
    public var session: Session
    public var status: SessionStatus
    /// herdr agent name when live (what a terminal attaches to).
    public var liveAgent: String?
    public var paneId: String?
    public var workspaceId: String?
    /// Account read from the live process (wins over the planned account).
    public var detectedAccount: String?
    /// True when the row came from herdr only (started outside One Roof).
    public var adopted: Bool
    public var title: String?
    /// herdr says the agent is ready for input.
    public var ready: Bool = false
    /// A plain terminal in which the owner started an agent (typed `claude`): the row shows that agent while it runs,
    /// but the stored session stays a terminal.
    public var agentInTerminal: Bool = false

    public var account: String? { detectedAccount ?? session.account }
    public var repoLabel: String { Workspace.repoLabel(for: session.repoPath) }
}

/// How the sidebar groups rows — automatic, never drag-and-drop.
public enum Grouping: String, CaseIterable, Identifiable, Sendable {
    case status, repo, workstream, agent, account
    public var id: String { rawValue }
    public var label: String {
        switch self {
        case .status: return "Status"
        case .repo: return "Repo"
        case .workstream: return "Workstream"
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
    /// Merge stored sessions with herdr's live agents.
    /// - A stored session whose herdr agent is live takes herdr's status.
    /// - A stored session that was launched but whose agent is gone is `exited` (unless parked as do-not-use).
    /// - A live agent with no stored session is adopted as its own row (started from a shell or another tool).
    public static func merge(
        stored: [Session],
        snapshot: HerdrSnapshot,
        accounts: [String: String] = [:]
    ) -> [BoardItem] {
        var byAgent: [String: HerdrAgent] = [:]
        for a in snapshot.agents { byAgent[a.name] = a }
        var byTerminal: [String: HerdrPane] = [:]
        for p in snapshot.panes { if let t = p.terminal_id { byTerminal[Session.terminalPrefix + t] = p } }
        var used = Set<String>()
        var items: [BoardItem] = []

        for s in stored {
            // A plain terminal: live while its herdr pane exists; it has no agent state, so it shows as idle.
            if !s.agent.isAgent {
                // An agent started inside the terminal: herdr reports it under the terminal's own name.
                if let name = s.herdrAgent, let a = byAgent[name], let kind = AgentKind(herdrName: a.agent), kind.isAgent {
                    used.insert(name)
                    var shown = s
                    shown.agent = kind
                    var item = BoardItem(
                        id: s.id, session: shown, status: s.lifecycle == .doNotUse ? .doNotUse : SessionStatus.fromHerdr(a.agent_status),
                        liveAgent: name, paneId: a.pane_id, workspaceId: a.workspace_id,
                        detectedAccount: accounts[name], adopted: false, title: a.terminal_title_stripped, ready: a.interactive_ready ?? false)
                    item.agentInTerminal = true
                    items.append(item)
                    continue
                }
                let pane = s.herdrAgent.flatMap { byTerminal[$0] }
                let status: SessionStatus = pane != nil ? (s.lifecycle == .doNotUse ? .doNotUse : .idle)
                    : (s.herdrAgent != nil && s.lifecycle != .doNotUse ? .exited : s.lifecycle)
                items.append(BoardItem(
                    id: s.id, session: s, status: status,
                    liveAgent: pane != nil ? s.herdrAgent : nil, paneId: pane?.pane_id, workspaceId: pane?.workspace_id,
                    detectedAccount: nil, adopted: false, title: nil, ready: pane != nil))
                continue
            }
            var status = s.lifecycle
            var live: HerdrAgent?
            if let name = s.herdrAgent, let a = byAgent[name] {
                live = a
                used.insert(name)
                status = s.lifecycle == .doNotUse ? .doNotUse : SessionStatus.fromHerdr(a.agent_status)
            } else if s.herdrAgent != nil, s.lifecycle != .doNotUse {
                status = .exited
            }
            items.append(BoardItem(
                id: s.id, session: s, status: status,
                liveAgent: live?.name, paneId: live?.pane_id, workspaceId: live?.workspace_id,
                detectedAccount: live.flatMap { accounts[$0.name] },
                adopted: false, title: live?.terminal_title_stripped, ready: live?.interactive_ready ?? false))
        }

        for a in snapshot.agents where !used.contains(a.name) {
            let kind = AgentKind(herdrName: a.agent) ?? .claude
            let cwd = a.foreground_cwd ?? a.cwd ?? Workspace.projectsRoot
            let title = a.terminal_title_stripped
            // Agents started without a name show their terminal title instead of "term:<id>".
            let display = a.name.hasPrefix(Session.terminalPrefix) || a.name.hasPrefix("pane:")
                ? ((title?.isEmpty == false ? title! : kind.displayName) + " (unnamed)") : a.name
            let s = Session(
                id: "herdr:" + a.name, name: display, agent: kind, repoPath: cwd,
                workstream: Workspace.workstream(in: [a.name, title ?? ""].joined(separator: " ")),
                lifecycle: .idle, herdrAgent: a.name)
            items.append(BoardItem(
                id: s.id, session: s, status: SessionStatus.fromHerdr(a.agent_status),
                liveAgent: a.name, paneId: a.pane_id, workspaceId: a.workspace_id,
                detectedAccount: accounts[a.name], adopted: true, title: title, ready: a.interactive_ready ?? false))
        }
        return items
    }

    public static func group(_ items: [BoardItem], by g: Grouping) -> [BoardGroup] {
        func key(_ i: BoardItem) -> String {
            switch g {
            case .status: return i.status.label
            case .repo: return i.repoLabel
            case .workstream: return i.session.workstream ?? "No workstream"
            case .agent: return i.session.agent.displayName
            case .account: return i.account ?? i.session.agent.displayName
            }
        }
        var dict: [String: [BoardItem]] = [:]
        for i in items { dict[key(i), default: []].append(i) }
        let rowOrder: (BoardItem, BoardItem) -> Bool = { a, b in
            if a.status.rank != b.status.rank { return a.status.rank < b.status.rank }
            return a.session.name.localizedCaseInsensitiveCompare(b.session.name) == .orderedAscending
        }
        // Pinned sessions leave their group and sit together at the top.
        let pinned = items.filter(\.session.pinned)
        dict = [:]
        for i in items where !i.session.pinned { dict[key(i), default: []].append(i) }
        var groups = dict.map { BoardGroup(title: $0.key, items: $0.value.sorted(by: rowOrder)) }
        if g == .status {
            let rank = Dictionary(uniqueKeysWithValues: SessionStatus.allCases.map { ($0.label, $0.rank) })
            groups.sort { (rank[$0.title] ?? 99) < (rank[$1.title] ?? 99) }
        } else {
            groups.sort { a, b in
                let an = a.title.hasPrefix("No "), bn = b.title.hasPrefix("No ")
                if an != bn { return bn }
                return a.title.localizedCaseInsensitiveCompare(b.title) == .orderedAscending
            }
        }
        if !pinned.isEmpty { groups.insert(BoardGroup(title: "Pinned", items: pinned.sorted(by: rowOrder)), at: 0) }
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
