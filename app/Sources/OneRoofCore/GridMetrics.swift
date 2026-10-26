import CoreGraphics
import Foundation

/// Grid layout sizes (LAB-1239, owner decision 2026-10-26): two columns, one row per two live sessions, and every tile
/// at least `minTileHeight` tall, so a tile always has room for its header, the Right now line, a few terminal lines
/// and the composer. When the rows do not fit, the terminal area is taller than the window and scrolls.
public enum GridMetrics {
    public static let columns = 2
    /// Header 36 + Right now 32 + two step rows 72 + composer 48 + about eight terminal lines.
    public static let minTileHeight: CGFloat = 330

    /// Rows for `sessions` tiles in `columns` columns (at least one row).
    public static func rows(sessions: Int, columns: Int = GridMetrics.columns) -> Int {
        let c = max(1, columns)
        return max(1, (max(0, sessions) + c - 1) / c)
    }

    /// Height of the laid-out grid: the viewport when the rows fit at `minTile` each, else the rows at `minTile` plus
    /// the gaps between them (the area then scrolls).
    public static func contentHeight(rows: Int, viewport: CGFloat, minTile: CGFloat = minTileHeight, gap: CGFloat) -> CGFloat {
        let r = CGFloat(max(1, rows))
        return max(viewport, r * minTile + (r - 1) * gap)
    }

    /// Where to scroll so `frame` (a tile, top-left origin) is fully visible in a viewport showing `visible`, moving
    /// as little as possible; a tile taller than the viewport shows its top.
    public static func scrollOffset(showing frame: CGRect, visible: CGRect) -> CGFloat {
        if frame.minY < visible.minY || frame.height > visible.height { return frame.minY }
        if frame.maxY > visible.maxY { return frame.maxY - visible.height }
        return visible.minY
    }
}
