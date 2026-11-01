import AppKit
import Carbon.HIToolbox
import OneRoofCore

/// Maps `Shortcut` to menu key equivalents, key events and a Carbon global hotkey.
enum ShortcutBridge {
    private static let named: [String: Int] = ["←": NSLeftArrowFunctionKey, "→": NSRightArrowFunctionKey,
                                               "↑": NSUpArrowFunctionKey, "↓": NSDownArrowFunctionKey]
    private static let plain: [String: String] = ["↩": "\r", "space": " ", "tab": "\t", "esc": "\u{1b}"]

    static func keyEquivalent(_ s: Shortcut) -> (String, NSEvent.ModifierFlags) {
        let key = named[s.key].map { String(Character(UnicodeScalar($0)!)) } ?? plain[s.key] ?? s.key
        var m: NSEvent.ModifierFlags = []
        if s.command { m.insert(.command) }; if s.shift { m.insert(.shift) }
        if s.option { m.insert(.option) }; if s.control { m.insert(.control) }
        return (key, m)
    }

    static func shortcut(of item: NSMenuItem) -> Shortcut? {
        let k = item.keyEquivalent
        guard !k.isEmpty else { return nil }
        let m = item.keyEquivalentModifierMask
        let name = named.first { String(Character(UnicodeScalar($0.value)!)) == k }?.key ?? plain.first { $0.value == k }?.key
        // An uppercase key equivalent implies shift.
        let upper = k.count == 1 && k != k.lowercased()
        return Shortcut(key: name ?? k.lowercased(), command: m.contains(.command), shift: m.contains(.shift) || upper,
                        option: m.contains(.option), control: m.contains(.control))
    }

    /// The shortcut a key press in the recorder means (nil for a lone modifier).
    static func shortcut(of e: NSEvent) -> Shortcut? {
        let m = e.modifierFlags
        let key: String
        switch Int(e.keyCode) {
        case kVK_LeftArrow: key = "←"
        case kVK_RightArrow: key = "→"
        case kVK_UpArrow: key = "↑"
        case kVK_DownArrow: key = "↓"
        case kVK_Return: key = "↩"
        case kVK_Space: key = "space"
        case kVK_Tab: key = "tab"
        case kVK_Escape: key = "esc"
        default:
            guard let c = e.charactersIgnoringModifiers?.lowercased(), c.count == 1 else { return nil }
            key = c
        }
        return Shortcut(key: key, command: m.contains(.command), shift: m.contains(.shift), option: m.contains(.option), control: m.contains(.control))
    }

    // MARK: Menu overrides

    /// Shortcuts as built in code, by menu item title (kept so Reset can restore them).
    private(set) static var defaults: [String: Shortcut?] = [:]

    static func allItems(_ menu: NSMenu?) -> [NSMenuItem] {
        (menu?.items ?? []).flatMap { i -> [NSMenuItem] in
            i.isSeparatorItem ? [] : (i.submenu.map { allItems($0) } ?? [i])
        }
    }

    /// Menu titles that changed in v2, so overrides the owner saved under the old title keep working (MenuRenames, Core).
    static var renamed: [String: String] { MenuRenames.renamed }

    /// Apply the owner's overrides on top of the built-in shortcuts.
    static func apply(_ overrides: ShortcutOverrides, to menu: NSMenu?) {
        let overrides = MenuRenames.carry(overrides)
        for item in allItems(menu) where !item.title.isEmpty {
            if defaults[item.title] == nil { defaults[item.title] = .some(shortcut(of: item)) }
            let target: Shortcut?
            if let o = overrides[item.title] { target = o.isEmpty ? nil : Shortcut(o) } else { target = defaults[item.title] ?? nil }
            if let t = target {
                let (k, m) = keyEquivalent(t)
                item.keyEquivalent = k; item.keyEquivalentModifierMask = m
            } else {
                item.keyEquivalent = ""; item.keyEquivalentModifierMask = []
            }
        }
    }

    /// Which menu item already uses a shortcut (to refuse duplicates).
    static func owner(of s: Shortcut, in menu: NSMenu?, except title: String) -> String? {
        allItems(menu).first { $0.title != title && shortcut(of: $0) == s }?.title
    }

    // MARK: Global hotkey (Carbon RegisterEventHotKey; works without Accessibility permission)

    private static var hotKeyRef: EventHotKeyRef?
    private static var handlerInstalled = false
    static var onHotKey: (() -> Void)?

    private static let keyCodes: [String: Int] = [
        "a": kVK_ANSI_A, "b": kVK_ANSI_B, "c": kVK_ANSI_C, "d": kVK_ANSI_D, "e": kVK_ANSI_E, "f": kVK_ANSI_F, "g": kVK_ANSI_G,
        "h": kVK_ANSI_H, "i": kVK_ANSI_I, "j": kVK_ANSI_J, "k": kVK_ANSI_K, "l": kVK_ANSI_L, "m": kVK_ANSI_M, "n": kVK_ANSI_N,
        "o": kVK_ANSI_O, "p": kVK_ANSI_P, "q": kVK_ANSI_Q, "r": kVK_ANSI_R, "s": kVK_ANSI_S, "t": kVK_ANSI_T, "u": kVK_ANSI_U,
        "v": kVK_ANSI_V, "w": kVK_ANSI_W, "x": kVK_ANSI_X, "y": kVK_ANSI_Y, "z": kVK_ANSI_Z,
        "0": kVK_ANSI_0, "1": kVK_ANSI_1, "2": kVK_ANSI_2, "3": kVK_ANSI_3, "4": kVK_ANSI_4, "5": kVK_ANSI_5, "6": kVK_ANSI_6,
        "7": kVK_ANSI_7, "8": kVK_ANSI_8, "9": kVK_ANSI_9, "`": kVK_ANSI_Grave, "space": kVK_Space, "↩": kVK_Return,
        "←": kVK_LeftArrow, "→": kVK_RightArrow, "↑": kVK_UpArrow, "↓": kVK_DownArrow, ";": kVK_ANSI_Semicolon,
        ",": kVK_ANSI_Comma, ".": kVK_ANSI_Period, "/": kVK_ANSI_Slash, "\\": kVK_ANSI_Backslash,
    ]

    /// Register (or clear, with nil) the system-wide shortcut. Returns false if it could not be registered.
    @discardableResult
    static func setGlobalHotKey(_ s: Shortcut?) -> Bool {
        if let r = hotKeyRef { UnregisterEventHotKey(r); hotKeyRef = nil }
        guard let s, s.isUsableGlobally, let code = keyCodes[s.key] else { return s == nil }
        if !handlerInstalled {
            var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
            InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
                DispatchQueue.main.async { ShortcutBridge.onHotKey?() }
                return noErr
            }, 1, &spec, nil, nil)
            handlerInstalled = true
        }
        var mods: UInt32 = 0
        if s.command { mods |= UInt32(cmdKey) }; if s.shift { mods |= UInt32(shiftKey) }
        if s.option { mods |= UInt32(optionKey) }; if s.control { mods |= UInt32(controlKey) }
        let id = EventHotKeyID(signature: OSType(0x4F4E5246), id: 1)   // "ONRF"
        return RegisterEventHotKey(UInt32(code), mods, id, GetApplicationEventTarget(), 0, &hotKeyRef) == noErr
    }
}
