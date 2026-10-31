import Foundation

// LAB-1835 · the shared Learn page in One Roof's colours and fonts. The embed takes colour roles (bg panel panel2 line ink muted
// acc acc2 warn hot blue heat0-4, the shared-pages standard); the host page maps each role to a CSS variable
// `--or-<role>`, and these are their values from the centre theme, so a theme change re-colours the page without a re-mount.
public extension LearnShared {
    /// `--or-<role>` values for a theme.
    static func vars(_ t: ThemeTokens) -> [String: String] {
        let dark = t.isDark
        func css(_ c: RGB) -> String { c.over(t.window).css }
        let acc = css(t.accent), panel2 = css(t.surface2)
        func heat(_ p: Int) -> String { "color-mix(in srgb, \(acc) \(p)%, \(panel2))" }
        return [
            "bg": css(t.window), "panel": css(t.surface), "panel2": panel2,
            "line": css(t.separatorStrong), "ink": css(t.text), "muted": css(t.text2),
            "acc": acc, "acc2": css(t.selection),
            "warn": (dark ? RGB(0xFF9F0A) : RGB(0xC93400)).css,
            "hot": css(t.needsText), "blue": (dark ? RGB(0x64D2FF) : RGB(0x0A64D6)).css,
            "heat0": panel2, "heat1": heat(25), "heat2": heat(50), "heat3": heat(75), "heat4": acc,
        ]
    }

    /// One Roof's fonts (SF Pro for the interface, SF Mono for labels and code); the embed then loads no fonts of its own.
    static let fonts: [String: String] = [
        "sans": "-apple-system, BlinkMacSystemFont, \"SF Pro Text\", system-ui, sans-serif",
        "head": "-apple-system, BlinkMacSystemFont, \"SF Pro Display\", system-ui, sans-serif",
        "mono": "ui-monospace, \"SF Mono\", Menlo, monospace",
    ]

    /// The argument of `oneroofLearnMount(…)` as JSON: the colour variables, fonts and light/dark, and Settings › Learn ›
    /// Auto-advance (the page's Auto-next starts from it each time Learn opens or the setting changes).
    static func mountOptions(_ t: ThemeTokens, autoAdvance: Bool? = nil) -> String {
        var o: [String: Any] = ["vars": vars(t), "fonts": fonts, "dark": t.isDark]
        if let autoAdvance { o["autoAdvance"] = autoAdvance }
        let d = (try? JSONSerialization.data(withJSONObject: o, options: [.sortedKeys])) ?? Data("{}".utf8)
        return String(decoding: d, as: UTF8.self)
    }
}
