import OneRoofCore
import SwiftUI

/// LAB-1509 · Session catalog: every session One Roof knows (live and history, every window, open or closed), grouped
/// by repo, newest first. Each row says where the session is and what Resume does; rows that cannot be resumed say why.
/// Finished sessions (agent ended, shell still open) can be closed in one step; their rows stay, as history.
struct CatalogView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var win: WindowState
    @Environment(\.theme) private var t
    @State private var query = ""
    @State private var states: Set<SessionCatalog.State> = []
    @State private var note: String?
    @State private var backfilled = false

    var body: some View {
        let entries = model.catalogEntries()
        let groups = SessionCatalog.groups(entries, query: query, states: states)
        let finished = entries.filter { $0.state == .finishedShell }.count
        FleetPage(title: "Session catalog", subtitle: subtitle(entries)) {
            HStack(spacing: 8) {
                RoofButton(finished == 0 ? "No finished sessions" : "Close \(finished) finished") {
                    let n = model.closeFinishedSessions()
                    note = "Closed \(n) finished session\(n == 1 ? "" : "s"). Their rows stay here, as history."
                }
                .disabled(finished == 0)
                .help("End the shells whose agent has finished. Nothing is deleted: each row stays in the catalog.")
            }
        } content: {
            VStack(alignment: .leading, spacing: 12) {
                filters
                if let note { Text(note).ui(12.5).foregroundStyle(t.text2.color) }
                if groups.isEmpty {
                    Card(padding: 20) {
                        Text(entries.isEmpty ? "No sessions yet." : "Nothing matches.").ui(13).foregroundStyle(t.text2.color)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                } else {
                    Card(padding: 8) {
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 2) {
                                ForEach(groups) { g in
                                    HStack(spacing: 8) {
                                        MicroLabel(Workspace.repoLabel(for: g.repo))
                                        Text("\(g.entries.count)").ui(11, mono: true).foregroundStyle(t.text3.color)
                                    }
                                    .padding(.horizontal, 8).padding(.top, 10).padding(.bottom, 2)
                                    ForEach(g.entries) { row($0) }
                                }
                            }
                        }
                    }
                }
            }
        }
        .onAppear {
            guard !backfilled else { return }
            backfilled = true
            model.backfillConversations { found, looked in
                if found > 0 { note = "Found the conversation of \(found) of \(looked) older Claude sessions: they can be resumed now." }
            }
        }
    }

    private var filters: some View {
        HStack(spacing: 8) {
            TextField("Find a session: name, repo, issue, agent, window", text: $query)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 360)
                .accessibilityLabel("Find a session")
            ForEach(SessionCatalog.State.allCases, id: \.self) { s in
                RoofButton(s.label, states.contains(s) ? .primary : .secondary) {
                    if states.contains(s) { states.remove(s) } else { states.insert(s) }
                }
                .accessibilityLabel("Show \(s.label) sessions")
            }
            if !states.isEmpty || !query.isEmpty {
                RoofButton("Clear", .plain) { states = []; query = "" }
            }
        }
    }

    private func row(_ e: SessionCatalog.Entry) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(e.state.label).ui(11, .semibold, mono: true).foregroundStyle(stateColor(e.state))
                .frame(width: 66, alignment: .leading)
            VStack(alignment: .leading, spacing: 3) {
                Text(e.name).ui(TypeScale.row, .semibold).foregroundStyle(t.text.color).lineLimit(1)
                Text(details(e)).ui(11.5).foregroundStyle(t.text3.color).lineLimit(1)
            }
            Spacer(minLength: 8)
            Text((e.state == .planned ? "created " : "") + Self.when.localizedString(for: e.when, relativeTo: Date())).ui(11.5).foregroundStyle(t.text3.color)
            if let title = e.resume.buttonTitle {
                RoofButton(title, e.resume == .open ? .secondary : .primary) { model.catalogResume(e.id) }
                    .help(help(e))
            } else {
                Text("Can't resume").ui(11.5).foregroundStyle(t.text3.color).help(e.resume.why ?? "")
            }
        }
        .padding(.horizontal, 8).padding(.vertical, 6)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(e.name), \(e.state.label), \(details(e))")
    }

    private func details(_ e: SessionCatalog.Entry) -> String {
        [e.agent + (e.account.map { " · \($0)" } ?? ""), e.ticket, e.window.map { "window \($0)" }].compactMap { $0 }.joined(separator: " · ")
    }

    private func help(_ e: SessionCatalog.Entry) -> String {
        switch e.resume {
        case .open: return "It is running: bring it forward."
        case .claude(let id): return "claude --resume \(id) — in its open shell, else a new terminal in the same folder and account."
        case .terminal: return "A new terminal in the same folder."
        case .launch: return "Planned and never started: start it now."
        default: return e.resume.why ?? ""
        }
    }

    private func stateColor(_ s: SessionCatalog.State) -> Color {
        switch s {
        case .working: return t.statusColor(.running).color
        case .waiting: return t.statusColor(.idle).color
        case .finishedShell: return t.statusColor(.needsYou).color
        case .history, .planned: return t.text3.color
        }
    }

    private func subtitle(_ entries: [SessionCatalog.Entry]) -> String {
        let repos = Set(entries.map(\.repo)).count
        let live = entries.filter { [.working, .waiting, .finishedShell].contains($0.state) }.count
        let resumable = entries.filter { $0.resume.buttonTitle != nil }.count
        return "\(entries.count) sessions · \(repos) repos · \(live) running · \(resumable) you can open or resume"
    }

    private static let when: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter(); f.unitsStyle = .short; return f
    }()
}
