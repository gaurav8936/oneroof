import AppKit
import SwiftUI
import OneRoofCore

/// A session in its own window (owner, 2026-10-17: "pull out a terminal and launch another window for one row" —
/// like dragging a tab out of a terminal app). The main window lets go of that session's terminal while it is popped out.
final class PopOutWindowController: NSWindowController, NSWindowDelegate {
    let agent: String
    private let model: AppModel
    private var surface: TerminalSurfaceView?
    /// A run terminal's agent session (LAB-598): the window floats over the main window with "Back to agent".
    let parentId: String?

    init(item: BoardItem, model: AppModel, parentId: String? = nil) {
        self.agent = item.liveAgent ?? ""
        self.model = model
        self.parentId = parentId
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1000, height: 680),
                         styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        w.title = "\(item.session.name) · \(item.session.agent.displayName)\(item.account.map { " · \($0)" } ?? "")"
        w.isReleasedWhenClosed = false
        super.init(window: w)
        w.delegate = self
        let dir = Workspace.isInsideProjects(item.session.repoPath) ? item.session.repoPath : Workspace.projectsRoot
        let s = TerminalSurfaceView(command: model.runtime.attachCommand(agent), workingDirectory: dir, theme: model.themes.terminal)
        s.onProcessExit = { [weak self] _ in self?.window?.close() }
        model.wire(s, agent: agent)
        w.contentView = s
        surface = s
        w.center()
        w.setFrameAutosaveName("OneRoofPopOut-" + agent)
        if parentId != nil { makeRunWindow(w, item: item) }
    }

    /// LAB-598: a small window that floats over One Roof (and hides when another app is in front), titled so it is
    /// clear nothing runs until Return, with a "Back to agent" button.
    private func makeRunWindow(_ w: NSWindow, item: BoardItem) {
        w.level = .floating
        w.hidesOnDeactivate = true
        w.title = item.session.name + " · press Return to run"
        if let main = NSApp.mainWindow ?? NSApp.windows.first(where: { $0.windowController is MainWindowController }) {
            let f = main.frame
            w.setFrame(NSRect(x: f.maxX - 760 - 24, y: f.minY + 24, width: 760, height: 360), display: false)
        } else {
            w.setContentSize(NSSize(width: 760, height: 360))
        }
        let back = NSButton(title: "Back to agent", target: self, action: #selector(backToAgent(_:)))
        back.bezelStyle = .rounded
        back.controlSize = .small
        back.toolTip = "Focus the agent session this terminal belongs to"
        back.setAccessibilityLabel("Back to agent")
        let holder = NSView(frame: NSRect(x: 0, y: 0, width: 130, height: 28))
        back.frame = NSRect(x: 4, y: 2, width: 120, height: 24)
        holder.addSubview(back)
        let acc = NSTitlebarAccessoryViewController()
        acc.view = holder
        acc.layoutAttribute = .trailing
        w.addTitlebarAccessoryViewController(acc)
    }

    @objc func backToAgent(_ sender: Any?) {
        guard let parentId else { return }
        // LAB-598: the run window floats, so it stayed on top of the agent's terminal and Back to agent seemed to do
        // nothing (0.5.2.2, 0.5.2.3). Step it out of the way: the terminal keeps running, the next Run in Terminal or
        // its ↳ row (Show window) brings it back.
        window?.orderOut(nil)
        model.showSession(parentId)
        // Then give the agent's own terminal the keyboard once it is shown.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            guard let self, let item = self.model.item(parentId), let agent = item.liveAgent else { return }
            if let r = RoofWindowController.owner(of: agent) { r.window?.makeKeyAndOrderFront(nil); return }
            if let c = PopOutWindowController.open[agent] { c.show(); return }
            guard let main = MainWindowController.forWorkspace(self.model.workspaceId(of: item)) else { return }
            self.model.goTerminals()
            main.window?.makeKeyAndOrderFront(nil)
            main.terminalArea.focusTerminal()
        }
    }

    required init?(coder: NSCoder) { fatalError("not supported") }

    func show() {
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        if let s = surface { window?.makeFirstResponder(s) }
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        WindowCloseGuard.shared.shouldClose(sender, what: "this session's window",
            detail: "The session keeps running and goes back to the main window.")
    }

    func windowWillClose(_ notification: Notification) {
        model.poppedOut.remove(agent)
        PopOutWindowController.open[agent] = nil
    }

    static var open: [String: PopOutWindowController] = [:]

    /// Pop a live session out (or bring its window to the front if it already is).
    static func popOut(_ item: BoardItem, model: AppModel) {
        guard let agent = item.liveAgent else { return }
        if let r = RoofWindowController.owner(of: agent) { r.window?.makeKeyAndOrderFront(nil); return }
        if let c = open[agent] { c.show(); return }
        model.poppedOut.insert(agent)            // the main window releases its terminal first
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            let c = PopOutWindowController(item: item, model: model)
            open[agent] = c
            c.show()
        }
    }

    /// LAB-598: a run terminal in its floating window (or its window brought forward if it already has one).
    static func popOutRun(_ item: BoardItem, parentId: String, model: AppModel) {
        guard let agent = item.liveAgent else { return }
        if let r = RoofWindowController.owner(of: agent) { r.window?.makeKeyAndOrderFront(nil); return }
        if let c = open[agent] { c.show(); return }
        model.poppedOut.insert(agent)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            guard open[agent] == nil else { open[agent]?.show(); return }
            let c = PopOutWindowController(item: item, model: model, parentId: parentId)
            open[agent] = c
            c.show()
        }
    }

    static func bringBack(_ agent: String) {
        if let r = RoofWindowController.owner(of: agent) { r.release(agent); return }
        open[agent]?.window?.close()
    }
}
