import Foundation

/// One Roof v2 · a look sets every panel theme at once (handover theme/looks.json).
public enum Look: String, CaseIterable, Identifiable, Codable, Sendable {
    case skyStudio, mintGarden, lavenderDusk, peachPaper, daylight, midnight
    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .skyStudio: return "Sky Studio"
        case .mintGarden: return "Mint Garden"
        case .lavenderDusk: return "Lavender Dusk"
        case .peachPaper: return "Peach Paper"
        case .daylight: return "Daylight"
        case .midnight: return "Midnight"
        }
    }

    public var blurb: String {
        switch self {
        case .skyStudio: return "Sky sidebar · Graphite terminal · Daylight plan"
        case .mintGarden: return "Mint all round · Midnight terminal"
        case .lavenderDusk: return "Lavender chrome · Midnight terminals"
        case .peachPaper: return "Warm paper · Graphite terminal"
        case .daylight: return "All light, including the terminal"
        case .midnight: return "All dark"
        }
    }

    /// The rail and dock theme (deepest plane). Uses `control` of this theme.
    public var rail: ThemeName { panelThemes.sidebar }

    public var panelThemes: PanelThemes {
        switch self {
        case .skyStudio: return PanelThemes(sidebar: .sky, files: .sky, terminal: .graphite, plan: .daylight, centre: .sky)
        case .mintGarden: return PanelThemes(sidebar: .mint, files: .mint, terminal: .midnight, plan: .mint, centre: .mint)
        case .lavenderDusk: return PanelThemes(sidebar: .lavender, files: .lavender, terminal: .midnight, plan: .lavender, centre: .lavender)
        case .peachPaper: return PanelThemes(sidebar: .peach, files: .peach, terminal: .graphite, plan: .peach, centre: .peach)
        case .daylight: return PanelThemes(sidebar: .daylight, files: .daylight, terminal: .daylight, plan: .daylight, centre: .daylight)
        case .midnight: return PanelThemes(sidebar: .midnight, files: .midnight, terminal: .midnight, plan: .midnight, centre: .midnight)
        }
    }

    /// The look that matches saved per-panel themes, or nil when the owner customised them.
    public static func matching(_ t: PanelThemes) -> Look? { allCases.first { $0.panelThemes == t } }
    public static let storageKey = "look.v2"

    /// LAB-1951 · ONEROOF_SELFTEST_LOOK=<look | theme>: the panel themes a self-test starts with. A look's name
    /// (skyStudio, midnight, …) gives its themes; a theme's name (daylight · graphite · midnight, or the v0.1
    /// light · dim · dark) puts every panel in that theme. Before 1.9.35 the variable only set Settings' look name and
    /// the panels kept the saved (or, on a fresh profile, default) themes, so LOOK=midnight changed nothing.
    public static func selfTestThemes(_ value: String) -> PanelThemes? {
        if let l = Look(rawValue: value) { return l.panelThemes }
        guard let t = ThemeName(stored: value.lowercased()) else { return nil }
        return PanelThemes(sidebar: t, files: t, terminal: t, plan: t, centre: t)
    }
}

/// The Focus ladder (shared/FOCUS_LADDER.md). Stored per window.
public enum FocusStep: Int, CaseIterable, Codable, Sendable, Comparable {
    case full = 0, sessions = 1, wide = 2, focus = 3
    public static func < (a: FocusStep, b: FocusStep) -> Bool { a.rawValue < b.rawValue }
    public var title: String { ["Full", "Sessions", "Wide", "Focus"][rawValue] }
    public var next: FocusStep { FocusStep(rawValue: min(3, rawValue + 1)) ?? .focus }
    public var previous: FocusStep { FocusStep(rawValue: max(0, rawValue - 1)) ?? .full }
    /// The step a click on the toolbar's step button goes to: the next one, and from Focus round to Full (LAB-1235).
    /// ⌥⌘F keeps `next` and leaves Focus to the step before it; ⇧⌥⌘F is `previous`.
    public var clicked: FocusStep { self == .focus ? .full : next }

    public var showsRail: Bool { self == .full || self == .wide }
    public var showsIconRow: Bool { self == .sessions }
    public var showsSessionColumn: Bool { self != .focus }
    public var showsAvatars: Bool { self == .focus }
    public var showsInspector: Bool { self == .full }
    public var showsInspectorTab: Bool { self == .sessions || self == .wide }
    public var showsDock: Bool { self == .full }
    public var showsDockLine: Bool { self == .sessions }
    public var seatsInRail: Bool { self == .wide }
}

/// Places (shared/NAVIGATION.md).
public enum Place: String, CaseIterable, Identifiable, Codable, Sendable {
    // LAB-2332: 13 places in six groups (Work · Agents · Run · Models · Ship · Learn). Agents, Factory, Train and Ship
    // start as PLANNED placeholders; History folds into Trace (its first tab). The case order is the rail order.
    case home, needsYou, sessions, work   // Work
    case agents, factory                  // Agents: the roster, the playbook
    case loops, trace, machine            // Run
    case evals, train                     // Models (evals: LAB-EVALS)
    case ship                             // Ship
    case learn                            // Learn
    public var id: String { rawValue }

    /// LAB-2332: a stored "history" (window state, menus, self-test fixtures, deep links) opens Trace, which holds
    /// History as its first tab. Written by hand so the synthesized Codable reads old values the same way.
    public init?(rawValue: String) {
        if rawValue == "history" { self = .trace; return }
        guard let p = Place.allCases.first(where: { $0.rawValue == rawValue }) else { return nil }
        self = p
    }

    public var title: String {
        switch self { case .home: return "Home"; case .needsYou: return "Inbox"; case .sessions: return "Sessions"; case .work: return "Projects"   // LAB-2049 (was Work); Resources: LAB-2039 (was Machine)
        case .agents: return "Agents"; case .factory: return "Factory"; case .loops: return "Loops"; case .trace: return "Trace"
        case .machine: return "Resources"; case .evals: return "Evals"; case .train: return "Train"; case .ship: return "Ship"; case .learn: return "Learn" }
    }
    public var symbol: String {
        switch self { case .home: return "house"; case .needsYou: return "tray"; case .sessions: return "rectangle.stack"; case .work: return "square.grid.2x2"
        case .agents: return "person.2"; case .factory: return "rectangle.3.group"; case .loops: return "arrow.triangle.2.circlepath"
        case .trace: return "waveform.path.ecg"; case .machine: return "gauge"; case .evals: return "chart.bar.xaxis"; case .train: return "brain"
        case .ship: return "shippingbox"; case .learn: return "graduationcap" }
    }
    /// LAB-2043: the Inbox's icon fills when something waits (tray → tray.full); the others never change.
    public func symbol(count: Int) -> String { self == .needsYou && count > 0 ? "tray.full" : symbol }
    /// Key for the ⌃⌘ place keys (KeymapV2.places). ⌘1–⌘6 stay Group by; ⌥⌘1–9 stay Workspaces.
    /// LAB-2044: an explicit table, not the rail order, so no place's key moves when the rail changes. LAB-2332: Trace
    /// takes History's ⌃⌘9; the new places take letters (Factory is ⌃⌘P, playbook: macOS keeps ⌃⌘F for full screen).
    public var controlKey: Character {
        switch self {
        case .home: return "1"; case .needsYou: return "2"; case .sessions: return "3"; case .work: return "4"; case .machine: return "5"
        case .loops: return "6"; case .learn: return "7"; case .evals: return "8"; case .trace: return "9"
        case .agents: return "A"; case .factory: return "P"; case .train: return "R"; case .ship: return "S"
        }
    }
    /// LAB-2332: the rail's six groups, in order; the rail leaves a gap and a hairline between them.
    public var group: PlaceGroup {
        switch self {
        case .home, .needsYou, .sessions, .work: return .work
        case .agents, .factory: return .agents
        case .loops, .trace, .machine: return .run
        case .evals, .train: return .models
        case .ship: return .ship
        case .learn: return .learn
        }
    }
    /// LAB-2332: places that are coming: their page is a placeholder (`PlannedPlaceCopy`) and the rail tags them.
    public var isPlanned: Bool { PlannedPlaceCopy.of(self) != nil }
    /// LAB-2332: the step-1 icon row in the toolbar shows these places; the rest are under its "more" menu (13 icons
    /// would not fit over the Sessions column).
    public static let iconRow: [Place] = [.home, .needsYou, .sessions, .work, .loops, .trace]
    /// Step a place opens at.
    public var defaultStep: FocusStep { self == .sessions ? .sessions : .full }
}

/// LAB-2332: the rail's groups (Work · Agents · Run · Models · Ship · Learn).
public enum PlaceGroup: String, CaseIterable, Sendable {
    case work, agents, run, models, ship, learn
    public var places: [Place] { Place.allCases.filter { $0.group == self } }
}

/// LAB-2332: the words on a planned place's page, in one table so the page and the tests read the same text.
public struct PlannedPlaceCopy: Equatable, Sendable {
    /// Where the nearest thing already lives today.
    public enum Link: Equatable, Sendable {
        case place(Place)
        case settings(pane: Int, name: String)
        case doc(title: String, path: String)
    }
    public let place: Place
    public let oneLine: String
    public let coming: [String]
    public let today: [(label: String, link: Link)]
    public let tickets: [String]

    public static func == (a: Self, b: Self) -> Bool {
        a.place == b.place && a.oneLine == b.oneLine && a.coming == b.coming && a.tickets == b.tickets
            && a.today.map(\.label) == b.today.map(\.label) && a.today.map(\.link) == b.today.map(\.link)
    }

    public static let tag = "Planned"
    /// A ticket's page in the connected Linear workspace (nil when none is connected: the id shows as text).
    public static func ticketURL(_ id: String, workspace: String?) -> URL? {
        guard let workspace, !workspace.isEmpty else { return nil }
        return URL(string: "https://linear.app/\(workspace)/issue/\(id)")
    }
    /// The workspace key from any Linear URL the app has loaded ("https://linear.app/<key>/project/…").
    public static func workspace(fromLinearURLs urls: [String]) -> String? {
        for u in urls {
            guard let c = URL(string: u), c.host == "linear.app" else { continue }
            let parts = c.path.split(separator: "/")
            if parts.count >= 2, let k = parts.first { return String(k) }
        }
        return nil
    }

    public static func of(_ p: Place) -> PlannedPlaceCopy? { all.first { $0.place == p } }

    /// Settings pane numbers (SettingsView.v2Panes): 2 = Seats & accounts, 11 = Evals.
    public static let all: [PlannedPlaceCopy] = [
        .init(place: .agents,
              oneLine: "The roster: every agent and account that can work for you, whether it is signed in, the limits left, cost, models and health.",
              coming: ["One row per agent and account: Claude (each account), Codex, Kimi, Gemini / Antigravity, open agents (OpenCode, Goose), hosted agents",
                       "Signed in or not, with the one command that signs it in",
                       "Limits left this 5 hours and this week, and what each has cost",
                       "The models each one can run, and its health from the last sessions"],
              today: [("Settings › Seats & accounts", .settings(pane: 2, name: "Seats & accounts")), ("Sessions", .place(.sessions))],
              tickets: ["LAB-2325"]),
        .init(place: .factory,
              oneLine: "The playbook: teams of agents for a kind of task, with the roles, the pattern they work in, the finish line and the budget, and running one on a task.",
              coming: ["A library of recipes, built-in and your own",
                       "A recipe's page: roles and the agent or model for each, the pattern drawn as steps, the finish line, past runs with cost and pass rate",
                       "Patterns: maker → checker, pipeline, fan-out → merge, two answers → judge, loop until the check passes",
                       "Run a recipe on a task: the orchestrator picks agents by capacity and cost, you approve the plan"],
              today: [("Sessions (start two agents by hand)", .place(.sessions)), ("Loops", .place(.loops))],
              tickets: ["LAB-1246", "LAB-2329", "LAB-1245", "LAB-198", "LAB-2330"]),
        .init(place: .train,
              oneLine: "Fine-tune, RL and pre-training jobs on GPUs, fed by what Evals finds.",
              coming: ["Start a fine-tune or RL job from an eval's failures",
                       "Where the GPUs come from (Modal, Hugging Face, your own) and what a job costs",
                       "Watch a job's loss and checkpoints, then send the new model back to Evals"],
              today: [("Evals", .place(.evals)), ("Settings › Evals", .settings(pane: 11, name: "Evals"))],
              tickets: ["LAB-2327"]),
        .init(place: .ship,
              oneLine: "live → lift → develop → main for many people and teams: releases and deploy status in one place.",
              coming: ["Every repo's live, develop and main, and what is waiting to ship",
                       "Lift, pull request and merge from one page, with the checks",
                       "Staging and production status from Woodpecker, Kargo and Argo CD",
                       "Releases: version, notes, who approved"],
              today: [("Projects", .place(.work)), ("The CI/CD runbook", .doc(title: "CI/CD runbook", path: "_common/docs/runbooks/20261020_01_cicd-woodpecker-kargo-argo.md"))],
              tickets: ["LAB-2328", "LAB-2308"]),
    ]
}

/// LAB-2044: Single · Grid · Wall arrange terminals only. Scroll (LAB-1831) left the switch and became the History place.
public enum SessionLayout: String, CaseIterable, Codable, Sendable { case single, grid, wall
    public var title: String { rawValue.capitalized }
    /// A saved layout, read back: "scroll" (One Roof 1.9.31–1.9.37) opens as Single; anything unknown is nil.
    public init?(stored: String) {
        if stored == "scroll" { self = .single; return }
        self.init(rawValue: stored)
    }
    public var defaultStep: FocusStep { self == .single ? .sessions : .wide }
}
