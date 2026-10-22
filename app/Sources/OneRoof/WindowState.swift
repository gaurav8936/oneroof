import AppKit
import Combine
import OneRoofCore

/// What the centre of a main window shows (WINDOW_SHELL §4). Exactly one at a time; the terminal area (Workspace) is
/// the default. Replaces v0.1's six mode flags (boardMode, workMode, launchpadMode, learnMode, objectiveId, viewerPath).
enum CentreView: String, CaseIterable, Codable {
    case workspace, overview, resources, board, decisions, subagents, work, learn, objective, editor, review

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
        }
    }

    /// The views in the toolbar's switcher (Subagents is reached from Overview and the session).
    static let switcher: [CentreView] = [.workspace, .overview, .resources, .board, .decisions, .work, .learn]

    /// Fleet views fold the Sessions panel away (v0.1 rule); the Plan panel stays for details.
    var foldsSessions: Bool { [.overview, .resources, .board, .decisions, .subagents, .work, .learn].contains(self) }
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
    /// Sessions currently showing in a centre pane (set by the terminal area).
    var visibleInPanes: Set<String> = []

    init(id: String, name: String, colour: String? = nil) {
        self.id = id; self.name = name; self.colour = colour
        textScale = SelfTest.isActive ? 1 : (Prefs.defaults.object(forKey: "textScale." + id) as? Double ?? 1)
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
        centre = .editor
    }
}

/// The Sessions panel's count chips (S06 §1.2). Owner 10-20: they cover where sessions actually sit (most are idle or
/// finished, "next" was rarely used), and "All" is always there to get the full list back.
enum StatusChip: String, CaseIterable {
    case all, needs, working, ready, idle, exited

    /// nil: every session.
    var statuses: Set<SessionStatus>? {
        switch self {
        case .all: return nil
        case .needs: return [.needsYou]
        case .working: return [.running]
        case .ready: return [.done]
        case .idle: return [.idle]
        case .exited: return [.exited]
        }
    }

    /// Exited counts agent sessions only (owner 10-20): an agent that ended is worth relaunching or clearing; a
    /// terminal that ended is not news.
    func matches(_ i: BoardItem) -> Bool {
        if self == .exited, !i.session.agent.isAgent { return false }
        return statuses?.contains(i.status) ?? true
    }

    /// What the chip's sessions are (LAB-241), shown on hover.
    var meaning: String {
        switch self {
        case .all: return "Every session in this window."
        case .needs: return SessionStatus.needsYou.meaning
        case .working: return SessionStatus.running.meaning
        case .ready: return SessionStatus.done.meaning
        case .idle: return SessionStatus.idle.meaning
        case .exited: return SessionStatus.exited.meaning
        }
    }

    func label(_ n: Int) -> String {
        switch self {
        case .all: return "\(n) all"
        case .needs: return "\(n) need you"
        case .working: return "\(n) working"
        case .ready: return "\(n) ready"
        case .idle: return "\(n) idle"
        case .exited: return "\(n) exited"
        }
    }
}
