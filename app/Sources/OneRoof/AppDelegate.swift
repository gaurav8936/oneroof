import AppKit
import OneRoofCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = AppModel()
    /// The main window in front (the active workspace), or the first one.
    var main: MainWindowController! {
        MainWindowController.forWorkspace(model.active.id) ?? MainWindowController.all.first
    }

    /// oneroof:// links; ones that arrive before the window exists wait for it.
    private var pendingLinks: [URL] = []
    private var launched = false

    func application(_ application: NSApplication, open urls: [URL]) {
        guard launched else { pendingLinks += urls; return }
        for u in urls {
            if let link = RoofLink.parse(u) { model.open(link) } else { model.lastError = "One Roof cannot open \(u.absoluteString)." }
        }
    }

    /// Keeps App Nap off: One Roof watches agents from the background (status, decisions, Dock badge, schedules).
    /// Napped, its timers and run loop were delayed by tens of seconds once its windows were hidden.
    private var watchActivity: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        watchActivity = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiatedAllowingIdleSystemSleep], reason: "One Roof watches agent sessions")
        if let err = GhosttyRuntime.shared.initError { model.lastError = "Terminal engine: \(err)" }
        NSApp.mainMenu = buildMenu()
        applyShortcuts()
        NotificationCenter.default.addObserver(forName: .shortcutsChanged, object: nil, queue: .main) { [weak self] _ in self?.applyShortcuts() }
        ShortcutBridge.onHotKey = { [weak self] in self?.toggleFromHotKey() }
        // One main window per open workspace (S00: restores every workspace window).
        let wanted = ProcessInfo.processInfo.environment["ONEROOF_SELFTEST_WORKSPACE"]
        if let wanted, !model.windows.contains(where: { $0.name == wanted }) {
            model.adopt(WindowState(id: "selftest-" + wanted.lowercased(), name: wanted))
        }
        for w in model.windows { openWindow(for: w) }
        if let wanted, let w = model.windows.first(where: { $0.name == wanted }) { model.activeWindowId = w.id }
        NotificationCenter.default.addObserver(forName: .newWorkspace, object: nil, queue: .main) { [weak self] n in
            guard let self, let a = n.object as? [String], let name = a.first else { return }
            let r = WorkspaceStore.shared.create(name: name, colour: a.count > 1 && !a[1].isEmpty ? a[1] : nil)
            let w = WindowState(id: r.id, name: r.name, colour: r.colour)
            self.model.adopt(w)
            self.model.activeWindowId = w.id
            self.openWindow(for: w)
        }
        NotificationCenter.default.addObserver(forName: .focusWorkspace, object: nil, queue: .main) { [weak self] n in
            guard let self, let id = n.object as? String else { return }
            if MainWindowController.forWorkspace(id) == nil, let w = self.model.window(id) { self.openWindow(for: w) }
            self.model.activeWindowId = id
            if !SelfTest.isActive { MainWindowController.forWorkspace(id)?.window?.makeKeyAndOrderFront(nil) }
        }
        model.start()
        statusItem = StatusItemController(model: model)
        launched = true
        if !pendingLinks.isEmpty {
            // A link that launched the app: give roofd and the store a moment to fill the sidebar first.
            let links = pendingLinks; pendingLinks = []
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in self?.application(NSApp, open: links) }
        }
        NotificationCenter.default.addObserver(forName: .panelCommand, object: nil, queue: .main) { [weak self] n in
            switch n.object as? String {
            case "sidebar": self?.main.toggleSidebar()
            case "plan": self?.main.togglePlanPanel()
            case "files": self?.main.toggleFiles()
            default: self?.main.toggleFocus()
            }
        }
        NotificationCenter.default.addObserver(forName: .newObjective, object: nil, queue: .main) { [weak self] _ in
            self?.main.newObjective()
        }
        NotificationCenter.default.addObserver(forName: .openFoundations, object: nil, queue: .main) { [weak self] _ in
            self?.showFoundations(nil)
        }
        NotificationCenter.default.addObserver(forName: .openSetup, object: nil, queue: .main) { [weak self] _ in
            self?.showSetup(nil)
        }
        // First run on this Mac (or --fresh-profile): the setup window. Self-tests show it only for a fresh profile.
        if !model.settings.setupDone, !SelfTest.isActive || Prefs.freshProfile {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in self?.showSetup(nil) }
        }
        SelfTest.runIfRequested(app: self)
    }

    func applicationWillTerminate(_ notification: Notification) { LocalModel.shared.stop() }

    /// Open (or bring forward) the main window of a workspace.
    @discardableResult
    func openWindow(for w: WindowState) -> MainWindowController {
        if let c = MainWindowController.forWorkspace(w.id) { c.window?.makeKeyAndOrderFront(nil); return c }
        if var r = WorkspaceStore.shared.workspaces.first(where: { $0.id == w.id }), !r.open, !SelfTest.isActive {
            r.open = true
            WorkspaceStore.shared.update(r)
        }
        model.adopt(w)
        let c = MainWindowController(model: model, win: w)
        if SelfTest.isActive {
            // Self-test: stay behind the owner's windows and never take keyboard focus from their apps.
            c.window?.orderBack(nil)
        } else {
            c.showWindow(nil)
            c.window?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
        if w.id == model.windows.first?.id, ProcessInfo.processInfo.environment["ONEROOF_SELFTEST_CENTRE"] == nil, !SelfTest.isActive,
           Prefs.defaults.object(forKey: "v2.firstLaunch") == nil {
            // First v2 launch opens on Overview (S00 L0).
            Prefs.defaults.set(true, forKey: "v2.firstLaunch")
            w.centre = .overview
        }
        return c
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    // MARK: Actions

    var settingsWindow: SettingsWindowController?
    var setupWindow: SetupWindowController?

    /// One Roof › Setup… (also shown at first launch): folders, agents, optional Linear key.
    @objc func showSetup(_ sender: Any?) {
        if setupWindow == nil { setupWindow = SetupWindowController(model: model) { [weak self] in self?.setupWindow?.close() } }
        setupWindow?.showWindow(nil)
        if SelfTest.isActive { setupWindow?.window?.orderBack(nil) } else {
            setupWindow?.window?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
    }
    private var statusItem: StatusItemController?
    var foundationsWindow: FoundationsWindowController?

    @objc func showFoundations(_ sender: Any?) {
        if foundationsWindow == nil {
            foundationsWindow = FoundationsWindowController(model: model,
                tab: Int(ProcessInfo.processInfo.environment["ONEROOF_SELFTEST_FOUNDATIONS_TAB"] ?? "") ?? 0)
        }
        if model.foundations.isEmpty { model.runFoundations() }
        foundationsWindow?.showWindow(nil)
        if SelfTest.isActive { foundationsWindow?.window?.orderBack(nil) } else { foundationsWindow?.window?.makeKeyAndOrderFront(nil) }
    }
    @objc func runCheck(_ sender: Any?) { model.runFoundations(); showFoundations(nil) }

    @objc func newSession(_ sender: Any?) { main.newSession() }
    @objc func newTerminal(_ sender: Any?) { model.newTerminal() }
    @objc func newObjective(_ sender: Any?) { main.newObjective() }
    @objc func newTerminalInRepo(_ sender: Any?) { model.newTerminal(in: model.selected?.session.repoPath) }
    @objc func showSettings(_ sender: Any?) {
        if settingsWindow == nil {
            settingsWindow = SettingsWindowController(model: model, tab: Int(ProcessInfo.processInfo.environment["ONEROOF_SELFTEST_SETTINGS_TAB"] ?? "") ?? 0)
        }
        settingsWindow?.showWindow(nil)
        settingsWindow?.window?.makeKeyAndOrderFront(nil)
    }
    @objc func markNext(_ sender: Any?) { if let i = model.selected { model.setLifecycle(i, .next) } }
    @objc func markPlanned(_ sender: Any?) { if let i = model.selected { model.setLifecycle(i, .planned) } }
    @objc func markDoNotUse(_ sender: Any?) {
        guard let i = model.selected else { return }
        model.setLifecycle(i, i.status == .doNotUse ? (i.liveAgent == nil ? .planned : .idle) : .doNotUse)
    }
    @objc func closeSelected(_ sender: Any?) { if let i = model.selected, i.liveAgent != nil { model.confirmClose(i) } }
    @objc func deleteSelected(_ sender: Any?) { if let i = model.selected, !i.adopted { model.delete(i) } }
    @objc func openRepo(_ sender: Any?) {
        if let i = model.selected { NSWorkspace.shared.open(URL(fileURLWithPath: i.session.repoPath)) }
    }
    @objc func popOut(_ sender: Any?) { if let i = model.selected { PopOutWindowController.popOut(i, model: model) } }
    /// Learn, ready for a question.
    @objc func howDoI(_ sender: Any?) { model.howDoI("") }
    /// Roof window for the selected session's repo.
    @objc func newRoofWindow(_ sender: Any?) { if let i = model.selected { RoofWindowController.show(.repo(i.session.repoPath), model: model) } }
    private lazy var roofMenu = RoofMenu(model: model)
    @objc func copyCwd(_ sender: Any?) {
        guard let i = model.selected else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(i.session.launchDirectory, forType: .string)
    }
    @objc func removeExited(_ sender: Any?) {
        let n = model.items.filter { $0.status == .exited && !$0.session.pinned && !$0.adopted }.count
        guard n > 0 else { return }
        let a = NSAlert()
        a.messageText = "Remove \(n) exited session\(n == 1 ? "" : "s")?"
        a.informativeText = "Their agents are already gone. Notes and stickers go with them; pinned sessions stay."
        a.addButton(withTitle: "Remove"); a.addButton(withTitle: "Cancel")
        if a.runModal() == .alertFirstButtonReturn { model.removeExited() }
    }
    @objc func copyAttach(_ sender: Any?) {
        guard let a = model.selected?.liveAgent else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(model.runtime.attachCommand(a), forType: .string)
    }
    /// ⌘+ ⌘− ⌘0 scale the window's UI type (0.85–1.3, S00.W.2) and the terminal font with it.
    @objc func textBigger(_ sender: Any?) { model.active.setTextScale(model.active.textScale + 0.05); main.terminalArea.terminalAction("increase_font_size:1") }
    @objc func textSmaller(_ sender: Any?) { model.active.setTextScale(model.active.textScale - 0.05); main.terminalArea.terminalAction("decrease_font_size:1") }
    @objc func textReset(_ sender: Any?) { model.active.setTextScale(1); main.terminalArea.terminalAction("reset_font_size") }

    // MARK: v2 actions

    @objc func newWorkspaceWindow(_ sender: Any?) { main.newWorkspace() }
    @objc func showResources(_ sender: Any?) { model.centre = model.centre == .resources ? .workspace : .resources }
    @objc func showDecisions(_ sender: Any?) { model.centre = model.centre == .decisions ? .workspace : .decisions }
    @objc func showSubagents(_ sender: Any?) { model.centre = model.centre == .subagents ? .workspace : .subagents }
    /// ⌘R: Run in the Editor, Raw stream in a session (SHORTCUTS: context-dependent).
    @objc func toggleRawStream(_ sender: Any?) {
        if model.centre == .editor { NotificationCenter.default.post(name: .runFile, object: [model.active.id]) }
        else { NotificationCenter.default.post(name: .rawStream, object: model.active.id) }
    }
    @objc func debugFile(_ sender: Any?) { NotificationCenter.default.post(name: .runFile, object: [model.active.id, "debug"]) }
    @objc func askAgentAboutSelection(_ sender: Any?) { NotificationCenter.default.post(name: .askAboutSelection, object: model.active.id) }
    @objc func saveFile(_ sender: Any?) { NotificationCenter.default.post(name: .saveFile, object: model.active.id) }
    @objc func openFile(_ sender: Any?) {
        let p = NSOpenPanel()
        p.directoryURL = URL(fileURLWithPath: model.selected?.session.repoPath ?? Workspace.projectsRoot)
        p.canChooseDirectories = false
        guard p.runModal() == .OK, let u = p.url else { return }
        model.openInViewer(u.path)
    }
    @objc func togglePinSelected(_ sender: Any?) { if let i = model.selected { model.togglePin(i) } }
    @objc func renameSelected(_ sender: Any?) {
        guard let i = model.selected else { return }
        let a = NSAlert()
        a.messageText = "Rename session"
        let f = NSTextField(string: i.session.name)
        f.frame = NSRect(x: 0, y: 0, width: 260, height: 24)
        a.accessoryView = f
        a.addButton(withTitle: "Rename"); a.addButton(withTitle: "Cancel")
        if a.runModal() == .alertFirstButtonReturn { model.rename(i, f.stringValue) }
    }
    @objc func attachIssueToSelected(_ sender: Any?) { if let i = model.selected { main.attachIssue(i) } }
    @objc func scheduleTonight(_ sender: Any?) { if let i = model.selected { model.schedule(i, hour: 2, minute: 0, nightly: false) } }
    @objc func scheduleNightly(_ sender: Any?) { if let i = model.selected { model.schedule(i, hour: 2, minute: 0, nightly: true) } }
    @objc func scheduleOff(_ sender: Any?) { if let i = model.selected { model.unschedule(i) } }
    @objc func interruptSelected(_ sender: Any?) { if let i = model.selected { model.interrupt(i) } }
    @objc func sendHandoff(_ sender: Any?) { if let i = model.selected { model.askForHandoff(i) } }
    @objc func copySessionId(_ sender: Any?) {
        guard let a = model.selected?.liveAgent else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(a, forType: .string)
    }
    @objc func goToWorkspace(_ sender: NSMenuItem) {
        guard let w = model.windows[safe: sender.tag - 1] else { return }
        openWindow(for: w)
    }
    @objc func openHelp(_ sender: Any?) {
        guard let page = AppResources.helpStartPage() else { model.lastError = "One Roof Help is not bundled with this build."; return }
        model.loadLearn()
        model.learnTarget = page
        model.centre = .learn
    }
    @objc func showShortcuts(_ sender: Any?) { settingsWindow = nil; showSettingsTab(4) }
    @objc func openReleaseNotes(_ sender: Any?) { openBundled(AppResources.releaseNotes, "Release notes") }
    private func openBundled(_ path: String?, _ what: String) {
        if let path { openPath(path) } else { model.lastError = "\(what) are not bundled with this build." }
    }
    private func showSettingsTab(_ tab: Int) {
        if settingsWindow == nil { settingsWindow = SettingsWindowController(model: model, tab: tab) }
        settingsWindow?.showWindow(nil)
        settingsWindow?.window?.makeKeyAndOrderFront(nil)
    }
    private lazy var moveMenu = MoveMenu(model: model)
    private lazy var workspaceMenu = WorkspaceListMenu(app: self)
    @objc func clearTerminal(_ sender: Any?) { main.terminalArea.terminalAction("clear_screen") }
    @objc func showPalette(_ sender: Any?) { PalettePanel.show(over: main.window, items: paletteItems()) }

    /// Everything the palette can find: views, actions, sessions, objectives, files in the selected repo, skills.
    private func paletteItems() -> [PaletteItem] {
        var out: [PaletteItem] = []
        let m = model
        func add(_ t: String, _ sub: String, _ sym: String, _ kind: String, _ run: @escaping () -> Void) {
            out.append(PaletteItem(title: t, subtitle: sub, symbol: sym, kind: kind, run: run))
        }
        add("Workspace", "Back to the terminals", "terminal", "View") { m.goTerminals() }
        add("Overview", "Every window, the feed, objectives (⇧⌘L)", "square.grid.2x2", "View") { m.centre = .overview }
        add("Resources", "Memory and CPU of One Roof, every window and session (⇧⌘U)", "gauge.with.dots.needle.33percent", "View") { m.centre = .resources }
        add("Decisions", "\(m.openDecisionCount) waiting (⌘I)", "hand.raised", "View") { m.centre = .decisions }
        add("Subagents", "Trace of every subagent (⇧⌘A)", "point.3.connected.trianglepath.dotted", "View") { m.centre = .subagents }
        add("New workspace window", "⇧⌘N", "macwindow.badge.plus", "Action") { [weak self] in self?.main.newWorkspace() }
        for w in m.windows { add("Window: \(w.name)", "\(m.items(in: w).count) sessions", "macwindow", "Window") { [weak self] in self?.openWindow(for: w) } }
        for d in m.openDecisions {
            add(d.headline, "Decision · " + (m.item(d.sessionId)?.session.name ?? ""), "hand.raised", "Decision") { m.centre = .decisions }
        }
        add("Board", "Kanban of every session", "rectangle.split.3x1", "View") { m.boardMode = true }
        add("Work", "Projects, roadmap, tickets", "list.bullet.rectangle", "View") { m.workMode = true }
        add("Learn", "Course, skills, Help, your Learn folders", "graduationcap", "View") { m.learnMode = true }
        add("Foundations", "Startup check, skills, hooks, memory", "checkmark.shield", "View") { [weak self] in self?.showFoundations(nil) }
        add("Settings", "Themes, agents, accounts, foundations", "gearshape", "View") { [weak self] in self?.showSettings(nil) }
        add("Plan a session", "⌘N", "plus.circle", "Action") { [weak self] in self?.main.newSession() }
        add("New terminal", "⌘T", "terminal.fill", "Action") { m.newTerminal() }
        add("New objective", "⌘⇧O", "target", "Action") { [weak self] in self?.main.newObjective() }
        add("New work item", "⌃⌘N", "plus.square.on.square", "Action") { [weak self] in self?.newWorkItem(nil) }
        add("Find in terminal", "⌘F", "magnifyingglass", "Action") { [weak self] in self?.findInTerminal(nil) }
        add("Toggle sessions panel", "⌘⌥S", "sidebar.left", "Action") { [weak self] in self?.main.toggleSidebar() }
        add("Toggle file browser", "⌘⌥B", "folder", "Action") { [weak self] in self?.main.toggleFiles() }
        add("Review changes (git diff)", "⌘⌥R", "plusminus", "Action") { m.openDiff() }
        add("Search in workspace", "⌘⇧S", "magnifyingglass", "Action") { m.openSearch() }
        add("Split pane right", "⌘D", "rectangle.split.2x1", "Action") { [weak self] in self?.splitRight(nil) }
        add("Split pane down", "⌘⇧D", "rectangle.split.1x2", "Action") { [weak self] in self?.splitDown(nil) }
        add("Reopen closed session", "⌘⌥T", "arrow.uturn.backward.circle", "Action") { [weak self] in self?.reopenClosed(nil) }
        add("Close pane", "⌘⌥W", "xmark.rectangle", "Action") { [weak self] in self?.closePane(nil) }
        add("Maximize pane", "⌘⇧↩", "arrow.up.left.and.arrow.down.right", "Action") { [weak self] in self?.zoomPane(nil) }
        add("Even out panes", "", "equal.square", "Action") { [weak self] in self?.evenOutPanes(nil) }
        add("Toggle centre panel", "⌘⌥C", "rectangle.center.inset.filled", "Action") { [weak self] in self?.main.toggleCentre() }
        add("Toggle plan panel", "⌘⌥P", "sidebar.right", "Action") { [weak self] in self?.main.togglePlanPanel() }
        add("Focus: terminal only", "⌘⌥F", "rectangle.inset.filled", "Action") { [weak self] in self?.main.toggleFocus() }
        add("Run startup check", "Foundations", "arrow.clockwise", "Action") { [weak self] in self?.runCheck(nil) }
        add("Remove exited sessions", "Session menu", "trash", "Action") { [weak self] in self?.removeExited(nil) }
        if let sel = m.selected, sel.liveAgent != nil {
            add("Open \(sel.session.name) in new window", "⌘⌥O", "macwindow.on.rectangle", "Action") { PopOutWindowController.popOut(sel, model: m) }
        }
        add("How do I…? (Learn)", "⌘⌥/", "questionmark.circle", "View") { m.howDoI("") }
        for r in RoofScope.available(in: m.items) {
            add("Roof window: \(r.scope.title)", "\(r.count) live session\(r.count == 1 ? "" : "s")", "house", "Action") { RoofWindowController.show(r.scope, model: m) }
        }
        for t in ThemeName.panelChoices {
            add("Theme: all panels \(t.label)", "Sessions, files, terminal, plan", "paintpalette", "Theme") {
                m.chosenThemes = PanelThemes(sidebar: t, files: t, terminal: t, plan: t, centre: t)
            }
        }
        for i in m.items {
            add(i.session.name, [i.account ?? i.session.agent.displayName, m.caption(for: i).text, m.window(m.workspaceId(of: i))?.name].compactMap { $0 }.joined(separator: " · "),
                "rectangle.stack", "Session") { m.reveal(i) }
        }
        for o in m.objectives {
            add(o.title, "Objective · \(o.status.rawValue)", "target", "Objective") { m.objectiveId = o.id }
        }
        for w in m.workstreams where !["completed", "canceled"].contains(w.state) {
            add(w.name, "Project · \(w.stateLabel)", "list.bullet.rectangle", "Project") { m.workMode = true }
        }
        // Files tracked in the selected session's repo (git ls-files), capped.
        let repo = m.selected?.session.repoPath ?? Workspace.projectsRoot
        if repo != Workspace.projectsRoot {
            let (rc, files) = Foundations.run("/usr/bin/git", ["-C", repo, "ls-files"], timeout: 3)
            if rc == 0 {
                for f in files.split(separator: "\n").prefix(4000) {
                    let path = repo + "/" + f
                    add(String((f as Substring).split(separator: "/").last ?? f), String(f), "doc", "File") { m.openInViewer(path) }
                }
            }
        }
        for s in Foundations.skills(FoundationPaths(agenticEngineering: m.settings.agenticEngineering.path)) {
            let html = s.path + "/" + (s.path as NSString).lastPathComponent + ".html"
            add(s.name, "Skill · " + s.track + " · " + s.description, "wand.and.stars", "Skill") {
                m.learnTarget = html; m.learnMode = true
            }
        }
        return out
    }

    @objc func findInTerminal(_ sender: Any?) { model.goTerminals(); main.terminalArea.showFind() }
    @objc func findNext(_ sender: Any?) { main.terminalArea.findNext() }
    @objc func findPrevious(_ sender: Any?) { main.terminalArea.findPrevious() }
    @objc func openReadme(_ sender: Any?) { openBundled(AppResources.readme, "The README files") }
    @objc func openDocs(_ sender: Any?) { openBundled(AppResources.helpFolder, "Help pages") }
    private func openPath(_ p: String) { model.openInViewer(p) }
    @objc func toggleSidebarPanel(_ sender: Any?) { main.toggleSidebar() }
    @objc func togglePlanPanel(_ sender: Any?) { main.togglePlanPanel() }
    @objc func toggleFocus(_ sender: Any?) { main.toggleFocus() }
    @objc func toggleFiles(_ sender: Any?) { main.toggleFiles() }
    @objc func reviewChanges(_ sender: Any?) { model.openDiff() }

    /// Owner's shortcut overrides and the global hotkey. Self-tests never register a global hotkey.
    func applyShortcuts() {
        ShortcutBridge.apply(model.settings.shortcuts, to: NSApp.mainMenu)
        guard !SelfTest.isActive else { return }
        let hk = Shortcut(model.settings.globalHotkey)
        if !ShortcutBridge.setGlobalHotKey(hk), let hk {
            model.lastError = "The global shortcut \(hk.display) could not be registered (another app may own it)."
        }
    }

    /// Global hotkey: bring One Roof to the front, or hide it if it is already in front.
    private func toggleFromHotKey() {
        if NSApp.isActive, main.window?.isKeyWindow == true { NSApp.hide(nil); return }
        NSApp.activate(ignoringOtherApps: true)
        main.showWindow(nil)
        main.window?.makeKeyAndOrderFront(nil)
        main.terminalArea.focusTerminal()
    }
    @objc func copyLink(_ sender: Any?) {
        guard let i = model.selected else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(RoofLink.link(session: i.id), forType: .string)
    }
    @objc func searchWorkspace(_ sender: Any?) { model.openSearch() }
    @objc func reopenClosed(_ sender: Any?) { showTerminals(); model.reopenClosed() }
    @objc func splitRight(_ sender: Any?) { showTerminals(); main.terminalArea.split(sideBySide: true) }
    @objc func splitDown(_ sender: Any?) { showTerminals(); main.terminalArea.split(sideBySide: false) }
    @objc func closePane(_ sender: Any?) { main.terminalArea.closePane() }
    @objc func zoomPane(_ sender: Any?) { main.terminalArea.toggleZoom() }
    @objc func evenOutPanes(_ sender: Any?) { main.terminalArea.evenOut() }
    @objc func focusPaneLeft(_ sender: Any?) { main.terminalArea.moveFocus(.left) }
    @objc func focusPaneRight(_ sender: Any?) { main.terminalArea.moveFocus(.right) }
    @objc func focusPaneUp(_ sender: Any?) { main.terminalArea.moveFocus(.up) }
    @objc func focusPaneDown(_ sender: Any?) { main.terminalArea.moveFocus(.down) }
    /// Panes live in the Terminals view: leave Board, Work, the viewer and the rest first.
    private func showTerminals() { if model.viewerPath != nil || model.boardMode || model.workMode || model.launchpadMode || model.learnMode || model.objectiveId != nil { model.goTerminals() } }
    @objc func toggleCentre(_ sender: Any?) { main.toggleCentre() }
    @objc func focusTerminal(_ sender: Any?) {
        model.goTerminals()
        main.terminalArea.focusTerminal()
    }
    @objc func toggleBoard(_ sender: Any?) { model.boardMode.toggle() }
    @objc func toggleWork(_ sender: Any?) { model.workMode.toggle() }
    @objc func toggleLaunchpad(_ sender: Any?) { model.launchpadMode.toggle() }
    @objc func toggleLearn(_ sender: Any?) { model.learnMode.toggle() }
    @objc func newWorkItem(_ sender: Any?) {
        model.workMode = true
        NotificationCenter.default.post(name: .newWorkItem, object: nil)
    }

    @objc func groupBy(_ sender: NSMenuItem) {
        if let g = Grouping.allCases[safe: sender.tag] { model.grouping = g }
    }

    @objc func setTheme(_ sender: NSMenuItem) {
        // tag = panel*10 + theme index
        guard let theme = ThemeName.allCases[safe: sender.tag % 10] else { return }
        switch sender.tag / 10 {
        case 0: model.chosenThemes.sidebar = theme
        case 1: model.chosenThemes.files = theme
        case 2: model.chosenThemes.terminal = theme
        case 3: model.chosenThemes.plan = theme
        default: model.chosenThemes.centre = theme
        }
    }

    @objc func selectNext(_ sender: Any?) { moveSelection(1) }
    @objc func selectPrevious(_ sender: Any?) { moveSelection(-1) }

    private func moveSelection(_ delta: Int) {
        let flat = model.groups(in: model.active).flatMap(\.items)
        guard !flat.isEmpty else { return }
        let i = flat.firstIndex { $0.id == model.selectedId } ?? (delta > 0 ? -1 : flat.count)
        let j = min(max(i + delta, 0), flat.count - 1)
        model.selectedId = flat[j].id
    }

    @objc func launchSelected(_ sender: Any?) {
        if let item = model.selected, item.liveAgent == nil, item.status != .doNotUse { model.launch(item) }
    }

    // MARK: Menu (WINDOW_SHELL §5: every v0.1 item kept, ★ = new in v2)

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()

        let appItem = NSMenuItem(); menu.addItem(appItem)
        let app = NSMenu()
        app.addItem(withTitle: "About One Roof", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        app.addItem(.separator())
        app.addItem(item("Settings…", #selector(showSettings(_:)), ","))
        app.addItem(item("Setup…", #selector(showSetup(_:)), ""))
        app.addItem(item("Foundations…", #selector(showFoundations(_:)), "f", [.command, .shift]))
        app.addItem(item("Run Startup Check", #selector(runCheck(_:)), ""))
        app.addItem(item("Command Palette…", #selector(showPalette(_:)), "k"))
        let pp = item("Command Palette (⌘P)", #selector(showPalette(_:)), "p")
        pp.isAlternate = false; pp.isHidden = true; pp.allowsKeyEquivalentWhenHidden = true
        app.addItem(pp)
        app.addItem(.separator())
        let services = NSMenuItem(title: "Services", action: nil, keyEquivalent: "")
        services.submenu = NSMenu(title: "Services"); NSApp.servicesMenu = services.submenu
        app.addItem(services)
        app.addItem(.separator())
        app.addItem(withTitle: "Hide One Roof", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        let hideOthers = NSMenuItem(title: "Hide Others", action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
        hideOthers.keyEquivalentModifierMask = [.command, .option]
        app.addItem(hideOthers)
        app.addItem(withTitle: "Show All", action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")
        app.addItem(.separator())
        app.addItem(withTitle: "Quit One Roof", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = app

        let fileItem = NSMenuItem(); menu.addItem(fileItem)
        let file = NSMenu(title: "File")
        file.addItem(item("New Session…", #selector(newSession(_:)), "n"))
        file.addItem(item("New Terminal", #selector(newTerminal(_:)), "t"))
        file.addItem(item("New Terminal in Selected Repo", #selector(newTerminalInRepo(_:)), "t", [.command, .control]))
        file.addItem(item("New Workspace Window…", #selector(newWorkspaceWindow(_:)), "n", [.command, .shift]))
        file.addItem(item("New Roof Window for Selected Repo", #selector(newRoofWindow(_:)), "n", [.command, .option]))
        file.addItem(item("New Objective…", #selector(newObjective(_:)), "o", [.command, .shift]))
        file.addItem(item("New Work Item…", #selector(newWorkItem(_:)), "n", [.command, .control]))
        file.addItem(.separator())
        file.addItem(item("Open File…", #selector(openFile(_:)), "o"))
        file.addItem(item("Save", #selector(saveFile(_:)), "s"))
        file.addItem(.separator())
        file.addItem(item("Launch Selected Session", #selector(launchSelected(_:)), "\r"))
        file.addItem(item("Close Session…", #selector(closeSelected(_:)), "w"))
        file.addItem(item("Reopen Closed Session", #selector(reopenClosed(_:)), "t", [.command, .shift]))
        let ro2 = item("Reopen Closed Session (⌥⌘T)", #selector(reopenClosed(_:)), "t", [.command, .option])
        ro2.isHidden = true; ro2.allowsKeyEquivalentWhenHidden = true
        file.addItem(ro2)
        file.addItem(item("Open in New Window", #selector(popOut(_:)), "o", [.command, .option]))
        file.addItem(.separator())
        let cw = NSMenuItem(title: "Close Window", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        cw.keyEquivalentModifierMask = [.command, .control]
        file.addItem(cw)
        fileItem.submenu = file

        let editItem = NSMenuItem(); menu.addItem(editItem)
        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        edit.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        edit.addItem(.separator())
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        edit.addItem(.separator())
        edit.addItem(item("Clear Terminal", #selector(clearTerminal(_:)), "k", [.command, .option]))
        edit.addItem(.separator())
        edit.addItem(item("Find…", #selector(findInTerminal(_:)), "f"))
        edit.addItem(item("Find Next", #selector(findNext(_:)), "g"))
        edit.addItem(item("Find Previous", #selector(findPrevious(_:)), "g", [.command, .shift]))
        edit.addItem(item("Find in Workspace", #selector(searchWorkspace(_:)), "s", [.command, .shift]))
        edit.addItem(item("Ask Agent About Selection", #selector(askAgentAboutSelection(_:)), ""))
        editItem.submenu = edit

        let viewItem = NSMenuItem(); menu.addItem(viewItem)
        let view = NSMenu(title: "View")
        for (i, g) in Grouping.allCases.enumerated() {
            let mi = item("Group by \(g.label)", #selector(groupBy(_:)), "\(i + 1)")
            mi.tag = i
            view.addItem(mi)
        }
        view.addItem(.separator())
        for (p, panel) in ["Sessions Panel", "File Browser", "Terminal", "Plan Panel", "Centre Views"].enumerated() {
            let sub = NSMenu(title: "\(panel) Theme")
            let choices = p == 2 ? ThemeName.terminalChoices : ThemeName.panelChoices
            for theme in choices {
                let mi = item(theme.label, #selector(setTheme(_:)), "")
                mi.tag = p * 10 + (ThemeName.allCases.firstIndex(of: theme) ?? 0)
                sub.addItem(mi)
            }
            let parent = NSMenuItem(title: "\(panel) Theme", action: nil, keyEquivalent: "")
            parent.submenu = sub
            view.addItem(parent)
        }
        view.addItem(.separator())
        view.addItem(item("Overview", #selector(toggleLaunchpad(_:)), "l", [.command, .shift]))
        view.addItem(item("Resources", #selector(showResources(_:)), "u", [.command, .shift]))
        view.addItem(item("Board", #selector(toggleBoard(_:)), "b"))
        view.addItem(item("Decisions", #selector(showDecisions(_:)), "i"))
        view.addItem(item("Subagents", #selector(showSubagents(_:)), "a", [.command, .shift]))
        view.addItem(item("Learn", #selector(toggleLearn(_:)), "e", [.command, .shift]))
        view.addItem(item("Work: Projects and Roadmap", #selector(toggleWork(_:)), "w", [.command, .shift]))
        view.addItem(.separator())
        view.addItem(item("Bigger Text", #selector(textBigger(_:)), "+"))
        view.addItem(item("Smaller Text", #selector(textSmaller(_:)), "-"))
        view.addItem(item("Actual Size", #selector(textReset(_:)), "0"))
        view.addItem(.separator())
        view.addItem(item("Toggle Sidebar", #selector(toggleSidebarPanel(_:)), "s", [.command, .option]))
        view.addItem(item("Toggle Plan Panel", #selector(togglePlanPanel(_:)), "p", [.command, .option]))
        view.addItem(item("Centre Panel", #selector(toggleCentre(_:)), "c", [.command, .option]))
        view.addItem(item("File Browser", #selector(toggleFiles(_:)), "b", [.command, .option]))
        view.addItem(item("Search in Workspace", #selector(searchWorkspace(_:)), ""))
        view.addItem(item("Review Changes", #selector(reviewChanges(_:)), "r", [.command, .option]))
        view.addItem(.separator())
        // Split panes: the usual terminal-app keys.
        view.addItem(item("Split Right", #selector(splitRight(_:)), "d"))
        view.addItem(item("Split Down", #selector(splitDown(_:)), "d", [.command, .shift]))
        view.addItem(item("Close Pane", #selector(closePane(_:)), "w", [.command, .option]))
        view.addItem(item("Maximize Pane", #selector(zoomPane(_:)), "\r", [.command, .shift]))
        view.addItem(item("Even Out Panes", #selector(evenOutPanes(_:)), ""))
        for (title, key, sel) in [("Focus Pane Left", NSLeftArrowFunctionKey, #selector(focusPaneLeft(_:))),
                                  ("Focus Pane Right", NSRightArrowFunctionKey, #selector(focusPaneRight(_:))),
                                  ("Focus Pane Up", NSUpArrowFunctionKey, #selector(focusPaneUp(_:))),
                                  ("Focus Pane Down", NSDownArrowFunctionKey, #selector(focusPaneDown(_:)))] {
            view.addItem(item(title, sel, String(Character(UnicodeScalar(key)!)), [.command, .option]))
        }
        view.addItem(.separator())
        view.addItem(item("Focus: Terminal Only", #selector(toggleFocus(_:)), "f", [.command, .option]))
        view.addItem(item("Focus Terminal", #selector(focusTerminal(_:)), "l"))
        view.addItem(item("Raw Stream / Run", #selector(toggleRawStream(_:)), "r"))
        view.addItem(item("Debug", #selector(debugFile(_:)), "r", [.command, .shift]))
        viewItem.submenu = view

        let sessItem = NSMenuItem(); menu.addItem(sessItem)
        let sess = NSMenu(title: "Session")
        sess.addItem(item("Launch", #selector(launchSelected(_:)), ""))
        sess.addItem(item("Mark as Next", #selector(markNext(_:)), ""))
        sess.addItem(item("Mark as Planned", #selector(markPlanned(_:)), ""))
        sess.addItem(item("Do Not Use", #selector(markDoNotUse(_:)), ""))
        sess.addItem(item("Pin", #selector(togglePinSelected(_:)), ""))
        sess.addItem(item("Rename…", #selector(renameSelected(_:)), ""))
        let mv = NSMenuItem(title: "Move to Window", action: nil, keyEquivalent: "")
        mv.submenu = NSMenu(title: "Move to Window")
        mv.submenu?.delegate = moveMenu
        sess.addItem(mv)
        sess.addItem(.separator())
        let sch = NSMenuItem(title: "Schedule", action: nil, keyEquivalent: "")
        let schm = NSMenu(title: "Schedule")
        schm.addItem(item("Tonight 2:00 AM", #selector(scheduleTonight(_:)), ""))
        schm.addItem(item("Nightly at 2:00 AM", #selector(scheduleNightly(_:)), ""))
        schm.addItem(item("On Demand", #selector(scheduleOff(_:)), ""))
        sch.submenu = schm
        sess.addItem(sch)
        sess.addItem(item("Run Now", #selector(launchSelected(_:)), ""))
        sess.addItem(item("Interrupt", #selector(interruptSelected(_:)), "."))
        sess.addItem(item("Send Handoff", #selector(sendHandoff(_:)), ""))
        sess.addItem(.separator())
        sess.addItem(item("Open in New Window", #selector(popOut(_:)), ""))
        sess.addItem(item("Open Repo in Finder", #selector(openRepo(_:)), ""))
        sess.addItem(item("Copy session id", #selector(copySessionId(_:)), ""))
        sess.addItem(item("Copy Working Directory", #selector(copyCwd(_:)), ""))
        sess.addItem(item("Copy Attach Command", #selector(copyAttach(_:)), ""))
        sess.addItem(item("Copy Link to Session", #selector(copyLink(_:)), ""))
        sess.addItem(.separator())
        sess.addItem(item("Close Agent…", #selector(closeSelected(_:)), ""))
        sess.addItem(item("Delete Session", #selector(deleteSelected(_:)), ""))
        sess.addItem(item("Remove Exited Sessions…", #selector(removeExited(_:)), ""))
        sess.addItem(.separator())
        sess.addItem(item("Next Session", #selector(selectNext(_:)), "]"))
        sess.addItem(item("Previous Session", #selector(selectPrevious(_:)), "["))
        sessItem.submenu = sess

        let winItem = NSMenuItem(); menu.addItem(winItem)
        let win = NSMenu(title: "Window")
        win.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        win.addItem(withTitle: "Zoom", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
        win.addItem(.separator())
        win.addItem(item("All Windows", #selector(toggleLaunchpad(_:)), String(Character(UnicodeScalar(NSUpArrowFunctionKey)!)), [.control]))
        let wsList = NSMenuItem(title: "Workspaces", action: nil, keyEquivalent: "")
        wsList.submenu = NSMenu(title: "Workspaces")
        wsList.submenu?.delegate = workspaceMenu
        win.addItem(wsList)
        for n in 1...9 {
            let w = item("Workspace \(n)", #selector(goToWorkspace(_:)), "\(n)", [.command, .option])
            w.tag = n; w.isHidden = true; w.allowsKeyEquivalentWhenHidden = true
            win.addItem(w)
        }
        let roofs = NSMenuItem(title: "Roof Windows", action: nil, keyEquivalent: "")
        roofs.submenu = NSMenu(title: "Roof Windows")
        roofs.submenu?.delegate = roofMenu
        win.addItem(roofs)
        win.addItem(item("Foundations", #selector(showFoundations(_:)), ""))
        win.addItem(.separator())
        win.addItem(withTitle: "Bring All to Front", action: #selector(NSApplication.arrangeInFront(_:)), keyEquivalent: "")
        winItem.submenu = win
        NSApp.windowsMenu = win

        let helpItem = NSMenuItem(); menu.addItem(helpItem)
        let help = NSMenu(title: "Help")
        help.addItem(item("One Roof Help", #selector(openHelp(_:)), ""))
        help.addItem(item("How Do I…?", #selector(howDoI(_:)), "/", [.command, .option]))
        help.addItem(item("Keyboard Shortcuts", #selector(showShortcuts(_:)), ""))
        help.addItem(item("Release Notes", #selector(openReleaseNotes(_:)), ""))
        help.addItem(.separator())
        help.addItem(item("One Roof README", #selector(openReadme(_:)), ""))
        help.addItem(item("Help Pages Folder", #selector(openDocs(_:)), ""))
        helpItem.submenu = help
        NSApp.helpMenu = help
        return menu
    }

    private func item(_ title: String, _ action: Selector, _ key: String, _ mods: NSEvent.ModifierFlags = [.command]) -> NSMenuItem {
        let mi = NSMenuItem(title: title, action: action, keyEquivalent: key)
        mi.keyEquivalentModifierMask = mods
        mi.target = self
        return mi
    }
}

extension AppDelegate: NSMenuItemValidation {
    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        switch item.action {
        case #selector(toggleBoard(_:)):
            item.state = model.boardMode ? .on : .off
        case #selector(toggleLearn(_:)):
            item.state = model.learnMode ? .on : .off
        case #selector(toggleLaunchpad(_:)):
            item.state = model.launchpadMode ? .on : .off
        case #selector(toggleWork(_:)):
            item.state = model.workMode ? .on : .off
        case #selector(showDecisions(_:)):
            item.state = model.centre == .decisions ? .on : .off
        case #selector(showResources(_:)):
            item.state = model.centre == .resources ? .on : .off
        case #selector(showSubagents(_:)):
            item.state = model.centre == .subagents ? .on : .off
        case #selector(togglePinSelected(_:)):
            item.title = model.selected?.session.pinned == true ? "Unpin" : "Pin"
            return model.selected != nil
        case #selector(renameSelected(_:)), #selector(scheduleTonight(_:)), #selector(scheduleNightly(_:)), #selector(scheduleOff(_:)):
            return model.selected != nil
        case #selector(interruptSelected(_:)), #selector(sendHandoff(_:)), #selector(copySessionId(_:)):
            return model.selected?.liveAgent != nil
        case #selector(reviewChanges(_:)):
            return GitDiff.repoRoot(for: model.selected?.session.repoPath ?? Workspace.projectsRoot) != nil
        case #selector(debugFile(_:)):
            return model.centre == .editor
        case #selector(goToWorkspace(_:)):
            return model.windows.count >= item.tag
        case #selector(groupBy(_:)):
            item.state = Grouping.allCases[safe: item.tag] == model.grouping ? .on : .off
        case #selector(setTheme(_:)):
            let current: ThemeName
            switch item.tag / 10 {
            case 0: current = model.themes.sidebar
            case 1: current = model.themes.files
            case 2: current = model.themes.terminal
            case 3: current = model.themes.plan
            default: current = model.themes.centre
            }
            item.state = ThemeName.allCases[safe: item.tag % 10] == current ? .on : .off
        case #selector(launchSelected(_:)):
            return model.selected.map { $0.liveAgent == nil && $0.status != .doNotUse } ?? false
        case #selector(markNext(_:)), #selector(markPlanned(_:)):
            return model.selected.map { !$0.status.isLive } ?? false
        case #selector(markDoNotUse(_:)):
            item.state = model.selected?.status == .doNotUse ? .on : .off
            return model.selected != nil
        case #selector(closeSelected(_:)), #selector(copyAttach(_:)), #selector(popOut(_:)):
            return model.selected?.liveAgent != nil
        case #selector(copyLink(_:)):
            return model.selected != nil
        case #selector(deleteSelected(_:)):
            return model.selected.map { !$0.adopted } ?? false
        case #selector(removeExited(_:)):
            return model.items.contains { $0.status == .exited && !$0.session.pinned && !$0.adopted }
        case #selector(openRepo(_:)), #selector(newTerminalInRepo(_:)), #selector(copyCwd(_:)), #selector(newRoofWindow(_:)):
            return model.selected != nil
        default: break
        }
        return true
    }
}

extension Array {
    subscript(safe i: Int) -> Element? { indices.contains(i) ? self[i] : nil }
}

/// Session › Move to Window: every workspace window.
final class MoveMenu: NSObject, NSMenuDelegate {
    private let model: AppModel
    init(model: AppModel) { self.model = model }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        guard let sel = model.selected else { menu.addItem(withTitle: "No session selected", action: nil, keyEquivalent: ""); return }
        let here = model.workspaceId(of: sel)
        for w in model.windows {
            let mi = NSMenuItem(title: w.name, action: w.id == here ? nil : #selector(move(_:)), keyEquivalent: "")
            mi.target = self
            mi.representedObject = w.id
            mi.state = w.id == here ? .on : .off
            menu.addItem(mi)
        }
    }

    @objc private func move(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String, let w = model.window(id), let sel = model.selected else { return }
        model.move(sel, to: w)
    }
}

/// Window › Workspaces: every workspace with ⌥⌘1–9, open or closed.
final class WorkspaceListMenu: NSObject, NSMenuDelegate {
    private weak var app: AppDelegate?
    init(app: AppDelegate) { self.app = app }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        guard let app else { return }
        for (i, r) in WorkspaceStore.shared.workspaces.enumerated() {
            let mi = NSMenuItem(title: r.name + (r.open ? "" : " (closed)"), action: #selector(open(_:)), keyEquivalent: i < 9 ? "\(i + 1)" : "")
            mi.keyEquivalentModifierMask = [.command, .option]
            mi.target = self
            mi.representedObject = r.id
            mi.state = app.model.activeWindowId == r.id ? .on : .off
            menu.addItem(mi)
        }
        menu.addItem(.separator())
        let n = NSMenuItem(title: "New Workspace Window…", action: #selector(AppDelegate.newWorkspaceWindow(_:)), keyEquivalent: "")
        n.target = app
        menu.addItem(n)
    }

    @objc private func open(_ sender: NSMenuItem) {
        guard let app, let id = sender.representedObject as? String, let r = WorkspaceStore.shared.workspaces.first(where: { $0.id == id }) else { return }
        let w = app.model.window(id) ?? WindowState(id: r.id, name: r.name, colour: r.colour)
        app.openWindow(for: w)
    }
}

/// Window › Roof Windows: one item per repo and workstream with live sessions, rebuilt each time it opens.
final class RoofMenu: NSObject, NSMenuDelegate {
    private let model: AppModel
    init(model: AppModel) { self.model = model }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let all = RoofScope.available(in: model.items)
        if all.isEmpty { menu.addItem(withTitle: "No live sessions", action: nil, keyEquivalent: ""); return }
        var lastWasRepo = true
        for r in all {
            if case .workstream = r.scope, lastWasRepo { menu.addItem(.separator()); lastWasRepo = false }
            let mi = NSMenuItem(title: "\(r.scope.title)  (\(r.count))", action: #selector(open(_:)), keyEquivalent: "")
            mi.target = self
            mi.representedObject = r.scope
            mi.state = RoofWindowController.open[r.scope] != nil ? .on : .off
            menu.addItem(mi)
        }
    }

    @objc private func open(_ sender: NSMenuItem) {
        if let s = sender.representedObject as? RoofScope { RoofWindowController.show(s, model: model) }
    }
}
