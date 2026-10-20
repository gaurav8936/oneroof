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
    @State private var teamKey = ""
    @State private var projectCode = ""
    @State private var milestonesText = ""
    @State private var textForIssue = ""
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
                    Text("New session").ui(20, .semibold).foregroundStyle(t.text.color)
                    Text("in \(win.name)").ui(13).foregroundStyle(t.text3.color)
                    Spacer()
                }
                // A session first (owner 10-20, LAB-242): optionally in a team, project and issue picked from what
                // exists; a new issue or project is the last item of its menu, not a mode of the sheet.
                if linked {
                    HStack(spacing: 14) {
                        teamPicker
                        workstreamPicker
                        issuePicker
                        Spacer(minLength: 0)
                    }
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text("What should happen").ui(12, .semibold).foregroundStyle(t.text.color)
                    TextField("", text: $text, prompt: Text(textForIssue.isEmpty ? "e.g. Help search returns results as you type" : textForIssue))
                        .textFieldStyle(.plain).ui(15).focused($textFocused)
                        .padding(.horizontal, 12).frame(height: 40)
                        .background(RoundedRectangle(cornerRadius: Radius.field, style: .continuous).fill(t.surface.color))
                        .overlay(RoundedRectangle(cornerRadius: Radius.field, style: .continuous)
                            .strokeBorder(textFocused ? t.accent.color : t.separatorStrong.color, lineWidth: textFocused ? 2 : 1))
                        .onChange(of: text) { _, v in textChanged(v) }
                }
                if let d = duplicate { duplicateBanner(d) }
                if kind == .workstream && linked { projectFields }
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
                    if kind == .session && !linked {
                        labelled("Project") {
                            TextField("CODE-…", text: $wsText).textFieldStyle(.plain).ui(13, mono: true)
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
                Text("When").ui(12, .semibold).foregroundStyle(t.text.color).fixedSize()
                whenPicker
                // Messages wrap inside their own space, so the bottom row never widens the sheet (LAB-243).
                if let error { Text(error).ui(12).foregroundStyle(t.needsText.color).lineLimit(2).frame(maxWidth: 200, alignment: .leading) }
                else if let why = blockedReason { Text(why).ui(12).foregroundStyle(t.needsText.color).lineLimit(2).frame(maxWidth: 200, alignment: .leading) }
                Spacer()
                if busy { ProgressView().controlSize(.small) }
                RoofButton("Cancel") { close() }.fixedSize().keyboardShortcut(.cancelAction)
                RoofButton("Save as planned") { go(launch: false, forcePlanned: true) }.fixedSize().disabled(!valid)
                RoofButton(primaryLabel, .primary) { go(launch: when == .now) }
                    .fixedSize()
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

    private func segment(_ label: String, on: Bool, inset: CGFloat = 14) -> some View {
        Text(label).ui(13, on ? .semibold : .medium).foregroundStyle(on ? t.text.color : t.text2.color)
            .lineLimit(1).fixedSize()
            .padding(.vertical, 6).padding(.horizontal, inset)
            .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(on ? t.surface.color : .clear)
                .shadow(color: on ? .black.opacity(0.1) : .clear, radius: 1, y: 1))
            .contentShape(Rectangle())
    }

    /// Linear is connected: Team and Project come from it (LAB-236/237).
    private var linked: Bool { model.linear.hasKey }
    private var needsTeam: Bool { kind != .session && useTicket == nil }

    /// Open projects, in the picked team (LAB-237), best match for the text first.
    private var openWorkstreams: [LinearWorkstream] {
        Intake.rankWorkstreams(text, model.workstreams.filter {
            !["completed", "canceled"].contains($0.state) && (teamKey.isEmpty || $0.team == teamKey)
        })
    }

    /// One Text (a borderless Menu draws only the first view of an HStack label, so the ▾ went missing).
    private func pickerLabel(_ title: String, _ value: String, warn: Bool) -> some View {
        (Text(title + "  ").foregroundColor(t.text2.color) + Text(value).foregroundColor(warn ? t.needsText.color : t.text.color)
         + Text("  ▾").foregroundColor(t.text2.color))
            .ui(12.5, .medium).lineLimit(1).truncationMode(.middle)
        .padding(.horizontal, 8).padding(.vertical, 4)
        .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(warn ? t.needsText.color : .clear, lineWidth: 1))
    }

    private var currentTeam: LinearTeamRef? { model.linearTeams.first { $0.key == teamKey } }

    /// Team first (LAB-237): a ticket or project always has one; a plain session may have none.
    private var teamPicker: some View {
        Menu {
            if kind == .session { Button("No team") { pickTeam("") } }
            ForEach(model.linearTeams) { tm in Button("\(tm.key) · \(tm.name)") { pickTeam(tm.key) } }
        } label: {
            pickerLabel("Team", currentTeam.map { "\($0.key) · \($0.name)" }
                        ?? (model.linearLoading ? "Loading teams…" : kind == .session ? "No team" : "Pick a team"),
                        warn: needsTeam && teamKey.isEmpty)
        }
        .menuStyle(.borderlessButton).menuIndicator(.hidden).frame(maxWidth: 170, alignment: .leading)
        .accessibilityLabel("Team")
    }

    private var workstreamPicker: some View {
        Menu {
            if linked { Button("No project") { wsId = ""; useTicket = nil; if kind == .workstream { kind = .session }; refreshOpening() } }
            ForEach(openWorkstreams) { w in Button("\(w.wsId ?? "") · \(w.title)") { pickWorkstream(w) } }
            if linked {
                Divider()
                Button("New project…") { wsId = ""; useTicket = nil; kind = .workstream; kindTouched = true; refreshOpening() }
            }
        } label: {
            pickerLabel("Project", kind == .workstream ? "New project" : currentWorkstream.map { "\($0.wsId ?? "") · \($0.title)" }
                        ?? (model.linearLoading ? "Loading projects…" : linked ? "No project" : "Pick a project"),
                        warn: !linked && currentWorkstream == nil)
        }
        .menuStyle(.borderlessButton).menuIndicator(.hidden).frame(maxWidth: 290, alignment: .leading)
        .accessibilityLabel("Project")
    }

    /// The project's open issues, newest first.
    private var openIssues: [LinearIssue] {
        guard let w = currentWorkstream else { return [] }
        return (model.issues[w.id] ?? []).filter { !["completed", "canceled"].contains($0.stateType) }.reversed()
    }

    private var issueLabel: String {
        if let tk = useTicket { return "\(tk.identifier) · \(tk.shortTitle)" }
        if kind == .defect { return "New bug" }
        if kind == .ticket { return "New " + (ticketType.labelNames.first ?? "issue").lowercased() }
        return "No issue"
    }

    /// Issue: none, an existing one (the session works on it), or a new one as the last item (LAB-242).
    private var issuePicker: some View {
        Menu {
            Button("No issue") { useTicket = nil; kind = .session; refreshOpening() }
            if !openIssues.isEmpty {
                Divider()
                ForEach(openIssues.prefix(40)) { i in Button("\(i.identifier) · \(i.shortTitle)") { pickIssue(i) } }
            }
            Divider()
            Menu("New issue…") {
                ForEach([WorkKind.deliverable, .defect, .chore, .spike, .decision], id: \.self) { k in
                    Button(k.labelNames.first ?? k.rawValue) { newIssue(k) }
                }
            }
        } label: {
            pickerLabel("Issue", issueLabel, warn: false)
        }
        .menuStyle(.borderlessButton).menuIndicator(.hidden).frame(maxWidth: 300, alignment: .leading)
        .disabled(kind == .workstream)
        .accessibilityLabel("Issue")
    }

    private func pickIssue(_ i: LinearIssue) {
        useTicket = i; kind = .session; kindTouched = true
        if text.trimmingCharacters(in: .whitespaces).isEmpty { textForIssue = i.shortTitle }
        refreshOpening()
    }

    private func newIssue(_ k: WorkKind) {
        useTicket = nil; kindTouched = true
        if k == .defect { kind = .defect } else { kind = .ticket; ticketType = k }
        if kind == .workstream { wsId = "" }
        refreshOpening()
    }

    private var currentWorkstream: LinearWorkstream? { model.workstreams.first { $0.id == wsId } }

    private func pickWorkstream(_ w: LinearWorkstream) {
        if wsId != w.id { useTicket = nil }
        if kind == .workstream { kind = .session }
        wsId = w.id; model.loadIssues(w)
        if !w.team.isEmpty { teamKey = w.team }
        refreshOpening()
        if !SelfTest.isActive {
            Prefs.defaults.set(w.id, forKey: "newWork.lastWorkstream")
            Prefs.defaults.set(teamKey, forKey: "newWork.lastTeam")
        }
    }

    private func pickTeam(_ key: String) {
        teamKey = key
        if let w = currentWorkstream, !key.isEmpty, w.team != key { wsId = "" }
        refreshOpening()
        if !SelfTest.isActive { Prefs.defaults.set(key, forKey: "newWork.lastTeam") }
    }

    /// The selected session's project, else the one used last (owner 10-18: an empty picker silently greyed out
    /// "Create ticket and launch"); the team follows it, else the team used last.
    private func defaultWorkstream() {
        if wsId.isEmpty {
            let open = model.workstreams.filter { !["completed", "canceled"].contains($0.state) }
            if let code = ProcessInfo.processInfo.environment["ONEROOF_SELFTEST_PROJECT"], let w = open.first(where: { $0.wsId == code }) {
                pickWorkstream(w); return
            }
            if let sel = model.selected?.session.workstream, let w = open.first(where: { $0.wsId == sel }) { wsId = w.id; model.loadIssues(w) }
            else if let last = Prefs.defaults.string(forKey: "newWork.lastWorkstream"), let w = open.first(where: { $0.id == last }) { wsId = w.id; model.loadIssues(w) }
        }
        if teamKey.isEmpty {
            if let w = currentWorkstream, !w.team.isEmpty { teamKey = w.team }
            else if let last = Prefs.defaults.string(forKey: "newWork.lastTeam") { teamKey = last }
        }
    }

    /// Project code (TEAM-TOPIC[-NN]) and milestones for a new Linear project (LAB-238).
    private var projectFields: some View {
        HStack(alignment: .top, spacing: 10) {
            labelled("Code") {
                TextField("", text: $projectCode, prompt: Text("\(teamKey.isEmpty ? "TEAM" : teamKey)-TOPIC"))
                    .textFieldStyle(.plain).ui(13, mono: true)
                    .padding(.horizontal, 10).frame(width: 200, height: 30)
                    .background(RoundedRectangle(cornerRadius: Radius.field, style: .continuous).fill(t.card.color))
            }
            labelled("Milestones · comma separated, in order") {
                TextField("", text: $milestonesText, prompt: Text("P0 Design, P1 Build, P2 Ship"))
                    .textFieldStyle(.plain).ui(13)
                    .padding(.horizontal, 10).frame(height: 30)
                    .background(RoundedRectangle(cornerRadius: Radius.field, style: .continuous).fill(t.card.color))
            }
        }
    }

    private var codeOK: Bool {
        let c = projectCode.trimmingCharacters(in: .whitespaces)
        return c.isEmpty || Workspace.projectCode(name: c + " · x") != nil
    }

    /// Why the primary button is greyed out, in words.
    private var blockedReason: String? {
        guard !valid else { return nil }
        if text.trimmingCharacters(in: .whitespaces).isEmpty && useTicket == nil { return nil }
        if model.linearLoading { return "Loading teams and projects from Linear…" }
        if linked && needsTeam && teamKey.isEmpty { return kind == .workstream ? "Pick a team (top right) for the project" : "Pick a team (top right) to file the ticket in" }
        if kind == .workstream && !codeOK { return "The code looks like TEAM-TOPIC or TEAM-TOPIC-01" }
        return "Pick a project (top right) to file the ticket in"
    }

    // MARK: Duplicate check (S09 §1.4)

    private var duplicate: LinearIssue? {
        guard kind == .ticket || kind == .defect, useTicket == nil, let w = currentWorkstream else { return nil }
        return Intake.similar(text, in: model.issues[w.id] ?? []).first
    }

    private func duplicateBanner(_ d: LinearIssue) -> some View {
        HStack(spacing: 10) {
            Text("Similar ticket").ui(12.5, .semibold).foregroundStyle(t.text.color)
            Text("\(d.identifier) · \(d.shortTitle) (\(d.state)\(currentWorkstream?.wsId.map { ", " + $0 } ?? ""))").ui(12.5).foregroundStyle(t.text2.color).lineLimit(1)
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
            Button { when = .tonight } label: { segment(nightly ? "Nightly 2 AM" : "Tonight 2 AM", on: when == .tonight, inset: 9) }
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
        Button { when = w } label: { segment(label, on: when == w, inset: 9) }.buttonStyle(.plain)
    }

    private var primaryLabel: String {
        let ticket = (kind == .ticket || kind == .defect) && useTicket == nil
        switch when {
        case .now: return ticket ? "Create issue, launch ⌘↩" : kind == .workstream ? (linked ? "Create project, launch ⌘↩" : "Plan the project ⌘↩") : "Launch ⌘↩"
        case .next: return ticket ? "Create issue, next ⌘↩" : kind == .workstream && linked ? "Create project, next ⌘↩" : "Save as next ⌘↩"
        case .tonight: return nightly ? "Save for every night ⌘↩" : "Save for tonight ⌘↩"
        case .onDemand: return "Save on demand ⌘↩"
        }
    }

    private var valid: Bool {
        let has = !text.trimmingCharacters(in: .whitespaces).isEmpty || useTicket != nil
        if (kind == .ticket || kind == .defect) && useTicket == nil { return has && (linked ? !teamKey.isEmpty : currentWorkstream != nil) }
        if kind == .workstream && linked { return has && !teamKey.isEmpty && codeOK }
        return has
    }

    // MARK: Behaviour

    private func appear() {
        DispatchQueue.main.async { textFocused = true }
        roles = Role.load(agenticEngineering: model.settings.agenticEngineering.path)
        model.loadWorkstreams(force: model.linearTeams.isEmpty)
        defaultWorkstream()
        let acc = model.settings.defaults(for: .claude).account
        select(acc == "Claude2" && marks.contains(.claude2) ? .claude2 : .claude1)
        let env = ProcessInfo.processInfo.environment
        if let k = env["ONEROOF_SELFTEST_KIND"].flatMap(Kind.init(rawValue:)) { kind = k; kindTouched = true }
        if let k = env["ONEROOF_SELFTEST_TEAM"] { teamKey = k }
        if let w = env["ONEROOF_SELFTEST_WHEN"] {
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
        // A picked issue stays picked while you type (LAB-242: it is chosen on purpose in the Issue menu).
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
            opening = "Work on \(tk.identifier) (\(w.wsId ?? w.name)): \(tk.shortTitle). Read the ticket and the project docs first; commit as `\(tk.identifier) · [\((w.wsId ?? "").lowercased())] …`."
        } else if (kind == .ticket || kind == .defect), let w = currentWorkstream {
            opening = "Work on the new ticket (\(w.wsId ?? w.name)): \(title). Read the ticket and the project docs first; commit as `<KEY> · [\((w.wsId ?? "").lowercased())] …`."
        } else if kind == .ticket || kind == .defect, !teamKey.isEmpty {
            opening = "Work on the new ticket (team \(teamKey)): \(title). Read the ticket first; commit as `<KEY> · …`."
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
        let typed = text.trimmingCharacters(in: .whitespaces)
        let title = typed.isEmpty ? (useTicket?.shortTitle ?? "") : typed
        if kind == .workstream && useTicket == nil, linked, let team = currentTeam {
            busy = true
            let ms = milestonesText.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            model.createProject(team: team, code: projectCode.trimmingCharacters(in: .whitespaces).uppercased(), title: title,
                                summary: doneWhen, milestones: ms) { r in
                busy = false
                switch r {
                case .success(let p):
                    model.planWorkstreamSession(title: title, details: doneWhen, project: p)
                    if launch && !forcePlanned, let s = model.selected { model.launch(s) }
                    close()
                case .failure(let e): error = "Linear: \(e)"
                }
            }
            return
        }
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
                            ticket: ticket?.identifier, ticketId: ticket?.id,
                            ticketTeam: ticket == nil ? w?.team : (w?.team ?? (teamKey.isEmpty ? nil : teamKey)))
            if let r = roles.first(where: { $0.id == roleId }) { s.tags = [Sticker.resolve(r.kind).builtIn ? r.kind : "review"] }
            model.createPlanned(s, launchNow: launch && !forcePlanned)
            if when == .tonight && !forcePlanned, let i = model.item(s.id) { model.schedule(i, hour: 2, minute: 0, nightly: nightly) }
            close()
        }
        if let tk = useTicket { makeSession(ticket: tk, w: currentWorkstream); return }
        if (kind == .ticket || kind == .defect), currentWorkstream != nil || (linked && !teamKey.isEmpty) {
            busy = true
            let w = currentWorkstream
            let type: WorkKind = kind == .defect ? .defect : ticketType
            model.createTicket(kind: type, title: title, details: doneWhen, in: w, team: teamKey, milestone: nil, planSession: false) { r in
                busy = false
                switch r {
                case .success(let issue): makeSession(ticket: issue, w: w)
                case .failure(let e): error = "Linear: \(e)"
                }
            }
            return
        }
        makeSession(ticket: nil, w: currentWorkstream)
    }
}
