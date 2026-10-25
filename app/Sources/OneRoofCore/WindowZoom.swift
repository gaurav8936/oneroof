import CoreGraphics

/// LAB-520 / LAB-596 / LAB-653: a main window's frame changes only when the owner changes it.
public enum WindowZoom {
    /// A title-bar (toolbar) double-click never shrinks a window; it may still grow one. LAB-520 only guarded a window
    /// that filled the screen, so a window tiled to half the screen still "zoomed" back to an older, smaller frame.
    /// Zoom from the menu or the green button is always allowed.
    public static func allow(current: CGRect, to new: CGRect, visible: CGRect?, fromTitleBarDoubleClick: Bool) -> Bool {
        guard fromTitleBarDoubleClick else { return true }
        let shrinks = new.width < current.width - 1 || new.height < current.height - 1
        return !shrinks
    }

    /// The click count a toolbar mouse event should carry. Two quick clicks on toolbar controls (the view tabs, the
    /// window name, the panel toggles) are two clicks, not a title-bar double-click: macOS would zoom or "fill" the
    /// window. Only empty toolbar space keeps the double-click.
    public static func toolbarClickCount(_ count: Int, at point: CGPoint, controls: [CGRect]) -> Int {
        guard count >= 2, controls.contains(where: { $0.contains(point) }) else { return count }
        return 1
    }
}

/// LAB-596 / LAB-653: the four panels' minimum widths. With every panel open they still fit the window's minimum
/// width, so opening a panel (or leaving the Editor, which reopens Plan with Files still open) never forces AppKit to
/// grow the window. Before: 240 + 200 + 420 + 260 = 1,120 pt in a window that may be 1,000 pt wide.
public enum PanelMinimums {
    public static let sessions: CGFloat = 240
    public static let files: CGFloat = 180
    public static let centre: CGFloat = 300
    public static let plan: CGFloat = 260
    /// The Editor folds Sessions to a rail of agent badges (S07 §1.1).
    public static let sessionsRail: CGFloat = 56
    public static let windowWidth: CGFloat = 1000
    public static let divider: CGFloat = 1

    /// Everything open, with the dividers between them.
    public static var allOpen: CGFloat { sessions + files + centre + plan + 3 * divider }
}

/// LAB-651 / LAB-714: the Sessions panel draws its narrow rail of agent badges only when it is actually narrow. It
/// used to follow the centre view (Editor = rail), so after opening any file the panel stayed a column of icons
/// however wide it was dragged, and never "expanded".
public enum SessionsRail {
    /// Narrower than this, the full list cannot show its rows; the rail is 56 pt and the full panel at least 240 pt.
    public static let maxWidth: CGFloat = 160
    public static func shows(width: CGFloat) -> Bool { width > 0 && width < maxWidth }
}

/// LAB-715: which toolbar items give way first when the window is too narrow for all of them. The panel toggles
/// (Sessions · Files · Terminal · Plan) are the last to go; the window name and the search field go first (search has
/// ⌘K, the name is in the Window menu). Whatever does not fit sits behind the toolbar's » menu, which works.
public enum ToolbarSlot: String, CaseIterable, Sendable {
    case switcher, workspace, search, panels, new

    /// Higher stays visible longer (maps onto NSToolbarItem.VisibilityPriority).
    public var keepRank: Int {
        switch self {
        case .panels: return 3
        case .switcher, .new: return 2
        case .workspace: return 1
        case .search: return 0
        }
    }
}
