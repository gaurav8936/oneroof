import AppKit
import SwiftUI
import OneRoofCore

/// Settings (⌘,): General · Appearance · Agents · Foundations · Shortcuts.
struct SettingsView: View {
    /// LAB-1533: Claude's conversation limit as its settings file says now (read when General opens), and a lower choice
    /// waiting for confirmation (lowering lets Claude delete older conversations).
    @State private var retention: Int? = ConversationRetention.current()
    @State private var pendingRetention: Int??
    @State private var retentionError: String?
    @ObservedObject var model: AppModel
    @State var tab = Int(ProcessInfo.processInfo.environment["ONEROOF_SELFTEST_SETTINGS_TAB"] ?? "") ?? 0
    /// What macOS says about One Roof's notifications (LAB-197).
    @State private var noteStatus = ""
    @State private var notePermission: NotePermissionStatus = .notAsked
    /// v2 Settings page (B1.x): one of the nine panes, drawn without the tab bar; nil = the 0.5 window.
    var v2Pane: Int? = nil

    var body: some View {
        if let p = v2Pane { v2Content(p) } else { tabs05 }
    }

    /// The panes (B1.x, LAB-1084 order): every 0.5 setting is in one of them. Permissions (LAB-1600) is added last so
    /// the self-test pane numbers stay the same.
    static let v2Panes = ["General", "Appearance", "Seats & accounts", "Notifications", "On-device model", "Foundations", "Learn", "Shortcuts", "Updates", "Permissions"]

    @ViewBuilder private func v2Content(_ p: Int) -> some View {
        switch p {
        case 0: v2General
        case 1: appearance
        case 2: VStack(spacing: 0) { v2Routing; agents }
        case 3: Form { notifications }.formStyle(.grouped)
        case 4: v2Model
        case 5: v2Foundations
        case 6: Form { learnClassicRow; autoAdvanceRow; aeRow; learnFoldersRow }.formStyle(.grouped)
        case 7: ShortcutsSettings(model: model)
        case 9: permissions
        default: v2Updates
        }
    }

    private var v2General: some View {
        Form {
            Section("Start") {
                LabeledContent("Start folder") {
                    Text(model.settings.projectsFolder.replacingOccurrences(of: NSHomeDirectory(), with: "~")).textSelection(.enabled)
                }
                Text("Agents start here. Change it in Settings › Foundations. A session can start in its repo instead (New session › Start in).")
                    .font(.caption).foregroundStyle(.secondary)
                Toggle("Check the foundations every time One Roof starts", isOn: $model.settings.startupCheck)
                Text("Checks roofd (the session manager), agent logins, skill links, hooks, the memory pin and, when a shared folder is set, its doors and MCP list. Red items ask before an agent launches.")
                    .font(.caption).foregroundStyle(.secondary)
                Toggle("Show sessions that need you on the Dock icon", isOn: $model.settings.dockBadge)
            // LAB-1524
            Picker("When an agent ends", selection: $model.settings.closeFinishedAfterMinutes) {
                ForEach(FinishedShellPolicy.choices, id: \.minutes) { c in Text(c.label).tag(c.minutes) }
            }
            Text("The agent's shell stays so you can read its last screen. One Roof closes it after this long untouched — never while something runs in it, never a pinned session. The row stays, and Resume works from All sessions (⌃⌘O).")
                .font(.caption).foregroundStyle(.secondary)
            // LAB-1535
            Picker("Close sessions untouched for", selection: $model.settings.closeIdleSessionsAfterHours) {
                ForEach(IdleSessionPolicy.choices, id: \.hours) { c in Text(c.label).tag(c.hours) }
            }
            Text(verbatim: "Housekeeping, so you don't have to: a session nobody touched this long is closed (agent, shell and roofd's holder) and stays in All sessions, where Resume brings its conversation back. Never one that is working or waiting for you, a pinned session, a loop, or one that can't be resumed. Closing a window only hides it.")
                .font(.caption).foregroundStyle(.secondary)
            // LAB-1533
            Picker("Keep agent conversations on this Mac", selection: Binding(get: { retention }, set: { new in
                if ConversationRetention.deletes(from: retention, to: new) { pendingRetention = .some(new) } else { setRetention(new) }
            })) {
                ForEach(ConversationRetention.choices, id: \.label) { c in Text(c.label).tag(c.days) }
            }
            Text(verbatim: "Resume needs an agent's conversation file. By default Claude Code deletes its conversations on this Mac (~/.claude/projects) after 30 days, so older sessions can no longer be resumed. One Roof sets this for every Claude account. Codex (~/.codex/sessions) and Kimi (~/.kimi-code/sessions) keep theirs until you delete them; there is no limit to set. Lowering the limit lets Claude delete older conversations the next time it starts.")
                .font(.caption).foregroundStyle(.secondary)
            if let retentionError { Text(retentionError).font(.caption).foregroundStyle(.red) }
                LabeledContent("Sessions") { Text(model.runtimeState).foregroundStyle(model.runtimeOK ? .green : .red) }
            }
            Section("New sessions") {
                Toggle("Done when required", isOn: $model.settings.doneWhenRequired)
                Text("When on, New session can't launch without a Done when. Off keeps it optional.")
                    .font(.caption).foregroundStyle(.secondary)
                Toggle("Step review: Claude reads each finished step", isOn: $model.settings.stepReview)
                Text("Shown in the Plan panel (also switched there). Each step it reviews is one Claude (\(StepExplainer.model)) call on your Claude account, so it is off by default.")
                    .font(.caption).foregroundStyle(.secondary)
                Toggle("Always show the composer under agents", isOn: $model.settings.alwaysShowComposer)
                Text("Off: you type into the agent's own prompt in the terminal; Compose in the pane header opens the composer (/ skill, @ file, ⌃↩ run as shell, ⌘. interrupt) when you want it, and it shows by itself in the Table view.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("In the background") {
                Toggle("Allow scheduled runs (Tonight, Nightly)", isOn: $model.settings.scheduledRuns)
                Text("roofd starts Tonight, Nightly and repeating sessions on time, with One Roof open or closed. Off, they run only while One Roof is open. Nothing is merged or committed on its own.")
                    .font(.caption).foregroundStyle(.secondary)
                Toggle("Menu-bar extra", isOn: $model.settings.menuBarExtra)
            }
            Section("Layout · 1.x") {
                LabeledContent("Classic layout") {
                    Button("Use the classic window…") { Self.switchToClassic(model) }
                }
                Text("The 0.5.2.9 window, as a fallback while the new one settles. One Roof quits to switch; open it again and it starts in the classic window.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    /// Classic layout (NEW-28): ui2 is read when a window is built, so switching needs a fresh start; ask, save, quit.
    static func switchToClassic(_ model: AppModel) {
        let a = NSAlert()
        a.messageText = "Switch to the classic window?"
        a.informativeText = "One Roof quits now. Open it again and it starts in the 0.5.2.9 window. Your sessions keep running in roofd."
        a.addButton(withTitle: "Quit and Switch"); a.addButton(withTitle: "Cancel")
        guard a.runModal() == .alertFirstButtonReturn else { return }
        model.settings.ui2 = false
        model.settings.ui2Chosen = true
        Prefs.defaults.synchronize()   // the settings didSet already wrote it
        NSApp.terminate(nil)
    }

    /// From the classic window to the One Roof 1 window: the layout is chosen when a window is built, so quit.
    static func switchToNew(_ model: AppModel) {
        let a = NSAlert()
        a.messageText = "Switch to the new window?"
        a.informativeText = "One Roof quits now. Open it again and it starts in the One Roof 1 window. Settings › General › Classic layout brings this one back. Your sessions keep running in roofd."
        a.addButton(withTitle: "Quit and Switch"); a.addButton(withTitle: "Cancel")
        guard a.runModal() == .alertFirstButtonReturn else { return }
        model.settings.ui2 = true
        model.settings.ui2Chosen = true
        Prefs.defaults.synchronize()
        NSApp.terminate(nil)
    }

    /// Seats & accounts › Routing (NEW-6): the rules the router and the objective runner already follow, made visible
    /// and adjustable. Steps rotate to another seat (after a handoff) when theirs passes the hand-off point.
    private var v2Routing: some View {
        let file = RoutingPolicy.load(agenticEngineering: model.settings.agenticEngineering.path)
        return Form {
            Section("Routing") {
                Stepper(value: Binding(get: { model.settings.handOffAt > 0 ? model.settings.handOffAt : Int(file.skipFiveHour) },
                                       set: { model.settings.handOffAt = $0 }), in: 50...100, step: 5) {
                    Text("Hand off before a limit: at \(model.settings.handOffAt > 0 ? model.settings.handOffAt : Int(file.skipFiveHour))% of a seat's 5-hour window")
                }
                Text("A running objective step past this point asks its agent for a handoff between turns, then restarts on another vendor's agent (up to twice per step). New work skips seats past this point (and past \(Int(file.skipSevenDay))% of the 7-day window).")
                    .font(.caption).foregroundStyle(.secondary)
                if model.settings.handOffAt > 0 { Button("Use the routing file's value (\(Int(file.skipFiveHour))%)") { model.settings.handOffAt = 0 } }
                Toggle("Prefer a different model family for review", isOn: $model.settings.reviewOtherFamily)
                Text("A review step goes to another vendor's agent than the one that wrote the code (e.g. Codex reviews Claude's work).")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(height: 250)
    }

    private var v2Model: some View {
        Form {
            Toggle("Use the on-device model for captions and reasons", isOn: $model.settings.captionsModel)
            Text("When llama-server runs on 127.0.0.1:\(LocalModel.port), One Roof asks it for one-line captions. Off, or when it is not running, captions come from the terminal (tool calls, test counts, prompts). Nothing leaves this Mac.")
                .font(.caption).foregroundStyle(.secondary)
            modelRow
        }
        .formStyle(.grouped)
    }

    private var v2Foundations: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("The startup check, skills, hooks and memory live in the Foundations window.").font(.callout).foregroundStyle(.secondary)
                Spacer()
                Button("Open Foundations ⇧⌘F") { NSApp.sendAction(#selector(AppDelegate.showFoundations(_:)), to: nil, from: nil) }
            }
            .padding(.horizontal, 20).padding(.top, 14)
            foundations
        }
    }

    private var v2Updates: some View {
        let v = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let b = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        return Form {
            Section("This Mac") {
                LabeledContent("One Roof") { Text("\(v) (build \(b))").textSelection(.enabled) }
                LabeledContent("roofd") { Text(model.runtimeState).foregroundStyle(model.runtimeOK ? .primary : Color.red) }
                HStack {
                    Button("Release notes") { NSApp.sendAction(#selector(AppDelegate.openReleaseNotes(_:)), to: nil, from: nil) }
                    Button("Check now") { NSWorkspace.shared.open(URL(string: "https://github.com/gaurav8936/oneroof/releases/latest")!) }
                }
            }
            Text("One Roof has no updater yet: new versions install from the download page (Check now opens it). The beta / release channel arrives with the updater.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
    }

    private var tabs05: some View {
        TabView(selection: $tab) {
            general.tabItem { Label("General", systemImage: "gearshape") }.tag(0)
            appearance.tabItem { Label("Appearance", systemImage: "paintpalette") }.tag(1)
            agents.tabItem { Label("Agents", systemImage: "person.3") }.tag(2)
            captions.tabItem { Label("Captions", systemImage: "text.bubble") }.tag(5)
            foundations.tabItem { Label("Foundations", systemImage: "building.columns") }.tag(3)
            ShortcutsSettings(model: model).tabItem { Label("Shortcuts", systemImage: "keyboard") }.tag(4)
            permissions.tabItem { Label("Permissions", systemImage: "lock.shield") }.tag(6)
        }
        .padding(20)
        .frame(width: 660, height: 500)
    }

    private func setRetention(_ days: Int?) {
        do { try ConversationRetention.apply(days); retention = days; retentionError = nil }
        catch { retentionError = "Could not update Claude's settings: \(error.localizedDescription)" }
    }

    private var general: some View {
        Form {
            LabeledContent("Start folder") {
                Text(model.settings.projectsFolder.replacingOccurrences(of: NSHomeDirectory(), with: "~")).textSelection(.enabled)
            }
            Text("Agents start in this folder (change it in Foundations). A session can start in its repo instead (Plan a session).")
                .font(.caption).foregroundStyle(.secondary)
            Toggle("Show sessions that need you on the Dock icon", isOn: $model.settings.dockBadge)
            notifications
            Toggle("Check the foundations every time One Roof starts", isOn: $model.settings.startupCheck)
            Text("Checks roofd (the session manager), agent logins, skill links, hooks, the memory pin and, when a shared folder is set, its doors and MCP list. Red items ask before an agent launches.")
                .font(.caption).foregroundStyle(.secondary)
            LabeledContent("Sessions") {
                Text(model.runtimeState).foregroundStyle(model.runtimeOK ? .green : .red)
            }
            // The way back from Classic layout (1.x): the new window, after a restart.
            LabeledContent("Window") { Button("Use the new window…") { Self.switchToNew(model) } }
        }
        .formStyle(.grouped)
        .alert("Keep conversations for less time?", isPresented: Binding(get: { pendingRetention != nil }, set: { if !$0 { pendingRetention = nil } }),
               presenting: pendingRetention) { new in
            Button("Keep \(ConversationRetention.label(new).lowercased())", role: .destructive) { setRetention(new); pendingRetention = nil }
            Button("Cancel", role: .cancel) { pendingRetention = nil }
        } message: { new in
            Text("The next time Claude starts, it deletes conversations older than \(ConversationRetention.effective(new)) days from this Mac. Those sessions can no longer be resumed, and raising the limit again does not bring them back.")
        }
    }

    /// Desktop notifications (LAB-197): what is worth a banner, and whether macOS lets One Roof show them.
    @ViewBuilder private var notifications: some View {
        Toggle("Notify me when an agent needs me", isOn: $model.settings.notifyNeedsYou)
        Toggle("Notify me when an agent finishes its turn", isOn: $model.settings.notifyDone)
        Toggle("Notify me when a long command finishes in a terminal", isOn: $model.settings.notifyLongCommands)
        Stepper(value: $model.settings.longCommandSeconds, in: 5...3600, step: 5) {
            Text("Long means at least \(model.settings.longCommandSeconds) seconds")
        }
        .disabled(!model.settings.notifyLongCommands)
        Text("No banner for the session you are looking at. Click a banner to open its session. Long commands need a shell that marks its commands (OSC 133); programs' own notifications (OSC 9 and 777) come through with the same switch.")
            .font(.caption).foregroundStyle(.secondary)
        LabeledContent("macOS") {
            HStack {
                Text(noteStatus.isEmpty ? "…" : NotePermission.settings(notePermission).text)
                    .font(.caption).foregroundStyle(.secondary)
                // LAB-718: no button once allowed; when turned off, macOS won't ask again, so open System Settings.
                switch NotePermission.settings(notePermission).button {
                case .ask:
                    Button("Allow notifications…") {
                        Notifier.shared.requestAuthorization { _ in Notifier.shared.permission { notePermission = $0; noteStatus = "set" } }
                    }
                case .openSystemSettings:
                    Button("Open Notification Settings…") {
                        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension")!)
                    }
                case .none:
                    EmptyView()
                }
            }
        }
        .onAppear { Notifier.shared.permission { notePermission = $0; noteStatus = "set" } }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            Notifier.shared.permission { notePermission = $0; noteStatus = "set" }
        }
    }

    /// Appearance: a grid — Sessions · Files · Terminal · Plan · Centre views × Daylight · Graphite · Midnight and the
    /// pastel light themes Mint · Sky · Lavender · Peach (LAB-601).
    @ViewBuilder private var appearance: some View {
        if model.settings.ui2 {
            V2LooksPicker(model: model) { panelGrid }   // v2 (A10.3): six looks first; this grid under Customize
        } else {
            appearance05
        }
    }

    private var panelGrid: some View {
        Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 10) {
            GridRow {
                Text("")
                ForEach(ThemeName.panelChoices) { Text($0.label).font(.system(size: 12, weight: .semibold)) }
            }
            themeRow("Sessions", \.sidebar)
            themeRow("Files", \.files)
            themeRow("Terminal", \.terminal)
            themeRow("Plan", \.plan)
            themeRow("Centre views", \.centre)
        }
    }

    private var appearance05: some View {
        Form {
            Section {
                Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 10) {
                    GridRow {
                        Text("")
                        ForEach(ThemeName.panelChoices) { Text($0.label).font(.system(size: 12, weight: .semibold)) }
                    }
                    themeRow("Sessions", \.sidebar)
                    themeRow("Files", \.files)
                    themeRow("Terminal", \.terminal)
                    themeRow("Plan", \.plan)
                    themeRow("Centre views", \.centre)
                }
                Text("Each panel picks its own theme. Blueprint stays available for the terminal in View › Terminal Theme.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Toggle("Follow macOS light and dark", isOn: $model.settings.followSystemAppearance)
            Text("In Dark Mode, Daylight and pastel panels turn Midnight; your choices above stay as they are.").font(.caption).foregroundStyle(.secondary)
            LabeledContent("Text size") {
                HStack {
                    Slider(value: Binding(get: { model.active.textScale }, set: { model.active.setTextScale($0) }), in: 0.85...1.3, step: 0.05)
                        .frame(width: 200)
                    Text("\(Int(model.active.textScale * 100))%").monospacedDigit()
                }
            }
            Toggle("Fill rows with their colour", isOn: $model.settings.tintRows)
            Text("On by default, as in v0.1: a row picks its colour from Stickers and Colour… (right-click a row).").font(.caption).foregroundStyle(.secondary)
            Picker("Sticker style", selection: $model.settings.stickerStyle) {
                Text("Bold").tag("bold")
                Text("Soft").tag("soft")
            }
            .pickerStyle(.segmented)
        }
        .formStyle(.grouped)
    }

    @ViewBuilder private func themeRow(_ title: String, _ key: WritableKeyPath<PanelThemes, ThemeName>) -> some View {
        GridRow {
            Text(title)
            ForEach(ThemeName.panelChoices) { th in
                let on = model.chosenThemes[keyPath: key] == th
                Button { model.chosenThemes[keyPath: key] = th } label: {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(th.tokens.window.color)
                        .overlay(RoundedRectangle(cornerRadius: 6).fill(th.tokens.sidebar.color).frame(width: 18).frame(maxWidth: .infinity, alignment: .leading))
                        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(on ? th.tokens.accent.color : Color.secondary.opacity(0.3), lineWidth: on ? 2.5 : 1))
                        .frame(width: 52, height: 30)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(title) \(th.label)\(on ? ", selected" : "")")
            }
        }
    }

    /// Captions: the on-device model is optional; heuristics always run first.
    private var captions: some View {
        Form {
            Toggle("Use the on-device model for captions and reasons", isOn: $model.settings.captionsModel)
            Text("When llama-server runs on 127.0.0.1:\(LocalModel.port), One Roof asks it for one-line captions. Off, or when it is not running, captions come from the terminal (tool calls, test counts, prompts). Nothing leaves this Mac.")
                .font(.caption).foregroundStyle(.secondary)
            Toggle("Step review: Claude reads each finished step", isOn: $model.settings.stepReview)
            Text("Shown in the Plan panel (also switched there). Each step it reviews is one Claude (\(StepExplainer.model)) call on your Claude account, so it is off by default.")
                .font(.caption).foregroundStyle(.secondary)
            Toggle("Allow scheduled runs (Tonight, Nightly)", isOn: $model.settings.scheduledRuns)
            Text("roofd starts Tonight, Nightly and repeating sessions on time, with One Roof open or closed. Off, they run only while One Roof is open. Nothing is merged or committed on its own.")
                .font(.caption).foregroundStyle(.secondary)
            Toggle("Menu-bar extra", isOn: $model.settings.menuBarExtra)
        }
        .formStyle(.grouped)
    }

    private var agents: some View {
        Form {
            Text("Defaults used when you plan a session. You can change them for each session.")
                .font(.caption).foregroundStyle(.secondary)
            // LAB-1998: the bottom bar shows every agent set up on this Mac; switch one off to take it out.
            Section("Bottom bar") {
                let shown = model.dockFacts.map { DockSeats.setUp($0, usageSeats: Set(model.seats.map(\.seat))) } ?? model.dockMarks
                ForEach(shown, id: \.self) { m in
                    Toggle(isOn: Binding(
                        get: { !model.settings.dockHidden.contains(m.rawValue) },
                        set: { on in
                            model.settings.dockHidden.removeAll { $0 == m.rawValue }
                            if !on { model.settings.dockHidden.append(m.rawValue) }
                        })) {
                        HStack(spacing: 8) {
                            AgentBadge(m, size: 18)
                            Text(DockSeats.agent(m).displayName + (m == .claude2 ? " (second account)" : ""))
                        }
                    }
                    .accessibilityLabel("Show \(m.mono) in the bottom bar")
                }
                Text("Agents appear here once they are set up: installed, signed in, or (OpenCode, Goose) with a hosted connection.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            HostedSettingsView(model: model)
            ForEach(AgentKind.allCases.filter { $0.isAgent && !$0.isHosted }) { agent in
                Section(agent.displayName) {
                    if !AccountResolver.choices(for: agent).isEmpty {
                        Picker("Account", selection: binding(agent, \.account)) {
                            ForEach(AccountResolver.choices(for: agent), id: \.self) { Text($0).tag(Optional($0)) }
                        }
                    } else if agent == .codex {
                        LabeledContent("Account") { Text("One seat (~/.codex)").foregroundStyle(.secondary) }
                    }
                    ModelField(agent: agent, model: binding(agent, \.model))
                    // LAB-1934: a bordered field you can see is editable (the grouped form drew it as a grey label).
                    LabeledContent("Extra arguments") {
                        TextField("", text: binding(agent, \.args), prompt: Text("optional, e.g. --verbose"))
                            .labelsHidden().textFieldStyle(.roundedBorder).multilineTextAlignment(.leading)
                            .font(.system(size: 12, design: .monospaced)).frame(minWidth: 240)
                            .accessibilityLabel("\(agent.displayName) extra arguments")
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    /// LAB-1600: one permission mode per agent, used by every new session (Auto unless chosen otherwise). The New
    /// session sheet can pick another for one session; arguments that set a mode win. Loops keep their own setting.
    private var permissions: some View {
        Form {
            Text("How much each agent may do without asking. Auto lets routine work run; Full never asks. Antigravity starts in Full, the others in Auto. Every new session starts in its agent's mode; the New session sheet can change it for one session, and arguments that set a mode win. Type your own flags to replace a mode's flags; Reset puts the standard ones back. Loops and objective steps keep their own setting.")
                .font(.caption).foregroundStyle(.secondary)
            ForEach(AgentKind.allCases.filter(\.isAgent)) { agent in
                Section(agent.displayName) {
                    Picker("Mode", selection: Binding(
                        get: { model.settings.permissionMode(for: agent) },
                        set: { model.settings.permissionModes[agent.rawValue] = $0 })) {
                        ForEach(PermissionMode.allCases) { m in Text(m.label(for: agent)).tag(m) }
                    }
                    .pickerStyle(.segmented)
                    .disabled(agent.isHosted)
                    .accessibilityLabel("\(agent.displayName) permission mode")
                    let m = model.settings.permissionMode(for: agent)
                    // LAB-1935: the flags are the owner's to change; empty = the mode's standard flags (shown as the hint).
                    let key = "\(agent.rawValue).\(m.rawValue)"
                    LabeledContent("Flags") {
                        HStack(spacing: 6) {
                            TextField("", text: Binding(
                                get: { model.settings.permissionFlags[key] ?? "" },
                                set: { model.settings.permissionFlags[key] = $0.trimmingCharacters(in: .whitespaces).isEmpty ? nil : $0 }),
                                      prompt: Text(m.args(for: agent).isEmpty ? "none (the CLI asks)" : m.args(for: agent).joined(separator: " ")))
                                .labelsHidden().textFieldStyle(.roundedBorder).multilineTextAlignment(.leading)
                                .font(.system(size: 11.5, design: .monospaced)).frame(minWidth: 260)
                                .disabled(agent.isHosted)
                                .accessibilityLabel("\(agent.displayName) \(m.label(for: agent)) flags")
                            Button("Reset") { model.settings.permissionFlags[key] = nil }
                                .disabled(model.settings.permissionFlags[key] == nil)
                        }
                    }
                    Text(m.meaning(for: agent)).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
    }

    private func binding<T>(_ agent: AgentKind, _ key: WritableKeyPath<AgentDefaults, T>) -> Binding<T> {
        Binding(
            get: { model.settings.defaults(for: agent)[keyPath: key] },
            set: { v in
                var d = model.settings.defaults(for: agent)
                d[keyPath: key] = v
                model.settings.agents[agent.rawValue] = d
            })
    }

    private var foundations: some View {
        Form {
            Text("One Roof only reads these folders; it never copies skills, hooks or routing rules into itself. Empty fields use the defaults shown.")
                .font(.caption).foregroundStyle(.secondary)
            folderSetting("Projects folder", $model.settings.projectsPath, placeholder: Workspace.defaultProjectsRoot(),
                          inUse: model.settings.projectsFolder, env: "ONEROOF_PROJECTS")
            folderSetting("Shared rules and docs", $model.settings.commonPath,
                          placeholder: Workspace.resolveShared(setting: "", projects: model.settings.projectsFolder),
                          inUse: model.settings.sharedFolder, env: "ONEROOF_SHARED", optional: true)
            aeRow
            learnFoldersRow
            modelRow
            pathRow("Claude memory", .constant(NSHomeDirectory() + "/.claude/projects/" + Workspace.mangle(model.settings.projectsFolder) + "/memory"))
        }
        .formStyle(.grouped)
    }

    /// A folder setting: free text ("" = default), Choose…, Show, and the folder actually in use.
    private func folderSetting(_ title: String, _ value: Binding<String>, placeholder: String, inUse: String, env: String,
                               optional: Bool = false) -> some View {
        let exists = Workspace.folderExists(inUse)
        let fromEnv = !(ProcessInfo.processInfo.environment[env] ?? "").isEmpty
        return LabeledContent(title) {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    TextField("", text: value, prompt: Text(placeholder.replacingOccurrences(of: NSHomeDirectory(), with: "~"))).labelsHidden()
                    Button("Choose…") {
                        if let p = Self.chooseFolder("Choose the \(title.lowercased())") { value.wrappedValue = p }
                    }
                    Button("Show") { NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: inUse) }.disabled(!exists)
                }
                HStack(spacing: 4) {
                    if !exists { Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange) }
                    Text("In use: \(fromEnv ? env + " · " : "")\(inUse.replacingOccurrences(of: NSHomeDirectory(), with: "~"))"
                         + (exists ? "" : optional ? " (not found: features that use it stay off)" : " (not found)"))
                        .font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                }
            }
        }
    }

    static func chooseFolder(_ message: String) -> String? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.allowsMultipleSelection = false
        panel.message = message
        return panel.runModal() == .OK ? panel.url?.path : nil
    }

    /// LAB-1837 · the way back to the native Learn screens for this release; off = the shared Agentic Engineering page.
    private var learnClassicRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            Toggle("Learn: classic screens", isOn: $model.settings.learnClassic)
            Text("Off: Learn shows the shared Agentic Engineering page, the same one every site shows, saved in this version of One Roof so it works offline. On: the earlier native screens.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if !model.settings.learnClassic, model.learnShared == nil {
                Text("This build has no saved shared page, so Learn shows the classic screens.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// LAB-1621 · a card played to its end rolls over to the next one after a three-second countdown.
    private var autoAdvanceRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            Toggle("Auto-advance to the next card", isOn: $model.settings.learnAutoAdvance)
            Text("When a card finishes, count down three seconds, then open the next card on the band and keep playing. Stay, Esc or pause cancels the countdown.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }

    /// Extra Learn folders: posts in them (`<folder>/<post>/index.md`) join Learn › Writing; in the classic window their
    /// Markdown pages and narration folders are also Learn pages (LAB-1274: the v2 window has no Pages list).
    private var learnFoldersRow: some View {
        LabeledContent("Learn folders") {
            VStack(alignment: .leading, spacing: 4) {
                if model.settings.learnFolders.isEmpty {
                    Text(model.settings.ui2 ? "None. Add a folder of posts (one folder per post, with an index.md) to read them in Learn › Writing."
                         : "None. Add a folder of Markdown pages or narration (.mp3) folders.").font(.caption).foregroundStyle(.secondary)
                }
                ForEach(model.settings.learnFolders, id: \.self) { f in
                    HStack(spacing: 6) {
                        if !Workspace.folderExists((f as NSString).expandingTildeInPath) {
                            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange).help("Folder not found")
                        }
                        Text(f.replacingOccurrences(of: NSHomeDirectory(), with: "~")).lineLimit(1).truncationMode(.middle)
                        Spacer()
                        Button("Remove") { model.settings.learnFolders.removeAll { $0 == f } }.controlSize(.small)
                    }
                }
                Button("Add…") {
                    if let p = Self.chooseFolder("Choose a folder of Markdown pages or narration folders"),
                       !model.settings.learnFolders.contains(p) { model.settings.learnFolders.append(p) }
                }
                .controlSize(.small)
            }
        }
    }

    /// The optional on-device router model (.gguf).
    private var modelRow: some View {
        let inUse = model.settings.modelFile
        let exists = FileManager.default.fileExists(atPath: inUse)
        return LabeledContent("On-device model") {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    TextField("", text: $model.settings.localModelPath,
                              prompt: Text(LocalModel.defaultModelPath.replacingOccurrences(of: NSHomeDirectory(), with: "~"))).labelsHidden()
                    Button("Choose…") {
                        let panel = NSOpenPanel()
                        panel.canChooseFiles = true; panel.canChooseDirectories = false; panel.allowsMultipleSelection = false
                        panel.message = "Choose the \(LocalModel.modelFileName) file"
                        if panel.runModal() == .OK, let u = panel.url { model.settings.localModelPath = u.path }
                    }
                }
                HStack(spacing: 4) {
                    Text(exists ? "In use: \(inUse.replacingOccurrences(of: NSHomeDirectory(), with: "~"))"
                         : "Optional add-on, not installed: captions and task sorting use the built-in rules. See Help › Seats and routing.")
                        .font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                }
                if exists, let warning = LocalModel.licenceWarning(path: inUse) {
                    Label(warning, systemImage: "exclamationmark.triangle").font(.caption)
                        .foregroundStyle(Pastel.named("peach")!.lightInk.color).fixedSize(horizontal: false, vertical: true)
                }
                // LAB-675: Get the model belongs to the model row (0.5.2 had it on the shared folder rows instead).
                ModelDownloadRow(download: model.modelDownload, offer: LocalModel.offerDownload(modelPath: inUse))
            }
        }
    }

    /// Agentic engineering ships inside One Roof (LAB-768): every skill and the narrated deck. No folder choice;
    /// ONEROOF_AE_PATH still overrides it for development, and the row says so when it does.
    private var aeRow: some View {
        let r = model.settings.agenticEngineering
        let cards = AEFolder.deckRoot(r.path).map { AEFolder.deckCards($0).count } ?? 0
        return LabeledContent("Agentic engineering") {
            HStack(spacing: 8) {
                Text(r.source == .bundled ? "Bundled with One Roof · \(cards) narrated cards" : "\(r.label) · \(r.path.replacingOccurrences(of: NSHomeDirectory(), with: "~"))")
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                Spacer()
                Button("Show") { NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: r.path) }
            }
        }
    }

    private func pathRow(_ title: String, _ path: Binding<String>) -> some View {
        LabeledContent(title) {
            HStack {
                TextField("", text: path).labelsHidden()
                Button("Show") { NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: path.wrappedValue) }
                if !FileManager.default.fileExists(atPath: path.wrappedValue) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange).help("Folder not found")
                }
            }
        }
    }
}

/// A model name: free text, with the agent's known models one click away.
struct ModelField: View {
    let agent: AgentKind
    @Binding var model: String

    var body: some View {
        LabeledContent("Model") {
            HStack(spacing: 6) {
                TextField("", text: $model, prompt: Text("CLI default")).labelsHidden()
                    .textFieldStyle(.roundedBorder).multilineTextAlignment(.leading).frame(minWidth: 200)   // LAB-1934
                    .accessibilityLabel("\(agent.displayName) model")
                if !agent.suggestedModels.isEmpty {
                    Menu {
                        Button("CLI default") { model = "" }
                        Divider()
                        ForEach(agent.suggestedModels, id: \.self) { m in Button(m) { model = m } }
                    } label: { Image(systemName: "chevron.down.circle") }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                }
            }
        }
    }
}

/// The Settings window (one instance).
final class SettingsWindowController: NSWindowController {
    convenience init(model: AppModel, tab: Int = 0) {
        let host = NSHostingController(rootView: SettingsView(model: model, tab: tab))
        let w = NSWindow(contentViewController: host)
        w.title = "One Roof Settings"
        w.styleMask = [.titled, .closable]
        w.isReleasedWhenClosed = false
        self.init(window: w)
        w.center()
    }
}
