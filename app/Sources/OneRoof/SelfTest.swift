import AppKit
import SwiftUI
import WebKit
import OneRoofCore

/// In-process checks driven by environment variables, so tests never send keystrokes system-wide.
///   ONEROOF_SELFTEST_UI2=1 · LOOK=<look | daylight|graphite|midnight: every panel> · PLACE=<place> · FOCUS=<0-3> · LAYOUT=<single|grid|wall>   v2 window (1.x)
///   ONEROOF_SELFTEST_WIDTH=<pt>                 the window this wide (1.8.2: narrow-window and toolbar checks)
///   ONEROOF_SELFTEST_INBOX=<0-7>                LAB-2042: with DEMO=1, the demo sessions ask you things (permission with
///                                               4 options, menu, question, finished turn, plan, loop item, fixed answers;
///                                               n ≥ 6 adds an answered ask), see SelfTestInbox.swift; INBOXPICK=<i> focuses
///                                               block i (=decided: the newest decided ask), INBOXDECIDED=1 opens Decided, INBOXIMAGE=<png> attaches an image,
///                                               INBOXREPLY=<text> sends a reply, INBOXPRESS=<n> presses option n,
///                                               INBOXOFFLINE=1 makes the seeded sessions unreachable
///   ONEROOF_SELFTEST_HISTORY=<n> · HISTORYFILTER=<f> · HISTORYNEW=<n> · ACTIONLOG=decisions|rules|open:<i> · ACTIONLOGFILTER=<f>
///                                               LAB-2044–2048: seed History (one moment of every kind over three days, a
///                                               deleted session, answered asks with options, rules; n > 1 adds n more),
///                                               filter it, show the "N new ↑" pill, open the Action log (SelfTestHistory.swift).
///                                               PLACE=history opens History (LAYOUT=scroll does too, LAB-2044)
///   ONEROOF_SELFTEST_PROJECTS=1 · PROJECTSTATUSES=<ids|all> · PROJECTSQUERY=<text> · PROJECTSFOLD=<team keys|all>
///                                               LAB-2050: the Projects page reads a fixture Linear (6 teams, 18 projects in
///                                               every status, milestones and issues; never the network, writes refused) and
///                                               starts with that status filter, text and folded teams (SelfTestProjects.swift);
///                                               WORK=<code> picks a project, PLACE=work opens the page
///   ONEROOF_SELFTEST_MACFIXTURE=<tabs|windows|sites|notasked|denied|safari|brave>   Resources › This Mac from fake
///                                               data (SelfTestMacFixture.swift): a browser with fake windows and tabs,
///                                               big and small helpers, a One Roof leftover and three running sessions
///                                               (LAB-853, LAB-2052, LAB-2053). The real browser is never asked anything.
///   ONEROOF_SELFTEST_TABCLOSE=tab:<id>,window:<id>,ask:<id>,hung:<id>,changed:<id> · TABHOVER=<tabId> · ALLPROCS=1
///                                               LAB-2054: press Close on fake tabs and windows (logged to <out>.tabclose.txt,
///                                               the row dropped from the fixture; never the owner's browser), draw a tab
///                                               row hovered, open "All processes"
///   ONEROOF_SELFTEST_LOOPVIEW=kinds|activity|kind:<family>|loop:<id>|empty   LAB-2055 (with PLACE=loops): the Loops page on
///                                               Kinds (the four family cards), Activity, a family's page (watch, check,
///                                               report, improve, other), a loop's pop-out card over Kinds, or the
///                                               no-loops card (empty, drawn for the capture only); never saved.
///                                               LOOPGALLERY=1 maps to kinds in the v2 window; LOOP=<id> opens the pop-out too
///   ONEROOF_SELFTEST_TRANSCRIPT=<jsonl>         LAB-1286: every pane's Table view reads this Claude transcript
///   ONEROOF_SELFTEST_TERMTEXT=<file>            LAB-1286: the Table view's terminal text (a locked screen has no surface)
///   ONEROOF_SELFTEST_TERMCOLS=<n>               LAB-1299: the width the TERMTEXT rows were cut at (rows that long rejoin)
///   ONEROOF_SELFTEST_PLACES=learn,sessions,…    open these places 0.6 s apart and write each window frame to
///                                               <out>.frames.txt (LAB-874: a place change never moves the window);
///                                               FRAMEDEBUG=1 adds the column widths, the toolbar fit and its visible items
///   ONEROOF_SELFTEST_FRAME=x,y,w,h | left|right | tile-left|tile-right   the window at this frame, the left/right
///                                               half of the screen, or tiled there by macOS (Window › Move & Resize) at
///                                               full height (the owner's layout, LAB-1281); with PLACES every window
///                                               resize is logged too
///   ONEROOF_SELFTEST_PLACES_DELAY=<s>          start the places this much later (e.g. after PLAY has loaded a card)
///   ONEROOF_SELFTEST_RENAME=<text>              with SELECTFIRST: rename that session (long-title toolbar checks)
///   ONEROOF_FRESH_PROFILE=1 ONEROOF_PROFILE_SEED=<exported defaults plist> ONEROOF_STORE=<copy of sessions.sqlite>
///                                               a real profile's settings and window state, read but never saved
///                                               (1.8.1 audit; add ONEROOF_SELFTEST_DEMO=0, ROOFD_DIR=<scratch> to stay off
///                                               the installed app's roofd, CFFIXED_USER_HOME=<scratch> for App Support)
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
///   ONEROOF_SELFTEST_STEPCLICKS=<n>            n clicks on the toolbar's Focus step button
///   ONEROOF_SELFTEST_STEPHINT=1                 show the toolbar Focus step button's hover hint (LAB-1274)
///   ONEROOF_SELFTEST_HOWDOI=<question>         ask Learn "how do I…" (v2: the best card's station; classic: the best page)
///   ONEROOF_SELFTEST_CLICK=x,y                  click the main window at that point (from its top-left)
///   ONEROOF_SELFTEST_PLAYCARD=<slug>[@muted]   play that deck card (v2 Learn); @muted plays it silently
///   ONEROOF_SELFTEST_PAGECLICK=<id>[@<s>]      Learn card page: click that element once loaded (LAB-1305, e.g. playAll;
///                                               with PLAYCARD=…@muted the page's clips play muted too)
///   ONEROOF_SELFTEST_PLAY=<page title>[@terminals]  play that Learn page's narration (then show the terminals)
///   ONEROOF_SELFTEST_LEARNHASH=#ae/<screen>    Learn's shared page opens at that screen (LAB-1893: #ae/post/<slug>, #ae/cards/folder …)
///   ONEROOF_SELFTEST_LEARNJS=<s>@<js>[;;<s>@<js>…]  run scripts in Learn's shared page that many seconds after it mounted
///   ONEROOF_SELFTEST_LEARNFOLDERS=<dir>[:<dir>…]  Settings › Learn folders for this run (never saved)
///   ONEROOF_SELFTEST_LEARNMODE / RAILFOLDED / AUTOADVANCE / CARDENDED / PAGECLICK / PAGEJS   the shared page (LearnSharedSelfTest)
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
        if let width = Double(env["ONEROOF_SELFTEST_WIDTH"] ?? "") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {   // after the first v2 layout has folded its columns
                guard let w = app.main.window else { return }
                var f = w.frame; f.size.width = CGFloat(width)
                w.setFrame(f, display: true)
            }
        }
        if let spec = env["ONEROOF_SELFTEST_FRAME"] {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
                guard let w = app.main.window, let v = (w.screen ?? NSScreen.main)?.visibleFrame else { return }
                let n = spec.split(separator: ",").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
                let f: NSRect
                // tile-left / tile-right: macOS window tiling (Window › Move & Resize), as the owner's half-screen layout
                // is made; a tiled window that AppKit resizes is untiled and gets its size from before the tile back.
                if spec.hasPrefix("tile-") {
                    w.makeKeyAndOrderFront(nil)
                    let side = spec == "tile-left" ? "Left" : "Right"
                    // macOS 15's Move & Resize items send these to the window; the menu itself is added only when shown.
                    let sel = Selector(("_zoom" + side + ":"))
                    if w.responds(to: sel) { w.perform(sel, with: nil); return }
                    if !invokeMenuPath(["Window", "Move & Resize", side]) { FileHandle.standardError.write("selftest: no Window › Move & Resize › \(side) in \(NSApp.windowsMenu?.items.map { $0.title + ($0.submenu.map { m in "[" + m.items.map(\.title).joined(separator: ",") + "]" } ?? "") } ?? [])\n".data(using: .utf8)!) }
                    return
                }
                switch spec {
                case "left": f = NSRect(x: v.minX, y: v.minY, width: (v.width / 2).rounded(), height: v.height)
                case "right": f = NSRect(x: v.minX + (v.width / 2).rounded(), y: v.minY, width: (v.width / 2).rounded(), height: v.height)
                default: guard n.count == 4 else { return }; f = NSRect(x: n[0], y: n[1], width: n[2], height: n[3])
                }
                w.setFrame(f, display: true)
            }
        }
        if let list = env["ONEROOF_SELFTEST_PLACES"], let out = env["ONEROOF_SELFTEST_OUT"] {
            let places = list.split(separator: ",").compactMap { Place(rawValue: String($0)) }
            var lines: [String] = []
            // LAB-1281: every resize of the window after the start line, whatever caused it.
            var started = false
            var rects: [NSRect] = []
            if let w = app.main.window {
                NotificationCenter.default.addObserver(forName: NSWindow.didResizeNotification, object: w, queue: .main) { _ in
                    MainActor.assumeIsolated { if started { lines.append("  resized \(NSStringFromRect(w.frame)) windows=\(MainWindowController.all.count)") } }
                }
            }
            func frame() -> String {
                guard let w = app.main.window else { return "-" }
                let dbg = ProcessInfo.processInfo.environment["ONEROOF_SELFTEST_FRAMEDEBUG"] == "1"
                    ? " fit=\(w.contentView?.fittingSize ?? .zero) panes=\(app.main.splitView.subviews.map { Int($0.frame.width) }) bar=\(app.main.v2Bar) visible=\(w.toolbar?.visibleItems?.map { $0.itemIdentifier.rawValue.replacingOccurrences(of: "oneroof.v2.", with: "") + ":" + ($0.view.map { v in "\(Int(v.convert(v.bounds, to: nil).minX))+\(Int(v.frame.width))" } ?? "-") } ?? [])" : ""
                // Every main window (a second workspace window can be the one that comes forward, LAB-1281).
                let others = MainWindowController.all.filter { $0 !== app.main }.compactMap { c -> String? in
                    guard let o = c.window else { return nil }
                    return " | other \"\(o.title)\" \(NSStringFromRect(o.frame))\(o.isVisible ? " visible" : "")\(o.isKeyWindow ? " key" : "")"
                }.joined()
                return NSStringFromRect(w.frame) + " \"\(w.title)\"\(w.isKeyWindow ? " key" : "")" + others + dbg
            }
            let t0 = 1.1 + (env["ONEROOF_SELFTEST_FRAME"] != nil ? 0.3 : 0) + (Double(env["ONEROOF_SELFTEST_PLACES_DELAY"] ?? "") ?? 0)
            DispatchQueue.main.asyncAfter(deadline: .now() + t0) { lines.append("start \(frame()) windows=\(MainWindowController.all.count)"); rects.append(app.main.window?.frame ?? .zero); started = true }
            for (k, p) in places.enumerated() {
                DispatchQueue.main.asyncAfter(deadline: .now() + t0 + 0.1 + Double(k) * 0.6) { app.main.v2Open(p) }
                DispatchQueue.main.asyncAfter(deadline: .now() + t0 + 0.6 + Double(k) * 0.6) {
                    lines.append("\(p.rawValue) \(frame())")
                    rects.append(app.main.window?.frame ?? .zero)
                    if k == places.count - 1 {
                        // One verdict line: the window kept its frame through every place (LAB-874, LAB-1281).
                        let moved = Set(rects.map { NSStringFromRect($0) }).count > 1 || lines.contains { $0.hasPrefix("  resized") }
                        lines.append(moved ? "result: CHANGED" : "result: unchanged")
                        try? lines.joined(separator: "\n").write(toFile: out + ".frames.txt", atomically: true, encoding: .utf8)
                    }
                }
            }
        }
        // P6 (v2): ONEROOF_SELFTEST_PLACE=<home|needsYou|sessions|work|machine|loops|learn>, ONEROOF_SELFTEST_FOCUS=<0-3>,
        // ONEROOF_SELFTEST_LAYOUT=<single|grid|wall>. Place first (it sets its default step), then the step.
        if app.model.settings.ui2, let p = env["ONEROOF_SELFTEST_PLACE"], let place = Place(rawValue: p) { app.model.active.open(place) }
        if let l = env["ONEROOF_SELFTEST_LAYOUT"], let layout = SessionLayout(rawValue: l) {
            app.model.active.layout = layout
        } else if env["ONEROOF_SELFTEST_LAYOUT"] == "scroll", app.model.settings.ui2 { app.model.active.open(.history) }   // LAB-2044
        if let f = Int(env["ONEROOF_SELFTEST_FOCUS"] ?? ""), let step = FocusStep(rawValue: f) { app.model.active.focusStep = step }
        // SELECTFIRST=1 selects the window's first session (demo ids are random) so the Plan and session tabs have one.
        if env["ONEROOF_SELFTEST_SELECTFIRST"] == "1" {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                if let first = app.model.items(in: app.model.active).first {
                    app.model.active.selectedId = first.id
                    // RENAME=<text>: give it a long name (1.8.2 toolbar checks).
                    if let name = env["ONEROOF_SELFTEST_RENAME"] { var s = first.session; s.name = name; app.model.save(s) }
                }
            }
        }
        // V2PLAN=1 slides the Plan over the terminal (C7.1); V2EDGE=1 reveals the session column at Focus (C7.2).
        if env["ONEROOF_SELFTEST_V2PLAN"] == "1" { DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { app.main.v2ShowPlanOverlay() } }
        // STEPCLICKS=<n>: n clicks on the toolbar's step button (its primary action; LAB-1235: from Focus round to Full).
        if let n = Int(env["ONEROOF_SELFTEST_STEPCLICKS"] ?? "") {
            for k in 0..<n { DispatchQueue.main.asyncAfter(deadline: .now() + 1.6 + Double(k) * 0.4) { app.main.v2StepClick() } }
        }
        // LAB-1274: the toolbar step button's hover hint, shown without a mouse.
        if env["ONEROOF_SELFTEST_STEPHINT"] == "1" {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { NotificationCenter.default.post(name: StepHintAnchor.HintAnchorView.show, object: nil) }
        }
        if env["ONEROOF_SELFTEST_V2EDGE"] == "1" { DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { app.main.v2ShowEdgeReveal() } }
        // LAB-1919 · LAB-1941 · LAB-1920 · LAB-1921 · LAB-1922 (loops, 1.9.34; point ONEROOF_SHARED at a scratch folder):
        //   LOOPPICK=<n>   Needs you shows its n-th loop item (failures and asks, then Today)
        //   LOOP=<id>      the Loops page opens that loop (its outcomes and rounds)
        //   LOOPDRAFT=<words>   the New loop editor opens with the rule-based draft of those words (LOOPPREVIEW=1 opens the dry run)
        //   LOOPGALLERY=1  the Loops page shows the gallery (v2: Kinds, LAB-2055)
        //   LOOPVIEW=kinds|activity|kind:<family>|loop:<id>   read by LoopsView itself (LAB-2055)
        if env.keys.contains(where: { $0.hasPrefix("ONEROOF_SELFTEST_LOOP") }) { app.model.refreshLoopInbox() }
        if let n = Int(env["ONEROOF_SELFTEST_LOOPPICK"] ?? "") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                let items = LoopInboxState.shared.items
                if n < items.count { app.model.needsPick = "loop-" + items[n].id }
            }
        }
        if let id = env["ONEROOF_SELFTEST_LOOP"] { DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { app.model.openLoop(id) } }
        if let words = env["ONEROOF_SELFTEST_LOOPDRAFT"] {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                let repo = WorkspaceSearch.repos().first ?? Workspace.projectsRoot
                LoopInboxState.shared.draftRequest = LoopDrafter.rules(words).apply(to: Loop(id: "", name: "", repoPath: repo))
                app.model.show(.loops)
            }
        }
        if env["ONEROOF_SELFTEST_DEMO"] == "1" { seedDemo(app.model) }
        if SelfTestProjects.active { SelfTestProjects.install(app.model) }   // LAB-2050: a fixture Linear (SelfTestProjects.swift)
        SelfTestHistory.run(app, env: env)   // LAB-2044–2048: History and the Action log (SelfTestHistory.swift)
        // LAB-2042 · the Inbox's blocks from the demo sessions (SelfTestInbox.swift says what each n adds).
        if let n = Int(env["ONEROOF_SELFTEST_INBOX"] ?? "") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { SelfTestInbox.seed(app.model, count: n) }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
                if env["ONEROOF_SELFTEST_INBOXDECIDED"] == "1" { NotificationCenter.default.post(name: .inboxSelfTest, object: ["decided": true]) }
                if env["ONEROOF_SELFTEST_INBOXPICK"] == "decided", let d = app.model.inboxDecided.first {   // the newest decided ask
                    app.model.needsPick = d.id.uuidString
                } else if let i = Int(env["ONEROOF_SELFTEST_INBOXPICK"] ?? ""), i < app.model.inboxLayout.all.count {
                    app.model.needsPick = app.model.inboxLayout.all[i].id
                }
            }
            if let text = env["ONEROOF_SELFTEST_INBOXREPLY"] {
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.6) { NotificationCenter.default.post(name: .inboxSelfTest, object: ["reply": text]) }
            }
            if let k = Int(env["ONEROOF_SELFTEST_INBOXPRESS"] ?? "") {
                let at = Double(env["ONEROOF_SELFTEST_INBOXPRESSAT"] ?? "") ?? 6.2
                DispatchQueue.main.asyncAfter(deadline: .now() + at) { NotificationCenter.default.post(name: .inboxSelfTest, object: ["press": k]) }
            }
            if let png = env["ONEROOF_SELFTEST_INBOXIMAGE"] {
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.4) { NotificationCenter.default.post(name: .inboxSelfTest, object: ["attach": png]) }
            }
        }
        if env["ONEROOF_SELFTEST_FOUNDATIONS"] == "1" { DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { app.showFoundations(nil) } }
        if let w = env["ONEROOF_SELFTEST_WORK"] {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { app.model.workMode = true; app.model.loadWorkstreams() }
            if w != "1" {   // a WS id: select it once loaded
                DispatchQueue.main.asyncAfter(deadline: .now() + 4.0) {
                    if let ws = app.model.workstreams.first(where: { $0.wsId == w || $0.name.contains(w) }) { workSelect = ws.id; app.model.loadIssues(ws) }
                }
                // LAB-1255: what Linear returned (projects, the picked project's name and issue count) in <out>.work.txt.
                if let out = env["ONEROOF_SELFTEST_OUT"] {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 12.0) {
                        let ws = app.model.workstreams.first { $0.wsId == w || $0.name.contains(w) }
                        let text = "projects=\(app.model.workstreams.count) error=\(app.model.linearError ?? "-")\n"
                            + "picked=\(ws?.name ?? "-") issues=\(ws.flatMap { app.model.issues[$0.id]?.count } ?? -1)\n"
                            + app.model.workstreams.map(\.name).filter { $0.contains("LAB-ONEROOF") }.joined(separator: "\n")
                        try? text.write(toFile: out + ".work.txt", atomically: true, encoding: .utf8)
                    }
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
        // LAB-1893 · the shared Learn page's own self-test hooks (LearnSharedController.selfTest runs LEARNJS once it mounts).
        // LAB-1894 · LEARNMODE (the classic screens' places) opens the same place on the shared page (LearnSharedSelfTest).
        if let m = env["ONEROOF_SELFTEST_LEARNMODE"] {
            let plan = LearnSharedSelfTest.mode(m)
            MainActor.assumeIsolated { LearnSharedController.lastHash = plan.hash; LearnSharedController.selfTestSteps += plan.scripts }
        }
        if let h = env["ONEROOF_SELFTEST_LEARNHASH"], h.hasPrefix("#ae/") { MainActor.assumeIsolated { LearnSharedController.lastHash = h } }
        if let f = env["ONEROOF_SELFTEST_LEARNFOLDERS"] { app.model.settings.learnFolders = f.split(separator: ":").map(String.init) }
        if let l = env["ONEROOF_SELFTEST_LEARN"] {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                if l.hasPrefix("/") { app.model.learnTarget = l }
                app.model.learnMode = true
            }
            // LAB-1233: ONEROOF_SELFTEST_LEARN=<page title> opens that Learn page once the index has loaded.
            if l != "1", !l.hasPrefix("/") {
                app.model.loadLearn()
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                    if let it = app.model.learnItems.first(where: { $0.title == l }) { app.model.learnTarget = it.id }
                }
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
                // LAB-1233: "<title>@paused" loads the page into the player and pauses at once (captures without sound).
                if spec.hasSuffix("@paused") { app.model.player.pause() }
                if spec.hasSuffix("@terminals") { DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { app.model.goTerminals() } }
            }
        }
        // PLAYCARD=<deck slug>[@muted]: play that card from the start as Radio's ▶ does (LAB-1281: Learn's frame with a
        // card playing and the player bar showing).
        if let spec = env["ONEROOF_SELFTEST_PLAYCARD"] {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                let slug = spec.components(separatedBy: "@")[0]
                guard let deck = app.model.learnDeck, let c = deck.cards[slug] else { return }
                let page = deck.htmlPath(slug), tracks = CourseAudio.tracks(page: page)
                guard !tracks.isEmpty else { return }
                app.model.player.play(pageId: page, title: c.title, tracks: tracks)
            }
        }
        // CLICK=x,y: a mouse click at that point of the main window, measured from its top-left (LAB-1266: the rail's
        // seats button), delivered through the window as a real click would be.
        if let spec = env["ONEROOF_SELFTEST_CLICK"] {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                let n = spec.split(separator: ",").compactMap { Double($0) }
                guard n.count == 2, let w = app.main.window else { return }
                let p = NSPoint(x: n[0], y: w.frame.height - n[1])
                for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
                    if let e = NSEvent.mouseEvent(with: type, location: p, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                                  windowNumber: w.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1) {
                        w.sendEvent(e)
                    }
                }
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
        // EDITAGENTS=1 (LAB-1934): open Settings › Seats & accounts in the main window, click into every agent's Model and
        // Extra arguments field the way a person would, type into it, and write <out>.editagents.txt: what the click hit,
        // who has the keyboard, what the field shows and what was saved.
        if env["ONEROOF_SELFTEST_EDITAGENTS"] == "1", let out = env["ONEROOF_SELFTEST_OUT"] {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { app.main.v2ShowSettings(pane: 2) }
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.5) { editAgentsProbe(app: app, out: out + ".editagents.txt") }
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
            drawWebViews(in: view, onto: rep)
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
        let inbox = app.model.inboxLayout.all.map { "\($0.kind.rawValue) \($0.id)" }   // LAB-2042: the Inbox's blocks, top to bottom
        let meta: [String: Any] = ["rows": rows, "runtime": app.model.runtimeState, "selected": app.model.selectedId ?? "",
                                   "inbox": inbox, "inboxBadge": app.model.needsYouBadge, "loopItems": LoopInboxState.shared.items.map(\.id),
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

    /// LAB-1305 · WebKit draws out of process, so cacheDisplay leaves a web view blank: take each visible web view's own
    /// snapshot (WKWebView.takeSnapshot) and draw it into the capture at its place.
    static func drawWebViews(in root: NSView, onto rep: NSBitmapImageRep) {
        func webs(_ v: NSView) -> [WKWebView] { (v as? WKWebView).map { [$0] } ?? v.subviews.flatMap(webs) }
        let list = webs(root).filter { !$0.isHiddenOrHasHiddenAncestor && $0.window != nil && $0.visibleRect.width > 1 }
        guard !list.isEmpty, let ctx = NSGraphicsContext(bitmapImageRep: rep) else { return }
        let scale = CGFloat(rep.pixelsWide) / max(1, root.bounds.width)
        for w in list {
            var image: NSImage?
            var done = false
            w.takeSnapshot(with: nil) { img, _ in image = img; done = true }
            let until = Date().addingTimeInterval(3)
            while !done, Date() < until { RunLoop.current.run(until: Date().addingTimeInterval(0.05)) }
            guard let image else { continue }
            let r = w.convert(w.bounds, to: root)
            let flipped = root.isFlipped ? NSRect(x: r.minX, y: root.bounds.height - r.maxY, width: r.width, height: r.height) : r
            let visible = w.convert(w.visibleRect, to: root)
            let clip = root.isFlipped ? NSRect(x: visible.minX, y: root.bounds.height - visible.maxY, width: visible.width, height: visible.height) : visible
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = ctx
            ctx.cgContext.scaleBy(x: scale, y: scale)
            NSBezierPath(rect: clip).addClip()
            image.draw(in: flipped)
            NSGraphicsContext.restoreGraphicsState()
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

    /// A menu item at any depth by titles ("Window", "Move & Resize", "Right"); true when it was performed.
    @discardableResult
    static func invokeMenuPath(_ titles: [String]) -> Bool {
        var menu: NSMenu? = NSApp.mainMenu
        var titles = titles
        if let first = titles.first, let top = menu?.items.first(where: { $0.submenu?.title == first })?.submenu { menu = top; titles.removeFirst() }
        while let m = menu, let t = titles.first {
            m.update()
            guard let i = m.items.firstIndex(where: { $0.title == t }) else { return false }
            titles.removeFirst()
            if titles.isEmpty { m.performActionForItem(at: i); return true }
            menu = m.items[i].submenu
        }
        return false
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

    /// LAB-1934: every editable text field whose placeholder is "optional" (Extra arguments) or "CLI default" (Model),
    /// top to bottom. Each is found again at its turn (a saved edit redraws Settings, so earlier views go stale), scrolled
    /// into view, given the keyboard, typed into through the window's own key path, then read back from the saved settings.
    static func editAgentsProbe(app: AppDelegate, out: String) {
        guard let w = app.main.window, let root = w.contentView else { return }
        func fields(_ v: NSView) -> [NSTextField] {
            var r: [NSTextField] = []
            if let f = v as? NSTextField, f.isEditable {
                let ph = f.placeholderString ?? f.placeholderAttributedString?.string ?? ""
                if ph.hasPrefix("optional") || ph == "CLI default" { r.append(f) }
            }
            for s in v.subviews where !s.isHidden { r += fields(s) }
            return r
        }
        var lines = ["fields found: \(fields(root).count)"]
        func save() { try? lines.joined(separator: "\n").appending("\n").write(toFile: out, atomically: true, encoding: .utf8) }
        save()
        func step(_ i: Int) {
            let all = fields(root)
            guard i < all.count else {
                for a in AgentKind.allCases where a.isAgent && !a.isHosted {
                    let d = app.model.settings.defaults(for: a)
                    lines.append("saved \(a.rawValue): model=\(d.model) args=\(d.args)")
                }
                lines.append("done")
                save()
                return
            }
            let f = all[i]
            f.scrollToVisible(f.bounds)
            let ph = f.placeholderString ?? f.placeholderAttributedString?.string ?? ""
            let took = w.makeFirstResponder(f)
            let editing = f.currentEditor() != nil && w.firstResponder === f.currentEditor()
            for ch in "p\(i)" {
                for t in [NSEvent.EventType.keyDown, .keyUp] {
                    if let e = NSEvent.keyEvent(with: t, location: .zero, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                                windowNumber: w.windowNumber, context: nil, characters: String(ch),
                                                charactersIgnoringModifiers: String(ch), isARepeat: false, keyCode: 0) {
                        w.sendEvent(e)
                    }
                }
            }
            let shown = f.stringValue
            lines.append("#\(i) [\(ph)] key=\(w.isKeyWindow) tookFocus=\(took) editing=\(editing) shows=\"\(shown)\" bordered=\(f.isBordered) bezeled=\(f.isBezeled) align=\(f.alignment.rawValue)")
            save()
            w.makeFirstResponder(nil)   // end editing: the value is committed, as when a person tabs away
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { step(i + 1) }
        }
        step(0)
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

    /// LAB-1556: drag divider `index` of `split` to window x `toX` with real mouse events: the split view's own drag
    /// loop reads them, so collapse rules apply exactly as for a hand drag.
    static func dragDivider(_ split: NSSplitView, in w: NSWindow, index: Int, toX: CGFloat) {
        let views = split.arrangedSubviews
        guard views.indices.contains(index) else { return }
        // A folded (hidden) panel comes back by a drag from AppKit's 15 pt strip where it starts (LAB-1829: the folded
        // rail, at the window's left edge; the outer 3 pt are the window's own resize edge).
        let x = views[index].isHidden ? views[index].frame.minX + 10 : views[index].frame.maxX + split.dividerThickness / 2
        let y = split.bounds.midY
        let start = split.convert(NSPoint(x: x, y: y), to: nil)
        let end = split.convert(NSPoint(x: toX, y: y), to: nil)
        func ev(_ type: NSEvent.EventType, _ p: NSPoint) -> NSEvent? {
            NSEvent.mouseEvent(with: type, location: p, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                               windowNumber: w.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)
        }
        let steps = 12
        if views[index].isHidden {
            // A folded panel's edge is hidden: a real drag there goes through the window to what it hits (LAB-1829: the
            // rail grip), so queue press, drags and release in order.
            if let down = ev(.leftMouseDown, start) { NSApp.postEvent(down, atStart: false) }
            for i in 1...steps {
                let p = NSPoint(x: start.x + (end.x - start.x) * CGFloat(i) / CGFloat(steps), y: start.y)
                if let e = ev(.leftMouseDragged, p) { NSApp.postEvent(e, atStart: false) }
            }
            if let up = ev(.leftMouseUp, end) { NSApp.postEvent(up, atStart: false) }
            return
        }
        for i in 1...steps {
            let p = NSPoint(x: start.x + (end.x - start.x) * CGFloat(i) / CGFloat(steps), y: start.y)
            if let e = ev(.leftMouseDragged, p) { NSApp.postEvent(e, atStart: false) }
        }
        if let up = ev(.leftMouseUp, end) { NSApp.postEvent(up, atStart: false) }
        if let down = ev(.leftMouseDown, start) { split.mouseDown(with: down) }
    }
}

