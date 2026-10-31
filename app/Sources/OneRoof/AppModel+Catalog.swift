import Foundation
import OneRoofCore

/// LAB-1509 · the session catalog: every session One Roof knows, grouped by repo, with Resume.
extension AppModel {
    /// Every session the board knows (live and history, every window, open or closed).
    func catalogEntries() -> [SessionCatalog.Entry] {
        let names = Dictionary(WorkspaceStore.shared.workspaces.map { ($0.id, $0.name) }, uniquingKeysWith: { a, _ in a })
        return sessionItems.map { i in   // LAB-1933: All sessions lists manual sessions only
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
        guard var i = item(id) else { return }
        // LAB-1537: opening an archived session puts it back in its window first.
        if i.session.archived {
            var s = i.session; s.archived = false; save(s)
            guard let back = item(id) else { return }
            i = back
        }
        let action = SessionCatalog.resume(for: i.session, state: catalogState(i))
        if action != .open { catalogNotes[id] = .starting(Date()); catalogPending = id }
        switch action {
        case .open: catalogNotes[id] = nil; reveal(i)
        case .claude: resume(i)
        case .terminal, .launch: launch(i)
        case let r: lastError = r.why
        }
    }

    /// LAB-1538 · Close from All sessions: end what runs for it (agent, shell, holder); the row stays.
    func catalogClose(_ id: String) {
        guard let i = item(id) else { return }
        closeAgent(i, remember: false)
    }

    /// LAB-1537 · the only way a session's record is deleted (All sessions, asked first).
    func catalogDeleteForever(_ id: String) {
        guard let i = item(id) else { return }
        deleteForever(i)
    }

    /// LAB-1514 · end every finished session (agent gone, shell still open) in roofd. The rows stay, as history.
    func closeFinishedSessions() -> Int {
        let finished = items.filter { catalogState($0) == .finishedShell }
        finished.forEach { closeAgent($0, remember: false) }
        return finished.count
    }

    // MARK: LAB-1585 search

    /// What search reads for each session (on the main thread: names and details only); `SessionSearch.docs` then
    /// reads the conversations, off the main thread.
    func catalogSearchRows() -> [(session: Session, window: String)] {
        let names = Dictionary(WorkspaceStore.shared.workspaces.map { ($0.id, $0.name) }, uniquingKeysWith: { a, _ in a })
        return sessionItems.map { ($0.session, names[workspaceId(of: $0)] ?? "") }   // LAB-1933
    }
}

extension SessionSearch {
    /// Conversation text per transcript (path → modified date, lines), read once while it is unchanged.
    nonisolated(unsafe) private static var cache: [String: (Date, [String])] = [:]
    private static let cacheLock = NSLock()

    /// One search document per session: its details, and its Claude conversation when it has one. Off the main thread.
    static func docs(_ rows: [(session: Session, window: String)]) -> [Doc] {
        rows.map { row in
            let s = row.session
            let meta = [s.name, s.ticket ?? "", s.lastRepo ?? s.repoPath, row.window, s.objective, s.openingMessage]
                .filter { !$0.isEmpty }.joined(separator: " · ")
            var lines: [String] = []
            if let cid = s.conversationId, let path = transcript(id: cid) {
                let mod = (try? FileManager.default.attributesOfItem(atPath: path)[.modificationDate] as? Date) ?? .distantPast
                cacheLock.lock(); let hit = cache[path]; cacheLock.unlock()
                if let (at, cached) = hit, at == mod { lines = cached }
                else {
                    lines = conversationLines(path: path)
                    cacheLock.lock(); cache[path] = (mod, lines); cacheLock.unlock()
                }
            }
            if !s.openingMessage.isEmpty { lines.insert(s.openingMessage, at: 0) }
            return Doc(id: s.id, title: s.name, meta: meta, lines: lines)
        }
    }
}

/// LAB-1584 · the answer to a catalog row's Resume, shown on the row.
enum CatalogNote: Equatable {
    case starting(Date)
    case failed(String)
}
