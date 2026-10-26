import AppKit
import SwiftUI
import Combine
import OneRoofCore

/// The v2 window (handover A1, FOCUS_LADDER.md), built into the same split view as 0.5 so every panel action keeps
/// working: rail · session column · (files, collapsed) · centre · Plan, with the dock under it and the toolbar band
/// split by tracking separators. The Focus step and the place decide which pieces show and how wide they are.
extension MainWindowController {

    // MARK: Install

    func v2InstallRailAndToolbar() {
        let rail = NSHostingController(rootView: V2RailHost(model: model, win: win, controller: self))
        rail.sizingOptions = []
        let item = NSSplitViewItem(viewController: rail)
        item.minimumThickness = 66; item.maximumThickness = 66
        item.canCollapse = true
        item.holdingPriority = .init(270)
        item.collapseBehavior = .preferResizingSiblingsWithFixedSplitView
        splitController.insertSplitViewItem(item, at: 0)
        v2RailItem = item
        filesItemRef.isCollapsed = true

        // Dividers: 0 rail|column · 1 column|files · 2 files|centre · 3 centre|plan.
        let tb = NSToolbar(identifier: "OneRoofToolbarV2." + win.id)
        let d = V2ToolbarDelegate(model: model, win: win, controller: self, splitView: splitView, centreDivider: 2)
        v2V2Toolbar = d
        tb.delegate = d
        tb.displayMode = .iconOnly
        tb.allowsUserCustomization = false
        tb.showsBaselineSeparator = false
        window?.toolbar = tb
        window?.toolbarStyle = .unified
    }

    func v2InstallDock(in root: NSView, under splitRoot: NSView, top: NSLayoutYAxisAnchor) {
        let dock = NSHostingView(rootView: V2DockHost(model: model, win: win, controller: self))
        dock.sizingOptions = []
        dock.wantsLayer = true
        dock.layer?.masksToBounds = true   // folded to 0 pt at steps 1-3: nothing may draw below the window
        dock.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(dock)
        let h = dock.heightAnchor.constraint(equalToConstant: 0)
        NSLayoutConstraint.activate([
            splitRoot.bottomAnchor.constraint(equalTo: dock.topAnchor),
            dock.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            dock.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            dock.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            h,
        ])
        v2Dock = dock
        v2DockHeight = h

        // Step 3: the left edge reveals the session column over the terminal (C7.2).
        let tracker = V2EdgeTracker()
        tracker.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(tracker)
        NSLayoutConstraint.activate([
            tracker.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            tracker.widthAnchor.constraint(equalToConstant: 6),
            tracker.topAnchor.constraint(equalTo: top),
            tracker.bottomAnchor.constraint(equalTo: root.bottomAnchor),
        ])
        tracker.onEnter = { [weak self] in self?.v2ShowEdgeReveal() }
        tracker.isHidden = true
        v2EdgeTracker = tracker
        // …and the right edge slides the Plan over it.
        let right = V2EdgeTracker()
        right.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(right)
        NSLayoutConstraint.activate([
            right.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            right.widthAnchor.constraint(equalToConstant: 6),
            right.topAnchor.constraint(equalTo: top),
            right.bottomAnchor.constraint(equalTo: root.bottomAnchor),
        ])
        right.onEnter = { [weak self] in self?.v2ShowPlanOverlay(hover: true) }
        right.isHidden = true
        v2RightTracker = right
    }

    func v2Start() {
        if let c = win.centre.place, c != win.place { win.place = c }
        win.$focusStep.removeDuplicates().receive(on: DispatchQueue.main).sink { [weak self] _ in
            self?.v2DockOverride = nil
            self?.v2ApplyLayout(animated: true)
        }.store(in: &v2Bag)
        win.$place.removeDuplicates().receive(on: DispatchQueue.main).sink { [weak self] _ in
            self?.v2ApplyLayout(animated: true)   // reads the current place and step, never the event's value
        }.store(in: &v2Bag)
        // Settings, Help and Release notes are pages over the current place (LAB-1084): no column, no Plan, the rail
        // keeps the place highlighted; Esc, ⌘[ or any place closes them.
        $v2Page.removeDuplicates().receive(on: DispatchQueue.main).sink { [weak self] p in
            guard let self else { return }
            self.v2PageHost?.isHidden = p == nil
            if p != nil, let host = self.v2PageHost { self.window?.makeFirstResponder(host) }   // keys go to the page, not the hidden terminal
            else if p == nil, self.win.centre == .workspace { self.terminalArea.focusTerminal() }
            self.v2ApplyLayout(animated: true)
        }.store(in: &v2Bag)
        v2InstallPageHost()
        // Anything that changes the centre (a notification, Search, a link) closes the page over it.
        win.$centre.removeDuplicates().dropFirst().receive(on: DispatchQueue.main).sink { [weak self] _ in self?.v2Page = nil }.store(in: &v2Bag)
        // …and so does picking a session (a notification, a oneroof:// link, the menu-bar popover, the hotkey).
        // (not the Wall: it watches every session, and background launches and exits change the selection)
        win.$selectedId.removeDuplicates().dropFirst().receive(on: DispatchQueue.main).sink { [weak self] _ in
            if self?.v2Page != "All windows" { self?.v2Page = nil }
        }.store(in: &v2Bag)
        // Wall (A4.2) is the "All windows" page; leaving it (Esc, ⌘[, a place, a tile) goes back to Single.
        win.$layout.removeDuplicates().receive(on: DispatchQueue.main).sink { [weak self] l in
            guard let self else { return }
            if l == .wall { self.v2ShowPage("All windows") } else if self.v2Page == "All windows" { self.v2Page = nil }
        }.store(in: &v2Bag)
        $v2Page.removeDuplicates().receive(on: DispatchQueue.main).sink { [weak self] p in
            if p != "All windows", self?.win.layout == .wall { self?.win.layout = .single }
        }.store(in: &v2Bag)
        NotificationCenter.default.publisher(for: NSSplitView.didResizeSubviewsNotification, object: splitView)
            .receive(on: DispatchQueue.main).sink { [weak self] _ in self?.v2PaintBand() }.store(in: &v2Bag)
        NotificationCenter.default.publisher(for: NSWindow.didResizeNotification, object: window)
            .receive(on: DispatchQueue.main).sink { [weak self] _ in self?.v2PaintBand() }.store(in: &v2Bag)
        v2InstallEscape()
        // The session tabs' Wrap: read the focused pane's text re-wrapped (LAB-657), in this window only.
        NotificationCenter.default.publisher(for: V2SessionTabs.wrap).receive(on: DispatchQueue.main).sink { [weak self] n in
            guard let self, n.object as? String == self.win.id else { return }
            self.terminalArea.toggleReading(self.terminalArea.focusedPane)
        }.store(in: &v2Bag)
        DispatchQueue.main.async { [weak self] in self?.v2ApplyLayout(animated: false) }
    }

    /// The place follows the centre inside WindowState. Since 1.2.0 the Files session tab holds the file tree, so the
    /// Editor no longer opens the separate Files panel (⌥⌘B still toggles it).
    func v2CentreChanged(_ c: CentreView) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in self?.v2PaintBand() }
    }

    // MARK: Layout

    /// Which pieces show at this step in this place, and how wide (FOCUS_LADDER.md table).
    func v2ApplyLayout(animated: Bool) {
        guard let rail = v2RailItem else { return }
        let step = win.focusStep, sessions = win.place == .sessions && v2Page == nil
        v2HidePlanOverlay(); v2HideEdgeReveal()
        v2EdgeTracker?.isHidden = !(step == .focus && sessions)
        v2RightTracker?.isHidden = !(step == .focus && sessions)

        // Outside Sessions the rail stays at every step, so Needs you is always visible (audit D2).
        let showRail = step == .full || step == .wide || !sessions
        let side = sideItemRef, plan = planItemRef
        let columnWidth: CGFloat = step == .focus ? 52 : (step == .sessions ? 280 : 250)
        let planMode: (collapsed: Bool, edge: Bool) = !sessions || step == .focus ? (true, false) : (step == .full ? (false, false) : (false, true))
        v2PlanEdge = planMode.edge

        let apply = {
            rail.isCollapsed = !showRail
            side.isCollapsed = !sessions
            if sessions {
                side.minimumThickness = step == .focus ? 52 : 200
                side.maximumThickness = step == .focus ? 52 : 440
            }
            plan.isCollapsed = planMode.collapsed
            if !planMode.collapsed {
                plan.minimumThickness = planMode.edge ? 28 : 240
                plan.maximumThickness = planMode.edge ? 28 : 520
            }
            self.filesItemRef.isCollapsed = self.filesItemRef.isCollapsed
        }
        apply()
        splitView.layoutSubtreeIfNeeded()
        // Widths after the collapse changes have settled.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            let sv = self.splitView
            let railW: CGFloat = showRail ? 66 : 0
            if sessions && !side.isCollapsed { sv.setPosition(railW + columnWidth, ofDividerAt: 1) }
            if !plan.isCollapsed {
                let w: CGFloat = planMode.edge ? 28 : 270
                sv.setPosition(sv.bounds.width - w, ofDividerAt: 3)
            }
            self.v2PaintBand()
            self.syncPanels()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in self?.v2PaintBand(); self?.syncPanels() }
        }
        let dockShown = v2DockOverride ?? (step == .full)
        v2DockFolded = !dockShown
        if animated && !Motion.reduce {
            NSAnimationContext.runAnimationGroup { ctx in ctx.duration = 0.18; v2DockHeight?.animator().constant = dockShown ? 50 : 0 }
        } else { v2DockHeight?.constant = dockShown ? 50 : 0 }
        window?.toolbar?.items.forEach { $0.view?.needsLayout = true }
    }

    /// The toolbar band takes the colour of the column under each part of it.
    func v2PaintBand() {
        let t = model.themes
        var segs: [(CGFloat, RGB)] = []
        let views = splitView.subviews
        let colours: [RGB] = [t.sidebar.tokens.control, t.sidebar.tokens.sidebar, t.files.tokens.sidebar, t.centre.tokens.window, t.plan.tokens.surface]
        for (i, v) in views.enumerated() where i < colours.count && !v.isHidden && v.frame.width > 0.5 {
            segs.append((v.frame.maxX, colours[i]))
        }
        backdropRef.segments = segs
    }

    func v2ApplyThemes(_ t: PanelThemes) {
        v2RailItem?.viewController.view.appearance = t.sidebar.appearance
        v2Dock?.appearance = t.sidebar.appearance
        DispatchQueue.main.async { [weak self] in self?.v2PaintBand() }
    }

    // MARK: Actions

    /// Open a place at its default step (rail, icon row, ⌃⌘1-7, the named view keys).
    func v2Open(_ p: Place) {
        v2Page = nil
        if p == .sessions && win.place == .sessions {
            if win.centre != .workspace { model.show(.workspace, in: win) }
            return
        }
        win.open(p)
    }

    func v2SetStep(_ s: FocusStep) {
        if s == .focus && win.focusStep != .focus { v2BeforeFocus = win.focusStep }
        win.focusStep = s
    }
    /// ⌥⌘F steps on; at Focus it leaves Focus again, as the 0.5.2.9 toggle did (Esc can't while the terminal has
    /// the keyboard, so without this a window could stay stuck at step 3, even across launches).
    func v2StepOn() { if win.focusStep == .focus { v2LeaveFocus() } else { v2SetStep(win.focusStep.next) } }
    func v2StepBack() { win.focusStep = win.focusStep.previous }
    /// Esc in Focus: back to the step before it.
    func v2LeaveFocus() { if win.focusStep == .focus { win.focusStep = v2BeforeFocus == .focus ? .wide : v2BeforeFocus } }

    /// ⌃⌘J: the dock full ↔ folded, without changing the step.
    func v2ToggleDock() {
        let shown = v2DockOverride ?? (win.focusStep == .full)
        v2DockOverride = !shown
        v2DockFolded = shown
        if Motion.reduce { v2DockHeight?.constant = shown ? 0 : 50 }
        else { NSAnimationContext.runAnimationGroup { ctx in ctx.duration = 0.18; v2DockHeight?.animator().constant = shown ? 0 : 50 } }
    }

    /// ⌥⌘S: the session column on or off, without changing the step.
    func v2ToggleColumn() {
        guard win.place == .sessions else { v2Open(.sessions); return }
        sideItemRef.animator().isCollapsed.toggle()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in self?.v2PaintBand() }
    }

    /// ⌥⌘P: at step 0 the inspector folds or opens; at steps 1-2 it slides over the terminal (no reflow).
    func v2TogglePlan() {
        guard win.place == .sessions else { return }
        switch win.focusStep {
        case .full:
            planItemRef.animator().isCollapsed.toggle()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in self?.v2PaintBand() }
        case .sessions, .wide, .focus:
            if v2PlanOverlay == nil { v2ShowPlanOverlay() } else { v2HidePlanOverlay() }
        }
    }

    func v2ShowLooks() { v2ShowSettings(pane: 1) }
    func v2OpenSettings(tab: Int) { v2ShowSettings(pane: tab) }

    /// Settings as a page over the current place (B1.x); `pane` from the 0.5 tab numbers or the v2 list.
    func v2ShowSettings(pane: Int) { v2SettingsPane = pane; v2ShowPage("Settings") }
    func v2ShowPage(_ title: String) {
        v2Page = title
        showWindow(nil); window?.makeKeyAndOrderFront(nil)   // ⌘, from another window opens it in front
    }

    /// The page layer: over the centre item (the column and Plan fold while it shows), hidden when no page is open.
    func v2InstallPageHost() {
        let centre = centreItemRef.viewController.view
        let host = V2PageHostingView(rootView: AnyView(V2PageHost(model: model, win: win, controller: self)))
        host.sizingOptions = []
        host.translatesAutoresizingMaskIntoConstraints = false
        host.isHidden = true
        centre.addSubview(host)
        NSLayoutConstraint.activate([host.leadingAnchor.constraint(equalTo: centre.leadingAnchor), host.trailingAnchor.constraint(equalTo: centre.trailingAnchor),
                                     host.topAnchor.constraint(equalTo: centre.topAnchor), host.bottomAnchor.constraint(equalTo: centre.bottomAnchor)])
        v2PageHost = host
    }
    func v2OpenSearch(query: String) {
        if query.isEmpty { NSApp.sendAction(#selector(AppDelegate.showPalette(_:)), to: nil, from: nil) }
        else { (NSApp.delegate as? AppDelegate)?.showPalette(query: query) }
    }

    /// The window switcher's menu (A10.4): every window with its colour and count, then the window actions.
    func v2ShowWindowMenu() {
        let m = NSMenu()
        let header = NSMenuItem(title: "WINDOWS", action: nil, keyEquivalent: ""); header.isEnabled = false
        m.addItem(header)
        for c in MainWindowController.all {
            let n = model.items(in: c.win).count
            let i = MenuAction("\(c.win.name)    \(n)") { c.window?.makeKeyAndOrderFront(nil) }
            i.state = c === self ? .on : .off
            if let accent = WindowAccent(named: c.win.colour, on: model.themes.sidebar.tokens) {
                i.image = NSImage(size: NSSize(width: 9, height: 9), flipped: false) { r in accent.ink.nsColor.setFill(); NSBezierPath(ovalIn: r).fill(); return true }
            }
            m.addItem(i)
        }
        m.addItem(.separator())
        m.addItem(MenuAction("New Window  ⇧⌘N") { [weak self] in self?.newWorkspace() })
        m.addItem(MenuAction("New Window for This Repo  ⌥⌘N") { NSApp.sendAction(#selector(AppDelegate.newRoofWindow(_:)), to: nil, from: nil) })
        m.addItem(MenuAction("Rename Window…") { [weak self] in self?.win.promptRename() })
        let colours = NSMenu()
        let none = MenuAction("None") { [weak self] in self?.win.setColour(nil) }
        none.state = win.colour == nil ? .on : .off
        colours.addItem(none)
        for p in Sticker.rowColors {
            let i = MenuAction(p.name.capitalized) { [weak self] in self?.win.setColour(p.name) }
            i.state = win.colour == p.name ? .on : .off
            colours.addItem(i)
        }
        let colour = NSMenuItem(title: "Window Colour", action: nil, keyEquivalent: ""); colour.submenu = colours
        m.addItem(colour)
        m.addItem(MenuAction("Show All Windows  ⌃↑") { NSApp.sendAction(#selector(AppDelegate.toggleLaunchpad(_:)), to: nil, from: nil) })
        m.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
    }

    // MARK: Overlays

    func v2ShowPlanOverlay(hover: Bool = false, tab: Int? = nil) {
        guard isV2, v2PlanOverlay == nil, let root = window?.contentView else { return }
        let host = V2HoverHost(rootView: AnyView(V2PlanOverlay(model: model, win: win, controller: self)))
        if hover { host.onExit = { [weak self] in self?.v2HidePlanOverlay() } }
        host.sizingOptions = []
        host.translatesAutoresizingMaskIntoConstraints = false
        host.wantsLayer = true
        host.shadow = NSShadow()
        host.layer?.shadowOpacity = 0.25; host.layer?.shadowRadius = 12; host.layer?.shadowOffset = CGSize(width: -2, height: 0)
        root.addSubview(host, positioned: .above, relativeTo: nil)
        let top = (window?.contentLayoutGuide as? NSLayoutGuide)?.topAnchor ?? root.topAnchor
        NSLayoutConstraint.activate([
            host.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: win.focusStep == .focus ? 0 : -28),
            host.widthAnchor.constraint(equalToConstant: 300),
            host.topAnchor.constraint(equalTo: top),
            host.bottomAnchor.constraint(equalTo: splitView.bottomAnchor),
        ])
        v2PlanOverlay = host
        if let tab, tab > 0 { DispatchQueue.main.async { [weak self] in if let id = self?.win.id { PlanTabRequest.post(tab, window: id) } } }
    }

    func v2HidePlanOverlay() { v2PlanOverlay?.removeFromSuperview(); v2PlanOverlay = nil }

    func v2ShowEdgeReveal() {
        guard isV2, v2EdgeOverlay == nil, win.focusStep == .focus, let root = window?.contentView else { return }
        let host = V2HoverHost(rootView: AnyView(V2SessionColumn(model: model, win: win, controller: self, overlay: true)))
        host.sizingOptions = []
        host.translatesAutoresizingMaskIntoConstraints = false
        host.wantsLayer = true
        host.layer?.shadowOpacity = 0.25; host.layer?.shadowRadius = 12
        host.onExit = { [weak self] in self?.v2HideEdgeReveal() }
        root.addSubview(host, positioned: .above, relativeTo: nil)
        let top = (window?.contentLayoutGuide as? NSLayoutGuide)?.topAnchor ?? root.topAnchor
        NSLayoutConstraint.activate([
            host.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            host.widthAnchor.constraint(equalToConstant: 280),
            host.topAnchor.constraint(equalTo: top),
            host.bottomAnchor.constraint(equalTo: splitView.bottomAnchor),
        ])
        v2EdgeOverlay = host
    }

    func v2HideEdgeReveal() { v2EdgeOverlay?.removeFromSuperview(); v2EdgeOverlay = nil }

    /// Esc leaves Focus, except when the terminal has the keyboard: there Esc belongs to the agent (Claude's
    /// interrupt), so it is never taken from it (0.5.2.9 behaviour wins; noted in the implementation notes).
    func v2InstallEscape() {
        v2EscMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] e in
            guard let self, e.window === self.window else { return e }
            let mods = e.modifierFlags.intersection([.command, .option, .control, .shift])
            // A page (LAB-1084) owns Esc and ⌘[ while it shows: they close it before anything underneath sees them.
            if self.v2Page != nil, !ShortcutsSettings.isRecording {
                if e.keyCode == 53, mods.isEmpty, !(self.window?.firstResponder is NSTextView) { self.v2Page = nil; return nil }
                if e.keyCode == 33, mods == .command { self.v2Page = nil; return nil }   // ⌘[
            }
            guard e.keyCode == 53, mods.isEmpty, self.win.place == .sessions else { return e }   // Focus is a Sessions thing
            guard self.win.focusStep == .focus else { return e }
            if self.window?.firstResponder is TerminalSurfaceView { return e }
            self.v2LeaveFocus()
            return nil
        }
    }
}

// MARK: Hosts

/// The rail in the sidebar theme, below the toolbar band.
struct V2RailHost: View {
    @ObservedObject var model: AppModel
    @ObservedObject var win: WindowState
    let controller: MainWindowController
    var body: some View { V2Rail(model: model, win: win, controller: controller).themed(model.themes.sidebar, scale: win.textScale) }
}

struct V2DockHost: View {
    @ObservedObject var model: AppModel
    @ObservedObject var win: WindowState
    let controller: MainWindowController
    var body: some View { V2Dock(model: model, resources: model.resources, controller: controller).themed(model.themes.sidebar, scale: 1) }
}

/// The Plan column: the 270 pt inspector at step 0 (today's Plan panel until M2 redraws it) or the edge tab.
struct V2PlanSlot: View {
    @ObservedObject var model: AppModel
    @ObservedObject var win: WindowState
    @ObservedObject var controller: MainWindowController
    var body: some View {
        if controller.v2PlanEdge {
            V2InspectorEdgeTab { tab in controller.v2ShowPlanOverlay(tab: tab) }
                .themed(model.themes.plan, scale: win.textScale)
        } else {
            PlanPanelView(model: model, win: win)
        }
    }
}

/// The Plan slid over the terminal (C7.1).
struct V2PlanOverlay: View {
    @ObservedObject var model: AppModel
    @ObservedObject var win: WindowState
    let controller: MainWindowController
    var body: some View {
        PlanPanelView(model: model, win: win)
            .overlay(alignment: .topTrailing) {
                Button { controller.v2HidePlanOverlay() } label: { Text("✕").ui(11) }
                    .buttonStyle(.plain).padding(8).help("Hide the Plan (⌥⌘P)").accessibilityLabel("Hide the Plan")
            }
    }
}

/// Ask the Plan panel to open a tab (the edge tab's Ticket and Notes).
enum PlanTabRequest {
    static let name = Notification.Name("oneroof.v2.planTab")
    /// Only that window's Plan switches tab (audit D5).
    static func post(_ tab: Int, window: String) { NotificationCenter.default.post(name: name, object: nil, userInfo: ["tab": tab, "window": window]) }
}

/// A thin strip on the window's left edge that reports the mouse entering it.
final class V2EdgeTracker: NSView {
    var onEnter: (() -> Void)?
    /// Never takes clicks: the avatars and the Plan under the strip stay clickable (tracking areas still fire).
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self))
    }
    override func mouseEntered(with event: NSEvent) { onEnter?() }
}

/// A hosting view that reports the mouse leaving it (the edge-reveal overlay hides then).
final class V2HoverHost: NSHostingView<AnyView> {
    var onExit: (() -> Void)?
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.filter { $0.owner === self && $0.userInfo?["v2"] != nil }.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self, userInfo: ["v2": true]))
    }
    /// Hides a moment after the mouse leaves, and only if it has not come back (a row's menu or popover is open over
    /// the column, or the mouse just crossed its edge) (audit D9).
    override func mouseExited(with event: NSEvent) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { [weak self] in
            guard let self, let w = self.window else { return }
            let p = self.convert(w.mouseLocationOutsideOfEventStream, from: nil)
            if self.bounds.contains(p) || NSApp.windows.contains(where: { $0 !== w && $0.isVisible && $0.level.rawValue > w.level.rawValue && $0.className.contains("Popover") }) { return }
            self.onExit?()
        }
    }
}

