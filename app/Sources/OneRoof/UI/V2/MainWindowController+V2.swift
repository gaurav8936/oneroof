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
        // LAB-1612 / LAB-1829: the folded Files item's edge never drags; the rail's only while the Sessions column is
        // folded beside it (the grab there is the column's).
        (splitController as? RoofSplitViewController)?.fixedDividers = [2]
        (splitController as? RoofSplitViewController)?.lockedNow = { [weak self] i in
            guard i == 0, let self, let rail = self.v2RailItem else { return false }
            return V2Layout.railEdgeLocked(inSessions: self.win.place == .sessions && self.v2Page == nil,
                                           columnFolded: self.sideItemRef.isCollapsed, railShown: !rail.isCollapsed)
        }
        let tb = NSToolbar(identifier: "OneRoofToolbarV2." + win.id)
        let d = V2ToolbarDelegate(model: model, win: win, controller: self)
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
        // LAB-1829: a folded rail comes back by a drag from the window's left edge. Its edge is hidden while folded
        // (AppKit's own reveal strip only serves sidebar items), so this grip takes the drag.
        let grip = V2RailGrip()
        grip.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(grip)
        NSLayoutConstraint.activate([
            grip.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            grip.widthAnchor.constraint(equalToConstant: 12),
            grip.topAnchor.constraint(equalTo: top),
            grip.bottomAnchor.constraint(equalTo: root.bottomAnchor),
        ])
        grip.onPull = { [weak self] in self?.v2ToggleRail() }
        grip.isHidden = true
        v2RailGrip = grip
    }

    func v2Start() {
        if let c = win.centre.place, c != win.place { win.place = c }
        win.step.$focusStep.removeDuplicates().receive(on: DispatchQueue.main).sink { [weak self] _ in
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
        // Posted on the main thread: handled at once, so the mouse event that caused it is still the current one (a
        // queued handler ran after the drag and often missed it, so a dragged width was not kept, LAB-829).
        NotificationCenter.default.publisher(for: NSSplitView.didResizeSubviewsNotification, object: splitView)
            .sink { [weak self] n in
                self?.v2PaintBand(fit: self?.window?.inLiveResize != true)
                // A divider the owner dragged (setPosition from the layout also names a divider, but not mid-drag):
                // keep that width for this window (1.8.1).
                if let i = n.userInfo?["NSSplitViewDividerIndex"] as? Int,
                   [.leftMouseDragged, .leftMouseUp].contains(NSApp.currentEvent?.type) {
                    self?.v2RememberWidth(divider: i)
                } else {
                    self?.v2PinFocusLane()
                }
            }.store(in: &v2Bag)
        // LAB-1337: during a live resize only the band's colours follow each frame; fitting the toolbar (a SwiftUI
        // fittingSize) and the Plan runs once, when the drag ends.
        NotificationCenter.default.publisher(for: NSWindow.didResizeNotification, object: window)
            .sink { [weak self] _ in
                guard let self else { return }
                if self.window?.inLiveResize == true { self.v2PaintBand(fit: false) } else { self.v2PaintBand(); self.v2FitPlanToWidth() }
            }.store(in: &v2Bag)
        NotificationCenter.default.publisher(for: NSWindow.didEndLiveResizeNotification, object: window)
            .sink { [weak self] _ in self?.v2PaintBand(); self?.v2FitPlanToWidth() }.store(in: &v2Bag)
        v2InstallEscape()
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
        // LAB-1366: a Focus lane dragged wide already shows the list: no left-edge reveal over it.
        v2EdgeTracker?.isHidden = !(step == .focus && sessions && win.focusColumnWidth == nil)
        v2RightTracker?.isHidden = !(step == .focus && sessions)
        // LAB-1829: the grip only where the rail belongs and you folded it.
        v2RailGrip?.isHidden = !(win.railFolded && V2Layout.showsRail(step: step, inSessions: sessions, folded: false))

        // Outside Sessions the rail stays at every step, so Needs you is always visible (audit D2), unless you
        // dragged it closed (LAB-1829: the places then show as the toolbar's icon row).
        let showRail = V2Layout.showsRail(step: step, inSessions: sessions, folded: win.railFolded)
        let placesRow = step == .sessions || win.railFolded
        let side = sideItemRef, plan = planItemRef
        let windowWidth = window.map { Double($0.frame.width) }
        let columnWidth = CGFloat(V2Layout.columnWidth(step: step, saved: win.columnWidth, focusWide: win.focusColumnWidth,
                                                       windowWidth: windowWidth, placesRow: placesRow))
        // At Full the inspector takes its column only while it fits; a narrower window gets the edge tab (LAB-831).
        let fits = v2PlanFits(step: step, column: Double(columnWidth))
        v2PlanFitsLast = fits
        let planMode: (collapsed: Bool, edge: Bool) = !sessions || step == .focus ? (true, false) : (step == .full && fits ? (false, false) : (false, true))
        if v2PlanEdge != planMode.edge { v2PlanEdge = planMode.edge }   // LAB-1736: a same-value set still redraws every observer

        // LAB-1337: places outside Sessions share one layout (rail, no column, no Plan): moving between them changed
        // nothing here but still forced a full layout of every panel, the largest cost of switching places.
        let dockShownNow = v2DockOverride ?? (step == .full)
        // The split's actual state is part of the key: a panel opened or closed by hand since is put back.
        let key = "\(showRail)|\(placesRow)|\(sessions)|\(step)|\(planMode.collapsed)|\(planMode.edge)|\(columnWidth)|\(dockShownNow)|\(win.planWidth ?? 0)"
            + "|\(rail.isCollapsed)|\(sideItemRef.isCollapsed)|\(planItemRef.isCollapsed)|\(filesItemRef.isCollapsed)"
        if key == v2LastLayout, window?.inLiveResize != true { return }
        let apply = {
            rail.isCollapsed = !showRail
            side.isCollapsed = !sessions
            if sessions {
                // LAB-1366: at Focus the lane can be dragged from the avatars out to the full list. LAB-1783: the lane is
                // the rail's width, and at Sessions a drag stops where the toolbar's icon row ends.
                side.minimumThickness = step == .focus ? CGFloat(V2Layout.focusLane)
                    : placesRow ? CGFloat(V2Layout.sessionsColumnMin(windowWidth: windowWidth)) : CGFloat(V2Layout.columnMin)
                side.maximumThickness = 440
            }
            plan.isCollapsed = planMode.collapsed
            if !planMode.collapsed {
                plan.minimumThickness = planMode.edge ? 28 : 240
                plan.maximumThickness = planMode.edge ? 28 : 520
            }
            self.filesItemRef.isCollapsed = true   // LAB-1306: was a no-op (x = x); the v2 file tree is the Files tab
        }
        apply()
        v2LastLayout = "\(showRail)|\(placesRow)|\(sessions)|\(step)|\(planMode.collapsed)|\(planMode.edge)|\(columnWidth)|\(dockShownNow)|\(win.planWidth ?? 0)"
            + "|\(rail.isCollapsed)|\(sideItemRef.isCollapsed)|\(planItemRef.isCollapsed)|\(filesItemRef.isCollapsed)"
        splitView.layoutSubtreeIfNeeded()
        // Widths after the collapse changes have settled.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            let sv = self.splitView
            let railW: CGFloat = showRail ? 66 : 0
            if sessions && !side.isCollapsed { sv.setPosition(railW + columnWidth, ofDividerAt: 1) }
            // LAB-1601: the lane has its width now; it follows its live width again (the drag to widen it).
            if self.win.focusLaneSettling { self.win.focusLaneSettling = false }
            if !plan.isCollapsed {
                let w: CGFloat = planMode.edge ? 28 : CGFloat(V2Layout.planWidth(saved: self.win.planWidth))
                sv.setPosition(sv.bounds.width - w, ofDividerAt: 3)
            }
            self.v2PaintBand()
            self.syncPanels()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in self?.v2PaintBand(); self?.syncPanels() }
        }
        let dockShown = v2DockOverride ?? (step == .full)
        if v2DockFolded != !dockShown { v2DockFolded = !dockShown }
        v2SetDock(shown: dockShown, animated: animated)
        window?.toolbar?.items.forEach { $0.view?.needsLayout = true }
    }

    /// Whether the Plan inspector fits in its column at this step (LAB-831; only Full shows it there).
    func v2PlanFits(step: FocusStep, column: Double) -> Bool {
        guard let w = window?.frame.width else { return true }
        return V2Layout.planFits(windowWidth: Double(w), rail: step == .full || step == .wide, column: column)
    }

    /// A window resize that crosses the Plan's fit at Full folds it to the edge tab or brings it back (LAB-831).
    /// Only the columns move: the window keeps the size you gave it (LAB-596).
    func v2FitPlanToWidth() {
        guard win.place == .sessions, v2Page == nil, win.focusStep == .full else { return }
        let fits = v2PlanFits(step: .full, column: V2Layout.columnWidth(step: .full, saved: win.columnWidth))
        guard fits != v2PlanFitsLast else { return }
        v2ApplyLayout(animated: false)
    }

    /// After a drag: the session column (divider 1, or 2 beside the folded Files item) at steps 0-2, the Plan
    /// inspector (divider 3) at Full.
    func v2RememberWidth(divider i: Int) {
        guard win.place == .sessions, v2Page == nil else { return }
        if i == 1 || i == 2, win.focusStep != .focus, !sideItemRef.isCollapsed { win.columnWidth = Double(sideItemRef.viewController.view.frame.width) }
        // LAB-1366: the Focus lane snaps when the drag ends: back to the avatars, or wide enough for the full list.
        // LAB-1601: only after a real drag of it. A click (the Focus button's mouse-up) is also the last event while the
        // step lays out; read as a drag's end, it snapped the lane to 200, the step put it back to 52, and the two
        // fought for ~1,700 layouts (two seconds of a stuck window on every click into Focus).
        if i == 1 || i == 2, win.focusStep == .focus, NSApp.currentEvent?.type == .leftMouseDragged { v2LaneDragged = true }
        if i == 1 || i == 2, win.focusStep == .focus, !sideItemRef.isCollapsed, v2LaneDragged, NSApp.currentEvent?.type == .leftMouseUp {
            v2LaneDragged = false
            v2SetFocusLane(V2Layout.focusLaneSnap(dragged: Double(sideItemRef.viewController.view.frame.width)))
        }
        if i == 3, win.focusStep == .full, !planItemRef.isCollapsed, !v2PlanEdge { win.planWidth = Double(planItemRef.viewController.view.frame.width) }
    }

    /// LAB-1382: at Focus the lane may be dragged (maximum 440), so the split also hands it width it was not asked
    /// to take (the classic Files item folding gave it its width: an empty box with one avatar). Anything but your
    /// drag puts it back at its own width.
    func v2PinFocusLane() {
        guard win.focusStep == .focus, win.place == .sessions, v2Page == nil, !sideItemRef.isCollapsed,
              window?.inLiveResize != true else { return }
        let want = CGFloat(V2Layout.columnWidth(step: .focus, saved: win.columnWidth, focusWide: win.focusColumnWidth))
        guard abs(sideItemRef.viewController.view.frame.width - want) > 1 else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self, self.win.focusStep == .focus, !self.sideItemRef.isCollapsed else { return }
            let railW: CGFloat = self.v2RailItem?.isCollapsed == false ? 66 : 0
            self.splitView.setPosition(railW + want, ofDividerAt: 1)
        }
    }

    /// LAB-1366: the Focus lane at this width (nil = avatars); re-applied even when the width is unchanged, so a drag
    /// that snaps back lands exactly on the snapped width.
    func v2SetFocusLane(_ width: Double?) {
        win.focusColumnWidth = width
        v2LastLayout = nil
        v2ApplyLayout(animated: false)
    }

    /// The toolbar band takes the colour of the column under each part of it.
    func v2PaintBand(fit: Bool = true) {
        let t = model.themes
        var segs: [(CGFloat, RGB)] = []
        let views = splitView.subviews
        let colours: [RGB] = [t.sidebar.tokens.control, t.sidebar.tokens.sidebar, t.files.tokens.sidebar, t.centre.tokens.window, t.plan.tokens.surface]
        for (i, v) in views.enumerated() where i < colours.count && !v.isHidden && v.frame.width > 0.5 {
            segs.append((v.frame.maxX, colours[i]))
        }
        backdropRef.setSegments(segs)
        if fit { v2FitToolbar() }
        v2NudgeTrafficLights()
    }

    /// LAB-1620 · the window's close, minimise and zoom buttons sit inside the rail's colour (66 pt): at macOS's own
    /// place the green one straddled the line where the rail's band ends, half in each colour. Same spacing, moved left.
    func v2NudgeTrafficLights() {
        guard let w = window, !w.styleMask.contains(.fullScreen),
              let close = w.standardWindowButton(.closeButton), let mini = w.standardWindowButton(.miniaturizeButton),
              let zoom = w.standardWindowButton(.zoomButton) else { return }
        let gap = mini.frame.minX - close.frame.minX
        guard gap > 0 else { return }
        let first = V2Layout.trafficLightsStart(rail: 66, gap: Double(gap), button: Double(zoom.frame.width))
        for (k, b) in [close, mini, zoom].enumerated() {
            let x = CGFloat(first) + CGFloat(k) * gap
            if abs(b.frame.minX - x) > 0.5 { b.setFrameOrigin(NSPoint(x: x, y: b.frame.minY)) }
        }
    }

    /// The toolbar's room right of the column (LAB-1237): published only when the fit changes.
    func v2FitToolbar() {
        guard let window else { return }
        let centreX = centreItemRef.viewController.view.convert(CGPoint.zero, to: nil).x
        let start = V2Layout.toolbarStart(divider: Double(centreX), placesRow: v2PlacesRowShown)
        let extras = window.toolbar?.items.first { $0.itemIdentifier == V2ToolbarDelegate.extras }?.view?.fittingSize.width ?? 0
        let fit = V2Layout.toolbarFit(room: Double(window.frame.width) - start, extras: Double(extras))
        if fit != v2Bar { v2Bar = fit; DispatchQueue.main.async { [weak self] in self?.v2KickToolbar() } }
        // LAB-1783: the title's text starts where the centre's content does (its tabs, a page's heading).
        if let title = window.toolbar?.items.first(where: { $0.itemIdentifier == V2ToolbarDelegate.title })?.view, title.window != nil {
            let lightsEnd = window.standardWindowButton(.zoomButton).map { Double($0.convert($0.bounds, to: nil).maxX) } ?? 0
            let shift = V2Layout.titleShift(itemX: Double(title.convert(CGPoint.zero, to: nil).x), centreX: Double(centreX), lightsEnd: lightsEnd)
            if abs(CGFloat(shift) - v2TitleShift.x) > 0.5 { v2TitleShift.x = CGFloat(shift) }
        }
    }

    /// NSToolbar measures an item once it moved into » and never again, so after a window shrink with a long title
    /// the title, Single · Grid · Wall (and in 1.8.1 the right group) stayed hidden or clipped although the title then
    /// got shorter (LAB-1237). Invalidating the items' sizes and re-laying the toolbar view out brings them back.
    func v2KickToolbar() {
        guard let tb = window?.toolbar else { return }
        tb.items.forEach { $0.view?.invalidateIntrinsicContentSize() }
        for item in tb.items {   // the first item view still in the toolbar leads to the toolbar view
            var v = item.view?.superview
            while let s = v, !String(describing: type(of: s)).contains("NSToolbarView") { v = s.superview }
            if let v { v.needsLayout = true; return }
        }
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
            // LAB-1576: a Sessions column folded away by a drag comes back with one click on Sessions.
            if sideItemRef.isCollapsed && win.focusStep != .focus {
                sideItemRef.animator().isCollapsed = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in self?.v2PaintBand() }
            }
            return
        }
        win.open(p)
    }

    func v2SetStep(_ s: FocusStep) {
        // LAB-1383: Focus is the thin lane: a widened lane snaps back first; entering Focus starts thin.
        switch V2Layout.stepRequest(current: win.focusStep, requested: s, laneWide: win.focusColumnWidth != nil) {
        case .snapLane: v2SetFocusLane(nil); return
        case .enterFocusThin: win.focusColumnWidth = nil
        case .step: break
        }
        if s == .focus && win.focusStep != .focus { v2BeforeFocus = win.focusStep }
        win.focusStep = s
    }
    /// ⌥⌘F steps on; at Focus it leaves Focus again, as the 0.5.2.9 toggle did (Esc can't while the terminal has
    /// the keyboard, so without this a window could stay stuck at step 3, even across launches).
    func v2StepOn() {
        if win.focusStep == .focus && win.focusColumnWidth != nil { v2SetFocusLane(nil); return }   // LAB-1383
        if win.focusStep == .focus { v2LeaveFocus() } else { v2SetStep(win.focusStep.next) }
    }
    /// A click on the toolbar's step button: the next step, and from Focus round to Full (LAB-1235).
    func v2StepClick() { v2SetStep(win.focusStep.clicked) }
    func v2StepBack() { win.focusStep = win.focusStep.previous }
    /// Esc in Focus: back to the step before it.
    func v2LeaveFocus() { if win.focusStep == .focus { win.focusStep = v2BeforeFocus == .focus ? .wide : v2BeforeFocus } }

    /// ⌃⌘J: the dock full ↔ folded, without changing the step.
    func v2ToggleDock() {
        let shown = v2DockOverride ?? (win.focusStep == .full)
        v2DockOverride = !shown
        v2DockFolded = shown
        v2SetDock(shown: !shown, animated: true)
    }

    /// LAB-1736 · the split's bottom is pinned to the dock's top, so animating the dock's height re-laid out every panel
    /// and the terminal on each frame of the animation (Full ↔ Wide, ⌃⌘J). The height changes once; the dock fades in.
    func v2SetDock(shown: Bool, animated: Bool) {
        let h: CGFloat = shown ? 50 : 0
        guard let c = v2DockHeight, c.constant != h else { return }
        c.constant = h
        if animated && !Motion.reduce && shown, let dock = v2Dock {
            dock.alphaValue = 0
            NSAnimationContext.runAnimationGroup { ctx in ctx.duration = 0.18; dock.animator().alphaValue = 1 }
        } else { v2Dock?.alphaValue = 1 }
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
        case .full where v2PlanEdge:   // too narrow for the inspector column (LAB-831): slide it over instead
            if v2PlanOverlay == nil { v2ShowPlanOverlay() } else { v2HidePlanOverlay() }
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
            // LAB-1286: Esc in a pane's Table view (when it has the keyboard) goes back to the live terminal first.
            if e.keyCode == 53, mods.isEmpty, self.terminalArea.escapeTable() { return nil }
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
        // LAB-1736: the Plan is built once and kept under the edge tab (Wide, a narrow window) at its last width, so a
        // step between Full and Wide neither builds it again nor measures its text again (a third of the step's stall).
        GeometryReader { g in
            let edge = controller.v2PlanEdge
            ZStack(alignment: .topLeading) {
                V2PlanPanel(model: model, win: win, controller: controller).equatable()
                    .keptLaidOut(hidden: edge, minWidth: 200, room: g.size.width)
                if edge {
                    V2InspectorEdgeTab { tab in controller.v2ShowPlanOverlay(tab: tab) }
                        .themed(model.themes.plan, scale: win.textScale)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(width: g.size.width, height: g.size.height, alignment: .topLeading)
        }
    }
}

/// LAB-1736 · the docked Plan, redrawn only by its own model and window changes. Built in V2PlanSlot's body, its close
/// action was a new closure each time, which SwiftUI counts as a change: the whole Plan redrew, hidden or not, each time
/// the controller published anything (2–3 times per step).
private struct V2PlanPanel: View, Equatable {
    let model: AppModel
    let win: WindowState
    let controller: MainWindowController
    var body: some View { PlanPanelView(model: model, win: win) { [weak controller] in controller?.togglePlanPanel() } }
    static func == (a: Self, b: Self) -> Bool { a.model === b.model && a.win === b.win && a.controller === b.controller }
}

/// The Plan slid over the terminal (C7.1).
struct V2PlanOverlay: View {
    @ObservedObject var model: AppModel
    @ObservedObject var win: WindowState
    let controller: MainWindowController
    var body: some View {
        // LAB-1274: the close button sits at the end of the panel's own tab row (it floated over the tabs before).
        PlanPanelView(model: model, win: win) { controller.v2HidePlanOverlay() }
    }
}

/// Ask the Plan panel to open a tab (the edge tab's Ticket and Notes).
enum PlanTabRequest {
    static let name = Notification.Name("oneroof.v2.planTab")
    /// Only that window's Plan switches tab (audit D5).
    static func post(_ tab: Int, window: String) { NotificationCenter.default.post(name: name, object: nil, userInfo: ["tab": tab, "window": window]) }
}

/// A thin strip on a window edge that reports the pointer resting there.
/// LAB-1829 · the window's left edge while the rail is folded: a drag of more than 24 pt to the right brings the
/// rail back (the resize cursor says it can be pulled). The outer 3 pt stay the window's own resize edge.
final class V2RailGrip: NSView {
    var onPull: (() -> Void)?
    private var startX: CGFloat?
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard !isHidden, let sv = superview else { return nil }
        let p = convert(point, from: sv)
        return bounds.contains(p) && p.x >= 3 ? self : nil
    }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .resizeLeftRight) }
    /// A drag on a window in the background pulls the rail too (as a divider drag does), not just brings it forward.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) { startX = event.locationInWindow.x }
    override func mouseDragged(with event: NSEvent) {
        guard let s = startX, event.locationInWindow.x - s > 24 else { return }
        startX = nil
        onPull?()
    }
    override func mouseUp(with event: NSEvent) { startX = nil }
}

final class V2EdgeTracker: NSView {
    var onEnter: (() -> Void)?
    /// LAB-1367 / LAB-1368: open only after the pointer rests at the edge for `V2Layout.edgeRevealDwell`; opening on
    /// contact made the panels flash whenever the pointer passed the edge.
    var dwell: TimeInterval = V2Layout.edgeRevealDwell
    /// How far from the strip the pointer may drift while resting (a window not flush with the screen edge).
    static let restSlack: CGFloat = 18
    private var pending: DispatchWorkItem?
    /// Never takes clicks: the avatars and the Plan under the strip stay clickable (tracking areas still fire).
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self))
    }
    override func mouseEntered(with event: NSEvent) {
        pending?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.pending = nil
            if self.stillResting { self.onEnter?() }
        }
        pending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + dwell, execute: work)
    }
    /// At fire time: still shown, in the key window, no button held (a window-edge resize drag is not a rest), and
    /// the pointer still at the edge (not carried on into the terminal).
    private var stillResting: Bool {
        guard !isHiddenOrHasHiddenAncestor, let w = window, w.isKeyWindow, NSEvent.pressedMouseButtons == 0 else { return false }
        let p = convert(w.mouseLocationOutsideOfEventStream, from: nil)
        return bounds.insetBy(dx: -Self.restSlack, dy: 0).contains(p)
    }
    /// Hiding a view does not always send mouseExited: a pending reveal must not fire for a hidden strip.
    override var isHidden: Bool { didSet { if isHidden { pending?.cancel(); pending = nil } } }
    override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); pending?.cancel(); pending = nil }
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

