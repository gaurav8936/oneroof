import AppKit
import SwiftUI
import OneRoofCore

/// File › New Objective (⌘⇧O): what, done when, where, how urgent, how much to spend.
struct NewObjectiveSheet: View {
    @ObservedObject var model: AppModel
    let close: () -> Void
    @State private var title = ""
    @State private var doneWhen = ""
    @State private var repo = Workspace.projectsRoot
    @State private var workstream = ""
    @State private var urgency = "week"
    @State private var budget = "normal"
    @State private var notes = ""
    private let repos = [Workspace.projectsRoot] + Workspace.listRepos()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("New objective").font(.system(size: 16, weight: .bold))
            Text("Say what you want and how you'll know it's done. A planner session (a real agent you can watch) writes a plan; you edit and approve it before anything runs.")
                .font(.system(size: 11.5)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Form {
                TextField("Objective", text: $title, prompt: Text("e.g. Help map as a horizontal tree"))
                TextField("Done when", text: $doneWhen, prompt: Text("e.g. map renders left-to-right on desktop and phone"), axis: .vertical).lineLimit(2...3)
                Picker("Repo", selection: $repo) { ForEach(repos, id: \.self) { Text(Workspace.repoLabel(for: $0)).tag($0) } }
                TextField("Workstream", text: $workstream, prompt: Text("optional, e.g. WS-WEB-12"))
                Picker("Urgency", selection: $urgency) { Text("Today").tag("today"); Text("This week").tag("week"); Text("Whenever").tag("whenever") }
                    .pickerStyle(.segmented)
                Picker("Budget", selection: $budget) { Text("Light").tag("light"); Text("Normal").tag("normal"); Text("Whatever it takes").tag("max") }
                    .pickerStyle(.segmented)
                TextField("Notes for the planner", text: $notes, axis: .vertical).lineLimit(2...4)
            }
            .formStyle(.grouped)
            .frame(minHeight: 380)
            HStack {
                Button("Cancel", role: .cancel, action: close).keyboardShortcut(.cancelAction)
                Spacer()
                Button("Save as draft") { save(plan: false) }.disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                Button("Plan it") { save(plan: true) }.keyboardShortcut(.defaultAction).disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(18)
        .frame(width: 560)
    }

    private func save(plan: Bool) {
        let ws = workstream.trimmingCharacters(in: .whitespaces)
        let o = Objective(title: title.trimmingCharacters(in: .whitespaces), doneWhen: doneWhen, repoPath: repo,
                          workstream: ws.isEmpty ? Workspace.workstream(in: title) : ws.uppercased(),
                          urgency: urgency, budget: budget, notes: notes)
        model.createObjective(o, planNow: plan)
        close()
    }
}

/// The objective in the centre: its plan as editable step cards, approve, and live progress.
struct ObjectiveView: View {
    @ObservedObject var model: AppModel
    @Environment(\.colorScheme) private var scheme
    var t: ThemeTokens { model.themes.centre.tokens }

    var body: some View {
        Group {
            if let o = model.currentObjective { content(o) } else { Text("No objective selected").foregroundStyle(t.secondaryText.color) }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(t.background.color)
        .environment(\.colorScheme, model.themes.centre.colorScheme)
    }

    private func content(_ o: Objective) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header(o)
                switch o.status {
                case .draft:
                    banner("Draft. Press Plan it to start the planner session.", "peach")
                    Button("Plan it") { model.startPlanner(o) }.buttonStyle(.borderedProminent)
                case .planning:
                    banner("The planner is writing the plan. Watch it in its terminal; this page fills in when the plan file is ready.", "sky")
                    HStack {
                        if let sid = o.plannerSession {
                            Button("Watch the planner") { model.selectedId = sid; model.objectiveId = nil }
                        }
                        Button("Check for the plan now") { model.reloadPlan(o) }
                    }
                default: EmptyView()
                }
                if let plan = o.plan { planBlock(o, plan) }
            }
            .padding(20)
        }
    }

    private func header(_ o: Objective) -> some View {
        let p = statusPastel(o.status)
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(o.status.rawValue.capitalized).font(.system(size: 10.5, weight: .bold, design: .rounded))
                    .foregroundStyle(p.inkColor(scheme)).padding(.horizontal, 7).padding(.vertical, 2)
                    .background(Capsule().fill(p.fillColor(scheme)))
                if let ws = o.workstream { Text(ws).font(.system(size: 11, weight: .heavy, design: .monospaced)).foregroundStyle(t.accent.color) }
                Text(Workspace.repoLabel(for: o.repoPath)).font(.system(size: 11)).foregroundStyle(t.secondaryText.color)
                Spacer()
                Button { model.openInViewer(o.planPath(common: model.settings.sharedFolder)) } label: {
                    Label("Plan file", systemImage: "doc.text")
                }.disabled(o.plan == nil)
                Menu {
                    Button("Re-plan (new planner session)") { model.startPlanner(o) }
                    Button("Reload plan from file") { model.reloadPlan(o) }
                    Divider()
                    Button("Delete objective", role: .destructive) { model.deleteObjective(o) }
                } label: { Image(systemName: "ellipsis.circle") }
                .menuStyle(.borderlessButton).fixedSize()
                Button { model.objectiveId = nil } label: { Image(systemName: "xmark") }.buttonStyle(.borderless).help("Close")
            }
            Text(o.title).font(.system(size: 22, weight: .bold)).foregroundStyle(t.text.color)
            if !o.doneWhen.isEmpty {
                Label("Done when: \(o.doneWhen)", systemImage: "checkmark.seal").font(.system(size: 12)).foregroundStyle(t.secondaryText.color)
            }
            Text("Urgency \(o.urgency) · budget \(o.budget)").font(.system(size: 11)).foregroundStyle(t.secondaryText.color)
        }
    }

    private func planBlock(_ o: Objective, _ plan: Plan) -> some View {
        let done = plan.steps.filter { PlanRunner.state(of: $0, in: o) == .done }.count
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("PLAN · \(plan.steps.count) STEPS").font(.system(size: 10.5, weight: .heavy)).tracking(0.6).foregroundStyle(t.secondaryText.color)
                if o.status == .running || o.status == .done {
                    ProgressView(value: Double(done), total: Double(max(plan.steps.count, 1))).frame(width: 140)
                    Text("\(done)/\(plan.steps.count) done").font(.system(size: 11)).foregroundStyle(t.secondaryText.color)
                }
                Spacer()
                switch o.status {
                case .review, .failed:
                    Button { model.approve(o) } label: { Label(o.status == .failed ? "Resume" : "Approve and run", systemImage: "play.fill") }
                        .buttonStyle(.borderedProminent).tint(Pastel.named("mint")!.lightInk.color)
                case .running:
                    Button { model.pause(o) } label: { Label("Pause", systemImage: "pause.fill") }
                default: EmptyView()
                }
            }
            if o.status != .done {
                Toggle(isOn: Binding(get: { o.autoApprove }, set: { v in var x = o; x.autoApprove = v; model.saveObjective(x) })) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Steps run without asking per command").font(.system(size: 12, weight: .semibold))
                        Text("Claude auto mode · Codex approve-for-me · Kimi ask-when-needed · Gemini and Antigravity approve everything. Applies to steps started after you switch it.")
                            .font(.system(size: 10.5)).foregroundStyle(t.secondaryText.color).fixedSize(horizontal: false, vertical: true)
                    }
                }
                .toggleStyle(.switch).controlSize(.small)
            }
            if o.status == .review {
                Button { routeAll(o, plan) } label: { Label("Route all steps", systemImage: "arrow.triangle.branch") }
                    .controlSize(.small).help("Let the router pick agent, account and model for every step (rules + capacity)")
                banner("Read the plan, change any agent, model or order, then Approve. Nothing runs before that. Steps run at most \(AppModel.stepCap) at a time, each in its own session.", "butter")
            }
            ForEach(Array(plan.steps.enumerated()), id: \.element.id) { idx, step in
                StepCard(model: model, objective: o, step: step, index: idx, count: plan.steps.count)
            }
            if let r = plan.risks, !r.isEmpty { listBlock("Risks", r) }
            if let q = plan.questions, !q.isEmpty { listBlock("Questions for you", q) }
        }
    }

    private func routeAll(_ o: Objective, _ plan: Plan) {
        var lastCoder: AgentKind?
        for step in plan.steps {
            let r = model.route(kind: step.kind, budget: o.budget, avoid: step.kind == "review" ? lastCoder : nil)
            var s = step
            s.agent = r.agent.rawValue; s.account = r.account; s.model = r.model
            model.updateStep(model.currentObjective ?? o, s)
            if step.kind == "code" { lastCoder = r.agent }
        }
    }

    private func listBlock(_ title: String, _ items: [String]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased()).font(.system(size: 10.5, weight: .heavy)).tracking(0.6).foregroundStyle(t.secondaryText.color)
            ForEach(items, id: \.self) { Text("• " + $0).font(.system(size: 12)).foregroundStyle(t.text.color) }
        }
    }

    private func banner(_ text: String, _ pastel: String) -> some View {
        let p = Pastel.named(pastel)!
        return Text(text).font(.system(size: 12)).foregroundStyle(p.inkColor(scheme))
            .padding(10).frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 10).fill(p.fillColor(scheme)))
    }
}

func statusPastel(_ s: Objective.Status) -> Pastel {
    switch s {
    case .draft: return Pastel.named("stone")!
    case .planning: return Pastel.named("sky")!
    case .review: return Pastel.named("butter")!
    case .running: return Pastel.named("periwinkle")!
    case .done: return Pastel.named("mint")!
    case .failed: return Pastel.named("coral")!
    }
}

/// One plan step: kind, agent and model (editable before approval), dependencies, done-when, cost, live state.
struct StepCard: View {
    @ObservedObject var model: AppModel
    let objective: Objective
    let step: PlanStep
    let index: Int
    let count: Int
    @State private var expanded = false
    @State private var routeReason: String?
    @Environment(\.colorScheme) private var scheme
    var t: ThemeTokens { model.themes.centre.tokens }

    var editable: Bool { objective.status == .review || objective.status == .draft || objective.status == .planning }

    var body: some View {
        let state = PlanRunner.state(of: step, in: objective)
        let sp = stepPastel(state)
        let session = objective.stepSessions[step.id].flatMap { model.item($0) }
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(step.id).font(.system(size: 11, weight: .heavy, design: .monospaced)).foregroundStyle(t.secondaryText.color)
                AgentLogo(agent: step.agentKind, size: 22)
                Text(step.title).font(.system(size: 13, weight: .semibold)).foregroundStyle(t.text.color)
                if let k = step.kind { StickerView(sticker: Sticker.resolve(k), size: 9.5) }
                Spacer()
                if let c = step.cost { Text("cost \(c)").font(.system(size: 10.5)).foregroundStyle(t.secondaryText.color) }
                Text(session.map { $0.status.label } ?? state.rawValue.capitalized)
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(sp.inkColor(scheme)).padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Capsule().fill(sp.fillColor(scheme)))
            }
            HStack(spacing: 10) {
                if editable {
                    Picker("", selection: Binding(get: { step.agentKind }, set: { var s = step; s.agent = $0.rawValue; if $0 != .claude { s.account = nil }; model.updateStep(objective, s) })) {
                        ForEach(AgentKind.allCases.filter(\.isAgent)) { Text($0.displayName).tag($0) }
                    }.labelsHidden().fixedSize()
                    if step.agentKind == .claude {
                        Picker("", selection: Binding(get: { step.account ?? "Claude1" }, set: { var s = step; s.account = $0; model.updateStep(objective, s) })) {
                            ForEach(AccountResolver.choices(for: .claude), id: \.self) { Text($0).tag($0) }
                        }.labelsHidden().fixedSize()
                    }
                    TextField("model", text: Binding(get: { step.model ?? "" }, set: { var s = step; s.model = $0.isEmpty ? nil : $0; model.updateStep(objective, s) }))
                        .textFieldStyle(.roundedBorder).frame(width: 110)
                    Button { suggest() } label: { Label("Suggest", systemImage: "wand.and.stars") }.controlSize(.small)
                        .help("Router: rules from the agentic-engineering folder + each seat's remaining capacity")
                } else {
                    Text([step.agentKind.displayName, step.account, step.model].compactMap { $0 }.joined(separator: " · "))
                        .font(.system(size: 11)).foregroundStyle(t.secondaryText.color)
                }
                if !step.deps.isEmpty {
                    Text("after " + step.deps.joined(separator: ", ")).font(.system(size: 11)).foregroundStyle(t.secondaryText.color)
                }
                Spacer()
                if let s = session {
                    Button("Open session") { model.selectedId = s.id; model.objectiveId = nil }.controlSize(.small)
                }
                if editable {
                    Button { model.moveStep(objective, step.id, by: -1) } label: { Image(systemName: "arrow.up") }.disabled(index == 0).buttonStyle(.borderless)
                    Button { model.moveStep(objective, step.id, by: 1) } label: { Image(systemName: "arrow.down") }.disabled(index == count - 1).buttonStyle(.borderless)
                    Button { model.removeStep(objective, step.id) } label: { Image(systemName: "trash") }.buttonStyle(.borderless)
                }
                Button { expanded.toggle() } label: { Image(systemName: expanded ? "chevron.up" : "chevron.down") }.buttonStyle(.borderless)
            }
            if let r = routeReason {
                Label(r, systemImage: "arrow.triangle.branch").font(.system(size: 11)).foregroundStyle(Pastel.named("periwinkle")!.inkColor(scheme))
            }
            if let d = step.done_when { Label("Done when: \(d)", systemImage: "checkmark.seal").font(.system(size: 11.5)).foregroundStyle(t.secondaryText.color) }
            if let r = objective.stepResults[step.id] {
                Text(r.text).font(.system(size: 11.5)).foregroundStyle(t.text.color).lineLimit(expanded ? nil : 3)
                    .padding(8).frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 8).fill(sp.fillColor(scheme).opacity(0.5)))
            }
            if expanded {
                Text(step.prompt).font(.system(size: 11, design: .monospaced)).foregroundStyle(t.secondaryText.color).textSelection(.enabled)
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(t.surface.color))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(sp.fillColor(scheme), lineWidth: state == .running ? 2 : 0))
    }

    private func suggest() {
        let r = model.route(kind: step.kind, budget: objective.budget)
        var s = step
        s.agent = r.agent.rawValue; s.account = r.account; s.model = r.model
        model.updateStep(objective, s)
        routeReason = r.reason
    }

    private func stepPastel(_ s: PlanRunner.StepState) -> Pastel {
        switch s {
        case .waiting: return Pastel.named("stone")!
        case .ready: return Pastel.named("peach")!
        case .running: return Pastel.named("sky")!
        case .done: return Pastel.named("mint")!
        case .failed: return Pastel.named("coral")!
        }
    }
}
