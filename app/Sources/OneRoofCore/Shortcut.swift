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
