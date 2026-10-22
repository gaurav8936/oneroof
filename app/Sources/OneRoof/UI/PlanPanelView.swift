import SwiftUI
import OneRoofCore

/// Plan panel (S06 §1.5): tabs Plan · Ticket · Notes · Artifacts · Resources (LAB-493) for the selected session, and the v0.1 Appearance
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
                Text("Select a session to see its plan, ticket, notes and artifacts. ⌘N starts a new one: Launch runs it on the agent and account you picked and sends the opening message once the agent is ready.")
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
enum PlanTab: String, CaseIterable { case plan, ticket, notes, artifacts, resources }

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
    /// The session's fields as last loaded or saved; Save writes only what differs from it (LAB-487).
    @State private var base: SessionEdits?
    @State private var savedAt: Date?
    @State private var mentioned: [(issue: LinearIssue, team: String, project: String?)] = []
    /// The Artifacts tab's list, kept here and refreshed off the main thread: it reads the handoff folder, so working it
    /// out in the tab label on every redraw froze the window (0.4.8).
    @State private var artifactItems: [SessionArtifacts.Item] = []

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
                    case .resources: SessionResourcesTab(item: live, res: model.resources)
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
        // Changed elsewhere (Rename…, the popover, an agent): show it in every field the owner is not editing here.
        .onChange(of: live.session) { _, s in rebase(onto: s) }
        // Again whenever the session changes, and every 10 s for handoffs the agent writes meanwhile.
        .task(id: live.session) {
            while !Task.isCancelled {
                await refreshArtifacts()
                try? await Task.sleep(for: .seconds(10))
            }
        }
    }

    // MARK: Tabs

    /// Five tabs since Resources (LAB-493) are wider than a narrow panel: the row tightens its spacing first and only
    /// then shortens Resources (Usage), and Artifacts (Files) last, so no tab is ever clipped off the edge.
    /// LAB-548: at the panel's narrowest (260 pt, or larger text) even the short labels did not fit, and a row wider
    /// than the panel pushed the whole panel off both edges (Plan cut on the left, ✕ on the right, the content
    /// squeezed sideways). Last come tighter margins, then icons with the chosen tab's name, then icons alone, and the
    /// bar is clipped to the panel's width whatever happens.
    private var tabBar: some View {
        ViewThatFits(in: .horizontal) {
            tabRow(spacing: 16, style: .full)
            tabRow(spacing: 9, style: .full)
            tabRow(spacing: 9, style: .shortResources)
            tabRow(spacing: 9, style: .short)
            tabRow(spacing: 7, style: .short, margin: 10)
            tabRow(spacing: 10, style: .iconsWithChosen, margin: 10)
            tabRow(spacing: 8, style: .icons, margin: 10)
        }
        .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
        .clipped()
    }

    enum TabStyle { case full, shortResources, short, iconsWithChosen, icons }

    private func tabRow(spacing: CGFloat, style: TabStyle, margin: CGFloat = 16) -> some View {
        HStack(spacing: spacing) {
            ForEach(PlanTab.allCases, id: \.self) { tb in
                Button { commit(); tab = tb } label: {
                    VStack(spacing: 6) {
                        tabLabel(tb, style: style).foregroundStyle(tab == tb ? t.text.color : t.text2.color)
                        Rectangle().fill(tab == tb ? t.accent.color : .clear).frame(height: 2)
                    }
                    .fixedSize()
                }
                .buttonStyle(.plain)
                .help(label(tb))
                .accessibilityLabel(label(tb))
                .accessibilityAddTraits(tab == tb ? .isSelected : [])
            }
            Spacer(minLength: 4)
            PanelCloseButton(title: "Plan panel", action: #selector(AppDelegate.togglePlanPanel(_:))).padding(.bottom, 8)
        }
        .padding(.horizontal, margin).padding(.top, 12)
    }

    @ViewBuilder private func tabLabel(_ tb: PlanTab, style: TabStyle) -> some View {
        switch style {
        case .full: Text(label(tb)).ui(TypeScale.small, .semibold)
        case .shortResources: Text(label(tb, short: tb == .resources)).ui(TypeScale.small, .semibold)
        case .short: Text(label(tb, short: true)).ui(TypeScale.small, .semibold)
        case .iconsWithChosen, .icons:
            HStack(spacing: 4) {
                Image(systemName: icon(tb)).ui(TypeScale.small, .semibold)
                if style == .iconsWithChosen && tab == tb { Text(label(tb, short: true)).ui(TypeScale.small, .semibold) }
            }
        }
    }

    private func icon(_ tb: PlanTab) -> String {
        switch tb {
        case .plan: return "list.bullet.rectangle"
        case .ticket: return "ticket"
        case .notes: return "note.text"
        case .artifacts: return "doc.on.doc"
        case .resources: return "gauge.with.dots.needle.33percent"
        }
    }

    private func label(_ tb: PlanTab, short: Bool = false) -> String {
        switch tb {
        case .plan: return "Plan"
        case .ticket: return "Ticket"
        case .notes: return "Notes"
        case .artifacts: return short ? "Files \(artifacts.count)" : "Artifacts \(artifacts.count)"
        case .resources: return short ? "Usage" : "Resources"
        }
    }

    // MARK: Plan tab

    @ViewBuilder private var planTab: some View {
        let it = live
        HStack(spacing: 6) {
            StatusDot(status: it.status)
            // The pill's text colour is made for the pill's own fill: draw the fill too, or it can vanish on the panel.
            let pill = t.pill(it.status)
            Text(StatusPalette.label(it.status)).ui(13, .semibold).foregroundStyle(pill.text.color)
                .padding(.horizontal, pill.fill == nil ? 0 : 8).padding(.vertical, pill.fill == nil ? 0 : 2)
                .background(Capsule().fill(pill.fill?.color ?? .clear))
            Spacer()
            actionButton(it)
            Button { showMore = true } label: { Text("•••").ui(13, .semibold).foregroundStyle(t.text2.color) }
                .buttonStyle(.plain).help("More: stickers, colour, emoji, copy, windows")
                .popover(isPresented: $showMore, arrowEdge: .leading) {
                    SessionPopover(item: it, model: model, close: { showMore = false }, rename: {
                        showMore = false
                        DispatchQueue.main.async { NSApp.sendAction(#selector(AppDelegate.renameSelected(_:)), to: nil, from: nil) }
                    }, attachIssue: {
                        showMore = false
                        DispatchQueue.main.async { NSApp.sendAction(#selector(AppDelegate.attachIssueToSelected(_:)), to: nil, from: nil) }
                    })
                    .themed(model.themes.plan)
                }
        }
        TextField("Session name", text: $name)
            .textFieldStyle(.plain).ui(TypeScale.title, .semibold).foregroundStyle(t.text.color)
            .onSubmit(commit)
        facts(it)
        if it.session.agent.isAgent, it.liveAgent != nil { StepReviewSection(model: model, item: it) }
        ForEach(it.session.allTickets, id: \.key) { i in TicketBox(item: it, issue: i, model: model) }
        field("Project") {
            HStack(spacing: 6) {
                TextField("CODE-…", text: $workstream).textFieldStyle(.plain).ui(12.5, mono: true)
                    .onSubmit(commit)
                // Pick from Linear (LAB-236) when it is connected; typing a code still works.
                if model.linear.hasKey {
                    Menu {
                        Button("No project") { workstream = ""; commit() }
                        ForEach(model.workstreams.filter { !["completed", "canceled"].contains($0.state) }) { w in
                            Button(NewSessionSheet.short("\(w.wsId ?? "") · \(w.title)")) { workstream = w.wsId ?? ""; commit() }
                        }
                    } label: { Text("Linear ▾").ui(11.5, .medium).foregroundStyle(t.text2.color) }
                        .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                        .onAppear { model.loadWorkstreams() }
                        .accessibilityLabel("Pick the project from Linear")
                }
            }
            .padding(8).background(RoundedRectangle(cornerRadius: Radius.field).fill(t.card.color))
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
            if let a = it.liveAgent {
                fact(model.runtime.kind.displayName, a + (it.paneId.flatMap { $0 == a ? nil : " · " + $0 } ?? ""), mono: true)
            }
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
                    Text("+ New").ui(11.5, .semibold).foregroundStyle(t.text2.color)
                        .padding(.vertical, 1).padding(.horizontal, 6)
                        .overlay(Capsule().strokeBorder(t.text2.color.opacity(0.6), lineWidth: 1))
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
            ForEach(it.session.allTickets, id: \.key) { i in TicketBox(item: it, issue: i, model: model, removable: true) }
        } else if mentioned.isEmpty {
            Text("No Linear issue yet.").ui(12.5).foregroundStyle(t.text2.color)
        }
        mentionedSection(it)
        // LAB-474: a session can resolve several issues; add one at any point before it ships.
        RoofButton(it.session.ticket == nil ? "Attach issue…" : "Add issue…") {
            NSApp.sendAction(#selector(AppDelegate.attachIssueToSelected(_:)), to: nil, from: nil)
        }.fixedSize()
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

    // MARK: Issues the session mentions (LAB-511)

    /// Issues the session worked on (named in its name, opening message, objective, notes or terminal) but has not
    /// attached: each with its Linear title and state and an Attach button.
    @ViewBuilder private func mentionedSection(_ it: BoardItem) -> some View {
        let open = mentioned.filter { !it.session.hasTicket($0.issue.identifier) }
        if !open.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text(it.session.ticket == nil ? "Not attached, but this session works on:" : "Also mentioned in this session:")
                    .ui(12, .semibold).foregroundStyle(t.text2.color)
                ForEach(open, id: \.issue.id) { m in
                    HStack(spacing: 8) {
                        Text(m.issue.identifier).ui(11.5, .semibold, mono: true).foregroundStyle(t.text.color)
                        Text(m.issue.shortTitle).ui(12).foregroundStyle(t.text.color).lineLimit(1).truncationMode(.tail).help(m.issue.shortTitle)
                        Spacer(minLength: 4)
                        Text(m.issue.state).ui(11).foregroundStyle(t.text3.color).fixedSize()
                        Button("Attach") {
                            model.attachIssue(m.issue, team: m.team.isEmpty ? nil : m.team, project: m.project, to: live, tellAgent: false)
                        }.controlSize(.small)
                    }
                    .padding(.horizontal, 10).padding(.vertical, 7)
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(t.card.color))
                }
            }
        }
        Color.clear.frame(height: 0).task(id: it.id) { await findMentions(it) }
    }

    /// Read the session's own text (and up to 3,000 terminal lines), then look each key up in Linear (at most 12).
    private func findMentions(_ it: BoardItem) async {
        guard model.linear.hasKey else { return }
        let s = it.session, runtime = model.runtime, linear = model.linear
        let teams = Set(model.linearTeams.map(\.key))
        let found: [(issue: LinearIssue, team: String, project: String?)] = await Task.detached {
            let terminal = it.liveAgent.flatMap { try? runtime.read(pane: $0, lines: 3000) }
            let keys = IssueMentions.keys(in: IssueMentions.texts(s, terminal: terminal), team: IssueMentions.team(of: s),
                                          teams: teams, excluding: s.allTickets.map(\.key))
            return keys.prefix(12).compactMap { k in (try? linear.issue(key: k)) ?? nil }
        }.value
        mentioned = found
    }

    // MARK: Notes tab

    @ViewBuilder private var notesTab: some View {
        field("Notes") { editor($notes, minHeight: 240) }
        HStack(spacing: 10) {
            RoofButton("Save", .primary) { commit(explicit: true) }.keyboardShortcut("s", modifiers: .command)
            // LAB-512: say whether it is saved (notes are kept with the session and come back when you return to it).
            if let base, local != base {
                Text("Unsaved changes").ui(12).foregroundStyle(t.text2.color)
            } else if let savedAt {
                Label("Saved \(savedAt.formatted(date: .omitted, time: .shortened))", systemImage: "checkmark.circle.fill")
                    .ui(12).foregroundStyle(t.diffAddText.color)
                    .accessibilityLabel("Saved")
            }
            Spacer()
        }
    }

    // MARK: Artifacts tab

    /// This session's own artifacts (LAB-513): files it wrote, its plan, handoffs naming its project or issues, and the
    /// screenshots given to it.
    private var artifacts: [SessionArtifacts.Item] { artifactItems }

    private func refreshArtifacts() async {
        let s = live.session
        let plan = model.objectives.first(where: { $0.stepSessions.values.contains(s.id) })?.planPath(common: model.settings.sharedFolder)
        let dir = model.settings.sharedFolder + "/docs/next-session-handoff"
        let items = await Task.detached(priority: .utility) { SessionArtifacts.list(s, plan: plan, handoffDir: dir) }.value
        if items != artifactItems { artifactItems = items }
    }

    @ViewBuilder private var artifactsTab: some View {
        let all = artifacts
        Text("What this session made or was given: files its agent wrote or edited, its plan, handoffs that name its project or issues, and screenshots in its opening message.")
            .ui(12).foregroundStyle(t.text2.color).fixedSize(horizontal: false, vertical: true)
        if all.isEmpty {
            Text("Nothing yet. Files show here as the agent edits them.").ui(12.5).foregroundStyle(t.text3.color)
        }
        ForEach([SessionArtifacts.Kind.written, .plan, .handoff, .screenshot], id: \.self) { kind in
            let group = all.filter { $0.kind == kind }
            if !group.isEmpty {
                Text("\(kind.rawValue) · \(group.count)").ui(11.5, .semibold).foregroundStyle(t.text3.color).padding(.top, 4)
                ForEach(group, id: \.path) { a in artifactRow(a.path) }
            }
        }
    }

    private func artifactRow(_ p: String) -> some View {
        Button { model.openInViewer(p) } label: {
            HStack(spacing: 8) {
                Image(nsImage: FileIcons.icon(for: p, size: 16)).resizable().frame(width: 16, height: 16)
                VStack(alignment: .leading, spacing: 1) {
                    Text((p as NSString).lastPathComponent).ui(12.5, .medium).foregroundStyle(t.text.color).lineLimit(1)
                    Text(((p as NSString).deletingLastPathComponent as NSString).abbreviatingWithTildeInPath).ui(11).foregroundStyle(t.text3.color).lineLimit(1)
                }
                Spacer()
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(t.card.color))
        }.buttonStyle(.plain).help(p)
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
        show(SessionEdits(live.session))
        base = SessionEdits(live.session)
        loaded = true
    }

    /// What the fields hold now.
    private var local: SessionEdits {
        SessionEdits(name: name, workstream: workstream, objective: objective, opening: opening, notes: notes,
                     args: args.split(separator: " ").map(String.init))
    }

    private func show(_ e: SessionEdits) {
        name = e.name; workstream = e.workstream; objective = e.objective
        opening = e.opening; notes = e.notes; args = e.args.joined(separator: " ")
    }

    private func rebase(onto s: Session) {
        guard loaded, let b = base else { return }
        let now = SessionEdits(s)
        guard now != b else { return }
        let mine = local
        let merged = mine.rebased(from: b, onto: now)
        if merged != mine { show(merged) }
        base = now
    }

    /// Save only the fields changed here since they were loaded (LAB-487: never write a stale copy over a rename).
    private func commit() { commit(explicit: false) }

    private func commit(explicit: Bool) {
        guard loaded, let b = base, let fresh = model.item(item.id) else { return }
        let edits = local
        // Save with nothing new still answers (LAB-512: Save used to give no sign at all).
        guard edits != b else { if explicit { savedAt = Date() }; return }
        model.update(fresh) { edits.apply(over: b, to: &$0) }
        let saved = SessionEdits(model.item(item.id)?.session ?? fresh.session)
        base = saved
        if saved != edits { show(saved) }
        savedAt = Date()
    }
}

/// One of the session's Linear issues (COMPONENTS TicketBox): key, state pill, Linear ↗, state buttons; ✕ takes it off
/// the session (LAB-474: a session can carry several).
struct TicketBox: View {
    @Environment(\.theme) private var t
    let item: BoardItem
    let issue: SessionIssue
    @ObservedObject var model: AppModel
    var removable = false
    @State private var state = ""
    @State private var url = ""
    @State private var busy = false

    var body: some View {
        let s = item.session
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(issue.key).ui(12.5, .semibold, mono: true).foregroundStyle(t.text.color)
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
                if removable {
                    Button { model.detachIssue(issue.key, from: item) } label: { Text("✕").ui(11, .semibold).foregroundStyle(t.text2.color) }
                        .buttonStyle(.plain).help("Take \(issue.key) off this session (it stays in Linear)")
                        .accessibilityLabel("Remove \(issue.key) from this session")
                }
            }
            // LAB-530: in a narrow panel the four buttons wrapped their words letter by letter ("Backl / og"). They
            // stay one line each; when the row does not fit, tighter buttons, then one "Move to" menu.
            ViewThatFits(in: .horizontal) {
                stateButtons(padding: 8)
                stateButtons(padding: 5)
                stateMenu
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(t.card.color))
        .onAppear(perform: load)
        .onReceive(model.$issues) { all in
            if let id = issue.id, let i = all.values.joined().first(where: { $0.id == id }) { state = i.state }
        }
    }

    private static let states = ["Backlog", "In Progress", "In Review", "Done"]

    private func move(_ st: String) {
        busy = true
        model.moveIssue(issue, to: st, comment: ["In Review", "Done"].contains(st) ? model.sessionSummary(item) : nil) { err in
            busy = false
            if err == nil { state = st }
        }
    }

    private func stateButtons(padding: CGFloat) -> some View {
        HStack(spacing: 4) {
            ForEach(Self.states, id: \.self) { st in
                let on = state == st
                Button { move(st) } label: {
                    Text(st).ui(11.5, .medium).foregroundStyle(on ? t.onAccent.color : t.text.color)
                        .lineLimit(1).fixedSize()
                        .padding(.vertical, 4).padding(.horizontal, padding)
                        .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(on ? t.accent.color : t.surface2.color))
                        .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(t.separator.color))
                }
                .buttonStyle(.plain).disabled(on || busy)
            }
        }
    }

    private var stateMenu: some View {
        Menu {
            ForEach(Self.states, id: \.self) { st in
                Button(st) { move(st) }.disabled(state == st || busy)
            }
        } label: {
            HStack(spacing: 4) {
                Text("Move to").ui(11.5, .medium).foregroundStyle(t.text.color).lineLimit(1)
                Text("▾").ui(9).foregroundStyle(t.text2.color)
            }
            .padding(.vertical, 4).padding(.horizontal, 8)
            .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(t.surface2.color))
            .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(t.separator.color))
        }
        .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
        .accessibilityLabel("Move \(issue.key) to another state")
    }

    private func load() {
        guard let id = issue.id else { return }
        DispatchQueue.global(qos: .userInitiated).async {
            if let r = try? model.linear.issueState(id) { DispatchQueue.main.async { state = r.name; url = r.url } }
        }
    }
}
