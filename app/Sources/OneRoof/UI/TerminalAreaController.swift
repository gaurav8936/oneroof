import AppKit
import Combine
import SwiftUI
import OneRoofCore

/// Centre panel: live terminals (`roofd attach <id>` in libghostty) in split panes, or a
/// placeholder for planned / exited sessions. Each pane shows one session; the focused pane follows the sidebar
/// selection, and clicking a pane selects its session. Surfaces are cached per agent so switching is instant.
final class TerminalAreaController: NSViewController {
    private let model: AppModel
    /// The window (workspace) this terminal area belongs to: its selection drives the focused pane.
    let win: WindowState
    private var surfaces: [String: TerminalSurfaceView] = [:]
    /// LAB-290: roofd lets one terminal show a session. A refused attach exits at once; without these the pane rebuilt
    /// the surface on every exit and looped (the blinking window, and a frozen one beside it).
    private var surfaceBorn: [String: Date] = [:]
    private var refused: [String: Int] = [:]
    private var bag = Set<AnyCancellable>()
    private let body = PaneBody()
    /// LAB-1239: the pane area scrolls when the Grid's rows do not fit (it is exactly the viewport otherwise).
    private let scroll = PaneScrollView()
    private var shownAgent: String?
    private var findBar: NSHostingView<FindBar>?
    let find = FindState()

    // Split panes
    private(set) var tree: PaneNode { didSet { savePanes() } }
    private(set) var focusedPane: String { didSet { savePanes() } }
    private(set) var zoomed: String?
    private var paneViews: [String: PaneView] = [:]
    /// Grid (A4.1): the Single layout's panes while the Grid shows, put back on Single.
    private var singleTree: (tree: PaneNode, focused: String)?
    /// Set when a click lands in a pane's composer: the next focus change leaves the keyboard where the click put it.
    private var keepKeyboardOnce = false

    /// Self-test (LAB-521): each pane's top strip height as laid out and as its content needs it.
    func topHeights() -> [(frame: CGFloat, needs: CGFloat)] { paneViews.values.filter { !$0.isHidden }.compactMap(\.topHeights) }
    private var dividerViews: [PaneDividerView] = []
    private var lastSelected: String?
    private var clickMonitor: Any?
    private var restoredSelection = false

    init(model: AppModel, win: WindowState) {
        self.model = model
        self.win = win
        // Restore the last pane layout; self-tests always start from one pane.
        if !SelfTest.isActive || Prefs.seeded, let data = Prefs.defaults.data(forKey: Self.panesKey(win.id)),
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
    static func panesKey(_ id: String) -> String { id == WorkspaceStore.mainId ? "OneRoofPanes" : "OneRoofPanes." + id }

    private var pendingSave: DispatchWorkItem?

    /// Saved half a second after the last change, so dragging a divider does not write on every mouse move.
    private func savePanes() {
        guard !SelfTest.isActive, singleTree == nil else { return }   // the Grid is built, never saved over your panes
        pendingSave?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.singleTree == nil, let data = try? JSONEncoder().encode(SavedPanes(tree: self.tree, focused: self.focusedPane)) else { return }
            Prefs.defaults.set(data, forKey: Self.panesKey(self.win.id))
        }
        pendingSave = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
    }

    required init?(coder: NSCoder) { fatalError("not supported") }

    deinit {
        if let clickMonitor { NSEvent.removeMonitor(clickMonitor) }
        foregroundTimer?.invalidate()
    }

    override func loadView() {
        let root = NSView()
        root.wantsLayer = true
        body.wantsLayer = true
        body.onLayout = { [weak self] in self?.layoutPanes() }
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = false
        scroll.autohidesScrollers = true
        scroll.horizontalScrollElasticity = .none
        scroll.verticalScrollElasticity = .none
        scroll.automaticallyAdjustsContentInsets = false
        scroll.contentInsets = NSEdgeInsetsZero
        scroll.documentView = body
        scroll.onTile = { [weak self] in self?.sizeBody() }
        column.translatesAutoresizingMaskIntoConstraints = false
        column.sizingOptions = []
        root.addSubview(scroll)
        root.addSubview(column)
        columnWidth = column.widthAnchor.constraint(equalToConstant: 0)
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: root.topAnchor),
            scroll.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            scroll.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            scroll.trailingAnchor.constraint(equalTo: column.leadingAnchor),
            column.topAnchor.constraint(equalTo: root.topAnchor),
            column.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            column.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            columnWidth,
        ])
        view = root
    }

    /// The Subagents column (S02 §1.7): shown when the Plan panel is closed and the session has subagents. Classic
    /// window only: the v2 window reaches subagents from the session's Subagents tab (LAB-1240, owner 1.8.2).
    private let column = NSHostingView(rootView: AnyView(EmptyView()))
    private var columnWidth: NSLayoutConstraint!
    var planPanelOpen = true { didSet { if oldValue != planPanelOpen { update() } } }
    var showsSubagentColumn = true { didSet { if oldValue != showsSubagentColumn, isViewLoaded { update() } } }
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
        win.$layout.removeDuplicates().receive(on: DispatchQueue.main).sink { [weak self] l in self?.applyLayout(l) }.store(in: &bag)
        model.$decisions.combineLatest(model.$subagents).receive(on: DispatchQueue.main)
            .sink { [weak self] _, _ in self?.update() }
            .store(in: &bag)
        // LAB-861: what each shown pane's keys go to, every 2 s (only while the window is on screen).
        foregroundTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] t in
            guard let self else { t.invalidate(); return }
            self.pollForeground()
        }
        NotificationCenter.default.addObserver(forName: .rawStream, object: nil, queue: .main) { [weak self] n in
            guard let self, (n.object as? String) == self.win.id else { return }
            self.raw.toggle()
            self.update()
        }
        // Another window is about to show a session: let go of our terminal for it (only a hidden one, unless forced).
        NotificationCenter.default.addObserver(forName: .releaseSurface, object: nil, queue: .main) { [weak self] n in
            // A session moved into this window (LAB-707): show it, even if it was handed away from here before.
            if let self, let agent = n.object as? String, (n.userInfo?["win"] as? String) == self.win.id,
               (n.userInfo?["moved"] as? Bool) == true { self.refused[agent] = nil }
            guard let self, let agent = n.object as? String, (n.userInfo?["win"] as? String) != self.win.id,
                  let s = self.surfaces[agent], s.isHidden || (n.userInfo?["force"] as? Bool) == true else { return }
            s.onProcessExit = nil
            s.removeFromSuperview()
            self.surfaces[agent] = nil
            if self.shownAgent == agent { self.shownAgent = nil }
            // Handed over on purpose: this pane says where it went, instead of attaching again and winning it back.
            // A session moved to another window (LAB-707) has left this one: nothing to say, and moving it back shows it.
            if (n.userInfo?["moved"] as? Bool) == true { self.refused[agent] = nil; self.update() }
            else if !s.isHidden { self.refused[agent] = 2; self.update() }
        }
        // A click in a pane focuses it (the terminal still gets the click).
        clickMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] e in
            guard let self, e.window === self.view.window, self.tree.leaves.count > 1 else { return e }
            let p = self.body.convert(e.locationInWindow, from: nil)
            if let (id, pv) = self.paneViews.first(where: { !$0.value.isHidden && $0.value.frame.contains(p) }), id != self.focusedPane {
                // A click into the pane's composer: the composer keeps the keyboard, not the pane's terminal.
                if pv.bottomContains(self.body.convert(p, to: pv)) { self.keepKeyboardOnce = true }
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
                body.addSubview(pv)
                paneViews[leaf.id] = pv
            }
            let item = leaf.session.flatMap { model.item($0) }
            let focused = leaf.id == focusedPane
            // LAB-1270: the summary starts as its one-line strip, so the terminal gets the room; ▾ opens the card.
            let expanded = summaryOverride[leaf.id] ?? false
            let leafId = leaf.id
            let liveSurface = item.flatMap(\.liveAgent).map { !model.poppedOut.contains($0) && (refused[$0] ?? 0) < 2 } ?? false
            let runningCmd = liveSurface ? item.flatMap { running[$0.id] } : nil
            pv.setTop(AnyView(PaneTop(model: model, item: item, focused: focused, split: multi, expanded: expanded, raw: raw,
                                      openChapter: openChapter[leafId],
                                      onToggleSummary: { [weak self] in self?.summaryOverride[leafId] = !expanded; self?.update() },
                                      onChapter: { [weak self] i in self?.toggleChapter(leafId, i, item) },
                                      onZoom: { [weak self] in self?.focus(pane: leafId); self?.toggleZoom() },
                                      onClose: { [weak self] in self?.closePane(leafId) },
                                      reading: reading.contains(leafId),
                                      onReading: liveSurface ? { [weak self] in self?.toggleReading(leafId) } : nil,
                                      onNewTerminal: { [weak self] in self?.newTerminal(in: item?.session.repoPath) },
                                      running: runningCmd,
                                      onStop: runningCmd == nil ? nil : { [weak self] in if let item { self?.stopForeground(item) } })))
            pv.layer?.borderWidth = multi && focused ? 1 : 0
            pv.layer?.borderColor = tokens.accent.nsColor.cgColor
            pv.layer?.backgroundColor = tokens.terminal.background.nsColor.cgColor
            if let item, let agent = item.liveAgent, !model.poppedOut.contains(agent), (refused[agent] ?? 0) >= 2 {
                pv.setBottom(nil)
                pv.setOverlay(nil)
                pv.setFloat(nil)
                pv.show(placeholder: AnyView(ShownElsewherePlaceholder(onShowHere: { [weak self] in self?.showHere(agent) }).themed(theme)))
            } else if let item, let agent = item.liveAgent, !model.poppedOut.contains(agent) {
                let sv = surface(agent: agent, cwd: item.session.repoPath, theme: theme, size: pv.surfaceSize(fallback: body.bounds.size))
                pv.show(surface: sv)
                shown.insert(agent)
                pv.setReading(reading.contains(leaf.id) ? ReadingText.prepare(sv.allText() ?? "") : nil, theme: theme)
                // LAB-825: viewing an earlier step and not at the live bottom: a second way back, at the bottom.
                if let open = openChapter[leafId], !raw, sv.atScrollBottom != true {
                    pv.setFloat(AnyView(BackToCurrentPill { [weak self] in self?.toggleChapter(leafId, open, item) }.themed(theme)))
                } else {
                    pv.setFloat(nil)
                }
                if item.session.agent.isAgent {
                    let onRaw: () -> Void = { [weak self] in
                        guard let self else { return }
                        NotificationCenter.default.post(name: .rawStream, object: self.win.id)
                    }
                    // v2 (NEW-1): a real composer under the terminal; the classic window keeps the hint strip.
                    pv.setBottom(model.settings.ui2 ? AnyView(V2Composer(model: model, item: item, raw: raw, onRaw: onRaw).themed(theme))
                                                    : AnyView(HintStrip(item: item, raw: raw, onRaw: onRaw).themed(theme)))
                } else {
                    pv.setBottom(nil)
                }
                if item.status == .needsYou, let d = model.openDecisions.first(where: { $0.sessionId == item.id }) {
                    pv.setOverlay(AnyView(ApprovalCard(model: model, decision: d).themed(theme).padding(.horizontal, 16).padding(.bottom, 10)))
                } else if StartingStrip.shows(item) {
                    // LAB-299: the terminal shows at once; this says the agent is still starting.
                    pv.setOverlay(AnyView(StartingStrip(item: item).themed(theme)))
                } else {
                    pv.setOverlay(nil)
                }
            } else {
                pv.setBottom(nil)
                pv.setOverlay(nil)
                pv.setFloat(nil)
                pv.setReading(nil, theme: theme)
                pv.show(placeholder: AnyView(PanePlaceholder(item: item, model: model, emptyPane: multi && item == nil,
                                                             onNewTerminal: { [weak self] in self?.newTerminal(in: nil) }).themed(theme)))
            }
        }
        reading.formIntersection(ids)
        syncReadingTimer()
        win.visibleInPanes = zoomed.flatMap { tree.leaf($0)?.session }.map { [$0] } ?? Set(tree.leaves.compactMap(\.session))
        // Surfaces not in any pane stay alive, hidden, so switching back is instant.
        for (name, s) in surfaces where !shown.contains(name) {
            if s.superview !== body { s.removeFromSuperview(); body.addSubview(s, positioned: .below, relativeTo: nil) }
            s.isHidden = true
        }
        sizeBody()
        body.needsLayout = true

        let agent = focusedAgent
        let keep = keepKeyboardOnce
        keepKeyboardOnce = false
        if shownAgent != agent {
            shownAgent = agent
            if !keep, let agent, let s = surfaces[agent] {
                DispatchQueue.main.async { [weak s] in
                    guard let s, let w = s.window else { return }
                    w.makeFirstResponder(s)
                }
            }
        }
    }

    /// Single ↔ Grid (handover A4, NEW-2; LAB-1239). Grid: every live session of this window (popped-out ones left out),
    /// the selected one first, two tiles across and as many rows as they need; the area scrolls when the rows do not
    /// fit (`GridMetrics`). The focus ring, ⌥⌘arrows (scrolling the tile into view), split and close work as on panes.
    /// Single puts your own panes back. Wall is its own page (V2Wall).
    private func applyLayout(_ l: SessionLayout) {
        switch l {
        case .grid:
            guard singleTree == nil, model.settings.ui2 else { return }   // the classic window has no Grid
            pendingSave?.cancel()   // a save queued just before must not write the Grid over your panes
            singleTree = (tree, focusedPane)
            var ids: [String] = []
            if let sel = win.selectedId, model.item(sel)?.liveAgent != nil { ids.append(sel) }
            let rank: (BoardItem) -> Int = { i in i.status == .needsYou ? 0 : i.status == .running ? 1 : 2 }
            for i in model.items(in: win).filter({ $0.liveAgent.map { !model.poppedOut.contains($0) } ?? false && !ids.contains($0.id) }).sorted(by: { rank($0) < rank($1) }) { ids.append(i.id) }
            zoomed = nil
            tree = PaneNode.grid(ids.map { Optional($0) }, columns: GridMetrics.columns)
            focusedPane = tree.leaves.first?.id ?? focusedPane
            update()
            scroll.contentView.scroll(to: .zero)
            scroll.reflectScrolledClipView(scroll.contentView)
        case .single, .wall:
            guard let s = singleTree else { return }
            singleTree = nil
            tree = s.tree; focusedPane = s.focused
            if let sel = win.selectedId, let leaf = tree.leafShowing(sel) { focusedPane = leaf.id }
            // A session chosen in the Grid that your panes do not show fills the focused pane, as a pick in the column
            // does (1.8.1 showed the old pane under the new session's name).
            else if win.selectedId != nil { lastSelected = nil }
            update()
            scroll.contentView.scroll(to: .zero)
            scroll.reflectScrolledClipView(scroll.contentView)
        }
    }

    /// "Show here": take the session from the window showing it (LAB-290).
    private func showHere(_ agent: String) {
        NotificationCenter.default.post(name: .releaseSurface, object: agent, userInfo: ["win": win.id, "force": true])
        refused[agent] = nil
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in self?.update() }
    }

    /// Rewind to a step (LAB-259): scroll the surface to where the step starts, a view over the scrollback; the owner
    /// scrolls on from there. The same step again (or Back to current) returns to the live bottom.
    private func toggleChapter(_ pane: String, _ index: Int, _ item: BoardItem?) {
        if openChapter[pane] == index {
            openChapter[pane] = nil
            if let item { model.reviewStep[item.id] = nil }
            terminalAction("scroll_to_bottom"); update(); return
        }
        openChapter[pane] = index
        // LAB-825: the pill shows until the terminal reports its viewport back at the live bottom.
        if let agent = item?.liveAgent { surfaces[agent]?.atScrollBottom = false }
        update()
        let chs = item.flatMap { model.chapters[$0.id] } ?? []
        guard let item, let ch = chs.first(where: { $0.index == index }) else { return }
        // The right panel's Step review follows the step (LAB-260), and reads it at once.
        model.reviewStep[item.id] = index
        if model.settings.stepReview, ch.ended != nil, model.stepExplanations[AppModel.stepKey(item, ch)] == nil {
            model.explainStep(item, ch)
        }
        // Where the step starts, read fresh from the session (the chapter list only covers its last 300 lines).
        let fallback = chs.last.map { max(0, $0.scrollbackRange.upperBound - ch.scrollbackRange.lowerBound) }
        model.stepOffset(item, ch) { [weak self] n in
            guard let self, self.openChapter[pane] == index, let lines = n ?? fallback else { return }
            self.terminalAction("scroll_to_bottom")
            self.terminalAction("scroll_page_lines:-\(lines)")
        }
    }

    private func updateColumn(theme: ThemeName) {
        let item = model.item(win.selectedId ?? "")
        let show = showsSubagentColumn && !planPanelOpen && item.map { !(model.subagents[$0.id] ?? []).isEmpty } == true
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

    /// When each session's terminal surface was last made (for the retry above).
    private var surfaceTried: [String: Date] = [:]

    private func surface(agent: String, cwd: String, theme: ThemeName, size: NSSize) -> TerminalSurfaceView {
        if let s = surfaces[agent] {
            // libghostty cannot make a surface while the screen is locked (no GPU): a session started then (a scheduled
            // run overnight) had a blank pane for good. Try again, at most every 5 s, until it has one.
            guard s.surface == nil, Date().timeIntervalSince(surfaceTried[agent] ?? .distantPast) > 5 else { return s }
            s.removeFromSuperview()
            surfaces[agent] = nil
        }
        surfaceTried[agent] = Date()
        surfaceBorn[agent] = Date()
        NotificationCenter.default.post(name: .releaseSurface, object: agent, userInfo: ["win": win.id])
        let dir = Workspace.isInsideProjects(cwd) ? cwd : Workspace.projectsRoot
        let surface = TerminalSurfaceView(command: model.runtime.attachCommand(agent), workingDirectory: dir, theme: theme, size: size)
        surface.onSearchTotal = { [weak self] n in self?.find.total = n }
        surface.onSearchSelected = { [weak self] n in self?.find.selected = n }
        surface.onOpenURL = { [weak self] url in self?.openLink(url) }
        // LAB-825: the floating Back to current follows the viewport (only matters while a step is open).
        surface.onScrollBottom = { [weak self] _ in
            guard let self, !self.openChapter.isEmpty else { return }
            self.update()
        }
        model.wire(surface, agent: agent)
        // LAB-745: right-click › New Terminal Here / Split Right with New Terminal, in this session's folder.
        surface.onNewTerminal = { [weak self] split in
            guard let self else { return }
            if let l = self.tree.leaves.first(where: { $0.session.flatMap { self.model.item($0)?.liveAgent } == agent }) {
                self.focus(pane: l.id)
            }
            if split { self.splitWithNewTerminal(sideBySide: true, in: cwd) } else { self.newTerminal(in: cwd) }
        }
        surface.onProcessExit = { [weak self] _ in
            // The attach client ended (agent closed or detached): forget it; reselecting reattaches.
            guard let self else { return }
            self.surfaces[agent]?.removeFromSuperview()
            self.surfaces[agent] = nil
            if self.shownAgent == agent { self.shownAgent = nil }
            // Refused (another window holds the session): try once more after the other window let go, then stop.
            if Date().timeIntervalSince(self.surfaceBorn[agent] ?? .distantPast) < 3 {
                let n = (self.refused[agent] ?? 0) + 1
                self.refused[agent] = n
                if n == 1 { DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in self?.update() } }
                else { self.update() }
                return
            }
            self.refused[agent] = nil
            self.update()
        }
        surfaces[agent] = surface
        return surface
    }

    /// The pane area's size: the viewport, or taller in the Grid when its rows need more than the window has (LAB-1239).
    private func sizeBody() {
        let clip = scroll.contentView.bounds.size
        var h = clip.height
        if singleTree != nil, zoomed == nil {
            h = GridMetrics.contentHeight(rows: tree.chainCount(sideBySide: false), viewport: clip.height, gap: 2)
        }
        let size = NSSize(width: clip.width, height: h)
        if body.frame.size != size { body.setFrameSize(size); body.needsLayout = true }
        scroll.verticalScrollElasticity = h > clip.height + 0.5 ? .automatic : .none
    }

    /// The Grid scrolls the focused tile into view (⌥⌘arrows, a click, a pick in the column).
    private var scrolledTo: String?
    private func scrollFocusedIntoView() {
        guard singleTree != nil, zoomed == nil, scrolledTo != focusedPane, let pv = paneViews[focusedPane] else { return }
        scrolledTo = focusedPane
        let visible = scroll.contentView.bounds
        guard body.frame.height > visible.height + 0.5 else { return }
        let y = GridMetrics.scrollOffset(showing: pv.frame, visible: visible)
        guard abs(y - visible.minY) > 0.5 else { return }
        scroll.contentView.scroll(to: NSPoint(x: 0, y: min(max(0, y), body.frame.height - visible.height)))
        scroll.reflectScrolledClipView(scroll.contentView)
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
        if singleTree == nil { scrolledTo = nil } else { DispatchQueue.main.async { [weak self] in self?.scrollFocusedIntoView() } }
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

    // MARK: What the keys go to (LAB-861)

    private var foregroundTimer: Timer?
    private var polling = false
    /// Session id → the command its pane's keys go to (nil = the shell or the session's agent).
    private var running: [String: String] = [:]

    /// Ask roofd for the foreground process group of each live pane on screen (off the main thread), and redraw the
    /// headers only when one changed.
    private func pollForeground() {
        // On screen only (self-test windows are drawn off screen, so they skip the occlusion check).
        guard !polling, let w = view.window, w.isVisible, w.occlusionState.contains(.visible) || SelfTest.isActive,
              !view.isHiddenOrHasHiddenAncestor else { return }
        let visible = scroll.contentView.bounds
        let shown = zoomed.flatMap { z in tree.leaf(z).map { [$0] } } ?? tree.leaves
        var targets: [(id: String, pane: String, agentShown: Bool)] = []
        for leaf in shown {
            guard let sid = leaf.session, let item = model.item(sid), let agent = item.liveAgent, let pane = item.paneId,
                  !model.poppedOut.contains(agent), (refused[agent] ?? 0) < 2,
                  zoomed != nil || paneViews[leaf.id].map({ $0.frame.intersects(visible) }) == true else { continue }
            targets.append((sid, pane, item.session.agent.isAgent || item.agentInTerminal))
        }
        let ids = Set(targets.map(\.id))
        if targets.isEmpty {
            if !running.isEmpty { running = [:]; update() }
            return
        }
        polling = true
        let runtime = model.runtime
        DispatchQueue.global(qos: .utility).async { [weak self] in
            var found: [String: String] = [:]
            for t in targets {
                guard let p = try? runtime.processes(pane: t.pane) else { continue }
                if let cmd = ForegroundProgram.label(p, agentShown: t.agentShown) { found[t.id] = cmd }
            }
            DispatchQueue.main.async {
                guard let self else { return }
                self.polling = false
                // Panes not polled this time (scrolled away, closed) drop their marker.
                let next = found.filter { ids.contains($0.key) }
                if next != self.running { self.running = next; self.update() }
            }
        }
    }

    /// Stop: Ctrl-C to the pane, as if typed (the program decides; a server normally quits), then look again soon.
    private func stopForeground(_ item: BoardItem) {
        guard let pane = item.paneId else { return }
        let runtime = model.runtime
        DispatchQueue.global().async { try? runtime.keys(pane: pane, [.ctrlC]) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in self?.pollForeground() }
    }

    // MARK: Wrap for reading (LAB-657)

    /// Panes showing their terminal's text re-wrapped at word boundaries instead of the live surface.
    private var reading = Set<String>()
    private var readingTimer: Timer?

    func toggleReading(_ pane: String) {
        if reading.contains(pane) { reading.remove(pane) } else { reading.insert(pane) }
        update()
        if !reading.contains(pane) { focusTerminal() }
    }

    /// While a pane reads, its text follows the terminal once a second.
    private func syncReadingTimer() {
        if reading.isEmpty { readingTimer?.invalidate(); readingTimer = nil; return }
        guard readingTimer == nil else { return }
        readingTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.refreshReading() }
    }

    private func refreshReading() {
        let theme = model.themes.terminal
        for id in reading {
            guard let pv = paneViews[id], let sid = tree.leaf(id)?.session, let agent = model.item(sid)?.liveAgent,
                  let s = surfaces[agent] else { continue }
            pv.setReading(ReadingText.prepare(s.allText() ?? ""), theme: theme)
        }
    }

    // MARK: New terminal (LAB-745)

    /// A plain shell in `dir` (or ~/Projects), shown in the focused pane once it starts.
    func newTerminal(in dir: String?) {
        let d = dir.flatMap { Workspace.isInsideProjects($0) ? $0 : nil }
        model.newTerminal(in: d)
    }

    /// A new pane beside (or below) the focused one with a new plain shell in it.
    func splitWithNewTerminal(sideBySide: Bool, in dir: String?) {
        split(sideBySide: sideBySide)
        newTerminal(in: dir)
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
    /// Self-test probe: what the terminal area shows and holds.
    func debugState() -> String {
        "shown=\(shownAgent ?? "-") surfaces=\(surfaces.keys.sorted()) panes=\(tree.leaves.map { $0.session ?? "-" }) " +
        "sel=\(win.selectedId ?? "-") live=\(model.items.compactMap(\.liveAgent)) popped=\(model.poppedOut.sorted()) " +
        "hasSurface=\(surfaces.values.map { $0.surface != nil })"
    }

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
            // Over the scroll view, not in it: it stays put while a scrolled Grid moves (LAB-1239).
            view.addSubview(h, positioned: .above, relativeTo: nil)
            NSLayoutConstraint.activate([
                h.topAnchor.constraint(equalTo: scroll.topAnchor, constant: 8),
                h.trailingAnchor.constraint(equalTo: scroll.trailingAnchor, constant: -16),
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

/// Holds the pane area (LAB-1239): reports each tile so the controller sizes the area to the viewport (or the Grid's
/// taller rows). A wheel over a terminal scrolls that terminal; over a tile's header, Right now line or the scroller it
/// scrolls the Grid.
final class PaneScrollView: NSScrollView {
    var onTile: (() -> Void)?
    override func tile() { super.tile(); onTile?() }
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
    /// Whether a point (in this view's coordinates) is in the bottom bar (the v2 composer).
    func bottomContains(_ p: NSPoint) -> Bool { bottom.map { !$0.isHidden && $0.frame.contains(p) } ?? false }
    private var overlay: NSHostingView<AnyView>?
    /// LAB-825: a pill floating at the bottom centre of the terminal (Back to current).
    private var float: NSHostingView<AnyView>?
    private var placeholder: NSHostingView<AnyView>?
    private var readingView: ReadingView?
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
    var topHeights: (frame: CGFloat, needs: CGFloat)? {
        guard let top, !top.isHidden else { return nil }
        return (top.frame.height, Self.height(of: top, width: top.frame.width))
    }

    /// The view's fitting height when it is `width` wide.
    static func height(of v: NSView, width: CGFloat) -> CGFloat {
        let c = v.widthAnchor.constraint(equalToConstant: max(width, 1))
        c.isActive = true
        defer { c.isActive = false }
        return ceil(v.fittingSize.height)
    }
    func setBottom(_ view: AnyView?) { bottom = host(bottom, view); needsLayout = true }
    func setOverlay(_ view: AnyView?) {
        overlay = host(overlay, view)
        if let overlay { addSubview(overlay, positioned: .above, relativeTo: nil) }
        needsLayout = true
    }

    func setFloat(_ view: AnyView?) {
        float = host(float, view)
        if let float, float.superview != nil, subviews.last !== float { addSubview(float, positioned: .above, relativeTo: nil) }
        needsLayout = true
    }

    /// The size a terminal shown in this pane gets (LAB-606): the laid-out content area, or a best guess before then.
    func surfaceSize(fallback: NSSize) -> NSSize {
        if content.frame.width > 1, content.frame.height > 1 { return content.frame.size }
        let base = bounds.width > 1 && bounds.height > 1 ? bounds.size : fallback
        return NSSize(width: base.width, height: max(1, base.height - 36))   // under the 36 pt pane header
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

    /// Wrap for reading (LAB-657): the terminal's text over the surface, or nil for the live terminal.
    func setReading(_ text: String?, theme: ThemeName) {
        guard let text else { readingView?.isHidden = true; return }
        let r = readingView ?? ReadingView()
        if readingView == nil {
            if let overlay { addSubview(r, positioned: .below, relativeTo: overlay) } else { addSubview(r) }
            readingView = r
            needsLayout = true
        }
        r.isHidden = false
        r.show(text, theme: theme)
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
            // LAB-521: the height the strip needs at this pane's width. `fittingSize` alone measures at the content's
            // ideal (widest) width; narrower, lines truncate or wrap differently, the box came out shorter than the
            // content and SwiftUI centred it, cutting the top off the pane header.
            let h = Self.height(of: top, width: w)
            top.frame = NSRect(x: inset, y: y, width: w, height: h)
            y += h
        }
        var bottomH: CGFloat = 0
        if let bottom, !bottom.isHidden {
            bottomH = Self.height(of: bottom, width: w)
            bottom.frame = NSRect(x: inset, y: bounds.height - inset - bottomH, width: w, height: bottomH)
        }
        content.frame = NSRect(x: inset, y: y, width: w, height: max(0, bounds.height - y - bottomH - inset))
        for v in content.subviews { v.frame = content.bounds }
        readingView?.frame = content.frame
        if let overlay, !overlay.isHidden {
            // LAB-716: measured at the pane's width, so a question that wraps gets the rows it needs.
            let h = min(Self.height(of: overlay, width: w), content.frame.height)
            overlay.frame = NSRect(x: inset, y: content.frame.maxY - h, width: w, height: h)
        }
        if let float, !float.isHidden {
            // Bottom centre of the terminal, above the approval card when one shows.
            let s = float.fittingSize
            let base = overlay.map { $0.isHidden ? content.frame.maxY : $0.frame.minY } ?? content.frame.maxY
            float.frame = NSRect(x: inset + max(0, (w - s.width) / 2), y: max(content.frame.minY, base - s.height), width: min(s.width, w), height: s.height)
        }
    }
}

/// Wrap for reading (LAB-657): a read-only, selectable text view of the terminal's text, wrapped at word boundaries to
/// the pane's width, in the terminal theme. It stays at the bottom while new output arrives, unless scrolled up.
final class ReadingView: NSScrollView {
    private let text = NSTextView()
    private var shown = ""

    init() {
        super.init(frame: .zero)
        hasVerticalScroller = true
        autohidesScrollers = true
        drawsBackground = true
        text.isEditable = false
        text.isSelectable = true
        text.isRichText = false
        text.textContainerInset = NSSize(width: 14, height: 10)
        text.textContainer?.widthTracksTextView = true
        text.isVerticallyResizable = true
        text.isHorizontallyResizable = false
        text.minSize = .zero
        text.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        text.autoresizingMask = [.width]
        text.font = .monospacedSystemFont(ofSize: 12.5, weight: .regular)
        text.setAccessibilityLabel("Terminal text, wrapped for reading")
        documentView = text
    }
    required init?(coder: NSCoder) { fatalError("not supported") }

    func show(_ s: String, theme: ThemeName) {
        let t = theme.tokens
        backgroundColor = t.terminal.background.nsColor
        text.backgroundColor = t.terminal.background.nsColor
        text.textColor = t.text.nsColor
        guard s != shown else { return }
        let atBottom = shown.isEmpty || contentView.bounds.maxY >= text.frame.height - 24
        shown = s
        text.string = s
        if atBottom { text.scrollToEndOfDocument(nil) }
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

/// A session another window is showing (roofd lets one terminal show it at a time).
private struct ShownElsewherePlaceholder: View {
    @Environment(\.theme) private var t
    let onShowHere: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Spacer()
            Text("Showing in another window").ui(18, .semibold).foregroundStyle(t.text.color)
            Text("A session shows in one window at a time.").ui(13).foregroundStyle(t.text2.color)
            RoofButton("Show here", .primary, action: onShowHere)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

extension Notification.Name {
    /// A window is about to show a session's terminal (object: agent id, userInfo: win, force).
    static let releaseSurface = Notification.Name("oneroof.releaseSurface")
}

