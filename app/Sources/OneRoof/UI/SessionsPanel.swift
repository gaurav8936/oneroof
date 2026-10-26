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
            // LAB-651 / LAB-714: the rail follows the panel's width, not the centre view. The Editor still folds the
            // panel to 56 pt (S07 §1.1); dragging it wider, or the rail's widen button, brings the full list back.
            GeometryReader { g in
                if SessionsRail.shows(width: g.size.width) { rail } else { full }
            }
        }

        /// The narrow panel (the Editor folds it to 56 pt): badge + status dot per session (S07 §1.1).
        private var rail: some View {
            let claimer = win.viewerPath.flatMap { model.fileClaims.claim(for: $0)?.sessionId }
            return ScrollView {
                VStack(spacing: 8) {
                    Button { controller.widenSessions() } label: {
                        Image(systemName: "chevron.right.2").font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(t.text2.color).frame(width: 32, height: 22).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Show the full Sessions list (or drag the panel's edge wider)")
                    .accessibilityLabel("Show the full Sessions list")
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
                        if win.statusFilter == .exited, !model.groups(in: win).isEmpty {
                            // Exited agents: relaunch one (select it), or clear them all at once.
                            Button("Remove all exited sessions") { model.removeExited() }
                                .buttonStyle(.link).ui(12).padding(.horizontal, 8).padding(.vertical, 6)
                        }
                        ForEach(model.groups(in: win)) { g in
                            Section {
                                ForEach(g.items) { item in
                                    row(item, now: now)
                                }
                            } header: { groupHeader(g) }
                        }
                        if model.groups(in: win).isEmpty { empty }
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
            // Two rows of two (LAB-515: All · Needs you · Active · Exited), every label in full at the panel's width.
            return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 5), count: 2), spacing: 5) {
                ForEach(StatusChip.allCases, id: \.self) { c in
                    let n = list.filter { c.matches($0) }.count
                    let on = (win.statusFilter ?? .all) == c
                    Button { win.statusFilter = (on || c == .all) ? nil : c } label: {
                        Text(c.label(n)).ui(11.5, .semibold)
                            .foregroundStyle(c == .needs && n > 0 ? t.pill(.needsYou).text.color : t.text.color)
                            .lineLimit(1).minimumScaleFactor(0.8)
                            .frame(maxWidth: .infinity, minHeight: 26, alignment: .leading)
                            .padding(.horizontal, 6)
                            .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(c == .needs && n > 0 ? (t.pill(.needsYou).fill ?? t.surface).color : t.surface.color))
                            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .strokeBorder(on ? t.accent.color : t.separator.color, lineWidth: on ? 1.5 : 1))
                    }
                    .buttonStyle(.plain)
                    .help(c.meaning)
                    .accessibilityLabel(c.label(n).replacingOccurrences(of: "\n", with: " ") + (on ? ", showing" : ""))
                }
            }
        }

        // MARK: Rows

        /// The row's ✕: a live session closes after the usual question; a stopped one is removed (Reopen Closed Session
        /// brings it back). Adopted sessions have no ✕, like the menu's Delete.
        private func closeAction(_ item: BoardItem) -> (() -> Void)? {
            if item.liveAgent != nil { return { model.confirmClose(item) } }
            return item.adopted ? nil : { model.delete(item) }
        }

        private func row(_ item: BoardItem, now: Date) -> some View {
            SessionRow(row: model.rowData(item, now: now), density: .full, selected: win.selectedId == item.id, ring: t.sidebar,
                       onRename: { model.rename(item, $0) }, onClose: closeAction(item),
                       closeHelp: item.liveAgent != nil ? "Close session (asks first)" : "Remove session (⇧⌘T reopens it)")
                .modifier(RunTerminalIndent(isRun: item.session.parentSessionId != nil, colour: t.text2.color))
                .onTapGesture { win.selectedId = item.id; model.show(.workspace, in: win) }
                .contextMenu { SessionContextMenu(model: model, item: item, win: win, editStickers: { popoverFor = item.id }) }
                .popover(isPresented: Binding(get: { popoverFor == item.id }, set: { if !$0 { popoverFor = nil } }), arrowEdge: .trailing) {
                    SessionPopover(item: item, model: model, close: { popoverFor = nil }, rename: {
                        popoverFor = nil
                        win.selectedId = item.id
                        DispatchQueue.main.async { NSApp.sendAction(#selector(AppDelegate.renameSelected(_:)), to: nil, from: nil) }
                    }, attachIssue: {
                        popoverFor = nil
                        win.selectedId = item.id
                        DispatchQueue.main.async { NSApp.sendAction(#selector(AppDelegate.attachIssueToSelected(_:)), to: nil, from: nil) }
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
            .help(g.title == "Active" ? SessionStatus.activeMeaning : SessionStatus.allCases.first { $0.label == g.title }?.meaning ?? "")
        }

        private var empty: some View {
            VStack(alignment: .leading, spacing: 6) {
                if win.statusFilter != nil || !win.filter.isEmpty {
                    // The list is filtered, not empty: say so and offer the way back.
                    Text("Nothing matches the filter").ui(13, .semibold).foregroundStyle(t.text.color)
                    Button("Show all \(model.items(in: win).count) sessions") { win.statusFilter = nil; win.filter = "" }
                        .buttonStyle(.link).ui(12)
                } else {
                    Text("No sessions in \(win.name)").ui(13, .semibold).foregroundStyle(t.text.color)
                    Text("Press ⌘N for a new session. Agents you start in a One Roof terminal show up here too.")
                        .ui(12).foregroundStyle(t.text2.color)
                }
            }
            .padding(12)
        }

        // MARK: Footer

        private var footer: some View {
            HStack(spacing: 6) {
                Circle().fill(t.statusColor(model.runtimeOK ? .done : .needsYou).color).frame(width: 7, height: 7)
                Text(model.runtimeState).ui(11.5).foregroundStyle(t.text2.color).lineLimit(1)
                // LAB-526: a quiet note (not a warning colour) when the running roofd is older than this app.
                if let note = AppVersion.daemonOlderNote(model.daemonVersion, app: AppVersion.current?.short) {
                    Text("· older than app").ui(11.5).foregroundStyle(t.text3.color).lineLimit(1).fixedSize()
                        .help(note).accessibilityLabel(note)
                }
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
        } else if it.liveAgent != nil {
            Button("Open") { model.reveal(it) }
        }
        // Next = scheduling: "do this one next" (LAB-257). A planned session moves to Next; a live one gets the Next sticker.
        if !it.status.isLive {
            Button(it.status == .next ? "Mark as Planned" : "Mark as Next") { model.setLifecycle(it, it.status == .next ? .planned : .next) }
        } else {
            let next = it.session.tags.contains { Sticker.resolve($0).id == "next" }
            Button(next ? "Not Next" : "Mark as Next") { model.toggleSticker(it, "next") }
        }
        Button(it.status == .doNotUse ? "Use Again" : "Do Not Use") { model.toggleSticker(it, "dnu") }
        Button(it.session.pinned ? "Unpin" : "Pin") { model.togglePin(it) }
        if it.status != .doNotUse {
            Button(it.session.ticket == nil ? "Attach Issue…" : "Add Issue…") {
                win?.selectedId = it.id
                DispatchQueue.main.async { NSApp.sendAction(#selector(AppDelegate.attachIssueToSelected(_:)), to: nil, from: nil) }
            }
        }
        // Loops (LAB-254): send the session's message again every N minutes while it waits; launch it if it is not running.
        if it.session.agent.isAgent {
            let looping = model.scheduleRecords[it.id]?.schedule.interval != nil
            Menu(looping ? "Repeat (\(model.scheduleRecords[it.id]?.schedule.label ?? ""))" : "Repeat") {
                if model.loopMessage(it) == nil {
                    Text("Give it an opening message first (Plan panel)")
                } else {
                    ForEach(Schedule.everyChoices, id: \.self) { m in
                        Button("Every " + Schedule.every(m)) { model.repeatEvery(it, minutes: m) }
                    }
                }
                if looping {
                    Divider()
                    Button("Stop Repeating") { model.unschedule(it) }
                }
            }
        }
        Divider()
        // LAB-300: stickers are labels only (the meaning was noise), and colours and emoji sit in the menu itself as
        // rows of swatches, one click each, instead of a submenu of colour names or a second panel.
        Section("Stickers") {
            let ids = Set(it.session.tags.map { Sticker.resolve($0).id })
            ForEach(Sticker.pickable(for: it.session.tags)) { s in
                Toggle(isOn: Binding(get: { ids.contains(s.id) }, set: { _ in model.toggleSticker(it, s.id) })) {
                    Label { Text(s.label) } icon: { Image(nsImage: MenuArt.sticker(s)) }
                }
            }
        }
        Section("Row Colour") {
            let current = Pastel.named(it.session.color)
            ControlGroup {
                Button { model.setColor(it, nil) } label: {
                    Label { Text("No Colour") } icon: { Image(nsImage: MenuArt.swatch(nil, selected: current == nil)) }
                }
                ForEach(Sticker.rowColors, id: \.name) { p in
                    Button { model.setColor(it, p.name) } label: {
                        Label { Text(p.name.capitalized) } icon: { Image(nsImage: MenuArt.swatch(p, selected: current == p)) }
                    }
                }
            }
            .controlGroupStyle(.palette)
        }
        Section("Emoji") {
            let choices: [String?] = [nil] + Sticker.emojiChoices.map { Optional($0) }
            let half = (choices.count + 1) / 2
            ForEach([Array(choices.prefix(half)), Array(choices.dropFirst(half))], id: \.self) { line in
                ControlGroup {
                    ForEach(line, id: \.self) { e in
                        Button { model.setIcon(it, e) } label: {
                            Label { Text(e.map { "Emoji " + $0 } ?? "No Emoji") } icon: { Image(nsImage: MenuArt.emoji(e, selected: it.session.icon == e)) }
                        }
                    }
                }
                .controlGroupStyle(.palette)
            }
        }
        if let editStickers { Button("Emoji, New Sticker and Rename…") { editStickers() } }
        Divider()
        Menu("Move to Window") {
            ForEach(model.windows) { w in
                Button(w.name) { model.move(it, to: w) }.disabled(model.workspaceId(of: it) == w.id)
            }
            Divider()
            Button("New Workspace Window…") { NotificationCenter.default.post(name: .newWorkspaceMoving, object: it.id) }
        }
        if it.liveAgent != nil {
            Button("Open in New Window") { PopOutWindowController.popOut(it, model: model) }
            Button("Roof Window for \(Workspace.repoLabel(for: it.session.repoPath))") { RoofWindowController.show(.repo(it.session.repoPath), model: model) }
        }
        Button("Review Changes") { model.reveal(it); model.openDiff(it.session.repoPath) }
        Button("Terminal Here") { model.newTerminal(in: it.session.repoPath) }
        Button("Show Folder in Finder") { NSWorkspace.shared.open(URL(fileURLWithPath: it.session.repoPath)) }
        Button("Copy Folder Path") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(it.session.launchDirectory, forType: .string)
        }
        Button("Copy Link to Session") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(RoofLink.link(session: it.id), forType: .string)
        }
        if let a = it.liveAgent {
            Button("Copy Attach Command") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(model.runtime.attachCommand(a), forType: .string)
            }
        }
        Divider()
        if it.liveAgent != nil { Button("Close Agent…") { model.confirmClose(it) } }
        if !it.adopted { Button("Delete") { model.delete(it) } }
    }
}

/// LAB-598: a run terminal's row sits under its agent's row, indented, with ↳.
struct RunTerminalIndent: ViewModifier {
    let isRun: Bool
    let colour: Color
    func body(content: Content) -> some View {
        if isRun {
            HStack(spacing: 2) {
                Text("↳").ui(12).foregroundStyle(colour).accessibilityHidden(true)
                content
            }
            .padding(.leading, 8)
            .help("Run terminal: commands you send here with Right-click › Run in Terminal wait for your Return")
        } else {
            content
        }
    }
}
