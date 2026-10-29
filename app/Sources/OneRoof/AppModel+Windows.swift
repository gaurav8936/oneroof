import AppKit
import Combine
import OneRoofCore

/// Workspaces (one per main window) and the centre router. Per-window state lives in `WindowState`; the
/// properties below read and write the active window's, so menu actions and older views act on the window in front.
extension AppModel {
    var active: WindowState {
        if let id = activeWindowId, let w = windows.first(where: { $0.id == id }) { return w }
        if let w = windows.first { return w }
        let w = WindowState(id: WorkspaceStore.mainId, name: "Main")
        adopt(w)
        return w
    }

    func window(_ id: String) -> WindowState? { windows.first { $0.id == id } }

    /// Add a window's state and forward its changes, so views observing the model redraw.
    func adopt(_ w: WindowState) {
        guard !windows.contains(where: { $0.id == w.id }) else { return }
        windows.append(w)
        windowBags[w.id] = w.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }
    }

    func forget(_ w: WindowState) {
        windows.removeAll { $0.id == w.id }
        windowBags[w.id] = nil
        if activeWindowId == w.id { activeWindowId = windows.first?.id }
    }

    // MARK: Per-window state of the window in front

    var selectedId: String? {
        get { active.selectedId }
        set { active.selectedId = newValue }
    }
    var centre: CentreView {
        get { active.centre }
        set { show(newValue) }
    }
    var filter: String {
        get { active.filter }
        set { active.filter = newValue }
    }
    var visibleInPanes: Set<String> {
        get { Set(windows.flatMap(\.visibleInPanes)) }
        set { active.visibleInPanes = newValue }
    }
    var viewerPath: String? {
        get { active.centre == .editor ? active.viewerPath : nil }
        set {
            if let v = newValue {
                if v.hasPrefix(FileKind.diffPrefix) { active.reviewRepo = String(v.dropFirst(FileKind.diffPrefix.count)); show(.review) }
                else { active.show(path: v, line: active.viewerLine) }
            } else if active.centre == .editor || active.centre == .review {
                show(.workspace)
            }
        }
    }
    var viewerLine: Int? {
        get { active.viewerLine }
        set { active.viewerLine = newValue }
    }
    var viewerHistory: [String] { active.viewerHistory }
    var objectiveId: String? {
        get { active.centre == .objective ? active.objectiveId : nil }
        set {
            active.objectiveId = newValue
            if newValue != nil { show(.objective) } else if active.centre == .objective { show(.workspace) }
        }
    }

    // v0.1 mode flags, now views of `centre`.
    var boardMode: Bool { get { centre == .board } set { toggle(.board, newValue) } }
    var workMode: Bool { get { centre == .work } set { toggle(.work, newValue) } }
    var launchpadMode: Bool { get { centre == .overview } set { toggle(.overview, newValue) } }
    var learnMode: Bool { get { centre == .learn } set { toggle(.learn, newValue) } }

    private func toggle(_ v: CentreView, _ on: Bool) {
        if on { show(v) } else if centre == v { show(.workspace) }
    }

    /// Switch the active window's centre view.
    func show(_ v: CentreView, in w: WindowState? = nil) {
        let win = w ?? active
        if win.centre != v { win.centre = v }
    }

    // MARK: Workspaces

    /// The workspace a session belongs to (LAB-705): the window it was made in or moved to, even while that window is
    /// closed; only a session with no window is the first open window's. See `WindowMembership`.
    func workspaceId(of item: BoardItem) -> String {
        WindowMembership.home(of: item.id, assigned: sessionWorkspace, open: windows.map(\.id), existing: WorkspaceStore.shared.ids)
            ?? WorkspaceStore.mainId
    }

    /// Sessions in one window, in the order the sidebar shows them. A closed window's sessions are in none.
    func items(in w: WindowState) -> [BoardItem] { items.filter { workspaceId(of: $0) == w.id } }

    /// Move a session to another workspace window (S00.W.1). The window it leaves lets go of its terminal, so the new
    /// window can show it at once; `select` also makes it the new window's selection.
    func move(_ item: BoardItem, to w: WindowState, select: Bool = false) {
        sessionWorkspace[item.id] = w.id
        WorkspaceStore.shared.assign(session: item.id, to: w.id)
        for other in windows where other.selectedId == item.id && other.id != w.id { other.selectedId = nil }
        if let agent = item.liveAgent {
            NotificationCenter.default.post(name: .releaseSurface, object: agent, userInfo: ["win": w.id, "force": true, "moved": true])
        }
        if select {
            w.selectedId = item.id
            show(.workspace, in: w)
        }
        objectWillChange.send()
    }

    /// A new session joins the window it was asked for in (LAB-705), or the window in front when no window asked.
    /// Pass the window: a sheet's Linear call or a launch can finish after the owner clicked into another window.
    func assign(_ sessionId: String, to w: WindowState? = nil) {
        guard sessionWorkspace[sessionId] == nil else { return }
        let id = (w ?? active).id
        sessionWorkspace[sessionId] = id
        WorkspaceStore.shared.assign(session: sessionId, to: id)
    }

    /// The open window a session belongs to; nil while that window is closed.
    func window(of sessionId: String) -> WindowState? { item(sessionId).flatMap { window(workspaceId(of: $0)) } }

    /// Select a session wherever it lives: its window comes forward (reopened if it was closed) with the terminal in the
    /// centre.
    func reveal(_ item: BoardItem) {
        let id = workspaceId(of: item)
        if window(id) == nil, let r = WorkspaceStore.shared.workspaces.first(where: { $0.id == id }) {
            adopt(WindowState(id: r.id, name: r.name, colour: r.colour))
        }
        let w = window(id) ?? active
        w.selectedId = item.id
        show(.workspace, in: w)
        NotificationCenter.default.post(name: .focusWorkspace, object: w.id)
    }

    /// LAB-1514: a session that ended more than a day ago, with nothing running (no agent, no shell) and not pinned.
    func isOldHistory(_ i: BoardItem, now: Date = Date()) -> Bool {
        guard i.liveAgent == nil, i.endedShell == nil, i.status == .exited, !i.session.pinned, !i.adopted else { return false }
        return (lastActiveDate(i) ?? .distantPast) < now.addingTimeInterval(-24 * 3600)
    }

    /// Rows matching a window's filter and count chip (name, caption, repo, workstream, ticket, stickers, agent, account).
    func visibleItems(in w: WindowState) -> [BoardItem] {
        var list = items(in: w)
        if let chip = w.statusFilter { list = list.filter { chip.matches($0) } }
        // LAB-1514: in the All list, history older than a day (nothing running, not pinned) leaves the window's live list.
        // It is still under the Exited chip and in View › Session Catalog; nothing is deleted.
        else { list = list.filter { !isOldHistory($0) } }
        let q = w.filter.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return list }
        return list.filter { i in
            [i.session.name, i.repoLabel, i.session.workstream ?? "", i.session.tags.joined(separator: " "), i.session.allTickets.map(\.key).joined(separator: " "),
             caption(for: i).text, i.session.agent.displayName, i.account ?? "", i.status.label]
                .joined(separator: " ").lowercased().contains(q)
        }
    }

    func groups(in w: WindowState) -> [BoardGroup] { Board.group(visibleItems(in: w), by: grouping) }
}

extension Notification.Name {
    /// Bring a workspace window forward (object: workspace id).
    static let focusWorkspace = Notification.Name("oneroof.focusWorkspace")
}
