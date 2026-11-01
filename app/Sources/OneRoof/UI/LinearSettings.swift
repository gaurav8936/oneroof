import AppKit
import SwiftUI
import OneRoofCore

/// LAB-2102 · Settings › Linear: connect (a key, kept readable only by you), test the connection, the recommended Linear
/// setup in plain words, and how One Roof maps it, with fields for the names that differ in your workspace (ticket
/// states, Type labels) and the teams Projects shows. One Roof ships no tracker data: Projects is empty until you connect.
struct LinearSettings: View {
    @ObservedObject var model: AppModel
    @State private var keyField = ""
    @State private var testing = false
    @State private var testLine: (text: String, ok: Bool)?
    @State private var draft = LinearMapping.standard
    @State private var loadedDraft = false
    @State private var saveLine: (text: String, ok: Bool)?
    @State private var checking = false
    @State private var problems: [String]?
    /// Where the key comes from, worked out off the main thread when the pane opens or a key is saved.
    @State private var keySource = ""

    private func readKeySource() {
        let hasKey = model.linear.hasKey
        DispatchQueue.global(qos: .utility).async {
            let s: String
            if let e = ProcessInfo.processInfo.environment["LINEAR_API_KEY"], !e.isEmpty { s = "from LINEAR_API_KEY in the environment" }
            else if FileManager.default.fileExists(atPath: LinearClient.keyPath) { s = "saved in \((LinearClient.keyPath as NSString).abbreviatingWithTildeInPath), readable only by you" }
            else if FileManager.default.fileExists(atPath: LegacyMigration.linearKeyPath) { s = "from an older key file" }
            else { s = hasKey ? "for this run only" : "" }
            DispatchQueue.main.async { keySource = s }
        }
    }

    var body: some View {
        Form {
            connect
            recommended
            mapping
        }
        .formStyle(.grouped)
        .onAppear {
            if !loadedDraft { draft = model.linearMapping; loadedDraft = true }
            readKeySource()
            if model.linear.hasKey && model.linearTeams.isEmpty { model.loadWorkstreams() }
        }
    }

    // MARK: Connect

    private var connect: some View {
        Section("Connect") {
            LabeledContent("Status") {
                Text(model.linear.hasKey ? "Connected" + (keySource.isEmpty ? "" : " · " + keySource) : "Not connected")
                    .foregroundStyle(model.linear.hasKey ? Color.primary : Color.secondary)
                    .textSelection(.enabled)
            }
            HStack {
                SecureField("Linear API key", text: $keyField, prompt: Text(model.linear.hasKey ? "paste a new key to replace it" : "lin_api_…"))
                    .accessibilityLabel("Linear API key")
                Button("Save key") { saveKey() }.disabled(keyField.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || testing)
            }
            Text("Make a personal API key in Linear › Settings › Security & access. One Roof keeps it in a file only you can read (the same place Setup saves it); LINEAR_API_KEY in the environment wins over the file.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 10) {
                Button("Test connection") { test() }.disabled(!model.linear.hasKey || testing)
                if testing { ProgressView().controlSize(.small) }
                if let l = testLine {
                    Text(l.text).font(.caption).foregroundStyle(l.ok ? Color.secondary : Color.red).fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                }
            }
            Text("One Roof never ships anyone's tracker data: Projects stays empty until you connect your own Linear, and reads it live (every few minutes while Projects is open).")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Recommended setup

    private var recommended: some View {
        Section("Recommended setup") {
            ForEach(LinearSetupGuide.recommended, id: \.0) { row in
                LabeledContent(row.0) {
                    Text(row.1).font(.callout).multilineTextAlignment(.trailing).fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .combine)
            }
        }
    }

    // MARK: Mapping

    private var mapping: some View {
        Group {
            Section("Ticket statuses · your names") {
                Text("One Roof moves tickets between these six. If a state is called something else in your teams, type its name; leave it as is when it matches.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                ForEach(LinearMapping.canonicalStates, id: \.self) { c in
                    LabeledContent(c) {
                        TextField(c, text: Binding(get: { draft.stateName(c) }, set: { draft.setState(c, to: $0) }), prompt: Text(c))
                            .labelsHidden().textFieldStyle(.roundedBorder).frame(maxWidth: 220)
                            .accessibilityLabel("Your name for the \(c) state")
                    }
                }
            }
            Section("Type labels · your names") {
                Text("Each ticket carries one Type label. One Roof reads these names (and the standard ones) and puts yours on new items.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                ForEach(LinearMapping.typeKinds) { k in
                    LabeledContent(k.labelNames.first ?? k.rawValue) {
                        TextField(k.labelNames.first ?? k.rawValue, text: Binding(get: { draft.labelName(k) }, set: { draft.setLabel(k, to: $0) }),
                                  prompt: Text(k.labelNames.first ?? k.rawValue))
                            .labelsHidden().textFieldStyle(.roundedBorder).frame(maxWidth: 220)
                            .accessibilityLabel("Your label for \(k.rawValue) tickets")
                    }
                }
            }
            Section("Teams on Projects") {
                if model.linearTeams.isEmpty {
                    Text(model.linear.hasKey ? "Reading your teams from Linear…" : "Connect Linear to list your teams.")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    ForEach(model.linearTeams) { team in
                        Toggle(isOn: Binding(get: { !draft.hiddenTeams.contains(team.key) }, set: { draft.setTeam(team.key, shown: $0) })) {
                            Text(team.key).font(.system(.body, design: .monospaced)) + Text(team.name != team.key ? "  " + team.name : "")
                        }
                        .accessibilityLabel("Show team \(team.key) \(team.name) on Projects")
                    }
                }
            }
            Section {
                HStack(spacing: 10) {
                    Button("Save mapping") { save() }.disabled(draft == model.linearMapping)
                    Button("Use the recommended names") { draft = .standard }.disabled(draft.isStandard)
                    Spacer()
                    Button("Check against Linear") { check() }.disabled(!model.linear.hasKey || model.linearTeams.isEmpty || checking)
                    if checking { ProgressView().controlSize(.small) }
                }
                if let l = saveLine { Text(l.text).font(.caption).foregroundStyle(l.ok ? Color.secondary : Color.red) }
                if let p = problems {
                    if p.isEmpty {
                        Text("Every team has each state and Type label this mapping names.").font(.caption).foregroundStyle(.secondary)
                    } else {
                        VStack(alignment: .leading, spacing: 2) {
                            ForEach(p.prefix(40), id: \.self) { Text($0).font(.caption) }
                            if p.count > 40 { Text("and \(p.count - 40) more").font(.caption).foregroundStyle(.secondary) }
                        }
                        .textSelection(.enabled)
                    }
                }
                Text("Saved in \((LinearMapping.path as NSString).abbreviatingWithTildeInPath), next to the key; never part of the app.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    // MARK: Actions (network off the main thread)

    private func saveKey() {
        let key = keyField.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return }
        if SelfTest.isActive {
            model.linear = LinearClient(key: key, mapping: model.linearMapping)   // a self-test never writes the key file
        } else {
            do { try LinearClient.saveKey(key); model.reconnectLinear() }
            catch { testLine = ("Could not save the key: \(error)", false); return }
        }
        keyField = ""
        readKeySource()
        test()
    }

    private func test() {
        testing = true; testLine = nil
        let c = model.linear
        DispatchQueue.global(qos: .userInitiated).async {
            let line: (String, Bool)
            do {
                let r = try c.testConnection()
                line = ("Connected as \(r.user) · workspace \(r.workspace) · \(r.teams) team\(r.teams == 1 ? "" : "s")", true)
            } catch { line = ("\(error)", false) }
            DispatchQueue.main.async {
                testing = false; testLine = line
                if line.1 { model.loadWorkstreams(force: true) }
            }
        }
    }

    private func save() {
        do { try model.applyLinearMapping(draft); saveLine = ("Saved. Projects reads Linear again with these names.", true) }
        catch { saveLine = ("Could not save: \(error)", false) }
    }

    private func check() {
        checking = true; problems = nil
        let c = model.linear.with(mapping: draft), keys = model.linearTeams.prefix(30).map(\.key)
        DispatchQueue.global(qos: .userInitiated).async {
            var out: [String] = []
            for k in keys {
                do {
                    let t = try c.team(key: k)
                    out += draft.problems(teamKey: k, states: t.states, labels: Array(t.labels.keys))
                } catch { out.append("\(k): \(error)") }
            }
            DispatchQueue.main.async { checking = false; problems = out }
        }
    }
}
