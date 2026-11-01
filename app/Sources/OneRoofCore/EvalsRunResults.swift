import Foundation

// LAB-2061 stage 2 · Run (LAB-2067), Results (LAB-2068) and one run (LAB-2069): the run plan and its engine arguments,
// why Start is disabled, the seats, the leaderboard, history and compare shapes, the words of a verdict, and each
// answer's code check · judge · you. Nothing here draws; every number comes from the engine (HP AGENT_RULES rule 2).

// MARK: - The run plan (moved from the app target so it is testable; 1.9.37's fields unchanged)

/// What Run starts: every task × every contestant, as background runs (they queue in the engine).
public struct EvalRunPlan: Identifiable, Equatable, Sendable {
    public var id = UUID()
    public var benchmark: EvalBenchmark?
    public var tasks: [String]
    public var models: [String]
    public var limit: Int
    public var epochs: Int?
    public var seed: Int?
    public var temperature: Double?
    public var cap: Double
    public var taskArgs: String
    public var place: String        // where code-running benchmarks execute (LAB-2000)
    public var sampleID: String?    // LAB-2064: one question only (Run just this one)
    /// LAB-2067 (HP EV-1): agents on your subscription seats ("claude_code", "codex_cli"), before the models.
    public var agents: [String]
    /// Agents on an API model, billed in dollars ("claude_code@anthropic/claude-haiku-5-5"), shown as Agent · API.
    public var apiAgents: [String]

    public init(id: UUID = UUID(), benchmark: EvalBenchmark? = nil, tasks: [String], models: [String] = ["mockllm/model"],
                limit: Int = 50, epochs: Int? = nil, seed: Int? = 42, temperature: Double? = nil, cap: Double = 2.0,
                taskArgs: String = "", place: String = "local", sampleID: String? = nil, agents: [String] = [],
                apiAgents: [String] = []) {
        self.id = id; self.benchmark = benchmark; self.tasks = tasks; self.models = models; self.limit = limit
        self.epochs = epochs; self.seed = seed; self.temperature = temperature; self.cap = cap; self.taskArgs = taskArgs
        self.place = place; self.sampleID = sampleID; self.agents = agents; self.apiAgents = apiAgents
    }

    /// Who answers: agents on seats first, then agents on API models, then models (owner: agents first).
    public enum Contestant: Hashable, Sendable {
        case seat(agent: String)
        case apiAgent(agent: String, model: String)
        case model(String)
        public var key: String {
            switch self {
            case .seat(let a): return "seat:" + a
            case .apiAgent(let a, let m): return a + "@" + m
            case .model(let m): return m
            }
        }
        public var isSeat: Bool { if case .seat = self { return true }; return false }
        /// "Claude Code", "Codex · claude-haiku-5-5", "gpt-5-mini".
        public var name: String {
            switch self {
            case .seat(let a): return EvalAgents.name(a)
            case .apiAgent(let a, let m): return EvalAgents.name(a) + " · " + EvalModels.short(m)
            case .model(let m): return EvalModels.short(m)
            }
        }
    }

    public var contestants: [Contestant] {
        agents.map { .seat(agent: $0) }
            + apiAgents.compactMap { s in
                let p = s.split(separator: "@", maxSplits: 1).map(String.init)
                return p.count == 2 ? .apiAgent(agent: p[0], model: p[1]) : nil
            }
            + models.map { .model($0) }
    }
    public var runCount: Int { tasks.count * contestants.count }

    /// An own eval set's task file (<evals>/sets/<name>/v<N>/<task>.py): agents on seats can answer these.
    public static func isOwnSet(_ task: String) -> Bool { task.hasSuffix(".py") && task.contains("/sets/") }

    /// The engine's arguments for one task × contestant (`roof eval run … --background --json`).
    public func arguments(task: String, contestant c: Contestant, seatLimit: Double = 90) -> [String] {
        var a = ["run", task]
        switch c {
        case .seat(let agent):
            a += ["--agent", agent, "--seat", EvalAgents.seat(agent) ?? "C1", "--seat-limit", String(Int(seatLimit)),
                  "--limit", String(limit)]
        case .apiAgent(let agent, let m):
            a += ["--model", m, "--agent", agent, "--limit", String(limit), "--max-cost", String(cap)]
        case .model(let m):
            a += ["--model", m, "--limit", String(limit), "--max-cost", String(cap)]
        }
        if let e = epochs { a += ["--epochs", String(e)] }
        if !c.isSeat {
            if let s = seed { a += ["--seed", String(s)] }
            if let t = temperature { a += ["--temperature", String(t)] }
            if !taskArgs.isEmpty { a += ["--task-args", taskArgs] }
            if place != "local" { a += ["--where", place] }
        }
        if let q = sampleID { a += ["--sample-id", q] }
        return a + ["--background", "--json"]
    }

    /// The engine's arguments for the estimate of one task × contestant.
    public func estimateArguments(task: String, contestant c: Contestant, seatLimit: Double = 90) -> [String] {
        var a = ["estimate", task, "--limit", String(limit), "--epochs", String(epochs ?? 1)]
        switch c {
        case .seat(let agent): a += ["--agent", agent, "--seat", EvalAgents.seat(agent) ?? "C1", "--seat-limit", String(Int(seatLimit))]
        case .apiAgent(let agent, let m): a += ["--model", m, "--agent", agent, "--where", place]
        case .model(let m): a += ["--model", m, "--where", place]
        }
        return a + ["--json"]
    }
}

// MARK: - Agents and seats (HP EV-1)

public enum EvalAgents {
    public static let names = ["claude_code": "Claude Code", "codex_cli": "Codex", "opencode": "OpenCode", "kimi_code": "Kimi",
                               "gemini_cli": "Gemini CLI", "antigravity": "Antigravity", "mini_swe_agent": "mini-SWE-agent"]
    public static func name(_ id: String) -> String { names[id] ?? id }
    public static func seat(_ id: String) -> String? { id == "claude_code" ? "C1" : id == "codex_cli" ? "CX" : nil }
    /// Agents that can run on an API model through Inspect (inspect-swe), billed in dollars.
    public static let onAPI = ["claude_code", "codex_cli"]
}

/// One agent in Run's Who column (`doctor --json` "agents").
public struct EvalAgentState: Decodable, Equatable, Identifiable, Sendable {
    public var id: String
    public var name: String
    public var seat: String?
    public var installed: Bool
    public var available: Bool
    public var why: String?
    public var fiveHour: Double?
    public var stale: Bool
    enum CodingKeys: String, CodingKey { case id, name, seat, installed, available, why, stale, fiveHour = "five_hour" }
    /// "C1 · 9 % used", "C1 · seat usage unknown", or why it cannot run.
    public var line: String {
        guard available else { return why ?? "not available" }
        guard let s = seat else { return "" }
        if stale || fiveHour == nil { return "\(s) · seat usage unknown" }
        return "\(s) · \(Int((fiveHour ?? 0).rounded())) % used"
    }
}

extension EvalDoctor {
    /// Decoded beside the rest of doctor's answer (an engine from before 2.0.0 has none: then no agent shows).
    public static func agents(from data: Data) -> [EvalAgentState] {
        struct Wrap: Decodable { var agents: [EvalAgentState]? }
        return (try? JSONDecoder().decode(Wrap.self, from: data))?.agents ?? []
    }
}

// MARK: - What this run can tell you (HP EV-9)

public struct EvalPower: Decodable, Equatable, Sendable {
    public var n: Int
    public var epochs: Int
    public var plusMinusPoints: Double
    public var method: String
    public init(n: Int, epochs: Int, plusMinusPoints: Double, method: String = "wilson") {
        self.n = n; self.epochs = epochs; self.plusMinusPoints = plusMinusPoints; self.method = method
    }

    /// The app's instant mirror of `roof eval power` (Wilson half-width at 50 % over n × epochs), test-locked to the engine.
    public static func mirror(n: Int, epochs: Int, p: Double = 0.5) -> EvalPower {
        let total = max(n * max(epochs, 1), 1)
        let (lo, hi) = EvalStats.wilson(p, n: total)
        return EvalPower(n: n, epochs: max(epochs, 1), plusMinusPoints: ((hi - lo) / 2 * 1000).rounded() / 10)
    }

    /// "20 cases × 3 attempts gives about ±12 points per contestant, so differences smaller than that are noise. Same
    /// cases for everyone, so they can be compared question by question (paired)."
    public func sentence(own: Bool, contestants: Int) -> String {
        let what = own ? (n == 1 ? "case" : "cases") : (n == 1 ? "question" : "questions")
        var s = "\(n) \(what) × \(epochs) \(epochs == 1 ? "attempt" : "attempts") gives about ±\(Int(plusMinusPoints.rounded())) points"
        s += contestants > 1 ? " per contestant, so differences smaller than that are noise." : ", so differences smaller than that are noise."
        if contestants > 1 { s += " Same \(own ? "cases" : "questions") for everyone, so they can be compared question by question (paired)." }
        return s
    }
}

// MARK: - Why Start is disabled (HP E3: over cap, no key, Docker stopped, seat too full)

public enum EvalStartCheck {
    public static func reason(plan: EvalRunPlan, overCap: Bool, missingKeys: [String], sandbox: Bool, placeReady: Bool,
                              place: String, fullSeats: [String], estimating: Bool = false) -> String? {
        if plan.tasks.isEmpty || plan.contestants.isEmpty { return "Pick what and who" }
        if !plan.agents.isEmpty, let t = plan.tasks.first(where: { !EvalRunPlan.isOwnSet($0) }) {
            return "Agents on your seats answer your own sets: untick \(EvalBenchmark.taskLabel(t)) or the agents"
        }
        if let p = missingKeys.first { return "No key for \(p): roof eval providers set \(p) --key-file PATH" }
        if sandbox && !placeReady {
            return place == "local" ? "Docker is stopped: start Docker first" : "\(EvalDoctor.placeTitle(place)) is not set up"
        }
        if let s = fullSeats.first { return "\(s) is too full for this run: wait for its 5-hour window" }
        if overCap { return "Over the cap: lower the questions or raise the cap" }
        if estimating { return nil }
        return nil
    }
}

// MARK: - Estimates (seat fields)

extension EvalEstimate {
    /// "seat" for an agent on a subscription, dollars otherwise.
    public var isSeat: Bool { seat != nil }
}

// MARK: - Results › By eval (HP EV-8)

/// One eval in Results' left column: a version of your set, a judge, or a benchmark task, with its run count.
public struct EvalResultsEntry: Equatable, Identifiable, Sendable {
    public var key: String          // "oneroof@v1" or a task name
    public var set: String?
    public var version: Int?
    public var task: String
    public var runs: Int
    public var failed: Bool         // the latest run failed (or the only one)
    public var own: Bool
    public var latest: String?
    public var id: String { key }

    /// Your evals (sets, then judges) first, newest first within each; then benchmarks by latest run.
    public static func from(_ results: [EvalResult]) -> [EvalResultsEntry] {
        var groups: [String: [EvalResult]] = [:]
        for r in results where !(r.task ?? "").hasPrefix("labeller_") {
            let key = r.setName.map { "\($0)@v\(r.setVersion ?? 1)" } ?? (r.task ?? "?")
            groups[key, default: []].append(r)
        }
        let rows = groups.map { key, rs -> EvalResultsEntry in
            let sorted = rs.sorted { ($0.started ?? "") > ($1.started ?? "") }
            let done = rs.filter { $0.status == "done" }.count
            let own = rs.first?.setName != nil || (rs.first?.task ?? "").hasPrefix("judge_")
            return EvalResultsEntry(key: key, set: rs.first?.setName, version: rs.first?.setVersion, task: rs.first?.task ?? key,
                                    runs: done, failed: sorted.first?.status == "failed", own: own, latest: sorted.first?.started)
        }
        return rows.sorted { a, b in
            if a.own != b.own { return a.own }
            if a.own && (a.set != nil) != (b.set != nil) { return a.set != nil }
            return (a.latest ?? "") > (b.latest ?? "")
        }
    }
}

public struct EvalLeaderboard: Decodable, Equatable, Sendable {
    public struct Judge: Decodable, Equatable, Sendable {
        public var name: String
        public var agreement: Double?
        public var n: Int?
        public var tpr: Double?
        public var tnr: Double?
        public var ready: Bool?
        /// "judge 70 % agree".
        public var badge: String { "judge " + (agreement.map { "\(Int(($0 * 100).rounded())) %" } ?? "–") + " agree" }
    }
    public struct Failed: Decodable, Equatable, Sendable { public var run: String; public var error: String?; public var hint: String? }
    public var key: String
    public var title: String
    public var set: String?
    public var version: Int?
    public var kind: String?
    public var cases: Int?
    public var taskFile: String?
    public var floor: Double?
    public var floorKind: String?
    public var versions: [Int]?
    public var judged: Bool?
    public var rows: [EvalOverview.Row]
    public var runs: Int
    public var judge: Judge?
    public var latestFailed: Failed?
    /// Ranked rows (1, 2, …) and the baseline unranked ("–").
    public var ranked: [(rank: Int?, row: EvalOverview.Row)] {
        var n = 0
        return rows.map { r in
            if r.kind == .baseline { return (nil, r) }
            n += 1
            return (n, r)
        }
    }
    /// "latest run per contestant · 20 cases · bar = 95 % range · dashed line = no-model floor".
    public var subtitle: String {
        var p = ["latest run per contestant"]
        if let c = cases { p.append("\(c) cases") }
        p.append("bar = 95 % range")
        if floor != nil { p.append("dashed line = " + (floorKind ?? "floor")) }
        return p.joined(separator: " · ")
    }
}

public struct EvalHistory: Decodable, Equatable, Sendable {
    public struct Point: Decodable, Equatable, Sendable {
        public var run: String
        public var date: String?
        public var score: Double?
        public var ci95: [Double]?
        public var n: Int?
        public var epochs: Int?
    }
    public struct Series: Decodable, Equatable, Sendable {
        public var contestant: String
        public var kind: EvalContestant.Kind
        public var points: [Point]
    }
    public struct Drop: Decodable, Equatable, Identifiable, Sendable {
        public var contestant: String
        public var id: String
        public var run: String
        public var prevRun: String
        public var delta: Double
        public var possible: Bool
        public var text: String
    }
    public var key: String
    public var series: [Series]
    public var drops: [Drop]
    public var first: String?
    public var last: String?
    public var floor: Double?
    /// "1 possible drop", "2 drops" (the word "possible" only while the paired range includes 0).
    public var dropsLine: String? {
        guard !drops.isEmpty else { return nil }
        let possible = drops.allSatisfy(\.possible)
        return "\(drops.count) \(possible ? "possible " : "")drop\(drops.count == 1 ? "" : "s")"
    }
}

/// `roof eval compare A B --json`: the engine's twin of EvalStats.compare plus the cases only one solved.
public struct EvalCompareResult: Decodable, Equatable, Sendable {
    public var diff: Double
    public var ci95: [Double]
    public var n: Int
    public var paired: Bool
    public var verdict: String   // a | b | noise
    public var onlyA: [String]
    public var onlyB: [String]
    public var tied: Int
    /// Fewer than EvalStats.minVerdictN shared questions: no winner is called (the engine's `too_few`).
    public var tooFew: Bool?
    public init(diff: Double, ci95: [Double], n: Int, paired: Bool, verdict: String, onlyA: [String], onlyB: [String], tied: Int,
                tooFew: Bool? = nil) {
        self.diff = diff; self.ci95 = ci95; self.n = n; self.paired = paired; self.verdict = verdict
        self.onlyA = onlyA; self.onlyB = onlyB; self.tied = tied; self.tooFew = tooFew
    }

    /// The verdict in words (HP E4.1): "Can't tell them apart yet", "Claude Code is better".
    public func headline(a: String, b: String) -> String {
        if tooFew == true { return "Can't tell them apart yet — too few shared questions (\(n))" }
        switch verdict {
        case "a": return "\(a) is better"
        case "b": return "\(b) is better"
        default: return "Can't tell them apart yet"
        }
    }

    /// "Claude Code is ahead by 15 points, but the range crosses zero: 4 cases only it solved, 1 only Codex solved, 15 tied."
    public func sentence(a: String, b: String) -> String {
        let pts = Int((abs(diff) * 100).rounded())
        let lead = diff >= 0 ? a : b, other = diff >= 0 ? b : a
        let onlyLead = diff >= 0 ? onlyA.count : onlyB.count, onlyOther = diff >= 0 ? onlyB.count : onlyA.count
        let head: String
        if pts == 0 { head = "\(a) and \(b) score the same" }
        else if tooFew == true { head = "\(lead) is ahead by \(pts) point\(pts == 1 ? "" : "s"), but on only \(n) \(paired ? "shared " : "")question\(n == 1 ? "" : "s"): too few to call (\(EvalStats.minVerdictN) needed)" }
        else { head = "\(lead) is ahead by \(pts) point\(pts == 1 ? "" : "s")" + (verdict == "noise" ? ", but the range crosses zero" : ", and the range stays clear of zero") }
        let what = paired ? "case" : "question"
        guard paired else { return head + " (unpaired: the runs share no cases, so this is a rough answer)." }
        return head + ": \(onlyLead) \(what)\(onlyLead == 1 ? "" : "s") only \(pts == 0 ? a : "it") solved, \(onlyOther) only \(other) solved, \(tied) tied."
    }
    public var discordant: [String] { onlyA + onlyB }
}

// MARK: - One run (HP EV-10)

extension EvalSample {
    /// The list's filters (HP E4.2): All · Wrong · Judge ≠ you.
    public enum Filter: String, CaseIterable, Sendable { case all = "All", wrong = "Wrong", disagree = "Judge ≠ you" }
    public enum Sort: String, CaseIterable, Sendable { case wrongFirst = "wrong first", id = "id", slowest = "slowest", costliest = "costliest" }
    public var isRight: Bool { (score ?? 0) >= 1 }

    public static func filtered(_ xs: [EvalSample], _ f: Filter, only: Set<String>? = nil) -> [EvalSample] {
        xs.filter { s in
            (only == nil || only!.contains(s.sampleID)) && {
                switch f { case .all: return true; case .wrong: return !s.isRight; case .disagree: return s.disagree == true }
            }()
        }
    }
    public static func sorted(_ xs: [EvalSample], _ s: Sort) -> [EvalSample] {
        switch s {
        case .wrongFirst: return xs.sorted { ($0.isRight ? 1 : 0, $0.sampleID, $0.epoch) < ($1.isRight ? 1 : 0, $1.sampleID, $1.epoch) }
        case .id: return xs.sorted { ($0.sampleID, $0.epoch) < ($1.sampleID, $1.epoch) }
        case .slowest: return xs.sorted { ($0.time ?? 0) > ($1.time ?? 0) }
        case .costliest: return xs.sorted { ($0.inputTokens ?? 0) + ($0.outputTokens ?? 0) > ($1.inputTokens ?? 0) + ($1.outputTokens ?? 0) }
        }
    }
    public static func counts(_ xs: [EvalSample]) -> (all: Int, wrong: Int, disagree: Int) {
        (xs.count, xs.filter { !$0.isRight }.count, xs.filter { $0.disagree == true }.count)
    }
    /// The mono second line: "named Handoff.swift · fix in CodexAdapter.swift", or "answer 52 · expected 52".
    public var summary: String {
        if let c = code, let changed = c.changed, !changed.isEmpty {
            let n = (c.named ?? []).map { ($0 as NSString).lastPathComponent }
            let f = changed.map { ($0 as NSString).lastPathComponent }
            if n.isEmpty { return "vague: no file named" }
            let hit = Set(n).intersection(f)
            return "named " + n.prefix(2).joined(separator: ", ") + (hit.isEmpty ? " · fix in " + f.prefix(2).joined(separator: ", ") : "")
        }
        if let e = error, !e.isEmpty { return "error: " + e }
        return "answer \(answer ?? "–") · expected \(target ?? "–")"
    }
    /// The line under the boxes when the judge and you disagree.
    public var takeaway: String? {
        guard disagree == true, let j = judge?.verdict else { return nil }
        return j == "pass" ? "A case like this, where the judge passes what you failed, is why the judge's score reads high."
                           : "A case like this, where the judge fails what you passed, is why the judge's score reads low."
    }
}

/// HP FactsStrip's third cell: "Agrees with your labels 70 % (n=30), but fails only 53 % of bad answers. Read this score as
/// an upper bound." From the run's judge agreement (LAB-1996 numbers, never invented).
public enum EvalTrustLine {
    public static func text(_ a: EvalJudgeAgreement) -> (heading: String, body: String, trusted: Bool) {
        let pct: (Double?) -> String = { $0.map { "\(Int(($0 * 100).rounded())) %" } ?? "–" }
        var body = "Agrees with \(a.against == "you" ? "your labels" : a.against) \(pct(a.agreement)) (n=\(a.n))"
        let weakBad = (a.tnr ?? 1) < 0.7, weakGood = (a.tpr ?? 1) < 0.7
        if a.mode != "pairwise" && weakBad { body += ", but fails only \(pct(a.tnr)) of bad answers. Read this score as an upper bound." }
        else if a.mode != "pairwise" && weakGood { body += ", but passes only \(pct(a.tpr)) of good answers. Read this score as a lower bound." }
        else { body += "." }
        if !a.trustworthy { body += " Too few of your labels to trust it yet." }
        let trusted = a.trustworthy && !weakBad && !weakGood && (a.agreement ?? 0) >= 0.7
        return ("How far to trust the judge", body, trusted)
    }
}

/// Every one of these is decoded from `samples <run> --json` (HP EV-10); runs from before 2.0.0 have none.
public struct EvalVerdict: Decodable, Equatable, Sendable {
    public var verdict: String
    public var why: String?
    public var named: [String]?
    public var changed: [String]?
    public var isPass: Bool { verdict == "pass" }
}

public struct EvalJudgeItemRef: Decodable, Equatable, Sendable {
    public var judge: String
    public var item: String
}

// MARK: - X-ray (EVO-2: a read-only table in 2.0.0)

/// `roof eval xray --repo … --days 30 --json` (snake_case): per agent, how much of its work survives in git.
public struct EvalXRay: Decodable, Equatable, Sendable {
    public struct Agent: Decodable, Equatable, Sendable {
        public var commits: Int
        public var linesAdded: Int
        public var matureCommits: Int?
        public var churn: Double?
        public var selfChurnShare: Double?
        public var revertRate: Double?
        public var fixupRate: Double?
    }
    public var windowDays: Int
    public var horizonDays: Int?
    public var computed: String?
    public var agents: [String: Agent]
    /// Agents by commits, "unattributed" (a person, or an agent that does not sign) last.
    public var rows: [(name: String, agent: Agent)] {
        agents.map { ($0.key, $0.value) }.sorted { a, b in
            if (a.name == "unattributed") != (b.name == "unattributed") { return b.name == "unattributed" }
            return a.agent.commits > b.agent.commits
        }
    }
    /// One-line definitions shown on hover (LAB-2070 writes the lessons).
    public static let definitions: [String: String] = [
        "Commits": "Commits signed by the agent (Co-Authored-By or author) in the window; merges skipped.",
        "Lines added": "Source lines the agent added in the window (docs, data and generated files left out).",
        "Churn": "Lines it added that a later commit deleted or rewrote within the horizon, ÷ lines it added. Needs commits at least 14 days old.",
        "Fixes own work": "The part of that churn done by the same agent (fixing its own work) rather than by others.",
        "Reverted": "Its commits later reverted ('This reverts commit …') ÷ its commits.",
        "Followed by a fix": "Its commits followed within 3 days by a fix touching a same file ÷ its commits (a proxy, not proof).",
    ]
}

/// `evalset add … --json`: where the answer went ("Added to oneroof_regressions (new version v2)").
public struct EvalSetAddResult: Decodable, Equatable, Sendable {
    public var name: String
    public var version: Int
    public var added: Bool
    public var count: Int
    public var message: String
}

// MARK: - Run again (LAB-2069): the same settings, through Run's estimate and cap

extension EvalRunPlan {
    public static func again(_ r: EvalResult) -> EvalRunPlan {
        let task = r.taskRef ?? r.task ?? "gsm8k"
        let model = r.model ?? "mockllm/model"
        var p = EvalRunPlan(tasks: [task], models: [], limit: r.limitN ?? r.samplesDone ?? 5, epochs: r.epochs, seed: r.seed,
                            temperature: r.temperature, cap: 2.0, place: r.whereRun ?? "local")
        if let a = r.agent, model.hasPrefix("seat/") { p.agents = [a] }
        else if let a = r.agent { p.apiAgents = [a + "@" + model] }
        else { p.models = [model] }
        return p
    }
}
