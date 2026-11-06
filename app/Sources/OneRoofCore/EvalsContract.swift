import Foundation

// LAB-2242 · Evals v2 (One Roof 2.0.4): the engine ↔ Swift JSON of the Evals v2 contract (CONTRACT.md) §1–§7, and the verdict sentences
// of its "Swift side" (EV-9). All new commands answer in snake_case: decode with `EvalEngine.decodeSnake` (or a decoder
// with `.convertFromSnakeCase`). Missing parts are nil, shown as "not recorded"; nothing here draws.

// MARK: - §1 The stamp

/// Who answered, how, on what: written into every 2.0.4 run, derived (`recorded == false`) for older runs.
public struct EvalStamp: Decodable, Equatable, Hashable, Sendable {
    /// model = a model on its own; agentModel = an agent CLI on a model; full = agent + rules "on".
    public enum Layer: String, Decodable, CaseIterable, Sendable {
        case model, agentModel = "agent_model", full
        /// Plain words (handover OVERVIEW.md).
        public var title: String {
            switch self { case .model: return "The model"; case .agentModel: return "The agent using a model"; case .full: return "Your full setup" }
        }
    }
    public var recorded: Bool
    public var layer: Layer?
    public var agent: String?
    public var agentName: String?
    public var agentVersion: String?
    public var model: String?
    public var modelRequested: String?
    /// chosen · cli_default_resolved · cli_default_unknown · api
    public var modelSource: String?
    /// seat:C1 · seat:CX · api:anthropic · … · local · stand-in
    public var runsOn: String?
    /// "off" · "on" · nil (layer model)
    public var rules: String?
    public var rulesHash: String?
    public var rulesCommit: String?
    public var rulesFiles: [String]?
    public var permissionMode: String?
    public var task: String?
    public var taskVersion: Int?
    public var taskCommit: String?
    public var seed: Int?

    public init(recorded: Bool = true, layer: Layer? = nil, agent: String? = nil, agentName: String? = nil, agentVersion: String? = nil,
                model: String? = nil, modelRequested: String? = nil, modelSource: String? = nil, runsOn: String? = nil,
                rules: String? = nil, rulesHash: String? = nil, rulesCommit: String? = nil, rulesFiles: [String]? = nil,
                permissionMode: String? = nil, task: String? = nil, taskVersion: Int? = nil, taskCommit: String? = nil, seed: Int? = nil) {
        self.recorded = recorded; self.layer = layer; self.agent = agent; self.agentName = agentName; self.agentVersion = agentVersion
        self.model = model; self.modelRequested = modelRequested; self.modelSource = modelSource; self.runsOn = runsOn
        self.rules = rules; self.rulesHash = rulesHash; self.rulesCommit = rulesCommit; self.rulesFiles = rulesFiles
        self.permissionMode = permissionMode; self.task = task; self.taskVersion = taskVersion; self.taskCommit = taskCommit; self.seed = seed
    }

    enum CodingKeys: String, CodingKey {
        case recorded, layer, agent, agentName, agentVersion, model, modelRequested, modelSource, runsOn, rules, rulesHash
        case rulesCommit, rulesFiles, permissionMode, task, taskVersion, taskCommit, seed
    }

    /// Tolerant: an unknown layer string decodes as nil (then `effectiveLayer` derives it), `recorded` defaults to false.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        recorded = (try? c.decodeIfPresent(Bool.self, forKey: .recorded)) ?? false
        layer = (try? c.decodeIfPresent(String.self, forKey: .layer)).flatMap { $0.flatMap(Layer.init(rawValue:)) }
        agent = try? c.decodeIfPresent(String.self, forKey: .agent)
        agentName = try? c.decodeIfPresent(String.self, forKey: .agentName)
        agentVersion = try? c.decodeIfPresent(String.self, forKey: .agentVersion)
        model = try? c.decodeIfPresent(String.self, forKey: .model)
        modelRequested = try? c.decodeIfPresent(String.self, forKey: .modelRequested)
        modelSource = try? c.decodeIfPresent(String.self, forKey: .modelSource)
        runsOn = try? c.decodeIfPresent(String.self, forKey: .runsOn)
        rules = try? c.decodeIfPresent(String.self, forKey: .rules)
        rulesHash = try? c.decodeIfPresent(String.self, forKey: .rulesHash)
        rulesCommit = try? c.decodeIfPresent(String.self, forKey: .rulesCommit)
        rulesFiles = try? c.decodeIfPresent([String].self, forKey: .rulesFiles)
        permissionMode = try? c.decodeIfPresent(String.self, forKey: .permissionMode)
        task = try? c.decodeIfPresent(String.self, forKey: .task)
        taskVersion = try? c.decodeIfPresent(Int.self, forKey: .taskVersion)
        taskCommit = try? c.decodeIfPresent(String.self, forKey: .taskCommit)
        seed = try? c.decodeIfPresent(Int.self, forKey: .seed)
    }

    /// Derived, never stored by the app (IMPLEMENTATION_NOTES): rules on → full, an agent → agent using a model, else model.
    public var derivedLayer: Layer { rules == "on" ? .full : (agent != nil || agentName != nil) ? .agentModel : .model }
    /// The engine's layer when it gave one, else derived.
    public var effectiveLayer: Layer { layer ?? derivedLayer }

    /// The part a stamp shows; `value` nil = "not recorded" (shown in the verdict colour).
    public struct Part: Equatable, Sendable {
        public var label: String
        public var value: String?
        public var text: String { value ?? EvalStamp.notRecorded }
    }
    public static let notRecorded = "not recorded"

    /// layer · model · agent (+CLI version) · rules on/off @ hash · task version (BRIEF "Stamp on every score").
    public var parts: [Part] {
        var p: [Part] = [Part(label: "layer", value: (recorded || layer != nil) ? effectiveLayer.title : nil)]
        p.append(Part(label: "model", value: model ?? (modelSource == "cli_default_unknown" ? "CLI default" : nil)))
        if effectiveLayer != .model {
            let name = agentName ?? agent
            p.append(Part(label: "agent", value: name.map { n in agentVersion.map { "\(n) \($0)" } ?? n }))
            if agentVersion == nil { p.append(Part(label: "CLI version", value: nil)) }
            let r: String? = rules.map { $0 == "on" ? "rules on" + (rulesHash.map { " @ \($0)" } ?? "") : "rules off" }
            p.append(Part(label: "rules", value: r))
        }
        p.append(Part(label: "task version", value: taskVersion.map { "v\($0)" }))
        return p
    }
    /// "Claude Code 2.1.31 · claude-opus-5-5 · rules off · v2", with "not recorded" for each missing part.
    public var line: String { parts.map(\.text).joined(separator: " · ") }
    /// Any part missing (the stamp shows in the verdict colour).
    public var hasGaps: Bool { !recorded || parts.contains { $0.value == nil } }
}

// MARK: - §3 Leaderboard by setup (the Compare screen's one call)

public struct EvalSetupLeaderboard: Decodable, Equatable, Sendable {
    public struct Floor: Decodable, Equatable, Sendable {
        public var right: Int
        public var of: Int
        public var rule: String?
        public init(right: Int, of: Int, rule: String? = nil) { self.right = right; self.of = of; self.rule = rule }
        public var share: Double? { of > 0 ? Double(right) / Double(of) : nil }
        /// "a blind guess gets 5" (or "a simple rule with no AI gets 5"): the rule's name before its colon.
        public var text: String {
            let name = rule.flatMap { $0.split(separator: ":", maxSplits: 1).first.map { String($0).trimmingCharacters(in: .whitespaces) } }
            return "\((name?.isEmpty == false ? name! : "a blind guess")) gets \(right)"
        }
    }
    public struct Case: Decodable, Equatable, Identifiable, Sendable {
        public var id: String
        public var issue: String?
        public var title: String?
    }
    public struct StandIn: Decodable, Equatable, Sendable { public var right: Double; public var n: Int }
    public var task: String
    public var version: Int?
    public var title: String?
    public var n: Int?
    /// code · judge · tests
    public var checkedBy: String?
    public var floor: Floor?
    public var cases: [Case]
    public var rows: [EvalSetupRow]
    public var standIn: StandIn?

    /// Finished rows best first, then running / waiting / queued, then failed / expired.
    public var ranked: [EvalSetupRow] {
        rows.enumerated().sorted { a, b in
            let ga = a.element.group, gb = b.element.group
            if ga != gb { return ga < gb }
            let sa = a.element.share ?? -1, sb = b.element.share ?? -1
            return sa != sb ? sa > sb : a.offset < b.offset
        }.map(\.element)
    }
}

/// One setup's row (contract §3): latest finished run per setup on that version, or a running / waiting / queued run.
public struct EvalSetupRow: Decodable, Equatable, Identifiable, Sendable {
    public struct CaseRight: Decodable, Equatable, Sendable {
        public var id: String
        /// Right on every attempt (score 1); nil = not answered.
        public var right: Bool?
        /// The attempts policy (CONTRACT §3 note): the mean over this bug's attempts, 0–1 (0.5 = right on 1 of 2); nil =
        /// not answered. An engine before 2.0.4 sends no score: 1 when right, 0 when wrong.
        public var score: Double?
        public init(id: String, right: Bool?, score: Double? = nil) {
            self.id = id; self.right = right; self.score = score ?? right.map { $0 ? 1 : 0 }
        }
        enum CodingKeys: String, CodingKey { case id, right, score }
        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            let id = try c.decode(String.self, forKey: .id)
            let right = try c.decodeIfPresent(Bool.self, forKey: .right)
            self.init(id: id, right: right, score: try c.decodeIfPresent(Double.self, forKey: .score))
        }
    }
    public var setupId: String
    public var label: String
    public var stamp: EvalStamp?
    /// done · running · waiting · queued · failed · expired
    public var status: String
    public var statusNote: String?
    public var run: String?
    public var started: String?
    /// The sum of the bug scores (the attempts policy): 8 with one attempt, 7.5 when attempts disagree.
    public var right: Double?
    public var n: Int?
    public var lo: Double?
    public var hi: Double?
    public var cost: Double?
    public var costPerRight: Double?
    public var perCase: [CaseRight]
    public var id: String { setupId + "|" + (run ?? status) }

    enum CodingKeys: String, CodingKey {
        case setupId, label, stamp, status, statusNote, run, started, right, n, lo, hi, cost, costPerRight, perCase
    }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        setupId = try c.decode(String.self, forKey: .setupId)
        label = try c.decode(String.self, forKey: .label)
        stamp = try c.decodeIfPresent(EvalStamp.self, forKey: .stamp)
        status = try c.decodeIfPresent(String.self, forKey: .status) ?? "done"
        statusNote = try c.decodeIfPresent(String.self, forKey: .statusNote)
        run = try c.decodeIfPresent(String.self, forKey: .run)
        started = try c.decodeIfPresent(String.self, forKey: .started)
        right = try c.decodeIfPresent(Double.self, forKey: .right)
        n = try c.decodeIfPresent(Int.self, forKey: .n)
        lo = try c.decodeIfPresent(Double.self, forKey: .lo)
        hi = try c.decodeIfPresent(Double.self, forKey: .hi)
        cost = try c.decodeIfPresent(Double.self, forKey: .cost)
        costPerRight = try c.decodeIfPresent(Double.self, forKey: .costPerRight)
        perCase = try c.decodeIfPresent([CaseRight].self, forKey: .perCase) ?? []
    }
    public init(setupId: String, label: String, stamp: EvalStamp? = nil, status: String = "done", run: String? = nil,
                right: Double? = nil, n: Int? = nil, lo: Double? = nil, hi: Double? = nil, perCase: [CaseRight] = []) {
        self.setupId = setupId; self.label = label; self.stamp = stamp; self.status = status; self.run = run
        self.right = right; self.n = n; self.lo = lo; self.hi = hi; self.perCase = perCase
    }

    public var isDone: Bool { status == "done" }
    public var isActive: Bool { ["running", "waiting", "queued"].contains(status) }
    public var share: Double? { guard isDone, let r = right, let n, n > 0 else { return nil }; return r / Double(n) }
    /// Layer from the stamp, else from the setup id ("model:…" → model; "<agent>:<model>:on" → full; else agent).
    public var layer: EvalStamp.Layer {
        if let s = stamp { return s.effectiveLayer }
        if setupId.hasPrefix("model:") { return .model }
        return setupId.hasSuffix(":on") ? .full : .agentModel
    }
    /// "8 of 10", "7.5 of 10" when attempts disagree (nil while not done).
    public var scoreText: String? { guard isDone, let r = right, let n else { return nil }; return "\(EvalScoreText.count(r)) of \(n)" }
    /// "On new bugs, expect 5 to 9".
    public var expectText: String? { guard isDone, let lo, let hi, let n else { return nil }; return EvalVerdicts.expect(lo: lo, hi: hi, n: n) }
    fileprivate var group: Int { isDone ? 0 : isActive ? 1 : 2 }
}

/// Counts under the attempts policy: whole numbers as integers ("8"), a fractional sum with one decimal ("7.5").
public enum EvalScoreText {
    public static func count(_ x: Double) -> String {
        let r = (x * 10).rounded() / 10
        return r == r.rounded() ? String(Int(r)) : String(format: "%.1f", r)
    }
}

// MARK: - §4 Per-case evidence

/// One case of one run: right or wrong, the files the answer named (max 3, in order) and the files the fix changed.
public struct EvalCaseResult: Equatable, Identifiable, Sendable {
    public var id: String
    public var right: Bool?
    public var named: [String]
    public var changed: [String]
    public init(id: String, right: Bool?, named: [String] = [], changed: [String] = []) {
        self.id = id; self.right = right; self.named = named; self.changed = changed
    }
    /// From a `samples <run>` row (score ≥ 1 is right; no score = not answered).
    public init(_ s: EvalSample) {
        self.init(id: s.sampleID, right: s.score.map { $0 >= 1 }, named: s.named ?? [], changed: s.changed ?? [])
    }
    /// The named files the fix really changed.
    public var hits: [String] { named.filter { changed.contains($0) } }
}

// MARK: - §5 Changes

public struct EvalChange: Decodable, Equatable, Identifiable, Sendable {
    public enum Who: String, Decodable, Sendable { case you, vendor }
    public struct Tested: Decodable, Equatable, Sendable {
        public var before: String?
        public var after: String?
        /// Re-review #3: several rules commits fell between the two runs, so the pair covers all of them (short shas,
        /// oldest first) and is credited to none. nil = the pair isolates this one change.
        public var spans: [String]?
        /// The task and task version both runs were on: the floor is read for that version (re-review #5).
        public var task: String?
        public var taskVersion: Int?
        public init(before: String? = nil, after: String? = nil, spans: [String]? = nil, task: String? = nil, taskVersion: Int? = nil) {
            self.before = before; self.after = after; self.spans = spans; self.task = task; self.taskVersion = taskVersion
        }
    }
    public var at: String
    public var who: Who
    public var what: String
    public var path: String?
    public var commit: String?
    public var tested: Tested?
    public var id: String { at + "|" + what }
    /// Not tested yet / tested before only / before and after.
    public var testedBoth: Bool { tested?.before != nil && tested?.after != nil }
    /// A before/after pair that covers several changes together (re-review #3): it can't tell which one moved the score.
    public var isSpan: Bool { testedBoth && (tested?.spans?.count ?? 0) > 1 }
    /// A before/after pair for this change alone: the only kind Changes draws as "did this change help?".
    public var testedAlone: Bool { testedBoth && !isSpan }
    public var date: Date? { ISO8601DateFormatter().date(from: at) }
}

// MARK: - §6 Real history (git)

/// One agent's git history row: commits, lines, and fractions 0–1 (churn, self, revert, fixup).
public struct EvalHistoryRow: Decodable, Equatable, Identifiable, Sendable {
    public var agent: String
    public var commits: Int
    public var lines: Int?
    public var churn: Double?
    /// The share of its churn the agent fixed itself ("self" in the JSON).
    public var selfShare: Double?
    public var revert: Double?
    public var fixup: Double?
    /// LAB-2254: the engine's exact counts when it sends them (the commit lists have exactly this many rows).
    public var fixCount: Int?
    public var revertCount: Int?
    /// Commits with any line rewritten within the horizon (the rewritten % is of lines, this is of commits).
    public var rewrittenCommits: Int?
    public var id: String { agent }
    enum CodingKeys: String, CodingKey {
        case agent, commits, lines, churn, selfShare = "self", revert, fixup
        case fixCount = "followedByFix", revertCount = "reverted", rewrittenCommits
    }
    public init(agent: String, commits: Int, lines: Int? = nil, churn: Double? = nil, selfShare: Double? = nil,
                revert: Double? = nil, fixup: Double? = nil, fixCount: Int? = nil, revertCount: Int? = nil,
                rewrittenCommits: Int? = nil) {
        self.agent = agent; self.commits = commits; self.lines = lines; self.churn = churn; self.selfShare = selfShare
        self.revert = revert; self.fixup = fixup
        self.fixCount = fixCount; self.revertCount = revertCount; self.rewrittenCommits = rewrittenCommits
    }
    /// From today's `xray --json` agent entry (agents keyed by name).
    public init(name: String, _ a: EvalXRay.Agent) {
        self.init(agent: name, commits: a.commits, lines: a.linesAdded, churn: a.churn, selfShare: a.selfChurnShare,
                  revert: a.revertRate, fixup: a.fixupRate, fixCount: a.followedByFix, revertCount: a.reverted,
                  rewrittenCommits: a.rewrittenCommits)
    }
    /// Commits followed by a fix: the engine's exact count, else fixup × commits, rounded (shown with the % too).
    public var followedByFix: Int? { fixCount ?? fixup.map { Int(($0 * Double(commits)).rounded()) } }
    public var reverted: Int? { revertCount ?? revert.map { Int(($0 * Double(commits)).rounded()) } }
    public var isUntagged: Bool { agent == "unattributed" }
    /// "18.8 %" (one decimal; a fraction 0–1).
    public static func pct(_ x: Double?) -> String { x.map { String(format: "%.1f %%", $0 * 100) } ?? "–" }
    public static func from(_ x: EvalXRay) -> [EvalHistoryRow] { x.rows.map { EvalHistoryRow(name: $0.name, $0.agent) } }
}

// MARK: - LAB-2254 · the commits behind a Real history count

/// `xray --repo … --days N --commits fixup|churn|revert [--agent NAME] --json`: the commits one count is made of, each with
/// the later commit(s) that fixed, rewrote or reverted it. The engine builds the count and the list in one pass, so
/// `count == commits.count` == the headline's number.
public struct EvalCommitList: Decodable, Equatable, Sendable {
    public enum Kind: String, CaseIterable, Identifiable, Sendable {
        case fixup, churn, revert
        public var id: String { rawValue }
        /// "followed by a fix" / "rewritten in 14 days" / "reverted": what the list is of.
        public func what(horizon: Int) -> String {
            switch self {
            case .fixup: return "followed by a fix"
            case .churn: return "rewritten in \(horizon) days"
            case .revert: return "reverted"
            }
        }
        /// The words before the later commits: "Fixed by", "Rewritten by", "Reverted by".
        public var byLabel: String {
            switch self {
            case .fixup: return "Fixed by"
            case .churn: return "Rewritten by"
            case .revert: return "Reverted by"
            }
        }
    }
    public struct Later: Decodable, Equatable, Identifiable, Sendable {
        public var sha: String
        public var short: String
        public var subject: String
        public var date: String
        public var agent: String
        public var id: String { sha }
        public init(sha: String, short: String, subject: String, date: String, agent: String) {
            self.sha = sha; self.short = short; self.subject = subject; self.date = date; self.agent = agent
        }
    }
    public struct Commit: Decodable, Equatable, Identifiable, Sendable {
        public var sha: String
        public var short: String
        public var subject: String
        public var date: String
        public var agent: String
        public var repo: String
        public var repoPath: String?
        public var linesRewritten: Int?
        public var by: [Later]
        public var id: String { (repoPath ?? repo) + "@" + sha }
        public init(sha: String, short: String, subject: String, date: String, agent: String, repo: String,
                    repoPath: String? = nil, linesRewritten: Int? = nil, by: [Later] = []) {
            self.sha = sha; self.short = short; self.subject = subject; self.date = date; self.agent = agent; self.repo = repo
            self.repoPath = repoPath; self.linesRewritten = linesRewritten; self.by = by
        }
    }
    public var kind: String
    public var agent: String?
    public var windowDays: Int
    public var horizonDays: Int?
    public var count: Int
    public var commits: [Commit]
    public init(kind: String, agent: String?, windowDays: Int, horizonDays: Int?, count: Int, commits: [Commit]) {
        self.kind = kind; self.agent = agent; self.windowDays = windowDays; self.horizonDays = horizonDays
        self.count = count; self.commits = commits
    }

    /// The engine call (without --json, which `ask` adds).
    public static func args(repos: [String], days: Int, kind: Kind, agent: String) -> [String] {
        ["xray"] + repos.flatMap { ["--repo", $0] } + ["--days", String(days), "--commits", kind.rawValue, "--agent", agent]
    }
    /// The visible button that opens the list (LAB-2255: a button, never a bare link): "See the 12 commits ›".
    public static func seeTitle(_ n: Int) -> String { n == 1 ? "See the commit ›" : "See the \(n) commits ›" }
    /// "Hide the commits" once open.
    public static let hideTitle = "Hide the commits"
    /// "2026-11-03" from the engine's ISO date (the date alone; the time adds nothing here).
    public static func day(_ iso: String) -> String { String(iso.prefix(10)) }
    /// The list's title: "12 of Claude's commits followed by a fix · last 60 days".
    public func title(horizon: Int) -> String {
        let k = Kind(rawValue: kind) ?? .fixup
        let what = k.what(horizon: horizon)
        guard let a = agent, a != "unattributed" else { return "\(count) commits with no agent name \(what) · last \(windowDays) days" }
        return "\(count) of \(a)'s commits \(what) · last \(windowDays) days"
    }
}

// MARK: - §7 Overview layers

public struct EvalOverviewLayer: Decodable, Equatable, Identifiable, Sendable {
    public var layer: EvalStamp.Layer
    public var insideRuns: Int
    public var insideStandIn: Int?
    public var insideWaiting: Int?
    public var outsideRuns: Int
    public var outsideBenchmarks: Int
    public var id: String { layer.rawValue }
    enum CodingKeys: String, CodingKey { case layer, insideRuns, insideStandIn, insideWaiting, outsideRuns, outsideBenchmarks }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        layer = try c.decode(EvalStamp.Layer.self, forKey: .layer)
        insideRuns = try c.decodeIfPresent(Int.self, forKey: .insideRuns) ?? 0
        insideStandIn = try c.decodeIfPresent(Int.self, forKey: .insideStandIn)
        insideWaiting = try c.decodeIfPresent(Int.self, forKey: .insideWaiting)
        outsideRuns = try c.decodeIfPresent(Int.self, forKey: .outsideRuns) ?? 0
        outsideBenchmarks = try c.decodeIfPresent(Int.self, forKey: .outsideBenchmarks) ?? 0
    }
}

// MARK: - Verdicts (CONTRACT "Swift side", EV-9): one function, exactly these sentences

public enum EvalVerdicts {
    /// The fewest shared bugs a winner needs (the engine's MIN_VERDICT_N).
    public static let minShared = EvalStats.minVerdictN

    public enum Kind: String, Equatable, Sendable { case notRun, tooFewShared, better, betterOnlyMatchesFloor, tooFewVsFloor, cantTell, beatsFloor }
    public struct Verdict: Equatable, Sendable {
        public var kind: Kind
        public var text: String
        /// The setup the verdict names as better (nil when none is).
        public var winner: String?
        /// A verdict that calls something (green family); the rest read as "needs" or neutral.
        public var isCall: Bool { kind == .better || kind == .beatsFloor }
    }

    /// One side of a comparison: its plain label and its own score (Wilson range 0–1).
    public struct Side: Equatable, Sendable {
        public var label: String
        /// Right answers under the attempts policy (may be fractional).
        public var right: Double?
        public var n: Int?
        public var lo: Double?
        public var hi: Double?
        public var done: Bool
        public init(label: String, right: Double?, n: Int?, lo: Double?, hi: Double?, done: Bool = true) {
            self.label = label; self.right = right; self.n = n; self.lo = lo; self.hi = hi; self.done = done
        }
        public init(_ r: EvalSetupRow) { self.init(label: r.label, right: r.right, n: r.n, lo: r.lo, hi: r.hi, done: r.isDone) }
    }

    /// A paired difference A − B (fractions 0–1) over `shared` bugs both answered.
    public struct Paired: Equatable, Sendable {
        public var diff: Double
        public var lo: Double
        public var hi: Double
        public var shared: Int
        public init(diff: Double, lo: Double, hi: Double, shared: Int) { self.diff = diff; self.lo = lo; self.hi = hi; self.shared = shared }
        /// From EvalStats.compare: unpaired runs share no bugs, so `shared` is 0 (never a winner).
        public init(_ c: EvalStats.Comparison) { self.init(diff: c.diff, lo: c.lo, hi: c.hi, shared: c.paired ? c.n : 0) }
    }

    /// The headline verdict of A against B:
    /// - "Not run yet" — either side not finished, or no comparison yet;
    /// - "Never a winner under 10 shared bugs" — fewer than 10 shared bugs;
    /// - "<W> is better: +X points (lo to hi)" — the paired 95 % range excludes 0 and the winner's own range clears the floor;
    /// - "<W> is better, but only matches a blind guess" — real, but the winner's range touches the floor;
    /// - "Can't tell yet: about N bugs would settle it" — the paired range includes 0 (N from `power`, or `settle`).
    public static func compare(_ a: Side, _ b: Side, paired: Paired?, floor: Double? = nil, epochs: Int = 1, settle: Int? = nil) -> Verdict {
        guard a.done, b.done, let p = paired else { return Verdict(kind: .notRun, text: "Not run yet", winner: nil) }
        guard p.shared >= minShared else {
            return Verdict(kind: .tooFewShared, text: "Never a winner under \(minShared) shared bugs", winner: nil)
        }
        if p.lo > 0 || p.hi < 0 {
            let aWins = p.lo > 0
            let w = aWins ? a : b
            let (d, lo, hi) = aWins ? (p.diff, p.lo, p.hi) : (-p.diff, -p.hi, -p.lo)
            if let f = floor, let wlo = w.lo, wlo <= f {
                return Verdict(kind: .betterOnlyMatchesFloor, text: "\(w.label) is better, but only matches a blind guess", winner: w.label)
            }
            return Verdict(kind: .better, text: "\(w.label) is better: +\(points(d)) points (\(points(lo)) to \(points(hi)))", winner: w.label)
        }
        let n = settle ?? bugsToSettle(diff: p.diff, epochs: epochs)
        return Verdict(kind: .cantTell, text: "Can't tell yet: about \(n) bugs would settle it", winner: nil)
    }

    /// One setup against the floor: "Not run yet" · "Too few bugs to be sure it beats a blind guess" (its range touches
    /// the floor) · "<A> is better: +X points (lo to hi)" than the guess (range above it). No floor: nil (nothing to say).
    public static func againstFloor(_ a: Side, floor: Double?) -> Verdict? {
        guard a.done, let r = a.right, let n = a.n, n > 0 else { return Verdict(kind: .notRun, text: "Not run yet", winner: nil) }
        guard let f = floor else { return nil }
        let share = r / Double(n)
        let (lo, hi) = (a.lo ?? EvalStats.wilson(share, n: n).lo, a.hi ?? EvalStats.wilson(share, n: n).hi)
        if lo <= f { return Verdict(kind: .tooFewVsFloor, text: "Too few bugs to be sure it beats a blind guess", winner: nil) }
        return Verdict(kind: .beatsFloor, text: "\(a.label) is better: +\(points(share - f)) points (\(points(lo - f)) to \(points(hi - f)))",
                       winner: a.label)
    }

    /// "On new bugs, expect L to H": L = round(lo·n), H = round(hi·n).
    public static func expect(lo: Double, hi: Double, n: Int) -> String {
        let (l, h) = expectRange(lo: lo, hi: hi, n: n)
        return "On new bugs, expect \(l) to \(h)"
    }
    public static func expectRange(lo: Double, hi: Double, n: Int) -> (Int, Int) {
        (Int((lo * Double(n)).rounded()), Int((hi * Double(n)).rounded()))
    }

    /// The bugs that would make a difference this size clear its ± (Wilson half-width at 50 %, as `roof eval power`):
    /// the smallest n whose ± points are at most the difference; 1000 when no n up to 1000 does (or no difference).
    public static func bugsToSettle(diff: Double, epochs: Int = 1, limit: Int = 1000) -> Int {
        let target = abs(diff) * 100
        guard target > 0 else { return limit }
        var n = minShared
        while n < limit {
            if EvalPower.mirror(n: n, epochs: epochs).plusMinusPoints <= target { return n }
            n += 1
        }
        return limit
    }

    /// Points from a fraction: 0.2 → "20", −0.05 → "−5".
    static func points(_ x: Double) -> String {
        let v = Int((x * 100).rounded())
        return v < 0 ? "−\(-v)" : "\(v)"
    }
}
