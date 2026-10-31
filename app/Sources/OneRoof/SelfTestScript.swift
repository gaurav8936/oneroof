import AppKit
import Combine
import SwiftUI
import OneRoofCore

/// Scripted self-test (LAB-12): `ONEROOF_SELFTEST_SCRIPT=<file>` runs one step per line, in order, inside the app,
/// so multi-step flows (launch → close → relaunch → reopen, quit → reopen) can be checked without keystrokes from
/// outside. Results go to `ONEROOF_SELFTEST_OUT` + "-<name>" (png / json / txt). Lines starting with # are comments.
///
///   wait <seconds>                 terminal [dir]               type <text>        (types text + Return)
///   send <text>                    (into the selected session through roofd, + Return)
///   plan <name>|<agent>|<repo>|<opening>|<launch 0/1>         select <session name>
///   rename <name> (the selected session, as Rename… does)   steps <n> (add finished steps)   checktop (top strip fits?)
///   launch · close · delete · reopen · interrupt · popout · quit · newsession (⌘N sheet) · keys <text> (into the sheet)
///   roof <dir>                     centre <view>                menu <Menu>/<Item>
///   answer allowOnce|always|deny   snap <name>   dump <name>   screen <name>   (selected session's text)
///   copytest <name>                (drag-select, copy, paste text, paste an image → <name>.copytest.txt)
///   compose                        (LAB-1298: the focused pane's composer on/off, as the pane header's Compose does)
///   table                          (LAB-1286: the focused pane's Table view on/off, as the Table button does)
///   tablescroll left|right         (scroll every table in the Table view to its left or right end)
///   strayfiles · togglefiles · panels   (LAB-1306: show the classic Files panel, send its × action, log panels)
///   dragdivider <i> <x>            (LAB-1556: drag split divider i to window x with real mouse events)
///   focusstep <0-3>                (LAB-1302: the window's Focus step, as ⌥⌘F steps it)
///   resumeall [max]                (LAB-1583: Resume every catalog row that offers it, one by one → <out>-resume.tsv)
///   catalogsearch <q> [!]          (LAB-1585: rank sessions for <q>; " !" widens with the model → log)
///   railsessions                   (LAB-1576: a click on Sessions in the rail)
///   tableprobe                     (log: Table view on?, what it shows, who has the keyboard)
///   esc                            (an Esc key event through the app, so key monitors see it)
///   width <pt>                     (the main window this wide; the panes follow)
///   alltext <name>                 (the focused terminal's whole text as libghostty gives it → <name>.alltext.txt)
///   expect · newwindow · switchwindow · place · search · textcount · hitch · resizegesture · windowsize   (SelfTestHarness)
///   window <name> · activate <name>   (LAB-1591: a new workspace window, active; or make an open one active)
///   place <place>                  (LAB-1592: home · needsYou · sessions · work · machine · loops · learn)
///   needs <name>                   (LAB-1592: Needs you's open asks, badge and every session's status → <name>.needs.json)
enum SelfTestScript {
    nonisolated(unsafe) static var perfBag: AnyCancellable?
    nonisolated(unsafe) static var noNap: NSObjectProtocol?
    static func run(_ path: String, app: AppDelegate) {
        guard let text = try? String(contentsOfFile: path, encoding: .utf8) else { return }
        let steps = text.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("#") }
        let out = ProcessInfo.processInfo.environment["ONEROOF_SELFTEST_OUT"] ?? "/tmp/oneroof-script"
        log(out, "start \(steps.count) steps")
        // LAB-1596: a scripted run must not nap. With the screen locked or the window covered, App Nap holds timers back
        // for a second or more, which the gesture probes then read as main-thread stalls the app never had.
        noNap = ProcessInfo.processInfo.beginActivity(options: [.userInitiated, .latencyCritical], reason: "self-test run")
        // Perf probe: how often the model announces a change (each one re-renders every panel), per 5 s.
        var changes = 0
        perfBag = app.model.objectWillChange.sink { changes += 1 }
        Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { _ in log(out, "perf: \(changes) model changes in 5 s"); changes = 0 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { step(steps, 0, app: app, out: out) }
    }

    /// LAB-1592: Needs you as the place shows it (open decisions, oldest first), plus every session's status and the
    /// badge count, so a run can say which asks reached it.
    static func writeNeeds(_ m: AppModel, to path: String) {
        let open = m.openDecisions.map { d -> [String: Any] in
            ["session": m.item(d.sessionId)?.session.name ?? d.sessionId, "agent": d.agent.rawValue, "kind": d.kind.rawValue,
             "headline": d.command.map { "Run " + $0 } ?? d.headline, "askedAt": d.askedAt.timeIntervalSince1970]
        }
        let rows = m.items.map { i -> [String: Any] in
            ["name": i.session.name, "status": i.status.rawValue, "agent": i.session.agent.rawValue, "live": i.liveAgent ?? "",
             "window": m.window(m.workspaceId(of: i))?.name ?? ""]
        }
        let meta: [String: Any] = ["at": Date().timeIntervalSince1970, "open": open, "badge": max(m.openDecisionCount, m.items.filter { $0.status == .needsYou }.count),   // V2Counts.needsYou
                                   "decisionsAll": m.decisions.count, "rows": rows]
        if let d = try? JSONSerialization.data(withJSONObject: meta, options: [.prettyPrinted, .sortedKeys]) {
            try? d.write(to: URL(fileURLWithPath: path))
        }
    }

    static func log(_ out: String, _ line: String) {
        let p = out + "-log.txt"
        let stamped = "\(String(format: "%.1f", Date().timeIntervalSince1970.truncatingRemainder(dividingBy: 10_000))) \(line)\n"
        if let h = FileHandle(forWritingAtPath: p) { h.seekToEndOfFile(); h.write(Data(stamped.utf8)); h.closeFile() }
        else { try? stamped.write(toFile: p, atomically: true, encoding: .utf8) }
    }

    static func step(_ steps: [String], _ i: Int, app: AppDelegate, out: String) {
        guard i < steps.count else { log(out, "done"); return }
        let line = steps[i]
        let cmd = String(line.split(separator: " ", maxSplits: 1).first ?? "")
        let arg = line.dropFirst(cmd.count).trimmingCharacters(in: .whitespaces)
        let m = app.model
        var delay = 0.5
        log(out, "\(i + 1): \(line)")
        switch cmd {
        case "wait": delay = Double(arg) ?? 1
        case "terminal": m.newTerminal(in: arg.isEmpty ? nil : (arg as NSString).expandingTildeInPath); delay = 2
        case "type":
            app.main.terminalArea.focusTerminal()
            SelfTest.type(arg + "\r", into: app.main.window)
            delay = 1
        case "send":
            // Type into the selected session through the runtime (roofd input), not synthetic key events.
            if let pane = m.selected?.paneId {
                let r = m.runtime
                DispatchQueue.global().async { try? r.type(pane: pane, text: arg + "\r") }
            } else { log(out, "  no selected session") }
            delay = 1
        case "plan":
            let f = arg.components(separatedBy: "|")
            if f.count >= 5, let agent = AgentKind(rawValue: f[1]) {
                var s = Session(name: f[0], agent: agent, repoPath: (f[2] as NSString).expandingTildeInPath,
                                openingMessage: f[3], lifecycle: .planned)
                s.startInRepo = s.repoPath != Workspace.projectsRoot
                if agent.isHosted {
                    let id = f.count > 5 ? f[5] : m.settings.defaults(for: agent).hostedConnectionID
                    s.hostedConnectionID = id
                    s.model = m.settings.hostedConnections.first(where: { $0.id == id })?.model
                    s.permissionMode = .manual
                }
                m.createPlanned(s, launchNow: f[4] == "1")
            } else { log(out, "  bad plan line") }
            delay = 1
        case "select":
            if let it = m.items.first(where: { $0.session.name == arg }) { m.selectedId = it.id } else { log(out, "  no session \(arg)") }
        case "launch": if let it = m.selected { m.launch(it) }; delay = 2
        case "close": if let it = m.selected { m.closeAgent(it) }; delay = 2
        case "delete": if let it = m.selected { m.delete(it) }
        case "rename": if let it = m.selected { m.rename(it, arg) }   // as Rename… does, with the plan panel open (LAB-487)
        case "steps":   // add n finished steps to the selected session, as the chapter engine would (LAB-521)
            if let it = m.selected, let n = Int(arg) {
                let have = m.chapters[it.id] ?? []
                let now = Date()
                m.chapters[it.id] = have + (0..<n).map { k in
                    Chapter(index: have.count + k + 1, title: "Step \(have.count + k + 1)", summary: "", toolCalls: 1,
                            started: now, ended: now, scrollbackRange: 0..<1)
                }
            }
        case "summarycard":   // LAB-1270: the open summary card's height with 0…12 steps; it must never change
            if let it = m.selected {
                let saved = m.chapters[it.id], now = Date()
                var heights: [String] = []
                for n in [0, 1, 3, 5, 6, 12] {
                    m.chapters[it.id] = (0..<n).map { k in
                        Chapter(index: k, title: "Step \(k + 1) · a longer title that runs on", summary: "", toolCalls: k + 1,
                                started: now.addingTimeInterval(-Double(60 * (k + 1))), ended: k == n - 1 ? nil : now, scrollbackRange: 0..<1)
                    }
                    let host = NSHostingView(rootView: SummaryCard(model: m, item: it, onCollapse: {}).themed(m.themes.centre))
                    host.frame = NSRect(x: 0, y: 0, width: 1200, height: 10)
                    let h = host.fittingSize.height
                    host.frame.size.height = h
                    host.layoutSubtreeIfNeeded()
                    if let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) {
                        host.cacheDisplay(in: host.bounds, to: rep)
                        try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: out + "-\(arg)-\(n).png"))
                    }
                    heights.append("\(n) steps: \(Int(h.rounded())) pt")
                }
                m.chapters[it.id] = saved
                log(out, "  summarycard " + heights.joined(separator: " · "))
            }
        case "checktop":   // each pane's top strip: laid-out height vs the height its content needs (LAB-521)
            for h in app.main.terminalArea.topHeights() {
                log(out, "  top \(abs(h.frame - h.needs) < 1 ? "OK" : "CLIPPED") frame=\(Int(h.frame)) needs=\(Int(h.needs))")
            }
        case "reopen": m.reopenClosed(); delay = 2
        case "interrupt": if let it = m.selected { m.interrupt(it) }
        case "popout": if let it = m.selected { PopOutWindowController.popOut(it, model: m) }; delay = 2
        case "roof": RoofWindowController.show(.repo((arg as NSString).expandingTildeInPath), model: m); delay = 3
        case "centre": if let v = CentreView(rawValue: arg) { m.show(v) }
        case "settingspane": if let pane = Int(arg) { app.main.v2ShowSettings(pane: pane) }; delay = 1
        case "menu": SelfTest.invokeMenu(arg)
        case "answer":
            if let d = m.openDecisions.first, let a = Answer(rawValue: arg) { m.answer(d, a) } else { log(out, "  no open decision") }
            delay = 1
        case "group": if let g = Grouping(rawValue: arg) { m.grouping = g } else { log(out, "  bad grouping") }
        case "chip": if let c = StatusChip(rawValue: arg) { app.main.win.statusFilter = c == .all ? nil : c }
        case "newsession":   // `newsession [agent]`: the sheet opens with that agent picked (LAB-1826: `newsession gemini`)
            NewSessionSheet.selfTestMark = AgentMark(rawValue: arg)
            app.main.newSession(); delay = 2
        case "keys":
            // Type into whatever has focus in the key window or its sheet (e.g. the New work sheet's text field).
            let w = app.main.window?.attachedSheet ?? NSApp.keyWindow ?? app.main.window
            SelfTest.type(arg, into: w)
            delay = 1
        case "probe": log(out, "  " + app.main.terminalArea.debugState())
        case "table": app.main.terminalArea.toggleTable(app.main.terminalArea.focusedPane); delay = 2.5
        case "compose": app.main.terminalArea.toggleComposer(app.main.terminalArea.focusedPane); delay = 1.5
        case "tablescroll": app.main.terminalArea.scrollTables(toEnd: arg == "right"); delay = 0.8
        case "strayfiles": app.main.filesItemRef.isCollapsed = false; delay = 1   // LAB-1306: the classic panel shows
        case "togglefiles": app.main.toggleFiles(); delay = 1.5
        case "panels":
            let sv = app.main.splitView
            let widths = sv.arrangedSubviews.map { "\(Int($0.frame.width))" }.joined(separator: ",")
            log(out, "  files=\(!app.main.filesItemRef.isCollapsed) sessions=\(!app.main.sideItemRef.isCollapsed) widths=\(widths) centre=\(app.model.active.centre)")
        case "dragdivider":
            // LAB-1556: a real divider drag (mouse down on divider <i>, drags to x, mouse up), as a hand drag sends it.
            let parts = arg.split(separator: " ").compactMap { Double($0) }
            if parts.count == 2, let w = app.main.window { SelfTest.dragDivider(app.main.splitView, in: w, index: Int(parts[0]), toX: CGFloat(parts[1])) }
            delay = 1.5
        case "focusstep": if let n = Int(arg), let st = FocusStep(rawValue: n) { app.model.active.focusStep = st }; delay = 1.5
        case "resumeall":   // LAB-1583: the next step starts when every row is done
            SelfTestResume.run(app, out: out, max: Int(arg) ?? 1000) { step(steps, i + 1, app: app, out: out) }
            return
        case "catalogresume":   // LAB-1584: press Resume on the catalog's History row number <n> (1 = first), as a click does
            let rows = m.catalogEntries().filter { $0.state == .history && $0.resume.buttonTitle != nil }
            if let n = Int(arg), rows.indices.contains(n - 1) { log(out, "  resume \(rows[n - 1].name)"); m.catalogResume(rows[n - 1].id) }
            delay = 1
        case "catalogsearch":   // LAB-1585: <query> (append " !" to widen with the model) → top hits in the log
            let deep = arg.hasSuffix(" !"), q = deep ? String(arg.dropLast(2)) : arg
            let rows = m.catalogSearchRows()
            DispatchQueue.global().async {
                let docs = SessionSearch.docs(rows)
                let extra = deep ? LocalModel.shared.expandSearch(q) : []
                let hits = SessionSearch.rank(q, extra: extra, docs: docs)
                let names = Dictionary(uniqueKeysWithValues: docs.map { ($0.id, $0.title) })
                DispatchQueue.main.async {
                    log(out, "  search '\(q)' docs=\(docs.count) withText=\(docs.filter { !$0.lines.isEmpty }.count) related=\(extra) hits=\(hits.count)")
                    for h in hits.prefix(5) { log(out, "    \(String(format: "%.1f", h.score)) \(names[h.id] ?? h.id) | \(h.snippet.prefix(120))") }
                    step(steps, i + 1, app: app, out: out)
                }
            }
            return
        case "rail":   // LAB-1829: `rail open` / `rail fold`, as View › Rail does (a folded rail is remembered per window)
            if app.main.win.railFolded != (arg == "fold") { app.main.v2ToggleRail() }
            delay = 1
        case "railsessions": app.main.v2Open(.sessions); delay = 1.0   // LAB-1576: the rail's Sessions button
        case "tableprobe": log(out, "  " + app.main.terminalArea.tableProbe())
        case "clickshrink":   // LAB-1758: a click in the centre, then the window made <w> wide while that click is handled
            if let w = app.main.window, let pt = Double(arg) {
                let v = app.main.centreItemRef.viewController.view
                let p = v.convert(NSPoint(x: v.bounds.midX, y: v.bounds.midY), to: nil)
                if let e = NSEvent.mouseEvent(with: .leftMouseUp, location: p, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                              windowNumber: w.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 0) {
                    NSApp.postEvent(e, atStart: true)
                    DispatchQueue.main.async { var f = w.frame; f.size.width = CGFloat(pt); w.setFrame(f, display: true) }
                }
            }
            delay = 1.5
        case "barprobe":   // LAB-1783: where the window buttons, toolbar items and columns sit (window points, from the left)
            if let w = app.main.window {
                let f = { (r: NSRect) in "\(Int(r.minX.rounded()))…\(Int(r.maxX.rounded()))@\(Int(r.midY.rounded()))" }
                let lights = [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton].compactMap { w.standardWindowButton($0) }
                    .map { b in f(b.convert(b.bounds, to: nil)) }
                let items = (w.toolbar?.items ?? []).map { i -> String in
                    let name = i.itemIdentifier.rawValue.replacingOccurrences(of: "oneroof.v2.", with: "")
                    guard let v = i.view, v.window != nil, !v.isHiddenOrHasHiddenAncestor else { return name + " -" }
                    return name + " " + f(v.convert(v.bounds, to: nil))
                }
                let arranged = app.main.splitView.arrangedSubviews
                let cols = app.main.splitView.subviews.map { v -> String in
                    (arranged.contains(v) ? "" : String(describing: type(of: v)) + ":") + (v.isHidden ? "h" : v.frame.width < 0.5 ? "0w" : "")
                        + "\(Int(v.frame.minX.rounded()))…\(Int(v.frame.maxX.rounded()))"
                }
                let at = { (x: CGFloat) in app.main.window?.contentView?.superview?.hitTest(NSPoint(x: x, y: 400)).map { String(describing: type(of: $0)) } ?? "-" }
                log(out, "  hit at the rail's edge: x=64 \(at(64)) · x=66 \(at(66)) · x=67 \(at(67)) · x=69 \(at(69))")
                let hit = at(10)
                log(out, "  hit at x=10: \(hit) · grip \(app.main.v2RailGrip.map { $0.isHidden ? "hidden" : "shown \(Int($0.frame.minX))…\(Int($0.frame.maxX)) h\(Int($0.frame.height))" } ?? "none") · folded \(app.main.win.railFolded)")
                log(out, "  bar \(arg) window \(Int(w.frame.width))×\(Int(w.frame.height)) lights \(lights) items \(items) columns \(cols)")
            }
        case "esc":
            if let w = app.main.window, let ev = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                                                   windowNumber: w.windowNumber, context: nil, characters: "\u{1b}",
                                                                   charactersIgnoringModifiers: "\u{1b}", isARepeat: false, keyCode: 53) {
                log(out, "  esc with keyboard in " + (w.firstResponder.map { String(describing: Swift.type(of: $0)) } ?? "-"))
                NSApp.postEvent(ev, atStart: false)
            }
            delay = 1
        case "width":
            if let w = app.main.window, let pt = Double(arg) { var f = w.frame; f.size.width = CGFloat(pt); w.setFrame(f, display: true) }
            delay = 2
        case "alltext":
            try? (app.main.terminalArea.focusedAllText() ?? "(none)").write(toFile: out + "-" + arg + ".alltext.txt", atomically: true, encoding: .utf8)
        case "window":   // LAB-1591: a new workspace window, as New Workspace Window… creates it; it becomes the active one
            NotificationCenter.default.post(name: .newWorkspace, object: [arg, ""])
            delay = 1.5
        case "activate":   // LAB-1591: make an open window (by name) the active one, so the next plan lands in it
            if let w = m.windows.first(where: { $0.name == arg }) { m.activeWindowId = w.id } else { log(out, "  no window \(arg)") }
        case "place":   // LAB-1592: open a place in the active window (home, needsYou, sessions, work, machine, loops, learn)
            if let p = Place(rawValue: arg) { app.main.v2Open(p) } else { log(out, "  bad place") }
            delay = 1
        case "needs":   // LAB-1592: what Needs you holds now → <name>.needs.json (the simulator compares it with what was asked)
            SelfTestScript.writeNeeds(m, to: out + "-" + arg + ".needs.json")
        case "snap": SelfTest.snapshot(app: app, to: out + "-" + arg)
        case "copytest": SelfTest.copyTest(app: app, to: out + "-" + arg); delay = 1
        case "dump":
            let rows = m.items.map { i -> [String: Any] in
                ["name": i.session.name, "status": i.status.rawValue, "agent": i.session.agent.rawValue,
                 "live": i.liveAgent ?? "", "runtimeId": i.session.runtimeId ?? "", "adopted": i.adopted,
                 "openingSent": i.session.openingSent, "caption": m.captions[i.id]?.text ?? ""]
            }
            let meta: [String: Any] = ["rows": rows, "runtime": m.runtimeState, "ok": m.runtimeOK, "error": m.lastError ?? "",
                                       "selected": m.selected?.session.name ?? "", "decisions": m.openDecisions.count,
                                       "windows": NSApp.windows.filter(\.isVisible).map(\.title)]
            if let d = try? JSONSerialization.data(withJSONObject: meta, options: [.prettyPrinted, .sortedKeys]) {
                try? d.write(to: URL(fileURLWithPath: out + "-" + arg + ".json"))
            }
        case "screen":
            if let pane = m.selected?.paneId {
                let r = m.runtime
                DispatchQueue.global().async {
                    let t = (try? r.read(pane: pane, lines: 60)) ?? "(read failed)"
                    try? t.write(toFile: out + "-" + arg + ".txt", atomically: true, encoding: .utf8)
                }
            }
        case "quit":
            log(out, "quit")
            if let w = app.main.window, let sheet = w.attachedSheet { w.endSheet(sheet) }
            NSApp.terminate(nil)
            return
        default:
            // LAB-1595: the release harness's steps (checks, windows, gesture probes) live in SelfTestHarness.
            if SelfTestHarness.step(cmd, arg, app: app, out: out, done: { d in
                DispatchQueue.main.asyncAfter(deadline: .now() + d) { step(steps, i + 1, app: app, out: out) }
            }) { return }
            log(out, "  unknown step")
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { step(steps, i + 1, app: app, out: out) }
    }
}
