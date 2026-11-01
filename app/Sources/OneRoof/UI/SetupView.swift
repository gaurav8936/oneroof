import AppKit
import SwiftUI
import OneRoofCore

/// First-run setup (One Roof › Setup…): the projects folder, the optional shared folder, the agentic-engineering
/// package, which agents are installed, and an optional Linear key. "Start" saves and marks setup done.
struct SetupView: View {
    @ObservedObject var model: AppModel
    var done: () -> Void

    @State private var projects = ""
    @State private var shared = ""
    @State private var sharedSkipped = false
    @State private var linearKey = ""
    @State private var agents: [AgentRow] = []
    @State private var tools: [CheckResult] = []
    @State private var error: String?
    /// v2 Setup step: 0 agents, 1 folders and tools, 2 kit, look and Linear.
    @State private var step = 0

    struct AgentRow: Identifiable {
        var id: String { command }
        var command: String
        var title: String
        var installed: Bool
        var detail: String
    }

    private var projectsInUse: String { Workspace.resolveProjects(setting: projects) }
    private var sharedInUse: String { Workspace.resolveShared(setting: shared, projects: projectsInUse) }

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Set up One Roof").font(.system(size: 20, weight: .bold))
                Text(!model.settings.ui2 ? "Pick the folders One Roof works in. Everything here can be changed later in Settings › Foundations."
                     : ["Agents on this Mac. Install any later; One Roof finds them on your PATH.", "Pick the folders One Roof works in.",
                        "The kit, your look and Linear."][step] + " Everything here can be changed later in Settings › Foundations.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 24).padding(.top, 20).padding(.bottom, 8)
            Form {
                if model.settings.ui2 {
                    // v2 (B3.1-B3.3, LAB-1195): three steps, every field of today's form.
                    switch step {
                    case 0: agentsSection
                    case 1: projectsSection; sharedSection; toolsSection
                    default: kitSection; lookSection; linearSection
                    }
                } else {
                    projectsSection; sharedSection; kitSection; toolsSection; agentsSection; linearSection
                }
            }
            .formStyle(.grouped)
            HStack {
                if let error { Text(error).font(.callout).foregroundStyle(.red).lineLimit(2) }
                Spacer()
                if model.settings.ui2 {
                    Text("Step \(step + 1) of 3").font(.callout).foregroundStyle(.secondary)
                    if step > 0 { Button("Back") { step -= 1 }.controlSize(.large) }
                    if step < 2 { Button("Continue") { step += 1 }.keyboardShortcut(.defaultAction).controlSize(.large) }
                    else { Button("Open One Roof") { start() }.keyboardShortcut(.defaultAction).controlSize(.large) }
                } else {
                    Button("Start") { start() }.keyboardShortcut(.defaultAction).controlSize(.large)
                }
            }
            .padding(.horizontal, 24).padding(.vertical, 14)
        }
        .frame(width: 640, height: 800)
        .onAppear(perform: load)
    }

    @ViewBuilder private var projectsSection: some View {
        Section("Projects folder") {
            folderRow(text: $projects, placeholder: Workspace.defaultProjectsRoot().tilde,
                      message: "Choose the folder that holds your repos")
            note("Agents start here; a session can start in one of its repos instead. In use: \(projectsInUse.tilde)",
                 warn: !Workspace.folderExists(projectsInUse))
        }
    }

    @ViewBuilder private var sharedSection: some View {
        Section("Shared rules and docs (optional)") {
            if sharedSkipped {
                HStack {
                    Text("Skipped: handoffs, gotchas and the workspace checks stay off.").foregroundStyle(.secondary)
                    Spacer()
                    Button("Use one") { sharedSkipped = false }
                }
            } else {
                folderRow(text: $shared, placeholder: Workspace.resolveShared(setting: "", projects: projectsInUse).tilde,
                          message: "Choose the folder with your shared rules, handoffs and gotchas") {
                    if !Workspace.folderExists(sharedInUse) {
                        Button("Create it") { create(sharedInUse) }
                    }
                    Button("Skip") { sharedSkipped = true; shared = "" }
                }
                note(Workspace.folderExists(sharedInUse) ? "In use: \(sharedInUse.tilde)"
                     : "Not found: \(sharedInUse.tilde). Create it, choose another folder, or skip.",
                     warn: !Workspace.folderExists(sharedInUse))
            }
        }
    }

    @ViewBuilder private var kitSection: some View {
        Section("Agentic engineering") {
            // LAB-768: bundled, nothing to choose.
            Text("Bundled with One Roof: every skill and the narrated Agentic Engineering deck (Learn, ⇧⌘E).")
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private var toolsSection: some View {
        Section("Required tools") {
            if tools.isEmpty {
                HStack(spacing: 8) { ProgressView().controlSize(.small); Text("Checking git…").foregroundStyle(.secondary) }
            }
            ForEach(tools) { c in
                HStack(spacing: 8) {
                    Image(systemName: c.level == .ok ? "checkmark.circle.fill" : "xmark.octagon.fill")
                        .foregroundStyle(c.level == .ok ? Color.green : Color.red)
                    Text(c.title).frame(width: 110, alignment: .leading)
                    Text(c.detail).foregroundStyle(.secondary).lineLimit(2).textSelection(.enabled)
                    Spacer()
                }
                .accessibilityElement(children: .combine)
            }
            if tools.contains(where: { $0.id == "tool-git" && $0.level != .ok }) {
                note("You can start now, but diffs and review need git: install it, then reopen One Roof.", warn: true)
            }
        }
    }

    @ViewBuilder private var agentsSection: some View {
        Section("Agents on this Mac") {
            if agents.isEmpty {
                HStack(spacing: 8) { ProgressView().controlSize(.small); Text("Looking for agents…").foregroundStyle(.secondary) }
            }
            ForEach(agents) { a in
                HStack(spacing: 8) {
                    Image(systemName: a.installed ? "checkmark.circle.fill" : "xmark.circle")
                        .foregroundStyle(a.installed ? Color.green : Color.secondary)
                    Text(a.title).frame(width: 110, alignment: .leading)
                    Text(a.detail).foregroundStyle(.secondary).lineLimit(3).truncationMode(.middle)
                    Spacer()
                }
                .accessibilityElement(children: .combine)
            }
            note("Install any agent CLI later; One Roof finds it on your PATH.", warn: false)
        }
    }

    @ViewBuilder private var linearSection: some View {
        Section("Linear (optional)") {
            SecureField("Linear API key", text: $linearKey, prompt: Text(model.linear.hasKey ? "already connected" : "lin_api_…"))
            note("Saved to \(LinearClient.keyPath.tilde), readable only by you. LINEAR_API_KEY in the environment also works.",
                 warn: false)
        }
    }

    /// v2 step 3: the look (A10.3) — one tap sets every panel; Settings › Appearance changes it later.
    @ViewBuilder private var lookSection: some View {
        Section("Look") {
            Picker("Look", selection: Binding(get: { Look.matching(model.chosenThemes) }, set: { if let l = $0 { model.chosenThemes = l.panelThemes } })) {
                if Look.matching(model.chosenThemes) == nil { Text("Your own mix").tag(Look?.none) }
                ForEach(Look.allCases) { Text($0.title).tag(Look?.some($0)) }
            }
            note("Sets every panel at once. Change it any time in Settings › Appearance.", warn: false)
        }
    }

    @ViewBuilder
    private func folderRow<Extra: View>(text: Binding<String>, placeholder: String, message: String,
                                        @ViewBuilder extra: () -> Extra = { EmptyView() }) -> some View {
        HStack {
            TextField("", text: text, prompt: Text(placeholder)).labelsHidden()
            Button("Choose…") { if let p = pick(message) { text.wrappedValue = p } }
            extra()
        }
    }

    private func note(_ text: String, warn: Bool) -> some View {
        HStack(spacing: 4) {
            if warn { Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange) }
            Text(text).font(.caption).foregroundStyle(.secondary).lineLimit(2)
        }
    }

    private func pick(_ message: String) -> String? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.message = message
        return panel.runModal() == .OK ? panel.url?.path : nil
    }

    private func create(_ path: String) {
        do { try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true); shared = path; error = nil }
        catch { self.error = "Could not create \(path.tilde): \(error.localizedDescription)" }
    }

    private func load() {
        let s = model.settings
        projects = s.projectsPath
        shared = s.commonPath
        DispatchQueue.global(qos: .userInitiated).async {
            let found = Foundations.requiredTools()
            DispatchQueue.main.async { tools = found }
            let rows = SetupView.detectAgents()
            DispatchQueue.main.async { agents = rows }
        }
    }

    /// claude, codex, kimi, gemini, agy: found on PATH, and for Claude the signed-in email of each account.
    static func detectAgents(home: String = NSHomeDirectory()) -> [AgentRow] {
        var out: [AgentRow] = []
        let claude = AccountResolver.installed("claude", home: home)
        let accounts = AccountResolver.claudeAccounts(home: home).map { a -> String in
            "\(a) " + (AccountResolver.claudeEmail(AccountResolver.claudeConfigFile(a, home: home)) ?? "not signed in")
        }
        out.append(AgentRow(command: "claude", title: "Claude Code", installed: claude,
                            detail: claude ? accounts.joined(separator: "\n") : "claude not found on PATH"))
        for (cmd, title) in [("codex", "Codex"), ("kimi", "Kimi"), ("gemini", "Gemini"), ("agy", "Antigravity")] {
            let ok = AccountResolver.installed(cmd, home: home)
            out.append(AgentRow(command: cmd, title: title, installed: ok, detail: ok ? "installed" : "\(cmd) not found on PATH"))
        }
        return out
    }

    private func start() {
        let key = linearKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if !key.isEmpty {
            do { try LinearClient.saveKey(key); model.reconnectLinear() }
            catch { self.error = "Could not save the Linear key: \(error)"; return }
        }
        var s = model.settings
        s.projectsPath = projects.trimmingCharacters(in: .whitespaces)
        s.commonPath = sharedSkipped ? "" : shared.trimmingCharacters(in: .whitespaces)
        s.setupDone = true
        model.settings = s
        model.runFoundations()
        done()
    }
}

private extension String {
    var tilde: String { replacingOccurrences(of: NSHomeDirectory(), with: "~") }
}

/// The setup window (one instance).
final class SetupWindowController: NSWindowController {
    convenience init(model: AppModel, done: @escaping () -> Void) {
        let host = NSHostingController(rootView: SetupView(model: model, done: done))
        host.sizingOptions = []
        let w = NSWindow(contentViewController: host)
        w.title = "One Roof Setup"
        w.styleMask = [.titled, .closable]
        w.setContentSize(NSSize(width: 640, height: 800))
        w.isReleasedWhenClosed = false
        self.init(window: w)
        w.center()
    }
}
