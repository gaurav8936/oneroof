import AppKit
import SwiftUI
import OneRoofCore

/// LAB-2098 · Home's front page (owner-approved mockup 2026-11-01): masthead, ticker, lead + side stories written as
/// findings, Decide now, and the overnight river. The rules live in OneRoofCore/HomeFrontPage.swift; this file gathers
/// the inputs (what needs the main thread is read there and is cheap; the store, the ledger, the loop files and the
/// disk are read on a background queue) and draws the page. It does not observe the whole AppModel: it reloads on a
/// timer and on the few changes that alter it (asks, loop items, History, seats), coalesced.
struct HomeFrontPageView: View {
    let model: AppModel
    @ObservedObject var win: WindowState
    @Binding var mode: String
    @Environment(\.theme) private var t
    @Environment(\.v2Window) private var v2
    @State private var page: HomeFrontPage.Page?
    @State private var generation = 0
    @State private var pending: DispatchWorkItem?
    @State private var note: String?
    private let tick = Timer.publish(every: 60, tolerance: 5, on: .main, in: .common).autoconnect()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                topRow
                if let p = page { content(p) } else {
                    Text("Reading last night…").ui(TypeScale.body).foregroundStyle(t.text2.color).padding(.top, 24)
                }
            }
            .padding(.horizontal, v2 ? CGFloat(V2Layout.Bar.contentLead) : 28).padding(.top, 18).padding(.bottom, 28)
            .frame(maxWidth: 1500, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(t.window.color)
        .onAppear {
            reload(after: 0)
            // As today's Overview: the projects sessions are linked to, from Linear (on demand, off the main thread).
            model.loadWorkstreams()
            let ids = Set(model.sessionItems.compactMap(\.session.workstream))
            for w in model.workstreams where w.wsId.map(ids.contains) ?? false { model.loadIssues(w, maxAge: 300) }
        }
        .onReceive(model.$issues.dropFirst()) { _ in reload() }
        .onReceive(tick) { _ in reload(after: 0) }
        .onReceive(NotificationCenter.default.publisher(for: .historyChanged)) { _ in reload() }
        .onReceive(LoopInboxState.shared.$items.dropFirst()) { _ in reload() }
        .onReceive(model.$decisions.dropFirst()) { _ in reload() }
        .onReceive(model.$seats.dropFirst()) { _ in reload() }
    }

    // MARK: Top row (the Home mode switch, kept from today's Overview header)

    private var topRow: some View {
        HStack(spacing: 10) {
            Spacer()
            RoofButton("+ New work item") { NotificationCenter.default.post(name: .newWorkItem, object: nil); model.show(.work, in: win) }
            if v2 { RoofButton("+ New objective") { NotificationCenter.default.post(name: .newObjective, object: nil) } }   // as All windows (A5)
            HomeModePicker(mode: $mode, model: model, win: win)
        }
        .padding(.bottom, 10)
    }

    // MARK: Page

    @ViewBuilder private func content(_ p: HomeFrontPage.Page) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(p.masthead).font(.system(size: 18, weight: .bold, design: .monospaced)).tracking(3).foregroundStyle(t.text.color)
                .lineLimit(1).minimumScaleFactor(0.7)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 16)
            Text(p.windowLine).ui(TypeScale.caption).foregroundStyle(t.text2.color).lineLimit(1)
        }
        VStack(spacing: 2) { rule(2); rule(1) }.padding(.top, 6)
        ticker(p.ticker).padding(.vertical, 8)
        rule(1)
        if let note { Text(note).ui(TypeScale.small).foregroundStyle(t.text2.color).padding(.top, 8) }
        HStack(alignment: .top, spacing: 28) {
            VStack(alignment: .leading, spacing: 0) {
                story(p.lead, lead: true)
                rule(1).padding(.top, 22)
                decideNow(p)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Rectangle().fill(t.separator.color).frame(width: 1)
            VStack(alignment: .leading, spacing: 0) {
                if p.side.isEmpty {
                    Text("Nothing else worth your attention overnight.").ui(TypeScale.body).foregroundStyle(t.text2.color).padding(.top, 18)
                }
                ForEach(Array(p.side.enumerated()), id: \.offset) { i, s in
                    if i > 0 { rule(1).padding(.vertical, 16) }
                    story(s, lead: false)
                }
            }
            .frame(width: 400, alignment: .leading)
        }
        .padding(.top, 18)
        rule(2).padding(.top, 26)
        river(p.river, p.digest).padding(.top, 12)
    }

    private func rule(_ h: CGFloat) -> some View {
        Rectangle().fill(h > 1 ? t.text.color : t.separator.color).frame(height: h).accessibilityHidden(true)
    }

    private func ticker(_ items: [HomeFrontPage.TickerItem]) -> some View {
        // One Text so it wraps as a line of type, never clips (1280 pt windows).
        items.enumerated().reduce(Text("")) { acc, e in
            let (i, it) = e
            let sep = i == 0 ? Text("") : Text("      ")
            return acc + sep + Text(it.label + " ").foregroundColor(t.text2.color)
                + Text(it.value).fontWeight(.semibold).foregroundColor(it.tone == .info ? t.text.color : tone(it.tone).color)
        }
        .ui(TypeScale.small).fixedSize(horizontal: false, vertical: true)
        .accessibilityLabel(items.map { "\($0.label): \($0.value)" }.joined(separator: ". "))
    }

    private func story(_ s: HomeFrontPage.Story, lead: Bool) -> some View {
        VStack(alignment: .leading, spacing: lead ? 10 : 7) {
            Text(s.kicker).font(.system(size: 11.5, weight: .bold, design: .monospaced)).tracking(2).foregroundStyle(tone(s.tone).color)
            Text(s.headline).font(.system(size: lead ? 32 : 21, weight: .semibold, design: .serif)).foregroundStyle(t.text.color)
                .fixedSize(horizontal: false, vertical: true).lineLimit(lead ? 4 : 3)
                .accessibilityAddTraits(.isHeader)
            if !s.body.isEmpty {
                Text(s.body).ui(lead ? 14.5 : TypeScale.body).foregroundStyle(t.text2.color).lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true).lineLimit(lead ? 6 : 4)
            }
            if !s.actions.isEmpty {
                HStack(spacing: 8) {
                    ForEach(Array(s.actions.enumerated()), id: \.offset) { _, a in
                        RoofButton(a.title, a.primary ? .primary : .secondary) { perform(a.target) }
                    }
                }
                .padding(.top, 4)
            }
        }
        .accessibilityElement(children: .contain)
    }

    private func decideNow(_ p: HomeFrontPage.Page) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("DECIDE NOW").font(.system(size: 11.5, weight: .bold, design: .monospaced)).tracking(2).foregroundStyle(t.now.color)
                Spacer()
                if p.moreWaiting > 0 {
                    Button { perform(.inbox) } label: { Text("+ \(p.moreWaiting) more in Inbox ›").ui(TypeScale.small).foregroundStyle(t.accentText.color) }
                        .buttonStyle(.plain)
                }
            }
            .padding(.top, 14).padding(.bottom, 6)
            if p.decide.isEmpty {
                Text("Nothing waits for you.").ui(TypeScale.body).foregroundStyle(t.text2.color).padding(.vertical, 6)
            }
            ForEach(p.decide) { r in
                HStack(alignment: .center, spacing: 12) {
                    Text(r.tag).font(.system(size: 11, weight: .bold, design: .monospaced)).tracking(1).foregroundStyle(t.now.color)
                        .frame(minWidth: 64, alignment: .leading)
                    Text(r.text).ui(TypeScale.body).foregroundStyle(t.text.color).lineLimit(2).frame(maxWidth: .infinity, alignment: .leading)
                    RoofButton(r.action.title, r.action.primary ? .primary : .secondary) { perform(r.action.target) }
                }
                .padding(.vertical, 8)
                .overlay(alignment: .bottom) {
                    Rectangle().stroke(style: StrokeStyle(lineWidth: 1, dash: [3, 3])).foregroundStyle(t.separator.color).frame(height: 1)
                }
                .accessibilityElement(children: .contain)
                .accessibilityLabel("\(r.tag): \(r.text)")
            }
        }
    }

    // MARK: Overnight river

    private func river(_ r: HomeFrontPage.River, _ d: HomeFrontPage.Digest) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("OVERNIGHT · WHAT RAN, WHEN").font(.system(size: 11.5, weight: .bold, design: .monospaced)).tracking(2).foregroundStyle(t.text.color)
                Spacer()
                if !r.isEmpty {
                    Text(HomeFrontPage.plural(d.total, "run") + (d.wrong.isEmpty ? " · all fine" : " · \(d.wrong.count) went wrong"))
                        .ui(TypeScale.small).foregroundStyle(d.wrong.isEmpty ? t.text2.color : t.needsText.color)
                }
            }
            if r.isEmpty {
                Text("Nothing ran in this window. Loop runs, your sessions' findings and releases show here as dots on a timeline.")
                    .ui(TypeScale.body).foregroundStyle(t.text2.color)
            } else {
                // LAB-2198: the strip is dots only (hover one for its name and time); the words are in the lists below.
                HStack(alignment: .top, spacing: 0) {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(r.lanes) { l in
                            Button { perform(laneTarget(l.name)) } label: {
                                Text(l.name).ui(TypeScale.small).foregroundStyle(t.text2.color).frame(height: Self.laneH, alignment: .leading)
                            }
                            .buttonStyle(.plain).help("Open \(laneTargetName(l.name))")
                            .accessibilityLabel("\(l.name). Open \(laneTargetName(l.name))")
                        }
                    }
                    .frame(width: 120, alignment: .leading)
                    RiverCanvas(river: r, tokens: t, laneH: Self.laneH)
                        .frame(height: CGFloat(r.lanes.count) * Self.laneH + 24)
                        .accessibilityElement()
                        .accessibilityLabel(riverSummary(r))
                }
                digestLists(d)
            }
        }
    }

    @ViewBuilder private func digestLists(_ d: HomeFrontPage.Digest) -> some View {
        if !d.wrong.isEmpty {
            digestHeading("WHAT WENT WRONG", tone: t.needsText)
            ForEach(d.wrong) { w in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text("✕").ui(12, .bold).foregroundStyle(t.needsText.color).frame(width: 12)
                    Text(Self.clock(w.at)).ui(12, mono: true).foregroundStyle(t.text2.color).frame(width: 44, alignment: .leading)
                    Text(w.kind).ui(12).foregroundStyle(t.text2.color).frame(width: 60, alignment: .leading)
                    Text(w.name).ui(13, .semibold).foregroundStyle(t.text.color).lineLimit(1)
                    Text(w.reason).ui(13).foregroundStyle(t.text2.color).lineLimit(1).truncationMode(.tail)
                    Spacer(minLength: 0)
                }
                .accessibilityElement(children: .combine)
            }
        }
        if !d.next.isEmpty {
            digestHeading("WHAT TO DO NEXT", tone: t.text)
            ForEach(Array(d.next.enumerated()), id: \.element.id) { n, rec in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text("\(n + 1).").ui(13, .semibold).foregroundStyle(t.text2.color).frame(width: 18, alignment: .trailing)
                    Text(rec.text).ui(13).foregroundStyle(t.text.color).fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 8)
                    ForEach(Array(rec.actions.enumerated()), id: \.offset) { _, a in
                        RoofButton(a.title, a.primary ? .primary : .secondary) { perform(a.target) }.fixedSize()
                    }
                }
                .padding(.vertical, 2)
            }
        }
        if !d.fine.isEmpty {
            digestHeading(d.wrong.isEmpty ? "ALL RAN FINE" : "RAN FINE", tone: t.statusDone)
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("✓").ui(12, .bold).foregroundStyle(t.statusDone.color).frame(width: 12)
                Text(Self.foldFine(d.fine)).ui(13).foregroundStyle(t.text2.color).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                RoofButton("Show all", .secondary) { perform(.history) }.fixedSize()
            }
        }
    }

    private func digestHeading(_ s: String, tone: RGB) -> some View {
        Text(s).font(.system(size: 10.5, weight: .bold, design: .monospaced)).tracking(1.5).foregroundStyle(tone.color)
            .padding(.top, 10).accessibilityAddTraits(.isHeader)
    }

    /// The first eight names, then "and N more".
    static func foldFine(_ names: [String]) -> String {
        let head = names.prefix(8).joined(separator: " · ")
        return names.count > 8 ? head + " · and \(names.count - 8) more" : head
    }

    static func clock(_ d: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "HH:mm"; return f.string(from: d)
    }

    static let laneH: CGFloat = 30   // LAB-2198: no slanted labels, so the lanes are close

    private func riverSummary(_ r: HomeFrontPage.River) -> String {
        r.lanes.map { l in
            l.marks.isEmpty ? "\(l.name): nothing" : "\(l.name): " + l.marks.map(\.label).joined(separator: ", ")
        }.joined(separator: ". ")
    }

    private func laneTarget(_ name: String) -> HomeFrontPage.Target {
        switch name { case "Loops": return .loops(nil); case "Asked you": return .inbox; default: return .history }
    }
    private func laneTargetName(_ name: String) -> String {
        switch name { case "Loops": return "Loops"; case "Asked you": return "Inbox"; default: return "History" }
    }

    private func tone(_ k: HomeFrontPage.Tone) -> RGB {
        switch k { case .bad: return t.needsText; case .warn: return t.now; case .good: return t.statusDone; case .info: return t.accentText }
    }

    // MARK: Actions

    private func perform(_ target: HomeFrontPage.Target) {
        switch target {
        case .inbox: model.show(.decisions, in: win)
        case .history: model.show(.history, in: win)
        case .sessions: model.show(.workspace, in: win)
        case .projects: model.show(.work, in: win)
        case .machine: model.show(.resources, in: win)
        case .evals: model.show(.evals, in: win)
        case .settings: break
        case .loops(let id): LoopInboxState.shared.focus = id; model.show(.loops, in: win)
        case .session(let id): if let item = model.item(id) { model.reveal(item) } else { model.show(.decisions, in: win) }
        case .runLoopAgain(let id):
            note = "Starting it again: roofd runs it within 30 s."
            LoopInboxState.shared.runAgain(id) { note = LoopInboxState.shared.lastResult[id] ?? note; reload() }
        }
    }

    // MARK: Loading

    /// Coalesce bursts (asks and loop items often change together) into one read.
    private func reload(after delay: Double = 0.4) {
        pending?.cancel()
        let w = DispatchWorkItem { load() }
        pending = w
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: w)
    }

    private func load() {
        generation += 1
        let gen = generation
        let now = Date()
        // Main thread, cheap: what the model holds in memory.
        var inputs = HomeFrontPage.Inputs(now: now)
        inputs.asks = Self.asks(model)
        inputs.seats = model.seats
        inputs.mac = model.resources.snapshot.mac
        inputs.version = AppVersion.current?.short
        let items = model.sessionItems
        inputs.liveSessions = items.filter { $0.status.isLive }.count
        inputs.working = items.filter { $0.status == .running }.count
        inputs.issues = Self.waitingIssues(model)
        let names = Dictionary(items.map { ($0.id, ($0.session.name, SessionScope.isLoop($0.session))) }, uniquingKeysWith: { a, _ in a })
        let live = HistoryLoader.live(model)
        let store = model.store
        let window = HomeFrontPage.window(now: now)
        DispatchQueue.global(qos: .userInitiated).async {
            var i = inputs
            // History's moments (manual sessions only; loop rounds live in Loops).
            if let store {
                var sessions = store.historySessions()
                for (id, v) in names { sessions[id] = HistorySession(id: id, name: v.0, agent: sessions[id]?.agent ?? .claude, account: sessions[id]?.account,
                                                                     isLoop: v.1, firstAt: sessions[id]?.firstAt, lastAt: sessions[id]?.lastAt) }
                let entries = store.historyEntries(from: window.start, to: window.end.addingTimeInterval(1), live: live) { sessions[$0]?.isLoop }
                i.moments = entries.map { HomeFrontPage.Moment(at: $0.at, kind: $0.kind, text: $0.text, session: sessions[$0.sessionId]?.name ?? "") }
            }
            // Loop runs from the outcome ledger, with each loop's title from the loop files.
            let loopStore = LoopInboxState.store()
            let titles = Dictionary(loopStore.all().map { ($0.id, $0.displayTitle) }, uniquingKeysWith: { a, _ in a })
            let iso = ISO8601DateFormatter()
            i.runs = (LoopInboxState.ledger(loopStore.root)?.runs(from: window.start, to: window.end.addingTimeInterval(1)) ?? []).compactMap { r in
                guard let st = iso.date(from: r.started) else { return nil }
                return HomeFrontPage.LoopRun(loop: r.loop, title: titles[r.loop] ?? r.loop, started: st, result: r.result, summary: r.summary)
            }
            i.diskFree = ModelDownload.freeBytes(at: NSHomeDirectory())
            let built = HomeFrontPage.build(i)
            DispatchQueue.main.async {
                guard gen == generation else { return }
                if page != built { page = built }
            }
        }
    }

    /// The Inbox's blocks as rows (its order: asks, plans, loop items).
    static func asks(_ m: AppModel) -> [HomeFrontPage.Ask] {
        let loopItems = Dictionary(m.loopInbox.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        return m.inboxLayout.all.compactMap { b -> HomeFrontPage.Ask? in
            let name = b.sessionId.flatMap { m.item($0)?.session.name } ?? "A session"
            switch b.kind {
            case .plan:
                let title = m.objectives.first { $0.id == b.planId }?.title ?? "An objective"
                return .init(id: b.id, kind: .plan, title: title, detail: "", at: b.at)
            case .loop:
                guard let it = b.loopItemId.flatMap({ loopItems[$0] }) else { return nil }
                let k: HomeFrontPage.Ask.Kind = it.kind == .failed ? .loopFailed : it.kind == .asks ? .loopAsks : .loopStaged
                return .init(id: b.id, kind: k, title: it.loopTitle, detail: it.headline, at: b.at, loopId: it.loopId)
            case .question, .menu:
                let text = b.decision.map { Inbox.body($0, agentName: $0.agent.displayName) }
                let detail = text?.headline ?? text?.lines.first ?? "asks you something"
                return .init(id: b.id, kind: .question, title: name, detail: String(detail.prefix(160)), at: b.at, sessionId: b.sessionId)
            case .finished, .waiting:
                return .init(id: b.id, kind: .finished, title: name, detail: String((b.decision?.why ?? "waiting for you").prefix(160)), at: b.at, sessionId: b.sessionId)
            case .permission:
                let d = b.decision
                let detail = d?.command.map { "$ " + $0 } ?? d?.path ?? d?.why ?? "asks permission"
                return .init(id: b.id, kind: .permission, title: name, detail: String(detail.prefix(160)), at: b.at, sessionId: b.sessionId)
            }
        }
    }

    /// Issues of the projects sessions are linked to that wait on you (in review or blocked), from what Linear loaded.
    static func waitingIssues(_ m: AppModel) -> [HomeFrontPage.Issue] {
        m.issues.values.joined().filter { i in
            let s = i.state.lowercased()
            return i.type != "commit" && i.stateType != "completed" && i.stateType != "canceled" && (s.contains("review") || s.contains("block"))
        }
        .map { HomeFrontPage.Issue(identifier: $0.identifier, title: $0.title, state: $0.state) }
    }
}

/// The river's dots, drawn in one Canvas (cheap to redraw, no view per dot). LAB-2198: no labels on the strip; hovering
/// near a dot shows its name and time.
struct RiverCanvas: View {
    let river: HomeFrontPage.River
    let tokens: ThemeTokens
    let laneH: CGFloat
    @State private var hover: (mark: HomeFrontPage.Mark, point: CGPoint)?

    var body: some View {
        GeometryReader { geo in
            let w = max(1, geo.size.width - 12)
            Canvas { ctx, size in
                for (li, lane) in river.lanes.enumerated() {
                    let y = Self.y(li, laneH)
                    var line = Path(); line.move(to: CGPoint(x: 0, y: y)); line.addLine(to: CGPoint(x: w, y: y))
                    ctx.stroke(line, with: .color(tokens.separator.color), lineWidth: 1)
                    for m in lane.marks {
                        let x = CGFloat(m.x) * w
                        let r: CGFloat = m.tone == .bad ? 7 : m.count > 1 ? 6 : 5
                        ctx.fill(Path(ellipseIn: CGRect(x: x - r, y: y - r, width: 2 * r, height: 2 * r)), with: .color(colour(m.tone).color))
                    }
                }
                let ty = CGFloat(river.lanes.count) * laneH + 12
                for tk in river.ticks {
                    let anchor: UnitPoint = tk.x < 0.03 ? .leading : tk.x > 0.97 ? .trailing : .center
                    ctx.draw(Text(tk.label).font(.system(size: 10.5, design: .monospaced)).foregroundColor(tokens.text2.color),
                             at: CGPoint(x: CGFloat(tk.x) * w, y: ty), anchor: anchor)
                }
            }
            .onContinuousHover { phase in
                switch phase {
                case .active(let p): hover = nearest(p, w)
                case .ended: hover = nil
                }
            }
            .overlay(alignment: .topLeading) {
                if let h = hover {
                    Text(label(h.mark))
                        .font(.system(size: 11.5, weight: h.mark.tone == .bad ? .semibold : .regular))
                        .foregroundStyle(h.mark.tone == .bad ? tokens.needsText.color : tokens.text.color)
                        .lineLimit(1).fixedSize()
                        .padding(.horizontal, 7).padding(.vertical, 3)
                        .background(RoundedRectangle(cornerRadius: 6).fill(tokens.surface.color))
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(tokens.separator.color))
                        // Beside the dot, kept inside the strip near the right edge.
                        .offset(x: min(h.point.x + 10, max(0, geo.size.width - 280)), y: max(0, h.point.y - 32))
                        .allowsHitTesting(false)
                }
            }
        }
    }

    static func y(_ lane: Int, _ laneH: CGFloat) -> CGFloat { CGFloat(lane) * laneH + laneH / 2 }

    private func nearest(_ p: CGPoint, _ w: CGFloat) -> (mark: HomeFrontPage.Mark, point: CGPoint)? {
        let li = Int(p.y / laneH)
        guard river.lanes.indices.contains(li) else { return nil }
        let y = Self.y(li, laneH)
        let best = river.lanes[li].marks.min { abs(CGFloat($0.x) * w - p.x) < abs(CGFloat($1.x) * w - p.x) }
        guard let m = best, abs(CGFloat(m.x) * w - p.x) <= 12 else { return nil }
        return (m, CGPoint(x: CGFloat(m.x) * w, y: y))
    }

    private func label(_ m: HomeFrontPage.Mark) -> String {
        let at = river.start.addingTimeInterval(m.x * river.end.timeIntervalSince(river.start))
        let f = DateFormatter(); f.dateFormat = "HH:mm"
        return (m.tone == .bad ? "✕ " : "") + f.string(from: at) + " · " + m.label
    }

    private func colour(_ k: HomeFrontPage.Tone) -> RGB {
        switch k { case .bad: return tokens.needsText; case .warn: return tokens.now; case .good: return tokens.statusDone; case .info: return tokens.accent }
    }
}

/// Home's mode: the front page (default), every window's cards (today's Overview), or the Subagents trace.
struct HomeModePicker: View {
    @Binding var mode: String
    let model: AppModel
    @ObservedObject var win: WindowState
    var body: some View {
        Segmented(options: [("front", "Front page"), ("windows", "All windows"), ("subagents", "Subagents")],
                  selection: Binding(get: { mode }, set: { v in if v == "subagents" { model.show(.subagents, in: win) } else { mode = v } }))
            .accessibilityLabel("Home view")
    }
}
