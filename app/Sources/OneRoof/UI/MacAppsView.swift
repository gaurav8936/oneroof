import AppKit
import SwiftUI
import OneRoofCore

/// LAB-544: Resources › This Mac, by app. Every app's memory and CPU with all its processes (helpers and the XPC
/// services it started count to it, as in Activity Monitor), heaviest first. An app opens to its processes, where a
/// Chrome or Electron helper says what it is (tab or site, extension, GPU …). Apps can be quit and single processes
/// ended from here, each after a confirmation; One Roof's own leftovers (a local model a force-quit left running, a
/// roofd this One Roof does not use) are called out at the top with a Stop button.
/// LAB-2052: colours you can read (text2 for every piece of information, a visible track under every bar, warning rows
/// tinted with a leading amber bar, the process panel at full surface2). LAB-2053: an open browser shows its windows and
/// tabs, then only the helpers "using a lot" (over 250 MB or 10 % CPU, held 30 s), one line about memory per tab, and
/// "All processes (N)" for today's full list. LAB-2054 / LAB-2060: tabs and windows close from here (Chrome, Safari).
struct MacAppsCard: View {
    @Environment(\.theme) private var t
    @ObservedObject var res: ResourceMonitor
    @State private var open: Set<String> = []
    @State private var showAll = false
    @State private var showAllProcs: Set<String> = []
    /// LAB-853: browsers whose renderer ("Tab or site") processes are listed one by one (folded into one row otherwise).
    @State private var showRenderers: Set<String> = []
    @State private var pending: Pending?
    @State private var message: String?
    /// LAB-2053: browsers whose full process list is open ("All processes"); closed by default, not remembered.
    @State private var allOpen: Set<String> = []
    /// LAB-2053: when each pid was last seen over a "Using a lot" line, so a process that drops below stays 30 s.
    @State private var bigSince: [Int32: Date] = [:]

    static let firstApps = 12
    static let firstProcs = 25

    /// An action waiting for its confirmation.
    enum Pending: Identifiable {
        case quit(MacAppGroup, force: Bool)
        case end(MacProc, force: Bool)
        var id: String {
            switch self {
            case .quit(let g, let f): return "quit:\(g.id):\(f)"
            case .end(let p, let f): return "end:\(p.pid):\(f)"
            }
        }
    }

    var body: some View { watchedBody.modifier(WatchesResources(res: res)) }   // LAB-1333
    @ViewBuilder private var watchedBody: some View {
        Card {
            VStack(alignment: .leading, spacing: 0) {
                if let b = res.mac { content(b) } else {
                    header(detail: "reading…")
                    Hairline()
                    Text("Reading every app's memory and CPU…").ui(12.5).foregroundStyle(t.text2.color).padding(14)
                }
            }
        }
        .confirmationDialog(dialogTitle, isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } }),
                            presenting: pending) { p in
            Button(confirmLabel(p), role: .destructive) { run(p) }
            Button("Cancel", role: .cancel) { pending = nil }
        } message: { p in Text(dialogMessage(p)) }
        .onAppear {
            if SelfTestMacFixture.mode != nil {
                open.insert(SelfTestMacFixture.chromeId)
                if SelfTestMacFixture.allProcesses { allOpen.insert(SelfTestMacFixture.chromeId) }
            }
            noteBig(res.mac)
        }
        .onChange(of: res.mac) { _, b in noteBig(b) }
    }

    /// LAB-2053: stamp the browsers' helpers that are over a line now.
    private func noteBig(_ b: MacBreakdown?) {
        guard let b else { return }
        let procs = b.groups.filter { BrowserTabs.family(appName: $0.name) != nil }.flatMap(\.procs)
        bigSince = BrowserTabs.bigSeen(procs, since: bigSince, now: Date())
    }

    @ViewBuilder private func content(_ b: MacBreakdown) -> some View {
        let groups = showAll ? b.groups : Array(b.groups.prefix(Self.firstApps))
        header(detail: detail(b))
        Hairline()
        if let message {
            HStack(spacing: 8) {
                Text(message).ui(12).foregroundStyle(t.needsText.color).fixedSize(horizontal: false, vertical: true)
                Spacer()
                Button("✕") { self.message = nil }.buttonStyle(.plain).ui(11).foregroundStyle(t.text2.color).accessibilityLabel("Dismiss")
            }
            .padding(.horizontal, 14).padding(.vertical, 8)
            Hairline()
        }
        ForEach(b.leftovers) { p in
            leftover(p)
            Hairline()
        }
        LazyVStack(spacing: 0) {
            ForEach(groups) { g in
                appRow(g, b)
                if open.contains(g.id) { processes(g) }
                Hairline().padding(.leading, 14)
            }
        }
        HStack(spacing: 10) {
            if b.groups.count > Self.firstApps {
                Button(showAll ? "Show the top \(Self.firstApps)" : "Show all \(b.groups.count) apps") { showAll.toggle() }
                    .buttonStyle(.link).ui(12)
            }
            Spacer()
            Text(footnote(b)).ui(11).foregroundStyle(t.text2.color).lineLimit(2).multilineTextAlignment(.trailing)
        }
        .padding(.horizontal, 14).padding(.vertical, 9)
    }

    private func header(detail: String) -> some View {
        HStack(spacing: 8) {
            Text("This Mac, by app").ui(13.5, .semibold).foregroundStyle(t.text.color).lineLimit(1)
            Text(detail).ui(12).foregroundStyle(t.text2.color).lineLimit(1).truncationMode(.tail)
            Spacer()
        }
        .padding(.horizontal, 14).frame(height: 36)
        .accessibilityAddTraits(.isHeader)
    }

    private func detail(_ b: MacBreakdown) -> String {
        var s = "\(b.groups.count) apps · \(b.processCount) processes"
        if let m = b.mac { s = "\(ResourceFormat.bytes(m.used)) of \(ResourceFormat.bytes(m.total)) in use · swap \(ResourceFormat.bytes(m.swapUsed)) · " + s }
        return s
    }

    private func footnote(_ b: MacBreakdown) -> String {
        var s = "\(b.unreadable) system and other users' processes are not counted (macOS shows them to administrators only)"
        if b.uncounted > 0 { s += " · \(ResourceFormat.bytes(b.uncounted)) in use outside the apps listed" }
        return s
    }

    // MARK: Leftovers

    /// LAB-2052: a warning row: `now` at 0.14 with a 3 pt amber bar on its leading edge; the name in text, the
    /// explanation in text2, the amount and ● in the amber text token (≥ 4.5:1 on the tint).
    private func leftover(_ p: MacProc) -> some View {
        let m = t.resourceMarks
        return HStack(spacing: 10) {
            Text("●").ui(11).foregroundStyle(m.nowText.color)
            VStack(alignment: .leading, spacing: 2) {
                Text(p.kind ?? p.name).ui(12.5, .semibold).foregroundStyle(t.text.color).lineLimit(1)
                Text("One Roof did not start this one and nothing uses it; it keeps its memory until stopped. One Roof starts a fresh one when it needs it.")
                    .ui(11.5).foregroundStyle(t.text2.color).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            Text(ResourceFormat.bytes(p.footprint)).ui(12.5, .semibold, mono: true).foregroundStyle(m.nowText.color)
            Button("Stop") { pending = .end(p, force: false) }.controlSize(.small)
                .accessibilityLabel("Stop \(p.kind ?? p.name), \(ResourceFormat.bytes(p.footprint))")
        }
        .padding(.horizontal, 14).padding(.vertical, 9)
        .background(m.nowTint.color)
        .overlay(alignment: .leading) { Rectangle().fill(m.nowBar.color).frame(width: 3).accessibilityHidden(true) }
        .accessibilityElement(children: .combine)
    }

    // MARK: Apps

    private func appRow(_ g: MacAppGroup, _ b: MacBreakdown) -> some View {
        let isOpen = open.contains(g.id)
        let share = Double(g.footprint) / Double(max(b.mac?.used ?? b.counted, 1))
        return HStack(spacing: 10) {
            Button {
                if isOpen { open.remove(g.id) } else { open.insert(g.id) }
            } label: {
                HStack(spacing: 10) {
                    Text(isOpen ? "▾" : "▸").ui(10).foregroundStyle(t.text3.color).frame(width: 10)
                    AppIcon(bundlePath: g.bundlePath).frame(width: 20, height: 20)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(g.name).ui(13, .semibold).foregroundStyle(t.text.color).lineLimit(1)
                        Text(subtitle(g)).ui(11).foregroundStyle(t.text2.color).lineLimit(1)
                    }
                    Spacer(minLength: 8)
                    Meter(fraction: share, colour: t.resourceMarks.bar).frame(width: 70)
                    Text(ResourceFormat.cpu(g.cpu)).ui(12.5, mono: true).foregroundStyle(t.text2.color).frame(width: 58, alignment: .trailing)
                    Text(ResourceFormat.bytes(g.footprint)).ui(12.5, .semibold, mono: true).foregroundStyle(t.text.color)
                        .frame(width: 72, alignment: .trailing)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(g.name), \(g.procs.count) processes, memory \(ResourceFormat.bytes(g.footprint)), CPU \(ResourceFormat.cpu(g.cpu))")
            .accessibilityHint(isOpen ? "Hides its processes" : "Shows its processes")
            Group {
                if g.quittable {
                    Menu {
                        Button("Quit \(g.name)…") { pending = .quit(g, force: false) }
                        Button("Force quit \(g.name)…") { pending = .quit(g, force: true) }
                    } label: { Text("Quit").ui(11.5, .medium).foregroundStyle(t.text.color) }
                    primaryAction: { pending = .quit(g, force: false) }
                    .menuStyle(.borderlessButton).fixedSize()
                    .help("Quit \(g.name) (it may ask to save first). The arrow offers Force quit.")
                    .accessibilityLabel("Quit \(g.name)")
                } else {
                    Color.clear
                }
            }
            .frame(width: 56, alignment: .trailing)
        }
        .padding(.horizontal, 14).padding(.vertical, 7)
        .hoverHighlight(over: t.surface)   // LAB-2052: a hover you can see
    }

    private func subtitle(_ g: MacAppGroup) -> String {
        let n = g.procs.count
        var s = "\(n) process\(n == 1 ? "" : "es")"
        let tabs = g.procs.filter { $0.kind == "Tab or site" }.count
        if tabs > 0 { s += " · \(tabs) tabs or sites" }
        if g.isOneRoof { s += " · app, roofd, sessions and the local model" }
        return s
    }

    // MARK: Processes

    @ViewBuilder private func processes(_ g: MacAppGroup) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if let family = BrowserTabs.family(appName: g.name) {
                browserProcesses(g, family)
            } else {
                processList(g)
            }
        }
        .padding(.leading, 54).padding(.trailing, 14).padding(.vertical, 8)
        .background(t.resourceMarks.panel.color)   // LAB-2052: full strength (was surface2 at 50 %)
    }

    /// LAB-2053: an open browser, top to bottom: its windows and tabs; the helpers using a lot (only when one is); one
    /// line about memory per tab; "All processes (N)", which opens today's full list.
    @ViewBuilder private func browserProcesses(_ g: MacAppGroup, _ family: BrowserTabs.Family) -> some View {
        BrowserTabsSection(app: g.name, family: family, mainPid: g.mainPid,
                           bundleId: g.bundlePath.flatMap { Bundle(path: $0)?.bundleIdentifier },
                           onForceQuit: g.quittable ? { pending = .quit(g, force: true) } : nil,
                           onClosed: { res.soon() })
            .padding(.bottom, 8)
        let big = BrowserTabs.bigProcesses(g.procs, since: bigSince, now: Date(), mainPid: g.mainPid)
        if !big.isEmpty {
            Text("Using a lot · over 250 MB or 10 % CPU").ui(11.5, .semibold).foregroundStyle(t.text.color)
                .padding(.bottom, 2)
                .accessibilityAddTraits(.isHeader)
            ForEach(big) { p in bigRow(p) }
                .padding(.bottom, 0)
            Color.clear.frame(height: 6)
        }
        taskManagerLine(g)
        let isAll = allOpen.contains(g.id)
        Button {
            if isAll { allOpen.remove(g.id) } else { allOpen.insert(g.id) }
        } label: {
            HStack(spacing: 6) {
                Text(isAll ? "▾" : "▸").ui(10).foregroundStyle(t.text3.color).frame(width: 10)
                Text("All processes (\(g.procs.count))").ui(11.5, .medium).foregroundStyle(t.accentText.color)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.top, 6)
        .accessibilityLabel("All processes, \(g.procs.count)")
        .accessibilityAddTraits(.isButton)
        .accessibilityHint(isAll ? "Hides the full process list" : "Shows every process with its pid, CPU, memory and End")
        if isAll {
            processList(g).padding(.top, 6)
        }
    }

    /// LAB-2053: "Memory per tab: Google Chrome's Task Manager (⇧Esc)", today's paragraph in the ⓘ tooltip, and Show.
    private func taskManagerLine(_ g: MacAppGroup) -> some View {
        let full = BrowserTabs.CloseCopy.taskManager(g.name)
        return HStack(spacing: 6) {
            Text("Memory per tab: \(g.name)'s Task Manager (⇧Esc)").ui(11.5).foregroundStyle(t.text2.color).lineLimit(2)
            Image(systemName: "info.circle").font(.system(size: 11.5)).foregroundStyle(t.text2.color)
                .help(full)
                .accessibilityLabel("About memory per tab")
                .accessibilityValue(full)
            if let pid = g.mainPid {
                Button("Show \(g.name)") { NSRunningApplication(processIdentifier: pid)?.activate() }
                    .buttonStyle(.link).ui(11.5).fixedSize()
            }
            Spacer(minLength: 0)
        }
    }

    /// LAB-2053: one helper or renderer over a line: what it is, CPU, memory, End ▾ (today's confirmations).
    private func bigRow(_ p: MacProc) -> some View {
        let what = p.kind == BrowserTabs.rendererKind ? "A tab or site (macOS does not say which)" : (p.kind ?? p.name)
        return HStack(spacing: 8) {
            Text(what).ui(12, .medium).foregroundStyle(t.text.color).lineLimit(1).truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
                .help("\(p.name), pid \(p.pid)\n\(p.path)")
            Text(ResourceFormat.cpu(p.cpu)).ui(11.5, mono: true).foregroundStyle(((p.cpu ?? 0) > BrowserTabs.bigCPU ? t.text : t.text2).color)
                .frame(width: 50, alignment: .trailing)
            Text(ResourceFormat.bytes(p.footprint)).ui(11.5, .semibold, mono: true).foregroundStyle(t.text.color).frame(width: 66, alignment: .trailing)
            endMenu(p).frame(width: 44, alignment: .trailing)
        }
        .padding(.vertical, 3)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(p.kind == BrowserTabs.rendererKind ? "A tab or site" : (p.kind ?? p.name)), process \(p.pid), memory \(ResourceFormat.bytes(p.footprint)), CPU \(ResourceFormat.cpu(p.cpu))")
    }

    /// Today's process list (every app; for a browser it sits under "All processes"): the breakdown by kind, a browser's
    /// renderers folded into one row, every process with pid, CPU, memory and End, the first 25 then "Show all".
    @ViewBuilder private func processList(_ g: MacAppGroup) -> some View {
        let all = showAllProcs.contains(g.id)
        // LAB-853: a browser's renderers are one row ("78 tabs or sites · 6.2 GB") until opened: macOS cannot say which
        // tab each one is, and the tab names are listed above them instead.
        let browser = BrowserTabs.family(appName: g.name)
        let rend = BrowserTabs.renderers(g.procs)
        let folded = browser != nil && rend.count > 1
        let listed = folded && !showRenderers.contains(g.id) ? g.procs.filter { $0.kind != BrowserTabs.rendererKind } : g.procs
        let procs = all ? listed : Array(listed.prefix(Self.firstProcs))
        let kinds = kindSummary(g)
        if !kinds.isEmpty {
            Text(kinds).ui(11.5).foregroundStyle(t.text2.color).fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 6)
        }
        if browser == nil, g.procs.contains(where: { $0.kind == "Tab or site" }) {
            HStack(spacing: 6) {
                Text("Tab names: \(g.name) lists each tab with its memory in its own Task Manager (⇧Esc in \(g.name), or Window › Task Manager), and can end a tab there. Ending a \"Tab or site\" here shows that tab as crashed until reloaded.")
                    .ui(11.5).foregroundStyle(t.text2.color).fixedSize(horizontal: false, vertical: true)
                if let pid = g.mainPid {
                    Button("Show \(g.name)") { NSRunningApplication(processIdentifier: pid)?.activate() }
                        .buttonStyle(.link).ui(11.5).fixedSize()
                }
            }
            .padding(.bottom, 6)
        }
        if folded { renderersRow(g, rend) }
        ForEach(procs) { p in procRow(p) }
        if listed.count > Self.firstProcs {
            Button(all ? "Show the top \(Self.firstProcs)" : "Show all \(listed.count) processes") {
                if all { showAllProcs.remove(g.id) } else { showAllProcs.insert(g.id) }
            }
            .buttonStyle(.link).ui(11.5).padding(.top, 4)
        }
    }

    /// LAB-853: a browser's renderer processes as one row; it opens to list them (each can still be ended).
    private func renderersRow(_ g: MacAppGroup, _ r: (count: Int, bytes: UInt64)) -> some View {
        let isOpen = showRenderers.contains(g.id)
        let cpu = g.procs.filter { $0.kind == BrowserTabs.rendererKind }.reduce(0) { $0 + ($1.cpu ?? 0) }
        return Button {
            if isOpen { showRenderers.remove(g.id) } else { showRenderers.insert(g.id) }
        } label: {
            HStack(spacing: 8) {
                Text(isOpen ? "▾" : "▸").ui(10).foregroundStyle(t.text3.color).frame(width: 10)
                VStack(alignment: .leading, spacing: 0) {
                    Text("\(r.count) tabs or sites").ui(12, .medium).foregroundStyle(t.text.color).lineLimit(1)
                    Text(isOpen ? "renderer processes, listed below · macOS does not say which tab each one is"
                                : "renderer processes, one per tab or site · macOS does not say which is which · show them")
                        .ui(10.5).foregroundStyle(t.text2.color).lineLimit(1).truncationMode(.tail)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Text(ResourceFormat.cpu(cpu)).ui(11.5, mono: true).foregroundStyle(t.text2.color).frame(width: 50, alignment: .trailing)
                Text(ResourceFormat.bytes(r.bytes)).ui(11.5, .semibold, mono: true).foregroundStyle(t.text.color).frame(width: 66, alignment: .trailing)
                Color.clear.frame(width: 44)
            }
            .padding(.vertical, 3)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .hoverHighlight(over: t.resourceMarks.panel)
        .accessibilityLabel("\(r.count) tabs or sites, renderer processes, memory \(ResourceFormat.bytes(r.bytes))")
        .accessibilityHint(isOpen ? "Hides the renderer processes" : "Lists the renderer processes one by one")
    }

    /// "67 Tab or site 10 GB · GPU 690 MB · …", heaviest first, for apps whose processes have kinds.
    private func kindSummary(_ g: MacAppGroup) -> String {
        var by: [String: (n: Int, bytes: UInt64)] = [:]
        for p in g.procs { if let k = p.kind { by[k, default: (0, 0)].n += 1; by[k]!.bytes += p.footprint } }
        guard !by.isEmpty else { return "" }
        return by.sorted { $0.value.bytes > $1.value.bytes }.map { k, v in
            (v.n > 1 ? "\(v.n) × " : "") + "\(k) \(ResourceFormat.bytes(v.bytes))"
        }.joined(separator: " · ")
    }

    private func procRow(_ p: MacProc) -> some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 0) {
                Text(p.kind ?? p.name).ui(12, p.kind == nil ? .regular : .medium).foregroundStyle(t.text.color).lineLimit(1)
                if p.kind != nil { Text(p.name).ui(10.5, mono: true).foregroundStyle(t.text2.color).lineLimit(1).truncationMode(.middle) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .help(p.path)
            Text("\(p.pid)").ui(11, mono: true).foregroundStyle(t.text2.color).frame(width: 56, alignment: .trailing)
            Text(ResourceFormat.cpu(p.cpu)).ui(11.5, mono: true).foregroundStyle(t.text2.color).frame(width: 50, alignment: .trailing)
            Text(ResourceFormat.bytes(p.footprint)).ui(11.5, .semibold, mono: true).foregroundStyle(t.text.color).frame(width: 66, alignment: .trailing)
            endMenu(p).frame(width: 44, alignment: .trailing)
        }
        .padding(.vertical, 3)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(p.kind ?? p.name), process \(p.pid), CPU \(ResourceFormat.cpu(p.cpu)), memory \(ResourceFormat.bytes(p.footprint))")
    }

    /// End ▾ Force end, each after today's confirmation.
    @ViewBuilder private func endMenu(_ p: MacProc) -> some View {
        if p.endable {
            Menu {
                Button("End…") { pending = .end(p, force: false) }
                Button("Force end…") { pending = .end(p, force: true) }
            } label: { Text("End").ui(11, .medium).foregroundStyle(t.text2.color) }
            primaryAction: { pending = .end(p, force: false) }
            .menuStyle(.borderlessButton).fixedSize()
            .help("End this process (it may tidy up first). The arrow offers Force end.")
            .accessibilityLabel("End \(p.kind ?? p.name), process \(p.pid)")
        } else {
            Color.clear
        }
    }

    // MARK: Confirm and run

    private var dialogTitle: String {
        switch pending {
        case .quit(let g, let f)?: return (f ? "Force quit " : "Quit ") + g.name + "?"
        case .end(let p, let f)?: return (f ? "Force end " : "End ") + (p.kind ?? p.name) + "?"
        case nil: return ""
        }
    }

    private func confirmLabel(_ p: Pending) -> String {
        switch p {
        case .quit(_, let f): return f ? "Force quit" : "Quit"
        case .end(_, let f): return f ? "Force end" : "End"
        }
    }

    private func dialogMessage(_ p: Pending) -> String {
        switch p {
        case .quit(let g, let f):
            return "Frees about \(ResourceFormat.bytes(g.footprint)). " + (f ? "Force quit closes it at once: anything unsaved is lost." : "\(g.name) may ask to save first.")
        case .end(let p, let f):
            var s = "\(p.name), pid \(p.pid), uses \(ResourceFormat.bytes(p.footprint)). "
            if p.kind == "Tab or site" { s += "Its tab or site stops and shows as crashed until reloaded. " }
            if p.kind?.hasPrefix("Local model") == true { s += "One Roof starts a fresh local model the next time it needs one. " }
            s += f ? "Force end stops it at once." : "It gets the chance to tidy up first."
            return s
        }
    }

    private func run(_ p: Pending) {
        pending = nil
        switch p {
        case .quit(let g, let f): message = res.quit(g, force: f)
        case .end(let proc, let f): message = res.end(proc, force: f)
        }
    }
}

/// LAB-554 / LAB-853: a browser's open tabs, read from the browser over Apple Events, by window (as the owner sees them
/// in the browser) or by site. macOS does not say which renderer process is which tab, so this list stands above the
/// processes. When the section appears it asks macOS, without prompting, whether One Roof may already read the browser:
/// if so the tabs load at once; if macOS has not asked yet, one line says why and offers the ask ("Show tab names"); if
/// the owner said no, it says where to allow it. Never an empty list without a reason. Clicking a tab brings it forward.
/// LAB-2054 (Chrome) / LAB-2060 (Safari): a tab's ✕ (on hover), right-click, ⌫ or VoiceOver closes it; "Close window"
/// closes a window (asking first when it has 2 or more tabs). Closing goes through the browser's own scripting with the
/// Automation permission reading already has; the scripts never launch the browser and close nothing that changed since
/// the list was read. A browser that does not answer in 10 s offers Force quit. Other browsers list their tabs only.
struct BrowserTabsSection: View {
    @Environment(\.theme) private var t
    let app: String
    let family: BrowserTabs.Family
    let mainPid: Int32?
    var bundleId: String? = nil
    /// LAB-2054: opens the app row's Force quit confirmation (a browser that did not answer).
    var onForceQuit: (() -> Void)? = nil
    /// LAB-2054: something closed: the process list refreshes sooner.
    var onClosed: (() -> Void)? = nil
    @State private var state: Load = .idle
    @State private var showAllSites = false
    @State private var showAllIn: Set<String> = []
    /// LAB-2054: what the last close did (one line under the header).
    @State private var note: Note?
    /// LAB-2054: a window waiting for "Close window?".
    @State private var askWindow: BrowserWindowTabs?
    /// Set after the first successful read: later opens read the tabs straight away.
    @AppStorage("resources.browserTabs.on", store: Prefs.viewState) private var on = false   // QA M6: a self-test never writes the real settings
    /// "windows" (default) or "sites".
    @AppStorage("resources.browserTabs.group", store: Prefs.viewState) private var grouping = "windows"

    static let firstSites = 8
    static let firstTabs = 12

    enum Load {
        case idle, checking, loading
        /// macOS has not asked the owner yet: the first read asks.
        case notAsked
        case loaded([BrowserTab], Date)
        case failed(BrowserTabs.Failure)
    }

    struct Note: Equatable {
        var text: String
        var error = false
        /// The browser did not answer: offer Force quit.
        var forceQuit = false
    }

    private var support: BrowserTabs.CloseSupport { BrowserTabs.closeSupport(appName: app) }
    private var closes: Bool { support == .closes }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text("Open tabs").ui(12, .semibold).foregroundStyle(t.text.color)
                Text(summary).ui(11.5).foregroundStyle(t.text2.color).lineLimit(1).truncationMode(.tail)
                Spacer(minLength: 8)
                switch state {
                case .loading, .checking: ProgressView().controlSize(.small)
                case .loaded:
                    Segmented(options: [("windows", "By window"), ("sites", "By site")], selection: $grouping)
                        .fixedSize().accessibilityLabel("Group tabs")
                    Button("Refresh") { load() }.buttonStyle(.link).ui(11.5)
                case .failed: Button("Refresh") { load() }.buttonStyle(.link).ui(11.5)
                default: EmptyView()
                }
            }
            if let note { noteLine(note) }
            content
            if case .loaded(let tabs, _) = state, !tabs.isEmpty, case .readOnly(let why) = support {
                Text(why).ui(11).foregroundStyle(t.text2.color).fixedSize(horizontal: false, vertical: true)
            }
        }
        .onAppear(perform: appear)
        .confirmationDialog(askWindow.map { BrowserTabs.CloseCopy.confirmTitle(window: $0.number, app: app) } ?? "",
                            isPresented: Binding(get: { askWindow != nil }, set: { if !$0 { askWindow = nil } }),
                            presenting: askWindow) { w in
            Button("Close window", role: .destructive) { askWindow = nil; closeWindow(w, asked: true) }
            Button("Cancel", role: .cancel) { askWindow = nil }
        } message: { w in Text(BrowserTabs.CloseCopy.confirmMessage(tabs: w.tabs.count, app: app)) }
    }

    private func noteLine(_ n: Note) -> some View {
        HStack(spacing: 8) {
            Text(n.text).ui(11.5).foregroundStyle((n.error ? t.needsText : t.text).color).fixedSize(horizontal: false, vertical: true)
            if n.forceQuit, let onForceQuit {
                Button("Force quit \(app)…") { onForceQuit() }.controlSize(.small).fixedSize()
                    .accessibilityLabel("Force quit \(app)")
            }
            Spacer(minLength: 4)
            Button("✕") { note = nil }.buttonStyle(.plain).ui(11).foregroundStyle(t.text2.color).accessibilityLabel("Dismiss")
        }
        .accessibilityElement(children: .contain)
    }

    private var summary: String {
        switch state {
        case .idle, .notAsked: return "names and sites of every tab, read from \(app)"
        case .checking: return "checking whether One Roof may read \(app)…"
        case .loading: return "asking \(app)…"
        case .failed: return ""
        case .loaded(let tabs, let at):
            let windows = Set(tabs.map(\.windowId)).count
            let sites = Set(tabs.map(\.site)).count
            return "\(tabs.count) tab\(tabs.count == 1 ? "" : "s") in \(windows) window\(windows == 1 ? "" : "s") · \(sites) site\(sites == 1 ? "" : "s") · read \(at.formatted(date: .omitted, time: .shortened))"
        }
    }

    @ViewBuilder private var content: some View {
        switch state {
        case .idle, .notAsked:
            HStack(spacing: 8) {
                Text("To name each tab, One Roof asks \(app) for its open tabs; macOS asks you once to allow it.")
                    .ui(11.5).foregroundStyle(t.text2.color).fixedSize(horizontal: false, vertical: true)
                Button("Show tab names") { load() }.controlSize(.small).fixedSize()
                    .help("Asks \(app) for its open tabs. The first time, macOS asks whether One Roof may control \(app).")
            }
        case .failed(.notAllowed):
            HStack(spacing: 6) {
                Text("macOS did not let One Roof read \(app)'s tabs. Allow it in System Settings › Privacy & Security › Automation › One Roof › \(app), then Refresh.")
                    .ui(11.5).foregroundStyle(t.needsText.color).fixedSize(horizontal: false, vertical: true)
                Button("Open Automation settings") {
                    if let u = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation") { NSWorkspace.shared.open(u) }
                }
                .buttonStyle(.link).ui(11.5).fixedSize()
            }
        case .failed(.failed(let why)):
            Text("Could not read \(app)'s tabs: \(why)").ui(11.5).foregroundStyle(t.needsText.color).fixedSize(horizontal: false, vertical: true)
        case .loaded(let tabs, _) where tabs.isEmpty:
            Text("\(app) answered with no open tabs (it may have no windows open).").ui(11.5).foregroundStyle(t.text2.color)
        case .loaded(let tabs, _):
            if grouping == "sites" { bySite(tabs) } else { byWindow(tabs) }
        default: EmptyView()
        }
    }

    // MARK: By window (LAB-853)

    private func byWindow(_ tabs: [BrowserTab]) -> some View {
        let windows = BrowserTabs.windows(tabs)
        return VStack(alignment: .leading, spacing: 8) {
            ForEach(windows) { w in
                let all = showAllIn.contains(w.id)
                let shown = all ? w.tabs : Array(w.tabs.prefix(Self.firstTabs))
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 6) {
                        Text("Window \(w.number)").ui(12, .semibold).foregroundStyle(t.text.color)
                        Text("\(w.tabs.count) tab\(w.tabs.count == 1 ? "" : "s")").ui(11).foregroundStyle(t.text2.color)
                        if closes {
                            // LAB-2054: close the whole window (asks first with 2 or more tabs).
                            Button("Close window") { closeWindow(w, asked: false) }
                                .buttonStyle(.link).ui(11)
                                .help(BrowserTabs.closeWindowAsks(tabs: w.tabs.count)
                                      ? "Closes this window and its \(w.tabs.count) tabs in \(app) (asks first)"
                                      : "Closes this window in \(app)")
                                .accessibilityLabel("Close window, \(w.tabs.count) tab\(w.tabs.count == 1 ? "" : "s")")
                        }
                    }
                    .accessibilityElement(children: .contain)
                    .accessibilityLabel("Window \(w.number), \(w.tabs.count) tab\(w.tabs.count == 1 ? "" : "s")")
                    .accessibilityAddTraits(.isHeader)
                    ForEach(shown) { tab in row(tab, site: true) }
                    if w.tabs.count > Self.firstTabs {
                        Button(all ? "Show the first \(Self.firstTabs)" : "Show all \(w.tabs.count) tabs") {
                            if all { showAllIn.remove(w.id) } else { showAllIn.insert(w.id) }
                        }
                        .buttonStyle(.link).ui(11).padding(.leading, 16)
                    }
                }
            }
        }
    }

    // MARK: By site (LAB-554)

    private func bySite(_ tabs: [BrowserTab]) -> some View {
        let sites = BrowserTabs.sites(tabs)
        let shown = showAllSites ? sites : Array(sites.prefix(Self.firstSites))
        return VStack(alignment: .leading, spacing: 5) {
            ForEach(shown) { site in siteBlock(site) }
            if sites.count > Self.firstSites {
                Button(showAllSites ? "Show the top \(Self.firstSites) sites" : "Show all \(sites.count) sites") { showAllSites.toggle() }
                    .buttonStyle(.link).ui(11.5)
            }
        }
    }

    private func siteBlock(_ site: BrowserSite) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 6) {
                Text(site.site).ui(12, .semibold).foregroundStyle(t.text.color).lineLimit(1)
                Text("\(site.tabs.count) tab\(site.tabs.count == 1 ? "" : "s")").ui(11).foregroundStyle(t.text2.color)
            }
            .accessibilityAddTraits(.isHeader)
            ForEach(site.tabs) { tab in row(tab, site: false) }
        }
    }

    private func row(_ tab: BrowserTab, site: Bool) -> some View {
        BrowserTabRow(tab: tab, app: app, showSite: site, closes: closes,
                      forcedHover: SelfTestMacFixture.mode != nil && SelfTestMacFixture.hoverTab == tab.tabId,
                      onShow: { show(tab) }, onClose: { closeTab(tab) })
    }

    // MARK: Closing (LAB-2054)

    private func closeTab(_ tab: BrowserTab) {
        guard closes else { return }
        run(.tab(tab), done: BrowserTabs.CloseCopy.closed(tab.title.isEmpty ? tab.url : tab.title, app: app))
    }

    /// Close window: a window with 2 or more tabs asks first (unless it just did).
    private func closeWindow(_ w: BrowserWindowTabs, asked: Bool) {
        guard closes else { return }
        if !asked && BrowserTabs.closeWindowAsks(tabs: w.tabs.count) { askWindow = w; return }
        run(.window(id: w.windowId, number: w.number, tabs: w.tabs.count),
            done: BrowserTabs.CloseCopy.closedWindow(w.number, tabs: w.tabs.count, app: app))
    }

    private func run(_ target: BrowserTabs.CloseTarget, done: String) {
        if SelfTestMacFixture.mode != nil {   // self-test: never the real browser (logged, row dropped)
            handle(SelfTestMacFixture.close(target), target, done: done)
            return
        }
        let app = app, family = family
        DispatchQueue.global(qos: .userInitiated).async {
            let o = BrowserTabs.close(app: app, family: family, target: target)
            DispatchQueue.main.async { handle(o, target, done: done) }
        }
    }

    private func handle(_ o: BrowserTabs.CloseOutcome, _ target: BrowserTabs.CloseTarget, done: String) {
        switch o {
        case .closed:
            note = Note(text: done)
            onClosed?()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { load() }
        case .gone:
            note = nil
            load()
        case .changed:
            if case .window = target { note = Note(text: BrowserTabs.CloseCopy.windowChanged) }
            else { note = Note(text: BrowserTabs.CloseCopy.changed) }
            load()
        case .timedOut:
            note = Note(text: BrowserTabs.CloseCopy.timedOut(app), error: true, forceQuit: true)
        case .notAllowed:
            note = nil
            state = .failed(.notAllowed)
        case .failed(let why):
            note = Note(text: BrowserTabs.CloseCopy.failed(why), error: true)
        }
    }

    // MARK: Reading

    private func appear() {
        if let mode = SelfTestMacFixture.mode {   // self-test: never ask the real browser
            switch mode {
            case "notasked": state = .notAsked
            case "denied": state = .failed(.notAllowed)
            default:
                grouping = mode == "sites" ? "sites" : "windows"
                state = .loaded(BrowserTabs.parse(SelfTestMacFixture.tabsOutput), Date())
                runSelfTestActions()
            }
            return
        }
        guard case .idle = state else { return }
        if on { load(); return }
        // Ask macOS (no prompt) whether the owner already allowed it: then read at once.
        guard let bundleId else { return }
        state = .checking
        DispatchQueue.global(qos: .userInitiated).async {
            let p = AutomationPermission.check(bundleId: bundleId)
            DispatchQueue.main.async {
                switch p {
                case .granted: load()
                case .denied: state = .failed(.notAllowed)
                default: state = .notAsked
                }
            }
        }
    }

    /// ONEROOF_SELFTEST_TABCLOSE (SelfTestMacFixture): press the close buttons in order, 0.5 s apart.
    private func runSelfTestActions() {
        for (i, a) in SelfTestMacFixture.actions.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0 + 0.5 * Double(i)) {
                guard case .loaded(let tabs, _) = state else { return }
                switch a.kind {
                case "tab", "hung", "changed":
                    if let tab = tabs.first(where: { $0.tabId == a.id }) { closeTab(tab) }
                case "window", "ask":
                    if let w = BrowserTabs.windows(tabs).first(where: { $0.windowId == a.id }) { closeWindow(w, asked: a.kind == "window") }
                default: break
                }
            }
        }
    }

    private func load() {
        if SelfTestMacFixture.mode != nil {
            if case .loaded = state { state = .loaded(BrowserTabs.parse(SelfTestMacFixture.tabsOutput), Date()) }
            return
        }
        state = .loading
        let app = app, family = family
        DispatchQueue.global(qos: .userInitiated).async {
            let r = BrowserTabs.list(app: app, family: family)
            DispatchQueue.main.async {
                switch r {
                case .success(let tabs): state = .loaded(tabs, Date()); on = true
                case .failure(let f): state = .failed(f)
                }
            }
        }
    }

    private func show(_ tab: BrowserTab) {
        if SelfTestMacFixture.mode != nil { return }
        let app = app, family = family
        DispatchQueue.global(qos: .userInitiated).async {
            if let f = BrowserTabs.show(app: app, family: family, tab: tab) {
                DispatchQueue.main.async { state = .failed(f) }
            }
        }
    }
}

/// LAB-2054 · one tab: front-tab dot, title, its site (by window), and a ✕ that shows on hover (its place is kept, so
/// nothing moves and it never covers the site). Click or Return brings it forward; ✕, ⌫ or the right-click menu closes
/// it; the menu also copies its address. VoiceOver: Bring forward · Close tab · Copy address.
struct BrowserTabRow: View {
    @Environment(\.theme) private var t
    let tab: BrowserTab
    let app: String
    let showSite: Bool
    let closes: Bool
    var forcedHover = false
    let onShow: () -> Void
    let onClose: () -> Void
    @State private var hover = false

    private var title: String { tab.title.isEmpty ? (tab.url.isEmpty ? "Untitled tab" : tab.url) : tab.title }

    var body: some View {
        HStack(spacing: 6) {
            Button(action: onShow) {
                HStack(spacing: 6) {
                    Text(tab.active ? "●" : " ").ui(9).foregroundStyle(t.accent.color).frame(width: 10)
                    Text(title).ui(11.5).foregroundStyle(t.text2.color).lineLimit(1).truncationMode(.tail)
                    Spacer(minLength: 8)
                    if showSite { Text(tab.site).ui(10.5, mono: true).foregroundStyle(t.text2.color).lineLimit(1).truncationMode(.middle) }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(tab.url)
            .onKeyPress(.return) { onShow(); return .handled }
            .onKeyPress(.delete) { guard closes else { return .ignored }; onClose(); return .handled }
            .onKeyPress(.deleteForward) { guard closes else { return .ignored }; onClose(); return .handled }
            if closes {
                Button(action: onClose) {
                    Text("✕").ui(10.5, .semibold).foregroundStyle(t.text2.color).frame(width: 16, height: 16).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .opacity(hover || forcedHover ? 1 : 0)
                .help("Close this tab")
                .accessibilityHidden(true)   // the row's "Close tab" action says it
            }
        }
        .padding(.trailing, 2)
        .hoverHighlight(over: t.resourceMarks.panel, forced: forcedHover)
        .onHover { hover = $0 }
        .contextMenu {
            Button("Bring forward", action: onShow)
            if closes { Button("Close tab", action: onClose) }
            Button("Copy address") { copy() }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(tab.title.isEmpty ? "Untitled tab" : tab.title), \(tab.site)\(tab.active ? ", front tab of its window" : "")")
        .accessibilityHint("Brings this tab forward in \(app)")
        .accessibilityActions {
            Button("Bring forward", action: onShow)
            if closes { Button("Close tab", action: onClose) }
            Button("Copy address") { copy() }
        }
    }

    private func copy() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(tab.url, forType: .string)
    }
}

/// Whether macOS already lets One Roof send Apple Events to an app, asked without prompting the owner.
enum AutomationPermission {
    static func check(bundleId: String) -> BrowserTabs.Permission {
        var addr = AEAddressDesc()
        let bytes = Array(bundleId.utf8)
        let made = bytes.withUnsafeBufferPointer { AECreateDesc(DescType(typeApplicationBundleID), $0.baseAddress, $0.count, &addr) }
        guard made == noErr else { return .unknown(Int32(made)) }
        defer { AEDisposeDesc(&addr) }
        let status = AEDeterminePermissionToAutomateTarget(&addr, AEEventClass(typeWildCard), AEEventID(typeWildCard), false)
        return BrowserTabs.permission(status: status)
    }
}

/// An app's Finder icon, cached per bundle (a plain square for processes outside any app).
struct AppIcon: View {
    @Environment(\.theme) private var t
    let bundlePath: String?
    private static var cache: [String: NSImage] = [:]

    var body: some View {
        if let p = bundlePath, let img = Self.icon(p) {
            Image(nsImage: img).resizable().interpolation(.high).accessibilityHidden(true)
        } else {
            RoundedRectangle(cornerRadius: 6, style: .continuous).fill(t.control.color).accessibilityHidden(true)
        }
    }

    private static func icon(_ path: String) -> NSImage? {
        if let i = cache[path] { return i }
        guard FileManager.default.fileExists(atPath: path) else { return nil }
        let i = NSWorkspace.shared.icon(forFile: path)
        cache[path] = i
        return i
    }
}
