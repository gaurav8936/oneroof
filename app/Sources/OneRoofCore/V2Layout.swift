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
    /// Sessions, 250 pt at Full and Wide), within the column's limits; Focus is always 52 pt avatars.
    public static func columnWidth(step: FocusStep, saved: Double?) -> Double {
        if step == .focus { return 52 }
        if let saved, saved > 0 { return min(440, max(200, saved)) }
        return step == .sessions ? 280 : 250
    }

    /// Plan inspector width at Full: the dragged width (kept per window), else 270 pt, within 240–520.
    public static func planWidth(saved: Double?) -> Double {
        if let saved, saved > 0 { return min(520, max(240, saved)) }
        return 270
    }
}
