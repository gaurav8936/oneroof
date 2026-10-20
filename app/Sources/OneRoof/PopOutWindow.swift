import AppKit
import SwiftUI
import OneRoofCore

/// A session in its own window (owner, 2026-10-17: "pull out a terminal and launch another window for one row" —
/// like dragging a tab out of a terminal app). The main window lets go of that session's terminal while it is popped out.
final class PopOutWindowController: NSWindowController, NSWindowDelegate {
    let agent: String
    private let model: AppModel
    private var surface: TerminalSurfaceView?

    init(item: BoardItem, model: AppModel) {
        self.agent = item.liveAgent ?? ""
        self.model = model
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1000, height: 680),
                         styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        w.title = "\(item.session.name) · \(item.session.agent.displayName)\(item.account.map { " · \($0)" } ?? "")"
        w.isReleasedWhenClosed = false
        super.init(window: w)
        w.delegate = self
        let dir = Workspace.isInsideProjects(item.session.repoPath) ? item.session.repoPath : Workspace.projectsRoot
        let s = TerminalSurfaceView(command: model.runtime.attachCommand(agent), workingDirectory: dir, theme: model.themes.terminal)
        s.onProcessExit = { [weak self] _ in self?.window?.close() }
        w.contentView = s
        surface = s
        w.center()
        w.setFrameAutosaveName("OneRoofPopOut-" + agent)
    }

    required init?(coder: NSCoder) { fatalError("not supported") }

    func show() {
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        if let s = surface { window?.makeFirstResponder(s) }
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

    static func bringBack(_ agent: String) {
        if let r = RoofWindowController.owner(of: agent) { r.release(agent); return }
        open[agent]?.window?.close()
    }
}
