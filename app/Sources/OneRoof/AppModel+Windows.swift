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

    /// The workspace a session belongs to.
    func workspaceId(of item: BoardItem) -> String {
        if let w = sessionWorkspace[item.id], windows.contains(where: { $0.id == w }) { return w }
        return windows.first?.id ?? WorkspaceStore.mainId
    }

    /// Sessions in one window, in the order the sidebar shows them.
    func items(in w: WindowState) -> [BoardItem] { items.filter { workspaceId(of: $0) == w.id } }

    /// Move a session to another workspace window (S00.W.1).
    func move(_ item: BoardItem, to w: WindowState) {
        sessionWorkspace[item.id] = w.id
        WorkspaceStore.shared.assign(session: item.id, to: w.id)
        for other in windows where other.selectedId == item.id && other.id != w.id { other.selectedId = nil }
        objectWillChange.send()
    }

    /// A new session joins the window in front.
    func assignToActive(_ sessionId: String) {
        guard sessionWorkspace[sessionId] == nil else { return }
        sessionWorkspace[sessionId] = active.id
        WorkspaceStore.shared.assign(session: sessionId, to: active.id)
    }

    /// Select a session wherever it lives: its window comes forward with the terminal in the centre.
    func reveal(_ item: BoardItem) {
        let w = window(workspaceId(of: item)) ?? active
        w.selectedId = item.id
        show(.workspace, in: w)
        NotificationCenter.default.post(name: .focusWorkspace, object: w.id)
    }

    /// Rows matching a window's filter and count chip (name, caption, repo, workstream, ticket, stickers, agent, account).
    func visibleItems(in w: WindowState) -> [BoardItem] {
        var list = items(in: w)
        if let chip = w.statusFilter { list = list.filter { chip.matches($0) } }
        let q = w.filter.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return list }
        return list.filter { i in
            [i.session.name, i.repoLabel, i.session.workstream ?? "", i.session.tags.joined(separator: " "), i.session.ticket ?? "",
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
