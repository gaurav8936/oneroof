import AppKit
import Combine
import OneRoofCore

/// What the centre of a main window shows (WINDOW_SHELL §4). Exactly one at a time; the terminal area (Workspace) is
/// the default. Replaces v0.1's six mode flags (boardMode, workMode, launchpadMode, learnMode, objectiveId, viewerPath).
enum CentreView: String, CaseIterable, Codable {
    case workspace, overview, resources, board, decisions, subagents, work, learn, objective, editor, review, loops

    var title: String {
        switch self {
        case .workspace: return "Workspace"
        case .overview: return "Overview"
        case .resources: return "Resources"
        case .board: return "Board"
        case .decisions: return "Decisions"
        case .subagents: return "Subagents"
        case .work: return "Work"
        case .learn: return "Learn"
        case .objective: return "Objective"
        case .editor: return "Editor"
        case .review: return "Review changes"
        case .loops: return "Loops"
        }
    }

    /// The views in the toolbar's switcher (Subagents is reached from Overview and the session).
    static let switcher: [CentreView] = [.workspace, .overview, .resources, .board, .decisions, .work, .learn]

    /// Fleet views fold the Sessions panel away (v0.1 rule); the Plan panel stays for details.
    var foldsSessions: Bool { [.overview, .resources, .board, .decisions, .subagents, .work, .learn, .loops].contains(self) }
}

/// One main window = one workspace (WINDOW_SHELL §1): its own sessions, selection, centre view and text size. All
/// windows share one AppModel (one store, one roofd), so fleet views always show every window.
final class WindowState: ObservableObject, Identifiable {
    /// The workspace id (store `workspaces.id`).
    let id: String
    @Published var name: String
    @Published var colour: String?
    @Published var centre: CentreView = .workspace
    @Published var selectedId: String?
    /// A file or folder in the centre (Editor, or the viewer for Markdown, images, HTML and folders).
    @Published var viewerPath: String?
    @Published var viewerLine: Int?
    var viewerHistory: [String] = []
    /// The objective in the centre (Objective view).
    @Published var objectiveId: String?
    /// The repo Review changes shows.
    @Published var reviewRepo: String?
    /// The subagent the trace focuses on, "<session>/<subagent>".
    @Published var traceFocus: String?
    @Published var filter = ""
    /// Count-chip filter in the Sessions panel.
    @Published var statusFilter: StatusChip?
    /// UI text scale, 0.85–1.3 in 0.05 steps (⌘+ ⌘− ⌘0), per window (S00.W.2).
    @Published var textScale: Double = 1
    /// v2 window (P1): the Focus ladder step, the layout and the place, per window, kept across relaunches.
    @Published var focusStep: FocusStep = .sessions { didSet { save(focusStep.rawValue, "focusStep") } }
    @Published var layout: SessionLayout = .single { didSet { save(layout.rawValue, "layout") } }
    @Published var place: Place = .sessions { didSet { save(place.rawValue, "place") } }
    /// Sessions currently showing in a centre pane (set by the terminal area).
    var visibleInPanes: Set<String> = []

    init(id: String, name: String, colour: String? = nil) {
        self.id = id; self.name = name; self.colour = colour
        textScale = SelfTest.isActive ? 1 : (Prefs.defaults.object(forKey: "textScale." + id) as? Double ?? 1)
        if !SelfTest.isActive {
            let d = Prefs.defaults
            if let v = d.object(forKey: "focusStep." + id) as? Int, let f = FocusStep(rawValue: v) { focusStep = f }
            if let v = d.string(forKey: "layout." + id), let l = SessionLayout(rawValue: v) { layout = l }
            if let v = d.string(forKey: "place." + id), let p = Place(rawValue: v) { place = p }
        }
    }

    private func save(_ value: Any, _ key: String) {
        if !SelfTest.isActive { Prefs.defaults.set(value, forKey: key + "." + id) }
    }

    /// Open a place at its default step (FOCUS_LADDER.md: Sessions at 1, the other places at 0).
    func open(_ p: Place) { place = p; focusStep = p.defaultStep }
    /// ⌥⌘F steps on (0 → 1 → 2 → 3), ⇧⌥⌘F steps back; Esc in Focus returns to the step before it.
    func stepOn() { focusStep = focusStep.next }
    func stepBack() { focusStep = focusStep.previous }

    /// Rename the window (LAB-509): the big name in its toolbar, its NSWindow title (Mission Control, Window menu) and
    /// Window › Workspaces. Saved with the workspace. False when the name is empty (the old one stays).
    @discardableResult
    func rename(_ raw: String) -> Bool {
        guard let n = WindowName.clean(raw) else { return false }
        name = n
        if var r = WorkspaceStore.shared.workspaces.first(where: { $0.id == id }) { r.name = n; WorkspaceStore.shared.update(r) }
        return true
    }

    /// The window's colour (LAB-590), a `Sticker.rowColors` name; nil = no accent (the look before 0.5.1).
    func setColour(_ c: String?) {
        colour = c
        if var r = WorkspaceStore.shared.workspaces.first(where: { $0.id == id }) { r.colour = c; WorkspaceStore.shared.update(r) }
    }

    /// Ask for a new name (toolbar name menu, Window › Rename Window…).
    func promptRename() {
        let a = NSAlert()
        a.messageText = "Name this window"
        a.informativeText = "Shown big at the top of the window and in Mission Control, so you can tell windows apart."
        let f = NSTextField(string: name)
        f.frame = NSRect(x: 0, y: 0, width: 260, height: 24)
        a.accessoryView = f
        a.window.initialFirstResponder = f
        a.addButton(withTitle: "Rename"); a.addButton(withTitle: "Cancel")
        guard a.runModal() == .alertFirstButtonReturn else { return }
        rename(f.stringValue)
    }

    func setTextScale(_ s: Double) {
        textScale = min(1.3, max(0.85, (s * 20).rounded() / 20))
        if !SelfTest.isActive { Prefs.defaults.set(textScale, forKey: "textScale." + id) }
    }

    /// Open the viewer/editor on a path (a folder with a README opens on the README).
    func show(path: String, line: Int? = nil) {
        viewerLine = line
        viewerPath = path
        if viewerHistory.last != path { viewerHistory.append(path) }
        let tabs = EditorState.of(id)
        tabs.tabs = CentreTabs.opening(path, in: tabs.tabs, isFile: path != FileKind.searchPath && !path.hasPrefix(FileKind.diffPrefix))
        centre = .editor
    }

    /// Close a file's tab (LAB-799): the centre moves to a neighbouring file, or back to the terminals after the last.
    func closeTab(_ path: String) {
        let state = EditorState.of(id)
        let front = centre == .editor ? viewerPath : nil
        let next = CentreTabs.showing(afterClosing: path, in: state.tabs, showing: front)
        state.close(path)
        if let next { if next != front { show(path: next) } } else if centre == .editor { centre = .workspace }
    }
}

/// The Sessions panel's count chips (S06 §1.2). Owner 10-20: they cover where sessions actually sit, and "All" is always
/// there to get the full list back. LAB-515: one Active chip for Working, Ready and Idle (the list's Active group); a
/// row says which on its own. Chips count the status the list groups by, so a chip's number matches its group.
enum StatusChip: String, CaseIterable {
    case all, needs, active, exited

    /// nil: every session.
    var statuses: Set<SessionStatus>? {
        switch self {
        case .all: return nil
        case .needs: return [.needsYou]
        case .active: return [.running, .done, .idle]
        case .exited: return [.exited]
        }
    }

    /// Exited counts agent sessions only (owner 10-20): an agent that ended is worth relaunching or clearing; a
    /// terminal that ended is not news.
    func matches(_ i: BoardItem) -> Bool {
        if self == .exited, !i.session.agent.isAgent { return false }
        return statuses?.contains(i.listStatus) ?? true
    }

    /// What the chip's sessions are (LAB-241), shown on hover.
    var meaning: String {
        switch self {
        case .all: return "Every session in this window."
        case .needs: return SessionStatus.needsYou.meaning
        case .active: return SessionStatus.activeMeaning
        case .exited: return SessionStatus.exited.meaning
        }
    }

    func label(_ n: Int) -> String {
        switch self {
        case .all: return "\(n) all"
        case .needs: return "\(n) need you"
        case .active: return "\(n) active"
        case .exited: return "\(n) exited"
        }
    }
}
