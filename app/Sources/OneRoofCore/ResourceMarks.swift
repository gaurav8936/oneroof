import Foundation

// LAB-2052 · Resources keeps its layout and gets colours you can read. Bars, sparklines, the warn tick, the leftover
// (warning) rows, the hover highlight and the status pill edges on that page come from here, per theme, so their
// contrast is tested (ResourcesContrastTests) instead of judged by eye:
//   text ≥ 4.5:1 on the surface it sits on · bar fill ≥ 3:1 against its track and the card · track ≥ 1.5:1 against the
//   card · sparkline line ≥ 3:1 · warn tick ≥ 3:1 · pill edge ≥ 3:1 · hover ≥ 1.3:1 against its row.

/// The marks Resources draws, for one theme.
public struct ResourceMarks: Equatable, Sendable {
    /// The card everything sits on (Card's fill).
    public var card: RGB
    /// An opened app's process panel (was surface2 at 50 %; LAB-2052: full strength).
    public var panel: RGB
    /// The empty part of a bar (Meter, HeadroomBar).
    public var track: RGB
    /// A bar's fill and the memory / CPU sparkline line while all is well.
    public var bar: RGB
    /// Over the warning line.
    public var warn: RGB
    /// Near the limit (the last 10 %).
    public var near: RGB
    /// The warn tick on HeadroomBar.
    public var tick: RGB
    /// A leftover or warning row's background: `now` at 0.14 over the card (opaque, so it can be tested).
    public var nowTint: RGB
    /// The amber text on that tint (the amount, the ● glyph).
    public var nowText: RGB
    /// The 3 pt bar on a warning row's leading edge.
    public var nowBar: RGB
    /// The edge drawn round a status pill on this page (pills with no fill or no edge get one).
    public var pillEdge: RGB
    /// Sparkline fill under the line.
    public static let sparkFill = 0.22
    public static let sparkLine: Double = 2
    public static let barHeight: Double = 6
    public static let nowTintAlpha = 0.14

    /// A hover highlight that reads at ≥ 1.3:1 against `bg` (the selection token at 50 % was ~1.1:1 on a white card):
    /// the theme's text over a light row, white over a dark one, just strong enough.
    public static func hover(over bg: RGB, dark: Bool) -> RGB {
        let ink = dark ? RGB(0xFFFFFF) : RGB(0x1C1C1E)
        var a = 0.04
        var out = ink.opacity(a).over(bg)
        while RGB.contrast(out, bg) < 1.3 && a < 1 {
            a += 0.01
            out = ink.opacity(a).over(bg)
        }
        return out
    }
}

public extension ThemeTokens {
    /// LAB-2052 · Resources' marks on this theme.
    var resourceMarks: ResourceMarks {
        let card = surface
        let track: RGB
        switch name {
        case _ where !isDark: track = text.opacity(0.22).over(card)              // a grey you can see on white or a pastel
        case .graphite: track = RGB(0x000000, alpha: 0.6).over(card)            // darker than the lighter Graphite card
        default: track = RGB(0xFFFFFF, alpha: 0.18).over(card)                  // lighter than the near-black Midnight card
        }
        let tint = now.opacity(ResourceMarks.nowTintAlpha).over(card)
        return ResourceMarks(card: card, panel: surface2, track: track, bar: accentText, warn: now, near: needsText,
                             tick: text2, nowTint: tint, nowText: now, nowBar: now, pillEdge: separatorStrong)
    }
}
