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
        window.minSize = NSSize(width: 1000, height: 560)
        window.isReleasedWhenClosed = false
        let autosave = win.id == WorkspaceStore.mainId ? "OneRoofMain" : "OneRoofMain." + win.id
        if !SelfTest.isActive { window.setFrameAutosaveName(autosave) }   // tests never change the owner's layout
        super.init(window: window)
        window.delegate = self
        Self.all.append(self)

        // Toolbar: a unified NSToolbar gives the 50 pt title bar with the traffic lights centred; its items are SwiftUI.
        toolbarDelegate = ToolbarDelegate(model: model, win: win, controller: self)
        let tb = NSToolbar(identifier: "OneRoofToolbar." + win.id)
        tb.delegate = toolbarDelegate
        tb.displayMode = .iconOnly
        tb.allowsUserCustomization = false
        tb.showsBaselineSeparator = false
        window.toolbar = tb
        window.toolbarStyle = .unified

        let sidebar = NSHostingController(rootView: SessionsPanel(model: model, win: win, controller: self))
        let plan = NSHostingController(rootView: PlanPanelView(model: model, win: win))
        let files = NSHostingController(rootView: FileBrowserView(model: model, win: win))
        // SwiftUI panels must not report a preferred/maximum size, or AppKit shrinks the window when a panel closes.
        sidebar.sizingOptions = []; plan.sizingOptions = []; files.sizingOptions = []
        centre = CentreController(model: model, win: win, terminalArea: terminalArea)

        split = NSSplitViewController()
        split.splitView.isVertical = true
        split.splitView.dividerStyle = .thin
        sideItem = NSSplitViewItem(viewController: sidebar)
        sideItem.minimumThickness = 240; sideItem.canCollapse = true
        sideItem.holdingPriority = .init(260)
        filesItem = NSSplitViewItem(viewController: files)
        filesItem.minimumThickness = 200; filesItem.canCollapse = true
        filesItem.holdingPriority = .init(255)
        filesItem.isCollapsed = true
        centreItem = NSSplitViewItem(viewController: centre)
        centreItem.minimumThickness = 420
        centreItem.canCollapse = true
        centreItem.holdingPriority = .init(250)
        planItem = NSSplitViewItem(viewController: plan)
        planItem.minimumThickness = 260; planItem.canCollapse = true
        planItem.holdingPriority = .init(251)
        for i in [sideItem, filesItem, centreItem, planItem] { split.addSplitViewItem(i!) }
        if !SelfTest.isActive { split.splitView.autosaveName = win.id == WorkspaceStore.mainId ? "OneRoofSplit" : "OneRoofSplit." + win.id }

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
            split.view.bottomAnchor.constraint(equalTo: root.bottomAnchor),
        ])

        if !window.setFrameUsingName(autosave), let screen = NSScreen.main {
            // First launch: 85% of the screen, at most 1700 × 1000, centred; later windows cascade.
            let v = screen.visibleFrame
            let size = NSSize(width: min(v.width * 0.85, 1700), height: min(v.height * 0.85, 1000))
            let shift = CGFloat(Self.all.count - 1) * 28
            window.setFrame(NSRect(x: v.midX - size.width / 2 + shift, y: v.midY - size.height / 2 - shift, width: size.width, height: size.height), display: false)
        }
        // Default widths (WINDOW_SHELL §3) when there is no saved layout: Sessions 300 · Plan 330.
        let saved = !SelfTest.isActive && !Prefs.freshProfile && UserDefaults.standard.object(forKey: "NSSplitView Subview Frames " + (split.splitView.autosaveName ?? "")) != nil
        if !saved {
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
    }

    required init?(coder: NSCoder) { fatalError("not supported") }

    // MARK: Window

    func windowDidBecomeKey(_ notification: Notification) {
        if model.activeWindowId != win.id { model.activeWindowId = win.id }
    }

    /// LAB-520: a double-click on empty toolbar space is a title-bar double-click, and macOS zooms the window. A window
    /// already stretched to fill the screen then "zooms" back to its last smaller size, so a stray double-click between the
    /// toolbar tabs shrank the window. Such a double-click never makes the window smaller; Window › Zoom still toggles.
    func windowShouldZoom(_ window: NSWindow, toFrame newFrame: NSRect) -> Bool {
        WindowZoom.allow(current: window.frame, to: newFrame, visible: window.screen?.visibleFrame,
                         fromTitleBarDoubleClick: Self.isTitleBarDoubleClick(NSApp.currentEvent, in: window))
    }

    static func isTitleBarDoubleClick(_ e: NSEvent?, in window: NSWindow) -> Bool {
        guard let e, e.window === window, [.leftMouseDown, .leftMouseUp].contains(e.type), e.clickCount >= 2 else { return false }
        return true
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        WindowCloseGuard.shared.shouldClose(sender, what: "the window \u{201C}\(win.name)\u{201D}",
            detail: "Its sessions keep running in roofd. Reopen the window from Window \u{25B8} Workspaces.")
    }

    /// Set when the app quits: AppKit then closes every window, and those closes are not the owner closing them.
    static var quitting = false

    func windowWillClose(_ notification: Notification) {
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
        let k = t.sidebar.tokens
        // LAB-590: a window with a colour gets a tinted band and a 2 pt stripe in the colour's ink; without one, as before.
        let accent = WindowAccent(named: win.colour, on: k)
        backdrop.fill = accent?.band ?? k.toolbar
        backdrop.line = accent?.ink ?? k.separator
        backdrop.lineWidth = accent == nil ? 1 : 2
        window?.appearance = t.sidebar.appearance
        sideItem.viewController.view.appearance = t.sidebar.appearance
        filesItem.viewController.view.appearance = t.files.appearance
        planItem.viewController.view.appearance = t.plan.appearance
    }

    // MARK: Panels

    /// Which panels are open (for the toolbar toggles).
    @Published var panels = PanelState()

    func syncPanels() {
        panels = PanelState(sidebar: !sideItem.isCollapsed, files: !filesItem.isCollapsed,
                            centre: !centreItem.isCollapsed, plan: !planItem.isCollapsed)
        terminalArea.planPanelOpen = panels.plan
    }

    /// Close or open the centre panel. With it closed, the plan panel takes the freed width (v0.1 rule).
    func toggleCentre() {
        let closing = !centreItem.isCollapsed
        if closing && sideItem.isCollapsed && planItem.isCollapsed && filesItem.isCollapsed { shake(); return }   // keep one panel
        planItem.holdingPriority = .init(closing ? 240 : 251)
        sideItem.holdingPriority = .init(closing ? 245 : 260)
        centreItem.animator().isCollapsed = closing
        syncLater()
    }

    func togglePlanPanel() { guard guardLast(planItem) else { return }; planItem.animator().isCollapsed.toggle(); syncLater() }
    func toggleFiles() { guard guardLast(filesItem) else { return }; filesItem.animator().isCollapsed.toggle(); syncLater() }
    func toggleSidebar() { guard guardLast(sideItem) else { return }; sideItem.animator().isCollapsed.toggle(); syncLater() }
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
        let hidden = sideItem.isCollapsed && planItem.isCollapsed
        sideItem.animator().isCollapsed = !hidden
        planItem.animator().isCollapsed = !hidden
        if !hidden { filesItem.animator().isCollapsed = true }
        centreItem.animator().isCollapsed = false
        syncLater()
    }

    /// Fleet views fold the Sessions panel away; Workspace brings it back as it was (S00.T.1).
    private func centreChanged(_ c: CentreView) {
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
            sideItem.minimumThickness = 56
            if !sideItem.isCollapsed { split.splitView.setPosition(56, ofDividerAt: 0) }
            if filesItem.isCollapsed { filesItem.animator().isCollapsed = false }
        } else if sideItem.minimumThickness != 240 {
            if let was = planBeforeEditor { planItem.animator().isCollapsed = !was; planBeforeEditor = nil }
            sideItem.minimumThickness = 240
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
    var fill = ThemeName.daylight.tokens.toolbar { didSet { needsDisplay = true } }
    var line = ThemeName.daylight.tokens.separator { didSet { needsDisplay = true } }
    var lineWidth: CGFloat = 1 { didSet { needsDisplay = true } }
    override var isFlipped: Bool { true }
    override func draw(_ dirtyRect: NSRect) {
        fill.nsColor.setFill(); bounds.fill()
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

    init(model: AppModel, win: WindowState, terminalArea: TerminalAreaController) {
        self.model = model; self.win = win; self.terminalArea = terminalArea
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError("not supported") }

    override func loadView() {
        let root = NSView()
        root.wantsLayer = true
        addChild(terminalArea)
        pin(terminalArea.view, in: root)
        hosts[.workspace] = terminalArea.view
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
        case .workspace: return terminalArea.view
        case .overview: v = AnyView(CentreThemed(model: m, win: w) { OverviewView(model: m, win: w) })
        case .resources: v = AnyView(CentreThemed(model: m, win: w) { ResourcesView(model: m, win: w) })
        case .board: v = AnyView(CentreThemed(model: m, win: w) { BoardView(model: m, win: w) })
        case .decisions: v = AnyView(CentreThemed(model: m, win: w) { DecisionsView(model: m, win: w) })
        case .subagents: v = AnyView(CentreThemed(model: m, win: w) { SubagentTraceView(model: m, win: w) })
        case .work: v = AnyView(CentreThemed(model: m, win: w) { WorkView(model: m) })
        case .learn: v = AnyView(CentreThemed(model: m, win: w) { LearnView(model: m) })
        case .objective: v = AnyView(CentreThemed(model: m, win: w) { ObjectiveView(model: m) })
        case .editor: v = AnyView(CentreThemed(model: m, win: w) { EditorView(model: m, win: w) })
        case .review: v = AnyView(CentreThemed(model: m, win: w) { ReviewChangesView(model: m, win: w) })
        case .loops: v = AnyView(CentreThemed(model: m, win: w) { LoopsView(model: m, win: w) })
        }
        let h = NSHostingView(rootView: v)
        h.sizingOptions = []
        pin(h, in: view)
        h.isHidden = true
        hosts[c] = h
        return h
    }

    func show(_ c: CentreView) {
        let next = host(c)
        let prev = hosts[current]
        current = c
        guard prev !== next else { next.isHidden = false; return }
        next.isHidden = false
        if Motion.reduce || prev == nil {
            prev?.isHidden = true
        } else {
            next.alphaValue = 0
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = 0.18
                ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
                next.animator().alphaValue = 1
                prev?.animator().alphaValue = 0
            }, completionHandler: { [weak prev, weak self] in
                guard let prev, let self, self.hosts[self.current] !== prev else { return }
                prev.isHidden = true
                prev.alphaValue = 1
            })
        }
        if c == .workspace { terminalArea.focusTerminal() }
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
            .background(model.themes.centre.tokens.window.color)
    }
}
