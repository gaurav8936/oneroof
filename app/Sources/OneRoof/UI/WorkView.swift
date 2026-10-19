import AppKit
import SwiftUI
import OneRoofCore

/// View › Work (⌘⇧W): every workstream, its roadmap (phases → tickets), and the sessions working on it, in one place.
/// Linear holds the tickets and their status; the master tracker holds the narrative; One Roof shows both and is where
/// new work starts (through the intake filter), so tab names, tracker and Linear stop drifting apart.
struct WorkView: View {
    @ObservedObject var model: AppModel
    @State private var selected: String?
    @State private var query = ""
    @State private var showShipped = false
    @State private var showIntake = false
    @State private var intakeWorkstream: String?
    @Environment(\.colorScheme) private var scheme

    var t: ThemeTokens { model.themes.centre.tokens }

    var list: [LinearWorkstream] {
        let q = query.lowercased()
        return model.workstreams.filter { w in
            (showShipped || !["completed", "canceled"].contains(w.state)) && (q.isEmpty || w.name.lowercased().contains(q))
        }
    }

    var current: LinearWorkstream? { model.workstreams.first { $0.id == (selected ?? SelfTest.workSelect) } }

    var body: some View {
        HStack(spacing: 0) {
            sidebar.frame(width: 300)
            Divider()
            if let w = current { WorkstreamDetail(model: model, w: w, newItem: { intakeWorkstream = w.id; showIntake = true }) }
            else { empty }
        }
        .background(t.background.color)
        .environment(\.colorScheme, model.themes.centre.colorScheme)
        .onAppear { model.loadWorkstreams() }
        .onReceive(NotificationCenter.default.publisher(for: .newWorkItem)) { _ in intakeWorkstream = selected; showIntake = true }
        .sheet(isPresented: $showIntake) {
            IntakeSheet(model: model, preselected: intakeWorkstream) { showIntake = false }
                .environment(\.colorScheme, model.themes.centre.colorScheme)
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Work").font(.system(size: 17, weight: .bold)).foregroundStyle(t.text.color)
                Spacer()
                Button { intakeWorkstream = selected; showIntake = true } label: { Label("New item", systemImage: "plus") }
                    .buttonStyle(.borderedProminent).controlSize(.small)
                    .help("New work item: One Roof asks what it is before creating anything (⌘⇧N)")
            }
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").font(.system(size: 11)).foregroundStyle(t.secondaryText.color)
                TextField("Filter workstreams", text: $query).textFieldStyle(.plain).font(.system(size: 12))
            }
            .padding(.horizontal, 8).padding(.vertical, 5)
            .background(RoundedRectangle(cornerRadius: 6).fill(t.surface.color))
            HStack {
                Toggle("Show shipped", isOn: $showShipped).toggleStyle(.checkbox).font(.system(size: 11))
                Spacer()
                Button { model.loadWorkstreams(force: true) } label: { Image(systemName: "arrow.clockwise") }
                    .buttonStyle(.borderless).help("Reload from Linear")
                Button { model.workMode = false } label: { Image(systemName: "terminal") }
                    .buttonStyle(.borderless).help("Back to terminals")
            }
            if model.linearLoading { ProgressView().controlSize(.small).frame(maxWidth: .infinity) }
            if let e = model.linearError { Text(e).font(.system(size: 11)).foregroundStyle(t.statusNeedsYou.color) }
            if !model.linear.hasKey {
                Button("Connect Linear…") { NotificationCenter.default.post(name: .openSetup, object: nil) }
                    .controlSize(.small).help("Optional: paste a Linear API key in Setup")
            }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(NSOrderedSet(array: list.map(\.team)).array as? [String] ?? [], id: \.self) { team in
                        let rows = list.filter { $0.team == team }
                        if !rows.isEmpty {
                            Text(teamName(team).uppercased()).font(.system(size: 10, weight: .heavy)).tracking(0.6)
                                .foregroundStyle(t.secondaryText.color).padding(.top, 8).padding(.leading, 4)
                            ForEach(rows) { w in row(w) }
                        }
                    }
                }
            }
        }
        .padding(12)
    }

    private func row(_ w: LinearWorkstream) -> some View {
        let live = model.sessions(in: w).filter { $0.status.isLive }.count
        let p = statePastel(w.state)
        return Button { selected = w.id; model.loadIssues(w) } label: {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(w.wsId ?? w.name).font(.system(size: 11, weight: .bold, design: .monospaced)).foregroundStyle(t.text.color)
                    Text(w.title).font(.system(size: 11.5)).foregroundStyle(t.secondaryText.color).lineLimit(1)
                }
                Spacer(minLength: 4)
                if live > 0 {
                    Text("\(live)").font(.system(size: 10, weight: .heavy, design: .rounded))
                        .foregroundStyle(Pastel.named("sky")!.inkColor(scheme))
                        .padding(.horizontal, 5).background(Capsule().fill(Pastel.named("sky")!.fillColor(scheme)))
                        .help("\(live) live sessions")
                }
                Text(w.stateLabel).font(.system(size: 9.5, weight: .bold, design: .rounded))
                    .foregroundStyle(p.inkColor(scheme)).padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Capsule().fill(p.fillColor(scheme)))
            }
            .padding(.horizontal, 8).padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 8).fill(selected == w.id ? t.selection.color : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var empty: some View {
        VStack(spacing: 10) {
            Image(systemName: "square.stack.3d.up").font(.system(size: 34)).foregroundStyle(t.secondaryText.color)
            Text("Pick a workstream to see its roadmap, tickets and sessions").font(.system(size: 13)).foregroundStyle(t.secondaryText.color)
            Text("New work starts with New item: One Roof asks whether it is a workstream, a ticket, a defect or just a session before creating anything.")
                .font(.system(size: 11.5)).foregroundStyle(t.secondaryText.color).multilineTextAlignment(.center).frame(maxWidth: 420)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func teamName(_ k: String) -> String { k }
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
                header
                sessionsBlock
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
                    .foregroundStyle(statePastel(w.state).inkColor(scheme)).padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Capsule().fill(statePastel(w.state).fillColor(scheme)))
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

    private var sessionsBlock: some View {
        let s = model.sessions(in: w)
        return VStack(alignment: .leading, spacing: 6) {
            Text("SESSIONS (\(s.count))").font(.system(size: 10, weight: .heavy)).tracking(0.6).foregroundStyle(t.secondaryText.color)
            if s.isEmpty {
                Text("No sessions yet. Plan one from a ticket below.").font(.system(size: 11.5)).foregroundStyle(t.secondaryText.color)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 260), spacing: 6)], spacing: 6) {
                    ForEach(s) { i in SessionRow(row: model.rowData(i), density: .compact).onTapGesture { model.reveal(i) } }
                }
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
        let p = statePastel(i.state), linked = model.sessions(for: i)
        return HStack(spacing: 8) {
            Text(i.identifier).font(.system(size: 10.5, weight: .bold, design: .monospaced)).foregroundStyle(t.secondaryText.color)
                .frame(width: 64, alignment: .leading)
            if let type = i.type, let st = typeSticker(type) { StickerView(sticker: st, size: 9.5) }
            Text(i.shortTitle).font(.system(size: 12)).foregroundStyle(t.text.color).lineLimit(1)
            Spacer(minLength: 6)
            if !linked.isEmpty {
                Button { model.selectedId = linked[0].id; model.workMode = false } label: {
                    Label("\(linked.count)", systemImage: "terminal").font(.system(size: 10, weight: .bold))
                }.buttonStyle(.borderless).help("Open its session")
            }
            Menu {
                ForEach(["Backlog", "Todo", "In Progress", "In Review", "Done", "Canceled"], id: \.self) { st in
                    Button(st) { model.moveTicket(id: i.id, team: w.team, to: st) }
                }
            } label: {
                Text(i.state).font(.system(size: 9.5, weight: .bold, design: .rounded))
                    .foregroundStyle(p.inkColor(scheme)).padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Capsule().fill(p.fillColor(scheme)))
            }
            .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
            .help("Change the ticket's state in Linear")
            if i.stateType != "completed" && i.stateType != "canceled" {
                Button { model.planSession(for: i, in: w); model.workMode = false } label: { Image(systemName: "play.circle") }
                    .buttonStyle(.borderless).help("Plan a session for \(i.identifier)")
            }
            Link(destination: URL(string: i.url) ?? URL(string: "https://linear.app")!) { Image(systemName: "arrow.up.right.square") }
                .help("Open in Linear")
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
                Picker("Workstream", selection: $workstream) {
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
        case .workstream: return "Plan the workstream"
        case .session: return "Plan the session"
        default: return "Create ticket"
        }
    }

    private var summary: String {
        switch kind {
        case .workstream:
            return "One Roof plans a Claude session that opens the workstream the workspace way: WS id, tracker pane, docs README, Linear project and phases. Nothing is created until that session runs."
        case .session:
            return "A planned session only. No ticket, nothing in Linear or the tracker."
        default:
            return "Creates a \(kind.rawValue) ticket in \(ws?.wsId ?? "the chosen workstream")\(milestone.isEmpty ? "" : ", in that phase") on Linear" + (planIt ? ", and a planned session linked to it (launching it moves the ticket to In Progress)." : ".")
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
