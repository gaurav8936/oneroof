import AppKit
import Combine
import SwiftUI
import OneRoofCore

/// What the centre of a main window shows (WINDOW_SHELL §4). Exactly one at a time; the terminal area (Workspace) is
/// the default. Replaces v0.1's six mode flags (boardMode, workMode, launchpadMode, learnMode, objectiveId, viewerPath).
enum CentreView: String, CaseIterable, Codable {
    case workspace, overview, resources, board, decisions, subagents, work, learn, objective, editor, review, loops, catalog, evals
    case history   // LAB-2044: the History place (was the Scroll layout page)

    var title: String {
        switch self {
        case .workspace: return "Workspace"
        case .overview: return "Overview"
        case .resources: return "Resources"
        case .board: return "Board"
        case .decisions: return "Decisions"
        case .subagents: return "Subagents"
        case .work: return "Projects"   // LAB-2049
        case .learn: return "Learn"
        case .objective: return "Objective"
        case .editor: return "Editor"
        case .review: return "Review changes"
        case .loops: return "Loops"
        case .catalog: return "Session catalog"   // LAB-1509
        case .evals: return "Evals"   // LAB-EVALS
        case .history: return "History"   // LAB-2044
        }
    }

    /// The views in the toolbar's switcher (Subagents is reached from Overview and the session).
    static let switcher: [CentreView] = [.workspace, .overview, .resources, .board, .decisions, .work, .learn]

    /// Fleet views fold the Sessions panel away (v0.1 rule); the Plan panel stays for details.
    var foldsSessions: Bool { [.overview, .resources, .board, .decisions, .subagents, .work, .learn, .loops, .catalog, .evals, .history].contains(self) }
}

/// One main window = one workspace (WINDOW_SHELL §1): its own sessions, selection, centre view and text size. All
/// windows share one AppModel (one store, one roofd), so fleet views always show every window.
final class WindowState: ObservableObject, Identifiable {
    /// The workspace id (store `workspaces.id`).
    let id: String
    @Published var name: String
    @Published var colour: String?
    /// v2: the centre and the place stay in step here, synchronously (a place opens its view; a view opened from a
    /// menu, such as ⇧⌘L Overview, moves the place). Views of a session (editor, review …) keep the place.
    @Published var centre: CentreView = .workspace {
        didSet { if let p = centre.place, p != place { place = p } }
    }
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
    /// v2 Subagents tab: true = the trace (Trace ▸ / Whole trace ▸), false = the cards.
    @Published var v2Trace = false
    @Published var filter = ""
    /// LAB-2046: History's filters and sort, remembered per window (the search text is not).
    @Published var historyQuery = HistoryQuery() { didSet { if historyQuery != oldValue { saveJSON(historyQuery, "v2.historyQuery") } } }
    /// LAB-2047 · LAB-2048: the Action log open over the Inbox, on this tab (nil = the Inbox itself).
    @Published var actionLog: ActionLogTab? { didSet { if let t = actionLog { save(t.rawValue, "v2.actionLogTab") } } }
    /// The tab the Action log opens on (the last one used in this window).
    var actionLogTab: ActionLogTab = .decisions
    /// LAB-2048: the Decisions tab's filters, remembered per window (the search text is not).
    @Published var actionLogQuery = ActionLogQuery() { didSet { if actionLogQuery != oldValue { saveJSON(actionLogQuery, "v2.actionLogQuery") } } }
    /// Count-chip filter in the Sessions panel.
    @Published var statusFilter: StatusChip?
    /// UI text scale, 0.85–1.3 in 0.05 steps (⌘+ ⌘− ⌘0), per window (S00.W.2).
    @Published var textScale: Double = 1
    /// v2 window (P1): the Focus ladder step, the layout and the place, per window, kept across relaunches.
    /// LAB-1736: the step and the Focus lane live in `step`, observed apart from this object (see `WindowStep`).
    let step = WindowStep()
    var focusStep: FocusStep {
        get { step.focusStep }
        set { step.focusStep = newValue }
    }
    private func focusStepChanged(from oldValue: FocusStep) {
        save(focusStep.rawValue, "focusStep")
        if focusStep != oldValue { TerminalSurfaceView.holdSizes() }   // LAB-1601: one terminal resize per step
        if place == .sessions, sessionsStep != focusStep { sessionsStep = focusStep; save(focusStep.rawValue, "sessionsStep") }
        // LAB-1601: entering the thin Focus lane shows the avatars at once, until the column has narrowed.
        if focusStep == .focus, oldValue != .focus, focusColumnWidth == nil {
            focusLaneSettling = true
            // Never left on: the layout clears it once the lane is narrow; this covers a layout that had nothing to do.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
                if self?.focusLaneSettling == true { self?.focusLaneSettling = false }
            }
        } else if focusStep != .focus, focusLaneSettling { focusLaneSettling = false }
    }
    /// LAB-1601 · the Focus lane is still narrowing to its avatars. Until it has, the column shows the avatars rather
    /// than reading its old width (250 pt) and building the whole session list for one layout pass, then again as it
    /// narrowed: about a second of a busy main thread on every step into Focus.
    var focusLaneSettling: Bool {
        get { step.focusLaneSettling }
        set { step.focusLaneSettling = newValue }
    }
    /// The step the Sessions place was last at (1.8.1): coming back from Home, Work… returns to it instead of resetting
    /// to step 1, so a Plan or dock you opened at Full does not fold away each time you visit another place.
    private(set) var sessionsStep: FocusStep?
    /// v2 column widths you dragged (1.8.1; 0.5.2.9 kept its panel widths, v2 reset them on every step and launch).
    var columnWidth: Double? { didSet { if let w = columnWidth { save(w, "v2.columnWidth") } } }
    var planWidth: Double? { didSet { if let w = planWidth { save(w, "v2.planWidth") } } }
    /// LAB-1829: the rail's width you dragged it to (66…132).
    var railWidth: Double? { didSet { if let w = railWidth { save(w, "v2.railWidth") } } }
    /// LAB-1829: you dragged the rail closed (it stays closed until you drag it back or use View › Show Rail).
    @Published var railFolded = false { didSet { if railFolded != oldValue { save(railFolded, "v2.railFolded") } } }
    /// LAB-1366: the Focus lane dragged wide to show the full list (nil = 52 pt avatars). Its own width, so widening
    /// it at Focus leaves the column width of the other steps alone.
    var focusColumnWidth: Double? {
        get { step.focusColumnWidth }
        set { step.focusColumnWidth = newValue }
    }
    private func focusColumnWidthChanged() {
        guard !SelfTest.isActive else { return }
        if let w = focusColumnWidth { Prefs.defaults.set(w, forKey: "v2.focusColumnWidth." + id) }
        else { Prefs.defaults.removeObject(forKey: "v2.focusColumnWidth." + id) }
    }
    @Published var layout: SessionLayout = .single { didSet { save(layout.rawValue, "layout") } }
    @Published var place: Place = .sessions {
        didSet {
            save(place.rawValue, "place")
            if centre.place != place, !(place == .sessions && centre.place == nil) { centre = place.centre }
        }
    }
    /// Sessions currently showing in a centre pane (set by the terminal area).
    var visibleInPanes: Set<String> = []

    init(id: String, name: String, colour: String? = nil) {
        self.id = id; self.name = name; self.colour = colour
        let readSaved = !SelfTest.isActive || Prefs.seeded   // a seeded test profile reads (never saves) window state
        textScale = readSaved ? (Prefs.defaults.object(forKey: "textScale." + id) as? Double ?? 1) : 1
        if readSaved {
            let d = Prefs.defaults
            // 1.8.1: a window from 0.5.2.9 (its classic pane layout is saved) opens once at Full, nothing hidden.
            let saved = d.object(forKey: "focusStep." + id) as? Int
            focusStep = V2Layout.initialStep(saved: saved, existedBefore: d.object(forKey: TerminalAreaController.panesKey(id)) != nil)
            if saved == nil { save(focusStep.rawValue, "focusStep") }   // decided once; later launches read it back
            sessionsStep = (d.object(forKey: "sessionsStep." + id) as? Int).flatMap(FocusStep.init(rawValue:))
            // Grid and Wall are built from live sessions; a relaunch starts in Single (your panes), never empty tiles.
            // LAB-2044: a window saved with "scroll" (1.9.31–1.9.37) opens as Single.
            if let v = d.string(forKey: "layout." + id), let l = SessionLayout(stored: v), l == .single { layout = l }
            if let v = d.string(forKey: "place." + id), let p = Place(rawValue: v) { place = p }
            if sessionsStep == nil, place == .sessions { sessionsStep = focusStep }
            columnWidth = d.object(forKey: "v2.columnWidth." + id) as? Double
            planWidth = d.object(forKey: "v2.planWidth." + id) as? Double
            railFolded = d.bool(forKey: "v2.railFolded." + id)
            railWidth = d.object(forKey: "v2.railWidth." + id) as? Double
            focusColumnWidth = d.object(forKey: "v2.focusColumnWidth." + id) as? Double
            if let q: HistoryQuery = Self.loadJSON(d, "v2.historyQuery." + id) { historyQuery = q }
            if let q: ActionLogQuery = Self.loadJSON(d, "v2.actionLogQuery." + id) { actionLogQuery = q }
            if let t = d.string(forKey: "v2.actionLogTab." + id).flatMap(ActionLogTab.init(rawValue:)) { actionLogTab = t }
        }
        // After the saved values are read: like didSet, these run for later changes only.
        step.stepChanged = { [unowned self] old in self.focusStepChanged(from: old) }
        step.laneWidthChanged = { [unowned self] in self.focusColumnWidthChanged() }
    }

    private func save(_ value: Any, _ key: String) {
        if !SelfTest.isActive { Prefs.defaults.set(value, forKey: key + "." + id) }
    }
    private func saveJSON<T: Encodable>(_ value: T, _ key: String) {
        if let d = try? JSONEncoder().encode(value), let s = String(data: d, encoding: .utf8) { save(s, key) }
    }
    private static func loadJSON<T: Decodable>(_ d: UserDefaults, _ key: String) -> T? {
        d.string(forKey: key).flatMap { try? JSONDecoder().decode(T.self, from: Data($0.utf8)) }
    }
    /// LAB-2047: open the Action log over the Inbox, on `tab` (or the last one used).
    func openActionLog(_ tab: ActionLogTab? = nil) {
        let t = tab ?? actionLogTab
        actionLogTab = t
        if place != .needsYou { open(.needsYou) }
        actionLog = t
    }

    /// Open a place at its default step (FOCUS_LADDER.md: Sessions at 1, the other places at 0).
    func open(_ p: Place) { place = p; focusStep = V2Layout.openingStep(p, sessionsStep: sessionsStep) }
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

/// LAB-1736 · the Focus ladder step and the Focus lane of one window, observed apart from the rest of its state. As
/// @Published properties of WindowState, a step redrew every view observing the window (rail, tabs, toolbar, Plan,
/// column) and, forwarded through AppModel, every view observing the model in every window: most of a step's
/// 60–130 ms main-thread stall. Only the views that draw the step observe this; `WindowState.focusStep`,
/// `focusLaneSettling` and `focusColumnWidth` read and write it.
final class WindowStep: ObservableObject {
    @Published var focusStep: FocusStep = .sessions { didSet { stepChanged?(oldValue) } }
    @Published var focusLaneSettling = false
    @Published var focusColumnWidth: Double? { didSet { laneWidthChanged?() } }
    var stepChanged: ((FocusStep) -> Void)?
    var laneWidthChanged: (() -> Void)?
}

/// LAB-1736 · redraws its content when the window's step or Focus lane changes (and nothing else does).
struct StepReader<Content: View>: View {
    @ObservedObject var step: WindowStep
    @ViewBuilder let content: (WindowStep) -> Content
    var body: some View { content(step) }
}
