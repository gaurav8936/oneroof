import SwiftUI
import UniformTypeIdentifiers
import OneRoofCore

/// Board (⌘B): every session of every window as a card, by status, agent or workstream. Drag between Planned ·
/// Next, Tonight and Do not use (One Roof's own states); columns the runtime owns (live status) refuse drops.
struct BoardView: View {
    /// LAB-1338: captions, feed, chapters and subagents redraw this view (they left AppModel).
    @ObservedObject var engineState = EngineState.shared
    @ObservedObject var model: AppModel
    @ObservedObject var win: WindowState
    @Environment(\.theme) private var t
    @AppStorage("board.grouping") private var grouping = "status"
    @State private var expanded: Set<String> = []
    @State private var flash: String?
    @State private var tonightFor: String?

    struct Column: Identifiable {
        var id: String
        var title: String
        var dot: RGB?
        var items: [BoardItem]
        var drop: SessionStatus?
        var tonight = false
        var collapsible = false
        var seat: (AgentMark, Double?)?
        var progress: Double?
    }

    @Environment(\.v2Window) private var v2

    var body: some View {
        FleetPage(title: "Board", subtitle: "All windows · group by \(grouping) · ⌘B") {
            Segmented(options: v2 ? [("status", "Status"), ("agent", "Agent"), ("workstream", "Project")]
                                  : [("status", "All windows"), ("agent", "By agent"), ("workstream", "By project")], selection: $grouping)
        } content: {
            GeometryReader { g in
                let cols = columns
                let wide = cols.filter { !($0.collapsible && !expanded.contains($0.id)) }
                let narrowCount = cols.count - wide.count
                let w = max(200, (g.size.width - CGFloat(narrowCount) * 56 - CGFloat(cols.count - 1) * 14) / CGFloat(max(wide.count, 1)))
                ScrollView(.horizontal) {
                    HStack(alignment: .top, spacing: 14) {
                        ForEach(cols) { c in
                            if c.collapsible && !expanded.contains(c.id) { collapsed(c) } else { column(c).frame(width: w) }
                        }
                    }
                    .frame(height: g.size.height, alignment: .top)
                }
            }
        }
        .onExitCommand { model.show(.workspace, in: win) }
    }

    // MARK: Columns

    private var all: [BoardItem] { model.items }

    private var columns: [Column] {
        switch grouping {
        case "agent":
            let marks: [AgentMark] = [.claude1, .claude2, .codex, .kimi, .gemini, .antigravity, .shell]
            let alwaysShown = AgentMark.available([.claude1, .claude2, .codex])
            let seats = Dictionary(model.seats.map { ($0.seat, $0.worst) }, uniquingKeysWith: { a, _ in a })
            return marks.map { m in
                let list = all.filter { AgentMark(agent: $0.session.agent, account: $0.account) == m }
                let seat = m == .claude1 ? "Claude1" : m == .claude2 ? "Claude2" : m == .codex ? "Codex" : ""
                return Column(id: m.rawValue, title: m == .shell ? "Shells" : name(m), dot: m.fill, items: sorted(list),
                              seat: (m, seats[seat] ?? nil))
            }.filter { !$0.items.isEmpty || alwaysShown.contains($0.seat?.0 ?? .shell) }
        case "workstream":
            let keys = Set(all.compactMap(\.session.workstream)).sorted()
            var cols = keys.map { ws -> Column in
                let list = all.filter { $0.session.workstream == ws }
                let done = list.filter { [.done, .exited].contains($0.status) }.count
                return Column(id: ws, title: ws, dot: nil, items: sorted(list), progress: list.isEmpty ? nil : Double(done) / Double(list.count))
            }
            let none = all.filter { $0.session.workstream == nil }
            if !none.isEmpty { cols.append(Column(id: "none", title: "No project", dot: nil, items: sorted(none))) }
            return cols
        default:
            let tonight = all.filter { model.schedules[$0.id] != nil }
            let rest = all.filter { model.schedules[$0.id] == nil }
            func st(_ s: Set<SessionStatus>) -> [BoardItem] { sorted(rest.filter { s.contains($0.status) }) }
            return [
                Column(id: "planned", title: "Planned · Next", dot: StatusPalette.dot(.next), items: st([.next, .planned]), drop: .next),
                Column(id: "working", title: "Working", dot: t.statusColor(.running), items: st([.running])),
                Column(id: "needs", title: "Needs you", dot: t.statusColor(.needsYou), items: st([.needsYou])),
                Column(id: "ready", title: "Ready", dot: t.statusColor(.done), items: st([.done])),
                Column(id: "idle", title: "Idle · Parked", dot: t.statusColor(.idle), items: st([.idle])),
                Column(id: "tonight", title: "Tonight", dot: StatusPalette.scheduledDot, items: sorted(tonight), tonight: true),
                Column(id: "exited", title: "Exited", dot: t.statusColor(.exited), items: st([.exited]), collapsible: true),
                Column(id: "dnu", title: "Do not use", dot: t.statusColor(.doNotUse), items: st([.doNotUse]), drop: .doNotUse, collapsible: true),
            ]
        }
    }

    private func name(_ m: AgentMark) -> String {
        switch m {
        case .claude1: return "Claude1"
        case .claude2: return "Claude2"
        case .codex: return "Codex"
        case .kimi: return "Kimi"
        case .gemini: return "Gemini"
        case .antigravity: return "Antigravity"
        case .opencode: return "OpenCode"
        case .goose: return "Goose"
        case .shell: return "Shells"
        }
    }

    private func sorted(_ l: [BoardItem]) -> [BoardItem] {
        l.sorted { a, b in
            if a.status.rank != b.status.rank { return a.status.rank < b.status.rank }
            return (model.lastActiveDate(a) ?? .distantPast) > (model.lastActiveDate(b) ?? .distantPast)
        }
    }

    private func column(_ c: Column) -> some View {
        let droppable = c.drop != nil || c.tonight
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 7) {
                if let d = c.dot { Circle().fill(d.color).frame(width: 8, height: 8) }
                Text(c.title.uppercased()).ui(12.5, .semibold).tracking(0.4).foregroundStyle(t.text.color).lineLimit(1)
                Spacer()
                if c.collapsible { Button { expanded.remove(c.id) } label: { Text("‹").ui(13).foregroundStyle(t.text3.color) }.buttonStyle(.plain) }
                Text("\(c.items.count)").ui(12.5).foregroundStyle(t.text3.color)
            }
            .padding(.horizontal, 6).padding(.top, 4)
            if let (m, used) = c.seat { SeatGauge(mark: m, used: used).padding(.horizontal, 6) }
            if let p = c.progress {
                GeometryReader { g in
                    ZStack(alignment: .leading) {
                        Capsule().fill(t.separator.color)
                        Capsule().fill(t.statusColor(.done).color).frame(width: g.size.width * p)
                    }
                }.frame(height: 4).padding(.horizontal, 6)
            }
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(c.items) { card($0) }
                    if c.items.isEmpty {
                        Text(droppable ? "Drop a session here" : "—").ui(12).foregroundStyle(t.text3.color)
                            .frame(maxWidth: .infinity).padding(.vertical, 18)
                    }
                }
                .padding(.bottom, 6)
            }
        }
        .padding(10)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).fill(t.sidebar.color.opacity(t.isDark ? 0.75 : 0.6)))
        .overlay(RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
            .strokeBorder(flash == c.id ? t.statusColor(.needsYou).color : .clear, lineWidth: 2))
        .onDrop(of: [.text], isTargeted: nil) { providers in drop(providers, on: c) }
        .popover(isPresented: Binding(get: { tonightFor != nil && c.tonight }, set: { if !$0 { tonightFor = nil } })) {
            TonightPicker { hour, minute, nightly in
                if let id = tonightFor, let i = model.item(id) { model.schedule(i, hour: hour, minute: minute, nightly: nightly) }
                tonightFor = nil
            }
            .themed(t.name)
        }
    }

    private func collapsed(_ c: Column) -> some View {
        Button { expanded.insert(c.id) } label: {
            VStack(spacing: 10) {
                if let d = c.dot { Circle().fill(d.color).frame(width: 8, height: 8) }
                Text("\(c.items.count)").ui(12.5, .semibold).foregroundStyle(t.text2.color)
                Text(c.title.uppercased()).ui(11.5, .semibold).tracking(0.4).foregroundStyle(t.text2.color)
                    .fixedSize().rotationEffect(.degrees(90)).frame(width: 20, height: 110)
                Spacer()
            }
            .padding(.top, 12)
            .frame(width: 44)
            .frame(maxHeight: .infinity)
            .background(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).fill(t.sidebar.color.opacity(t.isDark ? 0.75 : 0.6)))
        }
        .buttonStyle(.plain)
        .onDrop(of: [.text], isTargeted: nil) { providers in drop(providers, on: c) }
        .accessibilityLabel("\(c.title), \(c.items.count) sessions, collapsed")
    }

    // MARK: Cards (COMPONENTS BoardCard)

    private func card(_ item: BoardItem) -> some View {
        let row = model.rowData(item)
        let needs = item.status == .needsYou
        let wsName = model.window(model.workspaceId(of: item))?.name ?? ""
        return VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 7) {
                AgentBadge(row.mark, size: 20)
                Text(row.name).ui(13, .semibold).foregroundStyle(t.text.color).lineLimit(1)
            }
            Text(row.caption.text).ui(12).foregroundStyle(row.caption.tone == .needs ? t.needsText.color : t.text2.color)
                .lineLimit(2).fixedSize(horizontal: false, vertical: true)
            if !row.stickers.isEmpty {
                HStack(spacing: 4) { ForEach(row.stickers.prefix(3)) { StickerTag(sticker: $0, size: 10) } }
            }
            HStack(spacing: 6) {
                Text(wsName).ui(11).foregroundStyle(t.text3.color).lineLimit(1)
                let n = model.subagentCount(item)
                if n > 0 { Text("\(n) subagents").ui(11).foregroundStyle(t.text3.color) }
                Spacer()
                Text(row.scheduled != nil ? "tonight" : [.planned, .next].contains(item.status) ? "planned" : row.age)
                    .ui(11).foregroundStyle(t.text3.color)
            }
        }
        .padding(.vertical, 10).padding(.horizontal, 11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Radius.row, style: .continuous).fill(win.selectedId == item.id ? t.selection.color : t.surface.color))
        .overlay(RoundedRectangle(cornerRadius: Radius.row, style: .continuous)
            .strokeBorder(needs ? t.statusColor(.needsYou).color.opacity(0.6) : t.separator.color, lineWidth: 1))
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { model.reveal(item) }
        .onTapGesture { win.selectedId = item.id }
        .contextMenu { SessionContextMenu(model: model, item: item, win: win) }
        .onDrag { NSItemProvider(object: ("oneroof-session:" + item.id) as NSString) }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(row.name), \(StatusPalette.label(item.status)), \(row.caption.text)")
    }

    // MARK: Drag and drop

    private func drop(_ providers: [NSItemProvider], on c: Column) -> Bool {
        guard let p = providers.first else { return false }
        _ = p.loadObject(ofClass: NSString.self) { obj, _ in
            guard let raw = obj as? String else { return }
            let id = raw.hasPrefix("oneroof-session:") ? String(raw.dropFirst(16)) : raw
            DispatchQueue.main.async {
                guard let item = model.item(id) else { return }
                if c.tonight { tonightFor = id; return }
                guard let target = c.drop, !item.status.isLive || target == .doNotUse else {
                    flash = c.id
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { flash = nil }
                    return
                }
                withAnimation(Motion.slow) {
                    if target == .next { model.setLifecycle(item, item.status == .next ? .planned : .next) }
                    else { model.setLifecycle(item, target) }
                    model.unschedule(item)
                }
            }
        }
        return true
    }
}

/// Time popover for Tonight (S04 drop, S09 When).
struct TonightPicker: View {
    @Environment(\.theme) private var t
    var done: (Int, Int, Bool) -> Void
    @State private var time = Calendar.current.date(bySettingHour: 2, minute: 0, second: 0, of: Date()) ?? Date()
    @State private var nightly = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Run tonight at").ui(13, .semibold).foregroundStyle(t.text.color)
            DatePicker("", selection: $time, displayedComponents: .hourAndMinute).labelsHidden()
            Toggle("Every night", isOn: $nightly).ui(12.5)
            HStack {
                Spacer()
                RoofButton("Schedule", .primary) {
                    let c = Calendar.current.dateComponents([.hour, .minute], from: time)
                    done(c.hour ?? 2, c.minute ?? 0, nightly)
                }
            }
        }
        .padding(14).frame(width: 220)
    }
}
