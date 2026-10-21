import AppKit

/// "Are you sure?" before a One Roof window closes (LAB-252): a sheet with a tick box that must be ticked before
/// Close is enabled. Closing from code (`window.close()`, the self-test, a session's process ending) skips it; only
/// the close button and File ▸ Close Window (⌃⌘W) (`performClose`) ask.
final class WindowCloseGuard: NSObject {
    private var asking: Set<ObjectIdentifier> = []
    static let shared = WindowCloseGuard()

    /// Call from `windowShouldClose`. Shows the sheet (once) and returns false; a confirmed sheet closes the window.
    func shouldClose(_ window: NSWindow, what: String, detail: String) -> Bool {
        let id = ObjectIdentifier(window)
        if SelfTest.isActive { return true }
        guard !asking.contains(id) else { return false }
        asking.insert(id)
        let a = NSAlert()
        a.messageText = "Close \(what)?"
        a.informativeText = detail
        let close = a.addButton(withTitle: "Close")
        a.addButton(withTitle: "Cancel")
        close.isEnabled = false
        close.keyEquivalent = ""                     // Return must not close it before the box is ticked
        a.buttons[1].keyEquivalent = "\u{1b}"
        let tick = NSButton(checkboxWithTitle: "Yes, I'm sure", target: self, action: #selector(toggled(_:)))
        tick.state = .off
        tick.setAccessibilityLabel("Confirm closing the window")
        objc_setAssociatedObject(tick, &Self.buttonKey, close, .OBJC_ASSOCIATION_ASSIGN)
        a.accessoryView = tick
        a.beginSheetModal(for: window) { [weak self, weak window] r in
            guard let self, let window else { return }
            self.asking.remove(id)
            guard r == .alertFirstButtonReturn, tick.state == .on else { return }
            // LAB-298: performClose did nothing here (the sheet is still attached while this handler runs, and
            // performClose refuses a window with a sheet). Close on the next turn, directly: it is already confirmed.
            DispatchQueue.main.async { window.close() }
        }
        DispatchQueue.main.async { a.window.makeFirstResponder(tick) }
        return false
    }

    private static var buttonKey = 0

    @objc private func toggled(_ sender: NSButton) {
        guard let close = objc_getAssociatedObject(sender, &Self.buttonKey) as? NSButton else { return }
        close.isEnabled = sender.state == .on
        close.keyEquivalent = sender.state == .on ? "\r" : ""
    }
}
