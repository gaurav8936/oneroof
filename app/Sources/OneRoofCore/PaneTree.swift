import CoreGraphics
import Foundation

/// Split panes in the centre: a binary tree of panes, each showing one session (or empty, waiting for the
/// owner to pick one). Pure value type: the terminal area draws it, tests check it.
public struct PaneLeaf: Codable, Equatable, Sendable {
    public var id: String
    public var session: String?
    public init(id: String = UUID().uuidString, session: String? = nil) { self.id = id; self.session = session }
}

public indirect enum PaneNode: Codable, Equatable, Sendable {
    /// Grid layout (handover A4.1, NEW-2; LAB-1239): always `columns` (2) tiles across and as many rows as the sessions
    /// need, filled with `sessions` in order (nil = an empty tile; an odd count leaves the last tile empty, no sessions
    /// = one row of two empty tiles). Rows split top / bottom in equal shares, each row splits into equal columns. When
    /// the rows do not fit the window, the terminal area scrolls (`GridMetrics`).
    public static func grid(_ sessions: [String?], columns: Int) -> PaneNode {
        let cols = max(1, columns)
        let rows = GridMetrics.rows(sessions: sessions.count, columns: cols)
        var cells = Array(sessions.prefix(cols * rows))
        while cells.count < cols * rows { cells.append(nil) }
        let rowNodes = (0..<rows).map { r in
            chain((0..<cols).map { c in PaneNode.leaf(PaneLeaf(id: "grid-\(r * cols + c)", session: cells[r * cols + c])) }, sideBySide: true)
        }
        return chain(rowNodes, sideBySide: false)
    }

    /// `a | (b | (c …))` with ratios that give every node an equal share.
    static func chain(_ nodes: [PaneNode], sideBySide: Bool) -> PaneNode {
        nodes.dropLast().reversed().reduce(nodes.last!) { acc, n in
            let k = Double(acc.chainCount(sideBySide: sideBySide) + 1)
            return .split(sideBySide: sideBySide, ratio: 1 / k, n, acc)
        }
    }

    /// How many nodes a chain along one axis holds (`a | (b | c)` = 3): for the Grid, its rows (`sideBySide: false`).
    public func chainCount(sideBySide: Bool) -> Int {
        if case .split(let s, _, _, let b) = self, s == sideBySide { return 1 + b.chainCount(sideBySide: sideBySide) }
        return 1
    }

    case leaf(PaneLeaf)
    /// `sideBySide`: first on the left, second on the right; else first on top. `ratio` = the first child's share.
    case split(sideBySide: Bool, ratio: Double, PaneNode, PaneNode)

    public enum Direction: Sendable { case left, right, up, down }

    public var leaves: [PaneLeaf] {
        switch self {
        case .leaf(let l): return [l]
        case .split(_, _, let a, let b): return a.leaves + b.leaves
        }
    }

    public func leaf(_ id: String) -> PaneLeaf? { leaves.first { $0.id == id } }
    public func leafShowing(_ session: String) -> PaneLeaf? { leaves.first { $0.session == session } }

    /// Same tree with `id` replaced by a split of it and `new` (placed right of it or below it).
    public func splitting(_ id: String, sideBySide: Bool, new: PaneLeaf) -> PaneNode {
        switch self {
        case .leaf(let l) where l.id == id: return .split(sideBySide: sideBySide, ratio: 0.5, self, .leaf(new))
        case .leaf: return self
        case .split(let s, let r, let a, let b):
            return .split(sideBySide: s, ratio: r, a.splitting(id, sideBySide: sideBySide, new: new), b.splitting(id, sideBySide: sideBySide, new: new))
        }
    }

    /// Same tree without pane `id` (its sibling takes the space); nil if it was the only pane.
    public func removing(_ id: String) -> PaneNode? {
        switch self {
        case .leaf(let l): return l.id == id ? nil : self
        case .split(let s, let r, let a, let b):
            guard let a2 = a.removing(id) else { return b }
            guard let b2 = b.removing(id) else { return a }
            return .split(sideBySide: s, ratio: r, a2, b2)
        }
    }

    public func setting(_ id: String, session: String?) -> PaneNode {
        switch self {
        case .leaf(var l):
            if l.id == id { l.session = session }
            return .leaf(l)
        case .split(let s, let r, let a, let b):
            return .split(sideBySide: s, ratio: r, a.setting(id, session: session), b.setting(id, session: session))
        }
    }

    /// Every split back to half and half.
    public func evened() -> PaneNode {
        switch self {
        case .leaf: return self
        case .split(let s, _, let a, let b): return .split(sideBySide: s, ratio: 0.5, a.evened(), b.evened())
        }
    }

    /// Change the ratio of the split at `path` (false = first child, true = second), clamped to 10–90 %.
    public func settingRatio(at path: [Bool], _ ratio: Double) -> PaneNode {
        guard case .split(let s, let r, let a, let b) = self else { return self }
        guard let step = path.first else { return .split(sideBySide: s, ratio: min(max(ratio, 0.1), 0.9), a, b) }
        let rest = Array(path.dropFirst())
        return step ? .split(sideBySide: s, ratio: r, a, b.settingRatio(at: rest, ratio))
                    : .split(sideBySide: s, ratio: r, a.settingRatio(at: rest, ratio), b)
    }

    /// A draggable divider: which split it belongs to, its rectangle, and the rectangle of the whole split.
    public struct Divider: Equatable, Sendable {
        public var path: [Bool]
        public var sideBySide: Bool
        public var rect: CGRect
        public var parent: CGRect
    }

    /// Frames of every pane and divider inside `rect` (origin top-left, y grows down), `gap` points between panes.
    public func layout(in rect: CGRect, gap: CGFloat = 1) -> (panes: [String: CGRect], dividers: [Divider]) {
        var panes: [String: CGRect] = [:]
        var dividers: [Divider] = []
        func walk(_ n: PaneNode, _ r: CGRect, _ path: [Bool]) {
            switch n {
            case .leaf(let l): panes[l.id] = r
            case .split(let s, let ratio, let a, let b):
                if s {
                    let w = ((r.width - gap) * ratio).rounded()
                    walk(a, CGRect(x: r.minX, y: r.minY, width: w, height: r.height), path + [false])
                    walk(b, CGRect(x: r.minX + w + gap, y: r.minY, width: r.width - w - gap, height: r.height), path + [true])
                    dividers.append(Divider(path: path, sideBySide: true, rect: CGRect(x: r.minX + w, y: r.minY, width: gap, height: r.height), parent: r))
                } else {
                    let h = ((r.height - gap) * ratio).rounded()
                    walk(a, CGRect(x: r.minX, y: r.minY, width: r.width, height: h), path + [false])
                    walk(b, CGRect(x: r.minX, y: r.minY + h + gap, width: r.width, height: r.height - h - gap), path + [true])
                    dividers.append(Divider(path: path, sideBySide: false, rect: CGRect(x: r.minX, y: r.minY + h, width: r.width, height: gap), parent: r))
                }
            }
        }
        walk(self, rect, [])
        return (panes, dividers)
    }

    /// The pane next to `id` in a direction (for ⌘⌥ + arrow): the nearest one that overlaps it on the other axis.
    public func neighbor(of id: String, _ d: Direction) -> String? {
        let frames = layout(in: CGRect(x: 0, y: 0, width: 1000, height: 1000), gap: 0).panes
        guard let me = frames[id] else { return nil }
        let candidates = frames.filter { key, f in
            guard key != id else { return false }
            switch d {
            case .left: return f.maxX <= me.minX + 0.5 && f.minY < me.maxY && f.maxY > me.minY
            case .right: return f.minX >= me.maxX - 0.5 && f.minY < me.maxY && f.maxY > me.minY
            case .up: return f.maxY <= me.minY + 0.5 && f.minX < me.maxX && f.maxX > me.minX
            case .down: return f.minY >= me.maxY - 0.5 && f.minX < me.maxX && f.maxX > me.minX
            }
        }
        func distance(_ f: CGRect) -> CGFloat {
            switch d {
            case .left: return me.minX - f.maxX + abs(f.midY - me.midY) / 1000
            case .right: return f.minX - me.maxX + abs(f.midY - me.midY) / 1000
            case .up: return me.minY - f.maxY + abs(f.midX - me.midX) / 1000
            case .down: return f.minY - me.maxY + abs(f.midX - me.midX) / 1000
            }
        }
        // Ties (two panes equally near) go to the top-most, then left-most one.
        return candidates.min { x, y in
            let dx = distance(x.value), dy = distance(y.value)
            return dx != dy ? dx < dy : (x.value.minY, x.value.minX) < (y.value.minY, y.value.minX)
        }?.key
    }
}
