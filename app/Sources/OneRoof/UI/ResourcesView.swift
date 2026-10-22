import SwiftUI
import OneRoofCore

/// Resources (LAB-493, ⇧⌘U): what One Roof itself costs, across every window and session. A summary strip (One Roof
/// total memory and CPU with ten-minute sparklines, process count, the Mac's memory and pressure), One Roof's own
/// processes (the app and the roofd daemon), then every running session by window, heaviest first, with its holder's
/// headroom against roofd's memory guard (LAB-310: warn 1 GB, end at 2 GB). Clicking a session reveals it.
struct ResourcesView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var win: WindowState
    @ObservedObject var res: ResourceMonitor
    @Environment(\.theme) private var t
    @State private var sort = ResourcesView.lastSort

    static var lastSort: ResourceSort = .heaviest

    init(model: AppModel, win: WindowState) {
        self.model = model; self.win = win; self.res = model.resources
    }

    var body: some View {
        let snap = res.snapshot
        let groups = ResourceBoard.group(rows(snap), windows: model.windows.map { ($0.id, $0.name) }, sort: sort)
        FleetPage(title: "Resources", subtitle: subtitle(snap)) {
            HStack(spacing: 10) {
                Text("Sort").ui(12.5).foregroundStyle(t.text2.color)
                Segmented(options: [(ResourceSort.heaviest, "Heaviest"), (.name, "Name")], selection: $sort)
                    .accessibilityLabel("Sort sessions")
            }
        } content: {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 18, pinnedViews: []) {
                    summary(snap)
                    ownProcesses(snap)
                    if groups.isEmpty {
                        Card(padding: 16) {
                            Text("No sessions are running. Running sessions show here with their memory and CPU.")
                                .ui(13).foregroundStyle(t.text2.color).frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    ForEach(groups) { g in windowCard(g) }
                }
                .padding(.bottom, 8)
            }
        }
        .onChange(of: sort) { _, v in Self.lastSort = v }
    }

    private func subtitle(_ s: ResourceSnapshot) -> String {
        let n = s.sessions.count
        return "One Roof uses \(ResourceFormat.bytes(s.footprint)) and \(ResourceFormat.cpu(s.cpu)) CPU across \(s.processCount) processes · \(n) running session\(n == 1 ? "" : "s") · every 3 s, last 10 minutes"
    }

    // MARK: Rows

    /// Running sessions as rows: the window they sit in (unassigned → the first window, like the sidebar; a closed
    /// window → Other), and sessions roofd runs that no row claims → Other.
    private func rows(_ snap: ResourceSnapshot) -> [ResourceRow] {
        let open = Set(model.windows.map(\.id))
        var out: [ResourceRow] = []
        var claimed = Set<String>()
        for i in model.items {
            guard let rid = i.liveAgent, let u = snap.sessions[rid] else { continue }
            claimed.insert(rid)
            let assigned = model.sessionWorkspace[i.id]
            let w = assigned == nil ? model.windows.first?.id : (open.contains(assigned!) ? assigned : nil)
            out.append(ResourceRow(id: i.id, name: i.session.name, windowId: w, usage: u))
        }
        let live = model.lastSnapshotSessions
        for (rid, u) in snap.sessions where !claimed.contains(rid) {
            out.append(ResourceRow(id: "runtime:" + rid, name: live[rid]?.title ?? rid, windowId: nil, usage: u))
        }
        return out
    }

    // MARK: Summary strip

    private func summary(_ s: ResourceSnapshot) -> some View {
        let total = res.history.points(ResourceHistory.totalKey)
        return Card(padding: 16) {
            HStack(alignment: .top, spacing: 22) {
                stat("One Roof memory", ResourceFormat.bytes(s.footprint), tint: nil) {
                    Sparkline(values: total.map { Double($0.footprint) }, color: t.accent).frame(height: 30)
                }
                .accessibilityLabel("One Roof memory \(ResourceFormat.bytes(s.footprint))")
                stat("One Roof CPU", ResourceFormat.cpu(s.cpu), tint: nil) {
                    Sparkline(values: total.map(\.cpu), color: t.statusRunning, floor: 100).frame(height: 30)
                }
                .accessibilityLabel("One Roof CPU \(ResourceFormat.cpu(s.cpu))")
                stat("Processes", "\(s.processCount)", tint: nil) {
                    Text("app, roofd, holders and everything they run").ui(11.5).foregroundStyle(t.text3.color)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: 170)
                if let m = s.mac {
                    stat("This Mac", "\(ResourceFormat.bytes(m.used)) of \(ResourceFormat.bytes(m.total))", tint: pressureColour(m.pressure)) {
                        VStack(alignment: .leading, spacing: 4) {
                            Meter(fraction: Double(m.used) / Double(max(m.total, 1)), colour: pressureColour(m.pressure) ?? t.accent)
                            Text("Memory \(m.label) · swap \(ResourceFormat.bytes(m.swapUsed))").ui(11.5)
                                .foregroundStyle((pressureColour(m.pressure) ?? t.text3).color)
                        }
                    }
                    .accessibilityLabel("This Mac: \(ResourceFormat.bytes(m.used)) of \(ResourceFormat.bytes(m.total)) used, memory \(m.label), swap \(ResourceFormat.bytes(m.swapUsed))")
                }
            }
        }
    }

    private func stat<Below: View>(_ label: String, _ value: String, tint: RGB?, @ViewBuilder below: () -> Below) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            MicroLabel(label)
            Text(value).ui(22, .semibold).monospacedDigit().foregroundStyle((tint ?? t.text).color).lineLimit(1)
            below()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private func pressureColour(_ p: MacMemory.Pressure) -> RGB? {
        switch p {
        case .normal: return nil
        case .warn: return t.now
        case .critical: return t.needsText
        }
    }

    // MARK: One Roof itself

    private func ownProcesses(_ s: ResourceSnapshot) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 0) {
                header("One Roof itself", detail: nil)
                Hairline()
                if let app = s.app.first {
                    let kids = s.app.count - 1
                    ownRow(name: "One Roof app", note: kids > 0 ? "with \(kids) helper\(kids == 1 ? "" : "s") (terminal attach, tools)" : nil,
                           pid: app.pid, cpu: s.appCPU, memory: s.appFootprint, started: app.started, headroom: nil)
                }
                if let d = s.daemon {
                    Hairline().padding(.leading, 14)
                    ownRow(name: "roofd daemon", note: "starts and keeps the sessions", pid: d.pid, cpu: d.cpu, memory: d.footprint,
                           started: d.started, headroom: s.daemonHeadroom)
                } else {
                    Hairline().padding(.leading, 14)
                    Text("roofd daemon: not found").ui(12.5).foregroundStyle(t.text2.color).padding(.horizontal, 14).padding(.vertical, 10)
                }
                ForEach(s.unclaimed, id: \.runtimeId) { u in
                    Hairline().padding(.leading, 14)
                    ownRow(name: "Holder without a live session", note: "an ended session still winding down", pid: u.holderPid ?? 0,
                           cpu: u.cpu, memory: u.footprint, started: u.procs.first?.started, headroom: u.headroom, holder: u.holderFootprint)
                }
            }
        }
    }

    private func ownRow(name: String, note: String?, pid: Int32, cpu: Double?, memory: UInt64, started: Date?,
                        headroom: Headroom?, holder: UInt64? = nil) -> some View {
        let level = headroom?.level(holder ?? memory) ?? .ok
        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(name).ui(13, .semibold).foregroundStyle(t.text.color)
                if let note { Text(note).ui(11.5).foregroundStyle(t.text3.color).lineLimit(1) }
            }
            Spacer(minLength: 8)
            Text("pid \(pid)").ui(11, mono: true).foregroundStyle(t.text3.color).frame(width: 74, alignment: .trailing)
            Text(started.map { "up " + ResourceFormat.uptime(Date().timeIntervalSince($0)) } ?? "").ui(11.5).foregroundStyle(t.text2.color)
                .frame(width: 70, alignment: .trailing)
            Text(ResourceFormat.cpu(cpu)).ui(12.5, mono: true).foregroundStyle(t.text2.color).frame(width: 58, alignment: .trailing)
            Text(ResourceFormat.bytes(memory)).ui(12.5, .semibold, mono: true).foregroundStyle(memoryColour(level).color)
                .frame(width: 72, alignment: .trailing)
            Group {
                if let headroom { HeadroomBar(headroom: headroom, footprint: holder ?? memory) } else { Color.clear }
            }
            .frame(width: 150)
        }
        .padding(.horizontal, 14).padding(.vertical, 9)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(name), process \(pid), CPU \(ResourceFormat.cpu(cpu)), memory \(ResourceFormat.bytes(memory))"
            + (headroom.map { ", limit \(ResourceFormat.bytes($0.limitBytes))" } ?? ""))
    }

    private func header(_ title: String, detail: String?) -> some View {
        HStack(spacing: 8) {
            Text(title).ui(13.5, .semibold).foregroundStyle(t.text.color).lineLimit(1)
            if let detail { Text(detail).ui(12).foregroundStyle(t.text3.color).lineLimit(1) }
            Spacer()
        }
        .padding(.horizontal, 14).frame(height: 36)
    }

    func memoryColour(_ l: Headroom.Level) -> RGB {
        switch l {
        case .ok: return t.text
        case .warn: return t.now
        case .nearLimit: return t.needsText
        }
    }

    // MARK: Sessions by window

    private func windowCard(_ g: ResourceWindowGroup) -> some View {
        let worst = g.rows.map(\.usage.level).max() ?? .ok
        return Card(needs: worst == .nearLimit) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 8) {
                    Text(g.name).ui(13.5, .semibold).foregroundStyle(t.text.color).lineLimit(1)
                    Text("\(g.rows.count)").ui(12).foregroundStyle(t.text3.color)
                    Spacer()
                    Text(ResourceFormat.cpu(g.cpu) + " CPU").ui(12, mono: true).foregroundStyle(t.text2.color)
                    Text(ResourceFormat.bytes(g.footprint)).ui(12.5, .semibold, mono: true).foregroundStyle(t.text.color)
                }
                .padding(.horizontal, 14).frame(height: 36)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(g.name), \(g.rows.count) running sessions, \(ResourceFormat.bytes(g.footprint)), CPU \(ResourceFormat.cpu(g.cpu))")
                .accessibilityAddTraits(.isHeader)
                Hairline()
                LazyVStack(spacing: 0) {
                    ForEach(g.rows) { r in sessionRow(r) }
                }
                .padding(.vertical, 4)
            }
        }
    }

    private func sessionRow(_ r: ResourceRow) -> some View {
        let item = model.item(r.id)
        return Button { if let item { model.reveal(item) } } label: { sessionRowLabel(r, item) }
            .buttonStyle(.plain)
            .hoverHighlight()
            .padding(.horizontal, 4)
            .disabled(item == nil)
            .help(item == nil ? "Running in roofd without a One Roof row" : "Show \(r.name)")
            .accessibilityElement(children: .combine)
            .accessibilityLabel(rowLabel(r, item))
            .accessibilityHint(item == nil ? "" : "Shows the session")
    }

    private func rowLabel(_ r: ResourceRow, _ item: BoardItem?) -> String {
        let u = r.usage
        var s = r.name
        if let item { s += ", " + StatusPalette.label(item.status) }
        s += ", memory \(ResourceFormat.bytes(u.footprint)), CPU \(ResourceFormat.cpu(u.cpu))"
        if u.holderPid != nil { s += ", holder \(ResourceFormat.bytes(u.holderFootprint)) of \(ResourceFormat.bytes(u.headroom.limitBytes))" }
        return s
    }

    @ViewBuilder private func badge(_ item: BoardItem?) -> some View {
        if let item { AgentBadge(item: item, size: 20, status: false) } else {
            RoundedRectangle(cornerRadius: 6, style: .continuous).fill(t.control.color).frame(width: 20, height: 20)
        }
    }

    private func sessionRowLabel(_ r: ResourceRow, _ item: BoardItem?) -> some View {
        let u = r.usage
        let points: [Double] = res.history.points(u.runtimeId).map { Double($0.footprint) }
        let lineColour: RGB = u.level == .ok ? t.accent : memoryColour(u.level)
        let n = u.procs.count
        let sub = "\(n) process\(n == 1 ? "" : "es")" + (item == nil ? " · not a One Roof row" : "")
        return HStack(spacing: 10) {
            badge(item)
            VStack(alignment: .leading, spacing: 1) {
                Text(r.name).ui(13, .semibold).foregroundStyle(t.text.color).lineLimit(1)
                Text(sub).ui(11).foregroundStyle(t.text3.color).lineLimit(1)
            }
            .frame(minWidth: 120, alignment: .leading)
            if let item { StatusPill(status: item.status) }
            Spacer(minLength: 8)
            Sparkline(values: points, color: lineColour).frame(width: 96, height: 22)
            Text(ResourceFormat.cpu(u.cpu)).ui(12.5, mono: true).foregroundStyle(t.text2.color).frame(width: 58, alignment: .trailing)
            Text(ResourceFormat.bytes(u.footprint)).ui(12.5, .semibold, mono: true).foregroundStyle(memoryColour(u.level).color)
                .frame(width: 72, alignment: .trailing)
            headroom(u).frame(width: 150, alignment: .leading)
        }
        .padding(.horizontal, 10).padding(.vertical, 7)
        .contentShape(Rectangle())
    }

    @ViewBuilder private func headroom(_ u: SessionUsage) -> some View {
        if u.holderPid != nil {
            HeadroomBar(headroom: u.headroom, footprint: u.holderFootprint, warned: u.memoryWarning)
        } else {
            Text("holder unknown").ui(11).foregroundStyle(t.text3.color)
        }
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
                    .fill(color.color.opacity(0.14))
                    Path { p in p.addLines(pts) }.stroke(color.color, style: StrokeStyle(lineWidth: 1.4, lineJoin: .round))
                } else if let pt = pts.first {
                    Circle().fill(color.color).frame(width: 3, height: 3).position(pt)
                }
            }
        }
        .accessibilityHidden(true)
    }
}

/// A thin bar 0…1 (the Mac's memory).
struct Meter: View {
    @Environment(\.theme) private var t
    let fraction: Double
    let colour: RGB
    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(t.separator.color)
                Capsule().fill(colour.color).frame(width: max(3, g.size.width * CGFloat(min(1, max(0, fraction)))))
            }
        }
        .frame(height: 5)
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

    var body: some View {
        let level = max(headroom.level(footprint), warned ? .warn : .ok)
        let colour: RGB = level == .nearLimit ? t.needsText : level == .warn ? t.now : t.statusRunning
        VStack(alignment: .leading, spacing: 3) {
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(t.separator.color)
                    Capsule().fill(colour.color).frame(width: max(3, g.size.width * CGFloat(headroom.fraction(footprint))))
                    Rectangle().fill(t.text2.color).frame(width: 1.5, height: 9)
                        .offset(x: g.size.width * CGFloat(headroom.fraction(headroom.warnBytes)) - 0.75)
                }
            }
            .frame(height: 5)
            Text("\(ResourceFormat.bytes(footprint)) of \(ResourceFormat.bytes(headroom.limitBytes))")
                .ui(10.5, mono: true).foregroundStyle((level == .ok ? t.text3 : colour).color).lineLimit(1)
        }
        .accessibilityElement()
        .accessibilityLabel("Holder memory \(ResourceFormat.bytes(footprint)) of the \(ResourceFormat.bytes(headroom.limitBytes)) limit, warning at \(ResourceFormat.bytes(headroom.warnBytes))")
    }
}

// MARK: Plan panel tab

/// The plan panel's Resources tab for one session: what it uses now, ten minutes of memory and CPU, the watchdog's
/// headroom and every process under its holder.
struct SessionResourcesTab: View {
    @Environment(\.theme) private var t
    let item: BoardItem
    @ObservedObject var res: ResourceMonitor

    var body: some View {
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
                MicroLabel("Memory")
                Text(ResourceFormat.bytes(u.footprint)).ui(20, .semibold).monospacedDigit().foregroundStyle(colour(u.level).color)
            }
            .accessibilityElement(children: .combine)
            VStack(alignment: .leading, spacing: 3) {
                MicroLabel("CPU")
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
            Sparkline(values: points.map { Double($0.footprint) }, color: u.level == .ok ? t.accent : colour(u.level)).frame(height: 44)
            chartLabel("CPU, last 10 minutes", peak: points.map(\.cpu).max().map { ResourceFormat.cpu($0) })
            Sparkline(values: points.map(\.cpu), color: t.statusRunning, floor: 100).frame(height: 32)
        }
        if u.holderPid != nil {
            VStack(alignment: .leading, spacing: 6) {
                MicroLabel("Memory guard")
                HeadroomBar(headroom: u.headroom, footprint: u.holderFootprint, warned: u.memoryWarning)
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
            .ui(10.5, .semibold).foregroundStyle(t.text3.color).padding(.vertical, 3)
            .accessibilityHidden(true)
            Hairline()
            ForEach(u.procs) { p in
                HStack(spacing: 8) {
                    Text(label(p)).ui(12, mono: true).foregroundStyle((p.role == .holder || p.role == .agent ? t.text : t.text2).color)
                        .lineLimit(1).truncationMode(.middle)
                        .padding(.leading, CGFloat(min(p.depth, 6)) * 10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text("\(p.pid)").ui(11, mono: true).foregroundStyle(t.text3.color).frame(width: 52, alignment: .trailing)
                    Text(ResourceFormat.cpu(p.cpu)).ui(11.5, mono: true).foregroundStyle(t.text2.color).frame(width: 46, alignment: .trailing)
                    Text(ResourceFormat.bytes(p.footprint)).ui(11.5, .semibold, mono: true)
                        .foregroundStyle((p.role == .holder ? colour(u.headroom.level(p.footprint)) : t.text).color)
                        .frame(width: 62, alignment: .trailing)
                }
                .padding(.vertical, 4)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(label(p)), process \(p.pid), CPU \(ResourceFormat.cpu(p.cpu)), memory \(ResourceFormat.bytes(p.footprint))")
            }
        }
    }

    private func label(_ p: ProcUsage) -> String {
        p.role == .holder ? "roofd session" : p.name
    }

    private func chartLabel(_ s: String, peak: String?) -> some View {
        HStack {
            Text(s).ui(11.5).foregroundStyle(t.text3.color)
            Spacer()
            if let peak { Text("peak \(peak)").ui(11, mono: true).foregroundStyle(t.text3.color) }
        }
    }
}
