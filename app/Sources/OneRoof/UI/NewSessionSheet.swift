import SwiftUI
import UniformTypeIdentifiers
import OneRoofCore

/// New work (⌘N): what it is (intake), what should happen, duplicate check, agent and account with the router's
/// suggestion, model · repo · start folder, done when + opening message, Advanced (args, resume, role), and when.
/// The launch path: a roofd session in the start folder with the account's environment, the agent started through the login shell →
/// opening message once the agent is ready and idle.
struct NewSessionSheet: View {
    @Environment(\.theme) private var t
    /// LAB-1571: the Project picker lists In Progress projects only, until switched off (remembered).
    @AppStorage("newSession.projectsActiveOnly") private var projectsActiveOnly = true
    @ObservedObject var model: AppModel
    @ObservedObject var win: WindowState
    var close: () -> Void

    enum Kind: String, CaseIterable { case session, ticket, defect, workstream }
    enum When: String, CaseIterable { case now, next, tonight, every, onDemand }

    @State private var kind: Kind = .session
    /// LAB-1514: the window the new session joins (nil = this window). Case C: sessions piled into whichever window
    /// was in front, so a busy window collected unrelated work.
    @State private var targetWindowId: String?
    @State private var ticketType: WorkKind = .deliverable
    @State private var kindTouched = false
    @State private var text = ""
    @State private var wsId = ""
    @State private var teamKey = ""
    @State private var projectCode = ""
    @State private var milestonesText = ""
    @State private var textForIssue = ""
    /// The picked issues (LAB-518), shared with the issue picker panel (LAB-523): the first is the session's ticket.
    @StateObject private var selection = IssueSelection()
    @State private var mark: SeatMark = .claude1
    @State private var modelName = ""
    @State private var hostedConnectionID = ""
    @State private var repo = Workspace.projectsRoot
    @State private var startInRepo = false
    @State private var doneWhen = ""
    @State private var opening = ""
    /// LAB-638: the last message the sheet generated. The message counts as edited when it differs from it (or a role
    /// or self-test set it): a flag set on every change raced the sheet's own updates and could stick, which froze a
    /// stale message while the team, project or issues changed.
    @State private var generatedOpening = ""
    @State private var openingSetByHand = false
    @State private var advanced = false
    @State private var args = ""
    /// LAB-1600: the permission mode picked here; nil = the agent's mode from Settings › Permissions.
    @State private var permMode: PermissionMode?
    @State private var resumeId = ""
    @State private var roleId = ""
    @State private var roles: [Role] = []
    @State private var conversations: [Conversation] = []
    @State private var when: When = .now
    @State private var nightly = false
    @State private var everyMinutes = 60
    @State private var suggestion: RouteSuggestion?
    @State private var suggestedMark: SeatMark?
    @State private var busy = false
    @State private var error: String?
    @State private var debounce: DispatchWorkItem?
    @FocusState private var textFocused: Bool
    /// Images pasted (⌘V) or dropped into the sheet (LAB-462): saved paths, with their thumbnails.
    @State private var images: [String] = []
    @State private var thumbs: [String: NSImage] = [:]
    @State private var dropTargeted = false
    @State private var pasteMonitor: Any?
    @StateObject private var sheetWindow = WindowRef()

    private let repos = [Workspace.projectsRoot] + Workspace.listRepos()
    /// One card per agent account (LAB-1999: Codex2, Gemini3 … follow their agent's first card), then Terminal.
    private var marks: [SeatMark] { Self.cards(model.settings.agentAccounts()) }

    static func cards(_ accounts: [AgentAccount]) -> [SeatMark] {
        let kinds: [AgentKind] = [.claude, .codex, .kimi, .gemini, .agy, .opencode, .goose]
        return kinds.flatMap { k in accounts.filter { $0.agent == k }.map(\.seat) } + [.shell]
    }
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
                if model.windows.count > 1 { windowPicker }
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
                attachments
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
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 5), spacing: 10) {
                    ForEach(marks, id: \.self) { agentCard($0) }
                }
                if agent(mark).isHosted {
                    Text("Choose a saved connection; start at ~/Projects or in any repository. Hosted sessions use Manual approvals and the connection's exact model and ceilings; timed and recurring starts are disabled.")
                        .ui(12).foregroundStyle(t.text2.color)
                }
                if mark.mark == .gemini { geminiKeyBanner }
                HStack(alignment: .top, spacing: 10) {
                    if agent(mark).isHosted { labelled("Hosted connection · model") { hostedMenu } }
                    else if mark != .shell { labelled("Model") { modelMenu } }
                    labelled("Repo") { repoMenu }
                    if !agent(mark).isHosted { labelled("Start in") { startIn } }
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
                    // LAB-639: say what Done when is for and what it does not do.
                    labelled(doneWhenNeeded ? "Done when · required" : "Done when · optional") {
                        box($doneWhen, minHeight: 64, placeholder: "What finished looks like, e.g. \"tests pass and the feed shows newest first\"")
                            .onChange(of: doneWhen) { _, _ in refreshOpening() }
                        Text(mark == .shell ? "Kept with the session and shown in its Plan panel."
                             : "Told to the agent in the opening message and shown in the Plan panel. It never ends the session or runs last call; you decide when it is done.")
                            .ui(11.5).foregroundStyle(t.text3.color).fixedSize(horizontal: false, vertical: true)
                    }
                    if mark != .shell {
                        labelled("Opening message · sent when the agent is ready") {
                            box($opening, minHeight: 64)
                            Text(openingTouched ? "Edited by you: your words stay; the focus and issue list still follow your picks."
                                 : "Built from the team, project, issues, what should happen and done when; it updates as you change them.")
                                .ui(11.5).foregroundStyle(t.text3.color).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                DisclosureGroup(isExpanded: $advanced) { advancedFields } label: {
                    Text("Advanced").ui(12, .semibold).foregroundStyle(t.text2.color)
                }
            }
            Hairline()
            // One row when it fits; otherwise When on top and the buttons below (LAB-472: "Create issue, launch"
            // made the fixed-size row wider than the sheet, which then overflowed off both edges).
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) { whenRow; Spacer(); actionButtons }
                VStack(alignment: .leading, spacing: 12) {
                    whenRow
                    HStack(spacing: 10) { Spacer(); actionButtons }
                }
            }
            .padding(.horizontal, 26).padding(.vertical, 16)
        }
        .frame(width: 820)
        .background(t.window.color)
        .background(WindowReader(ref: sheetWindow))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .strokeBorder(dropTargeted ? t.accent.color : .clear, lineWidth: 2).allowsHitTesting(false))
        .onDrop(of: [.fileURL, .image], isTargeted: $dropTargeted, perform: drop)
        .onAppear(perform: appear)
        .onAppear(perform: installPaste)
        .onDisappear(perform: removePaste)
        .onDisappear { IssuePickerPanel.close() }
        .onChange(of: model.workstreams) { _, _ in defaultWorkstream(); refreshOpening() }
        // LAB-638: the opening follows the team, project and kind however they change (the last-used project and team
        // are picked in on open, and the team names arrive from Linear later).
        .onChange(of: wsId) { _, _ in refreshOpening() }
        .onChange(of: teamKey) { _, _ in refreshOpening() }
        .onChange(of: kind) { _, _ in refreshOpening() }
        .onReceive(model.$linearTeams.dropFirst()) { _ in DispatchQueue.main.async { refreshOpening() } }
        .onReceive(model.$issues) { all in selfTestPick(all) }
        .onReceive(selection.$issues.dropFirst()) { _ in DispatchQueue.main.async { selectionChanged() } }
        .onReceive(selection.$newKind.compactMap { $0 }) { k in DispatchQueue.main.async { selection.newKind = nil; newIssue(k) } }
    }

    /// Self-test (LAB-518): ONEROOF_SELFTEST_PICK=KEY,KEY,… ticks those issues once the project's issues load;
    /// ONEROOF_SELFTEST_ISSUES=1 opens the issue checklist.
    private static var selfTestPicked = false

    private func selfTestPick(_ all: [String: [LinearIssue]]) {
        let env = ProcessInfo.processInfo.environment
        // @Published sends the new value before `model.issues` holds it, so read the value sent.
        // Once: the issues are published more than once while they load, and a second pass would untick them.
        guard SelfTest.isActive, !Self.selfTestPicked, let w = currentWorkstream, let list = all[w.id], !list.isEmpty else { return }
        Self.selfTestPicked = true
        // LAB-528: the owner's own words typed before the picks (they must survive, and the list must follow the picks).
        if let o = env["ONEROOF_SELFTEST_OPENING"] { opening = o; openingSetByHand = true }
        for k in (env["ONEROOF_SELFTEST_PICK"] ?? "").split(separator: ",").map(String.init) {
            if let i = list.first(where: { $0.identifier == k }) { toggleIssue(i) }
        }
        if env["ONEROOF_SELFTEST_ISSUES"] == "1" { DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { openIssuePicker() } }
        if let out = env["ONEROOF_SELFTEST_OUT"] {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { try? opening.write(toFile: out + ".opening.txt", atomically: true, encoding: .utf8) }
        }
    }

    // MARK: Bottom row

    @ViewBuilder private var whenRow: some View {
        HStack(spacing: 10) {
            Text("When").ui(12, .semibold).foregroundStyle(t.text.color).fixedSize()
            whenPicker
            // Messages wrap inside their own space, so the bottom row never widens the sheet (LAB-243).
            if let error { Text(error).ui(12).foregroundStyle(t.needsText.color).lineLimit(2).frame(maxWidth: 200, alignment: .leading) }
            else if let why = blockedReason { Text(why).ui(12).foregroundStyle(t.needsText.color).lineLimit(2).frame(maxWidth: 200, alignment: .leading) }
        }
    }

    @ViewBuilder private var actionButtons: some View {
        if busy { ProgressView().controlSize(.small) }
        RoofButton("Cancel") { close() }.fixedSize().keyboardShortcut(.cancelAction)
        RoofButton("Save as planned") { go(launch: false, forcePlanned: true) }.fixedSize().disabled(!valid)
        RoofButton(primaryLabel, .primary) { go(launch: when == .now || when == .every) }
            .fixedSize()
            .keyboardShortcut(.return, modifiers: .command)
            .disabled(!valid || busy)
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
                && (!projectsActiveOnly || ActiveFilter.project($0.state) || $0.id == wsId)
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
    /// The team the opening message anchors the agent in (LAB-491): the project's team, else the picked one.
    private var openingTeam: String? { currentWorkstream.flatMap { $0.team.isEmpty ? nil : $0.team } ?? (teamKey.isEmpty ? nil : teamKey) }

    /// Team first (LAB-237): a ticket or project always has one; a plain session may have none.
    private var teamPicker: some View {
        SearchPicker(prompt: "Search teams",
                     rows: model.linearTeams.map { tm in .init(id: tm.key, title: "\(tm.key) · \(tm.name)") { pickTeam(tm.key) } },
                     top: kind == .session ? [.init(id: "∅team", title: "No team") { pickTeam("") }] : []) {
            pickerLabel("Team", currentTeam.map { "\($0.key) · \($0.name)" }
                        ?? (model.linearLoading ? "Loading teams…" : kind == .session ? "No team" : "Pick a team"),
                        warn: needsTeam && teamKey.isEmpty)
        }
        .frame(maxWidth: 170, alignment: .leading)
        .accessibilityLabel("Team")
    }

    private var workstreamPicker: some View {
        SearchPicker(prompt: "Search projects",
                     rows: openWorkstreams.map { w in .init(id: w.id, title: Self.short("\(w.wsId ?? "") · \(w.title)")) { pickWorkstream(w) } },
                     top: linked ? [.init(id: "∅project", title: "No project") {
                         wsId = ""; selection.issues = []; if kind == .workstream { kind = .session }; refreshOpening() }] : [],
                     bottom: linked ? [.init(id: "+project", title: "New project…") {
                         wsId = ""; selection.issues = []; kind = .workstream; kindTouched = true; refreshOpening() }] : [],
                     activeOnly: $projectsActiveOnly,
                     openOnAppear: ProcessInfo.processInfo.environment["ONEROOF_SELFTEST_PROJECTS"] == "1") {
            pickerLabel("Project", kind == .workstream ? "New project" : currentWorkstream.map { "\($0.wsId ?? "") · \($0.title)" }
                        ?? (model.linearLoading ? "Loading projects…" : linked ? "No project" : "Pick a project"),
                        warn: !linked && currentWorkstream == nil)
        }
        .frame(maxWidth: 290, alignment: .leading)
        .accessibilityLabel("Project")
    }

    /// Menu items stay narrow (LAB-245): long titles end in "…".
    static func short(_ s: String, max: Int = 64) -> String {
        s.count <= max ? s : String(s.prefix(max - 1)).trimmingCharacters(in: .whitespaces) + "…"
    }

    /// The project's open issues, newest first.
    private var openIssues: [LinearIssue] {
        guard let w = currentWorkstream else { return [] }
        return (model.issues[w.id] ?? []).filter { !["completed", "canceled"].contains($0.stateType) }.reversed()
    }

    /// The issues the session will work on, in the order they were picked (LAB-518): the first is its ticket.
    private var pickedIssues: [LinearIssue] { selection.issues }
    private var useTicket: LinearIssue? { selection.issues.first }
    private var moreTickets: [LinearIssue] { Array(selection.issues.dropFirst()) }

    private var issueLabel: String {
        if pickedIssues.count > 1, let first = pickedIssues.first { return "\(pickedIssues.count) issues · \(first.identifier) +\(pickedIssues.count - 1)" }
        if let tk = useTicket { return "\(tk.identifier) · \(tk.shortTitle)" }
        if kind == .defect { return "New bug" }
        if kind == .ticket { return "New " + (ticketType.labelNames.first ?? "issue").lowercased() }
        return "No issue"
    }

    /// LAB-1514: which window the session joins; each window is shown with its session count, so two windows with the
    /// same name can be told apart.
    private var windowPicker: some View {
        let target = targetWindowId.flatMap { model.window($0) } ?? win
        return Menu {
            ForEach(model.windows, id: \.id) { w in
                Button("\(w.name) · \(model.items(in: w).count) sessions\(w.id == win.id ? " (this window)" : "")") { targetWindowId = w.id }
            }
        } label: { pickerLabel("Window", target.name, warn: false) }
        .menuStyle(.borderlessButton).fixedSize()
        .accessibilityLabel("Window for the new session")
        .accessibilityValue(target.name)
    }

    /// Issue: none, one or several existing ones (LAB-518: one session works on all of them), or a new one (LAB-242).
    /// A checklist in a popover, so several can be ticked without the menu closing after each.
    private var issuePicker: some View {
        Button { openIssuePicker() } label: { pickerLabel("Issue", issueLabel, warn: false) }
            .buttonStyle(.plain).frame(maxWidth: 300, alignment: .leading)
            .disabled(kind == .workstream)
            .accessibilityLabel("Issue")
            .accessibilityValue(issueLabel)
    }

    /// LAB-523: a resizable panel beside the sheet (table with resizable columns + a pane to read the issue in full).
    private func openIssuePicker() {
        let w = currentWorkstream, sel = selection
        IssuePickerPanel.show(parent: sheetWindow.window, theme: model.themes.centre, scale: win.textScale, content: IssuePickerView(
            model: model, workstreamId: w?.id ?? "",
            title: w.map { "Issues in \($0.wsId ?? $0.title)" } ?? "Pick a project first: its open issues show here",
            // The panel holds the shared object itself, never a copy of this view (whose StateObject it could not reach).
            selection: sel, toggle: { sel.toggle($0) },
            newIssue: { k in sel.newKind = k; IssuePickerPanel.close() }, clear: { sel.issues = [] },
            done: { IssuePickerPanel.close() }))
    }

    /// Tick or untick an issue; the first ticked stays the session's ticket (its name and opening lead with it). Only the
    /// shared selection changes here (the panel calls this too); the sheet reacts in `selectionChanged`.
    private func toggleIssue(_ i: LinearIssue) { selection.toggle(i) }

    private func clearIssues() { selection.issues = [] }

    /// The picked issues as the opening message names them.
    private var picked: [PickedIssue] {
        pickedIssues.map { PickedIssue(key: $0.identifier, title: $0.shortTitle, state: $0.state, url: $0.url.isEmpty ? nil : $0.url) }
    }

    /// The picks changed (here or in the panel): the sheet is a plain session on them, with a matching title hint and
    /// opening message.
    private func selectionChanged() {
        let all = selection.issues
        if !all.isEmpty { kind = .session; kindTouched = true }
        textForIssue = all.count > 1 ? "Optional: a title for these \(all.count) issues" : all.first?.shortTitle ?? ""
        refreshOpening()
    }

    private func newIssue(_ k: WorkKind) {
        selection.issues = []; kindTouched = true
        if k == .defect { kind = .defect } else { kind = .ticket; ticketType = k }
        if kind == .workstream { wsId = "" }
        refreshOpening()
    }

    private var currentWorkstream: LinearWorkstream? { model.workstreams.first { $0.id == wsId } }

    private func pickWorkstream(_ w: LinearWorkstream) {
        if wsId != w.id { selection.issues = []; IssuePickerPanel.close() }
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

    /// LAB-1931: the hosted conditions, in one place for the button and its reason; ~/Projects is a valid start.
    private var hostedBlock: String? {
        HostedSheetRules.blockedReason(hasRuntime: model.settings.hostedRuntime != nil,
                                       connection: model.settings.hostedConnections.first(where: { $0.id == hostedConnectionID }),
                                       startSupported: when == .now || when == .onDemand || when == .next, repo: repo)
    }

    /// Why the primary button is greyed out, in words.
    private var blockedReason: String? {
        guard !valid else { return nil }
        if text.trimmingCharacters(in: .whitespaces).isEmpty && useTicket == nil { return nil }
        if agent(mark).isHosted, let why = hostedBlock { return why }
        if doneWhenNeeded && doneWhen.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "Say when it's done (Settings › General › Done when required)" }
        if model.linearLoading { return "Loading teams and projects from Linear…" }
        if linked && needsTeam && teamKey.isEmpty { return kind == .workstream ? "Pick a team (top right) for the project" : "Pick a team (top right) to file the ticket in" }
        if kind == .workstream && !codeOK { return "The code looks like TEAM-TOPIC or TEAM-TOPIC-01" }
        return "Pick a project (top right) to file the ticket in"
    }

    // MARK: Images (LAB-462)

    /// The attached images as removable chips, or a hint that ⌘V and drops attach them.
    @ViewBuilder private var attachments: some View {
        if images.isEmpty {
            Text("Paste (⌘V) or drop a screenshot to attach it").ui(11.5).foregroundStyle(t.text3.color)
        } else {
            VStack(alignment: .leading, spacing: 6) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) { ForEach(images, id: \.self) { imageChip($0) } }
                }
                Text(attachNote).ui(11.5).foregroundStyle(t.text3.color)
            }
        }
    }

    private var attachNote: String {
        var parts: [String] = []
        if mark != .shell { parts.append("The opening message names them for the agent") }
        if (kind == .ticket || kind == .defect) && useTicket == nil && linked { parts.append("the new issue gets them uploaded") }
        return parts.isEmpty ? "Saved in \(TerminalMouse.pastedImagesDir.path)" : parts.joined(separator: "; ") + "."
    }

    private func imageChip(_ path: String) -> some View {
        HStack(spacing: 6) {
            Group {
                if let img = thumbs[path] { Image(nsImage: img).resizable().scaledToFill() }
                else { Image(systemName: "photo").foregroundStyle(t.text2.color) }
            }
            .frame(width: 36, height: 26).clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
            Text((path as NSString).lastPathComponent).ui(11.5, mono: true).foregroundStyle(t.text2.color)
                .lineLimit(1).truncationMode(.middle).frame(maxWidth: 160, alignment: .leading)
            Button { images.removeAll { $0 == path }; thumbs[path] = nil } label: {
                Text("✕").ui(11, .semibold).foregroundStyle(t.text2.color).frame(width: 18, height: 18).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Remove image \((path as NSString).lastPathComponent)")
        }
        .padding(.leading, 4).padding(.trailing, 6).padding(.vertical, 3)
        .background(Capsule().fill(t.card.color))
        .overlay(Capsule().strokeBorder(t.separator.color))
        .help(path)
    }

    private func attach(_ paths: [String]) {
        for p in paths where !images.contains(p) {
            images.append(p)
            if let img = NSImage(contentsOfFile: p) { thumbs[p] = img }
        }
    }

    /// ⌘V with an image on the clipboard attaches it (text pastes as usual). The sheet's text views take ⌘V first and
    /// paste only text, so this looks at the key before them, in this sheet's window only.
    private func installPaste() {
        guard pasteMonitor == nil else { return }
        let ref = sheetWindow
        pasteMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { e in
            guard e.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command,
                  e.charactersIgnoringModifiers?.lowercased() == "v",
                  let w = ref.window, e.window === w,
                  let paths = ImageAttachments.pastedImages(from: .general) else { return e }
            attach(paths)
            return nil
        }
    }

    private func removePaste() {
        if let m = pasteMonitor { NSEvent.removeMonitor(m) }
        pasteMonitor = nil
    }

    /// Dropped image files keep their path; dropped image data (from a browser, say) is saved like a paste.
    private func drop(_ providers: [NSItemProvider]) -> Bool {
        var took = false
        for p in providers {
            if p.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                took = true
                _ = p.loadObject(ofClass: URL.self) { url, _ in
                    guard let url, ImageAttachments.isImagePath(url.path) else { return }
                    DispatchQueue.main.async { attach([url.path]) }
                }
            } else if p.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
                took = true
                p.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, _ in
                    guard let data, let path = TerminalMouse.saveImage(data: data, in: TerminalMouse.pastedImagesDir) else { return }
                    DispatchQueue.main.async { attach([path]) }
                }
            }
        }
        return took
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
            Button { selection.issues = [d] } label: {
                Text("Plan a session for \(d.identifier) instead").ui(12.5, .semibold).foregroundStyle(t.accentText.color)
            }.buttonStyle(.plain)
        }
        .padding(.horizontal, 12).padding(.vertical, 9)
        .background(RoundedRectangle(cornerRadius: Radius.field, style: .continuous).fill(t.now.color.opacity(0.12)))
        .overlay(RoundedRectangle(cornerRadius: Radius.field, style: .continuous).strokeBorder(t.now.color.opacity(0.35)))
    }

    /// LAB-1826 · Gemini CLI no longer signs in with a personal Google account (Google, June 2026: "This client is no
    /// longer supported for Gemini Code Assist for individuals"); it needs a Gemini API key. Shown whenever Gemini is
    /// picked: the key lives in your shell or ~/.gemini, which One Roof does not read.
    private var geminiKeyBanner: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Gemini needs an API key").ui(12.5, .semibold).foregroundStyle(t.needsText.color)
                Text("Google no longer lets Gemini CLI sign in with a personal Google account, so \u{201C}Sign in with Google\u{201D} fails and asks again. Set GEMINI_API_KEY (a key from aistudio.google.com/apikey) in your shell before starting, or use Antigravity for Google's models.")
                    .ui(12).foregroundStyle(t.text2.color).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            Button { select(.antigravity) } label: {
                Text("Use Antigravity").ui(12.5, .semibold).foregroundStyle(t.accentText.color)
            }.buttonStyle(.plain)
        }
        .padding(.horizontal, 12).padding(.vertical, 9)
        .background(RoundedRectangle(cornerRadius: Radius.field, style: .continuous).fill(t.needsText.color.opacity(0.08)))
        .overlay(RoundedRectangle(cornerRadius: Radius.field, style: .continuous).strokeBorder(t.needsText.color.opacity(0.45)))
        .accessibilityElement(children: .combine)
    }

    // MARK: Agent cards (S09 §1.5)

    /// The card's name: Claude1 · Claude2 · Codex · Kimi …, and an added account's name (LAB-1999: "Codex2", or what
    /// the owner renamed it to).
    private func name(_ m: SeatMark) -> String {
        if m == .shell { return "Terminal" }
        if m.agent == .claude || !m.isFirst { return AgentAccounts.label(of: m.accountID, agent: m.agent) }
        return m.agent.displayName
    }

    private func agent(_ m: SeatMark) -> AgentKind { m.agent }

    private func seat(_ m: SeatMark) -> SeatUsage? {
        guard let n = DockSeats.usageName(m) else { return nil }
        return model.seats.first { $0.seat == n }
    }

    private func note(_ m: SeatMark) -> String {
        var parts: [String] = []
        if let s = seat(m) {
            if let f = s.fiveHour { parts.append("5h \(Int(f))%") } else if let w = s.sevenDay { parts.append("7d \(Int(w))%") }
            if let r = s.fiveHourResets { parts.append("resets " + r.formatted(date: .omitted, time: .shortened)) }
        } else if m == .shell {
            parts.append("plain shell, no agent")
        } else if m.mark == .gemini {
            parts.append("API key only")   // LAB-1826: needs a Gemini API key
        } else {
            parts.append([.kimi, .antigravity].contains(m.mark) ? "sessions only" : "no usage feed")
        }
        if suggestedMark == m { parts.append("suggested") }
        return parts.joined(separator: " · ")
    }

    private func agentCard(_ m: SeatMark) -> some View {
        let on = mark == m
        return Button { select(m) } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 7) {
                    AgentBadge(m, size: 22)
                    Text(name(m)).ui(13, .semibold).foregroundStyle(t.text.color).lineLimit(1)
                }
                if m == .shell || agent(m).isHosted { Text(agent(m).isHosted ? "Hosted API · Manual" : note(m)).ui(11).foregroundStyle(t.text3.color) }
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

    private func select(_ m: SeatMark) {
        mark = m
        let a = agent(m)
        let d = model.settings.defaults(for: a)
        modelName = d.model
        args = d.args
        permMode = nil
        if a.isHosted {
            hostedConnectionID = d.hostedConnectionID ?? model.settings.hostedConnections.first?.id ?? ""
            modelName = model.settings.hostedConnections.first(where: { $0.id == hostedConnectionID })?.model ?? ""
            args = ""; permMode = .manual; startInRepo = true
        }
        refreshOpening()
    }

    // MARK: Model · repo · start in

    /// Any model name works (the CLI gets --model <name>); the menu offers the known ones.
    /// LAB-1930: each saved connection lists its provider's verified open-weight coding models (its own model first).
    private var hostedMenu: some View {
        FieldMenu(title: model.settings.hostedConnections.first(where: { $0.id == hostedConnectionID }).map { "\($0.name) · \(hostedModelLabel($0, modelName))" } ?? "Set up in Settings › Seats & accounts") {
            ForEach(model.settings.hostedConnections) { c in
                Section("\(c.name) · \(c.provider.displayName)") {
                    ForEach(c.sessionModels, id: \.self) { m in
                        Button { hostedConnectionID = c.id; modelName = m } label: {
                            Text(hostedModelLabel(c, m) + (c.provider.verifiedModel(m).map { "  ·  \($0.priceLabel)" } ?? ""))
                        }
                    }
                }
            }
        }
    }

    private func hostedModelLabel(_ c: HostedConnection, _ id: String) -> String {
        c.provider.verifiedModel(id)?.displayName ?? id
    }

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

    private func box(_ binding: Binding<String>, minHeight: CGFloat, placeholder: String? = nil) -> some View {
        TextEditor(text: binding)
            .ui(13).scrollContentBackground(.hidden)
            .padding(8).frame(minHeight: minHeight, maxHeight: 110)
            .background(RoundedRectangle(cornerRadius: Radius.field, style: .continuous).fill(t.card.color))
            .foregroundStyle(t.text.color)
            .overlay(alignment: .topLeading) {
                if let placeholder, binding.wrappedValue.isEmpty {
                    Text(placeholder).ui(13).foregroundStyle(t.text3.color).padding(.horizontal, 13).padding(.vertical, 8).allowsHitTesting(false)
                }
            }
    }

    // MARK: Advanced

    private var advancedFields: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                labelled("Agent arguments") {
                    TextField("e.g. --permission-mode plan", text: $args).textFieldStyle(.plain).ui(12.5, mono: true).disabled(agent(mark).isHosted)
                        .padding(.horizontal, 8).frame(height: 28)
                        .background(RoundedRectangle(cornerRadius: Radius.field).fill(t.card.color))
                }
                labelled("Permissions") {
                    let a = agent(mark)
                    let current = permMode ?? model.settings.permissionMode(for: a)
                    FieldMenu(title: PermissionMode.hasExplicit(Session.parseArgs(args), agent: a) ? "From arguments" : current.label(for: a)) {
                        ForEach(PermissionMode.allCases) { m in
                            Button(m.label(for: a) + (m == model.settings.permissionMode(for: a) ? " (default)" : "")) { permMode = m }
                        }
                    }
                    .help(current.meaning(for: a) + " The default is set in Settings › Permissions; arguments that set a mode win.")
                    .accessibilityLabel("Permission mode: \(current.label(for: a))")
                    .disabled(!a.isAgent || a.isHosted)
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
            // A loop (LAB-254): start now, then send the message again every N minutes when the agent waits.
            Button { when = .every } label: { segment("Every " + Schedule.every(everyMinutes), on: when == .every, inset: 9) }
                .buttonStyle(.plain)
                .help("Start now, then send the message again every \(Schedule.every(everyMinutes)), when the agent is waiting (never while it works)")
            if when == .every {
                Menu {
                    ForEach(Schedule.everyChoices, id: \.self) { m in Button("Every " + Schedule.every(m)) { everyMinutes = m } }
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
        case .every: return "Launch, repeat every \(Schedule.every(everyMinutes)) ⌘↩"
        case .onDemand: return "Save on demand ⌘↩"
        }
    }

    /// Settings › General › Done when required (v2 only; off keeps 0.5's optional Done when).
    private var doneWhenNeeded: Bool { model.settings.ui2 && model.settings.doneWhenRequired }

    private var valid: Bool {
        if agent(mark).isHosted && hostedBlock != nil { return false }
        let has = !text.trimmingCharacters(in: .whitespaces).isEmpty || useTicket != nil
        if doneWhenNeeded && doneWhen.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return false }   // NEW-30
        if (kind == .ticket || kind == .defect) && useTicket == nil { return has && (linked ? !teamKey.isEmpty : currentWorkstream != nil) }
        if kind == .workstream && linked { return has && !teamKey.isEmpty && codeOK }
        return has
    }

    // MARK: Behaviour

    /// Self-test only: the agent the next sheet opens with (`newsession <agent>`, LAB-1826).
    static var selfTestMark: SeatMark?

    private func appear() {
        DispatchQueue.main.async { textFocused = true }
        if SelfTest.isActive, let m = Self.selfTestMark { Self.selfTestMark = nil; DispatchQueue.main.async { select(m) } }
        roles = Role.load(agenticEngineering: model.settings.agenticEngineering.path)
        // LAB-1255: the project picker shows Linear's current list (fetched again when older than 10 s).
        model.loadWorkstreams(force: model.linearTeams.isEmpty, maxAge: 10)
        defaultWorkstream()
        let acc = model.settings.defaults(for: .claude).account
        let preferred = SeatMark(agent: .claude, account: acc)
        select(marks.contains(preferred) ? preferred : .claude1)
        let env = ProcessInfo.processInfo.environment
        if let k = env["ONEROOF_SELFTEST_KIND"].flatMap(Kind.init(rawValue:)) { kind = k; kindTouched = true }
        if let k = env["ONEROOF_SELFTEST_TEAM"] { teamKey = k }
        if let w = env["ONEROOF_SELFTEST_WHEN"] {
            when = ["now": When.now, "next": .next, "tonight": .tonight, "every": .every, "ondemand": .onDemand][w] ?? .now
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
            if let w = currentWorkstream { model.loadIssues(w, maxAge: 120) }
            model.suggestAgent(for: v) { r, _ in
                suggestion = r
                let m = SeatMark(agent: r.agent, account: r.account)
                withAnimation(Motion.base) { suggestedMark = m }
            }
        }
        debounce = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
    }

    /// Did the owner (or a role) write the opening message, rather than the sheet?
    private var openingTouched: Bool { openingSetByHand || opening != generatedOpening }

    /// LAB-638: what the opening message is built from — always what is picked now.
    private func openingFocus(issues: [PickedIssue]? = nil, w: LinearWorkstream? = nil) -> OpeningFocus {
        let ws = w ?? currentWorkstream
        let team = ws.flatMap { $0.team.isEmpty ? nil : $0.team } ?? openingTeam
        let creating = (kind == .ticket || kind == .defect) && useTicket == nil && issues == nil
        return OpeningFocus(team: team, teamName: model.linearTeams.first { $0.key == team }?.name,
                            project: ws?.wsId, projectTitle: ws?.title, issues: issues ?? picked,
                            newIssueTitle: creating ? text.trimmingCharacters(in: .whitespaces) : nil,
                            ask: creating ? "" : text, doneWhen: doneWhen)
    }

    /// The opening message (S09 §1.7): rebuilt from the picks until the owner edits it; an edited message keeps the
    /// owner's words and only its focus and issue blocks follow the picks (LAB-528).
    private func refreshOpening() {
        let f = openingFocus()
        if openingTouched { opening = Intake.syncOpening(opening, focus: f); return }
        let g = Intake.sessionOpening(f)
        generatedOpening = g
        opening = g
    }

    private func applyRole(_ r: Role) {
        roleId = r.id
        mark = SeatMark(agent: r.agent, account: model.settings.defaults(for: r.agent).account)
        if let m = r.model { modelName = m }
        if text.isEmpty { text = r.title }
        opening = r.opening(repo: Workspace.repoLabel(for: repo), workstream: currentWorkstream?.wsId)
        openingSetByHand = true
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
            // LAB-248: a new issue's real key replaces the placeholder (the template is rebuilt unless edited).
            let several = ticket != nil && ticket?.id == useTicket?.id && !moreTickets.isEmpty
            if several {
                opening = openingTouched ? Intake.syncOpening(opening, focus: openingFocus(w: w))
                    : Intake.sessionOpening(openingFocus(w: w))
            } else if let tk = ticket {
                let one = [PickedIssue(key: tk.identifier, title: tk.shortTitle, state: tk.state, url: tk.url.isEmpty ? nil : tk.url)]
                if !openingTouched {
                    opening = Intake.sessionOpening(openingFocus(issues: one, w: w))
                } else if opening.contains(Intake.newIssueKey) {
                    opening = opening.replacingOccurrences(of: Intake.newIssueKey, with: tk.identifier)
                }
            }
            let sessionName = several ? Intake.sessionName(keys: pickedIssues.map(\.identifier), title: typed)
                : ticket.map { Intake.sessionName(key: $0.identifier, title: title) } ?? title
            var s = Session(name: sessionName, agent: a,
                            account: a == .claude || mark.number > 1 ? mark.accountID : (AccountResolver.choices(for: a).first),
                            repoPath: repo,
                            workstream: w?.wsId ?? (wsText.trimmingCharacters(in: .whitespaces).isEmpty ? Workspace.workstream(in: title) : wsText.trimmingCharacters(in: .whitespaces).uppercased()),
                            objective: doneWhen, openingMessage: a.isAgent ? ImageAttachments.openingMessage(opening, images: images) : "",
                            lifecycle: forcePlanned || when == .onDemand ? .planned : .next,
                            startInRepo: startInRepo,
                            agentArgs: a.isAgent ? (resumeId.isEmpty ? [] : ["--resume", resumeId]) + Session.parseArgs(args) : [],
                            model: modelName.trimmingCharacters(in: .whitespaces).isEmpty ? nil : modelName,
                            ticket: ticket?.identifier, ticketId: ticket?.id,
                            ticketTeam: ticket == nil ? w?.team : (w?.team ?? (teamKey.isEmpty ? nil : teamKey)))
            if a.isHosted { s.hostedConnectionID = hostedConnectionID; s.model = modelName; s.startInRepo = true; s.agentArgs = []; s.permissionMode = .manual }
            else if a.isAgent {   // LAB-1600; LAB-1935: the owner's own flags for that mode come along
                let m = permMode ?? model.settings.permissionMode(for: a)
                s.permissionMode = m
                s.permissionFlags = model.settings.permissionFlags(for: a, mode: m)
            }
            if several { s.moreTickets = moreTickets.map { SessionIssue(key: $0.identifier, id: $0.id, team: s.ticketTeam) } }
            if let r = roles.first(where: { $0.id == roleId }) { s.tags = [Sticker.resolve(r.kind).builtIn ? r.kind : "review"] }
            model.createPlanned(s, launchNow: launch && !forcePlanned, in: targetWindowId.flatMap { model.window($0) } ?? win)   // LAB-1514
            if when == .tonight && !forcePlanned, let i = model.item(s.id) { model.schedule(i, hour: 2, minute: 0, nightly: nightly) }
            if when == .every && !forcePlanned, let i = model.item(s.id) { model.repeatEvery(i, minutes: everyMinutes) }
            close()
        }
        if let tk = useTicket { makeSession(ticket: tk, w: currentWorkstream); return }
        if (kind == .ticket || kind == .defect), currentWorkstream != nil || (linked && !teamKey.isEmpty) {
            busy = true
            let w = currentWorkstream
            let type: WorkKind = kind == .defect ? .defect : ticketType
            model.createTicket(kind: type, title: title, details: doneWhen, in: w, team: teamKey, milestone: nil, planSession: false,
                               images: images) { r in
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

/// The sheet's own window, so its ⌘V monitor ignores keys meant for other windows (LAB-462).
final class WindowRef: ObservableObject {
    weak var window: NSWindow?
}

private struct WindowReader: NSViewRepresentable {
    let ref: WindowRef
    func makeNSView(context: Context) -> NSView { Reader(ref: ref) }
    func updateNSView(_ v: NSView, context: Context) {}

    final class Reader: NSView {
        let ref: WindowRef
        init(ref: WindowRef) { self.ref = ref; super.init(frame: .zero) }
        required init?(coder: NSCoder) { fatalError("not supported") }
        override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); ref.window = window }
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }
}
