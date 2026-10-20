import AppKit
import Combine
import SwiftUI
import OneRoofCore

/// Centre panel: live terminals (`herdr agent attach <name>` in libghostty) in split panes, or a
/// placeholder for planned / exited sessions. Each pane shows one session; the focused pane follows the sidebar
/// selection, and clicking a pane selects its session. Surfaces are cached per agent so switching is instant.
final class TerminalAreaController: NSViewController {
    private let model: AppModel
    /// The window (workspace) this terminal area belongs to: its selection drives the focused pane.
    let win: WindowState
    private var surfaces: [String: TerminalSurfaceView] = [:]
    private var bag = Set<AnyCancellable>()
    private let body = PaneBody()
    private var shownAgent: String?
    private var findBar: NSHostingView<FindBar>?
    let find = FindState()

    // Split panes
    private(set) var tree: PaneNode { didSet { savePanes() } }
    private(set) var focusedPane: String { didSet { savePanes() } }
    private(set) var zoomed: String?
    private var paneViews: [String: PaneView] = [:]
    private var dividerViews: [PaneDividerView] = []
    private var lastSelected: String?
    private var clickMonitor: Any?
    private var restoredSelection = false

    init(model: AppModel, win: WindowState) {
        self.model = model
        self.win = win
        // Restore the last pane layout; self-tests always start from one pane.
        if !SelfTest.isActive, let data = Prefs.defaults.data(forKey: Self.panesKey(win.id)),
           let saved = try? JSONDecoder().decode(SavedPanes.self, from: data), saved.tree.leaf(saved.focused) != nil {
            tree = saved.tree
            focusedPane = saved.focused
        } else {
            let first = PaneLeaf()
            tree = .leaf(first)
            focusedPane = first.id
        }
        super.init(nibName: nil, bundle: nil)
    }

    private struct SavedPanes: Codable { var tree: PaneNode; var focused: String }
    private static func panesKey(_ id: String) -> String { id == WorkspaceStore.mainId ? "OneRoofPanes" : "OneRoofPanes." + id }

    private var pendingSave: DispatchWorkItem?

    /// Saved half a second after the last change, so dragging a divider does not write on every mouse move.
    private func savePanes() {
        guard !SelfTest.isActive else { return }
        pendingSave?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, let data = try? JSONEncoder().encode(SavedPanes(tree: self.tree, focused: self.focusedPane)) else { return }
            Prefs.defaults.set(data, forKey: Self.panesKey(self.win.id))
        }
        pendingSave = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
    }

    required init?(coder: NSCoder) { fatalError("not supported") }

    deinit { if let clickMonitor { NSEvent.removeMonitor(clickMonitor) } }

    override func loadView() {
        let root = NSView()
        root.wantsLayer = true
        body.translatesAutoresizingMaskIntoConstraints = false
        body.wantsLayer = true
        body.onLayout = { [weak self] in self?.layoutPanes() }
        column.translatesAutoresizingMaskIntoConstraints = false
        column.sizingOptions = []
        root.addSubview(body)
        root.addSubview(column)
        columnWidth = column.widthAnchor.constraint(equalToConstant: 0)
        NSLayoutConstraint.activate([
            body.topAnchor.constraint(equalTo: root.topAnchor),
            body.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            body.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            body.trailingAnchor.constraint(equalTo: column.leadingAnchor),
            column.topAnchor.constraint(equalTo: root.topAnchor),
            column.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            column.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            columnWidth,
        ])
        view = root
    }

    /// The Subagents column (S02 §1.7): shown when the Plan panel is closed and the session has subagents.
    private let column = NSHostingView(rootView: AnyView(EmptyView()))
    private var columnWidth: NSLayoutConstraint!
    var planPanelOpen = true { didSet { if oldValue != planPanelOpen { update() } } }
    /// Raw stream (⌘R): chapters folded open, the plain v0.1 terminal.
    private var raw = false
    /// Summary expanded/collapsed per pane, when the owner toggled it.
    private var summaryOverride: [String: Bool] = [:]
    private var openChapter: [String: Int] = [:]

    override func viewDidLoad() {
        super.viewDidLoad()
        win.$selectedId.combineLatest(model.$items, model.$themes, model.$poppedOut)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _, _, _, _ in self?.update() }
            .store(in: &bag)
        model.$decisions.combineLatest(model.$subagents).receive(on: DispatchQueue.main)
            .sink { [weak self] _, _ in self?.update() }
            .store(in: &bag)
        NotificationCenter.default.addObserver(forName: .rawStream, object: nil, queue: .main) { [weak self] n in
            guard let self, (n.object as? String) == self.win.id else { return }
            self.raw.toggle()
            self.update()
        }
        // A click in a pane focuses it (the terminal still gets the click).
        clickMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] e in
            guard let self, e.window === self.view.window, self.tree.leaves.count > 1 else { return e }
            let p = self.body.convert(e.locationInWindow, from: nil)
            if let (id, _) = self.paneViews.first(where: { !$0.value.isHidden && $0.value.frame.contains(p) }), id != self.focusedPane {
                self.focus(pane: id)
            }
            return e
        }
    }

    private func update() {
        let theme = model.themes.terminal
        let tokens = theme.tokens
        view.layer?.backgroundColor = tokens.background.nsColor.cgColor
        body.layer?.backgroundColor = tokens.border.nsColor.cgColor
        view.appearance = theme.appearance
        for s in surfaces.values where s.theme != theme { s.applyTheme(theme) }

        // Drop surfaces whose agent is gone, or is popped out into its own window.
        let live = Set(model.items.compactMap(\.liveAgent)).subtracting(model.poppedOut)
        for (name, s) in surfaces where !live.contains(name) {
            s.removeFromSuperview()
            surfaces[name] = nil
        }

        // The sidebar selection fills the focused pane, or focuses the pane already showing it.
        let sel = win.selectedId
        if !restoredSelection, !model.items.isEmpty {
            // First update with sessions loaded: select what the restored focused pane shows.
            restoredSelection = true
            if let sid = tree.leaf(focusedPane)?.session, model.item(sid) != nil, sel == nil {
                lastSelected = sid
                win.selectedId = sid
                return
            }
        }
        if sel != lastSelected {
            lastSelected = sel
            if let sel, let l = tree.leafShowing(sel) { focusedPane = l.id }
            else if sel != nil || tree.leaves.count == 1 { tree = tree.setting(focusedPane, session: sel) }
        }

        render(theme: theme)
        updateColumn(theme: theme)
    }

    private func render(theme: ThemeName) {
        let tokens = theme.tokens
        let multi = tree.leaves.count > 1
        let ids = Set(tree.leaves.map(\.id))
        for (id, v) in paneViews where !ids.contains(id) { v.removeFromSuperview(); paneViews[id] = nil }
        if let z = zoomed, !ids.contains(z) { zoomed = nil }

        var shown = Set<String>()
        for leaf in tree.leaves {
            let pv: PaneView
            if let v = paneViews[leaf.id] { pv = v } else {
                pv = PaneView()
                if let findBar { body.addSubview(pv, positioned: .below, relativeTo: findBar) } else { body.addSubview(pv) }
                paneViews[leaf.id] = pv
            }
            let item = leaf.session.flatMap { model.item($0) }
            let focused = leaf.id == focusedPane
            let tall = body.bounds.height >= 520 && !multi
            let expanded = summaryOverride[leaf.id] ?? tall
            let leafId = leaf.id
            pv.setTop(AnyView(PaneTop(model: model, item: item, focused: focused, split: multi, expanded: expanded, raw: raw,
                                      openChapter: openChapter[leafId],
                                      onToggleSummary: { [weak self] in self?.summaryOverride[leafId] = !expanded; self?.update() },
                                      onChapter: { [weak self] i in self?.toggleChapter(leafId, i, item) },
                                      onZoom: { [weak self] in self?.focus(pane: leafId); self?.toggleZoom() },
                                      onClose: { [weak self] in self?.closePane(leafId) })))
            pv.layer?.borderWidth = multi && focused ? 1 : 0
            pv.layer?.borderColor = tokens.accent.nsColor.cgColor
            pv.layer?.backgroundColor = tokens.terminal.background.nsColor.cgColor
            if let item, let agent = item.liveAgent, !model.poppedOut.contains(agent) {
                pv.show(surface: surface(agent: agent, cwd: item.session.repoPath, theme: theme))
                shown.insert(agent)
                if item.session.agent.isAgent {
                    pv.setBottom(AnyView(HintStrip(item: item, raw: raw, onRaw: { [weak self] in
                        guard let self else { return }
                        NotificationCenter.default.post(name: .rawStream, object: self.win.id)
                    }).themed(theme)))
                } else {
                    pv.setBottom(nil)
                }
                if item.status == .needsYou, let d = model.openDecisions.first(where: { $0.sessionId == item.id }) {
                    pv.setOverlay(AnyView(ApprovalCard(model: model, decision: d).themed(theme).padding(.horizontal, 16).padding(.bottom, 10)))
                } else {
                    pv.setOverlay(nil)
                }
            } else {
                pv.setBottom(nil)
                pv.setOverlay(nil)
                pv.show(placeholder: AnyView(PanePlaceholder(item: item, model: model, emptyPane: multi && item == nil).themed(theme)))
            }
        }
        win.visibleInPanes = zoomed.flatMap { tree.leaf($0)?.session }.map { [$0] } ?? Set(tree.leaves.compactMap(\.session))
        // Surfaces not in any pane stay alive, hidden, so switching back is instant.
        for (name, s) in surfaces where !shown.contains(name) {
            if s.superview !== body { s.removeFromSuperview(); body.addSubview(s, positioned: .below, relativeTo: nil) }
            s.isHidden = true
        }
        body.needsLayout = true

        let agent = focusedAgent
        if shownAgent != agent {
            shownAgent = agent
            if let agent, let s = surfaces[agent] {
                DispatchQueue.main.async { [weak s] in
                    guard let s, let w = s.window else { return }
                    w.makeFirstResponder(s)
                }
            }
        }
    }

    /// Expand a finished chapter: scroll the surface to where it starts (a view over the scrollback).
    private func toggleChapter(_ pane: String, _ index: Int, _ item: BoardItem?) {
        if openChapter[pane] == index { openChapter[pane] = nil; terminalAction("scroll_to_bottom"); update(); return }
        openChapter[pane] = index
        let chs = item.flatMap { model.chapters[$0.id] } ?? []
        if let ch = chs.first(where: { $0.index == index }), let last = chs.last {
            let fromBottom = max(0, last.scrollbackRange.upperBound - ch.scrollbackRange.lowerBound)
            terminalAction("scroll_to_bottom")
            terminalAction("scroll_page_lines:-\(fromBottom)")
        }
        update()
    }

    private func updateColumn(theme: ThemeName) {
        let item = model.item(win.selectedId ?? "")
        let show = !planPanelOpen && item.map { !(model.subagents[$0.id] ?? []).isEmpty } == true
        columnWidth.constant = show ? 330 : 0
        column.isHidden = !show
        guard show, let item else { return }
        let m = model, w = win
        column.rootView = AnyView(ScrollView { SubagentList(model: m, item: item, onTrace: { w.traceFocus = item.id; m.show(.subagents, in: w) }).padding(16) }
            .themed(m.themes.plan).background(m.themes.plan.tokens.window.color))
    }

    private var focusedAgent: String? {
        guard let sid = tree.leaf(focusedPane)?.session, let item = model.item(sid), let agent = item.liveAgent,
              !model.poppedOut.contains(agent) else { return nil }
        return agent
    }

    private func surface(agent: String, cwd: String, theme: ThemeName) -> TerminalSurfaceView {
        if let s = surfaces[agent] { return s }
        let dir = Workspace.isInsideProjects(cwd) ? cwd : Workspace.projectsRoot
        let surface = TerminalSurfaceView(command: model.runtime.attachCommand(agent), workingDirectory: dir, theme: theme)
        surface.onSearchTotal = { [weak self] n in self?.find.total = n }
        surface.onSearchSelected = { [weak self] n in self?.find.selected = n }
        surface.onOpenURL = { [weak self] url in self?.openLink(url) }
        surface.onProcessExit = { [weak self] _ in
            // The attach client ended (agent closed or detached): forget it; reselecting reattaches.
            guard let self else { return }
            self.surfaces[agent]?.removeFromSuperview()
            self.surfaces[agent] = nil
            if self.shownAgent == agent { self.shownAgent = nil }
            self.update()
        }
        surfaces[agent] = surface
        return surface
    }

    private func layoutPanes() {
        let r = body.bounds
        let multi = tree.leaves.count > 1
        if let z = zoomed, let pv = paneViews[z] {
            for (id, v) in paneViews { v.isHidden = id != z }
            pv.frame = r
            dividerViews.forEach { $0.isHidden = true }
            return
        }
        let (frames, dividers) = tree.layout(in: r, gap: multi ? 2 : 0)
        for (id, f) in frames { paneViews[id]?.frame = f; paneViews[id]?.isHidden = false }
        while dividerViews.count < dividers.count {
            let d = PaneDividerView()
            d.onDrag = { [weak self] path, ratio in
                guard let self else { return }
                self.tree = self.tree.settingRatio(at: path, ratio)
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

    // MARK: Pane commands (View › Panes)

    func split(sideBySide: Bool) {
        let new = PaneLeaf()
        tree = tree.splitting(focusedPane, sideBySide: sideBySide, new: new)
        zoomed = nil
        focusedPane = new.id
        lastSelected = nil
        if win.selectedId == nil { update() } else { win.selectedId = nil }   // the new pane waits for a pick
    }

    func closePane(_ id: String? = nil) {
        let id = id ?? focusedPane
        guard let t = tree.removing(id) else { return }      // the last pane stays
        tree = t
        if focusedPane == id || tree.leaf(focusedPane) == nil { focusedPane = tree.leaves[0].id }
        syncSelectionToFocus()
    }

    func focus(pane id: String) {
        guard tree.leaf(id) != nil else { return }
        focusedPane = id
        if zoomed != nil { zoomed = id }
        syncSelectionToFocus()
    }

    func moveFocus(_ d: PaneNode.Direction) {
        if let n = tree.neighbor(of: focusedPane, d) { focus(pane: n) }
    }

    func toggleZoom() {
        guard tree.leaves.count > 1 else { return }
        zoomed = zoomed == nil ? focusedPane : nil
        update()
    }

    func evenOut() { tree = tree.evened(); body.needsLayout = true }

    var paneCount: Int { tree.leaves.count }

    /// The selection follows the focused pane (an empty pane clears it, so the sidebar fills it).
    private func syncSelectionToFocus() {
        let sid = tree.leaf(focusedPane)?.session
        lastSelected = sid
        if win.selectedId != sid { win.selectedId = sid } else { update() }
    }

    /// Text currently on screen in the focused terminal (self-test).
    func visibleText() -> String? {
        guard let agent = shownAgent, let s = surfaces[agent] else { return nil }
        return s.screenText()
    }

    /// Run a libghostty binding action on the focused terminal (text size, clear).
    func terminalAction(_ name: String) {
        guard let agent = shownAgent, let s = surfaces[agent] else { return }
        s.bindingAction(name)
    }

    // MARK: Find (⌘F) and links

    func showFind() {
        guard let agent = shownAgent, surfaces[agent] != nil else { return }
        if findBar == nil {
            let h = NSHostingView(rootView: FindBar(state: find, onChange: { [weak self] q in self?.search(q) },
                                                    onNext: { [weak self] in self?.terminalAction("navigate_search:next") },
                                                    onPrevious: { [weak self] in self?.terminalAction("navigate_search:previous") },
                                                    onClose: { [weak self] in self?.hideFind() }))
            h.translatesAutoresizingMaskIntoConstraints = false
            body.addSubview(h, positioned: .above, relativeTo: nil)
            NSLayoutConstraint.activate([
                h.topAnchor.constraint(equalTo: body.topAnchor, constant: 8),
                h.trailingAnchor.constraint(equalTo: body.trailingAnchor, constant: -16),
            ])
            findBar = h
        }
        findBar?.isHidden = false
        find.visible = true
        find.focusToken += 1
    }

    func hideFind() {
        terminalAction("end_search")
        find.visible = false
        find.total = 0; find.selected = -1
        findBar?.isHidden = true
        focusTerminal()
    }

    func findNext() { if find.visible { terminalAction("navigate_search:next") } else { showFind() } }
    func findPrevious() { if find.visible { terminalAction("navigate_search:previous") } }

    private func search(_ q: String) {
        if q.isEmpty { terminalAction("end_search"); find.total = 0; return }
        terminalAction("search:" + q)
    }

    /// ⌘-clicked link: local files (file://, absolute paths, ~/…) open in the centre viewer; web links in the browser.
    private func openLink(_ raw: String) {
        var s = raw
        if s.hasPrefix("file://") { s = URL(string: s)?.path ?? String(s.dropFirst(7)) }
        if s.hasPrefix("~") { s = (s as NSString).expandingTildeInPath }
        let pathOnly = s.split(separator: ":").first.map(String.init) ?? s       // drop :line:col
        if pathOnly.hasPrefix("/"), FileManager.default.fileExists(atPath: pathOnly) {
            model.openInViewer(pathOnly)
        } else if let u = URL(string: raw) {
            NSWorkspace.shared.open(u)
        }
    }

    /// Focus the visible terminal (⌘L / after launch).
    func focusTerminal() {
        guard let agent = shownAgent, let s = surfaces[agent] else { return }
        view.window?.makeFirstResponder(s)
    }
}

/// The pane area: top-left origin (like `PaneNode.layout`), lays panes out by frame.
final class PaneBody: NSView {
    var onLayout: (() -> Void)?
    override var isFlipped: Bool { true }
    override func layout() { super.layout(); onLayout?() }
}

/// One pane (S06 §1.4): chrome on top (header, summary, chapters), the terminal surface or a placeholder, an approval
/// card over the bottom of the surface when the agent needs you, and the hint strip below.
final class PaneView: NSView {
    private var top: NSHostingView<AnyView>?
    private var bottom: NSHostingView<AnyView>?
    private var overlay: NSHostingView<AnyView>?
    private var placeholder: NSHostingView<AnyView>?
    private let content = NSView()
    override var isFlipped: Bool { true }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        addSubview(content)
    }
    required init?(coder: NSCoder) { fatalError("not supported") }

    private func host(_ existing: NSHostingView<AnyView>?, _ view: AnyView?) -> NSHostingView<AnyView>? {
        guard let view else { existing?.isHidden = true; return existing }
        if let existing { existing.rootView = view; existing.isHidden = false; return existing }
        let h = NSHostingView(rootView: view)
        h.sizingOptions = [.intrinsicContentSize]
        addSubview(h)
        return h
    }

    func setTop(_ view: AnyView?) { top = host(top, view); needsLayout = true }
    func setBottom(_ view: AnyView?) { bottom = host(bottom, view); needsLayout = true }
    func setOverlay(_ view: AnyView?) {
        overlay = host(overlay, view)
        if let overlay { addSubview(overlay, positioned: .above, relativeTo: nil) }
        needsLayout = true
    }

    func show(surface: NSView) {
        placeholder?.isHidden = true
        for v in content.subviews where v !== surface && v !== placeholder { v.removeFromSuperview() }
        if surface.superview !== content {
            surface.removeFromSuperview()
            surface.translatesAutoresizingMaskIntoConstraints = true
            surface.autoresizingMask = [.width, .height]
            surface.frame = content.bounds
            content.addSubview(surface)
        }
        surface.isHidden = false
    }

    func show(placeholder view: AnyView) {
        for v in content.subviews where v !== placeholder { v.removeFromSuperview() }
        if let placeholder { placeholder.rootView = view } else {
            let p = NSHostingView(rootView: view)
            p.autoresizingMask = [.width, .height]
            p.frame = content.bounds
            content.addSubview(p)
            placeholder = p
        }
        placeholder?.isHidden = false
    }

    override func layout() {
        super.layout()
        let inset: CGFloat = (layer?.borderWidth ?? 0) > 0 ? 1 : 0
        let w = bounds.width - 2 * inset
        var y = inset
        if let top, !top.isHidden {
            let h = top.fittingSize.height
            top.frame = NSRect(x: inset, y: y, width: w, height: h)
            y += h
        }
        var bottomH: CGFloat = 0
        if let bottom, !bottom.isHidden {
            bottomH = bottom.fittingSize.height
            bottom.frame = NSRect(x: inset, y: bounds.height - inset - bottomH, width: w, height: bottomH)
        }
        content.frame = NSRect(x: inset, y: y, width: w, height: max(0, bounds.height - y - bottomH - inset))
        for v in content.subviews { v.frame = content.bounds }
        if let overlay, !overlay.isHidden {
            let h = min(overlay.fittingSize.height, content.frame.height)
            overlay.frame = NSRect(x: inset, y: content.frame.maxY - h, width: w, height: h)
        }
    }
}

/// A divider between two panes: drag to resize.
final class PaneDividerView: NSView {
    var divider: PaneNode.Divider?
    var onDrag: (([Bool], Double) -> Void)?
    override var isFlipped: Bool { true }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: divider?.sideBySide == false ? .resizeUpDown : .resizeLeftRight)
    }

    override func mouseDragged(with event: NSEvent) {
        guard let d = divider, let sv = superview else { return }
        let p = sv.convert(event.locationInWindow, from: nil)
        let ratio = d.sideBySide ? (p.x - d.parent.minX) / max(d.parent.width, 1) : (p.y - d.parent.minY) / max(d.parent.height, 1)
        onDrag?(d.path, Double(ratio))
    }
}

final class FindState: ObservableObject {
    @Published var visible = false
    @Published var total = 0
    @Published var selected = -1
    @Published var focusToken = 0
}

/// Find in terminal (⌘F): libghostty highlights matches; Return / ⇧Return move between them; Esc closes.
struct FindBar: View {
    @ObservedObject var state: FindState
    let onChange: (String) -> Void
    let onNext: () -> Void
    let onPrevious: () -> Void
    let onClose: () -> Void
    @State private var query = ""
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Find in terminal", text: $query)
                .textFieldStyle(.plain).frame(width: 220).focused($focused)
                .onChange(of: query) { _, q in onChange(q) }
                .onSubmit { NSEvent.modifierFlags.contains(.shift) ? onPrevious() : onNext() }
                .onExitCommand(perform: onClose)
            Text(query.isEmpty ? "" : state.total == 0 ? "no matches" : "\(max(state.selected + 1, 1)) of \(state.total)")
                .font(.system(size: 11, design: .rounded)).foregroundStyle(.secondary).frame(minWidth: 64, alignment: .trailing)
            Button(action: onPrevious) { Image(systemName: "chevron.up") }.buttonStyle(.borderless).disabled(state.total == 0)
            Button(action: onNext) { Image(systemName: "chevron.down") }.buttonStyle(.borderless).disabled(state.total == 0)
            Button(action: onClose) { Image(systemName: "xmark.circle.fill") }.buttonStyle(.borderless)
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 9).fill(.regularMaterial))
        .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(Color.primary.opacity(0.12)))
        .shadow(color: .black.opacity(0.25), radius: 6, y: 2)
        .onChange(of: state.focusToken) { _, _ in focused = true }
        .onAppear { focused = true }
    }
}
