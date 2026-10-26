import AppKit
import SwiftUI
import OneRoofCore

/// Overview (⇧⌘L / ⌃↑, replaces Launchpad): every workspace window as a card with its sessions, and a rail with
/// the FYI feed, objectives, workstreams in play and the foundations. Covers all windows (one store, one roofd).
struct OverviewView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var win: WindowState
    @Environment(\.theme) private var t
    @State private var rail = OverviewView.initialRail
    @State private var sibling: CentreView = .overview
    /// LAB-591: the rail (feed) is as wide as the owner drags it.
    @AppStorage("overview.railWidth", store: Prefs.defaults) private var railWidth: Double = 330
    @State private var dragStart: Double?
    static let railWidths: ClosedRange<Double> = 280...760

    static var initialRail: String { ProcessInfo.processInfo.environment["ONEROOF_SELFTEST_RAILTAB"] ?? "feed" }

    @Environment(\.v2Window) private var v2

    var body: some View {
        FleetPage(title: "All windows", subtitle: subtitle) {
            RoofButton("+ New work item") { NotificationCenter.default.post(name: .newWorkItem, object: nil); model.show(.work, in: win) }
            if v2 { RoofButton("+ New objective") { NotificationCenter.default.post(name: .newObjective, object: nil) } }   // A5
            // LAB-593: Board and Decisions are top-level tabs (and ⌘ shortcuts) already; only Subagents lives here.
            Segmented(options: [(CentreView.overview, "Overview"), (.subagents, "Subagents")],
                      selection: Binding(get: { .overview }, set: { model.show($0, in: win) }))
        } content: {
            HStack(alignment: .top, spacing: 0) {
                ScrollView {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 18, alignment: .top), count: 3), spacing: 18) {
                        ForEach(model.windows) { w in windowCard(w) }
                    }
                }
                .frame(maxWidth: .infinity)
                railHandle
                railCard.frame(width: CGFloat(min(max(railWidth, Self.railWidths.lowerBound), Self.railWidths.upperBound)))
            }
        }
        .onAppear {
            model.loadWorkstreams()
            for w in activeWorkstreams { model.loadIssues(w, maxAge: 300) }
        }
    }

    private var subtitle: String {
        let all = model.items
        let working = all.filter { $0.status == .running }.count
        let tonight = model.schedules.count
        let w = model.windows.count
        let finished = all.filter { $0.status == .done }.count
        let queued = all.filter { [.next, .planned].contains($0.status) }.count
        let onTicket = all.filter { $0.session.ticket != nil }.count
        return "\(w) window\(w == 1 ? "" : "s") · \(all.count) sessions · \(working) working · \(finished) finished · \(queued) queued · \(onTicket) on a ticket · \(model.runningSubagents) subagents running · \(tonight) scheduled tonight"
    }

    // MARK: Window cards (COMPONENTS WindowCard)

    static let order: [SessionStatus] = [.needsYou, .running, .done, .next, .planned, .idle, .exited, .doNotUse]

    private func windowCard(_ w: WindowState) -> some View {
        let list = model.items(in: w).sorted { a, b in
            let ra = Self.rank(a, model), rb = Self.rank(b, model)
            if ra != rb { return ra < rb }
            return (model.lastActiveDate(a) ?? .distantPast) > (model.lastActiveDate(b) ?? .distantPast)
        }
        let needs = list.filter { $0.status == .needsYou }.count
        return Card(needs: needs > 0) {
            VStack(alignment: .leading, spacing: 0) {
                Button { focus(w) } label: {
                    HStack(spacing: 8) {
                        HStack(spacing: 5) { ForEach(0..<3, id: \.self) { _ in Circle().fill(t.separatorStrong.color).frame(width: 9, height: 9) } }
                        Text(w.name).ui(13.5, .semibold).foregroundStyle(t.text.color).lineLimit(1)
                        Text("\(list.count)").ui(12).foregroundStyle(t.text3.color)
                        Spacer()
                        if needs > 0 { Text("\(needs) need you").ui(12, .semibold).foregroundStyle(t.needsText.color) }
                    }
                    .padding(.horizontal, 12).frame(height: 36)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Window \(w.name), \(list.count) sessions, \(needs) need you")
                Hairline()
                VStack(spacing: 0) {
                    ForEach(list.prefix(6)) { item in
                        let subs = model.subagents[item.id] ?? []
                        SessionRow(row: model.rowData(item), density: .compact, selected: false)
                            .overlay(alignment: .topLeading) { if !subs.isEmpty { SubagentTrunk() } }
                            .onTapGesture { model.reveal(item) }
                            .contextMenu { SessionContextMenu(model: model, item: item, win: w) }
                            .onDrag { NSItemProvider(object: ("oneroof-session:" + item.id) as NSString) }
                        // LAB-595: its subagents hang under it, joined by tree lines, instead of living only in Subagents.
                        SubagentBranches(subs: subs, parent: item.session.name) { sub in
                            win.traceFocus = item.id + (sub.map { "/" + $0.id } ?? "")
                            model.show(.subagents, in: win)
                        }
                    }
                    if list.isEmpty {
                        Text("No sessions").ui(12).foregroundStyle(t.text3.color).frame(maxWidth: .infinity, alignment: .leading)
                            .padding(12)
                    }
                }
                .padding(.vertical, 4)
                if list.count > 6 {
                    Button { w.filter = ""; w.statusFilter = nil; focus(w) } label: {
                        Text("+ \(list.count - 6) more").ui(12).foregroundStyle(t.text3.color)
                    }
                    .buttonStyle(.plain).padding(.horizontal, 12).padding(.bottom, 10)
                }
            }
        }
        .onDrop(of: [.text], isTargeted: nil) { providers in
            guard let p = providers.first else { return false }
            _ = p.loadObject(ofClass: NSString.self) { obj, _ in
                guard let raw = obj as? String, raw.hasPrefix("oneroof-session:") else { return }
                DispatchQueue.main.async { if let i = model.item(String(raw.dropFirst(16))) { withAnimation(Motion.base) { model.move(i, to: w) } } }
            }
            return true
        }
    }

    static func rank(_ i: BoardItem, _ m: AppModel) -> Int {
        if m.schedules[i.id] != nil { return 5 }
        return order.firstIndex(of: i.status) ?? 9
    }

    private func focus(_ w: WindowState) {
        model.show(.workspace, in: w)
        NotificationCenter.default.post(name: .focusWorkspace, object: w.id)
    }

    // MARK: Rail

    /// Drag to resize the rail (LAB-591); double-click puts it back to 330 pt.
    private var railHandle: some View {
        Capsule().fill(t.separatorStrong.color).frame(width: 3, height: 36)
            .frame(width: 22).frame(maxHeight: .infinity)   // the 22 pt gap between the cards and the rail
            .contentShape(Rectangle())
            .onHover { inside in if inside { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() } }
            .gesture(DragGesture(minimumDistance: 1)
                .onChanged { v in
                    let start = dragStart ?? railWidth
                    dragStart = start
                    railWidth = min(max(start - Double(v.translation.width), Self.railWidths.lowerBound), Self.railWidths.upperBound)
                }
                .onEnded { _ in dragStart = nil })
            .onTapGesture(count: 2) { railWidth = 330 }
            .help("Drag to make the feed wider or narrower")
            .accessibilityLabel("Resize the feed")
    }

    private var railCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    ForEach([("feed", "Feed"), ("agents", "Agents"), ("objectives", "Objectives"), ("workstreams", "Projects"), ("foundations", "Foundations")], id: \.0) { id, label in
                        Button { rail = id } label: {
                            VStack(spacing: 4) {
                                Text(label).ui(12, .semibold).foregroundStyle(rail == id ? t.text.color : t.text2.color).lineLimit(1).fixedSize()
                                Rectangle().fill(rail == id ? t.accent.color : .clear).frame(height: 2)
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(rail == id ? .isSelected : [])
                    }
                    Spacer(minLength: 0)
                }
                switch rail {
                case "objectives": objectives
                case "workstreams": workstreams
                case "foundations": foundations
                case "agents": agents
                default: feed
                }
            }
            .padding(16)
            .frame(maxHeight: .infinity, alignment: .top)
        }
    }

    private var feed: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("What's happening").ui(15, .semibold).foregroundStyle(t.text.color)
                Text("FYI · all windows · newest first").ui(12).foregroundStyle(t.text3.color).lineLimit(1)
                Spacer()
                Menu("Mute") {
                    ForEach(model.windows) { w in
                        Button((model.mutedWindows.contains(w.id) ? "✓ " : "") + w.name) { model.toggleMute(window: w.id) }
                    }
                }
                .menuStyle(.borderlessButton).fixedSize().ui(12)
            }
            .padding(.bottom, 6)
            if model.visibleFeed.isEmpty {
                Text("Nothing new. Captions appear as agents work.").ui(12.5).foregroundStyle(t.text2.color).padding(.top, 8)
            }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(model.visibleFeed) { e in FeedRow(entry: e, model: model) }
                }
            }
        }
    }

    private var objectives: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                let list = Array(model.objectives.filter { $0.status != .done }.reversed())
                if list.isEmpty {
                    Text("No open objectives. Say what you want; a planner writes a plan you approve.").ui(12.5).foregroundStyle(t.text2.color)
                }
                ForEach(list) { o in
                    let steps = o.plan?.steps.count ?? 0
                    let done = o.plan?.steps.filter { o.stepResults[$0.id]?.ok == true }.count ?? 0
                    Button { model.objectiveId = o.id } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(o.title).ui(13, .semibold).foregroundStyle(t.text.color).lineLimit(2)
                            Text(o.status == .running ? "\(done) of \(steps) steps" : o.status == .review ? "Plan ready · \(steps) steps" : o.status.rawValue.capitalized)
                                .ui(12).foregroundStyle(o.status == .review ? t.needsText.color : t.text2.color)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                        .background(RoundedRectangle(cornerRadius: Radius.row, style: .continuous).fill(t.surface2.color))
                    }.buttonStyle(.plain)
                }
                RoofButton("+ New objective ⇧⌘O", .plain) { NotificationCenter.default.post(name: .newObjective, object: nil) }
            }
        }
    }

    private var activeWorkstreams: [LinearWorkstream] {
        let ids = Set(model.items.compactMap(\.session.workstream))
        return model.workstreams.filter { $0.wsId.map(ids.contains) ?? false }
    }

    private var workstreams: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if activeWorkstreams.isEmpty {
                    Text(model.linearLoading ? "Loading from Linear…" : "No session is linked to a project yet.").ui(12.5).foregroundStyle(t.text2.color)
                }
                ForEach(activeWorkstreams) { w in
                    let tickets = (model.issues[w.id] ?? []).filter { $0.type != "commit" }
                    let done = tickets.filter { $0.stateType == "completed" }.count
                    let next = tickets.first { $0.stateType == "started" } ?? tickets.first { $0.stateType == "unstarted" || $0.stateType == "backlog" }
                    let live = model.sessions(in: w).filter { $0.status.isLive }.count
                    Button { model.show(.work, in: win) } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(w.wsId ?? "").ui(11.5, .semibold, mono: true).foregroundStyle(t.accentText.color)
                                Spacer()
                                if live > 0 { Text("\(live) live").ui(11, .semibold).foregroundStyle(t.statusColor(.running).color) }
                                if v2, !tickets.isEmpty { Text("\(done * 100 / tickets.count)%").ui(11, .semibold).foregroundStyle(t.text2.color) }   // NEW-23
                            }
                            Text(w.title).ui(13, .semibold).foregroundStyle(t.text.color).lineLimit(1)
                            if !tickets.isEmpty {
                                GeometryReader { g in
                                    ZStack(alignment: .leading) {
                                        Capsule().fill(t.separator.color)
                                        Capsule().fill(t.statusColor(.done).color).frame(width: g.size.width * CGFloat(done) / CGFloat(tickets.count))
                                    }
                                }.frame(height: 4)
                                Text("\(done)/\(tickets.count)" + (next.map { " · next: \($0.identifier) \($0.shortTitle)" } ?? ""))
                                    .ui(11.5).foregroundStyle(t.text2.color).lineLimit(1)
                            }
                        }
                    }.buttonStyle(.plain)
                }
            }
        }
    }

    /// Agents at work, seats and just finished (v0.1 Launchpad).
    private var agents: some View {
        let live = model.items.filter { $0.status.isLive && $0.session.agent.isAgent }
        let groups = AgentsAtWork.groups(live.map { ($0.id, $0.account ?? $0.session.agent.displayName) }, subagents: model.subagents)
        let finished = model.items.filter { $0.status == .done }
        return ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                MicroLabel("Agents at work")
                if groups.isEmpty { Text("No agent sessions open.").ui(12.5).foregroundStyle(t.text2.color) }
                ForEach(groups) { g in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 8) {
                            if let first = g.sessions.first.flatMap({ model.item($0.sessionId) }) { AgentBadge(item: first, size: 20, status: false) }
                            Text(g.key).ui(13, .semibold).foregroundStyle(t.text.color)
                            Spacer()
                            Text("\(g.sessions.count) live" + (g.runningSubagents > 0 ? " · \(g.runningSubagents) subagent\(g.runningSubagents == 1 ? "" : "s")" : ""))
                                .ui(12).foregroundStyle(t.text2.color)
                        }
                        // LAB-635: each session, and under it the subagents (Agent/Task lanes) it is running now.
                        ForEach(g.sessions) { e in
                            if let item = model.item(e.sessionId) {
                                SessionRow(row: model.rowData(item), density: .compact, selected: false)
                                    .overlay(alignment: .topLeading) { if !e.running.isEmpty { SubagentTrunk() } }
                                    .onTapGesture { model.reveal(item) }
                                SubagentBranches(subs: e.running, parent: item.session.name) { sub in
                                    win.traceFocus = item.id + (sub.map { "/" + $0.id } ?? "")
                                    model.show(.subagents, in: win)
                                }
                            }
                        }
                    }
                }
                MicroLabel("Seats").padding(.top, 6)
                if model.seats.isEmpty {
                    Text("No usage data yet. Claude seats report after their next status-line refresh; Codex from its session logs.").ui(12).foregroundStyle(t.text2.color)
                }
                ForEach(model.seats, id: \.seat) { s in
                    let mark: AgentMark = s.seat == "Claude2" ? .claude2 : s.seat == "Codex" ? .codex : .claude1
                    VStack(alignment: .leading, spacing: 3) {
                        HStack {
                            Text(s.seat).ui(12.5, .semibold).foregroundStyle(t.text.color)
                            Spacer()
                            Text([s.fiveHour.map { "5h \(Int($0))%" }, s.sevenDay.map { "7d \(Int($0))%" }].compactMap { $0 }.joined(separator: " · "))
                                .ui(11.5, mono: true).foregroundStyle(t.text2.color)
                        }
                        SeatGauge(mark: mark, used: s.worst, note: s.fiveHourResets.map { "resets " + $0.formatted(date: .omitted, time: .shortened) }, style: .card)
                    }
                }
                Text("Kimi and Antigravity publish no usage figures; One Roof counts their sessions.").ui(11.5).foregroundStyle(t.text3.color)
                MicroLabel("Just finished").padding(.top, 6)
                if finished.isEmpty { Text("No unread results.").ui(12.5).foregroundStyle(t.text2.color) }
                ForEach(finished) { i in
                    SessionRow(row: model.rowData(i), density: .compact).onTapGesture { model.reveal(i) }
                }
            }
        }
    }

    private var foundations: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 7) {
                if model.foundations.isEmpty {
                    Text(model.checkingFoundations ? "Checking…" : "Not checked yet.").ui(12.5).foregroundStyle(t.text2.color)
                }
                ForEach(model.foundations) { r in
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(r.level == .ok ? "✓" : r.level == .warn ? "!" : "✕").ui(12, .semibold)
                            .foregroundStyle(r.level == .ok ? t.statusDone.color : r.level == .warn ? t.now.color : t.needsText.color)
                        Text("\(r.title): \(r.detail)").ui(12).foregroundStyle(t.text.color).lineLimit(2)
                    }
                }
                RoofButton("Open Foundations", .secondary) { NotificationCenter.default.post(name: .openFoundations, object: nil) }
                    .padding(.top, 4)
            }
        }
    }
}

/// A feed item (COMPONENTS FeedItem). LAB-591/659: one row per event, read like a table row — when · agent · what
/// happened (and "Needs you" when the session is waiting on the owner now), then what was done, then the session on
/// one truncated line (a multi-issue session's long name no longer fills the row twice).
struct FeedRow: View {
    @Environment(\.theme) private var t
    let entry: FeedEntry
    @ObservedObject var model: AppModel

    var body: some View {
        let item = model.item(entry.sessionId)
        let name = item?.session.name ?? entry.sessionName
        let line = FeedLine.describe(kind: entry.feedKind, text: entry.text, sessionName: name)
        let needs = item?.status == .needsYou
        let agent = item.map { $0.account ?? $0.session.agent.displayName } ?? ""
        let place = [windowName(item), name].filter { !$0.isEmpty }.joined(separator: " › ")
        Button { if let item { model.reveal(item) } } label: {
            HStack(alignment: .top, spacing: 8) {
                if let item { AgentBadge(item: item, size: 18, status: false) } else { Color.clear.frame(width: 18, height: 18) }
                VStack(alignment: .leading, spacing: 3) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(line.action).ui(11.5, .semibold).foregroundStyle(kindColor.color).lineLimit(1).fixedSize()
                        if !agent.isEmpty { Text(agent).ui(11.5).foregroundStyle(t.text2.color).lineLimit(1) }
                        if needs { StatusPill(status: .needsYou) }
                        Spacer(minLength: 4)
                        Text(FeedLine.timeLabel(entry.at)).ui(11, mono: true).foregroundStyle(t.text3.color).lineLimit(1).fixedSize()
                    }
                    Text(line.detail).ui(13).foregroundStyle(t.text.color).lineLimit(3).fixedSize(horizontal: false, vertical: true)
                    if !place.isEmpty {
                        Text(place).ui(11.5).foregroundStyle(t.text3.color).lineLimit(1).truncationMode(.tail).help(place)
                    }
                }
            }
            .padding(.vertical, 9)
            .overlay(alignment: .top) { Hairline() }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(line.action)\(agent.isEmpty ? "" : ", " + agent)\(needs ? ", needs you" : ""): \(line.detail). Session \(place). \(FeedLine.timeLabel(entry.at))")
    }

    private func windowName(_ i: BoardItem?) -> String {
        guard let i else { return "" }
        return model.window(model.workspaceId(of: i))?.name ?? ""
    }

    /// tokens.json `feedKinds`.
    private var kindColor: RGB {
        switch entry.kind {
        case "step done", "done": return t.statusDone
        case "finding": return t.accentText
        case "choice": return t.now
        case "subagents": return t.isDark ? AgentMark.kimi.fill : t.sticker(Pastel.named("lavender")!).ink
        case "rotated": return StatusPalette.scheduledPill(theme: t.name).text
        case "error": return t.needsText
        default: return t.text2
        }
    }
}

/// LAB-595: a session's subagents under its row in the Overview: tree lines from the session's badge to each
/// subagent (and from a subagent to the ones it started), a status dot, the name, what it is doing and its age.
/// A row opens the Subagents trace on that subagent.
struct SubagentBranches: View {
    @Environment(\.theme) private var t
    let subs: [Subagent]
    let parent: String
    var onOpen: (Subagent?) -> Void

    var body: some View {
        let (rows, hidden) = SubagentTree.branches(subs)
        if !rows.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(rows) { b in row(b) }
                if hidden > 0 {
                    Button { onOpen(nil) } label: {
                        Text("+ \(hidden) more · \(SubagentTree.summary(subs)) ▸").ui(11.5).foregroundStyle(t.text3.color)
                            .padding(.leading, SubagentTreeLines.trunkX + 6).frame(height: 22)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(hidden) more subagents of \(parent). Open the trace")
                }
            }
            .padding(.bottom, 4)
        }
    }

    private func row(_ b: SubagentBranch) -> some View {
        let s = b.sub
        return Button { onOpen(s) } label: {
            HStack(spacing: 6) {
                SubagentTreeLines(level: b.level, rails: b.rails, isLast: b.isLast)
                    .stroke(t.separatorStrong.color, style: StrokeStyle(lineWidth: 1.2, lineCap: .round, dash: s.inferred ? [3, 3] : []))
                    .frame(width: SubagentTreeLines.width(level: b.level), height: 26)
                StatusDot(status: s.status == .needsYou ? .needsYou : s.ended == nil ? .running : .done, size: 7)
                Text(s.name).ui(12, .medium, mono: true).foregroundStyle(t.text.color).lineLimit(1).layoutPriority(1)
                Text(caption(s)).ui(11.5).foregroundStyle(t.text3.color).lineLimit(1).truncationMode(.tail)
                Spacer(minLength: 4)
                Text(s.ended == nil ? ageText(s.started) : "done").ui(11, mono: true).foregroundStyle(t.text3.color)
            }
            .padding(.trailing, 10)
            .frame(height: 26)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(s.asked.isEmpty ? s.name : "Asked: " + s.asked)
        .accessibilityLabel("Subagent \(s.name) of \(parent), \(s.ended == nil ? (s.status == .needsYou ? "needs you" : "running") : "finished"). Open the trace")
    }

    private func caption(_ s: Subagent) -> String {
        if !s.caption.isEmpty { return s.caption }
        if let last = s.lastText?.split(separator: "\n").first(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }) { return String(last) }
        return s.ended == nil ? "no caption yet" : ""
    }
}

/// The tree lines left of a subagent row: a rail for each ancestor that carries on below, then ├ or └ to this row.
struct SubagentTreeLines: Shape {
    /// The x of the session badge's centre in a compact row (10 pt padding + half of 20 pt).
    static let trunkX: CGFloat = 20
    static let step: CGFloat = 16
    static func width(level: Int) -> CGFloat { trunkX + CGFloat(level - 1) * step + step - 2 }

    let level: Int
    let rails: [Bool]
    let isLast: Bool

    func path(in r: CGRect) -> Path {
        var p = Path()
        for (i, carries) in rails.enumerated() where carries {
            let x = Self.trunkX + CGFloat(i) * Self.step
            p.move(to: CGPoint(x: x, y: r.minY)); p.addLine(to: CGPoint(x: x, y: r.maxY))
        }
        let x = Self.trunkX + CGFloat(level - 1) * Self.step
        p.move(to: CGPoint(x: x, y: r.minY)); p.addLine(to: CGPoint(x: x, y: isLast ? r.midY : r.maxY))
        p.move(to: CGPoint(x: x, y: r.midY)); p.addLine(to: CGPoint(x: x + Self.step - 6, y: r.midY))
        return p
    }
}

/// The line from a session's badge down to its first subagent row.
struct SubagentTrunk: View {
    @Environment(\.theme) private var t
    var body: some View {
        GeometryReader { g in
            Path { p in
                p.move(to: CGPoint(x: SubagentTreeLines.trunkX, y: 29))
                p.addLine(to: CGPoint(x: SubagentTreeLines.trunkX, y: g.size.height))
            }
            .stroke(t.separatorStrong.color, style: StrokeStyle(lineWidth: 1.2, lineCap: .round))
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
