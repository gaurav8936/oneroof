import Foundation

/// One Roof v2 themes (UI v2 packet, theme/tokens.json): Daylight · Graphite · Midnight, chosen per panel, so a light
/// sessions panel can sit next to a dark terminal ("Apple meets terminal"). Paper is retired (owner, 2026-10-18: "no
/// off-white paper"); Blueprint stays as a hidden terminal-only theme.
public enum ThemeName: String, CaseIterable, Identifiable, Codable, Sendable {
    case daylight, graphite, midnight, blueprint
    public var id: String { rawValue }
    public var label: String { rawValue.capitalized }
    public var isDark: Bool { self != .daylight }
    /// The themes offered for panels and centre views; Blueprint only for the terminal.
    public static let panelChoices: [ThemeName] = [.daylight, .graphite, .midnight]
    public static let terminalChoices: [ThemeName] = [.daylight, .graphite, .midnight, .blueprint]
    /// What a light theme turns into while the panels follow macOS Dark Mode.
    public var darkTwin: ThemeName { self == .daylight ? .midnight : self }

    /// v0.1 names map onto v2: Light and Paper → Daylight, Dim → Graphite, Dark → Midnight.
    public init?(stored: String) {
        switch stored {
        case "light", "paper": self = .daylight
        case "dim": self = .graphite
        case "dark": self = .midnight
        default:
            guard let t = ThemeName(rawValue: stored) else { return nil }
            self = t
        }
    }

    public init(from d: Decoder) throws {
        let s = try d.singleValueContainer().decode(String.self)
        guard let t = ThemeName(stored: s) else {
            throw DecodingError.dataCorrupted(.init(codingPath: d.codingPath, debugDescription: "unknown theme \(s)"))
        }
        self = t
    }
}

/// An sRGB colour as 0xRRGGBB with an optional alpha (tokens.json writes alpha as RRGGBBAA).
public struct RGB: Equatable, Hashable, Sendable {
    public var hex: UInt32
    public var alpha: Double
    public init(_ hex: UInt32, alpha: Double = 1) { self.hex = hex; self.alpha = alpha }
    /// 0xRRGGBBAA.
    public init(rgba: UInt32) { self.init(rgba >> 8, alpha: Double(rgba & 0xFF) / 255) }
    public var r: Double { Double((hex >> 16) & 0xFF) / 255 }
    public var g: Double { Double((hex >> 8) & 0xFF) / 255 }
    public var b: Double { Double(hex & 0xFF) / 255 }
    public var css: String { String(format: "#%06x", hex) }
    public func opacity(_ a: Double) -> RGB { RGB(hex, alpha: a) }

    /// This colour painted over an opaque background.
    public func over(_ bg: RGB) -> RGB {
        guard alpha < 1 else { return self }
        func mix(_ f: Double, _ b: Double) -> UInt32 { UInt32((f * alpha + b * (1 - alpha)) * 255 + 0.5) }
        return RGB(mix(r, bg.r) << 16 | mix(g, bg.g) << 8 | mix(b, bg.b))
    }

    /// WCAG relative luminance (alpha ignored; composite with `over` first).
    public var luminance: Double {
        func lin(_ c: Double) -> Double { c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
        return 0.2126 * lin(r) + 0.7152 * lin(g) + 0.0722 * lin(b)
    }

    /// WCAG contrast ratio between two opaque colours (1…21).
    public static func contrast(_ a: RGB, _ b: RGB) -> Double {
        let (l1, l2) = (max(a.luminance, b.luminance), min(a.luminance, b.luminance))
        return (l1 + 0.05) / (l2 + 0.05)
    }
}

/// How a status pill draws its edge.
public enum PillEdge: Equatable, Sendable { case none, solid(RGB), dashed(RGB), strike }

/// A status pill: fill (nil = none), text colour and edge, per theme.
public struct PillStyle: Equatable, Sendable {
    public var fill: RGB?
    public var text: RGB
    public var edge: PillEdge
}

/// The terminal's colours (fed to libghostty as a Ghostty config).
public struct TerminalTokens: Equatable, Sendable {
    public var background: RGB
    public var foreground: RGB
    public var cursor: RGB
    public var selection: RGB
    public var paneHeader: RGB
    public var summaryStrip: RGB
    public var ansi: [RGB]
}

/// Colour tokens for one theme (tokens.json `themes.<name>`). Views never use a hex literal: everything comes from here.
public struct ThemeTokens: Sendable {
    public var name: ThemeName
    public var window: RGB
    public var toolbar: RGB
    public var sidebar: RGB
    public var surface: RGB
    public var surface2: RGB
    public var control: RGB
    public var separator: RGB
    public var separatorStrong: RGB
    public var text: RGB
    public var text2: RGB
    public var text3: RGB
    public var selection: RGB
    public var accent: RGB
    public var accentText: RGB
    public var onAccent: RGB
    public var now: RGB
    public var diffAddFill: RGB
    public var diffDelFill: RGB
    public var diffAddText: RGB
    public var diffDelText: RGB
    public var terminal: TerminalTokens
    public var isDark: Bool { name.isDark }

    /// The desk gradient behind fleet views (Overview, Board, Decisions, Subagents), top → bottom.
    public var desk: (top: RGB, bottom: RGB) {
        switch name {
        case .daylight: return (RGB(0xDCE3EE), RGB(0xC3CCDA))
        case .graphite: return (RGB(0x4A4E5A), RGB(0x2E3038))
        default: return (RGB(0x1E2030), RGB(0x0B0C10))
        }
    }

    // v0.1 names, kept so older views read the v2 palette.
    public var background: RGB { window }
    public var secondaryText: RGB { text2 }
    public var border: RGB { separator }
    /// Needs-you text on this theme (the only red in the UI).
    public var needsText: RGB { isDark ? RGB(0xFF6961) : RGB(0xC4261D) }

    // MARK: Syntax (S07 §1.5)

    /// Editor token colours: Daylight is Xcode's light palette; Graphite and Midnight use the Xcode Dark equivalents.
    /// Graphite's surface is lighter, so its comment grey is raised to #9CA7B2 to keep 4.5:1 (Midnight keeps #7F8C98).
    public func syntax(_ k: TokenKind) -> RGB {
        switch (k, isDark) {
        case (.keyword, false): return RGB(0x9B2393)
        case (.string, false): return RGB(0xC41A16)
        case (.comment, false): return RGB(0x5D6C79)
        case (.type, false): return RGB(0x0B4F79)
        case (.function, false): return RGB(0x326D74)
        case (.number, false): return RGB(0x1C00CF)
        case (.keyword, true): return RGB(0xFF7AB2)
        case (.string, true): return RGB(0xFF8170)
        case (.comment, true): return name == .graphite ? RGB(0x9CA7B2) : RGB(0x7F8C98)
        case (.type, true): return RGB(0x6BDFFF)
        case (.function, true): return RGB(0x67B7A4)
        case (.number, true): return RGB(0xD9C97C)
        case (.plain, _): return text
        }
    }

    // MARK: Status

    /// The status dot colour (the same in every theme).
    public static func dot(_ s: SessionStatus) -> RGB { StatusPalette.dot(s) }
    /// The status dot on this theme (Daylight darkens Ready and Idle so a 7 pt dot still reads at 3:1).
    public func statusColor(_ s: SessionStatus) -> RGB { StatusPalette.dot(s, theme: name) }
    public func pill(_ s: SessionStatus) -> PillStyle { StatusPalette.pill(s, theme: name) }

    // MARK: Stickers (APPEARANCE §5)

    /// Fill and ink for a sticker on this theme: Daylight uses the pastel pair; Graphite and Midnight use the ink hue
    /// at 20% over the panel, with the ink lightened until it reads at 4.5:1.
    public func sticker(_ p: Pastel, on bg: RGB? = nil) -> (fill: RGB, ink: RGB) {
        guard isDark else { return (p.lightFill, p.lightInk) }
        let base = bg ?? sidebar
        let fill = p.lightInk.opacity(0.2).over(base)
        return (fill, Self.lighten(p.lightInk, until: 4.5, on: fill))
    }

    /// Blend a colour towards white until it reaches `ratio` against `bg`.
    static func lighten(_ c: RGB, until ratio: Double, on bg: RGB) -> RGB {
        var t = 0.0
        var out = c
        while RGB.contrast(out, bg) < ratio && t < 1 {
            t += 0.04
            out = RGB(0xFFFFFF, alpha: t).over(c)
        }
        return out
    }

    /// Ghostty config lines for a terminal in this theme.
    public var ghosttyConfig: String {
        let t = terminal
        var lines = [
            "background = \(t.background.css)",
            "foreground = \(t.foreground.css)",
            "cursor-color = \(t.cursor.css)",
            "selection-background = \(t.selection.over(t.background).css)",
            "selection-foreground = \(t.foreground.css)",
        ]
        for (i, c) in t.ansi.enumerated() { lines.append("palette = \(i)=\(c.css)") }
        return lines.joined(separator: "\n") + "\n"
    }
}

/// Status colours (tokens.json `status`). Labels: Needs you · Working · Ready · Idle · Next · Planned · Tonight · Exited · Parked.
public enum StatusPalette {
    public static func dot(_ s: SessionStatus) -> RGB {
        switch s {
        case .needsYou: return RGB(0xFF453A)
        case .running: return RGB(0x0A84FF)
        case .done: return RGB(0x30D158)
        case .idle: return RGB(0xC7C7CC)
        case .next: return RGB(0x8E8E93)
        case .planned: return RGB(0xC7C7CC)
        case .exited: return RGB(0x636366)
        case .doNotUse: return RGB(0x48484A)
        }
    }

    public static func dot(_ s: SessionStatus, theme: ThemeName) -> RGB {
        guard theme == .daylight else { return dot(s) }
        switch s {
        case .done: return RGB(0x1F9D55)
        case .idle: return RGB(0x7C7C80)
        default: return dot(s)
        }
    }

    /// The v2 label for a status (Running reads "Working", Done reads "Ready", Do not use reads "Parked").
    public static func label(_ s: SessionStatus) -> String {
        switch s {
        case .needsYou: return "Needs you"
        case .running: return "Working"
        case .done: return "Ready"
        case .idle: return "Idle"
        case .next: return "Next"
        case .planned: return "Planned"
        case .exited: return "Exited"
        case .doNotUse: return "Parked"
        }
    }

    /// Dot for a scheduled ("Tonight") session.
    public static let scheduledDot = RGB(0x64D2FF)

    public static func scheduledPill(theme: ThemeName) -> PillStyle {
        switch theme {
        case .daylight: return PillStyle(fill: RGB(0xE6EFFC), text: RGB(0x2B63C0), edge: .none)
        case .graphite: return PillStyle(fill: RGB(rgba: 0x0A84FF29).over(RGB(0x3A3A3C)), text: RGB(0xA9D1FF), edge: .none)
        default: return PillStyle(fill: RGB(rgba: 0x0A84FF1F).over(RGB(0x1C1C1E)), text: RGB(0x9CCBFF), edge: .none)
        }
    }

    /// Pill colours per theme. Translucent fills are composited over the theme's surface so contrast is testable.
    public static func pill(_ s: SessionStatus, theme: ThemeName) -> PillStyle {
        let light = theme == .daylight
        let surface: RGB = theme == .graphite ? RGB(0x3A3A3C) : (light ? RGB(0xFFFFFF) : RGB(0x1C1C1E))
        switch s {
        case .needsYou:
            return light ? PillStyle(fill: RGB(0xFFE5E3), text: RGB(0xC4261D), edge: .solid(RGB(0xF5B5AE)))
                         : PillStyle(fill: RGB(0xFF453A), text: RGB(0x1A0E0E), edge: .solid(RGB(0xFF453A)))
        case .running:
            return light ? PillStyle(fill: RGB(0xECEDF2), text: RGB(0x1C1C1E), edge: .none)
                         : PillStyle(fill: RGB(rgba: 0xFFFFFF14).over(surface), text: theme == .graphite ? RGB(0xF2F2F7) : RGB(0xE5E5EA), edge: .none)
        case .done:
            switch theme {
            case .daylight: return PillStyle(fill: RGB(0xDDF6E5), text: RGB(0x1F7A3D), edge: .none)
            case .graphite: return PillStyle(fill: RGB(rgba: 0x30D15829).over(surface), text: RGB(0x7FE0A0), edge: .none)
            default: return PillStyle(fill: RGB(rgba: 0x30D15824).over(surface), text: RGB(0x30D158), edge: .none)
            }
        case .idle:
            return PillStyle(fill: nil, text: light ? RGB(0x6E6E73) : (theme == .graphite ? RGB(0xAEAEB2) : RGB(0x8E8E93)), edge: .none)
        case .next:
            switch theme {
            case .daylight: return PillStyle(fill: nil, text: RGB(0x48484A), edge: .dashed(RGB(0xB8B9C0)))
            case .graphite: return PillStyle(fill: nil, text: RGB(0xE5E5EA), edge: .dashed(RGB(0x8E8E93)))
            default: return PillStyle(fill: nil, text: RGB(0xE5E5EA), edge: .dashed(RGB(0x636366)))
            }
        case .planned:
            switch theme {
            case .daylight: return PillStyle(fill: nil, text: RGB(0x6E6E73), edge: .dashed(RGB(0xC7C8D0)))
            case .graphite: return PillStyle(fill: nil, text: RGB(0xAEAEB2), edge: .dashed(RGB(0x636366)))
            default: return PillStyle(fill: nil, text: RGB(0xAEAEB2), edge: .dashed(RGB(0x48484A)))
            }
        case .exited:
            return PillStyle(fill: nil, text: light ? RGB(0x6E6E73) : (theme == .graphite ? RGB(0xAEAEB2) : RGB(0x8E8E93)), edge: .none)
        case .doNotUse:
            return PillStyle(fill: nil, text: light ? RGB(0x6E6E73) : (theme == .graphite ? RGB(0xAEAEB2) : RGB(0x8E8E93)), edge: .strike)
        }
    }
}

/// The agent mark: a monogram squircle in the agent's colour. The two Claude accounts get their own
/// colours so they tell apart at a glance. Same colours in every theme.
public enum AgentMark: String, CaseIterable, Sendable {
    case claude1, claude2, codex, kimi, gemini, antigravity, shell

    /// `marks` without Claude2 when this Mac has no second Claude account (~/.claude-2).
    public static func available(_ marks: [AgentMark], home: String = NSHomeDirectory()) -> [AgentMark] {
        AccountResolver.claudeAccounts(home: home).contains("Claude2") ? marks : marks.filter { $0 != .claude2 }
    }

    public var mono: String {
        switch self {
        case .claude1: return "C1"
        case .claude2: return "C2"
        case .codex: return "CX"
        case .kimi: return "KM"
        case .gemini: return "GM"
        case .antigravity: return "AG"
        case .shell: return ">_"
        }
    }

    public var fill: RGB {
        switch self {
        case .claude1: return RGB(0xFF9F0A)
        case .claude2: return RGB(0xFFD60A)
        case .codex: return RGB(0x30D158)
        case .kimi: return RGB(0xBF5AF2)
        case .gemini: return RGB(0x0A84FF)
        case .antigravity: return RGB(0xFF375F)
        case .shell: return RGB(0xC7C7CC)
        }
    }

    public static let ink = RGB(0x1C1C1E)

    /// Shell squircle on dark panels.
    public func fill(dark: Bool) -> RGB { self == .shell && dark ? RGB(0x3A3A3C) : fill }
    public func ink(dark: Bool) -> RGB { self == .shell && dark ? RGB(0xE5E5EA) : Self.ink }

    /// The mark for an agent on an account ("Claude2" → C2; any other Claude account → C1).
    public init(agent: AgentKind, account: String?) {
        switch agent {
        case .claude: self = (account ?? "").contains("2") ? .claude2 : .claude1
        case .codex: self = .codex
        case .kimi: self = .kimi
        case .gemini: self = .gemini
        case .agy: self = .antigravity
        case .shell: self = .shell
        }
    }
}

public extension ThemeName {
    var tokens: ThemeTokens {
        switch self {
        case .daylight:
            return ThemeTokens(
                name: self, window: RGB(0xFFFFFF), toolbar: RGB(0xF6F7FA), sidebar: RGB(0xF0F1F6), surface: RGB(0xFFFFFF),
                surface2: RGB(0xF2F2F7), control: RGB(0xE6E8EF), separator: RGB(0xE3E4EA), separatorStrong: RGB(0xC7C8D0),
                text: RGB(0x1C1C1E), text2: RGB(0x5E5E66), text3: RGB(0x86868B),
                selection: RGB(0xDCE8FF), accent: RGB(0x0A84FF), accentText: RGB(0x0066CC), onAccent: RGB(0xFFFFFF),
                now: RGB(0x8A5A00),
                diffAddFill: RGB(0xE9F8EE), diffDelFill: RGB(0xFDECEC), diffAddText: RGB(0x1F7A3D), diffDelText: RGB(0xD70015),
                terminal: TerminalTokens(
                    background: RGB(0xFFFFFF), foreground: RGB(0x1C1C1E), cursor: RGB(0x0A84FF), selection: RGB(rgba: 0x0A84FF33),
                    paneHeader: RGB(0xF6F7FA), summaryStrip: RGB(0xF0F1F6),
                    ansi: [0x1C1C1E, 0xC4261D, 0x1F7A3D, 0x8A5A00, 0x0058C2, 0x8E3FA8, 0x0B6B73, 0x5E5E66,
                           0x8E8E93, 0xD70015, 0x1A7A3C, 0x7A5000, 0x0066CC, 0x9A3FB8, 0x0B7A80, 0x1C1C1E].map { RGB($0) }))
        case .graphite:
            return ThemeTokens(
                name: self, window: RGB(0x2C2C2E), toolbar: RGB(0x323236), sidebar: RGB(0x262628), surface: RGB(0x3A3A3C),
                surface2: RGB(0x323236), control: RGB(0x48484A), separator: RGB(0x48484A), separatorStrong: RGB(0x636366),
                text: RGB(0xF2F2F7), text2: RGB(0xAEAEB2), text3: RGB(0x98989D),
                selection: RGB(rgba: 0x0A84FF33), accent: RGB(0x0A84FF), accentText: RGB(0x64D2FF), onAccent: RGB(0xFFFFFF),
                now: RGB(0xFFD60A),
                diffAddFill: RGB(rgba: 0x30D15824), diffDelFill: RGB(rgba: 0xFF453A24), diffAddText: RGB(0x4CD964), diffDelText: RGB(0xFFA39D),
                terminal: TerminalTokens(
                    background: RGB(0x232325), foreground: RGB(0xF2F2F7), cursor: RGB(0xF2F2F7), selection: RGB(rgba: 0x0A84FF55),
                    paneHeader: RGB(0x2C2C2E), summaryStrip: RGB(0x262628),
                    ansi: [0x232325, 0xFF6961, 0x30D158, 0xFFD60A, 0x5AA9FF, 0xD08CF2, 0x64D2FF, 0xE5E5EA,
                           0x8E8E93, 0xFF8A82, 0x4CD964, 0xFFE066, 0x80BDFF, 0xDA8FFF, 0x8AE1FF, 0xFFFFFF].map { RGB($0) }))
        case .midnight:
            return ThemeTokens(
                name: self, window: RGB(0x161618), toolbar: RGB(0x1C1C1E), sidebar: RGB(0x121214), surface: RGB(0x1C1C1E),
                surface2: RGB(0x2C2C2E), control: RGB(0x2C2C2E), separator: RGB(0x2A2A2D), separatorStrong: RGB(0x3A3A3C),
                text: RGB(0xE5E5EA), text2: RGB(0xAEAEB2), text3: RGB(0x8E8E93),
                selection: RGB(rgba: 0x0A84FF33), accent: RGB(0x0A84FF), accentText: RGB(0x64D2FF), onAccent: RGB(0xFFFFFF),
                now: RGB(0xFFD60A),
                diffAddFill: RGB(rgba: 0x30D15824), diffDelFill: RGB(rgba: 0xFF453A24), diffAddText: RGB(0x30D158), diffDelText: RGB(0xFF6961),
                terminal: TerminalTokens(
                    background: RGB(0x0B0B0D), foreground: RGB(0xE5E5EA), cursor: RGB(0xE5E5EA), selection: RGB(rgba: 0x0A84FF55),
                    paneHeader: RGB(0x161618), summaryStrip: RGB(0x121214),
                    ansi: [0x0B0B0D, 0xFF453A, 0x30D158, 0xFFD60A, 0x0A84FF, 0xBF5AF2, 0x64D2FF, 0xE5E5EA,
                           0x636366, 0xFF6961, 0x4CD964, 0xFFE066, 0x409CFF, 0xDA8FFF, 0x8AE1FF, 0xFFFFFF].map { RGB($0) }))
        case .blueprint:
            // Hidden, terminal-only; panel tokens follow Midnight so a stray choice still reads.
            var t = ThemeName.midnight.tokens
            t.name = self
            t.terminal = TerminalTokens(
                background: RGB(0x0B2A5B), foreground: RGB(0xF2F6FF), cursor: RGB(0xFFD84D), selection: RGB(0x2A5A9E),
                paneHeader: RGB(0x103571), summaryStrip: RGB(0x0D2F66),
                ansi: [0x103571, 0xFF9A9A, 0x7EF0C8, 0xFFD84D, 0x9CC3FF, 0xE2B4FF, 0x8AE8F0, 0xD8E3F7,
                       0x5679B0, 0xFFB8B8, 0xA4F5DA, 0xFFE68A, 0xC0D9FF, 0xEDCCFF, 0xB0F0F5, 0xFFFFFF].map { RGB($0) })
            return t
        }
    }
}

/// Which theme each panel uses; every panel is independent (APPEARANCE §2). Defaults: Sessions and Files Daylight,
/// Terminal Midnight, Plan Graphite, centre views Daylight. Stored under `panelThemes.v2`; v0.1's `panelThemes` is
/// migrated once (Light/Paper → Daylight, Dim → Graphite, Dark → Midnight).
public struct PanelThemes: Codable, Equatable, Sendable {
    public var sidebar: ThemeName
    public var files: ThemeName
    public var terminal: ThemeName
    public var plan: ThemeName
    public var centre: ThemeName

    public init(sidebar: ThemeName = .daylight, files: ThemeName? = nil, terminal: ThemeName = .midnight,
                plan: ThemeName = .graphite, centre: ThemeName = .daylight) {
        self.sidebar = sidebar; self.files = files ?? sidebar; self.terminal = terminal; self.plan = plan; self.centre = centre
    }

    public static let defaults = PanelThemes()
    public static let storageKey = "panelThemes.v2"
    public static let legacyKey = "panelThemes"

    enum CodingKeys: String, CodingKey { case sidebar, files, terminal, plan, centre }

    /// The themes to draw with: the owner's choice, or its dark twins while macOS is in Dark Mode and the panels
    /// follow it. Dark choices stay as they are.
    public func forAppearance(systemDark: Bool, follow: Bool) -> PanelThemes {
        guard follow && systemDark else { return self }
        return PanelThemes(sidebar: sidebar.darkTwin, files: files.darkTwin, terminal: terminal.darkTwin,
                           plan: plan.darkTwin, centre: centre.darkTwin)
    }

    /// Older settings had no `files` (→ the sessions panel's theme) and no `centre` (→ Daylight). Blueprint is
    /// terminal-only: on any other panel it reads as Midnight.
    public init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        func panel(_ t: ThemeName?) -> ThemeName? { t == .blueprint ? .midnight : t }
        sidebar = panel(try? c.decode(ThemeName.self, forKey: .sidebar)) ?? .daylight
        files = panel(try? c.decode(ThemeName.self, forKey: .files)) ?? sidebar
        terminal = (try? c.decode(ThemeName.self, forKey: .terminal)) ?? .midnight
        plan = panel(try? c.decode(ThemeName.self, forKey: .plan)) ?? .graphite
        centre = panel(try? c.decode(ThemeName.self, forKey: .centre)) ?? .daylight
    }

    /// Read from preferences: the v2 key, else a one-time migration of the v0.1 key, else the defaults.
    public static func load(_ defaults: UserDefaults) -> PanelThemes {
        if let d = defaults.data(forKey: storageKey), let t = try? JSONDecoder().decode(PanelThemes.self, from: d) { return t }
        if let d = defaults.data(forKey: legacyKey), let t = try? JSONDecoder().decode(PanelThemes.self, from: d) { return t }
        return PanelThemes()
    }
}
