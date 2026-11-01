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
    // LAB-2044: History sits right under the Inbox on the rail (the live list, then its record).
    case home, needsYou, history, sessions, work, machine, loops, learn, evals   // evals: LAB-EVALS
    public var id: String { rawValue }
    public var title: String {
        switch self { case .home: return "Home"; case .needsYou: return "Inbox"; case .history: return "History"; case .sessions: return "Sessions"; case .work: return "Projects"   // LAB-2049 (was Work); Resources: LAB-2039 (was Machine)
        case .machine: return "Resources"; case .loops: return "Loops"; case .learn: return "Learn"; case .evals: return "Evals" }
    }
    public var symbol: String {
        switch self { case .home: return "house"; case .needsYou: return "tray"; case .history: return "clock.arrow.circlepath"; case .sessions: return "rectangle.stack"
        case .work: return "square.grid.2x2"; case .machine: return "gauge"; case .loops: return "arrow.triangle.2.circlepath"; case .learn: return "graduationcap"
        case .evals: return "chart.bar.xaxis" }
    }
    /// LAB-2043: the Inbox's icon fills when something waits (tray → tray.full); the others never change.
    public func symbol(count: Int) -> String { self == .needsYou && count > 0 ? "tray.full" : symbol }
    /// Digit for the ⌃⌘1–⌃⌘9 place keys (KeymapV2.places). ⌘1–⌘6 stay Group by; ⌥⌘1–9 stay Workspaces.
    /// LAB-2044: an explicit table, not the rail order, so History (⌃⌘9, second on the rail) moves no other place's key.
    public var controlKey: Character {
        switch self {
        case .home: return "1"; case .needsYou: return "2"; case .sessions: return "3"; case .work: return "4"; case .machine: return "5"
        case .loops: return "6"; case .learn: return "7"; case .evals: return "8"; case .history: return "9"
        }
    }
    /// Step a place opens at.
    public var defaultStep: FocusStep { self == .sessions ? .sessions : .full }
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
