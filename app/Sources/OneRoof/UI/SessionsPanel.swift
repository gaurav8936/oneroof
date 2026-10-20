import SwiftUI
import OneRoofCore

/// Sessions panel (S06 §1.2): seat bars, count chips, Group ▾ + filter, grouped rows, footer. Sidebar theme.
struct SessionsPanel: View {
    @ObservedObject var model: AppModel
    @ObservedObject var win: WindowState
    let controller: MainWindowController

    var body: some View {
        Content(model: model, win: win, controller: controller)
            .themed(model.themes.sidebar, scale: win.textScale)
    }

    private struct Content: View {
        @Environment(\.theme) private var t
        @ObservedObject var model: AppModel
        @ObservedObject var win: WindowState
        let controller: MainWindowController
        @State private var popoverFor: String?

        var body: some View {
            if win.centre == .editor { rail } else { full }
        }

        /// The Editor folds the panel to a 56 pt rail: badge + status dot per session (S07 §1.1).
        private var rail: some View {
            let claimer = win.viewerPath.flatMap { model.fileClaims.claim(for: $0)?.sessionId }
            return ScrollView {
                VStack(spacing: 8) {
                    ForEach(model.items(in: win)) { i in
                        let mark = AgentMark(agent: i.session.agent, account: i.account)
                        Button { win.selectedId = i.id; model.show(.workspace, in: win) } label: {
                            AgentBadge(mark, size: 32, status: i.status, ring: t.sidebar)
                                .padding(3)
                                .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous)
                                    .strokeBorder(i.id == claimer ? mark.fill.color : (i.id == win.selectedId ? t.accent.color : .clear), lineWidth: 2))
                        }
                        .buttonStyle(.plain)
                        .help(i.session.name + " · " + model.caption(for: i).text)
                    }
                }
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity)
            }
            .background(t.sidebar.color)
        }

        private var full: some View {
            let now = Date()
            return VStack(spacing: 0) {
                top
                Hairline()
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 1, pinnedViews: [.sectionHeaders]) {
                        ForEach(model.groups(in: win)) { g in
                            Section {
                                ForEach(g.items) { item in
                                    row(item, now: now)
                                }
                            } header: { groupHeader(g) }
                        }
                        if model.items(in: win).isEmpty { empty }
                    }
                    .padding(.horizontal, 8).padding(.bottom, 8)
                }
                Hairline()
                footer
            }
            .background(t.sidebar.color)
        }

        // MARK: Top block

        private var top: some View {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 6) {
                    seatBars
                    PanelCloseButton(title: "Sessions", action: #selector(AppDelegate.toggleSidebarPanel(_:)))
                }
                chips
                HStack(spacing: 8) {
                    Text("Group").ui(12).foregroundStyle(t.text2.color)
                    FieldMenu(title: model.grouping.label, height: 26, expand: false) {
                        ForEach(Array(Grouping.allCases.enumerated()), id: \.element) { i, g in
                            Button("\(g.label)  ⌘\(i + 1)") { model.grouping = g }
                        }
                    }
                    HStack(spacing: 4) {
                        TextField("Filter", text: $win.filter)
                            .textFieldStyle(.plain).ui(12.5).foregroundStyle(t.text.color)
                        if !win.filter.isEmpty {
                            Button { win.filter = "" } label: { Text("✕").ui(10).foregroundStyle(t.text3.color) }
                                .buttonStyle(.plain).accessibilityLabel("Clear filter")
                        }
                    }
                    .padding(.horizontal, 8).frame(height: 26)
                    .background(RoundedRectangle(cornerRadius: Radius.field, style: .continuous).fill(t.control.color))
                }
            }
            .padding(12)
        }

        private var seatBars: some View {
            let seats = Dictionary(model.seats.map { ($0.seat, $0) }, uniquingKeysWith: { a, _ in a })
            return HStack(spacing: 8) {
                ForEach(AgentMark.available([.claude1, .claude2, .codex, .kimi, .gemini]), id: \.self) { m in
                    SeatGauge(mark: m, used: seats[seatName(m)]?.worst)
                        .help(seatHelp(seats[seatName(m)], m))
                }
            }
        }

        private var chips: some View {
            let list = model.items(in: win)
            return HStack(spacing: 6) {
                ForEach(StatusChip.allCases, id: \.self) { c in
                    let n = list.filter { c.statuses.contains($0.status) }.count
                    let on = win.statusFilter == c
                    Button { win.statusFilter = on ? nil : c } label: {
                        Text(c.label(n)).ui(11.5, .semibold)
                            .foregroundStyle(c == .needs && n > 0 ? t.pill(.needsYou).text.color : t.text.color)
                            .lineLimit(2).multilineTextAlignment(.leading).minimumScaleFactor(0.85)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, minHeight: 34, alignment: .leading)
                            .padding(.horizontal, 7)
                            .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(c == .needs && n > 0 ? (t.pill(.needsYou).fill ?? t.surface).color : t.surface.color))
                            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .strokeBorder(on ? t.accent.color : t.separator.color, lineWidth: on ? 1.5 : 1))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(c.label(n) + (on ? ", filtering" : ""))
                }
            }
        }

        // MARK: Rows

        private func row(_ item: BoardItem, now: Date) -> some View {
            SessionRow(row: model.rowData(item, now: now), density: .full, selected: win.selectedId == item.id, ring: t.sidebar,
                       onRename: { model.rename(item, $0) })
                .onTapGesture { win.selectedId = item.id; model.show(.workspace, in: win) }
                .contextMenu { SessionContextMenu(model: model, item: item, win: win, editStickers: { popoverFor = item.id }) }
                .popover(isPresented: Binding(get: { popoverFor == item.id }, set: { if !$0 { popoverFor = nil } }), arrowEdge: .trailing) {
                    SessionPopover(item: item, model: model, close: { popoverFor = nil }, rename: {
                        popoverFor = nil
                        win.selectedId = item.id
                        DispatchQueue.main.async { NSApp.sendAction(#selector(AppDelegate.renameSelected(_:)), to: nil, from: nil) }
                    })
                        .themed(model.themes.sidebar)
                }
                .onDrag { NSItemProvider(object: ("oneroof-session:" + item.id) as NSString) }
                .id(item.id)
        }

        private func groupHeader(_ g: BoardGroup) -> some View {
            HStack(spacing: 6) {
                Text(g.title.uppercased()).ui(11.5, .bold).tracking(0.5).foregroundStyle(t.text.color).lineLimit(1)
                Text("\(g.items.count)").ui(11, .semibold).foregroundStyle(t.text2.color)
                    .padding(.horizontal, 6).padding(.vertical, 1)
                    .background(Capsule().fill(t.control.color))
                Spacer()
            }
            .padding(.horizontal, 8).padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(t.surface2.color))
            .padding(.top, 10).padding(.bottom, 4)
            .background(t.sidebar.color)
        }

        private var empty: some View {
            VStack(alignment: .leading, spacing: 6) {
                Text("No sessions in \(win.name)").ui(13, .semibold).foregroundStyle(t.text.color)
                Text("Press ⌘N for a new session. Agents you start in herdr from anywhere show up in the first window.")
                    .ui(12).foregroundStyle(t.text2.color)
            }
            .padding(12)
        }

        // MARK: Footer

        private var footer: some View {
            HStack(spacing: 6) {
                Circle().fill(t.statusColor(model.runtimeOK ? .done : .needsYou).color).frame(width: 7, height: 7)
                Text(model.runtimeState).ui(11.5).foregroundStyle(t.text2.color).lineLimit(1)
                Spacer()
                Button { NotificationCenter.default.post(name: .openFoundations, object: nil) } label: {
                    let issues = model.foundations.filter { $0.level != .ok }.count
                    if model.checkingFoundations {
                        Text("Checking…").ui(11.5).foregroundStyle(t.text3.color).lineLimit(1).fixedSize()
                    } else if issues > 0 {
                        Text("\(issues) foundations issue\(issues == 1 ? "" : "s")").ui(11.5, .medium).foregroundStyle(t.needsText.color)
                            .lineLimit(1).fixedSize()
                    } else {
                        Text(model.foundations.isEmpty ? "Foundations" : "Foundations ok").ui(11.5).foregroundStyle(t.text2.color)
                    }
                }
                .buttonStyle(.plain)
                .help("Startup check: doors, guard, memory, skills, hooks, MCP, logins (⇧⌘F)")
            }
            .padding(.vertical, 9).padding(.horizontal, 12)
        }

        private func seatName(_ m: AgentMark) -> String {
            switch m {
            case .claude1: return "Claude1"
            case .claude2: return "Claude2"
            case .codex: return "Codex"
            case .kimi: return "Kimi"
            case .gemini: return "Gemini"
            default: return m.rawValue
            }
        }

        private func seatHelp(_ s: SeatUsage?, _ m: AgentMark) -> String {
            guard let s else { return "\(m.mono): no usage feed" }
            var parts: [String] = []
            if let f = s.fiveHour { parts.append("5 h \(Int(f))%") }
            if let w = s.sevenDay { parts.append("7 d \(Int(w))%") }
            if let r = s.fiveHourResets { parts.append("resets \(r.formatted(date: .omitted, time: .shortened))") }
            return "\(s.seat): " + parts.joined(separator: " · ")
        }
    }
}

/// Context menu on a session row or card (WINDOW_SHELL §5).
struct SessionContextMenu: View {
    @ObservedObject var model: AppModel
    let item: BoardItem
    var win: WindowState?
    var editStickers: (() -> Void)?

    var body: some View {
        let it = model.item(item.id) ?? item
        if it.liveAgent == nil && it.status != .doNotUse {
            Button(it.status == .exited ? "Relaunch" : "Launch") { model.launch(it) }
        }
        if !it.status.isLive {
            Button(it.status == .next ? "Mark as Planned" : "Mark as Next") { model.setLifecycle(it, it.status == .next ? .planned : .next) }
        }
        Button(it.status == .doNotUse ? "Use Again" : "Do Not Use") { model.toggleSticker(it, "dnu") }
        Button(it.session.pinned ? "Unpin" : "Pin") { model.togglePin(it) }
        Divider()
        Section("Stickers") {
            let ids = Set(it.session.tags.map { Sticker.resolve($0).id })
            let customs = it.session.tags.map(Sticker.resolve).filter { !$0.builtIn }
            ForEach(Sticker.catalog.filter { $0.id != "next" && $0.id != "dnu" } + customs) { s in
                Toggle(s.label, isOn: Binding(get: { ids.contains(s.id) }, set: { _ in model.toggleSticker(it, s.id) }))
            }
        }
        Menu("Colour") {
            Button("None") { model.setColor(it, nil) }
            ForEach(Sticker.rowColors, id: \.name) { p in
                Toggle(p.name.capitalized, isOn: Binding(get: { Pastel.named(it.session.color) == p }, set: { _ in model.setColor(it, p.name) }))
            }
        }
        if let editStickers { Button("Emoji and New Sticker…") { editStickers() } }
        Divider()
        Menu("Move to Window") {
            ForEach(model.windows) { w in
                Button(w.name) { model.move(it, to: w) }.disabled(model.workspaceId(of: it) == w.id)
            }
            Divider()
            Button("New Workspace Window…") { NSApp.sendAction(#selector(AppDelegate.newWorkspaceWindow(_:)), to: nil, from: nil) }
        }
        if it.liveAgent != nil {
            Button("Open in New Window") { PopOutWindowController.popOut(it, model: model) }
            Button("Roof Window for \(it.repoLabel)") { RoofWindowController.show(.repo(it.session.repoPath), model: model) }
        }
        Button("Review Changes") { model.reveal(it); model.openDiff(it.session.repoPath) }
        Button("Terminal Here") { model.newTerminal(in: it.session.repoPath) }
        Button("Copy Link to Session") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(RoofLink.link(session: it.id), forType: .string)
        }
        Divider()
        if it.liveAgent != nil { Button("Close Agent…") { model.confirmClose(it) } }
        if !it.adopted { Button("Delete") { model.delete(it) } }
    }
}
