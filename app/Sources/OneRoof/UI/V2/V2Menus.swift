import AppKit
import OneRoofCore

/// The One Roof 1 menus (handover A11, shared/MENUS.md): today's menus with the v2 names, the new window's keys made
/// visible, Single · Grid · Wall, Look… and Copy Session Output. Built only when the window is the v2 one. Every
/// item keeps its action and key; renamed items keep shortcuts set under their old names (ShortcutBridge.renamed).
extension AppDelegate {
    /// The front main window is the v2 one. False when no main window is left (a pop-out or Roof window alone): menu
    /// validation and the openers then behave as the classic app did, never touching a missing window.
    var isV2Window: Bool { main?.isV2 == true }

    static let v2Renames: [String: String] = [
        "Overview": "Home", "Resources": "Machine", "Decisions": "Needs You", "Work: Projects and Roadmap": "Work",
        "Toggle Sidebar": "Sessions Column", "Toggle Plan Panel": "Plan", "File Browser": "Files Tab", "Review Changes": "Changes",
        "Focus: Terminal Only": "Focus: Step On", "Focus Terminal": "Sessions",
    ]

    func v2AdjustMenus(_ menu: NSMenu?) {
        guard let menu else { return }
        for top in menu.items {
            guard let sub = top.submenu else { continue }
            for i in sub.items {
                if let n = Self.v2Renames[i.title] { i.title = n }
                // The new window's keys, hidden until now: Focus: Step Back and Dock show in View (⌃⌘1-7 stay hidden aliases).
                if ["Focus: Step Back", "Dock", "Split Editor"].contains(i.title) { i.isHidden = false }
            }
            if sub.title == "View" { v2AdjustView(sub) }
            if sub.title == "Edit" { v2AdjustEdit(sub) }
        }
    }

    private func v2AdjustView(_ view: NSMenu) {
        // The four per-panel theme menus go (Look… and Settings › Appearance › Customize each panel hold them);
        // Terminal Theme stays, since Blueprint for the terminal lives only there.
        for i in view.items where i.submenu != nil && i.title.hasSuffix(" Theme") && i.title != "Terminal Theme" { view.removeItem(i) }
        // Sessions (⌘L) opens the Sessions place on the terminal, as Focus Terminal did.
        if let s = view.items.first(where: { $0.title == "Sessions" }) { s.action = #selector(v2OpenSessions(_:)); s.target = self }
        guard let anchor = view.items.firstIndex(where: { $0.title == "Focus: Step On" }) else { return }
        var at = anchor
        let layouts: [(String, Int)] = [("Single", 1), ("Grid", 2), ("Wall", 3)]
        for (title, n) in layouts {
            let mi = NSMenuItem(title: title, action: n == 1 ? #selector(v2LayoutSingle(_:)) : nil, keyEquivalent: String(n))
            mi.keyEquivalentModifierMask = [.command, .option, .control]
            mi.target = self
            if n == 1 { mi.state = .on }
            if n > 1 { mi.toolTip = n == 2 ? "Grid arrives in 1.7.0" : "Wall arrives in 1.8.0" }   // shown, not active yet (CAP-2, CAP-3)
            view.insertItem(mi, at: at); at += 1
        }
        view.insertItem(.separator(), at: at)
        let look = NSMenuItem(title: "Look…", action: #selector(v2ShowLook(_:)), keyEquivalent: "")
        look.target = self
        view.addItem(.separator()); view.addItem(look)
    }

    private func v2AdjustEdit(_ edit: NSMenu) {
        let copy = NSMenuItem(title: "Copy Session Output", action: #selector(copySessionOutput(_:)), keyEquivalent: "")
        copy.target = self
        if let i = edit.items.firstIndex(where: { $0.title == "Clear Terminal" }) { edit.insertItem(copy, at: i + 1) } else { edit.addItem(copy) }
    }

    @objc func v2OpenSessions(_ sender: Any?) {
        if isV2Window { main.v2Open(.sessions) }
        focusTerminal(sender)
    }
    @objc func v2LayoutSingle(_ sender: Any?) {}   // Single is the only layout until Grid (1.7.0); kept for the key and the check mark
    @objc func v2ShowLook(_ sender: Any?) { if isV2Window { main.v2ShowLooks() } else { showSettingsTab(1) } }

    /// Edit › Copy Session Output (NEW-13): the text on the shown session's terminal screen.
    @objc func copySessionOutput(_ sender: Any?) {
        guard let text = main.terminalArea.visibleText(), !text.isEmpty else { NSSound.beep(); return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}
