import Foundation

/// Which main window (workspace) a session belongs to, and which windows come back at launch (LAB-705..708).
///
/// A session belongs to the window it was made in, or the one it was moved to, and only that window lists it. A
/// session whose window is closed waits for that window (Window › Workspaces reopens it); it never shows up in another
/// window's sidebar. Only a session with no window at all (started outside One Roof, or its workspace deleted) is
/// listed in the first open window.
public enum WindowMembership {
    /// The workspace a session belongs to: its assigned one when that workspace still exists (open or closed), else the
    /// first open window. `assigned` maps session id → workspace id; `existing` is every workspace id in the store.
    public static func home(of session: String, assigned: [String: String], open: [String], existing: Set<String>) -> String? {
        if let w = assigned[session], existing.contains(w) || open.contains(w) { return w }
        return open.first
    }

    /// The sessions one window lists, in the given order.
    public static func sessions(in window: String, _ ids: [String], assigned: [String: String], open: [String],
                                existing: Set<String>) -> [String] {
        ids.filter { home(of: $0, assigned: assigned, open: open, existing: existing) == window }
    }

    /// Whether a window that is closing should be remembered as closed. Not while the app quits (LAB-706: AppKit closes
    /// every window after `applicationWillTerminate`, which used to mark all but the last one closed, so only one came
    /// back), and not for the last window (closing it quits the app, and it should come back).
    public static func remembersClosed(quitting: Bool, otherOpenWindows: Int) -> Bool {
        !quitting && otherOpenWindows > 0
    }

    /// The workspaces to open at launch, in order: every one that was open; the first one if none was.
    public static func toRestore(_ workspaces: [(id: String, open: Bool)]) -> [String] {
        let open = workspaces.filter(\.open).map(\.id)
        if !open.isEmpty { return open }
        return workspaces.first.map { [$0.id] } ?? []
    }
}

/// What a pop-out window does when its terminal's attach ends (LAB-708). roofd lets one terminal show a session, so an
/// attach made while a main window still holds the session ends at once ("another terminal is showing this session").
public enum PopOutAttach: Equatable {
    /// Ended within moments of starting: refused; try again.
    case retry
    /// Refused every time: tell the owner and close.
    case giveUp
    /// Ran a while, then ended (the agent closed or detached): close the window.
    case ended

    /// Seconds within which an ended attach counts as refused.
    public static let refusedWithin: TimeInterval = 3

    public static func next(attempt: Int, ranFor seconds: TimeInterval, max: Int) -> PopOutAttach {
        guard seconds < refusedWithin else { return .ended }
        return attempt < max ? .retry : .giveUp
    }
}
