import AppKit
import SwiftUI
import Combine
import OneRoofCore

/// A roof window: every live session of one repo or workstream, side by side in its own window. New
/// sessions in that scope join it; closing the window hands them back to the main window. Like a pop-out, the
/// main window lets go of a session's terminal while a roof window holds it (one attach client per agent).
final class RoofWindowController: NSWindowController, NSWindowDelegate {
    let scope: RoofScope
    private let model: AppModel
    private let body = PaneBody()
    private var tree: PaneNode?
    private var paneViews: [String: PaneView] = [:]      // by session id
    private var dividerViews: [PaneDividerView] = []
    private var surfaces: [String: TerminalSurfaceView] = [:]   // by session id
    /// Agents this window holds (added to `model.poppedOut` so the main window releases them).
    private(set) var claimed: Set<String> = []
    /// Agents handed back with "Bring back here": they stay in the main window until this window closes.
    private var released: Set<String> = []
    private var focused: String?
    private var zoomed: String?
    private var bag = Set<AnyCancellable>()

    init(scope: RoofScope, model: AppModel) {
        self.scope = scope
        self.model = model
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1300, height: 820),
                         styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        w.isReleasedWhenClosed = false
        w.minSize = NSSize(width: 600, height: 400)
        super.init(window: w)
        w.delegate = self
        w.contentView = body
        body.wantsLayer = true
        body.onLayout = { [weak self] in self?.layoutPanes() }
        w.center()
        if !SelfTest.isActive { w.setFrameAutosaveName("OneRoofRoof-" + scope.title) }
        model.$items.combineLatest(model.$themes, model.$poppedOut).receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.update() }.store(in: &bag)
    }

    required init?(coder: NSCoder) { fatalError("not supported") }

    // MARK: Open windows

    static var open: [RoofScope: RoofWindowController] = [:]

    /// Open (or bring forward) the roof window for `scope`.
    static func show(_ scope: RoofScope, model: AppModel) {
        let c = open[scope] ?? RoofWindowController(scope: scope, model: model)
        open[scope] = c
        c.showWindow(nil)
        c.window?.makeKeyAndOrderFront(nil)
        c.update()
    }

    /// The roof window holding a session, if any.
    static func owner(of agent: String) -> RoofWindowController? { open.values.first { $0.claimed.contains(agent) } }

    /// "Bring back here" from the main window: this window lets the session go (until it is reopened).
    func release(_ agent: String) {
        released.insert(agent)
        claimed.remove(agent)
        model.poppedOut.remove(agent)
        update()
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        WindowCloseGuard.shared.shouldClose(sender, what: "this roof window",
            detail: "Its sessions keep running and go back to the main window.")
    }

    func windowWillClose(_ notification: Notification) {
        bag.removeAll()
        surfaces.values.forEach { $0.removeFromSuperview() }
        surfaces = [:]
        model.poppedOut.subtract(claimed)
        claimed = []
        RoofWindowController.open[scope] = nil
    }

    // MARK: Panes

    private func update() {
        guard let window, window.isVisible || RoofWindowController.open[scope] === self else { return }
        // Sessions in scope, minus ones another window (pop-out or roof) already holds or the owner brought back.
        let mine = scope.sessions(in: model.items).filter { i in
            guard let a = i.liveAgent, !released.contains(a) else { return false }
            return claimed.contains(a) || !model.poppedOut.contains(a)
        }
        let agents = Set(mine.compactMap(\.liveAgent))
        // Claim new agents; the main window drops its attach client first, so attach a moment later (as pop-out does).
        let fresh = agents.subtracting(claimed)
        if !fresh.isEmpty {
            claimed.formUnion(fresh)
            model.poppedOut.formUnion(fresh)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in self?.update() }
        }
        for gone in claimed.subtracting(agents) {
            claimed.remove(gone)
            surfaces[gone]?.removeFromSuperview()
            surfaces[gone] = nil
            model.poppedOut.remove(gone)
        }

        let theme = model.themes.terminal
        let tokens = theme.tokens
        body.layer?.backgroundColor = tokens.background.nsColor.cgColor
        window.title = "\(scope.title) · \(mine.count) session\(mine.count == 1 ? "" : "s")"
        let ids = mine.map(\.id)
        if tree?.leaves.map(\.id) != ids { tree = PaneNode.grid(ids) }
        if focused == nil || !ids.contains(focused!) { focused = ids.first }
        if let z = zoomed, !ids.contains(z) { zoomed = nil }
        for (id, v) in paneViews where !ids.contains(id) { v.removeFromSuperview(); paneViews[id] = nil }

        for item in mine {
            guard let agent = item.liveAgent else { continue }
            let pv: PaneView
            if let v = paneViews[item.id] { pv = v } else { pv = PaneView(); body.addSubview(pv); paneViews[item.id] = pv }
            let isFocused = item.id == focused
            pv.setTop(AnyView(PaneHeader(model: model, item: item, focused: isFocused, split: true,
                                         onZoom: { [weak self] in self?.toggleZoom(item.id) },
                                         onClose: { [weak self] in self?.release(agent) })
                .themed(theme)))
            pv.layer?.borderWidth = ids.count > 1 && isFocused ? 1 : 0
            pv.layer?.borderColor = tokens.accent.nsColor.cgColor
            pv.layer?.backgroundColor = tokens.terminal.background.nsColor.cgColor
            if fresh.contains(agent) && surfaces[agent] == nil {
                pv.show(placeholder: AnyView(Text("Attaching…").foregroundStyle(tokens.secondaryText.color)))
            } else {
                pv.show(surface: surface(agent: agent, cwd: item.session.repoPath, theme: theme))
            }
        }
        if mine.isEmpty {
            let pv = paneViews["_empty"] ?? { let v = PaneView(); body.addSubview(v); paneViews["_empty"] = v; return v }()
            pv.setTop(nil)
            pv.show(placeholder: AnyView(RoofEmpty(scope: scope, tokens: tokens).environment(\.colorScheme, theme.colorScheme)))
            tree = .leaf(PaneLeaf(id: "_empty"))
        }
        body.needsLayout = true
    }

    private func toggleZoom(_ id: String) {
        zoomed = zoomed == id ? nil : id
        focus(id)
    }

    private func focus(_ id: String) {
        focused = id
        update()
        if let agent = model.item(id)?.liveAgent, let s = surfaces[agent] { window?.makeFirstResponder(s) }
    }

    private func surface(agent: String, cwd: String, theme: ThemeName) -> TerminalSurfaceView {
        if let s = surfaces[agent] { return s }
        let dir = Workspace.isInsideProjects(cwd) ? cwd : Workspace.projectsRoot
        let s = TerminalSurfaceView(command: model.runtime.attachCommand(agent), workingDirectory: dir, theme: theme)
        s.onProcessExit = { [weak self] _ in
            self?.surfaces[agent]?.removeFromSuperview()
            self?.surfaces[agent] = nil
            self?.update()
        }
        surfaces[agent] = s
        return s
    }

    private func layoutPanes() {
        guard let tree else { return }
        if let z = zoomed, let pv = paneViews[z] {
            for (id, v) in paneViews { v.isHidden = id != z }
            pv.frame = body.bounds
            dividerViews.forEach { $0.isHidden = true }
            return
        }
        paneViews.values.forEach { $0.isHidden = false }
        let multi = tree.leaves.count > 1
        let (frames, dividers) = tree.layout(in: body.bounds, gap: multi ? 2 : 0)
        for (id, f) in frames { paneViews[id]?.frame = f }
        while dividerViews.count < dividers.count {
            let d = PaneDividerView()
            d.onDrag = { [weak self] path, ratio in
                guard let self, let t = self.tree else { return }
                self.tree = t.settingRatio(at: path, ratio)
                self.body.needsLayout = true
            }
            body.addSubview(d)
            dividerViews.append(d)
        }
        for (i, d) in dividerViews.enumerated() {
            guard i < dividers.count else { d.isHidden = true; continue }
            d.divider = dividers[i]
            d.isHidden = false
            d.frame = dividers[i].sideBySide ? dividers[i].rect.insetBy(dx: -3, dy: 0) : dividers[i].rect.insetBy(dx: 0, dy: -3)
        }
    }
}

private struct RoofEmpty: View {
    let scope: RoofScope
    let tokens: ThemeTokens
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "house").font(.system(size: 28)).foregroundStyle(tokens.secondaryText.color)
            Text("No live sessions in \(scope.title)").font(.system(size: 15, weight: .semibold)).foregroundStyle(tokens.text.color)
            Text("Sessions you start here join this window by themselves.")
                .font(.system(size: 12)).foregroundStyle(tokens.secondaryText.color)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
