import Foundation

/// A window's accent (LAB-509 / LAB-590): the colour picked for its workspace (one of `Sticker.rowColors`, the same
/// pastels the row colours and the pastel themes use) tints the toolbar band and draws the window name and a stripe
/// in its ink, so with several windows open each is told apart at a glance. Without a colour the window looks as
/// before. Pure colour maths, so every pastel × theme pair is contrast-tested.
public struct WindowAccent: Equatable, Sendable {
    /// The toolbar band behind the title bar.
    public var band: RGB
    /// The window name and the stripe under the band.
    public var ink: RGB

    /// The accent for a window coloured `pastel`, on a Sessions panel in theme `t`. The tint starts soft and fades
    /// further until the toolbar's secondary and tertiary text still read on it (text2 4.5:1, text3 3:1).
    public init(_ pastel: Pastel, on t: ThemeTokens) {
        func band(_ a: Double) -> RGB {
            (t.isDark ? pastel.lightInk.opacity(a * 0.6) : pastel.lightFill.opacity(a)).over(t.toolbar)
        }
        var a = 0.7
        var b = band(a)
        while a > 0, RGB.contrast(t.text3, b) < 3 || RGB.contrast(t.text2, b) < 4.5 || RGB.contrast(t.text, b) < 7 {
            a -= 0.05
            b = band(max(a, 0))
        }
        self.band = b
        self.ink = t.isDark ? ThemeTokens.lighten(pastel.lightInk, until: 4.5, on: b) : Self.darken(pastel.lightInk, until: 4.5, on: b)
    }

    /// The accent for a stored colour name; nil (no accent, the default look) when unset or unknown.
    public init?(named name: String?, on t: ThemeTokens) {
        guard let p = Pastel.named(name) else { return nil }
        self.init(p, on: t)
    }

    /// Blend towards black until `ratio` against `bg` (the pastel inks already read on their fills; this is a guard).
    static func darken(_ c: RGB, until ratio: Double, on bg: RGB) -> RGB {
        var t = 0.0
        var out = c
        while RGB.contrast(out, bg) < ratio && t < 1 {
            t += 0.04
            out = RGB(0x000000, alpha: t).over(c)
        }
        return out
    }
}

/// A window's name as the owner typed it (LAB-509): trimmed, inner runs of spaces and line breaks folded to one
/// space, at most `maxLength` characters (it is drawn big in the toolbar). nil for an empty name (keep the old one).
public enum WindowName {
    public static let maxLength = 40

    public static func clean(_ raw: String) -> String? {
        let words = raw.split(whereSeparator: { $0.isWhitespace || $0.isNewline })
        guard !words.isEmpty else { return nil }
        let s = words.joined(separator: " ")
        return s.count > maxLength ? String(s.prefix(maxLength)).trimmingCharacters(in: .whitespaces) : s
    }
}
