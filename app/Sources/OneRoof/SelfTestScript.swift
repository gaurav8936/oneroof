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
enum SelfTestScript {
    nonisolated(unsafe) static var perfBag: AnyCancellable?
    static func run(_ path: String, app: AppDelegate) {
        guard let text = try? String(contentsOfFile: path, encoding: .utf8) else { return }
        let steps = text.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("#") }
        let out = ProcessInfo.processInfo.environment["ONEROOF_SELFTEST_OUT"] ?? "/tmp/oneroof-script"
        log(out, "start \(steps.count) steps")
        // Perf probe: how often the model announces a change (each one re-renders every panel), per 5 s.
        var changes = 0
        perfBag = app.model.objectWillChange.sink { changes += 1 }
        Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { _ in log(out, "perf: \(changes) model changes in 5 s"); changes = 0 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { step(steps, 0, app: app, out: out) }
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
        case "menu": SelfTest.invokeMenu(arg)
        case "answer":
            if let d = m.openDecisions.first, let a = Answer(rawValue: arg) { m.answer(d, a) } else { log(out, "  no open decision") }
            delay = 1
        case "group": if let g = Grouping(rawValue: arg) { m.grouping = g } else { log(out, "  bad grouping") }
        case "chip": if let c = StatusChip(rawValue: arg) { app.main.win.statusFilter = c == .all ? nil : c }
        case "newsession": app.main.newSession(); delay = 2
        case "keys":
            // Type into whatever has focus in the key window or its sheet (e.g. the New work sheet's text field).
            let w = app.main.window?.attachedSheet ?? NSApp.keyWindow ?? app.main.window
            SelfTest.type(arg, into: w)
            delay = 1
        case "probe": log(out, "  " + app.main.terminalArea.debugState())
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
        default: log(out, "  unknown step")
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { step(steps, i + 1, app: app, out: out) }
    }
}
