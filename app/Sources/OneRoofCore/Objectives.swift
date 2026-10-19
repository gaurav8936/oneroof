import Foundation

/// An objective the owner types by hand: what, done when, where, how urgent, how much to spend.
/// A planner session turns it into a `Plan`; after approval One Roof runs the steps.
public struct Objective: Codable, Identifiable, Equatable, Sendable {
    public enum Status: String, Codable, Sendable { case draft, planning, review, running, done, failed }

    public var id: String
    public var title: String
    public var doneWhen: String
    public var repoPath: String
    public var workstream: String?
    public var urgency: String          // today · week · whenever
    public var budget: String           // light · normal · max
    public var notes: String
    public var status: Status
    public var createdAt: Date
    /// The One Roof session running the planner.
    public var plannerSession: String?
    public var plan: Plan?
    /// Step id → One Roof session id, once the step has a session.
    public var stepSessions: [String: String]
    /// Steps finished (`.done` marker seen) or failed (`.failed`), with the marker text.
    public var stepResults: [String: StepResult]
    /// How many times a step moved to another agent (rotation), and steps waiting for a handoff.
    public var rotations: [String: Int] = [:]
    public var rotating: [String: String] = [:]      // step id → agent being rotated away from
    /// Step agents start in their auto-approve mode. Off by default; only steps started after it changes.
    public var autoApprove = false

    public init(id: String = UUID().uuidString, title: String, doneWhen: String = "", repoPath: String = Workspace.projectsRoot,
                workstream: String? = nil, urgency: String = "week", budget: String = "normal", notes: String = "") {
        self.id = id; self.title = title; self.doneWhen = doneWhen; self.repoPath = repoPath; self.workstream = workstream
        self.urgency = urgency; self.budget = budget; self.notes = notes; self.status = .draft; self.createdAt = Date()
        self.plannerSession = nil; self.plan = nil; self.stepSessions = [:]; self.stepResults = [:]
    }

    enum CodingKeys: String, CodingKey {
        case id, title, doneWhen, repoPath, workstream, urgency, budget, notes, status, createdAt, plannerSession, plan,
             stepSessions, stepResults, rotations, rotating, autoApprove
    }

    public init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        doneWhen = try c.decodeIfPresent(String.self, forKey: .doneWhen) ?? ""
        repoPath = try c.decodeIfPresent(String.self, forKey: .repoPath) ?? Workspace.projectsRoot
        workstream = try c.decodeIfPresent(String.self, forKey: .workstream)
        urgency = try c.decodeIfPresent(String.self, forKey: .urgency) ?? "week"
        budget = try c.decodeIfPresent(String.self, forKey: .budget) ?? "normal"
        notes = try c.decodeIfPresent(String.self, forKey: .notes) ?? ""
        status = try c.decodeIfPresent(Status.self, forKey: .status) ?? .draft
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        plannerSession = try c.decodeIfPresent(String.self, forKey: .plannerSession)
        plan = try c.decodeIfPresent(Plan.self, forKey: .plan)
        stepSessions = try c.decodeIfPresent([String: String].self, forKey: .stepSessions) ?? [:]
        stepResults = try c.decodeIfPresent([String: StepResult].self, forKey: .stepResults) ?? [:]
        rotations = try c.decodeIfPresent([String: Int].self, forKey: .rotations) ?? [:]
        rotating = try c.decodeIfPresent([String: String].self, forKey: .rotating) ?? [:]
        autoApprove = try c.decodeIfPresent(Bool.self, forKey: .autoApprove) ?? false
    }

    public var slug: String {
        let s = title.lowercased().map { $0.isLetter || $0.isNumber ? $0 : "-" }
        return String(String(s).split(separator: "-").joined(separator: "-").prefix(48))
    }

    /// Plan Markdown lives with the workstream's docs when there is one, else in `<shared>/docs/plans/` (owner D3),
    /// else (no shared folder) in One Roof's own data folder.
    public func planPath(common: String = Workspace.sharedRoot) -> String {
        let day = Objective.dayFormatter.string(from: createdAt)
        if let ws = workstream, let folder = Trackers.docsFolder(for: ws) { return folder + "/plans/\(day)_\(slug).md" }
        let base = Workspace.folderExists(common) ? common + "/docs/plans" : Workspace.appSupport + "/plans"
        return base + "/\(day)_\(slug).md"
    }

    /// Where step agents drop their `.done` / `.failed` markers (the shared folder's git-ignored scratchpad, else
    /// One Roof's own data folder).
    public func runDir(common: String = Workspace.sharedRoot) -> String {
        let base = Workspace.folderExists(common) ? common + "/scratchpad/oneroof-runs/" : Workspace.appSupport + "/runs/"
        return base + id.prefix(8).lowercased()
    }

    static let dayFormatter: DateFormatter = { let f = DateFormatter(); f.dateFormat = "yyyyMMdd"; return f }()
}

public struct StepResult: Codable, Equatable, Sendable {
    public var ok: Bool
    public var text: String
}

public struct Plan: Codable, Equatable, Sendable {
    public var objective: String?
    public var done_when: String?
    public var steps: [PlanStep]
    public var risks: [String]?
    public var questions: [String]?
}

public struct PlanStep: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var title: String
    public var kind: String?
    public var agent: String
    public var account: String?
    public var model: String?
    public var depends: [String]?
    public var done_when: String?
    public var cost: String?
    public var skill: String?
    public var repo: String?
    public var prompt: String

    public var agentKind: AgentKind { AgentKind(rawValue: agent.lowercased()) ?? AgentKind(herdrName: agent) ?? .claude }
    public var deps: [String] { depends ?? [] }
}

public enum PlanParser {
    /// The ```oneroof-plan JSON block from a plan Markdown file.
    public static func parse(_ markdown: String) -> Plan? {
        guard let start = markdown.range(of: "```oneroof-plan") else { return nil }
        let rest = markdown[start.upperBound...]
        guard let end = rest.range(of: "```") else { return nil }
        let json = rest[..<end.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines)
        return try? JSONDecoder().decode(Plan.self, from: Data(json.utf8))
    }

    /// The opening message for the visible planner session.
    public static func plannerPrompt(_ o: Objective, planPath: String, runDir: String) -> String {
        """
        Use the plan-objective skill to plan this objective for One Roof.
        Objective: \(o.title)
        Done when: \(o.doneWhen.isEmpty ? "(not given: propose one)" : o.doneWhen)
        Repo: \(o.repoPath)
        Workstream: \(o.workstream ?? "none")
        Urgency: \(o.urgency) · Budget: \(o.budget)
        Notes: \(o.notes.isEmpty ? "none" : o.notes)
        PLAN FILE: \(planPath)
        RUN DIR: \(runDir)
        Write the plan file (Markdown + the oneroof-plan JSON block), then reply PLAN READY. Do not start any step.
        """
    }
}

/// The deterministic part of running a plan (no model in the loop, an idea taken from Bernstein): which steps are
/// ready, finished or blocked, from the plan, the markers on disk and the cap on parallel steps.
public enum PlanRunner {
    public enum StepState: String, Sendable { case waiting, ready, running, done, failed }

    public static func state(of step: PlanStep, in o: Objective) -> StepState {
        if let r = o.stepResults[step.id] { return r.ok ? .done : .failed }
        if o.stepSessions[step.id] != nil { return .running }
        let depsDone = step.deps.allSatisfy { o.stepResults[$0]?.ok == true }
        return depsDone ? .ready : .waiting
    }

    /// Steps to start now: ready ones, in plan order, up to `cap` running at once.
    public static func toStart(_ o: Objective, cap: Int = 3) -> [PlanStep] {
        guard let plan = o.plan, o.status == .running else { return [] }
        let running = plan.steps.filter { state(of: $0, in: o) == .running }.count
        let ready = plan.steps.filter { state(of: $0, in: o) == .ready }
        return Array(ready.prefix(max(0, cap - running)))
    }

    /// Read markers from the run dir into `stepResults`; returns true if anything changed.
    @discardableResult
    public static func collectMarkers(_ o: inout Objective, runDir: String) -> Bool {
        guard let plan = o.plan else { return false }
        var changed = false
        for s in plan.steps where o.stepResults[s.id] == nil {
            for (ext, ok) in [("done", true), ("failed", false)] {
                let f = runDir + "/" + s.id + "." + ext
                if let text = try? String(contentsOfFile: f, encoding: .utf8) {
                    o.stepResults[s.id] = StepResult(ok: ok, text: text.trimmingCharacters(in: .whitespacesAndNewlines))
                    changed = true
                    break
                }
            }
        }
        if changed {
            if plan.steps.contains(where: { o.stepResults[$0.id]?.ok == false }) { o.status = .failed }
            else if plan.steps.allSatisfy({ o.stepResults[$0.id]?.ok == true }) { o.status = .done }
        }
        return changed
    }
}
