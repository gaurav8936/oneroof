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

    static var initialRail: String { ProcessInfo.processInfo.environment["ONEROOF_SELFTEST_RAILTAB"] ?? "feed" }

    var body: some View {
        FleetPage(title: "All windows", subtitle: subtitle) {
            RoofButton("+ New work item") { NotificationCenter.default.post(name: .newWorkItem, object: nil); model.show(.work, in: win) }
            Segmented(options: [(CentreView.overview, "Overview"), (.board, "Board"), (.decisions, "Decisions"), (.subagents, "Subagents")],
                      selection: Binding(get: { .overview }, set: { model.show($0, in: win) }),
                      badge: { v in
                          if v == .decisions, model.openDecisionCount > 0 { return "\(model.openDecisionCount)" }
                          if v == .subagents, model.runningSubagents > 0 { return nil }
                          return nil
                      })
        } content: {
            HStack(alignment: .top, spacing: 22) {
                ScrollView {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 18, alignment: .top), count: 3), spacing: 18) {
                        ForEach(model.windows) { w in windowCard(w) }
                    }
                }
                .frame(maxWidth: .infinity)
                railCard.frame(width: 330)
            }
        }
        .onAppear {
            model.loadWorkstreams()
            for w in activeWorkstreams { model.loadIssues(w) }
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
                        SessionRow(row: model.rowData(item), density: .compact, selected: false)
                            .onTapGesture { model.reveal(item) }
                            .contextMenu { SessionContextMenu(model: model, item: item, win: w) }
                            .onDrag { NSItemProvider(object: ("oneroof-session:" + item.id) as NSString) }
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
                Text("FYI · all windows").ui(12).foregroundStyle(t.text3.color)
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
        let byAccount = Dictionary(grouping: live) { $0.account ?? $0.session.agent.displayName }
        let finished = model.items.filter { $0.status == .done }
        return ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                MicroLabel("Agents at work")
                if byAccount.isEmpty { Text("No agent sessions open.").ui(12.5).foregroundStyle(t.text2.color) }
                ForEach(byAccount.keys.sorted(), id: \.self) { k in
                    let first = byAccount[k]![0]
                    HStack(spacing: 8) {
                        AgentBadge(item: first, size: 20, status: false)
                        Text(k).ui(13, .semibold).foregroundStyle(t.text.color)
                        Spacer()
                        Text("\(byAccount[k]!.count) live").ui(12).foregroundStyle(t.text2.color)
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

/// A feed item (COMPONENTS FeedItem): time · agent badge · "Window › Session · kind" · text.
struct FeedRow: View {
    @Environment(\.theme) private var t
    let entry: FeedEntry
    @ObservedObject var model: AppModel

    var body: some View {
        let item = model.item(entry.sessionId)
        Button { if let item { model.reveal(item) } } label: {
            HStack(alignment: .top, spacing: 8) {
                Text(entry.at.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute())).ui(11, mono: true).foregroundStyle(t.text3.color)
                    .frame(width: 40, alignment: .leading)
                if let item { AgentBadge(item: item, size: 18, status: false) } else { Color.clear.frame(width: 18, height: 18) }
                VStack(alignment: .leading, spacing: 2) {
                    (Text("\(windowName(item)) › \(item?.session.name ?? entry.sessionName) · ").foregroundColor(t.text3.color)
                     + Text(entry.kind).foregroundColor(kindColor.color))
                        .ui(11.5).lineLimit(1)
                    Text(entry.text).ui(13).foregroundStyle(t.text.color).fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.vertical, 9)
            .overlay(alignment: .top) { Hairline() }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
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
