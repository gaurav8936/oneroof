import Foundation
import OneRoofCore

/// Workspaces (main windows) and which session lives in which, in sessions.sqlite (DATA_MODEL §2 `workspaces`,
/// `session_workspace`; migration 1 created one "Main" workspace holding every v0.1 session). Whether a window is
/// open is kept in the workspace's layout JSON, so closed workspaces stay listed in Window ▸ Workspaces.
final class WorkspaceStore {
    static let mainId = RoofWorkspace.mainId.uuidString
    static let shared = WorkspaceStore()

    struct Record: Equatable {
        var id: String
        var name: String
        var colour: String?
        var order: Int
        var open: Bool = true
    }

    private struct Layout: Codable { var open: Bool = true }

    private var store: SessionStore?

    /// Called once by the model with its store.
    func attach(_ s: SessionStore?) { store = s }

    var workspaces: [Record] {
        let all = store?.allWorkspaces() ?? [RoofWorkspace(id: RoofWorkspace.mainId, name: "Main")]
        return all.sorted { $0.order < $1.order }.map { w in
            let open = w.layout.flatMap { try? JSONDecoder().decode(Layout.self, from: Data($0.utf8)) }?.open ?? true
            return Record(id: w.id.uuidString, name: w.name, colour: w.colour, order: w.order, open: open)
        }
    }

    var assignments: [String: String] {
        (store?.sessionWorkspaces() ?? [:]).mapValues(\.uuidString)
    }

    func assign(session: String, to workspace: String) {
        guard let id = UUID(uuidString: workspace) else { return }
        store?.move(session: session, to: id)
    }

    @discardableResult
    func create(name: String, colour: String? = nil) -> Record {
        let order = (workspaces.map(\.order).max() ?? 0) + 1
        let w = RoofWorkspace(name: name, colour: colour, order: order, layout: Self.layout(open: true))
        store?.save(w)
        return Record(id: w.id.uuidString, name: name, colour: colour, order: order)
    }

    func update(_ r: Record) {
        guard let id = UUID(uuidString: r.id) else { return }
        store?.save(RoofWorkspace(id: id, name: r.name, colour: r.colour, order: r.order, layout: Self.layout(open: r.open)))
    }

    /// Remove a workspace; its sessions go back to Main.
    func remove(_ id: String) {
        guard id != Self.mainId, let u = UUID(uuidString: id) else { return }
        store?.deleteWorkspace(id: u)
    }

    private static func layout(open: Bool) -> String {
        String(decoding: (try? JSONEncoder().encode(Layout(open: open))) ?? Data(), as: UTF8.self)
    }
}
