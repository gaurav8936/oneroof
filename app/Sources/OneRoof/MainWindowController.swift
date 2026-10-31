import AppKit
import SwiftUI
import Combine
import OneRoofCore

/// A main window: one workspace. Toolbar (50 pt, Sessions theme) over four panels — Sessions · Files · Centre ·
/// Plan — each with its own theme. The centre shows the terminal area or one centre view (`WindowState.centre`).
final class MainWindowController: NSWindowController, NSWindowDelegate, ObservableObject {
    let model: AppModel
    let win: WindowState
    let terminalArea: TerminalAreaController
    private(set) var centre: CentreController!
    private var split: NSSplitViewController!
    private var planItem: NSSplitViewItem!
    private var filesItem: NSSplitViewItem!
    private var centreItem: NSSplitViewItem!
    private var sideItem: NSSplitViewItem!
    private var backdrop: ToolbarBackdrop!
    private var toolbarDelegate: ToolbarDelegate!
    private var sheet: NSWindow?
    private var bag = Set<AnyCancellable>()
    /// Sessions panel was open before a fleet view folded it.
    private var sessionsBeforeFold: Bool?
    /// Plan panel was open before the Editor (its inspector) took its place.
    private var planBeforeEditor: Bool?

    // One Roof 1.x v2 window (LAB-ONEROOF-UI-REDESIGN M1): set once at init from the ui2 setting.
    private(set) var isV2 = false
    var v2RailItem: NSSplitViewItem?
    var v2Dock: NSView?
    var v2DockHeight: NSLayoutConstraint?
    var v2PlanOverlay: NSView?
    var v2EdgeTracker: V2EdgeTracker?
    var v2RightTracker: V2EdgeTracker?
    /// The Plan was opened by the 0.5-style Editor rule (the file tree beside it), to fold back afterwards.
    var v2FilesOpenedByEditor = false
    var v2EdgeOverlay: NSView?
    var v2V2Toolbar: V2ToolbarDelegate?
    var v2Bag = Set<AnyCancellable>()
    var v2EscMonitor: Any?
    /// ⌃⌘J at the current step: nil = the step's own dock (full at 0, a line at 1, none at 2 and 3).
    var v2DockOverride: Bool?
    /// The step before Focus, for Esc / leaving Focus.
    var v2BeforeFocus: FocusStep = .sessions
    /// A page over the current place (Settings, Help …, M5); the rail then highlights no place (LAB-1084).
    @Published var v2Page: String?
    /// Which Settings pane the v2 Settings page shows (B1.x).
    @Published var v2SettingsPane = 0
    var v2PageHost: NSView?
    var v2OnPage: Bool { v2Page != nil }
    /// The dock is folded into the session column's line (step 1) rather than shown full.
    @Published var v2DockFolded = true
    /// Plan inspector mode in its column: the 270 pt inspector (step 0) or the 28 pt edge tab (steps 1-2).
    @Published var v2PlanEdge = false
    /// What the toolbar right of the column has room for (LAB-1237), from the window and column widths.
    @Published var v2Bar = V2Layout.toolbarFit(room: 1400)
    /// LAB-1783 · how far the title draws from its toolbar item so its text lines up with the centre's content. Its
    /// own object, observed by the title alone: it changes on every frame of a column drag, and as a @Published of
    /// the controller it redrew every view that observes the controller (LAB-1736 pattern).
    let v2TitleShift = V2TitleShift()
    /// The last Plan-fits answer at Full, so a window resize re-lays the columns out only when it crosses it (LAB-831).
    var v2PlanFitsLast: Bool?
    /// LAB-1337: the layout v2ApplyLayout last put in place (target + the split's state after it).
    var v2LastLayout: String?
    /// LAB-1601: the Focus lane's edge is being dragged by the mouse (set by a drag event, cleared when it snaps).
    var v2LaneDragged = false
    /// LAB-1612: the rail is showing only because the Sessions column was dragged closed at a step that hides it.
    var v2RailShownForFold = false

    /// LAB-1612 · a Sessions column dragged closed leaves the rail on screen, so there is always an edge to drag it back
    /// from (and the Sessions button): at the Sessions step the rail is hidden, and folding the column left nothing at
    /// the window's left edge. Once the column is back, the step's own layout returns.
    func v2RailForFoldedColumn() {
        guard isV2, let rail = v2RailItem, win.place == .sessions, v2Page == nil else { return }
        let folded = sideItem.isCollapsed
        if folded, rail.isCollapsed, win.focusStep != .focus {
            v2RailShownForFold = true
            DispatchQueue.main.async { rail.isCollapsed = false }
        } else if !folded, v2RailShownForFold {
            v2RailShownForFold = false
            DispatchQueue.main.async { [weak self] in self?.v2LastLayout = nil; self?.v2ApplyLayout(animated: false) }
        }
    }
    var splitView: NSSplitView { split.splitView }
    var splitController: NSSplitViewController { split }
    var centreItemRef: NSSplitViewItem { centreItem }
    var sideItemRef: NSSplitViewItem { sideItem }
    var planItemRef: NSSplitViewItem { planItem }
    var filesItemRef: NSSplitViewItem { filesItem }
    var backdropRef: ToolbarBackdrop { backdrop }

    /// Every open main window, in Window-menu order.
    static var all: [MainWindowController] = []
    static func forWorkspace(_ id: String) -> MainWindowController? { all.first { $0.win.id == id } }

    init(model: AppModel, win: WindowState) {
        self.model = model
        self.win = win
        self.terminalArea = TerminalAreaController(model: model, win: win)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1440, height: 900),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered, defer: false)
        window.title = win.name
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.titlebarSeparatorStyle = .none
        // LAB-831: the v2 window goes down to about a third of the screen (its Plan and column fold first); the classic
        // window keeps the width its four panels need.
        window.minSize = NSSize(width: model.settings.ui2 ? CGFloat(V2Layout.minWindowWidth) : PanelMinimums.windowWidth, height: 560)
        window.isReleasedWhenClosed = false
        let autosave = win.id == WorkspaceStore.mainId ? "OneRoofMain" : "OneRoofMain." + win.id
        super.init(window: window)
        // LAB-1281: the frame is remembered through the controller. Set on the window before `super.init(window:)`
        // (1.9.2 and before), NSWindowController replaced it with its own empty name, so no main window's frame was
        // ever saved: every launch opened each window at the first-launch default (1700 × 1000, cascaded), and a
        // window tiled to half the screen fell back to that size when macOS untiled it. Cascading stays ours (below).
        shouldCascadeWindows = false
        window.delegate = self
        Self.all.append(self)

        isV2 = model.settings.ui2
        terminalArea.showsSubagentColumn = !isV2   // LAB-1240: v2 has the Subagents tab, never a column beside the terminal
        // Toolbar: a unified NSToolbar gives the 50 pt title bar with the traffic lights centred; its items are SwiftUI.
        // The v2 window builds its own toolbar once the split view exists (its sections track the column dividers).
        if !isV2 {
            toolbarDelegate = ToolbarDelegate(model: model, win: win, controller: self)
            let tb = NSToolbar(identifier: "OneRoofToolbar." + win.id)
            tb.delegate = toolbarDelegate
            tb.displayMode = .iconOnly
            tb.allowsUserCustomization = false
            tb.showsBaselineSeparator = false
            window.toolbar = tb
            window.toolbarStyle = .unified
        }

        let sidebar = isV2 ? NSHostingController(rootView: AnyView(V2SessionColumn(model: model, win: win, controller: self)))
                           : NSHostingController(rootView: AnyView(SessionsPanel(model: model, win: win, controller: self)))
        let plan = isV2 ? NSHostingController(rootView: AnyView(V2PlanSlot(model: model, win: win, controller: self)))
                        : NSHostingController(rootView: AnyView(PlanPanelView(model: model, win: win)))
        let files = NSHostingController(rootView: FileBrowserView(model: model, win: win))
        // SwiftUI panels must not report a preferred/maximum size, or AppKit shrinks the window when a panel closes.
        sidebar.sizingOptions = []; plan.sizingOptions = []; files.sizingOptions = []
        centre = CentreController(model: model, win: win, terminalArea: terminalArea, v2: isV2)

        split = RoofSplitViewController()
        split.splitView.isVertical = true
        split.splitView.dividerStyle = .thin
        // LAB-596: the minimum widths of all four panels fit the window's minimum width (PanelMinimums), so opening a
        // panel never makes AppKit grow the window; a panel opening or closing resizes its neighbours, never the window.
        sideItem = NSSplitViewItem(viewController: sidebar)
        sideItem.minimumThickness = PanelMinimums.sessions; sideItem.canCollapse = true
        sideItem.holdingPriority = .init(260)
        filesItem = NSSplitViewItem(viewController: files)
        filesItem.minimumThickness = PanelMinimums.files; filesItem.canCollapse = true
        filesItem.holdingPriority = .init(255)
        filesItem.isCollapsed = true
        centreItem = NSSplitViewItem(viewController: centre)
        centreItem.minimumThickness = PanelMinimums.centre
        centreItem.canCollapse = true
        centreItem.holdingPriority = .init(250)
        planItem = NSSplitViewItem(viewController: plan)
        planItem.minimumThickness = PanelMinimums.plan; planItem.canCollapse = true
        planItem.holdingPriority = .init(251)
        // LAB-1556: in the v2 window no drag can open the classic Files item (it has no width). LAB-1576: a drag left
        // still folds the Sessions column away, as before; the Sessions rail button and ⌥⌘S bring it back.
        if isV2 {
            // The v2 file tree is the Files tab: the classic item has no width to give, so no drag can open it.
            filesItem.minimumThickness = 0; filesItem.maximumThickness = 0
        }
        if isV2, let roof = split as? RoofSplitViewController {
            roof.keepOnDrag = { [weak self] v in
                guard let self else { return false }
                // The split view hands over the wrapper AppKit puts around each item's view.
                return self.filesItem.viewController.view.isDescendant(of: v)
            }
            // LAB-1576: a drag that folds the Sessions column hands its place to the classic Files item, which has no
            // width in v2; fold it straight back so nothing reads it as open.
            roof.afterResize = { [weak self] in
                guard let self else { return }
                if !self.filesItem.isCollapsed {
                    DispatchQueue.main.async { if !self.filesItem.isCollapsed { self.filesItem.isCollapsed = true } }
                }
                self.v2RailForFoldedColumn()
            }
        }
        for i in [sideItem, filesItem, centreItem, planItem] {
            i!.collapseBehavior = .preferResizingSiblingsWithFixedSplitView
            split.addSplitViewItem(i!)
        }
        // The v2 window keeps its own layout save: its split view has a rail item 0.5's does not (audit D1).
        if !SelfTest.isActive {
            let base = isV2 ? "OneRoofSplitV2" : "OneRoofSplit"
            split.splitView.autosaveName = win.id == WorkspaceStore.mainId ? base : base + "." + win.id
        }
        if isV2 { v2InstallRailAndToolbar() }

        // Content: the themed toolbar backdrop (behind the transparent title bar) and the panels below it.
        let root = NSView()
        backdrop = ToolbarBackdrop()
        backdrop.translatesAutoresizingMaskIntoConstraints = false
        split.view.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(backdrop)
        root.addSubview(split.view)
        let container = NSViewController()
        container.view = root
        container.addChild(split)
        window.contentViewController = container
        let top = (window.contentLayoutGuide as? NSLayoutGuide)?.topAnchor ?? root.topAnchor
        NSLayoutConstraint.activate([
            backdrop.topAnchor.constraint(equalTo: root.topAnchor),
            backdrop.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            backdrop.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            backdrop.bottomAnchor.constraint(equalTo: top),
            split.view.topAnchor.constraint(equalTo: top),
            split.view.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            split.view.trailingAnchor.constraint(equalTo: root.trailingAnchor),
        ])
        if isV2 { v2InstallDock(in: root, under: split.view, top: top) }
        else { split.view.bottomAnchor.constraint(equalTo: root.bottomAnchor).isActive = true }

        // A fresh profile is a new Mac: no saved frame (and a test never reads the real domain's).
        if Prefs.freshProfile || !window.setFrameUsingName(autosave), let screen = NSScreen.main {
            // First launch: 85% of the screen, at most 1700 × 1000, centred; later windows cascade.
            let v = screen.visibleFrame
            let size = NSSize(width: min(v.width * 0.85, 1700), height: min(v.height * 0.85, 1000))
            let shift = CGFloat(Self.all.count - 1) * 28
            window.setFrame(NSRect(x: v.midX - size.width / 2 + shift, y: v.midY - size.height / 2 - shift, width: size.width, height: size.height), display: false)
        }
        // LAB-1758: the frame is saved only from here on. Named before the content was set (1.9.27 and before), the
        // window's squeeze to its content's smallest size (600 × 584, then 870 wide) was saved over your frame at once,
        // and the line above read that back: every launch and install opened a small box in the screen's corner.
        // Tests and fresh profiles never read or write the owner's saved layout.
        if !SelfTest.isActive && !Prefs.freshProfile { windowFrameAutosaveName = autosave }
        ownerFrame = window.frame
        // Default widths (WINDOW_SHELL §3) when there is no saved layout: Sessions 300 · Plan 330.
        let saved = !SelfTest.isActive && !Prefs.freshProfile && UserDefaults.standard.object(forKey: "NSSplitView Subview Frames " + (split.splitView.autosaveName ?? "")) != nil
        if !saved && !isV2 {
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                let w = self.split.splitView.bounds.width
                self.split.splitView.setPosition(300, ofDividerAt: 0)
                self.split.splitView.setPosition(w - 330, ofDividerAt: 2)
            }
        }

        model.$themes.receive(on: DispatchQueue.main).sink { [weak self] t in self?.applyThemes(t) }.store(in: &bag)
        win.$centre.removeDuplicates().receive(on: DispatchQueue.main).sink { [weak self] c in self?.centreChanged(c) }.store(in: &bag)
        win.$name.receive(on: DispatchQueue.main).sink { [weak window] n in window?.title = n }.store(in: &bag)
        // LAB-590: the window's colour tints its toolbar band.
        win.$colour.removeDuplicates().receive(on: DispatchQueue.main).sink { [weak self] _ in
            guard let self else { return }
            self.applyThemes(self.model.themes)
        }.store(in: &bag)
        syncPanels()
        watchToolbarClicks()
        if isV2 { v2Start() }
    }

    required init?(coder: NSCoder) { fatalError("not supported") }

    deinit {
        if let toolbarClickMonitor { NSEvent.removeMonitor(toolbarClickMonitor) }
        if let v2EscMonitor { NSEvent.removeMonitor(v2EscMonitor) }
    }

    /// LAB-596 / LAB-653: two quick clicks on toolbar controls (tabs, window name, panel toggles) reach the title bar
    /// as a double-click where SwiftUI does not take them, and macOS zooms or "fills" the window. They become single
    /// clicks; a double-click on empty toolbar space still does what System Settings says.
    private var toolbarClickMonitor: Any?
    private func watchToolbarClicks() {
        toolbarClickMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .leftMouseUp]) { [weak self] e in
            guard let self, let window = self.window, e.window === window, e.clickCount >= 2,
                  let items = window.toolbar?.items else { return e }
            let controls = items.compactMap { i -> CGRect? in
                guard let v = i.view, v.window === window, !v.isHidden else { return nil }
                return v.convert(v.bounds, to: nil)
            }
            guard WindowZoom.toolbarClickCount(e.clickCount, at: e.locationInWindow, controls: controls) != e.clickCount else { return e }
            return NSEvent.mouseEvent(with: e.type, location: e.locationInWindow, modifierFlags: e.modifierFlags,
                                      timestamp: e.timestamp, windowNumber: e.windowNumber, context: nil,
                                      eventNumber: e.eventNumber, clickCount: 1, pressure: e.pressure) ?? e
        }
    }

    // MARK: Window

    func windowDidBecomeKey(_ notification: Notification) {
        if model.activeWindowId != win.id { model.activeWindowId = win.id }
        // LAB-1255: Linear's project list is refreshed when a window comes to the front (when it was ever loaded, so a
        // Mac without a Linear key never gets an error from this; at most once per 30 s).
        if !model.workstreams.isEmpty, !SelfTest.isActive { model.loadWorkstreams() }
    }

    /// LAB-520: a double-click on empty toolbar space is a title-bar double-click, and macOS zooms the window. A window
    /// already stretched to fill the screen then "zooms" back to its last smaller size, so a stray double-click between the
    /// toolbar tabs shrank the window. LAB-653: the same for a window tiled to half the screen. Such a double-click never
    /// makes the window smaller; Window › Zoom and the green button still toggle.
    func windowShouldZoom(_ window: NSWindow, toFrame newFrame: NSRect) -> Bool {
        WindowZoom.allow(current: window.frame, to: newFrame, visible: window.screen?.visibleFrame,
                         fromTitleBarDoubleClick: Self.isTitleBarDoubleClick(NSApp.currentEvent, in: window))
    }

    static func isTitleBarDoubleClick(_ e: NSEvent?, in window: NSWindow) -> Bool {
        guard let e, e.window === window, [.leftMouseDown, .leftMouseUp].contains(e.type), e.clickCount >= 2 else { return false }
        return true
    }

    // MARK: LAB-1758 · the window keeps the frame you gave it

    /// The frame you last gave the window (a resize, a move, a tile, the green button, Window › Zoom) or it opened at.
    private var ownerFrame: NSRect?

    func windowDidResize(_ notification: Notification) { frameChanged() }
    func windowDidMove(_ notification: Notification) { frameChanged() }
    func windowDidEndLiveResize(_ notification: Notification) { ownerFrame = window?.frame }
    func windowDidExitFullScreen(_ notification: Notification) { ownerFrame = window?.frame }

    /// A frame change while a click on one of our controls is handled was not yours: logged with what caused it, and
    /// undone when it made the window smaller (WindowZoom.undoUnasked). Anything else becomes the frame to keep.
    private func frameChanged() {
        guard let w = window, !w.inLiveResize, !w.styleMask.contains(.fullScreen) else { return }
        let now = w.frame
        guard let owner = ownerFrame, owner != now else { return }   // nil while the window is being built
        let event = NSApp.currentEvent
        let click = Self.isControlClick(event, in: w)
        let undo = WindowZoom.undoUnasked(owner: owner, now: now, visible: w.screen?.visibleFrame, duringControlClick: click)
        if now.size != owner.size { WindowFrameLog.write(window: win.name, from: owner, to: now, event: event, undone: undo) }
        guard undo else { ownerFrame = now; return }
        DispatchQueue.main.async { [weak w] in
            guard let w, w.frame != owner, !w.inLiveResize else { return }
            w.setFrame(owner, display: true)
        }
    }

    /// A mouse click inside the window's content (the rail, a column, a page) or on a toolbar item, being handled now:
    /// never a drag of the title bar (the toolbar's empty space), a menu or a key. `currentEvent` stays the last event
    /// until the next one, so a click more than a second old is not the cause (a self-test's resizes after a drag).
    static func isControlClick(_ e: NSEvent?, in window: NSWindow) -> Bool {
        guard let e, e.window === window, ProcessInfo.processInfo.systemUptime - e.timestamp < 1,
              [.leftMouseDown, .leftMouseUp, .rightMouseDown, .rightMouseUp, .otherMouseDown, .otherMouseUp].contains(e.type) else { return false }
        if e.locationInWindow.y < window.contentLayoutRect.maxY { return true }
        return (window.toolbar?.items ?? []).contains { i in
            guard let v = i.view, v.window === window, !v.isHiddenOrHasHiddenAncestor, v.frame.width > 2 else { return false }
            return v.convert(v.bounds, to: nil).contains(e.locationInWindow)
        }
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        // LAB-1485: say what is in this window (how many keep running, which agents are working, which are finished
        // shells, how many are saved rows), instead of one sentence for every window.
        let rows = model.items(in: win).map {
            WindowCloseText.Row(name: $0.session.name,
                                kind: WindowCloseText.kind(liveAgent: $0.liveAgent != nil, endedShell: $0.endedShell != nil, status: $0.status))
        }
        return WindowCloseGuard.shared.shouldClose(sender, what: "the window \u{201C}\(win.name)\u{201D}", detail: WindowCloseText.detail(rows))
    }

    /// Set when the app quits: AppKit then closes every window, and those closes are not the owner closing them.
    static var quitting = false

    func windowWillClose(_ notification: Notification) {
        if let m = v2EscMonitor { NSEvent.removeMonitor(m); v2EscMonitor = nil }
        Self.all.removeAll { $0 === self }
        // Closing a workspace window keeps its sessions (they wait in the store, roofd keeps the agents);
        // reopen it from Window ▸. Quitting is not closing (LAB-706): every window comes back at the next launch.
        if var r = WorkspaceStore.shared.workspaces.first(where: { $0.id == win.id }), !SelfTest.isActive,
           WindowMembership.remembersClosed(quitting: Self.quitting, otherOpenWindows: Self.all.count) {
            r.open = false
            WorkspaceStore.shared.update(r)
        }
        if Self.all.isEmpty || Self.quitting { return }
        model.forget(win)
    }

    /// Which window this is ("window 2 of 6").
    var position: (Int, Int) {
        ((Self.all.firstIndex { $0 === self } ?? 0) + 1, Self.all.count)
    }

    private func applyThemes(_ t: PanelThemes) {
        if isV2 { v2ApplyThemes(t) }
        let k = t.sidebar.tokens
        // LAB-590: a window with a colour gets a tinted band and a 2 pt stripe in the colour's ink; without one, as before.
        let accent = WindowAccent(named: win.colour, on: k)
        backdrop.fill = accent?.band ?? k.toolbar
        backdrop.line = accent?.ink ?? k.separator
        backdrop.lineWidth = accent == nil ? 1 : 2
        // v2: the band follows the columns, so the window's colour keeps only its 2 pt stripe (1.8.1: a coloured window
        // was no longer told apart at a glance; the switcher dot alone was the only trace of it).
        if isV2 { backdrop.lineWidth = accent == nil ? 0 : 2 }
        window?.appearance = t.sidebar.appearance
        sideItem.viewController.view.appearance = t.sidebar.appearance
        filesItem.viewController.view.appearance = t.files.appearance
        planItem.viewController.view.appearance = t.plan.appearance
    }

    // MARK: Panels

    /// Which panels are open (for the toolbar toggles).
    @Published var panels = PanelState()

    func syncPanels() {
        // LAB-1306: the v2 window never shows the classic Files side panel; whatever opened it, it closes again here.
        if isV2, !filesItem.isCollapsed { filesItem.isCollapsed = true }
        let now = PanelState(sidebar: !sideItem.isCollapsed, files: !filesItem.isCollapsed,
                             centre: !centreItem.isCollapsed, plan: !planItem.isCollapsed)
        if now != panels { panels = now }   // LAB-1337: published; set on every place change, twice
        // v2: the 28 pt edge tab is not an open Plan (audit D3). The v2 window shows no Subagents column (LAB-1240).
        terminalArea.planPanelOpen = panels.plan && !(isV2 && v2PlanEdge)
    }

    /// Close or open the centre panel. With it closed, the plan panel takes the freed width (v0.1 rule).
    func toggleCentre() {
        // v2: every other column has a capped width, so collapsing the centre would resize the window (LAB-596 rule);
        // ⌥⌘C brings the terminal (Terminal tab) forward instead.
        if isV2 { model.show(.workspace, in: win); terminalArea.focusTerminal(); return }
        let closing = !centreItem.isCollapsed
        if closing && sideItem.isCollapsed && planItem.isCollapsed && filesItem.isCollapsed { shake(); return }   // keep one panel
        planItem.holdingPriority = .init(closing ? 240 : 251)
        sideItem.holdingPriority = .init(closing ? 245 : 260)
        centreItem.animator().isCollapsed = closing
        syncLater()
    }

    func togglePlanPanel() {
        if isV2 { v2TogglePlan(); return }
        guard guardLast(planItem) else { return }; planItem.animator().isCollapsed.toggle(); syncLater()
    }
    func toggleFiles() {
        // v2: the file tree lives in the Files tab (A2.1): ⌥⌘B opens it, or goes back to the terminal from it.
        // LAB-1306: the classic Files side panel can still come back in the v2 window (a restored split layout); its ×
        // sends this same action, which opened the Files tab (a second tree) instead of closing it. Close it first.
        if isV2, !filesItem.isCollapsed { filesItem.isCollapsed = true; syncLater(); return }
        if isV2 {
            if win.centre == .editor { model.show(.workspace, in: win) }
            else if let p = win.viewerPath, EditorState.of(win.id).tabs.contains(p) { win.show(path: p) }
            else if let last = EditorState.of(win.id).tabs.last { win.show(path: last) }
            else { win.viewerPath = nil; model.show(.editor, in: win) }
            return
        }
        guard guardLast(filesItem) else { return }; filesItem.animator().isCollapsed.toggle(); syncLater() }
    func toggleSidebar() {
        if isV2 { v2ToggleColumn(); return }
        guard guardLast(sideItem) else { return }; sideItem.animator().isCollapsed.toggle(); syncLater()
    }
    /// The Sessions rail's widen button (LAB-714): back to the panel's usual width.
    func widenSessions() {
        if sideItem.isCollapsed { sideItem.animator().isCollapsed = false }
        split.splitView.setPosition(300, ofDividerAt: 0)
        syncLater()
    }
    private func syncLater() { DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { self.syncPanels() } }

    /// Never close the last open panel (S00.T.4: the button shakes, no beep).
    private func guardLast(_ item: NSSplitViewItem) -> Bool {
        let all: [NSSplitViewItem] = [sideItem, filesItem, centreItem, planItem]
        let others = all.filter { $0 !== item && !$0.isCollapsed }
        if !item.isCollapsed && others.isEmpty { shake(); return false }
        return true
    }

    @Published var shakeToggle = 0
    private func shake() { shakeToggle += 1 }

    /// Focus: hide both side panels (terminal only); if both are already hidden, show them again.
    func toggleFocus() {
        if isV2 { v2StepOn(); return }
        let hidden = sideItem.isCollapsed && planItem.isCollapsed
        sideItem.animator().isCollapsed = !hidden
        planItem.animator().isCollapsed = !hidden
        if !hidden { filesItem.animator().isCollapsed = true }
        centreItem.animator().isCollapsed = false
        syncLater()
    }

    /// Fleet views fold the Sessions panel away; Workspace brings it back as it was (S00.T.1).
    private func centreChanged(_ c: CentreView) {
        if isV2 {
            if centreItem.isCollapsed { centreItem.animator().isCollapsed = false }
            v2CentreChanged(c)
            centre.show(c); syncLater(); return
        }
        if c.foldsSessions {
            if sessionsBeforeFold == nil { sessionsBeforeFold = !sideItem.isCollapsed }
            sideItem.animator().isCollapsed = true
        } else if let was = sessionsBeforeFold {
            sideItem.animator().isCollapsed = !was
            sessionsBeforeFold = nil
        }
        if centreItem.isCollapsed { centreItem.animator().isCollapsed = false }
        // Editor: Sessions folds to a 56 pt rail (S07 §1.1); leaving restores the panel.
        if c == .editor {
            if planBeforeEditor == nil { planBeforeEditor = !planItem.isCollapsed }
            planItem.animator().isCollapsed = true
            sideItem.minimumThickness = PanelMinimums.sessionsRail
            if !sideItem.isCollapsed { split.splitView.setPosition(PanelMinimums.sessionsRail, ofDividerAt: 0) }
            if filesItem.isCollapsed { filesItem.animator().isCollapsed = false }
        } else if sideItem.minimumThickness != PanelMinimums.sessions {
            if let was = planBeforeEditor { planItem.animator().isCollapsed = !was; planBeforeEditor = nil }
            sideItem.minimumThickness = PanelMinimums.sessions
            if !sideItem.isCollapsed { split.splitView.setPosition(300, ofDividerAt: 0) }
        }
        centre.show(c)
        syncLater()
    }

    // MARK: Sheets

    func newObjective() {
        present(NewObjectiveSheet(model: model, close: { [weak self] in self?.closeSheet() }))
    }

    func newSession() {
        present(NewSessionSheet(model: model, win: win, close: { [weak self] in self?.closeSheet() }))
    }

    func attachIssue(_ item: BoardItem) {
        present(AttachIssueSheet(model: model, item: item, close: { [weak self] in self?.closeSheet() }))
    }

    /// New Workspace Window…; with `moving`, that session moves into the new window (LAB-707).
    func newWorkspace(moving sessionId: String? = nil) {
        present(NewWorkspaceSheet(model: model, moving: sessionId, close: { [weak self] in self?.closeSheet() }))
    }

    private func present<V: View>(_ v: V) {
        guard window?.attachedSheet == nil, let window else { return }
        let host = NSHostingController(rootView: v.themed(model.themes.centre, scale: win.textScale))
        let w = NSWindow(contentViewController: host)
        w.styleMask = [.titled]
        w.appearance = model.themes.centre.appearance
        sheet = w
        window.beginSheet(w)
    }

    func closeSheet() {
        guard let window else { return }
        if let s = window.attachedSheet { window.endSheet(s) }
        sheet = nil
    }
}

struct PanelState: Equatable {
    var sidebar = true, files = false, centre = true, plan = true
}

/// The 50 pt band behind the transparent title bar, in the Sessions theme's toolbar colour, with a bottom separator.
final class ToolbarBackdrop: NSView {
    /// v2: the band painted per column, each segment (right edge x, colour) from left to right.
    var segments: [(CGFloat, RGB)] = [] { didSet { needsDisplay = true } }
    /// LAB-1337: redraw only when an edge or a colour moved (it is set on every resize frame and place change).
    func setSegments(_ new: [(CGFloat, RGB)]) {
        guard new.count != segments.count || zip(new, segments).contains(where: { $0.0 != $1.0 || $0.1 != $1.1 }) else { return }
        segments = new
    }
    var fill = ThemeName.daylight.tokens.toolbar { didSet { needsDisplay = true } }
    var line = ThemeName.daylight.tokens.separator { didSet { needsDisplay = true } }
    var lineWidth: CGFloat = 1 { didSet { needsDisplay = true } }
    override var isFlipped: Bool { true }
    override func draw(_ dirtyRect: NSRect) {
        fill.nsColor.setFill(); bounds.fill()
        var x: CGFloat = 0
        for (end, colour) in segments where end > x { colour.nsColor.setFill(); NSRect(x: x, y: 0, width: end - x, height: bounds.height).fill(); x = end }
        line.nsColor.setFill(); NSRect(x: 0, y: bounds.height - lineWidth, width: bounds.width, height: lineWidth).fill()
    }
}

/// The centre panel: the terminal area (Workspace) and every centre view, one visible at a time, crossfading 0.18 s.
final class CentreController: NSViewController {
    private let model: AppModel
    private let win: WindowState
    let terminalArea: TerminalAreaController
    private var hosts: [CentreView: NSView] = [:]
    private var current: CentreView = .workspace
    /// v2 window: the terminal area is a card inset 8 pt on the centre's background, corners 12 (handover A1.11).
    private let v2: Bool
    private var cardFrame: NSView?
    private var bag = Set<AnyCancellable>()

    init(model: AppModel, win: WindowState, terminalArea: TerminalAreaController, v2: Bool = false) {
        self.model = model; self.win = win; self.terminalArea = terminalArea; self.v2 = v2
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError("not supported") }

    /// Where the centre views sit, under the file tab strip (LAB-799).
    private let content = NSView()

    override func loadView() {
        let root = NSView()
        root.wantsLayer = true
        // The strip is as tall as it draws: 30 pt while a file is open, nothing otherwise.
        let m = model, w = win
        // v2: the session tabs (Terminal · Files · Changes · Subagents); file tabs live inside Files (A2.0).
        // Only its height counts (NoIdealWidth). Its width (every tab, Split · Raw · Wrap) was a required minimum of the
        // centre: in a narrow window, showing the tabs (a place change, a session) grew the window (LAB-874, LAB-596).
        let strip = v2 ? NSHostingView(rootView: AnyView(NoIdealWidth { CentreThemed(model: m, win: w) { V2SessionTabs(model: m, win: w) } }))
                       : NSHostingView(rootView: AnyView(NoIdealWidth { CentreThemed(model: m, win: w) { CentreTabStrip(model: m, win: w) } }))
        // LAB-1317: the v2 strip is 34 pt or nothing, known from the centre alone; sized by its intrinsic content it was
        // measured (all five ViewThatFits levels) on every model change: 18 % of the idle main thread.
        strip.sizingOptions = v2 ? [] : [.intrinsicContentSize]
        for v in [strip, content] { v.translatesAutoresizingMaskIntoConstraints = false; root.addSubview(v) }
        if v2 {
            let h = strip.heightAnchor.constraint(equalToConstant: 0)
            h.isActive = true
            w.$centre.combineLatest(w.$viewerPath).receive(on: DispatchQueue.main).sink { c, p in
                let on = V2SessionTabs.shows(centre: c, viewerPath: p) ? V2SessionTabs.height : 0
                if h.constant != on { h.constant = on }
            }.store(in: &bag)
        }
        NSLayoutConstraint.activate([
            strip.topAnchor.constraint(equalTo: root.topAnchor),
            strip.leadingAnchor.constraint(equalTo: root.leadingAnchor), strip.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            content.topAnchor.constraint(equalTo: strip.bottomAnchor), content.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            content.leadingAnchor.constraint(equalTo: root.leadingAnchor), content.trailingAnchor.constraint(equalTo: root.trailingAnchor),
        ])
        addChild(terminalArea)
        if v2 {
            // The card: a rounded, clipped frame around the terminal area, 8 pt in from the centre's edges.
            let card = NSView()
            card.wantsLayer = true
            card.layer?.cornerRadius = Radius.card
            card.layer?.cornerCurve = .continuous
            card.layer?.masksToBounds = true
            let bg = NSHostingView(rootView: AnyView(CentreThemed(model: m, win: w) { Color.clear }))
            bg.sizingOptions = []   // a background must never size the centre (a clear view's size would shrink it to nothing)
            pin(bg, in: content)
            card.translatesAutoresizingMaskIntoConstraints = false
            content.addSubview(card)
            NSLayoutConstraint.activate([
                card.topAnchor.constraint(equalTo: content.topAnchor, constant: 6), card.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -8),
                card.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 8), card.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -8),
            ])
            pin(terminalArea.view, in: card)
            let hint = PassThroughHostingView(rootView: AnyView(V2FocusHintSlot(win: w).themed(m.themes.terminal, scale: 1)))
            hint.sizingOptions = [.intrinsicContentSize]
            hint.translatesAutoresizingMaskIntoConstraints = false
            card.addSubview(hint)
            NSLayoutConstraint.activate([hint.centerXAnchor.constraint(equalTo: card.centerXAnchor), hint.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -48)])
            let toast = NSHostingView(rootView: AnyView(V2UndoToastSlot(model: m, windowId: w.id).themed(m.themes.centre, scale: 1)))
            toast.sizingOptions = [.intrinsicContentSize]
            toast.translatesAutoresizingMaskIntoConstraints = false
            card.addSubview(toast)
            NSLayoutConstraint.activate([toast.centerXAnchor.constraint(equalTo: card.centerXAnchor), toast.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -84)])
            cardFrame = card
            hosts[.workspace] = card
        } else {
            pin(terminalArea.view, in: content)
            hosts[.workspace] = terminalArea.view
        }
        view = root
    }

    private func pin(_ v: NSView, in root: NSView) {
        v.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(v)
        NSLayoutConstraint.activate([
            v.topAnchor.constraint(equalTo: root.topAnchor), v.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            v.leadingAnchor.constraint(equalTo: root.leadingAnchor), v.trailingAnchor.constraint(equalTo: root.trailingAnchor),
        ])
    }

    private func host(_ c: CentreView) -> NSView {
        if let h = hosts[c] { return h }
        let m = model, w = win
        let v: AnyView
        switch c {
        case .workspace: return cardFrame ?? terminalArea.view
        case .overview: v = AnyView(CentreThemed(model: m, win: w) { OverviewView(model: m, win: w) })
        case .resources: v = AnyView(CentreThemed(model: m, win: w) { ResourcesView(model: m, win: w) })
        case .board: v = AnyView(CentreThemed(model: m, win: w) { BoardView(model: m, win: w) })
        case .decisions: v = AnyView(CentreThemed(model: m, win: w) { DecisionsView(model: m, win: w) })
        case .subagents: v = v2 ? AnyView(CentreThemed(model: m, win: w) { V2SubagentsHost(model: m, win: w) })
                                : AnyView(CentreThemed(model: m, win: w) { SubagentTraceView(model: m, win: w) })
        case .work: v = AnyView(CentreThemed(model: m, win: w) { WorkView(model: m) })
        case .learn: v = AnyView(CentreThemed(model: m, win: w) { LearnView(model: m) })
        case .objective: v = AnyView(CentreThemed(model: m, win: w) { ObjectiveView(model: m) })
        case .editor: v = v2 ? AnyView(CentreThemed(model: m, win: w) { V2FilesTab(model: m, win: w) })
                             : AnyView(CentreThemed(model: m, win: w) { EditorView(model: m, win: w) })
        case .review: v = AnyView(CentreThemed(model: m, win: w) { ReviewChangesView(model: m, win: w) })
        case .loops: v = AnyView(CentreThemed(model: m, win: w) { LoopsView(model: m, win: w) })
        case .catalog: v = AnyView(CentreThemed(model: m, win: w) { CatalogView(model: m, win: w) })   // LAB-1509
        }
        let h = NSHostingView(rootView: v)
        h.sizingOptions = []
        h.isHidden = true   // attached by show(c) (LAB-1601: off screen, out of the window)
        hosts[c] = h
        return h
    }

    func show(_ c: CentreView) {
        let next = host(c)
        let prev = hosts[current]
        current = c
        guard prev !== next else { unpark(next); next.isHidden = false; return }
        unpark(next)
        next.isHidden = false
        if Motion.reduce || prev == nil {
            if let prev { park(prev) }
        } else {
            next.alphaValue = 0
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = 0.18
                ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
                next.animator().alphaValue = 1
                prev?.animator().alphaValue = 0
            }, completionHandler: { [weak prev, weak self] in
                guard let prev, let self, self.hosts[self.current] !== prev else { return }
                self.park(prev)
                prev.alphaValue = 1
            })
        }
        if c == .workspace { terminalArea.focusTerminal() }
    }

    /// LAB-1601 · a centre page that is not on screen leaves the window. A hidden view still takes part in layout: every
    /// width change (a Focus step, Full/Wide, a window resize) laid out every page opened since launch (the Files tab's
    /// whole tree, the catalog, Learn…), on each animation frame. The terminal area stays: its terminals live on.
    private func park(_ v: NSView) {
        v.isHidden = true
        if v !== hosts[.workspace], v.superview != nil { v.removeFromSuperview() }
    }

    private func unpark(_ v: NSView) {
        if v.superview == nil { pin(v, in: content) }
    }
}

/// A view that asks for no width of its own, only its content's height at the width it is given (LAB-874): an
/// NSHostingView sized by its intrinsic content then never makes its container, or the window, wider.
struct NoIdealWidth<Content: View>: View {
    @ViewBuilder var content: () -> Content
    var body: some View { HeightOnly { content() } }

    private struct HeightOnly: Layout {
        func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
            let w = proposal.width.map { $0.isFinite ? $0 : 0 }
            let h = subviews.map { $0.sizeThatFits(ProposedViewSize(width: w, height: proposal.height)).height }.max() ?? 0
            return CGSize(width: w ?? 0, height: h)
        }
        func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
            for s in subviews { s.place(at: bounds.origin, proposal: ProposedViewSize(width: bounds.width, height: bounds.height)) }
        }
    }
}

/// Wraps a centre view in the centre theme and the window's text size.
struct CentreThemed<Content: View>: View {
    @ObservedObject var model: AppModel
    @ObservedObject var win: WindowState
    @ViewBuilder var content: () -> Content
    var body: some View {
        content()
            .themed(model.themes.centre, scale: win.textScale)
            .environment(\.v2Window, model.settings.ui2)
            .background(model.themes.centre.tokens.window.color)
    }
}

/// LAB-1556: a split view controller that can refuse a drag-collapse for some panels.
final class RoofSplitViewController: NSSplitViewController {
    /// Panels a divider drag may not fold away.
    var keepOnDrag: ((NSView) -> Bool)?

    override func splitView(_ splitView: NSSplitView, canCollapseSubview subview: NSView) -> Bool {
        if keepOnDrag?(subview) == true { return false }
        return super.splitView(splitView, canCollapseSubview: subview)
    }

    /// LAB-1612: dividers no drag may take (v2: the rail's, fixed at 66 pt, and the folded classic Files item's). With
    /// the Sessions column folded, all of them sit on the same spot as the column's own edge; a grab there took one of
    /// these and nothing moved, so the column could not be dragged back out.
    var fixedDividers: Set<Int> = []
    override func splitView(_ splitView: NSSplitView, effectiveRect proposedEffectiveRect: NSRect, forDrawnRect drawnRect: NSRect,
                            ofDividerAt dividerIndex: Int) -> NSRect {
        if fixedDividers.contains(dividerIndex) { return .zero }
        return super.splitView(splitView, effectiveRect: proposedEffectiveRect, forDrawnRect: drawnRect, ofDividerAt: dividerIndex)
    }

    /// LAB-1576: runs after every layout change, drags included.
    var afterResize: (() -> Void)?
    override func splitViewDidResizeSubviews(_ notification: Notification) {
        super.splitViewDidResizeSubviews(notification)
        afterResize?()
    }
}

/// LAB-1758 · every change of a main window's size you did not make by dragging its edge, with the event being handled
/// and the code that did it, in ~/Library/Logs/One Roof/window-frames.log (kept under 256 KB). A self-test writes
/// next to its other output instead.
enum WindowFrameLog {
    static func write(window: String, from: NSRect, to: NSRect, event: NSEvent?, undone: Bool) {
        let path: String
        if let out = ProcessInfo.processInfo.environment["ONEROOF_SELFTEST_OUT"] { path = out + "-frames.log" }
        else if SelfTest.isActive { return }
        else {
            let dir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/One Roof")
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            path = dir.appendingPathComponent("window-frames.log").path
        }
        if let size = (try? FileManager.default.attributesOfItem(atPath: path))?[.size] as? Int, size > 256_000 {
            try? FileManager.default.removeItem(atPath: path)
        }
        let r = { (f: NSRect) in "\(Int(f.minX)),\(Int(f.minY)) \(Int(f.width))×\(Int(f.height))" }
        let ev = event.map { "\($0.type.rawValue) at \(Int($0.locationInWindow.x)),\(Int($0.locationInWindow.y)) in \($0.window?.title ?? "-")" } ?? "none"
        let stamp = ISO8601DateFormatter().string(from: Date())
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        var text = "\(stamp) \(version) [\(window)] \(r(from)) → \(r(to))\(undone ? " UNDONE" : "") · event \(ev)\n"
        text += Thread.callStackSymbols.dropFirst(2).prefix(16).map { "    " + $0 }.joined(separator: "\n") + "\n"
        if let h = FileHandle(forWritingAtPath: path) { h.seekToEndOfFile(); h.write(Data(text.utf8)); h.closeFile() }
        else { try? text.write(toFile: path, atomically: true, encoding: .utf8) }
    }
}
