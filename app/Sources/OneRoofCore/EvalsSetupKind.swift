import Foundation

// LAB-2261 · Evals v3 lane A (One Roof 2.0.5): the 2.0.4 three-layer words (the model · agent using a model · your full
// setup) read as the two kinds of job. Set up a test's switch is One-shot · Agent, with a Rules choice under Agent
// (D4: with our rules by default, clean kept); Our tasks' layer chips become "tested as" chips (D5); All results marks
// each run one-shot · agent · public model · public agent (E4.2). Pure mapping only: the engine still gets the same
// setups (EvalSetupChoice), so `run` is byte-identical for the same choices.

/// Rules for an agent setup (D4). With our rules = the 2.0.4 full-setup layer (the repo's CLAUDE.md / AGENTS.md at HEAD,
/// read-only); clean = the 2.0.4 "agent using a model" layer (no rules files in the case).
public enum EvalSetupRules: String, CaseIterable, Identifiable, Sendable {
    case withRules, clean
    public var id: String { rawValue }
    public var on: Bool { self == .withRules }
    public init(on: Bool) { self = on ? .withRules : .clean }
    /// The Rules switch label in Set up a test.
    public var title: String { self == .withRules ? "With our rules" : "Clean (no rules)" }
}

/// Set up a test, step 2: what the switch shows (one-shot, or agent with a rules value) ⇄ the 2.0.4 layer.
public struct EvalSetupKindChoice: Hashable, Sendable {
    public var kind: EvalJobKind
    /// Only meaningful for agent; one-shot keeps the last agent value so switching back restores it.
    public var rules: EvalSetupRules

    public init(kind: EvalJobKind, rules: EvalSetupRules = .withRules) { self.kind = kind; self.rules = rules }

    /// The sheet opens on Agent with our rules (D4: test the way we use it).
    public static let `default` = EvalSetupKindChoice(kind: .agent, rules: .withRules)

    /// model → one-shot · agent_model → agent, clean · full → agent, with our rules.
    public init(layer: EvalStamp.Layer) {
        switch layer {
        case .model: self.init(kind: .oneShot)
        case .agentModel: self.init(kind: .agent, rules: .clean)
        case .full: self.init(kind: .agent, rules: .withRules)
        }
    }
    /// The 2.0.4 layer this choice lists (one-shot = the model layer).
    public var layer: EvalStamp.Layer { kind == .oneShot ? .model : rules.on ? .full : .agentModel }

    /// Whether a setup row belongs under this choice.
    public func shows(_ c: EvalSetupChoice) -> Bool { c.layer == layer }

    /// Where a pre-filled sheet opens: any agent → Agent, with the first agent's rules; only models → One-shot; nothing → nil.
    public static func opening(_ choices: [EvalSetupChoice]) -> EvalSetupKindChoice? {
        if let a = choices.first(where: { $0.agent != nil }) { return .init(kind: .agent, rules: .init(on: a.rules)) }
        return choices.isEmpty ? nil : .init(kind: .oneShot)
    }

    /// The sheet's valid default (QA m4: never "Start 0 tests"): 2.0.4's defaults, with a seat agent's rules on (D4).
    public static func defaults(task: String?, seatAgents: [String]) -> (choice: EvalSetupKindChoice, choices: [EvalSetupChoice]) {
        let d = EvalSetupChoice.defaults(task: task, seatAgents: seatAgents)
        let cs = d.choices.map { c in c.isSeat ? EvalSetupChoice.seat(c.agent ?? "", model: c.model, rules: true) : c }
        return (opening(cs) ?? .default, cs)
    }

    /// " · 2": how many chosen setups sit under a switch position (kind) or a rules value.
    public static func count(_ choices: [EvalSetupChoice], kind: EvalJobKind) -> Int {
        choices.filter { $0.agent == nil ? kind == .oneShot : kind == .agent }.count
    }
    public static func count(_ choices: [EvalSetupChoice], rules: EvalSetupRules) -> Int {
        choices.filter { $0.agent != nil && $0.rules == rules.on }.count
    }
}

/// Our tasks (E5.1, D5): the 2.0.4 layer chips read as "tested as" chips. A task is testable both ways.
public extension EvalTaskCoverage.Chip {
    /// "model" · "agent clean" · "agent with our rules".
    var testedAs: String {
        switch layer { case .model: return "model"; case .agentModel: return "agent clean"; case .full: return "agent with our rules" }
    }
    var kind: EvalJobKind { layer == .model ? .oneShot : .agent }
}

/// All results (E4.2): a run's kind. Public = a run with no task set of our own (setName nil).
/// The CSV / JSON export is built by the engine (`roof eval export`), which this lane leaves alone.
public enum EvalResultKind: String, CaseIterable, Sendable {
    case oneShot, agent, publicModel, publicAgent
    public var title: String {
        switch self { case .oneShot: return "one-shot"; case .agent: return "agent"; case .publicModel: return "public model"; case .publicAgent: return "public agent" }
    }
    public var jobKind: EvalJobKind { self == .oneShot || self == .publicModel ? .oneShot : .agent }
    public var isPublic: Bool { self == .publicModel || self == .publicAgent }

    /// Public: no set of our own and not one of our tasks by name (an older `own_<set>_vN` run, a grader / labeller study
    /// of our notes are ours, as in the grid's blue columns).
    public static func isPublic(_ r: EvalResult) -> Bool {
        let task = r.task ?? ""
        return r.setName == nil && !task.hasPrefix("own_") && !task.hasPrefix("judge_") && !task.hasPrefix("labeller_")
    }

    public static func of(_ r: EvalResult) -> EvalResultKind {
        let k = EvalJobKind.of(r)
        if isPublic(r) { return k == .agent ? .publicAgent : .publicModel }
        return k == .agent ? .agent : .oneShot
    }
    /// A grid row (one who-answered across columns): its kind when every result agrees; else the job kind alone
    /// (one-shot / agent), since public vs ours is a column. nil for no results.
    public static func row(_ results: [EvalResult]) -> EvalResultKind? {
        let ks = Set(results.map(of))
        if ks.count == 1 { return ks.first }
        let jobs = Set(ks.map(\.jobKind))
        guard jobs.count == 1, let j = jobs.first else { return nil }
        return j == .agent ? .agent : .oneShot
    }
}
