import SwiftUI
import OneRoofCore

/// Plan panel (S06 §1.5): tabs Plan · Ticket · Notes · Artifacts for the selected session, and the v0.1 Appearance
/// block at the bottom. Its own theme (default Graphite). With the centre closed it widens to a two-column form.
struct PlanPanelView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var win: WindowState

    var body: some View {
        Content(model: model, win: win).themed(model.themes.plan, scale: win.textScale)
    }

    private struct Content: View {
        @Environment(\.theme) private var t
        @ObservedObject var model: AppModel
        @ObservedObject var win: WindowState

        var body: some View {
            VStack(spacing: 0) {
                if let item = model.item(win.selectedId ?? "") {
                    PlanDetail(item: item, model: model, win: win).id(item.id)
                } else {
                    ScrollView { today.padding(16).frame(maxWidth: .infinity, alignment: .leading) }
                }
                Hairline()
                appearance
            }
            .background(t.window.color)
        }

        private var today: some View {
            let c = Board.counts(model.items(in: win))
            return VStack(alignment: .leading, spacing: 10) {
                Text(win.name).ui(TypeScale.title, .semibold).foregroundStyle(t.text.color)
                Text("\(c.needsYou) need you · \(c.running) working · \(c.done) ready · \(c.queued) next")
                    .ui(12.5).foregroundStyle(t.text2.color)
                Text("Select a session to see its plan, ticket, notes and artifacts. ⌘N starts a new one: Launch runs it in herdr on the agent and account you picked and sends the opening message once the agent is ready.")
                    .ui(12.5).foregroundStyle(t.text2.color).fixedSize(horizontal: false, vertical: true)
                if let err = model.lastError { Text(err).ui(12).foregroundStyle(t.needsText.color) }
            }
        }

        /// v0.1 Appearance block, kept (S06 §1.5): Sessions · Files · Terminal · This panel.
        private var appearance: some View {
            VStack(alignment: .leading, spacing: 4) {
                themeRow("Sessions", $model.chosenThemes.sidebar, ThemeName.panelChoices)
                themeRow("Files", $model.chosenThemes.files, ThemeName.panelChoices)
                themeRow("Terminal", $model.chosenThemes.terminal, ThemeName.terminalChoices)
                themeRow("This panel", $model.chosenThemes.plan, ThemeName.panelChoices)
                themeRow("Centre", $model.chosenThemes.centre, ThemeName.panelChoices)
            }
            .padding(.horizontal, 16).padding(.vertical, 10)
        }

        private func themeRow(_ label: String, _ binding: Binding<ThemeName>, _ choices: [ThemeName]) -> some View {
            HStack(spacing: 8) {
                Text(label).ui(12).foregroundStyle(t.text3.color).frame(width: 64, alignment: .leading)
                Menu {
                    ForEach(choices) { th in Button(th.label) { binding.wrappedValue = th } }
                } label: {
                    HStack(spacing: 3) {
                        Text(binding.wrappedValue.label).ui(12, .medium).foregroundStyle(t.text.color)
                        Text("▾").ui(9).foregroundStyle(t.text2.color)
                    }
                }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                .accessibilityLabel("\(label) theme \(binding.wrappedValue.label)")
                Spacer()
            }
        }
    }
}

/// Which Plan panel tab is showing, remembered per session.
enum PlanTab: String, CaseIterable { case plan, ticket, notes, artifacts }

struct PlanDetail: View {
    @Environment(\.theme) private var t
    let item: BoardItem
    @ObservedObject var model: AppModel
    @ObservedObject var win: WindowState

    @State private var tab: PlanTab = .plan
    @State private var name = ""
    @State private var workstream = ""
    @State private var objective = ""
    @State private var opening = ""
    @State private var notes = ""
    @State private var args = ""
    @State private var newSticker = ""
    @State private var addingSticker = false
    @State private var loaded = false
    @State private var showMore = false

    static var tabs: [String: PlanTab] = [:]

    var live: BoardItem { model.item(item.id) ?? item }

    var body: some View {
        VStack(spacing: 0) {
            tabBar
            Hairline()
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    switch tab {
                    case .plan: planTab
                    case .ticket: ticketTab
                    case .notes: notesTab
                    case .artifacts: artifactsTab
                    }
                    if let err = model.lastError {
                        Text(err).ui(12).foregroundStyle(t.needsText.color).fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .onAppear {
            load(); model.loadLearn()
            tab = PlanTab(rawValue: ProcessInfo.processInfo.environment["ONEROOF_SELFTEST_PLANTAB"] ?? "") ?? Self.tabs[item.id] ?? .plan
        }
        .onDisappear(perform: commit)
        .onChange(of: tab) { _, v in Self.tabs[item.id] = v }
    }

    // MARK: Tabs

    private var tabBar: some View {
        HStack(spacing: 16) {
            ForEach(PlanTab.allCases, id: \.self) { tb in
                Button { commit(); tab = tb } label: {
                    VStack(spacing: 6) {
                        Text(label(tb)).ui(TypeScale.small, .semibold).foregroundStyle(tab == tb ? t.text.color : t.text2.color)
                        Rectangle().fill(tab == tb ? t.accent.color : .clear).frame(height: 2)
                    }
                    .fixedSize()
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(tab == tb ? .isSelected : [])
            }
            Spacer()
            PanelCloseButton(title: "Plan panel", action: #selector(AppDelegate.togglePlanPanel(_:))).padding(.bottom, 8)
        }
        .padding(.horizontal, 16).padding(.top, 12)
    }

    private func label(_ tb: PlanTab) -> String {
        switch tb {
        case .plan: return "Plan"
        case .ticket: return "Ticket"
        case .notes: return "Notes"
        case .artifacts: return "Artifacts \(artifacts.count)"
        }
    }

    // MARK: Plan tab

    @ViewBuilder private var planTab: some View {
        let it = live
        HStack(spacing: 6) {
            StatusDot(status: it.status)
            Text(StatusPalette.label(it.status)).ui(13, .semibold).foregroundStyle(t.pill(it.status).text.color)
            Spacer()
            actionButton(it)
            Button { showMore = true } label: { Text("•••").ui(13, .semibold).foregroundStyle(t.text2.color) }
                .buttonStyle(.plain).help("More: stickers, colour, emoji, copy, windows")
                .popover(isPresented: $showMore, arrowEdge: .leading) {
                    SessionPopover(item: it, model: model, close: { showMore = false }, rename: {
                        showMore = false
                        DispatchQueue.main.async { NSApp.sendAction(#selector(AppDelegate.renameSelected(_:)), to: nil, from: nil) }
                    })
                    .themed(model.themes.plan)
                }
        }
        TextField("Session name", text: $name)
            .textFieldStyle(.plain).ui(TypeScale.title, .semibold).foregroundStyle(t.text.color)
            .onSubmit(commit)
        facts(it)
        if it.session.ticket != nil { TicketBox(item: it, model: model) }
        field("Workstream") {
            TextField("WS-…", text: $workstream).textFieldStyle(.plain).ui(12.5, mono: true)
                .padding(8).background(RoundedRectangle(cornerRadius: Radius.field).fill(t.card.color))
                .onSubmit(commit)
        }
        field("Objective · done when") { editor($objective, minHeight: 54) }
        let steps = planSteps(it)
        if !steps.isEmpty {
            field("Plan · \(steps.filter { $0.state == .done }.count) of \(steps.count)") { StepList(steps: steps) }
        }
        field("Stickers") { stickers(it) }
        relatedInLearn(it)
    }

    @ViewBuilder private func actionButton(_ it: BoardItem) -> some View {
        if model.busy.contains(it.id) {
            ProgressView().controlSize(.small)
        } else if it.liveAgent == nil && it.status != .doNotUse {
            RoofButton(it.status == .exited ? "Relaunch" : "Launch", .primary) {
                commit()
                if let fresh = model.item(it.id) { model.launch(fresh) }
            }
        } else if it.liveAgent != nil {
            RoofButton("Stop") { model.confirmClose(it) }
        }
    }

    private func facts(_ it: BoardItem) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            fact("Agent", [it.session.agent.displayName, it.account, it.session.model].compactMap { $0 }.joined(separator: " · "))
            fact("Repo", it.repoLabel)
            HStack(alignment: .top) {
                Text("Start folder").ui(12).foregroundStyle(t.text3.color).frame(width: 82, alignment: .leading)
                Text((it.session.launchDirectory as NSString).abbreviatingWithTildeInPath).ui(12.5).foregroundStyle(t.text.color).lineLimit(1)
                if !it.session.startInRepo { Text("✓ one memory").ui(12.5).foregroundStyle(t.statusDone.color).lineLimit(1).fixedSize() }
            }
            if let a = it.liveAgent { fact("herdr", a + (it.paneId.map { " · " + $0 } ?? ""), mono: true) }
            if let title = it.title, !title.isEmpty { fact("Title", title) }
            if let at = it.session.launchedAt { fact("Launched", at.formatted(date: .omitted, time: .shortened) + " · " + ageText(at)) }
            if it.adopted { fact("Source", "Started outside One Roof") }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(t.card.color))
    }

    private func fact(_ k: String, _ v: String, mono: Bool = false) -> some View {
        HStack(alignment: .top) {
            Text(k).ui(12).foregroundStyle(t.text3.color).frame(width: 82, alignment: .leading)
            Text(v).ui(12.5, mono: mono).foregroundStyle(t.text.color).textSelection(.enabled).lineLimit(2)
        }
    }

    /// Steps: the objective plan this session runs a step of, else the caption engine's step count.
    private func planSteps(_ it: BoardItem) -> [StepList.Step] {
        if let o = model.objectives.first(where: { $0.stepSessions.values.contains(it.id) }), let plan = o.plan {
            let mine = o.stepSessions.first { $0.value == it.id }?.key
            return plan.steps.enumerated().map { i, s in
                let done = o.stepResults[s.id]?.ok == true
                return StepList.Step(id: i, title: s.title, note: s.id == mine ? "this session" : nil,
                                     state: done ? .done : (s.id == mine ? .now : .todo))
            }
        }
        if let c = model.captions[it.id], let n = c.steps, let i = c.step, n > 0 {
            return (1...n).map { k in StepList.Step(id: k, title: "Step \(k)", note: k == i ? c.text : nil, state: k < i ? .done : (k == i ? .now : .todo)) }
        }
        return []
    }

    private func stickers(_ it: BoardItem) -> some View {
        let mine = Set(it.session.tags.map { Sticker.resolve($0).id })
        return FlowLayout(spacing: 5) {
            ForEach(Sticker.catalog.filter { !["next", "dnu"].contains($0.id) }) { s in
                Button { commit(); if let f = model.item(it.id) { model.toggleSticker(f, s.label) } } label: {
                    StickerTag(sticker: s, filled: mine.contains(s.id), size: 11.5)
                }.buttonStyle(.plain)
            }
            ForEach(it.session.tags.filter { !Sticker.resolve($0).builtIn }, id: \.self) { tag in
                Button { if let f = model.item(it.id) { model.toggleSticker(f, tag) } } label: {
                    StickerTag(sticker: Sticker.resolve(tag), filled: true, size: 11.5)
                }.buttonStyle(.plain)
            }
            if addingSticker {
                TextField("word", text: $newSticker, onCommit: {
                    let w = newSticker.trimmingCharacters(in: .whitespaces)
                    if !w.isEmpty, let f = model.item(it.id) { model.toggleSticker(f, w) }
                    newSticker = ""; addingSticker = false
                })
                .textFieldStyle(.plain).ui(11.5).frame(width: 90)
            } else {
                Button { addingSticker = true } label: {
                    Text("+ New").ui(11.5, .semibold).foregroundStyle(t.text3.color)
                        .padding(.vertical, 1).padding(.horizontal, 6)
                        .overlay(Capsule().strokeBorder(t.separatorStrong.color, style: StrokeStyle(lineWidth: 1, dash: [3, 2])))
                }.buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder private func relatedInLearn(_ it: BoardItem) -> some View {
        let related = it.session.agent.isAgent ? model.learnMatches(it.session.name + " " + it.session.objective, limit: 3) : []
        if !related.isEmpty {
            field("Related in Learn") {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(related) { r in
                        Button { model.learnTarget = r.id; model.show(.learn, in: win) } label: {
                            Text((r.audio ? "▸ " : "") + r.title).ui(12.5).foregroundStyle(t.accentText.color).lineLimit(1)
                        }.buttonStyle(.plain)
                    }
                    Button { model.howDoI(it.session.objective.isEmpty ? it.session.name : it.session.objective) } label: {
                        Text("More: how do I…").ui(11.5).foregroundStyle(t.text2.color)
                    }.buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: Ticket tab

    @ViewBuilder private var ticketTab: some View {
        let it = live
        if it.session.ticket != nil {
            TicketBox(item: it, model: model)
        } else {
            Text("No Linear ticket. Plan a session from a ticket in Work (⇧⌘W) to link one.").ui(12.5).foregroundStyle(t.text2.color)
        }
        if it.session.agent.isAgent {
            field(it.session.launchedAt == nil && !it.adopted ? "Opening message (sent when the agent is ready)" : "Opening message") {
                editor($opening, minHeight: 90)
            }
            field("Agent arguments") {
                TextField("e.g. --resume <id>", text: $args).textFieldStyle(.plain).ui(12.5, mono: true)
                    .padding(8).background(RoundedRectangle(cornerRadius: Radius.field).fill(t.card.color))
                    .onSubmit(commit)
            }
        }
    }

    // MARK: Notes tab

    @ViewBuilder private var notesTab: some View {
        field("Notes") { editor($notes, minHeight: 240) }
        HStack {
            RoofButton("Save", .primary) { commit() }.keyboardShortcut("s", modifiers: .command)
            Spacer()
        }
    }

    // MARK: Artifacts tab

    private var artifacts: [String] {
        let s = live.session
        var out: [String] = []
        if let o = model.objectives.first(where: { $0.stepSessions.values.contains(s.id) }) {
            let p = o.planPath(common: model.settings.sharedFolder)
            if FileManager.default.fileExists(atPath: p) { out.append(p) }
        }
        // Newest handoffs that name this session's workstream.
        if let ws = s.workstream?.lowercased() {
            let dir = model.settings.sharedFolder + "/docs/next-session-handoff"
            let files = (try? FileManager.default.contentsOfDirectory(atPath: dir)) ?? []
            out += files.filter { $0.lowercased().contains(ws) }.sorted().suffix(3).reversed().map { dir + "/" + $0 }
        }
        return out
    }

    @ViewBuilder private var artifactsTab: some View {
        if artifacts.isEmpty {
            Text("No artifacts yet. Plan files, handoffs and screenshots for this session show here.").ui(12.5).foregroundStyle(t.text2.color)
        }
        ForEach(artifacts, id: \.self) { p in
            Button { model.openInViewer(p) } label: {
                HStack(spacing: 8) {
                    Image(systemName: p.hasSuffix(".png") ? "photo" : "doc.text").foregroundStyle(t.text2.color)
                    VStack(alignment: .leading, spacing: 1) {
                        Text((p as NSString).lastPathComponent).ui(12.5, .medium).foregroundStyle(t.text.color).lineLimit(1)
                        Text(((p as NSString).deletingLastPathComponent as NSString).abbreviatingWithTildeInPath).ui(11).foregroundStyle(t.text3.color).lineLimit(1)
                    }
                    Spacer()
                }
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(t.card.color))
            }.buttonStyle(.plain)
        }
    }

    // MARK: Fields

    private func field<C: View>(_ label: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label).ui(12, .semibold).foregroundStyle(t.text2.color)
            content()
        }
    }

    private func editor(_ text: Binding<String>, minHeight: CGFloat) -> some View {
        TextEditor(text: text)
            .ui(13)
            .scrollContentBackground(.hidden)
            .padding(6)
            .frame(minHeight: minHeight)
            .background(RoundedRectangle(cornerRadius: Radius.field, style: .continuous).fill(t.card.color))
            .foregroundStyle(t.text.color)
    }

    private func load() {
        guard !loaded else { return }
        let s = item.session
        name = s.name; workstream = s.workstream ?? ""; objective = s.objective
        opening = s.openingMessage; notes = s.notes; args = s.agentArgs.joined(separator: " ")
        loaded = true
    }

    private func commit() {
        guard loaded, let fresh = model.item(item.id) else { return }
        let s = fresh.session
        let ws = workstream.trimmingCharacters(in: .whitespaces)
        let argList = args.split(separator: " ").map(String.init)
        let changed = s.name != name || (s.workstream ?? "") != ws || s.objective != objective
            || s.openingMessage != opening || s.notes != notes || s.agentArgs != argList
        guard changed else { return }
        model.update(fresh) {
            $0.name = name.isEmpty ? $0.name : name
            $0.workstream = ws.isEmpty ? nil : ws.uppercased()
            $0.objective = objective
            $0.openingMessage = opening
            $0.notes = notes
            $0.agentArgs = argList
        }
    }
}

/// The session's Linear ticket (COMPONENTS TicketBox): key, state pill, Linear ↗, state buttons.
struct TicketBox: View {
    @Environment(\.theme) private var t
    let item: BoardItem
    @ObservedObject var model: AppModel
    @State private var state = ""
    @State private var url = ""
    @State private var busy = false

    var body: some View {
        let s = item.session
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(s.ticket ?? "").ui(12.5, .semibold, mono: true).foregroundStyle(t.text.color)
                if !state.isEmpty {
                    Text(state).ui(10.5, .semibold).foregroundStyle(t.accentText.color)
                        .padding(.horizontal, 6).padding(.vertical, 1)
                        .background(Capsule().fill(t.selection.color))
                }
                Spacer()
                if busy { ProgressView().controlSize(.mini) }
                if let u = URL(string: url), !url.isEmpty {
                    Link(destination: u) { Text("Linear ↗").ui(11.5).foregroundStyle(t.text3.color) }
                }
            }
            HStack(spacing: 4) {
                ForEach(["Backlog", "In Progress", "In Review", "Done"], id: \.self) { st in
                    let on = state == st
                    Button {
                        busy = true
                        model.moveTicket(of: s, to: st, comment: ["In Review", "Done"].contains(st) ? model.sessionSummary(item) : nil) { err in
                            busy = false
                            if err == nil { state = st }
                        }
                    } label: {
                        Text(st).ui(11.5, .medium).foregroundStyle(on ? t.onAccent.color : t.text.color)
                            .padding(.vertical, 4).padding(.horizontal, 8)
                            .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(on ? t.accent.color : t.surface2.color))
                            .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(t.separator.color))
                    }
                    .buttonStyle(.plain).disabled(on || busy)
                }
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(t.card.color))
        .onAppear(perform: load)
        .onReceive(model.$issues) { all in
            if let id = item.session.ticketId, let i = all.values.joined().first(where: { $0.id == id }) { state = i.state }
        }
    }

    private func load() {
        guard let id = item.session.ticketId else { return }
        DispatchQueue.global(qos: .userInitiated).async {
            if let r = try? model.linear.issueState(id) { DispatchQueue.main.async { state = r.name; url = r.url } }
        }
    }
}
