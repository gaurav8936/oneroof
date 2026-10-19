import Foundation

/// Roof windows: a window for one repo or one workstream that shows every live session of it as panes.
/// Pure: which sessions belong, what the Window menu offers, and how the panes are laid out.
public enum RoofScope: Codable, Hashable, Sendable {
    case repo(String)          // absolute repo path
    case workstream(String)    // workstream id, e.g. "WS-WEB-12"

    public var title: String {
        switch self {
        case .repo(let p): return Workspace.repoLabel(for: p)
        case .workstream(let w): return w
        }
    }

    /// Live sessions only: a roof window shows terminals, and only live agents have one.
    public func contains(_ item: BoardItem) -> Bool {
        guard item.liveAgent != nil else { return false }
        switch self {
        case .repo(let p): return item.session.repoPath == p
        case .workstream(let w): return item.session.workstream?.caseInsensitiveCompare(w) == .orderedSame
        }
    }

    public func sessions(in items: [BoardItem]) -> [BoardItem] { items.filter(contains) }

    /// Scopes with at least one live session, repos first, each with its live count (for the Window menu).
    public static func available(in items: [BoardItem]) -> [(scope: RoofScope, count: Int)] {
        let live = items.filter { $0.liveAgent != nil }
        let repos = Dictionary(grouping: live, by: \.session.repoPath)
            .map { (scope: RoofScope.repo($0.key), count: $0.value.count) }
            .sorted { $0.scope.title.localizedCaseInsensitiveCompare($1.scope.title) == .orderedAscending }
        let ws = Dictionary(grouping: live.filter { !($0.session.workstream ?? "").isEmpty }, by: { $0.session.workstream!.uppercased() })
            .map { (scope: RoofScope.workstream($0.key), count: $0.value.count) }
            .sorted { $0.scope.title < $1.scope.title }
        return repos + ws
    }
}

extension PaneNode {
    /// An even grid for `sessions`: rows stacked top to bottom, each row side by side, about as many columns as
    /// rows (1 → one pane, 2 → side by side, 3–4 → 2 × 2, 5–6 → 2 rows of 3). Nil for no sessions.
    public static func grid(_ sessions: [String]) -> PaneNode? {
        guard !sessions.isEmpty else { return nil }
        let cols = Int(Double(sessions.count).squareRoot().rounded(.up))
        let rows = stride(from: 0, to: sessions.count, by: cols).map { Array(sessions[$0..<min($0 + cols, sessions.count)]) }
        func chain(_ nodes: [PaneNode], sideBySide: Bool) -> PaneNode {
            nodes.count == 1 ? nodes[0]
                : .split(sideBySide: sideBySide, ratio: 1 / Double(nodes.count), nodes[0], chain(Array(nodes.dropFirst()), sideBySide: sideBySide))
        }
        return chain(rows.map { r in chain(r.map { .leaf(PaneLeaf(id: $0, session: $0)) }, sideBySide: true) }, sideBySide: false)
    }
}
