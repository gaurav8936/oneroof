import SwiftUI
import OneRoofCore

/// New work (⌘N): what it is (intake), what should happen, duplicate check, agent and account with the router's
/// suggestion, model · repo · start folder, done when + opening message, Advanced (args, resume, role), and when.
/// The launch path: a roofd session in the start folder with the account's environment, the agent started through the login shell →
/// opening message once the agent is ready and idle.
struct NewSessionSheet: View {
    @Environment(\.theme) private var t
    @ObservedObject var model: AppModel
    @ObservedObject var win: WindowState
    var close: () -> Void

    enum Kind: String, CaseIterable { case session, ticket, defect, workstream }
    enum When: String, CaseIterable { case now, next, tonight, onDemand }

    @State private var kind: Kind = .session
    @State private var ticketType: WorkKind = .deliverable
    @State private var kindTouched = false
    @State private var text = ""
    @State private var wsId = ""
    @State private var useTicket: LinearIssue?
    @State private var mark: AgentMark = .claude1
    @State private var modelName = ""
    @State private var repo = Workspace.projectsRoot
    @State private var startInRepo = false
    @State private var doneWhen = ""
    @State private var opening = ""
    @State private var openingTouched = false
    @State private var advanced = false
    @State private var args = ""
    @State private var resumeId = ""
    @State private var roleId = ""
    @State private var roles: [Role] = []
    @State private var conversations: [Conversation] = []
    @State private var when: When = .now
    @State private var nightly = false
    @State private var suggestion: RouteSuggestion?
    @State private var suggestedMark: AgentMark?
    @State private var busy = false
    @State private var error: String?
    @State private var debounce: DispatchWorkItem?
    @FocusState private var textFocused: Bool

    private let repos = [Workspace.projectsRoot] + Workspace.listRepos()
    private let marks: [AgentMark] = AgentMark.available([.claude1, .claude2, .codex, .kimi, .gemini, .antigravity, .shell])
    @State private var wsText = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            section {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text("New work").ui(20, .semibold).foregroundStyle(t.text.color)
                    Text("in \(win.name)").ui(13).foregroundStyle(t.text3.color)
                    Spacer()
                }
                HStack(spacing: 10) {
                    kindPicker
                    Spacer()
                    if kind == .ticket || kind == .defect { workstreamPicker }
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text("What should happen").ui(12, .semibold).foregroundStyle(t.text.color)
                    TextField("", text: $text, prompt: Text("e.g. Help search returns results as you type"))
                        .textFieldStyle(.plain).ui(15).focused($textFocused)
                        .padding(.horizontal, 12).frame(height: 40)
                        .background(RoundedRectangle(cornerRadius: Radius.field, style: .continuous).fill(t.surface.color))
                        .overlay(RoundedRectangle(cornerRadius: Radius.field, style: .continuous)
                            .strokeBorder(textFocused ? t.accent.color : t.separatorStrong.color, lineWidth: textFocused ? 2 : 1))
                        .onChange(of: text) { _, v in textChanged(v) }
                }
                if let d = duplicate { duplicateBanner(d) }
            }
            Hairline()
            section {
                HStack {
                    Text("Agent and account").ui(12, .semibold).foregroundStyle(t.text.color)
                    Spacer()
                    if let s = suggestion, let m = suggestedMark {
                        (Text("Suggested: ").foregroundColor(t.text2.color) + Text(name(m)).fontWeight(.semibold).foregroundColor(t.text.color)
                         + Text(", " + s.reason).foregroundColor(t.text2.color))
                            .ui(12).lineLimit(1)
                        if mark != m {
                            Button { select(m); if let md = s.model { modelName = md } } label: {
                                Text("Use it").ui(12, .semibold).foregroundStyle(t.accentText.color)
                            }.buttonStyle(.plain)
                        }
                    }
                }
                HStack(spacing: 10) { ForEach(marks, id: \.self) { agentCard($0) } }
                HStack(alignment: .top, spacing: 10) {
                    if mark != .shell { labelled("Model") { modelMenu } }
                    labelled("Repo") { repoMenu }
                    labelled("Start in") { startIn }
                    if kind == .session {
                        labelled("Workstream") {
                            TextField("WS-…", text: $wsText).textFieldStyle(.plain).ui(13, mono: true)
                                .padding(.horizontal, 10).frame(height: 30)
                                .background(RoundedRectangle(cornerRadius: Radius.field, style: .continuous).fill(t.card.color))
                        }
                    }
                }
            }
            Hairline()
            section {
                HStack(alignment: .top, spacing: 14) {
                    labelled("Done when") { box($doneWhen, minHeight: 64) }
                    if mark != .shell { labelled("Opening message · sent when the agent is ready") { box($opening, minHeight: 64, onEdit: { openingTouched = true }) } }
                }
                DisclosureGroup(isExpanded: $advanced) { advancedFields } label: {
                    Text("Advanced").ui(12, .semibold).foregroundStyle(t.text2.color)
                }
            }
            Hairline()
            HStack(spacing: 10) {
                Text("When").ui(12, .semibold).foregroundStyle(t.text.color)
                whenPicker
                if let error { Text(error).ui(12).foregroundStyle(t.needsText.color).lineLimit(2) }
                else if let why = blockedReason { Text(why).ui(12).foregroundStyle(t.needsText.color).lineLimit(2) }
                Spacer()
                if busy { ProgressView().controlSize(.small) }
                RoofButton("Cancel") { close() }.keyboardShortcut(.cancelAction)
                RoofButton("Save as planned") { go(launch: false, forcePlanned: true) }.disabled(!valid)
                RoofButton(primaryLabel, .primary) { go(launch: when == .now) }
                    .keyboardShortcut(.return, modifiers: .command)
                    .disabled(!valid || busy)
            }
            .padding(.horizontal, 26).padding(.vertical, 16)
        }
        .frame(width: 820)
        .background(t.window.color)
        .onAppear(perform: appear)
        .onChange(of: model.workstreams) { _, _ in defaultWorkstream() }
    }

    // MARK: Sections

    private func section<C: View>(@ViewBuilder _ c: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 12) { c() }.padding(.horizontal, 26).padding(.vertical, 18)
    }

    private func labelled<C: View>(_ label: String, @ViewBuilder _ c: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).ui(12, .semibold).foregroundStyle(t.text.color)
            c()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var kindPicker: some View {
        HStack(spacing: 2) {
            kindButton(.session, "Just a session")
            Button { kind = .ticket; kindTouched = true; refreshOpening() } label: {
                segment("Ticket · \(ticketType.rawValue)", on: kind == .ticket)
            }
            .buttonStyle(.plain)
            .contextMenu { ticketTypes }
            if kind == .ticket {
                Menu { ticketTypes } label: { Text("▾").ui(11).foregroundStyle(t.text2.color) }
                    .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                    .accessibilityLabel("Ticket type")
            }
            kindButton(.defect, "Defect")
            kindButton(.workstream, "Workstream")
        }
        .padding(3)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(t.control.color))
    }

    @ViewBuilder private var ticketTypes: some View {
        ForEach([WorkKind.deliverable, .spike, .decision, .chore], id: \.self) { k in
            Button(k.rawValue.capitalized) { ticketType = k; kind = .ticket; kindTouched = true; refreshOpening() }
        }
    }

    private func kindButton(_ k: Kind, _ label: String) -> some View {
        Button { kind = k; kindTouched = true; refreshOpening() } label: { segment(label, on: kind == k) }.buttonStyle(.plain)
    }

    private func segment(_ label: String, on: Bool) -> some View {
        Text(label).ui(13, on ? .semibold : .medium).foregroundStyle(on ? t.text.color : t.text2.color)
            .padding(.vertical, 6).padding(.horizontal, 14)
            .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(on ? t.surface.color : .clear)
                .shadow(color: on ? .black.opacity(0.1) : .clear, radius: 1, y: 1))
            .contentShape(Rectangle())
    }

    private var openWorkstreams: [LinearWorkstream] {
        Intake.rankWorkstreams(text, model.workstreams.filter { !["completed", "canceled"].contains($0.state) })
    }

    private var workstreamPicker: some View {
        Menu {
            ForEach(openWorkstreams) { w in Button("\(w.wsId ?? "") · \(w.title)") { pickWorkstream(w) } }
        } label: {
            HStack(spacing: 4) {
                Text(currentWorkstream.map { "\($0.wsId ?? "") · \($0.title)" } ?? (model.linearLoading ? "Loading workstreams…" : "Pick a workstream"))
                    .ui(12.5, .medium).foregroundStyle(currentWorkstream == nil ? t.needsText.color : t.text.color).lineLimit(1)
                Text("▾").ui(10).foregroundStyle(t.text2.color)
            }
            .padding(.horizontal, 8).padding(.vertical, 4)
            .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous)
                .strokeBorder(currentWorkstream == nil ? t.needsText.color : .clear, lineWidth: 1))
            .frame(maxWidth: 300)
        }
        .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
    }

    private var currentWorkstream: LinearWorkstream? { model.workstreams.first { $0.id == wsId } }

    private func pickWorkstream(_ w: LinearWorkstream) {
        wsId = w.id; model.loadIssues(w); refreshOpening()
        if !SelfTest.isActive { Prefs.defaults.set(w.id, forKey: "newWork.lastWorkstream") }
    }

    /// The selected session's workstream, else the one used last (owner 10-18: an empty picker silently greyed out
    /// "Create ticket and launch").
    private func defaultWorkstream() {
        guard wsId.isEmpty else { return }
        let open = model.workstreams.filter { !["completed", "canceled"].contains($0.state) }
        if let sel = model.selected?.session.workstream, let w = open.first(where: { $0.wsId == sel }) { wsId = w.id; model.loadIssues(w) }
        else if let last = Prefs.defaults.string(forKey: "newWork.lastWorkstream"), let w = open.first(where: { $0.id == last }) { wsId = w.id; model.loadIssues(w) }
    }

    /// Why the primary button is greyed out, in words.
    private var blockedReason: String? {
        guard !valid else { return nil }
        if text.trimmingCharacters(in: .whitespaces).isEmpty && useTicket == nil { return nil }
        return model.linearLoading ? "Loading workstreams from Linear…" : "Pick a workstream (top right) to file the ticket in"
    }

    // MARK: Duplicate check (S09 §1.4)

    private var duplicate: LinearIssue? {
        guard kind == .ticket || kind == .defect, useTicket == nil, let w = currentWorkstream else { return nil }
        return Intake.similar(text, in: model.issues[w.id] ?? []).first
    }

    private func duplicateBanner(_ d: LinearIssue) -> some View {
        HStack(spacing: 10) {
            Text("Similar ticket").ui(12.5, .semibold).foregroundStyle(t.text.color)
            Text("\(d.identifier) · \(d.shortTitle) (\(d.state), \(currentWorkstream?.wsId ?? ""))").ui(12.5).foregroundStyle(t.text2.color).lineLimit(1)
            Spacer()
            Button { useTicket = d; refreshOpening() } label: {
                Text("Plan a session for \(d.identifier) instead").ui(12.5, .semibold).foregroundStyle(t.accentText.color)
            }.buttonStyle(.plain)
        }
        .padding(.horizontal, 12).padding(.vertical, 9)
        .background(RoundedRectangle(cornerRadius: Radius.field, style: .continuous).fill(t.now.color.opacity(0.12)))
        .overlay(RoundedRectangle(cornerRadius: Radius.field, style: .continuous).strokeBorder(t.now.color.opacity(0.35)))
    }

    // MARK: Agent cards (S09 §1.5)

    private func name(_ m: AgentMark) -> String {
        switch m {
        case .claude1: return "Claude1"
        case .claude2: return "Claude2"
        case .codex: return "Codex"
        case .kimi: return "Kimi"
        case .gemini: return "Gemini"
        case .antigravity: return "Antigravity"
        case .shell: return "Terminal"
        }
    }

    private func agent(_ m: AgentMark) -> AgentKind {
        switch m {
        case .claude1, .claude2: return .claude
        case .codex: return .codex
        case .kimi: return .kimi
        case .gemini: return .gemini
        case .antigravity: return .agy
        case .shell: return .shell
        }
    }

    private func seat(_ m: AgentMark) -> SeatUsage? { model.seats.first { $0.seat == name(m) } }

    private func note(_ m: AgentMark) -> String {
        var parts: [String] = []
        if let s = seat(m) {
            if let f = s.fiveHour { parts.append("5h \(Int(f))%") } else if let w = s.sevenDay { parts.append("7d \(Int(w))%") }
            if let r = s.fiveHourResets { parts.append("resets " + r.formatted(date: .omitted, time: .shortened)) }
        } else if m == .shell {
            parts.append("plain shell, no agent")
        } else {
            parts.append([.kimi, .antigravity].contains(m) ? "sessions only" : "no usage feed")
        }
        if suggestedMark == m { parts.append("suggested") }
        return parts.joined(separator: " · ")
    }

    private func agentCard(_ m: AgentMark) -> some View {
        let on = mark == m
        return Button { select(m) } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 7) {
                    AgentBadge(m, size: 22)
                    Text(name(m)).ui(13, .semibold).foregroundStyle(t.text.color).lineLimit(1)
                }
                if m == .shell { Text(note(m)).ui(11).foregroundStyle(t.text3.color) }
                else { SeatGauge(mark: m, used: seat(m)?.worst, note: note(m), style: .card) }
            }
            .padding(10)
            .frame(maxWidth: .infinity, minHeight: 86, alignment: .topLeading)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(on ? t.accent.color.opacity(0.08) : t.surface.color))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(on ? t.accent.color : t.separator.color, lineWidth: on ? 2 : 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(name(m))\(on ? ", selected" : "")")
    }

    private func select(_ m: AgentMark) {
        mark = m
        let a = agent(m)
        let d = model.settings.defaults(for: a)
        modelName = d.model
        args = d.args
        refreshOpening()
    }

    // MARK: Model · repo · start in

    /// Any model name works (the CLI gets --model <name>); the menu offers the known ones.
    private var modelMenu: some View {
        HStack(spacing: 4) {
            TextField("CLI default", text: $modelName).textFieldStyle(.plain).ui(13)
            Menu {
                Button("CLI default") { modelName = "" }
                ForEach(agent(mark).suggestedModels, id: \.self) { m in Button(m) { modelName = m } }
            } label: { Text("▾").ui(11).foregroundStyle(t.text2.color) }
            .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
        }
        .padding(.horizontal, 10).frame(height: 30)
        .background(RoundedRectangle(cornerRadius: Radius.field, style: .continuous).fill(t.card.color))
    }

    private var repoMenu: some View {
        FieldMenu(title: Workspace.repoLabel(for: repo)) {
            ForEach(repos, id: \.self) { r in Button(Workspace.repoLabel(for: r)) { repo = r; if r == Workspace.projectsRoot { startInRepo = false } } }
        }
    }

    /// "~/Projects · one memory ✓", or the repo folder with the blog rule's warning.
    private var startIn: some View {
        FieldMenu(title: startInRepo ? "Repo folder ⚠" : "~/Projects · one memory ✓", tint: startInRepo ? t.now : t.statusDone) {
            Button("~/Projects · one memory") { startInRepo = false }
            Button("Repo folder (\(Workspace.repoLabel(for: repo)))") { startInRepo = true }.disabled(repo == Workspace.projectsRoot)
        }
        .help(startInRepo ? "Claude memory will split from ~/Projects" : "Starts in ~/Projects so every agent shares one memory")
    }

    private func box(_ binding: Binding<String>, minHeight: CGFloat, onEdit: (() -> Void)? = nil) -> some View {
        TextEditor(text: binding)
            .ui(13).scrollContentBackground(.hidden)
            .padding(8).frame(minHeight: minHeight, maxHeight: 110)
            .background(RoundedRectangle(cornerRadius: Radius.field, style: .continuous).fill(t.card.color))
            .foregroundStyle(t.text.color)
            .onChange(of: binding.wrappedValue) { _, _ in onEdit?() }
    }

    // MARK: Advanced

    private var advancedFields: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                labelled("Agent arguments") {
                    TextField("e.g. --permission-mode plan", text: $args).textFieldStyle(.plain).ui(12.5, mono: true)
                        .padding(.horizontal, 8).frame(height: 28)
                        .background(RoundedRectangle(cornerRadius: Radius.field).fill(t.card.color))
                }
                labelled("Role") {
                    FieldMenu(title: roles.first { $0.id == roleId }?.title ?? "None") {
                        Button("None") { roleId = "" }
                        ForEach(roles) { r in Button("\(r.title) · \(r.agent.displayName)") { applyRole(r) } }
                    }
                }
            }
            if agent(mark) == .claude {
                labelled("Resume a Claude conversation") {
                    FieldMenu(title: conversations.first { $0.id == resumeId }?.title ?? "New conversation") {
                        Button("New conversation") { resumeId = "" }
                        ForEach(conversations) { c in
                            Button("\(c.title) · \(c.modified.formatted(.relative(presentation: .named)))") { pickConversation(c) }
                        }
                    }
                }
                if let c = conversations.first(where: { $0.id == resumeId }), c.maybeOpen() {
                    Text("Active \(c.modified.formatted(.relative(presentation: .named))): close it in the other terminal first so two Claudes don't write to it.")
                        .ui(12).foregroundStyle(t.now.color)
                }
            }
            HStack(spacing: 6) {
                Toggle("Own git worktree", isOn: .constant(false)).disabled(true).ui(12.5)
                Text("not connected").ui(11.5).foregroundStyle(t.text3.color)
            }
        }
        .padding(.top, 8)
    }

    // MARK: When

    private var whenPicker: some View {
        HStack(spacing: 2) {
            whenButton(.now, "Now")
            whenButton(.next, "Next")
            Button { when = .tonight } label: { segment(nightly ? "Nightly 2:00 AM" : "Tonight 2:00 AM", on: when == .tonight) }
                .buttonStyle(.plain)
            if when == .tonight {
                Menu {
                    Button("Tonight 2:00 AM") { nightly = false }
                    Button("Nightly at 2:00 AM") { nightly = true }
                } label: { Text("▾").ui(11).foregroundStyle(t.text2.color) }
                    .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
            }
            whenButton(.onDemand, "On demand")
        }
        .padding(3)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(t.control.color))
    }

    private func whenButton(_ w: When, _ label: String) -> some View {
        Button { when = w } label: { segment(label, on: when == w) }.buttonStyle(.plain)
    }

    private var primaryLabel: String {
        let ticket = (kind == .ticket || kind == .defect) && useTicket == nil
        switch when {
        case .now: return ticket ? "Create ticket and launch ⌘↩" : kind == .workstream ? "Plan the workstream session ⌘↩" : "Launch ⌘↩"
        case .next: return ticket ? "Create ticket, up next ⌘↩" : "Save as next ⌘↩"
        case .tonight: return nightly ? "Save for every night ⌘↩" : "Save for tonight ⌘↩"
        case .onDemand: return "Save on demand ⌘↩"
        }
    }

    private var valid: Bool {
        let has = !text.trimmingCharacters(in: .whitespaces).isEmpty || useTicket != nil
        if (kind == .ticket || kind == .defect) && useTicket == nil { return has && currentWorkstream != nil }
        return has
    }

    // MARK: Behaviour

    private func appear() {
        DispatchQueue.main.async { textFocused = true }
        roles = Role.load(agenticEngineering: model.settings.agenticEngineering.path)
        model.loadWorkstreams()
        defaultWorkstream()
        let acc = model.settings.defaults(for: .claude).account
        select(acc == "Claude2" && marks.contains(.claude2) ? .claude2 : .claude1)
        if let w = ProcessInfo.processInfo.environment["ONEROOF_SELFTEST_WHEN"] {
            when = ["now": When.now, "next": .next, "tonight": .tonight, "ondemand": .onDemand][w] ?? .now
        }
        let dir = Workspace.projectsRoot
        DispatchQueue.global(qos: .userInitiated).async {
            let list = ConversationIndex.recent(in: ConversationIndex.folder(forLaunchDirectory: dir))
            DispatchQueue.main.async { conversations = list }
        }
    }

    /// Debounced 500 ms: ticket-type suggestion (intake), router suggestion (on-device model + seats), duplicate check.
    private func textChanged(_ v: String) {
        useTicket = nil
        // The kind stays what the owner picked (owner 10-20: "it starts as just a session and should remain just a
        // session"). The text only pre-picks the ticket type, for when the owner switches to Ticket.
        if !kindTouched {
            switch Intake.suggest(v) {
            case .session, .defect, .workstream: break
            case let k: ticketType = k
            }
        }
        refreshOpening()
        debounce?.cancel()
        let work = DispatchWorkItem {
            guard v.count > 6 else { return }
            if let w = currentWorkstream { model.loadIssues(w) }
            model.suggestAgent(for: v) { r, _ in
                suggestion = r
                let m = AgentMark(agent: r.agent, account: r.account)
                withAnimation(Motion.base) { suggestedMark = m }
            }
        }
        debounce = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
    }

    /// The opening message template (S09 §1.7), until the owner edits it.
    private func refreshOpening() {
        guard !openingTouched else { return }
        let title = useTicket?.shortTitle ?? text.trimmingCharacters(in: .whitespaces)
        if let tk = useTicket, let w = currentWorkstream {
            opening = "Work on \(tk.identifier) (\(w.wsId ?? w.name)): \(tk.shortTitle). Read the ticket and the workstream docs first; commit as `\(tk.identifier) · [\((w.wsId ?? "").lowercased())] …`."
        } else if (kind == .ticket || kind == .defect), let w = currentWorkstream {
            opening = "Work on the new ticket (\(w.wsId ?? w.name)): \(title). Read the ticket and the workstream docs first; commit as `<KEY> · [\((w.wsId ?? "").lowercased())] …`."
        } else {
            opening = title
        }
        DispatchQueue.main.async { openingTouched = false }
    }

    private func applyRole(_ r: Role) {
        roleId = r.id
        mark = AgentMark(agent: r.agent, account: model.settings.defaults(for: r.agent).account)
        if let m = r.model { modelName = m }
        if text.isEmpty { text = r.title }
        opening = r.opening(repo: Workspace.repoLabel(for: repo), workstream: currentWorkstream?.wsId)
        openingTouched = true
    }

    private func pickConversation(_ c: Conversation) {
        resumeId = c.id
        if text.isEmpty { text = c.title }
        if wsText.isEmpty, let ws = Workspace.workstream(in: c.title + " " + (c.lastPrompt ?? "")) { wsText = ws }
    }

    private func go(launch: Bool, forcePlanned: Bool = false) {
        let title = useTicket?.shortTitle ?? text.trimmingCharacters(in: .whitespaces)
        if kind == .workstream && useTicket == nil {
            model.planWorkstreamSession(title: title, details: doneWhen)
            if launch, let s = model.selected { model.launch(s) }
            close()
            return
        }
        func makeSession(ticket: LinearIssue?, w: LinearWorkstream?) {
            let a = agent(mark)
            var s = Session(name: title, agent: a,
                            account: a == .claude ? name(mark) : (AccountResolver.choices(for: a).first),
                            repoPath: repo,
                            workstream: w?.wsId ?? (wsText.trimmingCharacters(in: .whitespaces).isEmpty ? Workspace.workstream(in: title) : wsText.trimmingCharacters(in: .whitespaces).uppercased()),
                            objective: doneWhen, openingMessage: a.isAgent ? opening : "",
                            lifecycle: forcePlanned || when == .onDemand ? .planned : .next,
                            startInRepo: startInRepo,
                            agentArgs: a.isAgent ? (resumeId.isEmpty ? [] : ["--resume", resumeId]) + Session.parseArgs(args) : [],
                            model: modelName.trimmingCharacters(in: .whitespaces).isEmpty ? nil : modelName,
                            ticket: ticket?.identifier, ticketId: ticket?.id, ticketTeam: w?.team)
            if let r = roles.first(where: { $0.id == roleId }) { s.tags = [Sticker.resolve(r.kind).builtIn ? r.kind : "review"] }
            model.createPlanned(s, launchNow: launch && !forcePlanned)
            if when == .tonight && !forcePlanned, let i = model.item(s.id) { model.schedule(i, hour: 2, minute: 0, nightly: nightly) }
            close()
        }
        if let tk = useTicket { makeSession(ticket: tk, w: currentWorkstream); return }
        if (kind == .ticket || kind == .defect), let w = currentWorkstream {
            busy = true
            let type: WorkKind = kind == .defect ? .defect : ticketType
            model.createTicket(kind: type, title: title, details: doneWhen, in: w, milestone: nil, planSession: false) { r in
                busy = false
                switch r {
                case .success(let issue): makeSession(ticket: issue, w: w)
                case .failure(let e): error = "Linear: \(e)"
                }
            }
            return
        }
        makeSession(ticket: nil, w: nil)
    }
}
