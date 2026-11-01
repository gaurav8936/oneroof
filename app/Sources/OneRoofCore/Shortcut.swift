import Foundation

/// A keyboard shortcut as the owner sees it ("⌘⇧D", "⌃`", "⌘⌥←"), for remapping menu items and the global
/// hotkey. Pure: AppKit flags and Carbon codes are mapped in the app.
public struct Shortcut: Equatable, Hashable, Codable, Sendable {
    public var key: String          // lowercased character, or a name: "←", "→", "↑", "↓", "↩", "space", "tab", "esc"
    public var command: Bool
    public var shift: Bool
    public var option: Bool
    public var control: Bool

    public init(key: String, command: Bool = false, shift: Bool = false, option: Bool = false, control: Bool = false) {
        self.key = key.lowercased(); self.command = command; self.shift = shift; self.option = option; self.control = control
    }

    /// "⌃⌥⇧⌘D" order, the way macOS menus show it.
    public var display: String {
        (control ? "⌃" : "") + (option ? "⌥" : "") + (shift ? "⇧" : "") + (command ? "⌘" : "") + (key.count == 1 ? key.uppercased() : key)
    }

    /// Parse what `display` writes (modifier symbols in any order, then the key).
    public init?(_ text: String) {
        var rest = Substring(text.trimmingCharacters(in: .whitespaces))
        var cmd = false, sh = false, opt = false, ctl = false
        while let c = rest.first, "⌘⇧⌥⌃".contains(c) {
            switch c { case "⌘": cmd = true; case "⇧": sh = true; case "⌥": opt = true; default: ctl = true }
            rest = rest.dropFirst()
        }
        guard !rest.isEmpty else { return nil }
        self.init(key: String(rest), command: cmd, shift: sh, option: opt, control: ctl)
    }

    /// A global hotkey needs a modifier, or it would steal a plain key from every app.
    public var isUsableGlobally: Bool { command || option || control }
}

/// Owner's overrides: menu item title → shortcut display text; "" removes the item's shortcut.
public typealias ShortcutOverrides = [String: String]

/// Menu items renamed over time (v2 names, LAB-2039/2049, LAB-2043): a shortcut the owner set under an old title keeps
/// working under the new one, through every step of a chain (Inbox ← Needs You ← Decisions, Home ← Overview ← Launchpad).
public enum MenuRenames {
    /// Menu titles that changed in v2, so overrides the owner saved under the old title keep working.
    public static let renamed: [String: String] = [
        "New Session…": "Plan a Session…", "Find…": "Find in Terminal…", "Overview": "Launchpad",
        "Raw Stream / Run": "Raw Stream",
        // One Roof 1 window (A11, MENUS.md): the v2 names keep any shortcut you set under the old ones.
        "Home": "Overview", "Resources": "Machine", "Inbox": "Needs You", "Needs You": "Decisions",   // LAB-2043: Inbox ← Needs You ← Decisions
        "Work": "Work: Projects and Roadmap",
        "Projects": "Work", "Evals · Draft": "Evals",
        "History": "Scroll",   // LAB-2044: a shortcut set on View › Scroll reaches History   // LAB-2072: a shortcut set on Evals stays; LAB-2039/2049: shortcuts set under Machine or Work keep working
        "Sessions Column": "Toggle Sidebar", "Plan": "Toggle Plan Panel", "Files Tab": "File Browser", "Changes": "Review Changes",
        "Focus: Step On": "Focus: Terminal Only", "Sessions": "Focus Terminal",
    ]

    /// The overrides with each new title given its old title's override (unless it has its own), chains followed.
    public static func carry(_ overrides: ShortcutOverrides) -> ShortcutOverrides {
        var out = overrides
        for _ in 0..<4 {
            for (new, old) in renamed where out[new] == nil { if let o = out[old] { out[new] = o } }
        }
        return out
    }
}
