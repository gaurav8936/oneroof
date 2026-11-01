import Foundation

/// LAB-2109 · LAB-2107: one stable colour per session, the same in the Inbox (its session card and block edge), the
/// Decided rows and History (card edge and header), so a session looks the same everywhere. Picked from the row
/// pastels by the session id (FNV-1a, never Swift's per-launch hash), then fitted to the theme for contrast.
public struct SessionHue: Equatable, Sendable {
    /// A soft fill for the session card / header band.
    public var fill: RGB
    /// The edge bar and the session name on the fill (≥ 4.5:1 on the fill, ≥ 3:1 on the panel).
    public var ink: RGB
    public var pastel: String

    public static func pastel(for sessionId: String) -> Pastel {
        var h: UInt32 = 2166136261
        for b in sessionId.utf8 { h = (h ^ UInt32(b)) &* 16777619 }
        let p = Sticker.rowColors
        return p[Int(h % UInt32(p.count))]
    }

    /// LAB-2115: the same hue, worked out once per session × theme × panel and kept (History draws one per line while
    /// you scroll; working out the contrast fit each time cost frames). Main thread only.
    nonisolated(unsafe) private static var cache: [String: SessionHue] = [:]
    public static func cached(sessionId: String, on t: ThemeTokens, panel: RGB? = nil) -> SessionHue {
        let bg = panel ?? t.window
        let key = "\(sessionId)|\(t.name.rawValue)|\(t.isDark)|\(bg.hex),\(bg.alpha)"
        if let h = cache[key] { return h }
        let h = SessionHue(sessionId: sessionId, on: t, panel: panel)
        if cache.count > 4000 { cache.removeAll() }
        cache[key] = h
        return h
    }

    public init(sessionId: String, on t: ThemeTokens, panel: RGB? = nil) {
        let p = Self.pastel(for: sessionId)
        let bg = panel ?? t.window
        let fill = (t.isDark ? p.lightInk.opacity(0.28) : p.lightFill.opacity(0.75)).over(bg)
        var ink = t.isDark ? ThemeTokens.lighten(p.lightInk, until: 4.5, on: fill) : WindowAccent.darken(p.lightInk, until: 4.5, on: fill)
        if RGB.contrast(ink, bg) < 3 { ink = t.isDark ? ThemeTokens.lighten(ink, until: 3, on: bg) : WindowAccent.darken(ink, until: 3, on: bg) }
        self.fill = fill; self.ink = ink; self.pastel = p.name
    }
}
