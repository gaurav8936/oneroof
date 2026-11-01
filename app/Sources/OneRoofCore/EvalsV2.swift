import Foundation

// LAB-2061 · the Evals redesign (Claude Design handover "Evals v1.0", blended with the owner's Overview). Shapes of the
// engine's new --json answers (roof_eval.py overview · anatomy · items · item · scores; evalset.py show · versions ·
// build --dry-run; judge.py items · queue · trust · advise · rubric · versions) and the pure logic the views use.
// Nothing here draws. Every number shown comes from the engine (HP AGENT_RULES rule 2).

// MARK: - Tabs and navigation

/// The six tabs, in the owner's order (LAB-2061): Overview opens first; HP's Build is named Your evals.
public enum EvalsTabV2: String, CaseIterable, Identifiable, Sendable {
    case howTo, overview, yourEvals, explore, run, results, learn   // LAB-2113: How to first
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .howTo: return "How to"; case .overview: return "Overview"; case .yourEvals: return "Your evals"; case .explore: return "Explore"
        case .run: return "Run"; case .results: return "Results"; case .learn: return "Learn"
        }
    }
    /// ⌃⌥1…⌃⌥7 (How to is 1 since LAB-2113; HP's ⌘1…5 and ⌥⌘1…9 are taken by group-by and workspaces, KeymapV2).
    public var keyDigit: Character { Character(String((Self.allCases.firstIndex(of: self) ?? 0) + 1)) }
    /// ONEROOF_SELFTEST_EVALS_TAB values: each tab's name, plus the drill-downs (question, scores, judge).
    public static func selfTest(_ v: String) -> (tab: EvalsTabV2, drill: String?)? {
        switch v.lowercased() {
        case "how-to", "howto": return (.howTo, nil)
        case "overview": return (.overview, nil)
        case "your-evals", "build", "yourevals": return (.yourEvals, nil)
        case "judge": return (.yourEvals, "judge")
        case "explore", "catalog": return (.explore, nil)
        case "question", "questions": return (.explore, "questions")
        case "scores": return (.explore, "scores")
        case "your-runs": return (.explore, "runs")
        case "run", "runs", "sheet": return (.run, v.lowercased() == "sheet" ? "sheet" : nil)
        case "results": return (.results, nil)
        case "run-detail", "one-run": return (.results, "rundetail")
        case "all-by-all", "allbyall", "matrix": return (.results, "allbyall")
        case "xray", "x-ray": return (.results, "xray")
        case "learn": return (.learn, nil)
        default: return nil
        }
    }
}

/// The page subtitle from real counts: "131 benchmarks · 2 of your evals · 1 judge · 32 finished runs · 1 running".
public enum EvalsSubtitle {
    public static func text(benchmarks: Int?, ownEvals: Int, judges: Int, finished: Int, running: Int) -> String {
        var p: [String] = []
        if let b = benchmarks { p.append("\(b) benchmarks") }
        p.append("\(ownEvals) of your evals")
        p.append("\(judges) \(judges == 1 ? "judge" : "judges")")
        p.append("\(finished) finished \(finished == 1 ? "run" : "runs")")
        if running > 0 { p.append("\(running) running") }
        return p.joined(separator: " · ")
    }
}

// MARK: - Contestants

/// Who a score belongs to (HP EV-2): an agent (its CLI on a model), a model, a model on this Mac, or the baseline.
public struct EvalContestant: Decodable, Equatable, Hashable, Sendable {
    public enum Kind: String, Decodable, Sendable { case agent, model, local, baseline }
    public var kind: Kind
    public var id: String
    public var name: String
    public var agent: String?
    public var model: String?
    /// Agents first, then models, models on this Mac, the no-model baseline (owner, 2026-11-01).
    public var rank: Int { Self.rank(kind) }
    public static func rank(_ k: Kind) -> Int { switch k { case .agent: return 0; case .model: return 1; case .local: return 2; case .baseline: return 3 } }
    public static func tag(_ k: Kind) -> String { switch k { case .agent: return "Agent"; case .model: return "Model"; case .local: return "On this Mac"; case .baseline: return "Baseline" } }
}

// MARK: - Overview (LAB-2062)

public struct EvalOverview: Decodable, Equatable, Sendable {
    public struct Row: Decodable, Equatable, Identifiable, Sendable {
        public var contestant: String
        public var kind: EvalContestant.Kind
        public var agent: String?
        public var model: String?
        public var run: String
        public var score: Double?
        public var ci95: [Double]?
        public var ciMethod: String?
        public var n: Int?
        public var epochs: Int?
        public var cost: Double?
        public var free: Bool
        public var seat: Bool
        public var usdPerRight: Double?
        public var date: String?
        public var id: String { run }
        /// "seat" for agents, "free" for free models, dollars otherwise; nil when unknown.
        public var costText: String {
            if seat { return "seat" }
            if free || cost == 0 { return "free" }
            return cost.map { String(format: "$%.3f", $0) } ?? "–"
        }
    }
    public struct Card: Decodable, Equatable, Identifiable, Sendable {
        public struct Floor: Decodable, Equatable, Sendable { public var right: Int?; public var of: Int? }
        public var key: String
        public var set: String?
        public var version: Int?
        public var task: String?
        public var kind: String?
        public var title: String
        public var cases: Int?
        public var checkedBy: String?
        public var taskFile: String?
        public var floor: Floor?
        public var rows: [Row]
        public var id: String { key }
        public var isOwn: Bool { self.set != nil }
        /// The floor as a share (right / of), for the dashed line on every bar.
        public var floorShare: Double? {
            guard let r = floor?.right, let o = floor?.of, o > 0 else { return nil }
            return Double(r) / Double(o)
        }
        /// "oneroof · fix locator v1 · 20 cases · checked by code".
        public var header: String {
            [title, cases.map { "\($0) cases" }, checkedBy.map { $0 == "code" ? "checked by code" : $0 }].compactMap { $0 }.joined(separator: " · ")
        }
    }
    public struct Change: Decodable, Equatable, Identifiable, Sendable {
        public var text: String
        public var eval: String
        public var contestant: String
        public var delta: Double
        public var ci95: [Double]
        public var verdict: String
        public var runs: [String]
        public var id: String { runs.joined(separator: "|") }
        public var isNoise: Bool { verdict == "noise" }
    }
    public struct Running: Decodable, Equatable, Identifiable, Sendable {
        public var id: String
        public var task: String?
        public var model: String?
        public var status: String?
        public var progress: String
        public var contestant: String?
    }
    public struct Suggestion: Decodable, Equatable, Sendable {
        public struct Target: Decodable, Equatable, Sendable {
            public var tab: String
            public var judge: String?
            public var set: String?
            public var task: String?
            public var epochs: Int?
            public var limit: Int?
        }
        public var rule: String
        public var text: String
        public var target: Target
    }
    public var evals: [Card]
    public var changes: [Change]
    public var running: [Running]
    public var suggestion: Suggestion?
    public var finishedRuns: Int

    /// The engine's order checked (agents, models, on this Mac, baseline; best first) — the scorecard never reorders.
    public static func ordered(_ rows: [Row]) -> [Row] {
        rows.sorted { a, b in
            let ra = EvalContestant.rank(a.kind), rb = EvalContestant.rank(b.kind)
            if ra != rb { return ra < rb }
            return (a.score ?? -1) > (b.score ?? -1)
        }
    }
}

// MARK: - Explore (LAB-2063): catalog extras, anatomy, published scores

extension EvalCatalog {
    /// Benchmarks only (your own sets are counted as "of your evals"): the page subtitle and Explore's footer agree.
    public var benchmarkCount: Int { benchmarks.filter { !$0.isOwn }.count }
    /// "23 of 129" (benchmarks shown of all benchmarks), or "2 of your evals" on the Your evals shelf.
    public static func footer(shown: [EvalBenchmark], total: EvalCatalog, ownShelf: Bool) -> String {
        ownShelf ? "\(shown.filter(\.isOwn).count) of your evals" : "\(shown.filter { !$0.isOwn }.count) of \(total.benchmarkCount)"
    }
}

extension EvalBenchmark {
    /// The topics of "What it tests" (HP E1.1); a benchmark's category maps onto one, the rest stay in More topics.
    public static let topics: [String] = ["Knowledge", "Hard frontier", "Factuality", "Math", "Reasoning", "Code", "Tool use",
                                          "Long context", "Safety", "Instruction following"]
    public var topic: String? {
        switch category {
        case "Knowledge", "Hard frontier", "Factuality", "Reasoning", "Tool use", "Long context", "Instruction following": return category
        case "Math", "Mathematics": return "Math"
        case "Coding", "Code (functions)", "Code (live)", "Software engineering": return "Code"
        case "Safety", "Safeguards": return "Safety"
        default: return nil
        }
    }
    public var isOwn: Bool { category == "Your evals" || shelf == "own" }
    public var isAgentTask: Bool { shelf == "agent" || sandbox || tags.contains("Agent") || category == "General agents" }
    /// The name before its subtitle ("GSM8K: Grade School Math Word Problems" → "GSM8K"), for list rows.
    public var shortName: String {
        let n = name
        guard let r = n.range(of: ": "), n.distance(from: n.startIndex, to: r.lowerBound) >= 3 else { return n }
        return String(n[..<r.lowerBound])
    }
    /// Questions in the default task (the row's mono number).
    public var questionCount: Int? { tasks.first(where: { $0.name == defaultTask })?.samples ?? tasks.first?.samples }
}

/// Explore's left column (HP E1.1): one shelf or topic at a time; graded-by and the two checkboxes AND together.
public struct EvalExploreFilter: Equatable, Sendable {
    public enum Shelf: String, CaseIterable, Sendable { case start = "Start here", own = "Your evals", agent = "Agent tasks", judges = "Judges" }
    public var shelf: Shelf?
    public var topic: String?
    /// A category outside the topics (More topics ▾), so every 1.9.37 category stays reachable.
    public var category: String?
    public var gradedBy: Set<String> = []
    public var noDocker = false
    public var ranIt = false
    public var search = ""
    public init(shelf: Shelf? = nil, topic: String? = nil, category: String? = nil, gradedBy: Set<String> = [], noDocker: Bool = false,
                ranIt: Bool = false, search: String = "") {
        self.shelf = shelf; self.topic = topic; self.category = category; self.gradedBy = gradedBy; self.noDocker = noDocker
        self.ranIt = ranIt; self.search = search
    }

    /// `ran`: the task names this Mac has run.
    public func apply(_ bs: [EvalBenchmark], ran: Set<String> = []) -> [EvalBenchmark] {
        let q = search.trimmingCharacters(in: .whitespaces).lowercased()
        return bs.filter { b in
            let shelfOK: Bool
            switch shelf {
            case .start?: shelfOK = b.isStarter
            case .own?: shelfOK = b.isOwn
            case .agent?: shelfOK = b.isAgentTask
            case .judges?: shelfOK = false   // judges are listed on their own (they are yours, not benchmarks)
            case nil: shelfOK = true
            }
            return shelfOK && (topic == nil || b.topic == topic) && (category == nil || b.category == category)
                && (gradedBy.isEmpty || gradedBy.contains(b.gradedBy ?? ""))
                && (!noDocker || !b.sandbox) && (!ranIt || b.tasks.contains { ran.contains($0.name) || ran.contains(EvalBenchmark.taskLabel($0.name)) })
                && (q.isEmpty || [b.folder, b.name, b.description, b.category, b.madeOf ?? "", b.tags.joined(separator: " "),
                                  b.tasks.map(\.name).joined(separator: " ")].joined(separator: " ").lowercased().contains(q))
        }
    }

    public static func count(_ bs: [EvalBenchmark], shelf: Shelf) -> Int { EvalExploreFilter(shelf: shelf).apply(bs).count }
    public static func count(_ bs: [EvalBenchmark], topic: String) -> Int { bs.filter { $0.topic == topic }.count }
    /// Categories with no topic row, for More topics.
    public static func otherCategories(_ bs: [EvalBenchmark]) -> [String] {
        Array(Set(bs.filter { $0.topic == nil && !$0.isOwn }.map(\.category))).sorted()
    }
}

public struct EvalAnatomy: Decodable, Equatable, Sendable {
    public struct Step: Decodable, Equatable, Sendable { public var title: String; public var body: String }
    public struct Headroom: Decodable, Equatable, Sendable {
        public var level: String
        public var text: String
        public var best: Double
        public var contestant: String
        public var sourceName: String
        public var checked: String?
        public var saturated: Bool { level == "saturated" }
    }
    public var benchmark: String
    public var task: String
    public var title: String
    public var summary: String?
    public var category: String?
    public var maker: String?
    public var year: Int?
    public var questions: Int?
    public var questionsNote: String?
    public var answerFormat: String?
    public var gradedBy: String?
    public var gradedByLabel: String?
    public var judge: String?
    public var chance: String?
    public var madeOf: String?
    public var promptTemplate: String?
    public var fewShot: Int?
    public var watchOut: [String]?
    public var teaches: String?
    public var paper: String?
    public var dataset: String?
    public var gated: Bool?
    public var termsUrl: String?
    public var marking: String?
    public var lesson: String?
    public var needs: [String]?
    public var steps: [Step]
    public var headroom: Headroom?
    /// "Hard frontier · Center for AI Safety & Scale AI · 2025" (unknown parts left out).
    public var eyebrow: String { [category, maker, year.map(String.init)].compactMap { $0 }.joined(separator: " · ") }
    /// The five facts tiles, unknown ones hidden (HP: "hide the cell when unknown").
    public var facts: [(label: String, value: String)] {
        var f: [(String, String)] = []
        if let q = questions { f.append(("Questions", "\(q.formatted())" + (questionsNote.map { " \($0)" } ?? ""))) }
        if let a = answerFormat { f.append(("Answer", a)) }
        if let g = gradedByLabel { f.append(("Graded by", g)) }
        if let c = chance { f.append(("Chance", c)) }
        if let h = headroom { f.append(("Headroom", h.text)) }
        return f
    }
}

public struct EvalPublishedScores: Decodable, Equatable, Sendable {
    public struct Source: Decodable, Equatable, Sendable { public var name: String; public var url: String }
    public struct Row: Decodable, Equatable, Identifiable, Sendable {
        public var contestant: String
        public var kind: String
        public var score: Double
        public var metric: String?
        public var setting: String?
        public var sourceUrl: String
        public var sourceName: String
        public var published: String?
        public var checked: String
        public var plusMinus: Double?
        public var stale: Bool?
        public var id: String { contestant }
    }
    public struct Failure: Decodable, Equatable, Sendable { public var date: String; public var reason: String }
    public var benchmark: String
    public var hasSource: Bool
    public var source: Source?
    public var rows: [Row]
    public var checked: String?
    public var failed: Failure?
    /// Agents first when the source reports agent harnesses, best first otherwise (the engine sorts by score).
    public var ordered: [Row] { rows.sorted { ($0.kind == "agent" ? 0 : 1, -$0.score) < ($1.kind == "agent" ? 0 : 1, -$1.score) } }
}

/// The red note under small runs (HP RangeWarning): "Both runs used 2 questions. 100 % on 2 still allows anything from
/// 34 % to 100 %." Built from the engine's own Wilson range, so the words match the bar.
public enum EvalRangeWarning {
    public static func text(_ runs: [(score: Double, n: Int)]) -> String? {
        let small = runs.filter { EvalStats.isSmall($0.n) }
        guard let first = small.first else { return nil }
        let (lo, hi) = EvalStats.wilson(first.score, n: first.n)
        let who = small.count == runs.count && runs.count > 1
            ? (Set(small.map(\.n)).count == 1 ? (runs.count == 2 ? "Both runs" : "All \(runs.count) runs") + " used \(first.n) questions."
                                               : "These runs used under 30 questions.")
            : (small.count == 1 ? "A run used \(first.n) questions." : "\(small.count) runs used under 30 questions.")
        return "\(who) \(pct(first.score)) on \(first.n) still allows anything from \(pct(lo)) to \(pct(hi))."
    }
    static func pct(_ x: Double) -> String { "\(Int((x * 100).rounded())) %" }
}

// MARK: - Questions (LAB-2064)

/// `items` answers either a page of questions or what is needed first (a download confirm, or the dataset's terms).
public struct EvalItemsPage: Decodable, Equatable, Sendable {
    public struct Dot: Decodable, Equatable, Sendable { public var run: String; public var score: Double? }
    public struct Item: Decodable, Equatable, Identifiable, Sendable {
        public var id: String
        public var index: Int
        public var input: String
        public var target: String
        public var solution: String?
        public var image: Bool?
        public var dots: [Dot]
    }
    public struct RunRef: Decodable, Equatable, Sendable { public var id: String; public var contestant: String }
    public struct Counts: Decodable, Equatable, Sendable { public var all: Int; public var seen: Int; public var wrong: Int }
    public var task: String
    // A page:
    public var total: Int?
    public var shown: Int?
    public var offset: Int?
    public var seed: Int?
    public var filter: String?
    public var counts: Counts?
    public var runs: [RunRef]?
    public var items: [Item]?
    // Or what is needed first:
    public var needsDownload: Bool?
    public var gated: Bool?
    public var dataset: String?
    public var termsUrl: String?
    public var sizeBytes: Int?
    public var alreadyOnMac: Bool?
    public var isPage: Bool { items != nil }
    /// "Download GSM8K's questions (2.3 MB) to this Mac?" — the one-line confirm before the first download.
    public var confirmLine: String {
        let what = dataset ?? task
        if alreadyOnMac == true { return "Load the questions of \(what) on this Mac (already downloaded by an earlier run)?" }
        return "Download the questions of \(what)" + (sizeBytes.map { " (\(Self.bytes($0)))" } ?? " (size unknown)") + " to this Mac?"
    }
    public static func bytes(_ n: Int) -> String {
        let f = ByteCountFormatter(); f.countStyle = .file
        return f.string(fromByteCount: Int64(n))
    }
}

public struct EvalItemDetail: Decodable, Equatable, Sendable {
    public struct Message: Decodable, Equatable, Sendable { public var role: String; public var text: String }
    public struct Prompt: Decodable, Equatable, Sendable {
        public var messages: [Message]?
        public var template: String?
        public var source: String
        public var fewShot: Int?
    }
    public struct Marking: Decodable, Equatable, Sendable { public var scorer: String; public var text: String }
    public struct RunAnswer: Decodable, Equatable, Identifiable, Sendable {
        public var run: String
        public var epoch: Int
        public var contestant: String?
        public var kind: EvalContestant.Kind?
        public var model: String?
        public var score: Double?
        public var answer: String?
        public var answerTail: String
        public var id: String { "\(run)#\(epoch)" }
        public var right: Bool { (score ?? 0) >= 1 }
    }
    public var id: String
    public var index: Int
    public var task: String
    public var input: String
    public var target: String
    public var solution: String?
    public var image: Bool?
    public var dataset: String?
    public var split: String?
    public var prompt: Prompt?
    public var marking: [Marking]
    public var lesson: String?
    public var runs: [RunAnswer]
    public var noReference: Bool?
    /// "gsm8k · test · #1".
    public var locator: String { [task, split, "#\(index)"].compactMap { $0 }.joined(separator: " · ") }
}

// MARK: - Your evals (LAB-2065)

public struct EvalSetList: Decodable, Equatable, Sendable {
    public struct Entry: Decodable, Equatable, Identifiable, Sendable {
        public var name: String
        public var version: Int
        public var kind: String
        public var repo: String
        public var count: Int
        public var built: String
        public var versions: Int
        public var taskFile: String
        /// The repo the set was built from (X-ray's repo menu, LAB-2068); sets built before it was kept have none.
        public var repoPath: String?
        public var id: String { name }
        public var kindTitle: String { kind == "triage" ? "bug triage" : kind == "fix-locator" ? "fix locator" : kind }
        public var checkedBy: String { kind == "triage" ? "judged" : "checked by code" }
        /// "oneroof · fix locator".
        public var title: String { "\(repo) · \(kindTitle)" }
    }
    public var sets: [Entry]
}

public struct EvalSetDetail: Decodable, Equatable, Sendable {
    public struct Case: Decodable, Equatable, Identifiable, Sendable {
        public struct Solved: Decodable, Equatable, Sendable { public var right: Int; public var runs: Int }
        public var id: String
        public var issue: String?
        public var report: String
        public var files: [String]
        public var date: String?
        public var solvedBy: Solved
    }
    public struct Best: Decodable, Equatable, Sendable { public var score: Double; public var contestant: String; public var run: String; public var n: Int }
    public struct Floor: Decodable, Equatable, Sendable { public var right: Int; public var of: Int }
    public struct Stats: Decodable, Equatable, Sendable { public var commitsConsidered: Int? }
    public var name: String
    public var version: Int
    public var kind: String
    public var repo: String
    public var repoPath: String?
    public var count: Int
    public var days: Int?
    public var built: String
    public var frozen: String?
    public var taskFile: String
    public var description: String?
    public var cases: [Case]
    public var runs: Int
    public var best: Best?
    public var floor: Floor
    public var stats: Stats?
    public var versions: [Int]?
    public var kindTitle: String { kind == "triage" ? "bug triage" : kind == "fix-locator" ? "fix locator" : kind }

    public enum Sort: String, CaseIterable, Sendable { case hardest = "hardest first", newest = "newest", issue = "issue" }
    /// Hardest first: fewest right, then most runs seen; newest: fix date; issue: key order.
    public func sorted(_ s: Sort) -> [Case] {
        switch s {
        case .hardest: return cases.sorted { a, b in
            let ra = a.solvedBy.runs > 0 ? Double(a.solvedBy.right) / Double(a.solvedBy.runs) : 2
            let rb = b.solvedBy.runs > 0 ? Double(b.solvedBy.right) / Double(b.solvedBy.runs) : 2
            return ra != rb ? ra < rb : (a.issue ?? "") < (b.issue ?? "")
        }
        case .newest: return cases.sorted { ($0.date ?? "") > ($1.date ?? "") }
        case .issue: return cases.sorted { ($0.issue ?? "").localizedStandardCompare($1.issue ?? "") == .orderedAscending }
        }
    }
    /// "nobody", "5 of 5", "2 of 5", or "not run yet".
    public static func solvedText(_ s: Case.Solved) -> String {
        s.runs == 0 ? "not run yet" : s.right == 0 ? "nobody" : "\(s.right) of \(s.runs)"
    }
}

public struct EvalBuildPreview: Decodable, Equatable, Sendable {
    public struct NewCase: Decodable, Equatable, Identifiable, Sendable {
        public var id: String
        public var issue: String?
        public var report: String
        public var files: [String]
        public var date: String?
    }
    public var name: String
    public var baseVersion: Int?
    public var nextVersion: Int
    public var repo: String
    public var days: Int
    public var kind: String?
    public var reportSource: String
    public var kept: Int
    public var new: [NewCase]
    public var total: Int
    public var leftOut: [String: Int]
    public var considered: Int
    public var written: Bool
    public var version: Int?
    /// "Left out on purpose: 7 reports that already name the file (too easy), 106 fixes touching more than 3 files …".
    public var leftOutText: String {
        // Keys arrive as leak · not_fixed · too_many_files · not_a_fix (or camel-cased by the decoder): compared bare.
        let bare = Dictionary(leftOut.map { ($0.key.replacingOccurrences(of: "_", with: "").lowercased(), $0.value) }, uniquingKeysWith: +)
        let words = [("leak", "reports that already name the file (too easy)"), ("notfixed", "issues still open"),
                     ("toomanyfiles", "fixes touching more than 3 source files"), ("notafix", "commits that are not a fix")]
        let parts = words.compactMap { k, w -> String? in
            guard let n = bare[k], n > 0 else { return nil }
            return "\(n) \(w)"
        }
        return parts.isEmpty ? "Nothing left out." : "Left out on purpose: " + parts.joined(separator: ", ") + "."
    }
}

public struct EvalSetVersions: Decodable, Equatable, Sendable {
    public struct Version: Decodable, Equatable, Identifiable, Sendable {
        public var version: Int
        public var count: Int
        public var built: String?
        public var frozen: String?
        public var runs: Int
        public var id: Int { version }
    }
    public var name: String
    public var versions: [Version]
}

// MARK: - Judges (LAB-2066)

public struct EvalJudgeList: Decodable, Equatable, Sendable {
    public struct Judge: Decodable, Equatable, Identifiable, Sendable {
        public var name: String
        public var mode: String
        public var rubric: String
        public var items: Int
        public var labelled: Int
        public var versions: Int
        public var task: String?
        public var models: [String]?
        /// The newest version's task file (what Run runs to measure it); nil before the first build.
        public var taskFile: String?
        public var id: String { name }
    }
    public var judges: [Judge]
}

public struct EvalJudgeItem: Decodable, Equatable, Identifiable, Sendable {
    public struct Label: Decodable, Equatable, Sendable { public var verdict: String; public var why: String?; public var by: String? }
    public struct Code: Decodable, Equatable, Sendable { public var named: [String]; public var right: Int; public var of: Int; public var hits: [String] }
    public var id: String
    public var issue: String
    public var title: String
    public var report: String
    public var model: String?
    public var run: String?
    public var answer: String
    public var target: String?
    public var labels: [String: Label]
    public var split: String
    public var judge: String?
    public var code: Code?
    public var a: String?
    public var b: String?
    public var mine: Label? { labels["owner"] }
    /// "files named: 1 of 2 right · checked by code".
    public var codeLine: String? { code.map { "files named: \($0.right) of \($0.of) right · checked by code" } }
    /// The fix's files ("The fix changed a.swift, b.swift").
    public var changed: [String] { (target ?? "").split(separator: "\n").map(String.init).filter { !$0.isEmpty } }
}

public struct EvalJudgeQueue: Decodable, Equatable, Sendable {
    public var total: Int
    public var labelled: Int
    public var queue: [EvalJudgeItem]
}

public struct EvalJudgeTrust: Decodable, Equatable, Sendable {
    public var name: String
    public var mode: String
    public var items: Int
    public var labelled: Int
    public var toLabel: Int
    public var examples: Int
    public var run: String?
    public var judgeModel: String?
    public var version: Int?
    public var n: Int
    public var agreement: Double?
    public var tpr: Double?
    public var tnr: Double?
    public var labelPass: Int?
    public var labelFail: Int?
    public var heldBackYours: Int?
    public var reference: String
    public var ready: Bool
    public var reading: String
    public var selfPreference: String?
    public var judgedPassRate: Double?
    /// A trust tile turns red under 70 % (HP AgreementTiles).
    public static func weak(_ rate: Double?) -> Bool { (rate ?? 1) < 0.7 }
    public static func pct(_ x: Double?) -> String { x.map { "\(Int(($0 * 100).rounded())) %" } ?? "–" }
    /// "Not ready to stand in for you" when either rate is under 70 % (HP), or too few of your labels.
    public var verdictLine: String? { ready ? nil : "Not ready to stand in for you" }
    public var tooFew: Bool { (heldBackYours ?? 0) < 10 }
}

public struct EvalJudgeVersions: Decodable, Equatable, Sendable {
    public struct Version: Decodable, Equatable, Identifiable, Sendable {
        public var version: Int
        public var built: String?
        public var rubric: String?
        public var examples: Int?
        public var examplesFrom: String?
        public var heldOut: Int?
        public var runs: Int
        public var agreement: Double?
        public var id: Int { version }
    }
    public var name: String
    public var versions: [Version]
    public var draft: String?
}

/// Labelling with the keyboard (HP E2.2): P pass, F fail, S skip, ↑/↓ move, ⌘Z undo. Single-letter keys only act while
/// the queue has focus, never while the Why field is being typed in.
public enum EvalLabelKey: Equatable, Sendable {
    case pass, fail, skip, previous, next, undo, a, b, tie
    public static func action(_ key: String, command: Bool = false, pairwise: Bool = false, typing: Bool) -> EvalLabelKey? {
        if command { return key.lowercased() == "z" ? .undo : nil }
        if typing { return nil }
        switch key.lowercased() {
        case "p": return pairwise ? nil : .pass
        case "f": return pairwise ? nil : .fail
        case "a": return pairwise ? .a : nil
        case "b": return pairwise ? .b : nil
        case "t": return pairwise ? .tie : nil
        case "s": return .skip
        case "↑", "up": return .previous
        case "↓", "down": return .next
        default: return nil
        }
    }
    public var verdict: String? {
        switch self { case .pass: return "pass"; case .fail: return "fail"; case .a: return "a"; case .b: return "b"; case .tie: return "tie"; default: return nil }
    }
}

/// The engine's JSON with snake_case keys (the new commands answer this way).
extension EvalEngine {
    public static func decodeSnake<T: Decodable>(_ type: T.Type, _ o: Output) -> Result<T, EvalError> {
        if let err = try? JSONDecoder().decode(EvalError.self, from: o.stdout), !err.message.isEmpty { return .failure(err) }
        let d = JSONDecoder(); d.keyDecodingStrategy = .convertFromSnakeCase
        do { return .success(try d.decode(T.self, from: o.stdout)) }
        catch {
            let msg = o.stderr.split(separator: "\n").last.map(String.init) ?? "the engine gave no answer (exit \(o.code))"
            return .failure(EvalError(message: msg.replacingOccurrences(of: "roof eval: ", with: ""), code: Int(o.code)))
        }
    }
}

/// The Agreement tab's table: the judge's verdict × one source's label, on answers the judge never saw as examples.
/// Each cell keeps its item ids so a click shows those answers.
public struct EvalJudgeConfusion: Equatable, Sendable {
    public var judgePassLabelPass: [String] = []
    public var judgePassLabelFail: [String] = []
    public var judgeFailLabelPass: [String] = []
    public var judgeFailLabelFail: [String] = []
    public var n: Int { judgePassLabelPass.count + judgePassLabelFail.count + judgeFailLabelPass.count + judgeFailLabelFail.count }
    /// Agreement, passes good (TPR) and fails bad (TNR), as judge.py reports them.
    public var agreement: Double? { n > 0 ? Double(judgePassLabelPass.count + judgeFailLabelFail.count) / Double(n) : nil }
    public var tpr: Double? { let d = judgePassLabelPass.count + judgeFailLabelPass.count; return d > 0 ? Double(judgePassLabelPass.count) / Double(d) : nil }
    public var tnr: Double? { let d = judgeFailLabelFail.count + judgePassLabelFail.count; return d > 0 ? Double(judgeFailLabelFail.count) / Double(d) : nil }

    public static func from(_ items: [EvalJudgeItem], source: String) -> EvalJudgeConfusion {
        var c = EvalJudgeConfusion()
        for x in items where x.split != "example" {
            guard let j = x.judge, let l = x.labels[source]?.verdict else { continue }
            switch (j, l) {
            case ("pass", "pass"): c.judgePassLabelPass.append(x.id)
            case ("pass", "fail"): c.judgePassLabelFail.append(x.id)
            case ("fail", "pass"): c.judgeFailLabelPass.append(x.id)
            case ("fail", "fail"): c.judgeFailLabelFail.append(x.id)
            default: break
            }
        }
        return c
    }
}
