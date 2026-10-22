import CoreGraphics

/// LAB-520: when a title-bar (toolbar) double-click may zoom a window.
public enum WindowZoom {
    /// A double-click never shrinks a window that already fills (nearly all of) the screen; it may still grow one.
    /// Zoom from the menu or the green button is always allowed.
    public static func allow(current: CGRect, to new: CGRect, visible: CGRect?, fromTitleBarDoubleClick: Bool) -> Bool {
        guard fromTitleBarDoubleClick, let v = visible, v.width > 0, v.height > 0 else { return true }
        let fills = current.width >= v.width * 0.95 && current.height >= v.height * 0.95
        let shrinks = new.width < current.width - 1 || new.height < current.height - 1
        return !(fills && shrinks)
    }
}
