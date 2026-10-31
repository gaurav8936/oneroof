import SwiftUI
import OneRoofCore

/// Credential references and bounded paid sessions, kept separate from subscription seats.
struct HostedSettingsView: View {
    @ObservedObject var model: AppModel
    @State private var draft = HostedConnection(name: "Hosted coding", provider: .together, model: HostedProvider.together.testedModel, keyFile: "")
    @State private var python = ""
    @State private var kit = ""
    @State private var opencode = ""
    @State private var goose = ""
    @State private var storage = ""
    @State private var mcp = ""
    @State private var message = ""
    @State private var checking = false

    private var runtime: HostedRuntimeConfiguration {
        HostedRuntimeConfiguration(pythonExecutable: Workspace.expand(python), kitDirectory: Workspace.expand(kit),
            nativeExecutables: ["opencode": Workspace.expand(opencode), "goose": Workspace.expand(goose)],
            storageDirectory: Workspace.expand(storage), baseConfigPath: mcp.isEmpty ? nil : Workspace.expand(mcp))
    }

    var body: some View {
        Section("Hosted coding · OpenCode and Goose") {
            Text("The agent runs here; the model runs at the selected provider. No local model or GPU is needed. Native permissions stay manual.")
                .font(.caption).foregroundStyle(.secondary)
            Picker("Connection", selection: Binding(get: { draft.id }, set: { id in
                if let c = model.settings.hostedConnections.first(where: { $0.id == id }) { draft = c }
            })) {
                Text(draft.name.isEmpty ? "Unsaved connection" : draft.name).tag(draft.id)
                ForEach(model.settings.hostedConnections.filter { $0.id != draft.id }) { Text($0.name).tag($0.id) }
            }
            HStack {
                Button("New connection") { draft = HostedConnection(name: "Hosted coding", provider: .together, model: HostedProvider.together.testedModel, keyFile: "") }
                Button("Remove saved connection") { model.settings.hostedConnections.removeAll { $0.id == draft.id } }
                    .disabled(!model.settings.hostedConnections.contains(where: { $0.id == draft.id }))
            }
            TextField("Name", text: $draft.name)
            Picker("Provider", selection: Binding(get: { draft.provider }, set: { p in
                draft.provider = p; draft.model = p.testedModel; draft.priceChecked = ""; draft.inputPerMillion = 0; draft.outputPerMillion = 0
            })) { ForEach(HostedProvider.allCases) { Text($0.displayName).tag($0) } }
            TextField("Exact provider model ID", text: Binding(get: { draft.model }, set: { value in draft.model = value; draft.priceChecked = "" }))
            TextField("Credential file path (never paste the key)", text: $draft.keyFile)
            TextField("Input USD / million tokens", value: $draft.inputPerMillion, format: .number)
            TextField("Output USD / million tokens", value: $draft.outputPerMillion, format: .number)
            TextField("Prices verified on (YYYY-MM-DD)", text: $draft.priceChecked)
            TextField("Price source URL", text: Binding(get: { draft.priceSource ?? "" }, set: { draft.priceSource = $0 }))
            TextField("Session reservation ceiling (USD)", value: $draft.sessionBudgetUSD, format: .number)
            TextField("Shared connection ceiling (USD)", value: $draft.sharedBudgetUSD, format: .number)
            TextField("Maximum requests / session", value: $draft.maxRequests, format: .number)
            TextField("Maximum output tokens / request", value: $draft.maxOutputTokens, format: .number)
            Text("Ceilings reserve a conservative maximum before each request; they are not a provider balance or final billed cost. The shared ceiling covers every session using this connection.")
                .font(.caption).foregroundStyle(.secondary)
            DisclosureGroup("Runtime installation") {
                TextField("Python with PyYAML", text: $python)
                TextField("Agent engineering kit folder", text: $kit)
                TextField("OpenCode 1.19.5 executable", text: $opencode)
                TextField("Goose 1.57.0 executable", text: $goose)
                TextField("Private launch storage folder", text: $storage)
                TextField("Optional reviewed kit config · MCP only", text: $mcp)
                Text("Only MCP definitions are imported. Each session gets a private home, skills and verified guards; other agents' account settings are not copied.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            HStack {
                Button(checking ? "Checking…" : "Refresh catalogue prices") { refresh() }.disabled(checking)
                Button("Save connection and runtime") { save() }.disabled(checking)
            }
            Text("Fireworks: enter rates from its official model page and today's verification date. Catalogue checks do not prove inference access. Launch verifies the pinned executable and guard; authentication is checked on the first paid request.")
                .font(.caption).foregroundStyle(.secondary)
            if !message.isEmpty { Text(message).font(.caption).textSelection(.enabled) }
        }
        .onAppear {
            if let c = model.settings.hostedConnections.first { draft = c }
            let data = NSHomeDirectory() + "/Library/Application Support/One Roof/HostedRuntime"
            let r = model.settings.hostedRuntime
            python = r?.pythonExecutable ?? data + "/python/bin/python3"
            kit = r?.kitDirectory ?? AEFolder.deckRoot(model.settings.agenticEngineering.path) ?? model.settings.agenticEngineering.path
            storage = r?.storageDirectory ?? data + "/private"
            opencode = r?.nativeExecutables["opencode"] ?? data + "/bin/opencode"
            goose = r?.nativeExecutables["goose"] ?? data + "/bin/goose"
            mcp = r?.baseConfigPath ?? ""
        }
    }

    private func save() {
        let errors = draft.configurationErrors()
        guard errors.isEmpty else { message = errors.joined(separator: "\n"); return }
        if let i = model.settings.hostedConnections.firstIndex(where: { $0.id == draft.id }) { model.settings.hostedConnections[i] = draft }
        else { model.settings.hostedConnections.append(draft) }
        model.settings.hostedRuntime = runtime
        for agent in [AgentKind.opencode, .goose] {
            var d = model.settings.defaults(for: agent); d.hostedConnectionID = draft.id
            model.settings.agents[agent.rawValue] = d
        }
        message = "Saved. Choose OpenCode or Goose, this connection and a specific repository in New session."
    }

    private func refresh() {
        let c = draft, r = runtime
        checking = true; message = ""
        DispatchQueue.global(qos: .userInitiated).async {
            let result = Result { try HostedPreparation.refreshPrices(connection: c, runtime: r, repo: Workspace.projectsRoot) }
            DispatchQueue.main.async {
                checking = false
                guard draft.id == c.id, draft.provider == c.provider, draft.model == c.model else { return }
                switch result {
                case .success(let updated): draft = updated; message = "Catalogue rates checked. Save to use them."
                case .failure(let error): message = String(describing: error)
                }
            }
        }
    }
}
