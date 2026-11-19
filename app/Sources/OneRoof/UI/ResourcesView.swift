import SwiftUI
import OneRoofCore

/// Resources (LAB-493, ⇧⌘U): what One Roof itself costs, across every window and session; since LAB-544 also every
/// other app on the Mac (MacAppsCard), with Quit and End. One Roof's own processes (the app and the roofd daemon), then
/// every running session by window, heaviest first, with its holder's headroom against roofd's memory guard (LAB-310;
/// the lines as roofd runs them, LAB-2312). Clicking a session reveals it.
/// LAB-2313 (owner option A): one page, summary first. A row of six tiles on top (Sessions by state, One Roof's memory
/// and CPU, This Mac, Swap, roofd, and Needs action when something does), then today's full detail, every card
/// folding to a one-line summary; each card's choice is remembered (ResourcesFoldStore). Rows roofd runs that are not
/// One Roof rows get a name (agent, folder, age, the row that replaced them) instead of a bare id.
struct ResourcesView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var win: WindowState
    @ObservedObject var res: ResourceMonitor
    @Environment(\.theme) private var t
    @State private var sort = ResourcesView.lastSort
    @Environment(\.v2Window) private var v2
    @StateObject private var folds: ResourcesFoldStore

    static var lastSort: ResourceSort = .heaviest

    init(model: AppModel, win: WindowState) {
        self.model = model; self.win = win; self.res = model.resources
        _folds = StateObject(wrappedValue: ResourcesFoldStore(thisWindow: win.id))
    }

    var body: some View { watchedBody.modifier(WatchesResources(res: res)) }   // LAB-1333
    @ViewBuilder private var watchedBody: some View {
        let snap = res.snapshot
        let all = rows(snap)
        let sorted = ResourceBoard.group(all, windows: model.windows.map { ($0.id, $0.name) }, sort: sort)
        // v2: this window first, the rest as sorted (LAB-973); v1 keeps window order.
        let groups = v2 ? sorted.filter { $0.id == win.id } + sorted.filter { $0.id != win.id } : sorted
        let sum = ResourcesSummary.make(groups, status: status)
        let names = orphanLabels(all, groups)
        let otherIds = Set(groups.first { $0.id == ResourceBoard.otherId }?.rows.map(\.id) ?? [])
        FleetPage(title: "Resources", subtitle: subtitle(snap)) {
            HStack(spacing: 10) {
                Text("Sort").ui(12.5).foregroundStyle(t.text2.color)
                Segmented(options: [(ResourceSort.heaviest, "Heaviest"), (.name, "Name")], selection: $sort)
                    .accessibilityLabel("Sort sessions")
            }
        } content: {
            ScrollViewReader { proxy in
                if v2 { v2Body(snap, groups, sum, names, proxy) } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 18, pinnedViews: []) {
                            tiles(snap, sum, proxy)
                            MacAppsCard(res: res, folds: folds)
                            ownProcesses(snap)
                            if groups.isEmpty { emptyCard }
                            ForEach(groups) { g in windowCard(g, names) }
                        }
                        .padding(.bottom, 8)
                    }
                }
            }
        }
        .onChange(of: sort) { _, v in Self.lastSort = v }
        .onChange(of: otherIds) { _, ids in folds.noteOther(ids) }   // LAB-2313: Other opens by itself for a new row
        .onAppear { res.watchMac(true); folds.noteOther(otherIds) }
        .onDisappear { res.watchMac(false) }
    }

    /// LAB-2312: the header's One Roof figures are One Roof's row in "This Mac, by app" (same processes, same readings).
    private func totals(_ s: ResourceSnapshot) -> OneRoofTotals { OneRoofTotals.of(s, mac: res.mac) }

    private func subtitle(_ s: ResourceSnapshot) -> String {
        let n = s.sessions.count
        let o = totals(s)
        if o.leftover > 0 {
            return "One Roof uses \(ResourceFormat.bytes(o.memory)) in RAM, \(ResourceFormat.bytes(o.leftover)) of it left over from an earlier run · \(n) running session\(n == 1 ? "" : "s") · every 3 s"
        }
        return "One Roof uses \(ResourceFormat.bytes(o.memory)) in RAM and \(ResourceFormat.cpu(o.cpu)) CPU (\(ResourceFormat.cpuUnit)) across \(o.processes) processes · \(n) running session\(n == 1 ? "" : "s") · every 3 s, last 10 minutes"
    }

    private var emptyCard: some View {
        Card(padding: 16) {
            Text("No sessions are running. Running sessions show here with their memory and CPU.")
                .ui(13).foregroundStyle(t.text2.color).frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: Rows

    /// Running sessions as rows: the window they sit in (unassigned → the first window, like the sidebar; a closed
    /// window → Other), and sessions roofd runs that no row claims → Other.
    private func rows(_ snap: ResourceSnapshot) -> [ResourceRow] {
        let open = Set(model.windows.map(\.id))
        let live = model.lastSnapshotSessions
        return ResourceBoard.rows(items: model.items, sessions: snap.sessions, window: { i in
            let home = model.workspaceId(of: i)
            return open.contains(home) ? home : nil
        }, title: { live[$0]?.title ?? SelfTestMacFixture.sessionTitle($0) })
    }

    /// A row's One Roof status; nil = not a One Roof row (a roofd session no row owns). Self-test sessions have one.
    private func status(_ r: ResourceRow) -> SessionStatus? { model.item(r.id)?.status ?? SelfTestMacFixture.sessionStatus(r.id) }

    /// LAB-2311: a roofd session no row owns (it gets Close); self-test sessions with a status are not.
    private func isOrphan(_ r: ResourceRow) -> Bool { r.id.hasPrefix("runtime:") && status(r) == nil && model.item(r.id) == nil }

    /// LAB-2313 · the name and sub-line parts of each row that is not a One Roof row, by row id, from what roofd says
    /// (`list`: agent or shell, folder, title) and the holder's start time.
    private func orphanLabels(_ all: [ResourceRow], _ groups: [ResourceWindowGroup]) -> [String: (name: String, sub: [String])] {
        let live = model.lastSnapshotSessions
        let cardName = Dictionary(groups.map { ($0.id, $0.name) }, uniquingKeysWith: { a, _ in a })
        var out: [String: (name: String, sub: [String])] = [:]
        for r in all where isOrphan(r) {
            let rid = r.usage.runtimeId
            let s = live[rid]
            let fx = SelfTestMacFixture.runtimeInfo(rid)
            let name = ResourceOrphanName.name(runtimeId: rid, isAgent: s?.isAgent ?? fx?.isAgent, agentName: s?.agentName ?? fx?.agentName,
                                               cwd: s?.cwd ?? fx?.cwd, title: s?.title)
            let replaced = ResourceOrphanName.replacement(of: rid, rows: all, owned: { status($0) != nil },
                                                          windowName: { id in cardName[id ?? ResourceBoard.otherId] ?? "Other" })
            let started = r.usage.procs.first { $0.role == .holder }?.started
            out[r.id] = (name, ResourceOrphanName.subline(started: started, replacedBy: replaced))
        }
        return out
    }

    // MARK: v2 (A8): the summary row, then This Mac by app | One Roof itself + sessions (this window first)

    private func v2Body(_ snap: ResourceSnapshot, _ groups: [ResourceWindowGroup], _ sum: ResourcesSummary,
                        _ names: [String: (name: String, sub: [String])], _ proxy: ScrollViewProxy) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            tiles(snap, sum, proxy)
            HStack(alignment: .top, spacing: 14) {
                ScrollView { MacAppsCard(res: res, folds: folds).padding(.bottom, 8) }
                    .frame(maxWidth: .infinity)
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 14) {
                        ownProcesses(snap)
                        if groups.isEmpty { emptyCard }
                        ForEach(groups) { g in windowCard(g, names) }
                        // LAB-2312: the lines roofd runs with, not a hard-coded "1.0 GB".
                        Text(ResourceFormat.guardNote(snap)).ui(11.5).foregroundStyle(t.text2.color)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.bottom, 8)
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    // MARK: Summary row (LAB-2313: six tiles, both layouts; replaces the four v2 meters and the v1 strip)

    private func tiles(_ s: ResourceSnapshot, _ sum: ResourcesSummary, _ proxy: ScrollViewProxy) -> some View {
        // Six across when there is room, then three, then two (the mockup's reflow); Needs action drops out when
        // nothing needs action and the rest close up.
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 172), spacing: 10, alignment: .top)], alignment: .leading, spacing: 10) {
            sessionsTile(sum)
            oneRoofTile(s)
            if let m = s.mac {
                macTile(m)
                swapTile(m)
            }
            roofdTile(s)
            if sum.needsAction { needsTile(sum, proxy) }
        }
    }

    /// One summary tile: caps label, a 20 pt figure with its unit beside it, then a graphic or a line. `edge` draws the
    /// 3 pt leading bar of a warning (amber) or an action (red) tile.
    private func tile<Below: View>(_ label: String, _ value: String, _ unit: String, tint: RGB? = nil, edge: RGB? = nil, needs: Bool = false,
                                   a11y: String, @ViewBuilder below: () -> Below) -> some View {
        let below = below()
        return Card(needs: needs, padding: 13) {
            VStack(alignment: .leading, spacing: 5) {
                MicroLabel(label)
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text(value).ui(20, .semibold).monospacedDigit().foregroundStyle((tint ?? t.text).color).lineLimit(1)
                    Text(unit).ui(12).foregroundStyle(t.text2.color).lineLimit(1).truncationMode(.tail)
                }
                .minimumScaleFactor(0.8)
                below
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .overlay(alignment: .leading) {
            if let edge { Capsule().fill(edge.color).frame(width: 3).padding(.vertical, 10).accessibilityHidden(true) }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(a11y)
    }

    private func note(_ s: String, tint: RGB? = nil) -> some View {
        Text(s).ui(11.5).foregroundStyle((tint ?? t.text2).color).fixedSize(horizontal: false, vertical: true)
    }

    /// LAB-2313 (new): running sessions by state, in the status palette's colours, plus the ones that are not One Roof rows.
    private func sessionsTile(_ sum: ResourcesSummary) -> some View {
        let w = sum.windows
        let pills = sum.states.map { "\($0.count) \(StatusPalette.label($0.status).lowercased())" }
            + (sum.notOneRoofRow > 0 ? ["\(sum.notOneRoofRow) not a One Roof row"] : [])
        let line = sum.running == 0 ? "No sessions are running" : sum.windowsLine
        return tile("Sessions", "\(sum.running)", "running · \(w) window\(w == 1 ? "" : "s")",
                    a11y: "Sessions: \(sum.running) running in \(w) window\(w == 1 ? "" : "s")" + (pills.isEmpty ? "" : "; " + pills.joined(separator: ", ")) + "; " + line) {
            if !pills.isEmpty {
                FlowLayout(spacing: 4) {
                    ForEach(sum.states, id: \.status) { c in
                        StatusPill(status: c.status, label: "\(c.count) \(StatusPalette.label(c.status).lowercased())", strongEdge: true)
                    }
                    if sum.notOneRoofRow > 0 { amberPill("\(sum.notOneRoofRow) not a One Roof row") }
                }
            }
            note(line).lineLimit(2)
        }
    }

    /// The amber pill for rows that are not One Roof rows: the leftover rows' tint and text (≥ 4.5:1, LAB-2052).
    private func amberPill(_ s: String) -> some View {
        let m = t.resourceMarks
        return Text(s).ui(10.5, .semibold).foregroundStyle(m.nowText.color).lineLimit(1)
            .padding(.horizontal, 7).padding(.vertical, 2)
            .background(Capsule().fill(m.nowTint.color))
            .overlay(Capsule().strokeBorder(m.pillEdge.color, lineWidth: 1))
    }

    /// Today's One Roof memory and CPU meters, merged: both ten-minute lines, and what the process count covers.
    private func oneRoofTile(_ s: ResourceSnapshot) -> some View {
        let total = res.history.points(ResourceHistory.totalKey)
        let o = totals(s)
        let what = "\(o.processes) processes: app, roofd, holders and everything they run · last 10 min"
        return tile("One Roof", ResourceFormat.bytes(o.memory), "in RAM · \(ResourceFormat.cpu(o.cpu)) CPU",
                    a11y: "One Roof: \(ResourceFormat.bytes(o.memory)) in RAM, CPU \(ResourceFormat.cpu(o.cpu)), \(ResourceFormat.cpuUnit); \(what)") {
            Sparkline(values: total.map { Double($0.footprint) }, color: t.resourceMarks.bar).frame(height: 22)
            Sparkline(values: total.map(\.cpu), color: t.resourceMarks.bar, floor: 100).frame(height: 12)
                .help("CPU, \(ResourceFormat.cpuUnit), last 10 minutes")
            note(what).lineLimit(2)
        }
    }

    private func macTile(_ m: MacMemory) -> some View {
        let tint = pressureColour(m.pressure)
        return tile("This Mac", ResourceFormat.bytes(m.used), "of \(ResourceFormat.bytes(m.total)) in RAM", tint: tint,
                    a11y: "This Mac: \(ResourceFormat.bytes(m.used)) of \(ResourceFormat.bytes(m.total)) used, memory \(m.label), swap \(ResourceFormat.bytes(m.swapUsed))") {
            Meter(fraction: Double(m.used) / Double(max(m.total, 1)), colour: tint ?? t.resourceMarks.bar)
            note("Memory \(m.label) (macOS pressure)", tint: tint)
        }
    }

    /// LAB-2313 (new): swap on its own tile, amber above the line Home's MAC story uses (MacMemory.heavySwapBytes).
    private func swapTile(_ m: MacMemory) -> some View {
        let line = "\(MacMemory.heavySwapBytes >> 30) GB"
        let heavy = m.heavySwap
        let text = heavy ? "Over \(line): the same line Home uses for its \"using a lot of swap\" story." : "Home warns above \(line)."
        return tile("Swap", ResourceFormat.bytes(m.swapUsed), "on disk", tint: heavy ? t.resourceMarks.warn : nil,
                    edge: heavy ? t.resourceMarks.nowBar : nil,
                    a11y: "Swap: \(ResourceFormat.bytes(m.swapUsed)) on disk. \(text)") {
            note(text)
        }
    }

    private func roofdTile(_ s: ResourceSnapshot) -> some View {
        let n = s.sessions.count
        let unit = s.daemon.map { d in (d.started.map { "up " + ResourceFormat.uptime(Date().timeIntervalSince($0)) + " · " } ?? "") + "\(n) sessions" }
            ?? "the session manager is not running"
        let value = s.daemon.map { ResourceFormat.bytes($0.resident) } ?? "not found"
        return tile("roofd", value, unit, a11y: "roofd: \(value), \(unit)" + (s.daemon.map { ", limit \(ResourceFormat.bytes(s.daemonHeadroom.limitBytes)), warns at \(ResourceFormat.bytes(s.daemonHeadroom.warnBytes)), now \(ResourceFormat.bytes($0.footprint))" } ?? "")) {
            if let d = s.daemon { HeadroomBar(headroom: s.daemonHeadroom, footprint: d.footprint, label: "roofd") }
        }
    }

    /// LAB-2313 (new): only when something needs action. The sessions no window owns (the Other card) and a way there;
    /// the session nearest its holder limit once one is at the warning line.
    private func needsTile(_ sum: ResourcesSummary, _ proxy: ScrollViewProxy) -> some View {
        let n = sum.otherCount
        let value = n > 0 ? "\(n)" : "\(sum.atWarn)"
        let unit = n > 0 ? "session\(n == 1 ? "" : "s") no window owns" : "session\(sum.atWarn == 1 ? "" : "s") near a holder limit"
        var text = n > 0 ? "\(ResourceFormat.bytes(sum.otherMemory)) in RAM, listed in Other below"
            + (sum.notOneRoofRow > 0 ? "; a row that is not a One Roof row has Close." : ".") : ""
        if let near = sum.nearest {
            text += (text.isEmpty ? "" : " ") + "Nearest a limit: \(near.name), holder \(ResourceFormat.bytes(near.holder)) of \(ResourceFormat.bytes(near.limit))."
        }
        let goOther = {
            folds.set(.other, true)
            withAnimation(Motion.fast) { proxy.scrollTo(ResourceBoard.otherId, anchor: .top) }
        }
        return tile("Needs action", value, unit, tint: t.resourceMarks.near, edge: t.resourceMarks.near, needs: true,
                    a11y: "Needs action: \(value) \(unit). \(text)") {
            note(text).lineLimit(4)
            if n > 0 {
                Button("Go to Other ▾") { goOther() }.buttonStyle(.link).ui(12)
                    .help("Opens the Other card and scrolls to it")
            }
        }
        .accessibilityAction(named: "Go to Other") { if n > 0 { goOther() } }
    }

    private func pressureColour(_ p: MacMemory.Pressure) -> RGB? {
        switch p {
        case .normal: return nil
        case .warn: return t.resourceMarks.warn
        case .critical: return t.resourceMarks.near
        }
    }

    // MARK: Folding (LAB-2313)

    /// A card's header as its fold button: chevron, name, the one-line summary, and the figures on the right.
    private func foldHeader(_ card: ResourcesFold.Card, title: String, detail: String, cpu: String? = nil, memory: String? = nil,
                            a11y: String, toggle: @escaping () -> Void) -> some View {
        let open = folds.isOpen(card)
        return Button(action: toggle) {
            HStack(spacing: 8) {
                FoldChevron(open: open)
                Text(title).ui(13.5, .semibold).foregroundStyle(t.text.color).lineLimit(1)
                Text(detail).ui(12).foregroundStyle(t.text2.color).lineLimit(1).truncationMode(.tail)
                Spacer(minLength: 8)
                if let cpu { Text(cpu + " CPU").ui(12, mono: true).foregroundStyle(t.text2.color).lineLimit(1).fixedSize() }
                if let memory { Text(memory).ui(12.5, .semibold, mono: true).foregroundStyle(t.text.color).lineLimit(1).fixedSize() }
            }
            .padding(.horizontal, 14).frame(height: 36)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .hoverHighlight(over: t.surface, radius: Radius.card)
        .help(open ? "Fold this card" : "Open this card")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(ResourcesFold.label(title, open: open, summary: a11y))
        .accessibilityHint(open ? "Folds the card" : "Opens the card")
        .accessibilityAddTraits([.isHeader, .isButton])
    }

    // MARK: One Roof itself

    private func ownSummary(_ s: ResourceSnapshot) -> String {
        var parts: [String] = []
        if !s.app.isEmpty { parts.append("app \(ResourceFormat.bytes(s.appResident))") }
        parts.append(s.daemon.map { "roofd \(ResourceFormat.bytes($0.resident))" } ?? "roofd not found")
        let u = s.unclaimed.count
        parts.append(u == 0 ? "no ended holders" : "\(u) ended holder\(u == 1 ? "" : "s")")
        return parts.joined(separator: " · ")
    }

    private func ownProcesses(_ s: ResourceSnapshot) -> some View {
        let open = folds.isOpen(.own)
        let detail = ownSummary(s)
        return Card {
            VStack(alignment: .leading, spacing: 0) {
                foldHeader(.own, title: "One Roof itself", detail: detail, a11y: detail) { folds.toggle(.own) }
                if open {
                    Hairline()
                    if let app = s.app.first {
                        // LAB-2312: the figures are the app and what it started together, not the app process alone; say so.
                        let kids = s.app.count - 1
                        let model = s.app.contains { $0.name.hasPrefix("llama-server") }
                        let what = model ? "terminal attach, local model" : "terminal attach"
                        ownRow(name: "One Roof app", note: kids > 0 ? "app + \(kids) helper\(kids == 1 ? "" : "s") it started (\(what)), together" : "the app process",
                               pid: app.pid, cpu: s.appCPU, memory: s.appResident, started: app.started, headroom: nil)
                    }
                    if let d = s.daemon {
                        Hairline().padding(.leading, 14)
                        ownRow(name: "roofd daemon", note: "keeps sessions running", pid: d.pid, cpu: d.cpu, memory: d.resident,
                               started: d.started, headroom: s.daemonHeadroom, holder: d.footprint, gauge: "roofd")
                    } else {
                        Hairline().padding(.leading, 14)
                        Text("roofd daemon: not found").ui(12.5).foregroundStyle(t.text2.color).padding(.horizontal, 14).padding(.vertical, 10)
                    }
                    ForEach(s.unclaimed, id: \.runtimeId) { u in
                        Hairline().padding(.leading, 14)
                        ownRow(name: "Holder without a live session", note: "an ended session still winding down", pid: u.holderPid ?? 0,
                               cpu: u.cpu, memory: u.resident, started: u.procs.first?.started, headroom: u.headroom, holder: u.holderFootprint, gauge: "holder")
                    }
                }
            }
        }
    }

    private func ownRow(name: String, note: String?, pid: Int32, cpu: Double?, memory: UInt64, started: Date?,
                        headroom: Headroom?, holder: UInt64? = nil, gauge: String? = nil) -> some View {
        let level = headroom?.level(holder ?? memory) ?? .ok
        return HStack(spacing: 12) {
            // LAB-2052: the name keeps one line ("One / Roof / app" wrapped at 1280); the note and the bar give way.
            VStack(alignment: .leading, spacing: 2) {
                Text(name).ui(13, .semibold).foregroundStyle(t.text.color).lineLimit(1).fixedSize()
                if let note { Text(note).ui(11.5).foregroundStyle(t.text2.color).lineLimit(1).truncationMode(.tail) }
            }
            .layoutPriority(1)
            Spacer(minLength: 8)
            Text("pid \(pid)").ui(11, mono: true).foregroundStyle(t.text2.color).frame(width: 74, alignment: .trailing)
            Text(started.map { "up " + ResourceFormat.uptime(Date().timeIntervalSince($0)) } ?? "").ui(11.5).foregroundStyle(t.text2.color)
                .lineLimit(1).frame(width: 60, alignment: .trailing)
            Text(ResourceFormat.cpu(cpu)).ui(12.5, mono: true).foregroundStyle(t.text2.color).frame(width: 58, alignment: .trailing)
            Text(ResourceFormat.bytes(memory)).ui(12.5, .semibold, mono: true).foregroundStyle(memoryColour(level).color)
                .frame(width: 72, alignment: .trailing)
            Group {
                if let headroom { HeadroomBar(headroom: headroom, footprint: holder ?? memory, label: gauge) } else { Color.clear }
            }
            .frame(minWidth: 106, idealWidth: 150, maxWidth: 150)
        }
        .padding(.horizontal, 14).padding(.vertical, 9)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(name), process \(pid), CPU \(ResourceFormat.cpu(cpu)) of one core, memory in RAM \(ResourceFormat.bytes(memory))"
            + (headroom.map { ", limit \(ResourceFormat.bytes($0.limitBytes))" } ?? ""))
    }

    func memoryColour(_ l: Headroom.Level) -> RGB {
        switch l {
        case .ok: return t.text
        case .warn: return t.resourceMarks.warn
        case .nearLimit: return t.resourceMarks.near
        }
    }

    // MARK: Sessions by window

    private func windowCard(_ g: ResourceWindowGroup, _ names: [String: (name: String, sub: [String])]) -> some View {
        let worst = g.rows.map(\.usage.level).max() ?? .ok
        let other = g.id == ResourceBoard.otherId
        let card: ResourcesFold.Card = other ? .other : .window(g.id)
        let open = folds.isOpen(card)
        let n = g.rows.count
        // LAB-2313: the folded line: how many, and whose (this window; Other = no window owns them).
        let detail = other ? "\(n) session\(n == 1 ? "" : "s") no window owns · windows closed or not a One Roof row"
            : "\(n) running session\(n == 1 ? "" : "s")" + (g.id == win.id && v2 ? " · this window" : "")
        let ids = Set(g.rows.map(\.id))
        return Card(needs: worst == .nearLimit) {
            VStack(alignment: .leading, spacing: 0) {
                foldHeader(card, title: g.name, detail: detail, cpu: ResourceFormat.cpu(g.cpu), memory: ResourceFormat.bytes(g.footprint),
                           a11y: "\(detail), \(ResourceFormat.bytes(g.footprint)), CPU \(ResourceFormat.cpu(g.cpu))") {
                    if other { folds.toggleOther(ids) } else { folds.toggle(card) }
                }
                if open {
                    Hairline()
                    LazyVStack(spacing: 0) {
                        ForEach(g.rows) { r in sessionRow(r, names[r.id]) }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .id(g.id)   // LAB-2313: "Go to Other" scrolls here
    }

    private func sessionRow(_ r: ResourceRow, _ orphanName: (name: String, sub: [String])?) -> some View {
        let item = model.item(r.id)
        let name = orphanName?.name ?? r.name
        // LAB-2052: a row without a One Roof session is no longer drawn disabled (dimmed below 4.5:1); it just does nothing.
        let row = Button { if let item { model.reveal(item) } } label: { sessionRowLabel(r, item, name: name, extra: orphanName?.sub) }
            .buttonStyle(.plain)
            .hoverHighlight(over: t.surface)   // LAB-2052: a hover you can see
            .help(item == nil ? "Running in roofd without a One Roof row" : "Show \(r.name)")
            .accessibilityElement(children: .combine)
            .accessibilityLabel(rowLabel(r, item, name: name, extra: orphanName?.sub))
            .accessibilityHint(item == nil ? "" : "Shows the session")
        // LAB-2311: a roofd session no row owns can be closed from here.
        let orphan = item == nil && r.id.hasPrefix("runtime:") && SelfTestMacFixture.sessionStatus(r.id) == nil ? String(r.id.dropFirst("runtime:".count)) : nil
        return HStack(spacing: 6) {
            row
            if let orphan {
                RoofButton("Close") {
                    // LAB-2313: a self-test's fixture sessions are not in roofd; Close draws, and does nothing.
                    if SelfTestMacFixture.runtimeInfo(orphan) == nil { model.closeOrphan(orphan) }
                }
                .help("End \(orphan) in roofd: no One Roof session owns it")
                .accessibilityLabel("Close \(name)")
            }
        }
        .padding(.horizontal, 4)
    }

    private func rowLabel(_ r: ResourceRow, _ item: BoardItem?, name: String, extra: [String]?) -> String {
        let u = r.usage
        var s = name
        if let st = item?.status ?? SelfTestMacFixture.sessionStatus(r.id) { s += ", " + StatusPalette.label(st) }
        if let extra { s += ", " + extra.joined(separator: ", ") }
        s += ", session total \(ResourceFormat.bytes(u.resident)) in RAM, CPU \(ResourceFormat.cpu(u.cpu)) of one core"
        if u.holderPid != nil { s += ", holder alone \(ResourceFormat.bytes(u.holderFootprint)) of its \(ResourceFormat.bytes(u.headroom.limitBytes)) limit" }
        return s
    }

    @ViewBuilder private func badge(_ item: BoardItem?) -> some View {
        if let item { AgentBadge(item: item, size: 20, status: false) } else {
            RoundedRectangle(cornerRadius: 6, style: .continuous).fill(t.control.color).frame(width: 20, height: 20)
        }
    }

    /// - Parameter extra: LAB-2313, for a row that is not a One Roof row: "not a One Roof row", the row that replaced
    ///   it, its age (else today's " · not a One Roof row" alone).
    private func sessionRowLabel(_ r: ResourceRow, _ item: BoardItem?, name: String, extra: [String]?) -> some View {
        let u = r.usage
        let points: [Double] = res.history.points(u.runtimeId).map { Double($0.footprint) }
        let lineColour: RGB = u.level == .ok ? t.resourceMarks.bar : memoryColour(u.level)
        let n = u.procs.count
        // LAB-2312: the total is the whole session; the gauge beside it is the holder alone (what the limit checks).
        let unowned = item == nil && SelfTestMacFixture.sessionStatus(r.id) == nil
        let sub = "session total, \(n) process\(n == 1 ? "" : "es")"
            + (extra.map { " · " + $0.joined(separator: " · ") } ?? (unowned ? " · not a One Roof row" : ""))
        return HStack(spacing: 10) {
            badge(item)
            VStack(alignment: .leading, spacing: 1) {
                Text(name).ui(13, .semibold).foregroundStyle(t.text.color).lineLimit(1).truncationMode(.middle)
                Text(sub).ui(11).foregroundStyle(t.text2.color).lineLimit(1)
            }
            .frame(minWidth: 90, alignment: .leading)
            .layoutPriority(1)
            if let item { StatusPill(status: item.status, strongEdge: true) }
            else if let s = SelfTestMacFixture.sessionStatus(r.id) { StatusPill(status: s, strongEdge: true) }   // self-test sessions
            Spacer(minLength: 8)
            // LAB-2052: the sparkline and the headroom bar give way at 1280 so nothing runs past the card.
            Sparkline(values: points, color: lineColour).frame(minWidth: 40, idealWidth: 96, maxWidth: 96).frame(height: 22)
            Text(ResourceFormat.cpu(u.cpu)).ui(12.5, mono: true).foregroundStyle(t.text2.color).frame(width: 50, alignment: .trailing)
            Text(ResourceFormat.bytes(u.resident)).ui(12.5, .semibold, mono: true).foregroundStyle(memoryColour(u.level).color)
                .frame(width: 66, alignment: .trailing)
                .help("Session total in RAM: the holder and everything under it")
            headroom(u).frame(minWidth: 106, idealWidth: 150, maxWidth: 150, alignment: .leading)
        }
        .padding(.horizontal, 10).padding(.vertical, 7)
        .contentShape(Rectangle())
    }

    @ViewBuilder private func headroom(_ u: SessionUsage) -> some View {
        if u.holderPid != nil {
            HeadroomBar(headroom: u.headroom, footprint: u.holderFootprint, warned: u.memoryWarning, label: "holder")
                .help("The holder process alone (roofd session), what roofd's limit checks")
        } else {
            Text("holder unknown").ui(11).foregroundStyle(t.text2.color)
        }
    }
}

// MARK: Folding (LAB-2313)

/// LAB-2313 · each Resources card's open / folded choice, remembered per card in `Prefs.viewState` (next to
/// `resources.browserTabs.*`; a self-test's suite is emptied at launch). Defaults: ResourcesFold.startsOpen.
final class ResourcesFoldStore: ObservableObject {
    let thisWindow: String?
    init(thisWindow: String?) { self.thisWindow = thisWindow }

    private func stored(_ c: ResourcesFold.Card) -> Bool? { Prefs.viewState.object(forKey: ResourcesFold.key(c)) as? Bool }

    func isOpen(_ c: ResourcesFold.Card) -> Bool {
        switch SelfTestMacFixture.foldMode {   // ONEROOF_SELFTEST_RESFOLD
        case "open": return true
        case "folded": return false
        default: break
        }
        // A self-test opens This Mac, by app by default, so its captures still show the browser panel.
        if SelfTestMacFixture.mode != nil, c == .mac, stored(c) == nil { return true }
        return ResourcesFold.isOpen(c, stored: stored(c), thisWindow: thisWindow)
    }

    func set(_ c: ResourcesFold.Card, _ open: Bool) {
        objectWillChange.send()
        Prefs.viewState.set(open, forKey: ResourcesFold.key(c))
    }

    func toggle(_ c: ResourcesFold.Card) { set(c, !isOpen(c)) }

    /// Other folded by the owner remembers which rows it had, so a new one opens it again (`noteOther`).
    func toggleOther(_ ids: Set<String>) {
        let open = !isOpen(.other)
        if !open { Prefs.viewState.set(Array(ids).sorted(), forKey: ResourcesFold.otherSeenKey) }
        set(.other, open)
    }

    /// Other opens by itself whenever a session joins it that was not there when it was folded.
    func noteOther(_ ids: Set<String>) {
        guard stored(.other) == false else { return }
        let seen = Set(Prefs.viewState.stringArray(forKey: ResourcesFold.otherSeenKey) ?? [])
        if ResourcesFold.reopensOther(seen: seen, now: ids) {
            objectWillChange.send()
            Prefs.viewState.removeObject(forKey: ResourcesFold.key(.other))
            Prefs.viewState.removeObject(forKey: ResourcesFold.otherSeenKey)
        }
    }
}

/// The ▸ / ▾ of a card that folds (the app rows' chevron).
struct FoldChevron: View {
    @Environment(\.theme) private var t
    let open: Bool
    var body: some View {
        Text(open ? "▾" : "▸").ui(10).foregroundStyle(t.text3.color).frame(width: 10).accessibilityHidden(true)
    }
}


// MARK: Shared pieces (centre view and the plan panel's Resources tab)

/// Ten minutes of values as a line (200 slots of 3 s, filled from the right as history builds up).
struct Sparkline: View {
    let values: [Double]
    let color: RGB
    /// The top of the scale is at least this (CPU: 100%), so a quiet line stays low.
    var floor: Double = 0
    var slots = ResourceHistory.capacity

    var body: some View {
        GeometryReader { g in
            let top = max(values.max() ?? 0, floor, 1)
            let step = g.size.width / CGFloat(max(slots - 1, 1))
            let start = g.size.width - step * CGFloat(max(values.count - 1, 0))
            let pts = values.enumerated().map { i, v in
                CGPoint(x: start + step * CGFloat(i), y: g.size.height - 1 - CGFloat(v / top) * (g.size.height - 2))
            }
            ZStack {
                if pts.count > 1 {
                    Path { p in
                        p.move(to: CGPoint(x: pts[0].x, y: g.size.height))
                        for pt in pts { p.addLine(to: pt) }
                        p.addLine(to: CGPoint(x: pts[pts.count - 1].x, y: g.size.height))
                        p.closeSubpath()
                    }
                    .fill(color.color.opacity(ResourceMarks.sparkFill))   // LAB-2052: was 0.14
                    Path { p in p.addLines(pts) }.stroke(color.color, style: StrokeStyle(lineWidth: ResourceMarks.sparkLine, lineJoin: .round))   // was 1.4
                } else if let pt = pts.first {
                    Circle().fill(color.color).frame(width: 4, height: 4).position(pt)
                }
            }
        }
        .accessibilityHidden(true)
    }
}

/// A thin bar 0…1 (the Mac's memory). LAB-2052: 6 pt, on a track you can see (ResourceMarks).
struct Meter: View {
    @Environment(\.theme) private var t
    let fraction: Double
    let colour: RGB
    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(t.resourceMarks.track.color)
                Capsule().fill(colour.color).frame(width: max(3, g.size.width * CGFloat(min(1, max(0, fraction)))))
            }
        }
        .frame(height: ResourceMarks.barHeight)
        .accessibilityHidden(true)
    }
}

/// A holder's (or the daemon's) footprint against roofd's memory guard: a bar to the limit with a tick at the
/// warning line, and "1.2 GB of 2 GB".
struct HeadroomBar: View {
    @Environment(\.theme) private var t
    let headroom: Headroom
    let footprint: UInt64
    var warned = false
    /// LAB-2312: what the bar measures ("holder" next to a session total), so the two figures are not read as one.
    var label: String? = nil

    var body: some View {
        let m = t.resourceMarks
        let level = max(headroom.level(footprint), warned ? .warn : .ok)
        let colour: RGB = level == .nearLimit ? m.near : level == .warn ? m.warn : m.bar
        VStack(alignment: .leading, spacing: 3) {
            GeometryReader { g in
                // The bar is 6 pt (LAB-2052, was 5), centred in a 10 pt row so the warn tick stands out above and below
                // it without running into the label underneath.
                ZStack(alignment: .leading) {
                    Capsule().fill(m.track.color).frame(height: ResourceMarks.barHeight)
                    Capsule().fill(colour.color).frame(width: max(3, g.size.width * CGFloat(headroom.fraction(footprint))), height: ResourceMarks.barHeight)
                    Rectangle().fill(m.tick.color).frame(width: 1.5, height: 10)
                        .offset(x: g.size.width * CGFloat(headroom.fraction(headroom.warnBytes)) - 0.75)
                }
                .frame(height: 10)
            }
            .frame(height: 10)
            Text((label.map { $0 + " " } ?? "") + "\(ResourceFormat.bytes(footprint)) of \(ResourceFormat.bytes(headroom.limitBytes))")
                .ui(10.5, mono: true).foregroundStyle((level == .ok ? t.text2 : colour).color).lineLimit(1)
        }
        .accessibilityElement()
        .accessibilityLabel("\(label == "roofd" ? "roofd" : "Holder") memory \(ResourceFormat.bytes(footprint)) of the \(ResourceFormat.bytes(headroom.limitBytes)) limit, warning at \(ResourceFormat.bytes(headroom.warnBytes))")
    }
}

// MARK: Plan panel tab

/// The plan panel's Resources tab for one session: what it uses now, ten minutes of memory and CPU, the watchdog's
/// headroom and every process under its holder.
struct SessionResourcesTab: View {
    @Environment(\.theme) private var t
    let item: BoardItem
    @ObservedObject var res: ResourceMonitor

    var body: some View { watchedBody.modifier(WatchesResources(res: res)) }   // LAB-1333
    @ViewBuilder private var watchedBody: some View {
        if let u = res.usage(item) {
            running(u)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Text(item.starting ? "Starting: its processes show here in a few seconds." : "This session is not running, so it uses no memory or CPU.")
                    .ui(13).foregroundStyle(t.text.color).fixedSize(horizontal: false, vertical: true)
                Text("Every running session shows its holder (roofd session), the agent and everything the agent started, with memory and CPU, updated every 3 s. View › Resources (⇧⌘U) shows all of them.")
                    .ui(12).foregroundStyle(t.text2.color).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func colour(_ l: Headroom.Level) -> RGB { l == .nearLimit ? t.needsText : l == .warn ? t.now : t.text }

    @ViewBuilder private func running(_ u: SessionUsage) -> some View {
        let points = res.history.points(u.runtimeId)
        HStack(alignment: .top, spacing: 18) {
            VStack(alignment: .leading, spacing: 3) {
                MicroLabel("Memory, session total")
                Text(ResourceFormat.bytes(u.resident)).ui(20, .semibold).monospacedDigit().foregroundStyle(colour(u.level).color)
            }
            .accessibilityElement(children: .combine)
            VStack(alignment: .leading, spacing: 3) {
                MicroLabel("CPU, \(ResourceFormat.cpuUnit)")
                Text(ResourceFormat.cpu(u.cpu)).ui(20, .semibold).monospacedDigit().foregroundStyle(t.text.color)
            }
            .accessibilityElement(children: .combine)
            VStack(alignment: .leading, spacing: 3) {
                MicroLabel("Processes")
                Text("\(u.procs.count)").ui(20, .semibold).monospacedDigit().foregroundStyle(t.text.color)
            }
            .accessibilityElement(children: .combine)
        }
        VStack(alignment: .leading, spacing: 6) {
            chartLabel("Memory, last 10 minutes", peak: points.map(\.footprint).max().map(ResourceFormat.bytes))
            Sparkline(values: points.map { Double($0.footprint) }, color: u.level == .ok ? t.resourceMarks.bar : colour(u.level)).frame(height: 44)
            chartLabel("CPU, last 10 minutes", peak: points.map(\.cpu).max().map { ResourceFormat.cpu($0) })
            Sparkline(values: points.map(\.cpu), color: t.statusRunning, floor: 100).frame(height: 32)
        }
        if u.holderPid != nil {
            VStack(alignment: .leading, spacing: 6) {
                MicroLabel("Memory guard")
                HeadroomBar(headroom: u.headroom, footprint: u.holderFootprint, warned: u.memoryWarning, label: "holder")
                Text("roofd warns when this session's holder passes \(ResourceFormat.bytes(u.headroom.warnBytes)) and ends the session at \(ResourceFormat.bytes(u.headroom.limitBytes)). \(ResourceFormat.bytes(u.headroom.left(u.holderFootprint))) left.")
                    .ui(12).foregroundStyle(t.text2.color).fixedSize(horizontal: false, vertical: true)
                if u.memoryWarning {
                    Text("roofd has flagged this holder as over its warning line.").ui(12, .semibold).foregroundStyle(t.now.color)
                }
                if u.level != .ok {
                    Text("Relaunch to free memory.").ui(12.5, .semibold).foregroundStyle(colour(u.level).color)
                }
            }
        }
        VStack(alignment: .leading, spacing: 0) {
            MicroLabel("Processes").padding(.bottom, 6)
            HStack(spacing: 8) {
                Text("Name").frame(maxWidth: .infinity, alignment: .leading)
                Text("pid").frame(width: 52, alignment: .trailing)
                Text("CPU").frame(width: 46, alignment: .trailing)
                Text("Memory").frame(width: 62, alignment: .trailing)
            }
            .ui(10.5, .semibold).foregroundStyle(t.text2.color).padding(.vertical, 3)
            .accessibilityHidden(true)
            Hairline()
            ForEach(u.procs) { p in
                HStack(spacing: 8) {
                    Text(label(p)).ui(12, mono: true).foregroundStyle((p.role == .holder || p.role == .agent ? t.text : t.text2).color)
                        .lineLimit(1).truncationMode(.middle)
                        .padding(.leading, CGFloat(min(p.depth, 6)) * 10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text("\(p.pid)").ui(11, mono: true).foregroundStyle(t.text2.color).frame(width: 52, alignment: .trailing)
                    Text(ResourceFormat.cpu(p.cpu)).ui(11.5, mono: true).foregroundStyle(t.text2.color).frame(width: 46, alignment: .trailing)
                    Text(ResourceFormat.bytes(p.resident)).ui(11.5, .semibold, mono: true)
                        .foregroundStyle((p.role == .holder ? colour(u.headroom.level(p.footprint)) : t.text).color)
                        .frame(width: 62, alignment: .trailing)
                }
                .padding(.vertical, 4)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(label(p)), process \(p.pid), CPU \(ResourceFormat.cpu(p.cpu)), memory \(ResourceFormat.bytes(p.resident))")
            }
        }
    }

    private func label(_ p: ProcUsage) -> String {
        p.role == .holder ? "roofd session" : p.name
    }

    private func chartLabel(_ s: String, peak: String?) -> some View {
        HStack {
            Text(s).ui(11.5).foregroundStyle(t.text2.color)
            Spacer()
            if let peak { Text("peak \(peak)").ui(11, mono: true).foregroundStyle(t.text2.color) }
        }
    }
}
