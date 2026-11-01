import AppKit
import SwiftUI
import OneRoofCore

/// Projects (⌘⇧W): every Linear project grouped by team, filtered by status, and the open project's roadmap
/// (phases → tickets). Linear holds the tickets and their status; the master tracker holds the narrative; One Roof shows
/// both and is where new work starts (through the intake filter), so tab names, tracker and Linear stop drifting apart.
/// LAB-2050: teams fold (with counts), status chips as in All sessions (default In progress + In review), title first.
/// LAB-2051: a project page shows the project only (no Sessions block); ▷ on an issue still plans a session.
struct WorkView: View {
    @ObservedObject var model: AppModel
    @State private var selected: String?
    @AppStorage("projects.query", store: Prefs.viewState) private var query = ""
    /// The chosen status chips (ProjectStatus raw values); never saved = the default, "" = no chip (every status).
    @AppStorage("projects.statuses", store: Prefs.viewState) private var statusesRaw = ProjectStatus.encode(ProjectStatus.defaultSet)
    @AppStorage("projects.foldedTeams", store: Prefs.viewState) private var foldedRaw = ""
    @State private var showIntake = false
    @State private var intakeWorkstream: String?
    @FocusState private var filterFocused: Bool
    @FocusState private var listFocused: Bool
    @Environment(\.colorScheme) private var scheme

    var t: ThemeTokens { model.themes.centre.tokens }
    var statuses: Set<ProjectStatus> { ProjectStatus.decode(statusesRaw) }
    var folded: Set<String> { ProjectList.decodeTeams(foldedRaw) }
    var result: ProjectList.Result {
        ProjectList.groups(projects: model.workstreams, teams: model.linearTeams, statuses: statuses, query: query, folded: folded)
    }

    var current: LinearWorkstream? { model.workstreams.first { $0.id == (selected ?? SelfTest.workSelect) } }

    var body: some View {
        GeometryReader { geo in
            HStack(spacing: 0) {
                // 340 pt at a 1280 window, 360 at 1440 and wider (the centre is the window less the rail).
                sidebar.frame(width: geo.size.width >= 1300 ? 360 : 340)
                Divider()
                if let w = current { WorkstreamDetail(model: model, w: w, newItem: { intakeWorkstream = w.id; showIntake = true }) }
                else { empty }
            }
        }
        .background(t.background.color)
        .environment(\.colorScheme, model.themes.centre.colorScheme)
        .onAppear { model.loadWorkstreams() }
        .onReceive(NotificationCenter.default.publisher(for: .newWorkItem)) { _ in intakeWorkstream = selected; showIntake = true }
        .onReceive(NotificationCenter.default.publisher(for: .projectsFind)) { _ in filterFocused = true }
        .sheet(isPresented: $showIntake) {
            IntakeSheet(model: model, preselected: intakeWorkstream) { showIntake = false }
                .environment(\.colorScheme, model.themes.centre.colorScheme)
        }
    }

    private var sidebar: some View {
        let r = result
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Projects").font(.system(size: 17, weight: .bold)).foregroundStyle(t.text.color)   // LAB-2049
                Spacer()
                Button { intakeWorkstream = selected; showIntake = true } label: { Label("New item", systemImage: "plus") }
                    .buttonStyle(.borderedProminent).controlSize(.small)
                    .help("New work item: One Roof asks what it is before creating anything (⌘⇧N)")
            }
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").font(.system(size: 11)).foregroundStyle(t.secondaryText.color)
                TextField("Filter by name or code", text: $query).textFieldStyle(.plain).font(.system(size: 12))
                    .focused($filterFocused)
                    .accessibilityLabel("Filter projects by name or code")
                if !query.isEmpty {
                    Button { query = "" } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.borderless).foregroundStyle(t.secondaryText.color)
                        .help("Clear the filter").accessibilityLabel("Clear the filter")
                }
            }
            .padding(.horizontal, 8).padding(.vertical, 5)
            .background(RoundedRectangle(cornerRadius: Radius.field).fill(t.surface.color))
            .overlay(RoundedRectangle(cornerRadius: Radius.field)
                .stroke(filterFocused ? t.accent.color : t.border.color, lineWidth: filterFocused ? 2 : 1))
            chips(r)
            HStack(spacing: 10) {
                if !ProjectList.isDefault(statuses: statuses, query: query) {
                    RoofButton("Reset", .plain) { reset() }
                        .help("Back to In progress + In review, no filter text")
                }
                Spacer()
                Button { model.loadWorkstreams(force: true) } label: { Image(systemName: "arrow.clockwise") }
                    .buttonStyle(.borderless).help("Reload from Linear").accessibilityLabel("Reload from Linear")
                Button { model.workMode = false } label: { Image(systemName: "terminal") }
                    .buttonStyle(.borderless).help("Back to terminals").accessibilityLabel("Back to terminals")
            }
            if model.linearLoading {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text("Loading projects from Linear…").font(.system(size: 11.5)).foregroundStyle(t.secondaryText.color)
                }
                .frame(maxWidth: .infinity)
            }
            if let e = model.linearError {
                VStack(alignment: .leading, spacing: 6) {
                    Text(e).font(.system(size: 11)).foregroundStyle(t.needsText.color).fixedSize(horizontal: false, vertical: true)
                    RoofButton("Try again", .secondary) { model.loadWorkstreams(force: true) }
                }
            }
            if !model.linear.hasKey {
                Button("Connect Linear…") { NotificationCenter.default.post(name: .openSetup, object: nil) }
                    .controlSize(.small).help("Optional: paste a Linear API key in Setup")
            }
            list(r)
        }
        .padding(12)
    }

    /// LAB-2050: one chip per status, All sessions style (RoofButton primary when on); several can be on; each shows its
    /// count after the text filter. The row wraps when narrow.
    private func chips(_ r: ProjectList.Result) -> some View {
        FlowLayout(spacing: 6) {
            ForEach(ProjectStatus.allCases, id: \.self) { s in
                let on = statuses.contains(s), n = r.counts[s] ?? 0
                RoofButton("\(s.label) \(n)", on ? .primary : .secondary) { toggle(s) }
                    .help(on ? "Hide \(s.label) projects" : "Show \(s.label) projects")
                    .accessibilityLabel(ProjectList.chipLabel(s, count: n, on: on))
                    .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
    }

    private func list(_ r: ProjectList.Result) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(r.groups) { g in
                        teamHeader(g, shown: r.groups.map(\.key))
                        if !g.folded { ForEach(g.projects) { w in row(w).id(w.id) } }
                    }
                    if r.isEmpty && !model.workstreams.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("No projects match. Choose more statuses or clear the filter.")
                                .font(.system(size: 12)).foregroundStyle(t.secondaryText.color).fixedSize(horizontal: false, vertical: true)
                            RoofButton("Reset", .secondary) { reset() }
                        }
                        .padding(.top, 12).padding(.horizontal, 4)
                    }
                    if let line = ProjectList.hiddenLine(r.isEmpty ? 0 : r.hiddenTeams) {
                        Text(line).font(.system(size: 11)).foregroundStyle(t.text3.color).padding(.top, 10).padding(.leading, 4)
                    }
                }
            }
            .focusable()
            .focused($listFocused)
            .focusEffectDisabled()
            .onKeyPress(.upArrow) { move(-1, r, proxy) }
            .onKeyPress(.downArrow) { move(1, r, proxy) }
            .onKeyPress(.leftArrow) { fold(true, r) }
            .onKeyPress(.rightArrow) { fold(false, r) }
            .onKeyPress(.return) {
                guard let w = current else { return .ignored }
                model.loadIssues(w, force: true); return .handled
            }
        }
    }

    private func teamHeader(_ g: ProjectGroup, shown: [String]) -> some View {
        Button {
            let all = NSEvent.modifierFlags.contains(.option)   // ⌥-click folds or unfolds every team
            foldedRaw = ProjectList.encodeTeams(ProjectList.toggleFold(g.key, folded: folded, all: all, shown: shown))
        } label: {
            HStack(spacing: 6) {
                Text(g.folded ? "▸" : "▾").font(.system(size: 14, weight: .bold)).foregroundStyle(t.secondaryText.color).frame(width: 14)
                (Text(g.key).font(.system(size: 11.5, weight: .heavy, design: .monospaced))
                    + Text(g.name != g.key ? " · \(g.name)" : "").font(.system(size: 12, weight: .semibold)))
                    .foregroundStyle(t.text.color).lineLimit(1)
                Spacer(minLength: 6)
                Text("\(g.projects.count)").font(.system(size: 11, weight: .semibold, design: .rounded)).foregroundStyle(t.secondaryText.color)
            }
            .padding(.horizontal, 6).padding(.vertical, 5)
            .contentShape(Rectangle())
            .hoverHighlight(radius: Radius.row)
        }
        .buttonStyle(PressStyle(radius: Radius.row))
        .padding(.top, 6)
        .help(g.folded ? "Unfold \(g.key) (⌥-click: every team)" : "Fold \(g.key) (⌥-click: every team)")
        .accessibilityLabel(g.accessibilityLabel)
        .accessibilityHint(g.folded ? "Unfolds the team" : "Folds the team")
    }

    private func row(_ w: LinearWorkstream) -> some View {
        let live = model.sessions(in: w).filter { $0.status.isLive }.count
        let p = Pastel.named(w.status.pastel)!
        let isSel = (selected ?? SelfTest.workSelect) == w.id
        return Button { open(w) } label: {
            VStack(alignment: .leading, spacing: 4) {
                // Title first, up to two lines, wrapping at word boundaries (LAB-2050).
                Text(w.title).font(.system(size: 13, weight: .semibold)).foregroundStyle(t.text.color)
                    .lineLimit(2).fixedSize(horizontal: false, vertical: true).multilineTextAlignment(.leading)
                HStack(spacing: 6) {
                    if let code = w.wsId {
                        Text(code).font(.system(size: 11, design: .monospaced)).foregroundStyle(t.secondaryText.color)
                            .lineLimit(1).truncationMode(.middle)
                    }
                    Text(w.stateLabel).font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundStyle(p.inkColor(scheme)).padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Capsule().fill(p.fillColor(scheme)))
                        .fixedSize()
                    if live > 0 {
                        Text("\(live)").font(.system(size: 10, weight: .heavy, design: .rounded))
                            .foregroundStyle(Pastel.named("sky")!.inkColor(scheme))
                            .padding(.horizontal, 5).background(Capsule().fill(Pastel.named("sky")!.fillColor(scheme)))
                            .help("\(live) live sessions")
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 8).padding(.vertical, 6)
            .padding(.leading, 10)
            .contentShape(Rectangle())
            .hoverHighlight(radius: Radius.row, selected: isSel)
        }
        .buttonStyle(PressStyle(radius: Radius.row))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(ProjectList.rowLabel(w, live: live))
        .accessibilityAddTraits(isSel ? [.isButton, .isSelected] : .isButton)
    }

    private var empty: some View {
        VStack(spacing: 10) {
            Image(systemName: "square.stack.3d.up").font(.system(size: 34)).foregroundStyle(t.secondaryText.color)
            Text("Pick a project to see its roadmap and tickets").font(.system(size: 13)).foregroundStyle(t.secondaryText.color)
            Text("New work starts with New item: One Roof asks whether it is a project, a ticket, a defect or just a session before creating anything.")
                .font(.system(size: 11.5)).foregroundStyle(t.secondaryText.color).multilineTextAlignment(.center).frame(maxWidth: 420)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Actions

    private func open(_ w: LinearWorkstream) { selected = w.id; SelfTest.workSelect = nil; model.loadIssues(w) }

    private func toggle(_ s: ProjectStatus) {
        var set = statuses
        if set.contains(s) { set.remove(s) } else { set.insert(s) }
        statusesRaw = ProjectStatus.encode(set)
    }

    private func reset() {
        let r = ProjectList.reset()
        statusesRaw = ProjectStatus.encode(r.statuses); query = r.query
    }

    private func move(_ delta: Int, _ r: ProjectList.Result, _ proxy: ScrollViewProxy) -> KeyPress.Result {
        guard let id = ProjectList.step(from: selected ?? SelfTest.workSelect, by: delta, in: r.visibleRows),
              let w = model.workstreams.first(where: { $0.id == id }) else { return .ignored }
        open(w); proxy.scrollTo(id)
        return .handled
    }

    /// ← folds the selected project's team, → unfolds it.
    private func fold(_ on: Bool, _ r: ProjectList.Result) -> KeyPress.Result {
        guard let team = current?.team else { return .ignored }
        var f = folded
        if on { f.insert(team) } else { f.remove(team) }
        foldedRaw = ProjectList.encodeTeams(f)
        return .handled
    }
}

func statePastel(_ state: String) -> Pastel {
    switch state {
    case "started", "In Progress": return Pastel.named("sky")!
    case "completed", "Done": return Pastel.named("mint")!
    case "In Review": return Pastel.named("lavender")!
    case "planned", "Todo", "unstarted": return Pastel.named("peach")!
    case "canceled", "Canceled", "Duplicate": return Pastel.named("stone")!
    default: return Pastel.named("butter")!
    }
}

struct WorkstreamDetail: View {
    /// LAB-1338: captions, feed, chapters and subagents redraw this view (they left AppModel).
    @ObservedObject var engineState = EngineState.shared
    @ObservedObject var model: AppModel
    let w: LinearWorkstream
    let newItem: () -> Void
    @State private var showDone = false
    @Environment(\.colorScheme) private var scheme

    var t: ThemeTokens { model.themes.centre.tokens }
    var tickets: [LinearIssue] { (model.issues[w.id] ?? []).filter { $0.type != "commit" } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header      // LAB-2051: the project only (no Sessions block); the roadmap sits 14 pt under the header
                roadmap
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var header: some View {
        let all = tickets, done = all.filter { $0.stateType == "completed" }.count
        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(w.wsId ?? "").font(.system(size: 13, weight: .heavy, design: .monospaced)).foregroundStyle(t.accent.color)
                Text(w.stateLabel).font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(Pastel.named(w.status.pastel)!.inkColor(scheme)).padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Capsule().fill(Pastel.named(w.status.pastel)!.fillColor(scheme)))
                Spacer()
                Button(action: newItem) { Label("New item here", systemImage: "plus") }.controlSize(.small)
            }
            Text(w.title).font(.system(size: 20, weight: .bold)).foregroundStyle(t.text.color)
            HStack(spacing: 14) {
                if !all.isEmpty {
                    ProgressView(value: Double(done), total: Double(max(all.count, 1))).frame(width: 160)
                    Text("\(done) of \(all.count) tickets done").font(.system(size: 11)).foregroundStyle(t.secondaryText.color)
                }
                Link(destination: URL(string: w.url) ?? URL(string: "https://linear.app")!) { Label("Linear", systemImage: "arrow.up.right.square") }
                    .font(.system(size: 11))
                if let id = w.wsId, let pane = Trackers.pane(for: id) {
                    Button { NSWorkspace.shared.open(pane) } label: { Label("Tracker pane", systemImage: "list.bullet.rectangle") }
                        .buttonStyle(.link).font(.system(size: 11))
                }
                if let id = w.wsId, let docs = Trackers.docsFolder(for: id) {
                    Button { model.openInViewer(docs) } label: { Label("Docs", systemImage: "doc.text") }
                        .buttonStyle(.link).font(.system(size: 11))
                }
                Button { model.loadIssues(w, force: true) } label: { Image(systemName: "arrow.clockwise") }.buttonStyle(.borderless)
            }
        }
    }

    private var roadmap: some View {
        let groups = phases()
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("ROADMAP").font(.system(size: 10, weight: .heavy)).tracking(0.6).foregroundStyle(t.secondaryText.color)
                Spacer()
                Toggle("Show done", isOn: $showDone).toggleStyle(.checkbox).font(.system(size: 11))
            }
            if model.issues[w.id] == nil { ProgressView().controlSize(.small) }
            else if groups.isEmpty {
                Text("No tickets in this project yet.").font(.system(size: 11.5)).foregroundStyle(t.secondaryText.color)
            }
            ForEach(groups, id: \.0) { name, list in
                let open = list.filter { $0.stateType != "completed" && $0.stateType != "canceled" }
                let shown = showDone ? list : open
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(name).font(.system(size: 13, weight: .bold)).foregroundStyle(t.text.color)
                        Text("\(list.count - open.count)/\(list.count) done").font(.system(size: 10.5)).foregroundStyle(t.secondaryText.color)
                    }
                    if shown.isEmpty {
                        Text(list.isEmpty ? "No tickets" : "All done").font(.system(size: 11)).foregroundStyle(t.secondaryText.color)
                    }
                    ForEach(shown) { ticketRow($0) }
                }
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(t.surface.color.opacity(0.7)))
            }
        }
    }

    /// Tickets grouped by phase (milestone), in the workstream's phase order; tickets without one last.
    private func phases() -> [(String, [LinearIssue])] {
        var out: [(String, [LinearIssue])] = w.milestones.map { m in (m.name, tickets.filter { $0.milestoneId == m.id }) }
        let loose = tickets.filter { $0.milestoneId == nil }
        if !loose.isEmpty { out.append(("Not in a phase", loose)) }
        return out
    }

    private func ticketRow(_ i: LinearIssue) -> some View {
        let p = statePastel(i.state)
        return HStack(spacing: 8) {
            Text(i.identifier).font(.system(size: 10.5, weight: .bold, design: .monospaced)).foregroundStyle(t.secondaryText.color)
                .frame(width: 64, alignment: .leading)
            if let type = i.type, let st = typeSticker(type) { StickerView(sticker: st, size: 9.5) }
            Text(i.shortTitle).font(.system(size: 12)).foregroundStyle(t.text.color).lineLimit(1)
            Spacer(minLength: 6)
            Menu {
                ForEach(["Backlog", "Todo", "In Progress", "In Review", "Done", "Canceled"], id: \.self) { st in
                    Button(st) { model.moveTicket(id: i.id, team: w.team, to: st) }
                }
            } label: {
                Text(i.state).font(.system(size: 9.5, weight: .bold, design: .rounded))
                    .foregroundStyle(p.inkColor(scheme)).padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Capsule().fill(p.fillColor(scheme)))
            }
            // A button-style menu draws the pill as made; the borderless style dropped its fill, and in Midnight and
            // Graphite its dark ink then vanished on the dark page (seen in the M5 before captures).
            .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
            .help("Change the ticket's state in Linear")
            .accessibilityLabel("\(i.identifier) state: \(i.state). Change it in Linear")
            if i.stateType != "completed" && i.stateType != "canceled" {
                Button { model.planSession(for: i, in: w); model.workMode = false } label: { Image(systemName: "play.circle") }
                    .buttonStyle(.borderless).help("Plan a session for \(i.identifier)")
                    .accessibilityLabel("Plan a session for \(i.identifier)")
            }
            Link(destination: URL(string: i.url) ?? URL(string: "https://linear.app")!) { Image(systemName: "arrow.up.right.square") }
                .help("Open in Linear").accessibilityLabel("Open \(i.identifier) in Linear")
        }
        .padding(.vertical, 2)
    }

    private func typeSticker(_ type: String) -> Sticker? {
        let map = ["defect": ("Defect", "ladybug.fill", "rose"), "spike": ("Spike", "magnifyingglass", "periwinkle"),
                   "decision": ("Decision", "arrow.triangle.branch", "lavender"), "chore": ("Chore", "wrench.fill", "stone"),
                   "deliverable": ("Deliverable", "shippingbox.fill", "aqua")]
        guard let m = map[type] else { return nil }
        return Sticker(id: type, label: m.0, symbol: m.1, pastel: Pastel.named(m.2)!, builtIn: true)
    }
}

/// New work item: decide what it is before anything is created (owner, 2026-10-17: "some filter before it actually
/// creates it in Linear … otherwise we end up with a huge problem reconciling it").
struct IntakeSheet: View {
    @ObservedObject var model: AppModel
    var preselected: String?
    let close: () -> Void

    @State private var title = ""
    @State private var details = ""
    @State private var kind: WorkKind = .deliverable
    @State private var kindTouched = false
    @State private var severalSessions = false
    @State private var workstream = ""
    @State private var milestone = ""
    @State private var planIt = true
    @State private var busy = false
    @State private var result: String?

    var ws: LinearWorkstream? { model.workstreams.first { $0.id == workstream } }
    var dupes: [LinearIssue] { kind.isTicket ? Intake.similar(title, in: ws.flatMap { model.issues[$0.id] } ?? []) : [] }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("New work item").font(.system(size: 16, weight: .bold))
            Text("Say what you want done. One Roof works out what it is, checks for duplicates, and only then creates it.")
                .font(.system(size: 11.5)).foregroundStyle(.secondary)
            TextField("What is it? e.g. Login fails on Safari", text: $title).textFieldStyle(.roundedBorder)
            TextField("Details (optional)", text: $details, axis: .vertical).lineLimit(2...5).textFieldStyle(.roundedBorder)

            GroupBox {
                VStack(alignment: .leading, spacing: 8) {
                    Toggle("It needs several sessions and more than one deliverable", isOn: $severalSessions)
                    Picker("It is a", selection: Binding(get: { kind }, set: { kind = $0; kindTouched = true })) {
                        ForEach(WorkKind.allCases) { Text($0.label).tag($0) }
                    }
                    Text(kind.meaning).font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                .padding(4)
            } label: { Label("What is it?", systemImage: "questionmark.circle") }

            if kind.isTicket {
                Picker("Project", selection: $workstream) {
                    Text("Choose…").tag("")
                    ForEach(Intake.rankWorkstreams(title + " " + details, model.workstreams.filter { !["completed", "canceled"].contains($0.state) })) {
                        Text($0.name).tag($0.id)
                    }
                }
                if let ws, !ws.milestones.isEmpty {
                    Picker("Phase", selection: $milestone) {
                        Text("None").tag("")
                        ForEach(ws.milestones) { Text($0.name).tag($0.id) }
                    }
                }
                if !dupes.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Label("Looks like an existing ticket. Use it instead?", systemImage: "exclamationmark.triangle.fill")
                            .font(.system(size: 11.5, weight: .semibold)).foregroundStyle(Pastel.named("peach")!.lightInk.color)
                        ForEach(dupes) { d in
                            HStack {
                                Text("\(d.identifier) · \(d.shortTitle) · \(d.state)").font(.system(size: 11)).lineLimit(1)
                                Spacer()
                                if let ws {
                                    Button("Plan a session for it") { model.planSession(for: d, in: ws); model.workMode = false; close() }
                                        .controlSize(.small)
                                }
                            }
                        }
                    }
                    .padding(8).background(RoundedRectangle(cornerRadius: 8).fill(Pastel.named("peach")!.lightFill.color.opacity(0.6)))
                }
                Toggle("Plan a session for it now", isOn: $planIt)
            }

            Text(summary).font(.system(size: 11.5, weight: .medium)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if let result { Text(result).font(.system(size: 11.5)).foregroundStyle(.red) }

            HStack {
                Button("Cancel", role: .cancel, action: close).keyboardShortcut(.cancelAction)
                Spacer()
                if busy { ProgressView().controlSize(.small) }
                Button(primaryTitle, action: create).keyboardShortcut(.defaultAction).disabled(!canCreate || busy)
            }
        }
        .padding(18)
        .frame(width: 560)
        .onAppear {
            model.loadWorkstreams()
            if let p = preselected { workstream = p; if let w = ws { model.loadIssues(w) } }
        }
        .onChange(of: title) { _, v in if !kindTouched { kind = severalSessions ? .workstream : Intake.suggest(v + " " + details) } }
        .onChange(of: severalSessions) { _, v in kind = v ? .workstream : Intake.suggest(title + " " + details); kindTouched = false }
        .onChange(of: workstream) { _, _ in milestone = ""; if let w = ws { model.loadIssues(w) } }
    }

    private var canCreate: Bool {
        !title.trimmingCharacters(in: .whitespaces).isEmpty && (!kind.isTicket || ws != nil)
    }

    private var primaryTitle: String {
        switch kind {
        case .workstream: return "Plan the project"
        case .session: return "Plan the session"
        default: return "Create ticket"
        }
    }

    private var summary: String {
        switch kind {
        case .workstream:
            return "One Roof plans a Claude session that opens the project the workspace way: project code, docs README, Linear project and milestones. Nothing is created until that session runs."
        case .session:
            return "A planned session only. No ticket, nothing in Linear or the tracker."
        default:
            return "Creates a \(kind.rawValue) ticket in \(ws?.wsId ?? "the chosen project")\(milestone.isEmpty ? "" : ", in that phase") on Linear" + (planIt ? ", and a planned session linked to it (launching it moves the ticket to In Progress)." : ".")
        }
    }

    private func create() {
        let t = title.trimmingCharacters(in: .whitespaces)
        switch kind {
        case .workstream:
            model.planWorkstreamSession(title: t, details: details); model.workMode = false; close()
        case .session:
            let s = Session(name: t, agent: .claude, account: model.settings.defaults(for: .claude).account, repoPath: Workspace.projectsRoot,
                            objective: details, lifecycle: .next)
            model.createPlanned(s, launchNow: false); model.selectedId = s.id; model.workMode = false; close()
        default:
            guard let ws else { return }
            busy = true
            model.createTicket(kind: kind, title: t, details: details, in: ws, milestone: milestone.isEmpty ? nil : milestone, planSession: planIt) { r in
                busy = false
                switch r {
                case .success: if planIt { model.workMode = false }; close()
                case .failure(let e): result = "\(e)"
                }
            }
        }
    }
}
