import Foundation
import OneRoofCore

/// LAB-1509 · the session catalog: every session One Roof knows, grouped by repo, with Resume.
extension AppModel {
    /// Every session the board knows (live and history, every window, open or closed).
    func catalogEntries() -> [SessionCatalog.Entry] {
        let names = Dictionary(WorkspaceStore.shared.workspaces.map { ($0.id, $0.name) }, uniquingKeysWith: { a, _ in a })
        return items.map { i in
            SessionCatalog.entry(i.session, state: catalogState(i), window: names[workspaceId(of: i)], lastActive: lastActiveDate(i))
        }
    }

    func catalogState(_ i: BoardItem) -> SessionCatalog.State {
        SessionCatalog.state(liveAgent: i.liveAgent != nil, endedShell: i.endedShell != nil, status: i.status, launched: i.session.launchedAt != nil)
    }

    /// LAB-1513 · the row's button: bring a running session forward, resume a saved Claude conversation (in its
    /// still-open shell, else a new terminal with `--resume <id>`), or open a new terminal for a shell. Rows that
    /// cannot be resumed say why instead of starting something new.
    func catalogResume(_ id: String) {
        guard let i = item(id) else { return }
        switch SessionCatalog.resume(for: i.session, state: catalogState(i)) {
        case .open: reveal(i)
        case .claude: resume(i)
        case .terminal, .launch: launch(i)
        case let r: lastError = r.why
        }
    }

    /// LAB-1514 · end every finished session (agent gone, shell still open) in roofd. The rows stay, as history.
    func closeFinishedSessions() -> Int {
        let finished = items.filter { catalogState($0) == .finishedShell }
        finished.forEach { closeAgent($0, remember: false) }
        return finished.count
    }
}
