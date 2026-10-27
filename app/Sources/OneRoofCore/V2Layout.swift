import Foundation

/// 1.8.1 real-profile audit: the pure rules behind the v2 window's launch state and column widths (FOCUS_LADDER.md),
/// kept here so they are tested.
public enum V2Layout {
    /// The step a window opens at. A saved step wins. A window that already existed in 0.5.2.9 (it has a saved pane
    /// layout from the classic window) opens once at Full: rail, session column, the Plan inspector and the full dock,
    /// the closest match to the four panels it had, so nothing it showed is hidden on the first launch after the
    /// upgrade. A new window opens at Sessions (step 1), as the handover says.
    public static func initialStep(saved: Int?, existedBefore: Bool) -> FocusStep {
        if let saved, let s = FocusStep(rawValue: saved) { return s }
        return existedBefore ? .full : .sessions
    }

    /// The step a place opens at: Sessions returns to the step it was last at (step 1 the first time), the other
    /// places open at their default (FOCUS_LADDER.md).
    public static func openingStep(_ place: Place, sessionsStep: FocusStep?) -> FocusStep {
        place == .sessions ? (sessionsStep ?? .sessions) : place.defaultStep
    }

    /// The rows of a capped group ("+ n more ›"): the first `cap`, plus any of `keep` (the selected row) further down,
    /// in list order, so the session you are on never disappears behind the cap.
    public static func cappedRows<T>(_ rows: [T], cap: Int, id: (T) -> String, keep: Set<String>) -> [T] {
        guard rows.count > cap else { return rows }
        return rows.enumerated().filter { $0.offset < cap || keep.contains(id($0.element)) }.map(\.element)
    }

    /// Session column width at a step: the width you dragged it to (kept per window), else the handover's (280 pt at
    /// Sessions, 250 pt at Full and Wide), within the column's limits; Focus is 52 pt avatars unless the lane was
    /// dragged wide (`focusWide`, LAB-1366).
    public static func columnWidth(step: FocusStep, saved: Double?, focusWide: Double? = nil) -> Double {
        if step == .focus { return focusWide.map { min(440, max(200, $0)) } ?? 52 }
        if let saved, saved > 0 { return min(440, max(200, saved)) }
        return step == .sessions ? 280 : 250
    }

    /// LAB-1366: the Focus lane's width after a drag: back to the avatars (nil) below the snap point, else the full
    /// list within the column's limits.
    public static let focusLaneSnapPoint: Double = 130
    public static func focusLaneSnap(dragged: Double) -> Double? {
        dragged < focusLaneSnapPoint ? nil : min(440, max(200, dragged))
    }

    /// LAB-1363: whether the terminal shows "Current ↓": scrolled up from the live bottom (libghostty has reported
    /// a position and it is not the bottom), and the pane shows the live terminal (not the Table view or raw stream).
    public static func showsCurrentPill(atBottom: Bool?, raw: Bool, table: Bool) -> Bool {
        atBottom == false && !raw && !table
    }

    /// LAB-1363: terminal keys added to libghostty's defaults: ⌘↓ / ⌘↑ jump to the live bottom / the top, as in
    /// Terminal and Warp. Bound in the terminal (not a menu) so the editor and composer keep ⌘↓ for themselves.
    public static let terminalKeybinds = """
    keybind = super+arrow_down=scroll_to_bottom
    keybind = super+arrow_up=scroll_to_top
    """

    /// LAB-1367 / LAB-1368: seconds the pointer rests at a window edge at Focus before the session column (left) or
    /// the Plan (right) slides in. Opening on contact made them flash while the pointer just passed the edge.
    public static let edgeRevealDwell: TimeInterval = 1.0

    /// Plan inspector width at Full: the dragged width (kept per window), else 270 pt, within 240–520.
    public static func planWidth(saved: Double?) -> Double {
        if let saved, saved > 0 { return min(520, max(240, saved)) }
        return 270
    }

    // MARK: Narrow windows (1.8.2, LAB-831 / LAB-1237)

    /// The v2 window's smallest width: about a third of a laptop screen. The classic window keeps
    /// `PanelMinimums.windowWidth` (its four panels need it).
    public static let minWindowWidth: Double = 600
    public static let railWidth: Double = 66
    public static let columnMin: Double = 200
    public static let centreMin: Double = 300
    public static let planMin: Double = 240
    public static let planEdge: Double = 28

    /// At Full the Plan inspector shows in its column only while rail + column + a usable centre + the inspector fit;
    /// narrower, it folds to its 28 pt edge tab (the Plan then slides over the terminal, as at steps 1-2). Judged on
    /// the window width and the column's chosen width, never on live frames, so it cannot flap while you resize.
    public static func planFits(windowWidth: Double, rail: Bool, column: Double) -> Bool {
        windowWidth >= (rail ? railWidth : 0) + max(columnMin, column) + centreMin + planMin + 4
    }

    /// The narrowest window each step needs with the Plan folded: rail, the column at its minimum, the edge tab and
    /// the centre's minimum. Every value fits `minWindowWidth`, so AppKit never grows the window (LAB-596).
    public static func narrowestFit(step: FocusStep) -> Double {
        switch step {
        case .full, .wide: return railWidth + columnMin + planEdge + centreMin + 4
        case .sessions: return columnMin + planEdge + centreMin + 4
        case .focus: return 52 + centreMin + 4
        }
    }

    /// What the toolbar shows right of the session column (LAB-1237): the right group (Single · Grid · Wall, the
    /// Focus step button, + New) never clips. As the room shrinks the title truncates first, then the subtitle and
    /// the step button's shortcut go, then Single · Grid · Wall (View menu, ⌃⌥⌘1-3), and the title last. + New and
    /// the step button always show.
    public struct ToolbarFit: Equatable, Sendable {
        public var titleWidth: Double
        public var subtitle: Bool
        public var shortcuts: Bool
        public var layoutControl: Bool
        public init(titleWidth: Double, subtitle: Bool, shortcuts: Bool, layoutControl: Bool) {
            self.titleWidth = titleWidth; self.subtitle = subtitle; self.shortcuts = shortcuts; self.layoutControl = layoutControl
        }
    }

    /// Measured widths of the toolbar pieces (points, 1.8.2 captures), with the toolbar's 10 pt item gap.
    public enum Bar {
        public static let layout: Double = 140, stepFull: Double = 136, stepShort: Double = 102, new: Double = 86
        public static let gap: Double = 10, trailing: Double = 14, titleLead: Double = 8, slack: Double = 16
        /// After the column's tracking separator the toolbar starts its next item this far in.
        public static let sectionLead: Double = 32
        /// The traffic lights; the icon row (step 1) starts after them.
        public static let lights: Double = 84
        /// The places icon row: 4 + 7 × 26 + 6 × 2 and the item's own gap.
        public static let placesRow: Double = 208
    }

    /// Where the toolbar's centre section starts: after the column's divider, or after the traffic lights and the
    /// icon row when they reach further.
    public static func toolbarStart(divider: Double, placesRow: Bool) -> Double {
        max(divider, Bar.lights + (placesRow ? Bar.placesRow : 0)) + Bar.sectionLead
    }

    /// `room`: the width from the centre section's start to the window's right edge; `extras`: the Learn player /
    /// Run · Debug width (0 when they are not shown).
    public static func toolbarFit(room: Double, extras: Double = 0) -> ToolbarFit {
        let fixed = Bar.trailing + Bar.new + Bar.gap + (extras > 0 ? extras + Bar.gap : 0) + Bar.titleLead + Bar.slack
        let avail = room - fixed
        func fit(_ shortcuts: Bool, _ layout: Bool) -> Double {
            avail - (shortcuts ? Bar.stepFull : Bar.stepShort) - Bar.gap - (layout ? Bar.layout + Bar.gap : 0)
        }
        let title: Double, shortcuts: Bool, layout: Bool
        if fit(true, true) >= 200 { (title, shortcuts, layout) = (fit(true, true), true, true) }
        else if fit(false, true) >= 140 { (title, shortcuts, layout) = (fit(false, true), false, true) }
        else { (title, shortcuts, layout) = (fit(false, false), false, false) }
        let w = min(620, max(0, title))
        return ToolbarFit(titleWidth: w < 48 ? 0 : w, subtitle: w >= 300, shortcuts: shortcuts, layoutControl: layout)
    }
}
