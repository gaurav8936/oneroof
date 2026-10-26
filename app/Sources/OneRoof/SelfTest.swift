import AppKit
import SwiftUI
import OneRoofCore

/// In-process checks driven by environment variables, so tests never send keystrokes system-wide.
///   ONEROOF_SELFTEST_UI2=1 · LOOK=<look> · PLACE=<place> · FOCUS=<0-3> · LAYOUT=<single|grid|wall>   v2 window (1.x)
///   ONEROOF_SELFTEST_SELECT=<session id>      select that agent's row after launch
///   ONEROOF_SELFTEST_TYPE=<text>                type text (+ Return) into the focused terminal via synthetic NSEvents
///   ONEROOF_SELFTEST_THEMES=sidebar,terminal,plan   e.g. "light,dark,dim"
///   ONEROOF_SELFTEST_TERMINAL=1                 open a plain terminal (File › New Terminal)
///   ONEROOF_SELFTEST_COPYTEST=1                 after TYPE: drag across the focused terminal with mouse events, Copy,
///                                               and write <out>.copytest.txt (mouse captured? clipboard text)
///   ONEROOF_SELFTEST_SETTINGS=1                 open the Settings window (snapshotted as an extra PNG)
///   ONEROOF_SELFTEST_MENU=<Menu>/<Item>         invoke a menu item by title, e.g. "Session/Mark as Next"
///   ONEROOF_SELFTEST_SPLIT=right,term,down,term  split panes and fill them with plain terminals
///   ONEROOF_SELFTEST_SHORTCUT=<title>=<keys>   override a menu shortcut; ONEROOF_SELFTEST_SETTINGS_TAB=4 opens Shortcuts
///   ONEROOF_SELFTEST_LINK=<oneroof:// url>       follow a link as if macOS had opened it
///   ONEROOF_SELFTEST_SEARCH=<text>              open Search in Workspace with that query
///   ONEROOF_SELFTEST_DIFF=<path>                open the code review panel for the repo containing <path>
///   ONEROOF_SELFTEST_HOWDOI=<question>         ask Learn "how do I…" (opens the best page)
///   ONEROOF_SELFTEST_PLAY=<page title>[@terminals]  play that Learn page's narration (then show the terminals)
///   ONEROOF_SELFTEST_CENTRE_AFTER=<view>        switch the centre view after TYPE (decisions, board, review …)
///   ONEROOF_SELFTEST_KIND=session|ticket|defect|workstream   ONEROOF_SELFTEST_TEAM=<key>   ONEROOF_SELFTEST_PROJECT=<code>   New session sheet starting state
///   ONEROOF_SELFTEST_PICK=KEY,KEY,…   tick those issues (LAB-518)   ONEROOF_SELFTEST_ISSUES=1   open the issue checklist
///   ONEROOF_SELFTEST_OPENING=<text>             the owner's own opening message, typed before the picks (LAB-528)
///   ONEROOF_SELFTEST_ROOF=<n>                   start n plain terminals in One Roof's source checkout (or
///                                               ONEROOF_SELFTEST_ROOF_REPO), then open its roof window
enum SelfTest {
    static var isActive: Bool { ProcessInfo.processInfo.environment.keys.contains { $0.hasPrefix("ONEROOF_SELFTEST_") } }

    static func runIfRequested(app: AppDelegate) {
        let env = ProcessInfo.processInfo.environment
        if let script = env["ONEROOF_SELFTEST_SCRIPT"] { SelfTestScript.run(script, app: app); return }
        if env["ONEROOF_SELFTEST_STICKERS"] == "soft" { app.model.settings.stickerStyle = "soft" }
        // v2: ONEROOF_SELFTEST_CENTRE=<overview|resources|board|decisions|subagents|work|learn|editor|review>, TEXTSIZE=<0.85…1.3>.
        // ONEROOF_SELFTEST_PLANTAB=<plan|ticket|notes|artifacts|resources> opens that plan panel tab (PlanPanelView).
        if let c = env["ONEROOF_SELFTEST_CENTRE"], let v = CentreView(rawValue: c) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { app.model.show(v) }
        }
        if let ts = Double(env["ONEROOF_SELFTEST_TEXTSIZE"] ?? "") { app.model.active.setTextScale(ts) }
        // P6 (v2): ONEROOF_SELFTEST_PLACE=<home|needsYou|sessions|work|machine|loops|learn>, ONEROOF_SELFTEST_FOCUS=<0-3>,
        // ONEROOF_SELFTEST_LAYOUT=<single|grid|wall>. Place first (it sets its default step), then the step.
        if app.model.settings.ui2, let p = env["ONEROOF_SELFTEST_PLACE"], let place = Place(rawValue: p) { app.model.active.open(place) }
        if let l = env["ONEROOF_SELFTEST_LAYOUT"], let layout = SessionLayout(rawValue: l) { app.model.active.layout = layout }
        if let f = Int(env["ONEROOF_SELFTEST_FOCUS"] ?? ""), let step = FocusStep(rawValue: f) { app.model.active.focusStep = step }
        // SELECTFIRST=1 selects the window's first session (demo ids are random) so the Plan and session tabs have one.
        if env["ONEROOF_SELFTEST_SELECTFIRST"] == "1" {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                if let first = app.model.items(in: app.model.active).first { app.model.active.selectedId = first.id }
            }
        }
        // V2PLAN=1 slides the Plan over the terminal (C7.1); V2EDGE=1 reveals the session column at Focus (C7.2).
        if env["ONEROOF_SELFTEST_V2PLAN"] == "1" { DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { app.main.v2ShowPlanOverlay() } }
        if env["ONEROOF_SELFTEST_V2EDGE"] == "1" { DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { app.main.v2ShowEdgeReveal() } }
        if env["ONEROOF_SELFTEST_DEMO"] == "1" { seedDemo(app.model) }
        if env["ONEROOF_SELFTEST_FOUNDATIONS"] == "1" { DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { app.showFoundations(nil) } }
        if let w = env["ONEROOF_SELFTEST_WORK"] {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { app.model.workMode = true; app.model.loadWorkstreams() }
            if w != "1" {   // a WS id: select it once loaded
                DispatchQueue.main.asyncAfter(deadline: .now() + 4.0) {
                    if let ws = app.model.workstreams.first(where: { $0.wsId == w }) { workSelect = ws.id; app.model.loadIssues(ws) }
                }
            }
        }
        // ONEROOF_SELFTEST_TICKET=WS-ID/ENG-123: plan a session for that ticket and move it to In Progress.
        if let spec = env["ONEROOF_SELFTEST_TICKET"], let slash = spec.firstIndex(of: "/") {
            let wsId = String(spec[..<slash]), key = String(spec[spec.index(after: slash)...])
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { app.model.loadWorkstreams() }
            DispatchQueue.main.asyncAfter(deadline: .now() + 4.0) {
                if let ws = app.model.workstreams.first(where: { $0.wsId == wsId }) { app.model.loadIssues(ws) }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 7.0) {
                guard let ws = app.model.workstreams.first(where: { $0.wsId == wsId }),
                      let issue = app.model.issues[ws.id]?.first(where: { $0.identifier == key }) else {
                    FileHandle.standardError.write("selftest ticket: workstreams=\(app.model.workstreams.count) issues=\(app.model.issues.mapValues(\.count)) err=\(app.model.linearError ?? "-")\n".data(using: .utf8)!)
                    return
                }
                let s = app.model.planSession(for: issue, in: ws)
                app.model.moveTicket(of: s, to: "In Progress")
            }
        }
        // ONEROOF_SELFTEST_OBJECTIVE="title|done when|repo[|workstream]": create an objective and start its planner.
        if let spec = env["ONEROOF_SELFTEST_OBJECTIVE"] {
            let f = spec.components(separatedBy: "|")
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                if let existing = app.model.objectives.first(where: { $0.title == f[0] }) {
                    app.model.objectiveId = existing.id
                    if env["ONEROOF_SELFTEST_APPROVE"] == "1" { app.model.approve(existing) }
                    return
                }
                let o = Objective(title: f[0], doneWhen: f.count > 1 ? f[1] : "", repoPath: f.count > 2 ? f[2] : Workspace.projectsRoot,
                                  workstream: f.count > 3 && !f[3].isEmpty ? f[3] : nil, budget: "light")
                app.model.createObjective(o, planNow: true)
            }
        }
        if env["ONEROOF_SELFTEST_INTAKE"] != nil {
            DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) { NotificationCenter.default.post(name: .newWorkItem, object: nil) }
        }
        if env["ONEROOF_SELFTEST_LAUNCHPAD"] == "1" { DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { app.model.launchpadMode = true } }
        if env["ONEROOF_SELFTEST_FILES"] == "1" { DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { app.main.toggleFiles() } }
        if let l = env["ONEROOF_SELFTEST_LEARN"] {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                if l != "1" { app.model.learnTarget = l }
                app.model.learnMode = true
            }
        }
        if let v = env["ONEROOF_SELFTEST_VIEW"] {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { app.model.openInViewer(v, line: Int(env["ONEROOF_SELFTEST_LINE"] ?? "")) }
        }
        if env["ONEROOF_SELFTEST_NOCENTRE"] == "1" { DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { app.main.toggleCentre() } }
        // ONEROOF_SELFTEST_SPLIT="right,term,down,term": split panes, opening a plain terminal where it says "term".
        if let spec = env["ONEROOF_SELFTEST_SPLIT"] {
            for (n, step) in spec.split(separator: ",").enumerated() {
                DispatchQueue.main.asyncAfter(deadline: .now() + 3.0 + Double(n) * 2.5) {
                    switch step {
                    case "right": app.main.terminalArea.split(sideBySide: true)
                    case "down": app.main.terminalArea.split(sideBySide: false)
                    case "term": app.model.newTerminal()
                    case "zoom": app.main.terminalArea.toggleZoom()
                    case "close": app.main.terminalArea.closePane()
                    case "closeagent": if let i = app.model.selected { app.model.closeAgent(i) }
                    case "reopen": app.model.reopenClosed()
                    default: break
                    }
                }
            }
        }
        // ONEROOF_SELFTEST_SHORTCUT="Split Right=⌃⌘D": override one menu shortcut (never saved in a test).
        if let spec = env["ONEROOF_SELFTEST_SHORTCUT"], let eq = spec.firstIndex(of: "=") {
            app.model.settings.shortcuts[String(spec[..<eq])] = String(spec[spec.index(after: eq)...])
        }
        if let l = env["ONEROOF_SELFTEST_LINK"], let u = URL(string: l) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { app.application(NSApp, open: [u]) }
        }
        if let q = env["ONEROOF_SELFTEST_SEARCH"] { DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { app.model.openSearch(q) } }
        if let d = env["ONEROOF_SELFTEST_DIFF"] { DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { app.model.openDiff(d) } }
        if let spec = env["ONEROOF_SELFTEST_PLAY"] {
            let title = spec.components(separatedBy: "@")[0]
            app.model.loadLearn()
            app.model.learnMode = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                guard let it = app.model.learnItems.first(where: { $0.title == title }) else { return }
                app.model.learnTarget = it.id
                app.model.player.rate = 1.5
                app.model.player.play(pageId: it.id, title: it.title, tracks: it.tracks())
                if spec.hasSuffix("@terminals") { DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { app.model.goTerminals() } }
            }
        }
        if let q = env["ONEROOF_SELFTEST_HOWDOI"] { DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { app.model.howDoI(q) } }
        if let n = Int(env["ONEROOF_SELFTEST_ROOF"] ?? "") {
            let repo = env["ONEROOF_SELFTEST_ROOF_REPO"] ?? AppResources.sourceCheckout
            for k in 0..<n { DispatchQueue.main.asyncAfter(deadline: .now() + 1.5 + Double(k) * 0.6) { app.model.newTerminal(in: repo) } }
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0 + Double(n) * 0.6 + 3.0) {
                RoofWindowController.show(.repo(repo), model: app.model)
                app.main.window?.orderFront(nil)
                // ONEROOF_SELFTEST_ROOF_BACK=1: hand the selected (last) terminal back to the main window.
                if env["ONEROOF_SELFTEST_ROOF_BACK"] == "1", let a = app.model.selected?.liveAgent {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { PopOutWindowController.bringBack(a) }
                }
            }
        }
        if env["ONEROOF_SELFTEST_POPOUT"] == "1" {
            DispatchQueue.main.asyncAfter(deadline: .now() + 6.0) {
                if let i = app.model.items.first(where: { $0.session.agent == .shell && $0.liveAgent != nil && !$0.adopted }) {
                    app.model.selectedId = i.id
                    PopOutWindowController.popOut(i, model: app.model)
                }
            }
        }
        if let q = env["ONEROOF_SELFTEST_FIND"] {
            DispatchQueue.main.asyncAfter(deadline: .now() + 7.3) {
                app.main.terminalArea.showFind()
                app.main.terminalArea.terminalAction("search:" + q)
            }
        }
        if env["ONEROOF_SELFTEST_PALETTE"] == "1" { DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { app.showPalette(nil) } }
        if env["ONEROOF_SELFTEST_BOARD"] == "1" { DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { app.model.boardMode = true } }
        if env["ONEROOF_SELFTEST_POPOVER"] == "1" {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                guard let item = app.model.items.first(where: { !$0.session.tags.isEmpty }) ?? app.model.items.first else { return }
                let host = NSHostingController(rootView: SessionPopover(item: item, model: app.model, close: {}, rename: {})
                    .environment(\.colorScheme, app.model.themes.sidebar.colorScheme)
                    .background(app.model.themes.sidebar.tokens.background.color))
                let w = NSWindow(contentViewController: host)
                w.title = "Session menu"
                w.orderBack(nil)
                popoverWindow = w
            }
        }
        if env["ONEROOF_SELFTEST_TERMINAL"] == "1" {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { app.model.newTerminal() }
        }
        // A sticker on a terminal row sticks (owner 10-18).
        if env["ONEROOF_SELFTEST_TERMSTICKER"] == "1" {
            DispatchQueue.main.asyncAfter(deadline: .now() + 6) {
                let out = (env["ONEROOF_SELFTEST_OUT"] ?? "/tmp/oneroof") + ".termsticker.txt"
                guard let t = app.model.items.first(where: { $0.session.agent == .shell }) else {
                    try? "no terminal".write(toFile: out, atomically: true, encoding: .utf8); return
                }
                app.model.selectedId = t.id
                app.model.toggleSticker(t, "wip")
                if let fresh = app.model.item(t.id) { app.model.setColor(fresh, "mint") }
                let after = app.model.item(t.id)
                try? "status=\(t.status) tags=\(after?.session.tags ?? []) color=\(after?.session.color ?? "nil")"
                    .write(toFile: out, atomically: true, encoding: .utf8)
            }
        }
        // PAGE=help / notes opens the v2 Help or Release notes page (B4.1, B4.2).
        if let pg = env["ONEROOF_SELFTEST_PAGE"], app.model.settings.ui2 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { app.main.v2ShowPage(pg == "notes" ? "Release notes" : "Help") }
        }
        if env["ONEROOF_SELFTEST_SETTINGS"] == "1" {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                app.showSettings(nil)
                app.settingsWindow?.window?.orderBack(nil)
            }
        }
        if let t = env["ONEROOF_SELFTEST_THEMES"] {
            let p = t.split(separator: ",").compactMap { ThemeName(stored: String($0)) }
            if p.count == 3 { app.model.chosenThemes = PanelThemes(sidebar: p[0], terminal: p[1], plan: p[2]) }
            if p.count == 4 { app.model.chosenThemes = PanelThemes(sidebar: p[0], files: p[1], terminal: p[2], plan: p[3]) }
            if p.count == 5 { app.model.chosenThemes = PanelThemes(sidebar: p[0], files: p[1], terminal: p[2], plan: p[3], centre: p[4]) }
            // One theme everywhere: ONEROOF_SELFTEST_THEMES=graphite
            if p.count == 1 { app.model.chosenThemes = PanelThemes(sidebar: p[0], files: p[0], terminal: p[0], plan: p[0], centre: p[0]) }
        }
        if let g = env["ONEROOF_SELFTEST_GROUP"], let grouping = Grouping(rawValue: g) {
            app.model.grouping = grouping
        }
        // ONEROOF_SELFTEST_PLAN="name|agent|account|repo|opening|launch(0/1)[|model]"
        if let plan = env["ONEROOF_SELFTEST_PLAN"] {
            let f = plan.components(separatedBy: "|")
            if f.count >= 6, let agent = AgentKind(rawValue: f[1]) {
                let s = Session(name: f[0], agent: agent, account: f[2].isEmpty ? nil : f[2], repoPath: f[3],
                                workstream: Workspace.workstream(in: f[0]), openingMessage: f[4], lifecycle: .next,
                                model: f.count > 6 && !f[6].isEmpty ? f[6] : nil)
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { app.model.createPlanned(s, launchNow: f[5] == "1") }
            }
        }
        if env["ONEROOF_SELFTEST_SHEET"] == "1" {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { app.main.newSession() }
        }
        // SHEET=objective / workitem opens New objective (⇧⌘O) / New work item (⌃⌘N) instead.
        if env["ONEROOF_SELFTEST_SHEET"] == "objective" { DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { app.main.newObjective() } }
        if env["ONEROOF_SELFTEST_SHEET"] == "workitem" { DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { app.newWorkItem(nil) } }
        let out = env["ONEROOF_SELFTEST_OUT"]
        let target = env["ONEROOF_SELFTEST_SELECT"]
        let wait = Double(env["ONEROOF_SELFTEST_WAIT"] ?? "") ?? 2.5
        DispatchQueue.main.asyncAfter(deadline: .now() + wait) {
            if let target, let item = app.model.items.first(where: { $0.liveAgent == target || $0.session.name == target }) {
                app.model.selectedId = item.id
            }
            if env["ONEROOF_SELFTEST_LAUNCH"] == "1", let item = app.model.selected { app.model.launch(item) }
            if let path = env["ONEROOF_SELFTEST_MENU"] { invokeMenu(path) }
            DispatchQueue.main.asyncAfter(deadline: .now() + (env["ONEROOF_SELFTEST_LAUNCH"] == "1" ? 20 : 2)) {
                if let text = env["ONEROOF_SELFTEST_TYPE"] {
                    app.main.terminalArea.focusTerminal()
                    type(text + "\r", into: app.main.window)
                }
                // ONEROOF_SELFTEST_CENTRE_AFTER=<view>: switch the centre view after typing (e.g. decisions, once a
                // typed agent is waiting on a prompt).
                let after = env["ONEROOF_SELFTEST_CENTRE_AFTER"].flatMap(CentreView.init(rawValue:))
                if let after { DispatchQueue.main.asyncAfter(deadline: .now() + 6) { app.model.show(after) } }
                // Snapshot after the terminal has had time to draw.
                DispatchQueue.main.asyncAfter(deadline: .now() + (after == nil ? 2.5 : 9)) {
                    guard let out else { return }
                    if env["ONEROOF_SELFTEST_COPYTEST"] == "1" { copyTest(app: app, to: out) }
                    snapshot(app: app, to: out)
                    if env["ONEROOF_SELFTEST_QUIT"] == "1" {
                        // AppKit refuses to quit while a sheet is attached.
                        if let w = app.main.window, let sheet = w.attachedSheet { w.endSheet(sheet) }
                        NSApp.terminate(nil)
                    }
                }
            }
        }
    }

    /// Select by dragging across the focused terminal (as a person would), then Edit › Copy, and record the result.
    static func copyTest(app: AppDelegate, to out: String) {
        func all(_ v: NSView) -> [TerminalSurfaceView] {
            (v as? TerminalSurfaceView).map { [$0] } ?? v.subviews.flatMap(all)
        }
        guard let w = app.main.window, let root = w.contentView,
              let view = all(root).first(where: { w.firstResponder === $0 }) ?? all(root).first(where: { !$0.isHiddenOrHasHiddenAncestor }) else {
            try? "no focused terminal".write(toFile: out + ".copytest.txt", atomically: true, encoding: .utf8); return
        }
        let captured = view.mouseCaptured
        // The owner's clipboard comes back afterwards.
        let saved = (NSPasteboard.general.pasteboardItems ?? []).map { item in
            item.types.compactMap { t in item.data(forType: t).map { (t, $0) } }
        }
        defer {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.writeObjects(saved.map { pairs in
                let it = NSPasteboardItem(); for (t, d) in pairs { it.setData(d, forType: t) }; return it
            })
        }
        NSPasteboard.general.clearContents()
        let r = view.convert(view.bounds, to: nil)
        func ev(_ t: NSEvent.EventType, _ p: NSPoint, clicks: Int = 1) -> NSEvent {
            NSEvent.mouseEvent(with: t, location: p, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                               windowNumber: w.windowNumber, context: nil, eventNumber: 0, clickCount: clicks, pressure: 1)!
        }
        let start = NSPoint(x: r.minX + 4, y: r.maxY - 4), end = NSPoint(x: r.maxX - 4, y: r.minY + 4)
        view.mouseDown(with: ev(.leftMouseDown, start))
        for k in 1...8 {
            let f = CGFloat(k) / 8
            view.mouseDragged(with: ev(.leftMouseDragged, NSPoint(x: start.x + (end.x - start.x) * f, y: start.y + (end.y - start.y) * f)))
        }
        view.mouseUp(with: ev(.leftMouseUp, end))
        let selected = view.hasSelection
        view.copy(nil)
        let clip = NSPasteboard.general.string(forType: .string) ?? ""
        // Paste: Edit › Paste must type the clipboard into the program.
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString("ONEROOF-PASTE-OK", forType: .string)
        view.paste(nil)
        RunLoop.current.run(until: Date().addingTimeInterval(1.5))
        let pasted = (app.main.terminalArea.visibleText() ?? "").contains("ONEROOF-PASTE-OK")
        // Image paste (owner 10-20): a screenshot on the clipboard types the saved PNG's path.
        NSPasteboard.general.clearContents()
        if let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 4, pixelsHigh: 4, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                      isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
           let png = rep.representation(using: .png, properties: [:]) {
            NSPasteboard.general.setData(png, forType: .png)
        }
        view.paste(nil)
        RunLoop.current.run(until: Date().addingTimeInterval(1.5))
        let imagePasted = (app.main.terminalArea.visibleText() ?? "").contains("OneRoof/pastes/paste-")
        let report = "mouse captured by the program: \(captured)\nselection after drag: \(selected)\npaste reached the terminal: \(pasted)\nimage paste typed its path: \(imagePasted)\nclipboard after copy (\(clip.count) chars):\n\(clip)"
        try? report.write(toFile: out + ".copytest.txt", atomically: true, encoding: .utf8)
    }

    /// Write <out>.png (the window drawn in-process; works with the screen locked), <out>.txt (visible
    /// terminal text read from libghostty) and <out>.json (sidebar rows).
    static func snapshot(app: AppDelegate, to out: String) {
        if let view = app.main.window?.contentView?.superview ?? app.main.window?.contentView, let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
            view.cacheDisplay(in: view.bounds, to: rep)
            try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: out + ".png"))
        }
        for (i, w) in NSApp.windows.enumerated() where w !== app.main.window && w.isVisible {
            if let v = w.contentView, let rep = v.bitmapImageRepForCachingDisplay(in: v.bounds) {
                v.cacheDisplay(in: v.bounds, to: rep)
                try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: out + "-window\(i).png"))
            }
        }
        let text = app.main.terminalArea.visibleText() ?? "(no terminal)"
        try? text.write(toFile: out + ".txt", atomically: true, encoding: .utf8)
        let rows = app.model.items.map { i -> [String: String] in
            ["name": i.session.name, "status": i.status.rawValue, "agent": i.session.agent.rawValue,
             "account": i.account ?? "", "repo": i.repoLabel, "workstream": i.session.workstream ?? "",
             "live": i.liveAgent ?? "", "adopted": i.adopted ? "yes" : "no"]
        }
        let meta: [String: Any] = ["rows": rows, "runtime": app.model.runtimeState, "selected": app.model.selectedId ?? "",
                                   "firstResponder": app.main.window?.firstResponder.map { String(describing: Swift.type(of: $0)) } ?? "-",
                                   "themes": [app.model.themes.sidebar.rawValue, app.model.themes.terminal.rawValue, app.model.themes.plan.rawValue],
                                   "grouping": app.model.grouping.rawValue, "error": app.model.lastError ?? "",
                                   "conversations": { () -> String in
                                       let t0 = Date()
                                       let list = ConversationIndex.recent(in: ConversationIndex.folder(forLaunchDirectory: Workspace.projectsRoot))
                                       return "\(list.count) in \(Int(Date().timeIntervalSince(t0) * 1000)) ms; newest: \(list.first?.title ?? "-")"
                                   }(),
                                   "menus": menuMap(),
                                   "player": { () -> String in
                                       let p = app.model.player
                                       return p.pageId == nil ? "-" : "\(p.pageTitle) part \(p.index + 1)/\(p.tracks.count) at \(String(format: "%.1f", p.elapsed))s of \(String(format: "%.1f", p.duration))s, playing=\(p.playing), rate=\(p.rate)"
                                   }(),
                                   "windows": NSApp.windows.map { "\($0.className) visible=\($0.isVisible) sheet=\($0.isSheet) \(Int($0.frame.width))x\(Int($0.frame.height))" }]
        if let d = try? JSONSerialization.data(withJSONObject: meta, options: [.prettyPrinted, .sortedKeys]) {
            try? d.write(to: URL(fileURLWithPath: out + ".json"))
        }
    }

    static var popoverWindow: NSWindow?
    /// Work view selection requested by a self-test (read by WorkView).
    static var workSelect: String?

    /// A varied set of planned sessions (never launched) to show stickers, colours, icons and pins.
    static func seedDemo(_ model: AppModel) {
        // Demo screenshots never read the author's Linear: Work shows its "Connect Linear" state.
        model.linear = LinearClient(key: nil)
        let r = Workspace.projectsRoot
        let second = AccountResolver.claudeAccounts().last ?? "Claude1"
        let demo: [Session] = [
            Session(name: "Checkout page stickers", agent: .claude, account: second, repoPath: r + "/acme/web", workstream: "WEB-12",
                    tags: ["wip", "important"], lifecycle: .planned, color: "blue", pinned: true),
            Session(name: "Help map as a tree", agent: .codex, repoPath: r + "/docs-site", workstream: "DOCS-4",
                    tags: ["review"], lifecycle: .next, icon: "🎨"),
            Session(name: "Nightly usage export", agent: .kimi, repoPath: r + "/acme/api", workstream: "API-7",
                    tags: ["research", "Data lake"], lifecycle: .planned, color: "purple"),
            Session(name: "Flaky login test", agent: .claude, account: "Claude1", repoPath: r + "/acme/web",
                    tags: ["bug", "blocked"], lifecycle: .planned, icon: "🐛", color: "red"),
            Session(name: "Old docs tab", agent: .agy, repoPath: r + "/docs-site", lifecycle: .doNotUse),
            Session(name: "Release notes", agent: .gemini, repoPath: r + "/acme/api", tags: ["shipped", "idea"], lifecycle: .planned, color: "green"),
        ]
        for s in demo where !model.items.contains(where: { $0.session.name == s.name }) { model.save(s) }
    }

    /// Press a menu item by its titles ("Session/Mark as Next"), the way a click would (validation included).
    static func invokeMenu(_ path: String) {
        let parts = path.split(separator: "/").map(String.init)
        guard parts.count == 2, let top = NSApp.mainMenu?.items.first(where: { $0.submenu?.title == parts[0] })?.submenu,
              let i = top.items.firstIndex(where: { $0.title == parts[1] }) else { return }
        top.update()
        top.performActionForItem(at: i)
    }

    /// Every menu and its items, with enabled state (written to the snapshot JSON).
    static func menuMap() -> [String: [String]] {
        var out: [String: [String]] = [:]
        for top in NSApp.mainMenu?.items ?? [] {
            guard let m = top.submenu else { continue }
            m.update()
            out[m.title.isEmpty ? "App" : m.title] = m.items.filter { !$0.isSeparatorItem }.map {
                $0.title + (ShortcutBridge.shortcut(of: $0).map { " " + $0.display } ?? "") + ($0.isEnabled ? "" : " (off)")
            }
        }
        return out
    }

    static func type(_ text: String, into window: NSWindow?) {
        guard let window, let responder = window.firstResponder as? NSView else { return }
        for ch in text {
            let s = String(ch)
            let code: UInt16 = s == "\r" ? 36 : 0
            for type in [NSEvent.EventType.keyDown, .keyUp] {
                if let ev = NSEvent.keyEvent(with: type, location: .zero, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                             windowNumber: window.windowNumber, context: nil, characters: s,
                                             charactersIgnoringModifiers: s, isARepeat: false, keyCode: code) {
                    if type == .keyDown { responder.keyDown(with: ev) } else { responder.keyUp(with: ev) }
                }
            }
        }
    }
}
