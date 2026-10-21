import Foundation

/// A sticker: a bold, coloured label with an icon (owner, 2026-10-17: "like fun stickers that are visible and clear,
/// not just text"). Stickers are a session's tags: a tag that matches a built-in sticker gets its colour and icon;
/// any other tag becomes a custom sticker with a colour picked from its name. Colours are the same in every theme
/// (vivid, white or black text chosen for contrast), so they pop on a light or a dark sidebar.
/// A dense pastel colour (owner, 2026-10-17: "dense pastel … not highly chromatic"; built around the
/// Porcelain / Graphite themes). Each has a fill and an ink (text) for light panels and for dark panels.
public struct Pastel: Equatable, Sendable {
    public var name: String
    public var lightFill: RGB, lightInk: RGB
    public var darkFill: RGB, darkInk: RGB

    public func fill(dark: Bool) -> RGB { dark ? darkFill : lightFill }
    public func ink(dark: Bool) -> RGB { dark ? darkInk : lightInk }

    static let darkText = RGB(0x1B1C20)

    public static let all: [Pastel] = [
        Pastel(name: "coral", lightFill: RGB(0xFFCFC8), lightInk: RGB(0x8A2A22), darkFill: RGB(0xF0A59C), darkInk: darkText),
        Pastel(name: "peach", lightFill: RGB(0xFFDDB8), lightInk: RGB(0x7A4100), darkFill: RGB(0xF4C08E), darkInk: darkText),
        Pastel(name: "butter", lightFill: RGB(0xFCEBA6), lightInk: RGB(0x6B5200), darkFill: RGB(0xE9D27E), darkInk: darkText),
        Pastel(name: "mint", lightFill: RGB(0xC4ECD5), lightInk: RGB(0x0B6B45), darkFill: RGB(0x93D6B2), darkInk: darkText),
        Pastel(name: "aqua", lightFill: RGB(0xBFE7EC), lightInk: RGB(0x0B5F66), darkFill: RGB(0x8DCFD7), darkInk: darkText),
        Pastel(name: "sky", lightFill: RGB(0xCADFFD), lightInk: RGB(0x1C4A9C), darkFill: RGB(0x9DBFF3), darkInk: darkText),
        Pastel(name: "periwinkle", lightFill: RGB(0xD4D6FB), lightInk: RGB(0x3B3FA8), darkFill: RGB(0xAEB2F0), darkInk: darkText),
        Pastel(name: "lavender", lightFill: RGB(0xE4D1FB), lightInk: RGB(0x5B2E9E), darkFill: RGB(0xC6AAEC), darkInk: darkText),
        Pastel(name: "rose", lightFill: RGB(0xFDCDDD), lightInk: RGB(0x8E1F4D), darkFill: RGB(0xEEA6C1), darkInk: darkText),
        Pastel(name: "stone", lightFill: RGB(0xE3E3DF), lightInk: RGB(0x45474D), darkFill: RGB(0xB9BBC0), darkInk: darkText),
    ]

    public static func named(_ name: String?) -> Pastel? {
        guard let name else { return nil }
        // Older rows stored Apple colour names.
        let legacy = ["red": "coral", "orange": "peach", "yellow": "butter", "green": "mint", "teal": "aqua",
                      "blue": "sky", "indigo": "periwinkle", "purple": "lavender", "pink": "rose"]
        let n = legacy[name] ?? name
        return all.first { $0.name == n }
    }
}

/// A sticker: a clear label with an icon in a dense pastel (owner, 2026-10-17: "like fun stickers that are visible
/// and clear, not just text"). Stickers are a session's tags: a tag that matches a built-in sticker gets its colour
/// and icon; any other tag becomes a custom sticker with a pastel picked from its name.
public struct Sticker: Identifiable, Equatable, Sendable {
    public var id: String          // lowercased key stored in Session.tags
    public var label: String
    public var symbol: String      // SF Symbol name
    public var pastel: Pastel
    public var builtIn: Bool

    public init(id: String, label: String, symbol: String, pastel: Pastel, builtIn: Bool) {
        self.id = id; self.label = label; self.symbol = symbol; self.pastel = pastel; self.builtIn = builtIn
    }

    public static func p(_ n: String) -> Pastel { Pastel.named(n)! }

    public static let catalog: [Sticker] = [
        Sticker(id: "next", label: "Next", symbol: "arrow.forward.circle.fill", pastel: p("peach"), builtIn: true),
        Sticker(id: "wip", label: "WIP", symbol: "hammer.fill", pastel: p("sky"), builtIn: true),
        Sticker(id: "important", label: "Important", symbol: "exclamationmark.triangle.fill", pastel: p("coral"), builtIn: true),
        Sticker(id: "blocked", label: "Blocked", symbol: "hand.raised.fill", pastel: p("lavender"), builtIn: true),
        Sticker(id: "review", label: "Review", symbol: "eye.fill", pastel: p("aqua"), builtIn: true),
        Sticker(id: "idea", label: "Idea", symbol: "lightbulb.fill", pastel: p("butter"), builtIn: true),
        Sticker(id: "bug", label: "Bug", symbol: "ladybug.fill", pastel: p("rose"), builtIn: true),
        Sticker(id: "research", label: "Research", symbol: "magnifyingglass", pastel: p("periwinkle"), builtIn: true),
        Sticker(id: "shipped", label: "Shipped", symbol: "checkmark.seal.fill", pastel: p("mint"), builtIn: true),
        Sticker(id: "dnu", label: "Do not use", symbol: "nosign", pastel: p("stone"), builtIn: true),
    ]

    /// One short line on what the sticker says about a session (LAB-257), shown next to it in menus and on hover.
    public var meaning: String {
        switch id {
        case "next": return "up next in your plan"
        case "wip": return "work in progress"
        case "important": return "do this before the rest"
        case "blocked": return "waiting on something else"
        case "review": return "ready for a look"
        case "idea": return "worth exploring later"
        case "bug": return "fixing a defect"
        case "research": return "reading and finding out"
        case "shipped": return "done and released"
        case "dnu": return "parked; kept but not used"
        default: return "your own sticker"
        }
    }

    /// Row colours offered in the menu (every pastel except stone).
    public static var rowColors: [Pastel] { Pastel.all.filter { $0.name != "stone" } }

    /// The sticker for a stored tag.
    public static func resolve(_ tag: String) -> Sticker {
        let key = tag.trimmingCharacters(in: .whitespaces).lowercased()
        if let s = catalog.first(where: { $0.id == key || $0.label.lowercased() == key }) { return s }
        // Stable colour from the name (FNV-1a), so a custom sticker keeps its colour everywhere.
        var h: UInt32 = 2166136261
        for b in key.utf8 { h = (h ^ UInt32(b)) &* 16777619 }
        let c = rowColors[Int(h % UInt32(rowColors.count))]
        return Sticker(id: key, label: tag.trimmingCharacters(in: .whitespaces), symbol: "tag.fill", pastel: c, builtIn: false)
    }

    /// Stickers to show on a row: the status ones (Next, Do not use) first, then the session's own, no duplicates.
    public static func forSession(_ s: Session, status: SessionStatus) -> [Sticker] {
        var out: [Sticker] = []
        if status == .next { out.append(resolve("next")) }
        if status == .doNotUse { out.append(resolve("dnu")) }
        for t in s.tags where !t.trimmingCharacters(in: .whitespaces).isEmpty {
            let st = resolve(t)
            if !out.contains(where: { $0.id == st.id }) { out.append(st) }
        }
        return out
    }
}

/// Each agent's logo: a pastel and a symbol (shown when the session has no emoji icon of its own).
public extension AgentKind {
    var logoPastel: Pastel {
        switch self {
        case .claude: return Pastel.named("peach")!
        case .codex: return Pastel.named("mint")!
        case .kimi: return Pastel.named("sky")!
        case .gemini: return Pastel.named("periwinkle")!
        case .agy: return Pastel.named("lavender")!
        case .shell: return Pastel.named("stone")!
        }
    }

    var logoSymbol: String {
        switch self {
        case .claude: return "asterisk"
        case .codex: return "chevron.left.forwardslash.chevron.right"
        case .kimi: return "moon.stars.fill"
        case .gemini: return "sparkles"
        case .agy: return "atom"
        case .shell: return "terminal.fill"
        }
    }
}
