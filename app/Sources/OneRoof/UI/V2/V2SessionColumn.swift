import AppKit
import SwiftUI
import OneRoofCore

/// The session column (handover A1.1, A1.8): window switcher · search · filter chips + Group ▾ · rows · dock line.
/// 280 pt at step 1, 250 pt at steps 0 and 2, avatars only (52 pt) at step 3. Rows are today's `SessionRow` with its
/// right-click menu, ••• popover, inline rename, ✕, drag and every row mark, so nothing a 0.5.2.9 row does is lost.
struct V2SessionColumn: View {
    @ObservedObject var model: AppModel
    @ObservedObject var win: WindowState
    let controller: MainWindowController
    /// The column slid over the terminal from the left edge at step 3 (C7.2): always the full list.
    var overlay = false

    var body: some View {
        Group {
            if win.focusStep == .focus && !overlay { V2AvatarColumn(model: model, win: win, controller: controller) }
            else { V2SessionList(model: model, win: win, controller: controller, overlay: overlay) }
        }
        .themed(model.themes.sidebar, scale: win.textScale)
    }
}

private struct V2SessionList: View {
    @Environment(\.theme) private var t
    @ObservedObject var model: AppModel
    @ObservedObject var win: WindowState
    let controller: MainWindowController
    let overlay: Bool
    @State private var popoverFor: String?
    @State private var showAllExited = false
    @FocusState private var searchFocused: Bool

    /// Exited rows shown before "+ n more ›" (A1.1 shows four).
    private let exitedShown = 4

    var body: some View {
        let now = Date()
        let groups = model.groups(in: win)
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                switcher
                search
                chips
                HStack {
                    groupMenu
                    Spacer()
                }
            }
            .padding(.horizontal, 10).padding(.top, 10).padding(.bottom, 6)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 1, pinnedViews: [.sectionHeaders]) {
                    if win.statusFilter == .exited, !groups.isEmpty {
                        Button("Remove all exited sessions") { model.removeExited() }
                            .buttonStyle(.link).ui(12).padding(.horizontal, 8).padding(.vertical, 6)
                    }
                    ForEach(groups) { g in
                        let exited = g.title == SessionStatus.exited.label
                        // The selected session always shows, even past the cap (1.8.1: it vanished behind "+ n more").
                        let rows = exited && !showAllExited
                            ? V2Layout.cappedRows(g.items, cap: exitedShown, id: \.id, keep: Set([win.selectedId].compactMap { $0 }))
                            : g.items
                        Section {
                            ForEach(rows) { item in
                                row(item, now: now).opacity(item.status == .exited ? 0.6 : 1)
                            }
                            if exited && !showAllExited && g.items.count > rows.count {
                                Button { showAllExited = true } label: {
                                    Text("+ \(g.items.count - rows.count) more ›").ui(11.5).foregroundStyle(t.text2.color)
                                }
                                .buttonStyle(.plain).padding(.horizontal, 8).padding(.vertical, 6)
                            }
                        } header: { groupHeader(g) }
                    }
                    if groups.isEmpty { empty }
                }
                .padding(.horizontal, 6).padding(.bottom, 8)
            }
            if win.focusStep == .sessions && !overlay && controller.v2DockFolded {
                Hairline()
                V2DockLine(model: model, controller: controller)
            }
        }
        .background(t.sidebar.color)
    }

    // MARK: Top

    /// "● Blogs & Public Presence   1 of 3 ▾": the window switcher (A10.4 right menu).
    private var switcher: some View {
        let accent = WindowAccent(named: win.colour, on: t)
        let (n, all) = controller.position
        return Button { controller.v2ShowWindowMenu() } label: {
            HStack(spacing: 6) {
                Circle().fill((accent?.ink ?? t.text3).color).frame(width: 8, height: 8)
                Text(win.name).ui(12.5, .semibold).foregroundStyle(t.text.color).lineLimit(1).truncationMode(.tail)
                Spacer(minLength: 4)
                Text("\(n) of \(all) ▾").ui(11).foregroundStyle(t.text3.color).fixedSize()
            }
            .padding(.horizontal, 10).frame(height: 30)
            .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(t.surface.color))
            .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(t.separator.color, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("This window is \u{201C}\(win.name)\u{201D}: switch windows, rename it, give it a colour")
        .accessibilityLabel("Window \(win.name), \(n) of \(all)")
    }

    /// "Search, or ask how do I… ⌘K". Typing filters the list (today's filter field); Return or ⌘K opens Search.
    private var search: some View {
        HStack(spacing: 6) {
            TextField("Search, or ask how do I…", text: $win.filter)
                .textFieldStyle(.plain).ui(12).foregroundStyle(t.text.color)
                .focused($searchFocused)
                .onSubmit { controller.v2OpenSearch(query: win.filter) }
            if !win.filter.isEmpty {
                Button { win.filter = "" } label: { Text("✕").ui(10).foregroundStyle(t.text3.color) }
                    .buttonStyle(.plain).accessibilityLabel("Clear filter")
            }
            Button { controller.v2OpenSearch(query: win.filter) } label: { Text("⌘K").ui(10.5).foregroundStyle(t.text3.color) }
                .buttonStyle(.plain).help("Search sessions, files, docs, tickets and Learn (⌘K)")
        }
        .padding(.horizontal, 9).frame(height: 28)
        .background(RoundedRectangle(cornerRadius: Radius.field, style: .continuous).fill(t.control.color))
    }

    /// All 16 · Need you 0 · Active 7 · Exited 9 (selected chip filled).
    private var chips: some View {
        let list = model.items(in: win)
        return ViewThatFits(in: .horizontal) {
            HStack(spacing: 4) { chipButtons(list) }
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) { chipButtons(list, Array(StatusChip.allCases.prefix(3))) }
                HStack(spacing: 4) { chipButtons(list, [.exited]) }
            }
        }
    }

    @ViewBuilder private func chipButtons(_ list: [BoardItem], _ chips: [StatusChip] = StatusChip.allCases) -> some View {
        ForEach(chips, id: \.self) { c in
            let n = list.filter { c.matches($0) }.count
            let on = (win.statusFilter ?? .all) == c
            Button { win.statusFilter = (on || c == .all) ? nil : c } label: {
                Text(Self.chipLabel(c, n)).ui(11, .semibold)
                    .foregroundStyle(on ? t.onAccent.color : (c == .needs && n > 0 ? t.needsText.color : t.text2.color))
                    .lineLimit(1).fixedSize()
                    .padding(.horizontal, 8).frame(height: 22)
                    .background(Capsule().fill(on ? t.text.color : t.surface.color))
            }
            .buttonStyle(.plain)
            .help(c.meaning)
            .accessibilityLabel(Self.chipLabel(c, n) + (on ? ", showing" : ""))
        }
    }

    static func chipLabel(_ c: StatusChip, _ n: Int) -> String {
        switch c { case .all: return "All \(n)"; case .needs: return "Need you \(n)"; case .active: return "Active \(n)"; case .exited: return "Exited \(n)" }
    }

    /// "Status ▾": Group sessions by Status, Repo, Project, Agent, Account, Folder (⌘1–⌘6, unchanged).
    private var groupMenu: some View {
        Menu {
            ForEach(Array(Grouping.allCases.enumerated()), id: \.element) { i, g in
                Button("\(g.label)  ⌘\(i + 1)") { model.grouping = g }
            }
        } label: {
            Text("\(model.grouping.label) ▾").ui(11).foregroundStyle(t.text2.color)
        }
        .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
        .help("Group sessions by (⌘1–⌘6)")
    }

    // MARK: Rows

    private func closeAction(_ item: BoardItem) -> (() -> Void)? {
        if item.liveAgent != nil { return { model.confirmClose(item) } }
        return item.adopted ? nil : { model.delete(item) }
    }

    private func row(_ item: BoardItem, now: Date) -> some View {
        SessionRow(row: model.rowData(item, now: now), density: .full, selected: win.selectedId == item.id, ring: t.sidebar,
                   onRename: { model.rename(item, $0) }, onClose: closeAction(item),
                   closeHelp: item.liveAgent != nil ? "Close session (asks first)" : "Remove session (⇧⌘T reopens it)")
            .modifier(RunTerminalIndent(isRun: item.session.parentSessionId != nil, colour: t.text2.color))
            .onTapGesture {
                win.selectedId = item.id
                controller.v2Open(.sessions)
                if overlay { controller.v2HideEdgeReveal() }
            }
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
        HStack(spacing: 4) {
            Text(g.title.uppercased() + " · \(g.items.count)").ui(10.5, .bold).tracking(0.4).foregroundStyle(t.text3.color).lineLimit(1)
            Spacer()
        }
        .padding(.horizontal, 8).padding(.top, 12).padding(.bottom, 4)
        .background(t.sidebar.color)
        .help(g.title == "Active" ? SessionStatus.activeMeaning : SessionStatus.allCases.first { $0.label == g.title }?.meaning ?? "")
    }

    private var empty: some View {
        VStack(alignment: .leading, spacing: 6) {
            if win.statusFilter != nil || !win.filter.isEmpty {
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
}

/// Step 3 (A1.4): 52 pt of avatars; the waiting one carries the Needs you badge; the selected one a blue ring, the
/// session that claimed the open file an outer ring in its colour (today's narrow rail).
struct V2AvatarColumn: View {
    @Environment(\.theme) private var t
    @ObservedObject var model: AppModel
    @ObservedObject var win: WindowState
    let controller: MainWindowController

    var body: some View {
        let claimer = win.viewerPath.flatMap { model.fileClaims.claim(for: $0)?.sessionId }
        ScrollView {
            VStack(spacing: 8) {
                ForEach(model.items(in: win)) { i in
                    let mark = AgentMark(agent: i.session.agent, account: i.account)
                    Button { win.selectedId = i.id; controller.v2Open(.sessions) } label: {
                        AgentBadge(mark, size: 30, status: i.status, ring: t.sidebar)
                            .padding(3)
                            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .strokeBorder(i.id == claimer ? mark.fill.color : (i.id == win.selectedId ? t.accent.color : .clear), lineWidth: 2))
                            .overlay(alignment: .topTrailing) {
                                if i.status == .needsYou { Circle().fill(t.statusColor(.needsYou).color).frame(width: 9, height: 9).offset(x: 1, y: -1) }
                            }
                    }
                    .buttonStyle(.plain)
                    .help(i.session.name + " · " + model.caption(for: i).text)
                    .accessibilityLabel(i.session.name + (i.status == .needsYou ? ", needs you" : ""))
                    .contextMenu { SessionContextMenu(model: model, item: i, win: win, editStickers: nil) }
                }
            }
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity)
        }
        .background(t.sidebar.color)
    }
}
