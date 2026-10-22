import SwiftUI
import OneRoofCore

/// Add an issue to an existing session (LAB-474): a session can resolve several, and more come in while it runs. An open
/// issue of a project, or a new one created in Linear, joins the session's issues; a live, idle agent is told about it.
/// Reached from the session menu ("Issue…" / "Add issue…"), right-click, and the Plan panel's Ticket tab.
struct AttachIssueSheet: View {
    @Environment(\.theme) private var t
    @ObservedObject var model: AppModel
    let item: BoardItem
    var close: () -> Void

    @State private var wsId = ""
    @State private var pick: LinearIssue?
    @State private var newKind: WorkKind?
    @State private var title = ""
    @State private var tellAgent = true
    @State private var busy = false
    @State private var error: String?

    private var live: BoardItem { model.item(item.id) ?? item }
    private var linked: Bool { model.linear.hasKey }
    private var openProjects: [LinearWorkstream] { model.workstreams.filter { !["completed", "canceled"].contains($0.state) } }
    private var project: LinearWorkstream? { model.workstreams.first { $0.id == wsId } }
    private var openIssues: [LinearIssue] {
        guard let w = project else { return [] }
        return (model.issues[w.id] ?? []).filter {
            $0.type != "commit" && !["completed", "canceled"].contains($0.stateType) && !live.session.hasTicket($0.identifier)
        }.reversed()
    }
    private var valid: Bool {
        guard linked, project != nil, !busy else { return false }
        if newKind != nil { return !title.trimmingCharacters(in: .whitespaces).isEmpty }
        return pick != nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(live.session.ticket == nil ? "Attach an issue" : "Add an issue").ui(20, .semibold).foregroundStyle(t.text.color)
                Text(live.session.name + ((live.session.allTickets.isEmpty ? "" : " · on " + live.session.allTickets.map(\.key).joined(separator: ", ")))).ui(13).foregroundStyle(t.text3.color).lineLimit(1)
            }
            if !linked {
                Text("Connect Linear in Settings to attach issues.").ui(13).foregroundStyle(t.needsText.color)
            } else {
                field("Project") {
                    FieldMenu(title: project.map { "\($0.wsId ?? "") · \($0.title)" } ?? (model.linearLoading ? "Loading projects…" : "Pick a project")) {
                        ForEach(openProjects) { w in Button(NewSessionSheet.short("\(w.wsId ?? "") · \(w.title)")) { pickProject(w) } }
                    }
                }
                field("Issue") {
                    FieldMenu(title: issueLabel) {
                        if !openIssues.isEmpty {
                            Section("Open issues") {
                                ForEach(openIssues.prefix(40)) { i in
                                    Button(NewSessionSheet.short("\(i.identifier) · \(i.shortTitle)")) { pick = i; newKind = nil }
                                }
                            }
                        }
                        Section("New issue") {
                            ForEach([WorkKind.deliverable, .defect, .chore, .spike, .decision], id: \.self) { k in
                                Button("New " + (k.labelNames.first ?? k.rawValue).lowercased() + "…") { newKind = k; pick = nil }
                            }
                        }
                    }
                }
                if newKind != nil {
                    field("Title") {
                        TextField("What the issue is about", text: $title).textFieldStyle(.plain).ui(14)
                            .padding(.horizontal, 10).frame(height: 32)
                            .background(RoundedRectangle(cornerRadius: Radius.field, style: .continuous).fill(t.card.color))
                    }
                }
                if live.liveAgent != nil && live.session.agent.isAgent {
                    Toggle(live.status == .running ? "Tell the agent (it is working; you will be reminded instead)" : "Tell the agent now",
                           isOn: $tellAgent).ui(12.5)
                }
                if live.session.ticket != nil {
                    Text("It joins the session's issues; closing or reviewing the session offers to move each one to In Review.")
                        .ui(11.5).foregroundStyle(t.text3.color)
                }
            }
            HStack(spacing: 10) {
                if let error { Text(error).ui(12).foregroundStyle(t.needsText.color).lineLimit(2) }
                Spacer()
                if busy { ProgressView().controlSize(.small) }
                RoofButton("Cancel") { close() }.fixedSize().keyboardShortcut(.cancelAction)
                RoofButton(newKind == nil ? "Attach ⌘↩" : "Create and attach ⌘↩", .primary) { attach() }
                    .fixedSize().keyboardShortcut(.return, modifiers: .command).disabled(!valid)
            }
        }
        .padding(24)
        .frame(width: 520)
        .background(t.window.color)
        .onAppear(perform: appear)
    }

    private var issueLabel: String {
        if let k = newKind { return "New " + (k.labelNames.first ?? k.rawValue).lowercased() }
        if let i = pick { return "\(i.identifier) · \(i.shortTitle)" }
        return project == nil ? "Pick a project first" : "Pick an issue"
    }

    private func field<C: View>(_ label: String, @ViewBuilder _ c: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).ui(12, .semibold).foregroundStyle(t.text.color)
            c()
        }
    }

    private func pickProject(_ w: LinearWorkstream) {
        if wsId != w.id { pick = nil }
        wsId = w.id
        model.loadIssues(w)
    }

    /// The session's own project first, else the one New session used last.
    private func appear() {
        model.loadWorkstreams(force: model.linearTeams.isEmpty)
        let open = openProjects
        if let code = live.session.workstream, let w = open.first(where: { $0.wsId == code }) { pickProject(w) }
        else if let last = Prefs.defaults.string(forKey: "newWork.lastWorkstream"), let w = open.first(where: { $0.id == last }) { pickProject(w) }
    }

    private func attach() {
        guard let w = project else { return }
        let team = w.team.isEmpty ? nil : w.team
        if let k = newKind {
            busy = true
            model.createTicket(kind: k, title: title.trimmingCharacters(in: .whitespaces), details: "", in: w, team: team,
                               milestone: nil, planSession: false) { r in
                busy = false
                switch r {
                case .success(let i): finish(i, team: team, w: w)
                case .failure(let e): error = "Linear: \(e)"
                }
            }
        } else if let i = pick {
            finish(i, team: team, w: w)
        }
    }

    private func finish(_ i: LinearIssue, team: String?, w: LinearWorkstream) {
        model.attachIssue(i, team: team, project: w.wsId, to: live, tellAgent: tellAgent)
        close()
    }
}
