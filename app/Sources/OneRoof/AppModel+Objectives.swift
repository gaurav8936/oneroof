import AppKit
import OneRoofCore

/// Objectives: the owner types one, a visible planner session writes the plan, the owner edits and approves,
/// then One Roof runs the steps as sessions, in dependency order, at most `stepCap` at a time.
extension AppModel {
    static let stepCap = 3

    var currentObjective: Objective? { objectives.first { $0.id == objectiveId } }

    func saveObjective(_ o: Objective) {
        if let i = objectives.firstIndex(where: { $0.id == o.id }) { objectives[i] = o } else { objectives.append(o) }
        store?.save(o)
    }

    func deleteObjective(_ o: Objective) {
        objectives.removeAll { $0.id == o.id }
        store?.deleteObjective(id: o.id)
        if objectiveId == o.id { objectiveId = nil }
    }

    func createObjective(_ o: Objective, planNow: Bool) {
        saveObjective(o)
        objectiveId = o.id
        if planNow { startPlanner(o) }
    }

    /// Start the planner: a Claude session in a terminal the owner can watch, using the plan-objective skill.
    func startPlanner(_ objective: Objective) {
        var o = objective
        let planPath = o.planPath(common: settings.sharedFolder), runDir = o.runDir(common: settings.sharedFolder)
        try? FileManager.default.createDirectory(atPath: (planPath as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(atPath: runDir, withIntermediateDirectories: true)
        let d = settings.defaults(for: .claude)
        let s = Session(name: "Plan: " + o.title, agent: .claude, account: d.account, repoPath: Workspace.projectsRoot,
                        workstream: o.workstream, objective: "Write the plan for: \(o.title)",
                        openingMessage: PlanParser.plannerPrompt(o, planPath: planPath, runDir: runDir),
                        tags: ["research"], lifecycle: .next, model: d.model.isEmpty ? nil : d.model)
        o.plannerSession = s.id
        o.status = .planning
        saveObjective(o)
        createPlanned(s, launchNow: true)
    }

    /// Re-read the plan file (after the planner, or after the owner edits the Markdown by hand).
    func reloadPlan(_ objective: Objective) {
        var o = objective
        guard let text = try? String(contentsOfFile: o.planPath(common: settings.sharedFolder), encoding: .utf8),
              let plan = PlanParser.parse(text) else { return }
        o.plan = plan
        if o.status == .planning || o.status == .draft { o.status = .review }
        saveObjective(o)
    }

    func updateStep(_ objective: Objective, _ step: PlanStep) {
        var o = objective
        guard let i = o.plan?.steps.firstIndex(where: { $0.id == step.id }) else { return }
        o.plan?.steps[i] = step
        saveObjective(o)
    }

    func removeStep(_ objective: Objective, _ id: String) {
        var o = objective
        o.plan?.steps.removeAll { $0.id == id }
        for i in o.plan?.steps.indices ?? 0..<0 { o.plan?.steps[i].depends?.removeAll { $0 == id } }
        saveObjective(o)
    }

    func moveStep(_ objective: Objective, _ id: String, by delta: Int) {
        var o = objective
        guard var steps = o.plan?.steps, let i = steps.firstIndex(where: { $0.id == id }) else { return }
        let j = min(max(i + delta, 0), steps.count - 1)
        steps.swapAt(i, j)
        o.plan?.steps = steps
        saveObjective(o)
    }

    func approve(_ objective: Objective) {
        var o = objective
        guard o.plan?.steps.isEmpty == false else { return }
        o.status = .running
        saveObjective(o)
        tickObjectives()
    }

    func pause(_ objective: Objective) {
        var o = objective
        o.status = .review
        saveObjective(o)
    }

    /// Every few seconds: pick up finished plans, collect step markers, start steps that are ready.
    func tickObjectives() {
        DispatchQueue.main.async { [self] in
            for var o in objectives {
                switch o.status {
                case .planning:
                    if let text = try? String(contentsOfFile: o.planPath(common: settings.sharedFolder), encoding: .utf8),
                       let plan = PlanParser.parse(text) {
                        o.plan = plan; o.status = .review; saveObjective(o)
                        classifyMissingKinds(o)
                    }
                case .running:
                    if PlanRunner.collectMarkers(&o, runDir: o.runDir(common: settings.sharedFolder)) { saveObjective(o) }
                    guard o.status == .running else { continue }
                    if foundationsLevel == .fail && !foundationsOverride {
                        lastError = "Objective \"\(o.title)\" is waiting: the foundations check has red items (Window › Foundations)."
                        continue
                    }
                    rotateIfNeeded(&o)
                    for step in PlanRunner.toStart(o, cap: Self.stepCap) { startStep(step, of: &o) }
                    saveObjective(o)
                default: break
                }
            }
        }
    }

    /// Steps the planner left without a kind get one from the on-device model.
    func classifyMissingKinds(_ objective: Objective) {
        guard let steps = objective.plan?.steps.filter({ ($0.kind ?? "").isEmpty }), !steps.isEmpty else { return }
        let kinds = RoutingPolicy.kindDescriptions(agenticEngineering: settings.agenticEngineering.path)
        DispatchQueue.global(qos: .utility).async { [weak self] in
            for st in steps {
                guard let k = LocalModel.shared.classify(st.title + ". " + String(st.prompt.prefix(400)), kinds: kinds) else { continue }
                DispatchQueue.main.async {
                    guard let self, let o = self.objectives.first(where: { $0.id == objective.id }) else { return }
                    var s = st; s.kind = k
                    self.updateStep(o, s)
                }
            }
        }
    }

    static let maxRotations = 2

    /// Rotation: a running step whose seat is near its limit is asked for a handoff; when the handoff file
    /// appears, its session is closed and the step restarts on the router's next choice, reading that handoff.
    private func rotateIfNeeded(_ o: inout Objective) {
        guard let plan = o.plan else { return }
        let runDir = o.runDir(common: settings.sharedFolder)
        let policy = routingPolicy()
        for step in plan.steps where PlanRunner.state(of: step, in: o) == .running {
            guard let sid = o.stepSessions[step.id], let item = item(sid) else { continue }
            let handoff = runDir + "/" + step.id + ".handoff"
            if let from = o.rotating[step.id] {
                guard FileManager.default.fileExists(atPath: handoff) else { continue }
                // Handoff written: close the old agent, start the step again elsewhere.
                closeAgent(item, remember: false)
                o.stepSessions[step.id] = nil
                o.rotating[step.id] = nil
                o.rotations[step.id, default: 0] += 1
                var next = step
                let r = route(kind: step.kind, budget: o.budget, avoid: AgentKind(rawValue: from))
                next.agent = r.agent.rawValue; next.account = r.account; next.model = r.model
                next.prompt = step.prompt + "\n\nThis step was started by another agent that ran out of capacity. Read its handoff first: \(handoff). Continue from there; do not redo finished work."
                if let i = o.plan?.steps.firstIndex(where: { $0.id == step.id }) { o.plan?.steps[i] = next }
                lastError = "Rotated \(step.id) of \"\(o.title)\" from \(from) to \(r.agent.displayName): \(r.reason)"
                continue
            }
            // Only when the agent is between turns: One Roof never types into a working agent.
            guard o.rotations[step.id, default: 0] < Self.maxRotations, item.status == .idle || item.status == .done else { continue }
            let seatName = item.session.agent == .claude ? (item.account ?? "Claude1") : item.session.agent == .codex ? "Codex" : nil
            guard let seat = seats.first(where: { $0.seat == seatName && !$0.stale }),
                  (seat.fiveHour ?? 0) >= policy.skipFiveHour || (seat.sevenDay ?? 0) >= policy.skipSevenDay,
                  let agentName = item.liveAgent else { continue }
            o.rotating[step.id] = item.session.agent.rawValue
            let text = "Your usage window is nearly full (\(seat.seat): \(seat.fiveHour.map { "\(Int($0))%" } ?? "?") of 5 h). Stop at a safe point. Write a handoff for the next agent to \(handoff): what is done, what is left, files touched, how to check. Then stop; do not write the .done marker."
            let r = runtime
            DispatchQueue.global().async { try? r.submit(agentName, text: text) }
        }
    }

    private func startStep(_ step: PlanStep, of o: inout Objective) {
        let agent = step.agentKind
        let repo = step.repo.flatMap { Workspace.isInsideProjects($0) ? $0 : nil } ?? o.repoPath
        let runDir = o.runDir(common: settings.sharedFolder)
        let marker = "\n\nWhen this step is finished and its done-when check passes, write a short summary to \(runDir)/\(step.id).done. If it cannot be done, write the reason to \(runDir)/\(step.id).failed. Do not start other steps."
        let prompt = step.prompt.contains(".done") ? step.prompt : step.prompt + marker
        let account = agent == .claude ? (step.account ?? settings.defaults(for: .claude).account) : nil
        let s = Session(name: "\(o.title) · \(step.id) \(step.title)", agent: agent, account: account, repoPath: repo,
                        workstream: o.workstream, objective: step.done_when ?? step.title, openingMessage: prompt,
                        tags: [step.kind ?? "step"].filter { Sticker.resolve($0).builtIn }, lifecycle: .next,
                        startInRepo: repo != Workspace.projectsRoot,
                        agentArgs: o.autoApprove ? agent.autoApproveArgs : [],
                        model: step.model ?? (settings.defaults(for: agent).model.isEmpty ? nil : settings.defaults(for: agent).model))
        o.stepSessions[step.id] = s.id
        createPlanned(s, launchNow: true)
    }
}
