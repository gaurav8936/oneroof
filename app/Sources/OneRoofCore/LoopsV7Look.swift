import Foundation

// LAB-ONEROOF-v2.0.6 · Loops v7 (handover theme/tokens.md): the five kind colours (kind name, kind tag and lane bar
// only) and the state colours (failing red, needs-you amber, running blue, fine green, trial violet, off grey; only for
// states). Light looks use the handover's values (darkened where a value missed 4.5:1); Graphite and Midnight get their
// own steps. Contrast-tested in LoopsV7LandingTests (text 4.5:1 on its fill and on the card, marks 3:1 on the card).
extension LoopLook {
    /// A colour pair: text (or a mark) and the fill it sits on.
    public struct Pair: Equatable, Sendable {
        public var text: RGB
        public var fill: RGB
        public init(text: RGB, fill: RGB) { self.text = text; self.fill = fill }
    }

    /// The colour of a kind: Watch · Check · Improve · Report · Other.
    public static func kind(_ family: String, theme: ThemeName) -> Pair {
        let k = theme.tokens
        if !theme.isDark {
            let text: RGB
            switch family {
            case "watch": text = RGB(0x1D4FD0)   // handover #2563EB, one step darker for 4.5:1 on its fill
            case "check": text = RGB(0x0D6A4C)   // handover #12805C, one step darker
            case "improve": text = RGB(0x6D4AE0)
            case "report": text = RGB(0x8F5600)   // handover #B26A00 reads 3.9:1 on its fill; one step darker
            default: text = RGB(0x5A6476)
            }
            return Pair(text: text, fill: text.opacity(0.10).over(k.surface))
        }
        let text: RGB
        switch family {
        case "watch": text = RGB(0xA8C6FF)
        case "check": text = RGB(0x7FE0BC)
        case "improve": text = RGB(0xD2C4FF)
        case "report": text = RGB(0xFFC562)
        default: text = RGB(0xCBD1DB)
        }
        return Pair(text: text, fill: text.opacity(0.13).over(k.surface))
    }

    /// The states v7 colours (never used for kinds).
    public enum Tone: String, CaseIterable, Equatable, Sendable { case failing, needsYou, running, fine, trial, off }

    public static func tone(_ s: Tone, theme: ThemeName) -> Pair {
        let k = theme.tokens
        let dark = theme.isDark
        switch s {
        case .failing: return Pair(text: k.needsText, fill: dark ? RGB(rgba: 0xFF453A1C).over(k.surface) : RGB(0xFDECEC))
        case .needsYou: return Pair(text: dark ? RGB(0xFFD60A) : RGB(0x8A5A00), fill: dark ? RGB(rgba: 0xFFD60A24).over(k.surface) : RGB(0xFFF4DD))
        case .running: return Pair(text: k.accentText, fill: dark ? RGB(rgba: 0x0A84FF33).over(k.surface) : RGB(0xE6EFFC))
        case .fine: return Pair(text: k.statusDone, fill: dark ? RGB(rgba: 0x30D1581C).over(k.surface) : RGB(0xE9F8EE))
        case .trial: return Pair(text: dark ? RGB(0xC2B0FF) : RGB(0x6D4AE0), fill: dark ? RGB(rgba: 0x8E6CFF33).over(k.surface) : RGB(0xEFEAFE))
        case .off: return Pair(text: k.text2, fill: k.control.over(k.surface))
        }
    }

    /// A loop row's dot: failing red, running blue, missed amber, trial violet, fine green, off grey.
    public static func dot(_ s: LoopRow.State, theme: ThemeName) -> RGB {
        switch s {
        case .failing: return tone(.failing, theme: theme).text
        case .running: return tone(.running, theme: theme).text
        case .missed: return tone(.needsYou, theme: theme).text
        case .trial: return tone(.trial, theme: theme).text
        case .fine, .notRun: return tone(.fine, theme: theme).text
        case .off: return theme.tokens.text3
        }
    }

    /// One mark of the last-runs strip: a fill (nil = outline only), an edge, and its height as a share of the strip.
    public struct StripMark: Equatable, Sendable {
        public var fill: RGB?
        public var edge: PillEdge
        public var height: Double
    }

    /// passed green · failed red · trial grey at 60 % height · missed dashed amber · not run dashed grey · to come outline.
    /// Strong colours, never faded (LAB-2056), so each mark reads at 3:1 on the card.
    public static func strip(_ r: LoopRun7.Result, theme: ThemeName) -> StripMark {
        let k = theme.tokens
        switch r {
        case .passed: return StripMark(fill: k.statusDone, edge: .none, height: 1)
        case .failed: return StripMark(fill: k.needsText, edge: .none, height: 1)
        case .trial: return StripMark(fill: unknownBar(theme), edge: .none, height: 0.6)
        case .missed: return StripMark(fill: nil, edge: .dashed(tone(.needsYou, theme: theme).text), height: 1)
        case .notRun: return StripMark(fill: nil, edge: .dashed(k.separatorStrong), height: 1)
        case .toCome: return StripMark(fill: nil, edge: .solid(k.separatorStrong), height: 1)
        }
    }

    /// The words for a loop's on/off and mode, from the engine that runs it (LP-1, LAB-2278): "On · live",
    /// "On · trial", "Off"; "kit state unknown" when the kit could not be read. nil for a One Roof loop that is on
    /// (its own state chip says more: Running, Needs you, Waiting …).
    public static func onLabel(_ r: LoopRow, kitKnown: Bool) -> String? {
        if r.engine == .kit {
            if !kitKnown { return "kit state unknown" }
            return r.on ? (r.mode == .shadow ? "On · trial" : "On · live") : "Off"
        }
        return r.on ? nil : "Off"
    }

    /// The tone of `onLabel`.
    public static func onTone(_ r: LoopRow, kitKnown: Bool) -> Tone {
        guard r.engine != .kit || kitKnown, r.on else { return .off }
        switch r.state {
        case .failing: return .failing
        case .missed: return .needsYou
        case .running: return .running
        default: return r.mode == .shadow ? .trial : .fine
        }
    }
}
