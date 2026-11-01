import AppKit
import QuartzCore
import OneRoofCore

/// LAB-1595 / LAB-1596 · steps the release test harness (`scripts/oneroof-test`) needs on top of `SelfTestScript`:
/// explicit pass/fail checks, several windows, places, and the gesture probes (frame timing, terminal size changes).
/// Every check logs one line `  CHECK PASS|FAIL <what> (got <value>)`; every probe one line `  PROBE <label> k=v …`.
/// The harness reads those lines from the self-test log; nothing here changes how the app behaves.
///
///   expect <key> <op> <value>      check the app's state now (keys: `SelfTestHarness.state`; ops = != >= <= > < ~)
///   newwindow <name>               a new workspace window, as File › New Workspace Window… makes it (it becomes active)
///   switchwindow <name>            the window named <name> (or #n, the n-th) comes forward and acts for the next steps
///   selectindex <n>                select the n-th session of the active window (switch sessions)
///   mark <key>                     remember a state value; `expect <key> < @<key>` compares with it
///   gesturemark                    just before a one-shot gesture (focusstep, dragdivider): settle time counts from here
///   place <place>                  the rail's place (home needsYou sessions work machine loops learn)
///   search <query>                 rank the session catalog for <query> (as LAB-1585's search) → key searchhits
///   textcount <needle> <op> <n>    how often <needle> appears in the focused terminal's text (stacked copies after a resize)
///   hitch start · hitch stop <label>   frame timing on the main thread (display link) and terminal size changes in between
///   resizegesture <from> <to> <ms> the window's width from <from> to <to> pt, one step per display frame, over <ms>
///   windowsize <w> <h>             the window's frame size
///   scrollgesture <pt> <ms>        LAB-2115: the place's main list scrolled by <pt> (negative = up), one step per
///                                  display frame, over <ms> — a fast trackpad fling, as History's jerk (LAB-2105) showed
///   scrolltop                      LAB-2115: that list back to its top
///   barcheck [label]               LAB-1932: CHECK the toolbar title crosses no window button or toolbar item;
///                                  LAB-1938: and the right-hand group sits on one band colour
///   barsweep [widths…]             LAB-1932: barcheck in every place × rail open/folded × Focus step × width
enum SelfTestHarness {
    nonisolated(unsafe) static var searchHits = -1
    nonisolated(unsafe) static var probe: FrameProbe?
    nonisolated(unsafe) static var marks: [String: String] = [:]

    /// The state an `expect` line can check, by key.
    static func state(_ app: AppDelegate) -> [String: String] {
        let m = app.model, c = app.main
        let mine = m.items(in: m.active)
        var s: [String: String] = [
            "windows": "\(m.windows.count)",
            "openwindows": "\(MainWindowController.all.filter { $0.window != nil }.count)",
            "window": m.active.name,
            "sessions": "\(mine.count)",
            "live": "\(mine.filter { $0.liveAgent != nil }.count)",
            "allsessions": "\(m.sessionItems.filter { !$0.session.archived }.count)",   // LAB-1933: manual only
            "looprounds": "\(m.items.filter { SessionScope.isLoop($0.session) }.count)",
            "needsbadge": "\(m.needsYouBadge)",
            "alllive": "\(m.items.filter { $0.liveAgent != nil }.count)",
            "centre": m.active.centre.rawValue,
            "place": m.active.place.rawValue,
            "focusstep": "\(m.active.focusStep.rawValue)",
            "selected": m.selected?.session.name ?? "-",
            "decisions": "\(m.openDecisions.count)",
            "catalog": "\(m.catalogEntries().count)",
            "searchhits": "\(searchHits)",
            "gridchanges": "\(TerminalSurfaceView.gridChanges)",
            "termsurface": c?.terminalArea.focusedAllText() != nil ? "true" : "false",
        ]
        if let c {
            s["sessionsopen"] = c.sideItemRef.isCollapsed ? "false" : "true"
            s["railopen"] = c.v2RailItem?.isCollapsed == false ? "true" : "false"   // LAB-1829
            s["railwidth"] = c.v2RailItem.map { "\(Int($0.viewController.view.frame.width.rounded()))" } ?? "0"
            s["filesopen"] = c.filesItemRef.isCollapsed ? "false" : "true"
            if let w = c.window { s["width"] = "\(Int(w.frame.width))"; s["height"] = "\(Int(w.frame.height))" }
            s["paneswidth"] = c.splitView.arrangedSubviews.map { "\(Int($0.frame.width))" }.joined(separator: ",")
            s["baroverlap"] = "\(c.v2TitleOverlaps().count)"   // LAB-1932: what the toolbar title crosses (0 = clear)
        }
        return s
    }

    /// One check: `op` compares numerically when both sides are numbers, else as text (`~` = contains).
    static func compare(_ got: String, _ op: String, _ want: String) -> Bool {
        if let g = Double(got), let w = Double(want) {
            switch op {
            case "=", "==": return g == w
            case "!=": return g != w
            case ">=": return g >= w
            case "<=": return g <= w
            case ">": return g > w
            case "<": return g < w
            default: break
            }
        }
        switch op {
        case "=", "==": return got == want
        case "!=": return got != want
        case "~": return got.localizedCaseInsensitiveContains(want)
        default: return false
        }
    }

    /// Handles a harness step; false when `cmd` is not one. `done(delay)` continues the script.
    static func step(_ cmd: String, _ arg: String, app: AppDelegate, out: String, done: @escaping (Double) -> Void) -> Bool {
        let log = { (s: String) in SelfTestScript.log(out, s) }
        let parts = arg.split(separator: " ").map(String.init)
        switch cmd {
        case "expect":
            guard parts.count >= 3 else { log("  CHECK FAIL bad expect line '\(arg)'"); done(0.1); return true }
            let key = parts[0], op = parts[1], raw = parts[2...].joined(separator: " ")
            let want = raw.hasPrefix("@") ? (marks[String(raw.dropFirst())] ?? raw) : raw   // @key: the value `mark` saved
            let got = state(app)[key] ?? "(no key \(key))"
            log("  CHECK \(compare(got, op, want) ? "PASS" : "FAIL") \(key) \(op) \(want) (got \(got))")
            done(0.1)
        case "mark":   // remember a state value for a later `expect <key> <op> @<key>`
            marks[arg] = state(app)[arg]; log("  mark \(arg)=\(marks[arg] ?? "-")"); done(0.05)
        case "selectindex":   // select the n-th session (1 = first) of the active window, as a click on its row does
            let mine = app.model.items(in: app.model.active)
            if let n = Int(arg), mine.indices.contains(n - 1) { app.model.selectedId = mine[n - 1].id; log("  selected \(mine[n - 1].session.name)") }
            else { log("  no session #\(arg) (window has \(mine.count))") }
            done(1)
        case "newwindow":
            NotificationCenter.default.post(name: .newWorkspace, object: [arg.isEmpty ? "Test window" : arg, ""])
            done(2)
        case "switchwindow":
            let byIndex = arg.hasPrefix("#") ? Int(arg.dropFirst()).flatMap { n in app.model.windows.indices.contains(n - 1) ? app.model.windows[n - 1] : nil } : nil
            if let w = byIndex ?? app.model.windows.first(where: { $0.name == arg }) {
                NotificationCenter.default.post(name: .focusWorkspace, object: w.id)
            } else { log("  no window \(arg)") }
            done(1)
        case "place":
            if let p = Place(rawValue: arg) { app.main.v2Open(p) } else { log("  bad place \(arg)") }
            done(1.2)
        case "search":
            let rows = app.model.catalogSearchRows()
            DispatchQueue.global().async {
                let hits = SessionSearch.rank(arg, docs: SessionSearch.docs(rows))
                DispatchQueue.main.async {
                    searchHits = hits.count
                    log("  search '\(arg)' rows=\(rows.count) hits=\(hits.count)")
                    done(0.2)
                }
            }
        case "textcount":
            guard parts.count >= 3 else { log("  CHECK FAIL bad textcount line '\(arg)'"); done(0.1); return true }
            let needle = parts[0], op = parts[1], want = parts[2]
            func check(_ text: String, _ source: String) {
                let n = text.isEmpty ? -1 : text.components(separatedBy: needle).count - 1
                log("  CHECK \(compare("\(n)", op, want) ? "PASS" : "FAIL") text '\(needle)' count \(op) \(want) (got \(n), from \(source))")
                done(0.1)
            }
            // The terminal surface's whole text (what is drawn); without a surface (no GPU while the screen is locked)
            // the session's text as roofd holds it (its history and screen), which is where reprint piles land too.
            if let t = app.main.terminalArea.focusedAllText() { check(t, "surface"); return true }
            guard let pane = app.model.selected?.paneId else { check("", "no session"); return true }
            let r = app.model.runtime
            DispatchQueue.global().async {
                let t = (try? r.read(pane: pane, lines: 2000)) ?? ""
                DispatchQueue.main.async { check(t, "roofd") }
            }
        case "hitch":
            if parts.first == "start" {
                probe?.stop(); probe = FrameProbe(); probe?.start(in: app.main.window); done(0.05)
            } else {
                let label = parts.count > 1 ? parts[1] : "gesture"
                // Wait for the gesture to settle (terminal sizes and frames), then report.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                    if let p = probe { log("  PROBE \(label) " + p.report()); p.stop() }
                    probe = nil
                    done(0.2)
                }
            }
        case "resizegesture":
            let v = parts.compactMap { Double($0) }
            guard v.count == 3, let w = app.main.window else { log("  bad resizegesture"); done(0.1); return true }
            let frames = max(2, Int(v[2] / 1000 * 120))
            var k = 0
            probe?.markGestureStart()
            Timer.scheduledTimer(withTimeInterval: 1.0 / 120, repeats: true) { t in
                k += 1
                var f = w.frame; f.size.width = CGFloat(v[0] + (v[1] - v[0]) * Double(k) / Double(frames))
                w.setFrame(f, display: true)
                if k >= frames { t.invalidate(); probe?.markGestureEnd(); log("  resized \(Int(v[0]))→\(Int(v[1])) in \(frames) steps"); done(0.1) }
            }
        case "scrollgesture":   // LAB-2115 · LAB-2105
            let v = parts.compactMap { Double($0) }
            guard v.count == 2, let sv = mainScrollView(app.main.window?.contentView) else { log("  no scroll view to scroll"); done(0.1); return true }
            let frames = max(2, Int(v[1] / 1000 * 120)), step = CGFloat(v[0]) / CGFloat(frames)
            var k = 0
            probe?.markGestureStart()
            Timer.scheduledTimer(withTimeInterval: 1.0 / 120, repeats: true) { t in
                k += 1
                let clip = sv.contentView, maxY = max(0, (sv.documentView?.frame.height ?? 0) - clip.bounds.height)
                var o = clip.bounds.origin
                // A flipped document (SwiftUI's) grows downward; an unflipped one scrolls the other way.
                o.y = min(maxY, max(0, o.y + ((sv.documentView?.isFlipped ?? true) ? step : -step)))
                clip.scroll(to: o); sv.reflectScrolledClipView(clip)
                if k >= frames {
                    t.invalidate(); probe?.markGestureEnd()
                    log("  scrolled \(Int(v[0])) pt in \(frames) steps (at \(Int(clip.bounds.origin.y)) of \(Int(maxY)))"); done(0.1)
                }
            }
        case "scrolltop":   // LAB-2115
            if let sv = mainScrollView(app.main.window?.contentView) {
                let clip = sv.contentView
                clip.scroll(to: NSPoint(x: 0, y: (sv.documentView?.isFlipped ?? true) ? 0 : max(0, (sv.documentView?.frame.height ?? 0) - clip.bounds.height)))
                sv.reflectScrolledClipView(clip)
            }
            done(0.5)
        case "gesturemark":
            probe?.markGestureStart(); probe?.markGestureEnd()
            done(0.01)
        case "windowsize":
            let v = parts.compactMap { Double($0) }
            if v.count == 2, let w = app.main.window { var f = w.frame; f.size = NSSize(width: v[0], height: v[1]); w.setFrame(f, display: true) }
            done(1.5)
        case "barcheck":   // LAB-1932: the title crosses no window button or toolbar item, now
            app.main.v2PaintBand()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                barCheck(app: app, label: arg.isEmpty ? "now" : arg, out: out, log: log)
                done(0.1)
            }
        case "barsweep":   // LAB-1932: every place × rail open/folded × (Sessions: every Focus step) × width, a check each
            let widths = parts.compactMap { Double($0) }
            barSweep(app: app, widths: widths.isEmpty ? [1700, 1280, 1000, 800, 600] : widths, out: out, log: log, done: done)
        default:
            return false
        }
        return true
    }

    /// LAB-2115: the place's main list — the widest scroll view taller than its window (a vertical scroller, not the rail,
    /// a chip strip or a terminal), ties broken by the larger visible area.
    static func mainScrollView(_ root: NSView?) -> NSScrollView? {
        guard let root else { return nil }
        var best: NSScrollView?, bestArea: CGFloat = 0
        func walk(_ v: NSView) {
            if let sv = v as? NSScrollView, !v.isHiddenOrHasHiddenAncestor, let doc = sv.documentView,
               doc.frame.height > sv.contentView.bounds.height + 40, sv.frame.width > 300 {
                let a = sv.frame.width * sv.frame.height
                if a > bestArea { best = sv; bestArea = a }
            }
            v.subviews.forEach(walk)
        }
        walk(root)
        return best
    }

    /// LAB-1932 · one toolbar check: `CHECK PASS|FAIL toolbar clear <label>` with what the title crossed, if anything.
    @discardableResult
    static func barCheck(app: AppDelegate, label: String, out: String, log: (String) -> Void, snapOnFail: Bool = true) -> Bool {
        let c: MainWindowController = app.main
        let hits = c.v2TitleOverlaps()
        let span = c.v2TitleDrawnSpan.map { "\(Int($0.minX))…\(Int($0.maxX))" } ?? "hidden"
        let items = c.v2BarSpans(excludingTitle: true).map { "\($0.name) \(Int($0.minX))…\(Int($0.maxX))" }.joined(separator: ", ")
        log("  CHECK \(hits.isEmpty ? "PASS" : "FAIL") toolbar clear \(label) (title \(span); crosses \(hits.isEmpty ? "nothing" : hits.joined(separator: "+")); items \(items))")
        // LAB-1938: the right-hand group sits on one band colour.
        let group = c.v2RightGroupSpan
        let under = group.map { V2Layout.bandColours(under: $0, segments: c.v2BandSegments()) } ?? []
        let oneBand = under.count <= 1
        log("  CHECK \(oneBand ? "PASS" : "FAIL") toolbar group one band \(label) (group \(group.map { "\(Int($0.minX))…\(Int($0.maxX))" } ?? "none"); \(under.count) colour\(under.count == 1 ? "" : "s"))")
        let ok = hits.isEmpty && oneBand
        if !ok && snapOnFail { SelfTest.snapshot(app: app, to: out + "-barfail-" + label.replacingOccurrences(of: " ", with: "_")) }
        return ok
    }

    /// The sweep's cases, run one after another with time to lay out between them.
    static func barSweep(app: AppDelegate, widths: [Double], out: String, log: @escaping (String) -> Void, done: @escaping (Double) -> Void) {
        struct Case { let place: Place; let fold: Bool; let step: FocusStep?; let width: Double }
        var cases: [Case] = []
        for w in widths { for fold in [false, true] { for p in Place.allCases {
            if p == .sessions { for st in FocusStep.allCases { cases.append(Case(place: p, fold: fold, step: st, width: w)) } }
            else { cases.append(Case(place: p, fold: fold, step: nil, width: w)) }
        } } }
        var fails = 0
        func run(_ i: Int) {
            guard i < cases.count else {
                log("  CHECK \(fails == 0 ? "PASS" : "FAIL") toolbar sweep \(cases.count) cases (got \(fails) overlapping)")
                done(0.1); return
            }
            let k = cases[i]; let c: MainWindowController = app.main
            if let w = c.window, abs(w.frame.width - k.width) > 0.5 { var f = w.frame; f.size.width = CGFloat(k.width); w.setFrame(f, display: true) }
            if c.win.railFolded != k.fold { c.v2ToggleRail() }
            c.v2Open(k.place)
            if let st = k.step { c.v2SetStep(st) }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                let label = "\(k.place.rawValue) \(k.fold ? "folded" : "rail") \(k.step.map { "step\($0.rawValue)" } ?? "-") \(Int(app.main.window?.frame.width ?? 0))"
                if !barCheck(app: app, label: label, out: out, log: log) { fails += 1 }
                if k.place == .needsYou { SelfTest.snapshot(app: app, to: out + "-bar-" + label.replacingOccurrences(of: " ", with: "_")) }
                run(i + 1)
            }
        }
        run(0)
    }
}

/// Main-thread timing for a gesture (LAB-1563). Two clocks: a display link on the window's content view (one
/// callback per display frame, only while the window is on a screen that draws) and a 4 ms main-run-loop timer that
/// runs whatever the display does (a locked screen draws nothing). A late tick means the main thread was busy: that is
/// a hitch, what the hand feels as a stutter. Terminal size changes (LAB-1565) are the grid changes the terminal
/// surfaces made in the window; settle = the last one after the gesture ended.
final class FrameProbe: NSObject {
    private var link: CADisplayLink?
    private var frames: [CFTimeInterval] = []
    private var waits: [Double] = []
    private var running = false
    private let lock = NSLock()
    private var frameDur: CFTimeInterval = 1.0 / 120
    private var grid0 = 0
    private var t0: CFTimeInterval = 0
    private var gestureStart: CFTimeInterval?
    private var gestureEnd: CFTimeInterval?

    func start(in window: NSWindow?) {
        grid0 = TerminalSurfaceView.gridChanges
        t0 = CACurrentMediaTime()
        // Main-thread responsiveness: a background thread posts a block to the main queue every 4 ms and times how long it
        // waits to run. A busy main thread delays it; an idle one runs it at once. (A main-run-loop timer read gaps that
        // were the system holding the timer back while the screen was locked, with the main thread idle: LAB-1596.)
        running = true
        let th = Thread { [weak self] in
            while let me = self, me.running {
                let sent = CACurrentMediaTime(), done = DispatchSemaphore(value: 0)
                DispatchQueue.main.async { done.signal() }
                _ = done.wait(timeout: .now() + 10)
                let waited = (CACurrentMediaTime() - sent) * 1000
                me.lock.lock(); me.waits.append(waited); me.lock.unlock()
                usleep(4_000)
            }
        }
        th.qualityOfService = .userInteractive
        th.start()
        guard let view = window?.contentView else { return }
        let l = view.displayLink(target: self, selector: #selector(tick(_:)))
        l.add(to: .main, forMode: .common)
        link = l
    }

    @objc private func tick(_ l: CADisplayLink) {
        frames.append(CACurrentMediaTime())
        let d = l.targetTimestamp - l.timestamp
        if d > 0.002 && d < 0.05 { frameDur = d }
    }

    func markGestureStart() { gestureStart = CACurrentMediaTime(); grid0 = TerminalSurfaceView.gridChanges }
    func markGestureEnd() { gestureEnd = CACurrentMediaTime() }

    func stop() { link?.invalidate(); link = nil; running = false }

    private static func gaps(_ s: [CFTimeInterval]) -> [Double] { zip(s.dropFirst(), s).map { ($0 - $1) * 1000 }.sorted() }
    private static func pct(_ v: [Double], _ p: Double) -> Double { v.isEmpty ? 0 : v[min(v.count - 1, Int(Double(v.count) * p))] }

    func report() -> String {
        let now = CACurrentMediaTime()
        let fd = frameDur * 1000
        lock.lock(); let g = waits.sorted(); lock.unlock()
        let f = Self.gaps(frames)
        // Hitch time: for every wait longer than a frame, the part beyond the frame (what shows as a dropped frame).
        let hitch = g.filter { $0 > fd }.reduce(0) { $0 + ($1 - fd) }
        let span = max(0.001, now - t0)
        let changes = TerminalSurfaceView.gridChanges - grid0
        let last = TerminalSurfaceView.lastGridChange
        let end = gestureEnd ?? t0
        let settle = last > end ? (last - end) * 1000 : 0
        return String(format: "frames=%d frame_ms=%.1f frame_p50_ms=%.1f frame_p99_ms=%.1f gap_p50_ms=%.1f gap_p99_ms=%.1f longest_ms=%.1f hitch_ms_per_s=%.1f stalls_50=%d size_changes=%d settle_ms=%.0f gesture_ms=%.0f",
                      frames.count, fd, Self.pct(f, 0.5), Self.pct(f, 0.99), Self.pct(g, 0.5), Self.pct(g, 0.99), g.last ?? 0, hitch / span,
                      g.filter { $0 >= 50 }.count, changes, settle, ((gestureEnd ?? now) - (gestureStart ?? t0)) * 1000)
    }
}
