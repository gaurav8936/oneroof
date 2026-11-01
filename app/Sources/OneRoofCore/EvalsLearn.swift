import Foundation

// LAB-2070 · Learn (Claude Design 1A-8 = HP E5.1): the lessons (Resources/evals/lessons.json, HP EV-12), the Try it
// maths, the "In your runs" example picker, the first-eval checklist and the hover explanations every number in Evals
// links to its lesson with (EvalHover). Pure logic, nothing that draws. App help, not Agentic Engineering content.

// MARK: - Lessons

public struct EvalLesson: Decodable, Equatable, Identifiable, Sendable {
    public struct Link: Decodable, Equatable, Sendable { public var label: String; public var route: String }
    public var id: String
    public var section: String
    public var title: String
    public var body: String
    public var example: String
    /// EvalGlossary ids this lesson carries; the first one's text is the body, the others show under it.
    public var glossary: [String]
    public var widget: String
    public var teaser: String
    public var links: [Link]
    /// One extra paragraph after the body (a caveat the glossary text leaves out).
    public var more: String?
}

public struct EvalLessonBook: Decodable, Equatable, Sendable {
    public struct Section: Decodable, Equatable, Sendable { public var id: String; public var title: String }
    public var sections: [Section]
    public var lessons: [EvalLesson]

    public static func decode(_ data: Data) -> EvalLessonBook? { try? JSONDecoder().decode(EvalLessonBook.self, from: data) }

    /// The bundled lessons (Resources/evals/lessons.json, or app/Resources/evals in a checkout).
    public static func bundled(resources: String? = Bundle.main.resourcePath) -> EvalLessonBook? {
        guard let p = AppResources.path(bundled: "evals/lessons.json", checkout: "app/Resources/evals/lessons.json", resources: resources),
              let d = FileManager.default.contents(atPath: p) else { return nil }
        return decode(d)
    }

    public func lesson(_ id: String) -> EvalLesson? { lessons.first { $0.id == id } }
    public func lessons(in section: String) -> [EvalLesson] { lessons.filter { $0.section == section } }
    public func sectionTitle(_ id: String) -> String { sections.first { $0.id == id }?.title ?? id }

    /// "Reading a score · 2 of 6".
    public func position(_ id: String) -> String {
        guard let l = lesson(id) else { return "" }
        let inSection = lessons(in: l.section)
        let i = (inSection.firstIndex { $0.id == id } ?? 0) + 1
        return "\(sectionTitle(l.section)) · \(i) of \(inSection.count)"
    }

    public func next(after id: String) -> EvalLesson? {
        guard let i = lessons.firstIndex(where: { $0.id == id }), i + 1 < lessons.count else { return nil }
        return lessons[i + 1]
    }

    /// "16 lessons · 4 done · each one opens in the app where it applies".
    public func subtitle(done: Set<String>) -> String {
        "\(lessons.count) lessons · \(lessons.filter { done.contains($0.id) }.count) done · each one opens in the app where it applies"
    }
}

/// Where a lesson's "Where this shows up" links go. The Python tests read this list to check lessons.json.
public enum EvalLessons {
    public static let knownRoutes = ["overview", "your-evals", "your-evals/judge", "explore", "explore/anatomy",
                                     "explore/questions", "explore/scores", "run", "results", "results/compare",
                                     "results/all-by-all", "results/run"]

    /// A question's "Lesson:" line (from the benchmark's anatomy) → the lesson it is about.
    public static func forMarking(_ text: String) -> String {
        let s = text.lowercased()
        if s.contains("judge") || s.contains("grader") { return "judges" }
        if s.contains("pass@") || s.contains("tests") { return "passk" }
        if s.contains("contamina") { return "contamination" }
        if s.contains("chance") || s.contains("guess") { return "accuracy-chance" }
        return "exact-match"
    }
}

// MARK: - Try it maths (all local: no runs, no cost)

public enum EvalLessonMath {
    /// RangeExplorer (HP): questions 5 · 10 · 20 · 50 · 200 · 1000 at 80 % right.
    public static let rangeNs = [5, 10, 20, 50, 200, 1000]
    public static func range(p: Double = 0.8, n: Int) -> (lo: Double, hi: Double) { EvalStats.wilson(p, n: n) }
    /// "67–89 %".
    public static func rangeText(_ r: (lo: Double, hi: Double)) -> String {
        "\(Int((r.lo * 100).rounded()))–\(Int((r.hi * 100).rounded())) %"
    }
    public static func rangeNote(n: Int) -> String {
        switch n {
        case ..<10: return "A handful of questions: the score could be almost anything."
        case ..<30: return "Under 30 questions: One Roof marks ranges like this as wide."
        case ..<100: return n == 50 ? "One Roof's default first run on a benchmark." : "Enough for a first look."
        case ..<500: return "A real measurement: differences of 10 points start to show."
        default: return "Narrow: only small differences stay hidden."
        }
    }

    /// Accuracy and chance: guessing among `options` scores 1 / options; a score's share of the way from chance to 100 %.
    public static func chance(options: Int) -> Double { 1 / Double(max(options, 1)) }
    public static func aboveChance(score: Double, options: Int) -> Double {
        let c = chance(options: options)
        return c >= 1 ? 0 : (score - c) / (1 - c)
    }

    /// Standard error of a proportion, sqrt(p(1−p)/n), and the score ± 2 standard errors.
    public static func stderr(p: Double, n: Int) -> Double { n > 0 ? (p * (1 - p) / Double(n)).squareRoot() : 0 }

    /// Is the difference real: two runs of n questions, A right on round(a·n), B on round(b·n). Paired: both are right
    /// on the easiest questions first (as close as two models can be). Unpaired: no questions shared. The verdict is
    /// EvalStats.compare's own, on those made-up answers.
    public static func compare(a: Double, b: Double, n: Int, paired: Bool) -> EvalStats.Comparison? {
        let ka = Int((a * Double(n)).rounded()), kb = Int((b * Double(n)).rounded())
        func run(_ k: Int, _ prefix: String) -> [EvalSample] {
            (0..<n).map { EvalSample(sampleID: prefix + String($0), epoch: 1, score: $0 < k ? 1 : 0) }
        }
        return EvalStats.compare(run(ka, paired ? "q" : "a"), run(kb, paired ? "q" : "b"))
    }

    /// pass@k when each attempt passes on its own with chance p: 1 − (1 − p)^k.
    public static func passAtK(p: Double, k: Int) -> Double { 1 - pow(1 - p, Double(max(k, 1))) }

    /// What a judge reports when the true pass rate is p and it passes good answers with tpr, fails bad ones with tnr.
    public static func judged(p: Double, tpr: Double, tnr: Double) -> Double { p * tpr + (1 - p) * (1 - tnr) }

    public static func costPerSolved(costPerTry: Double, rate: Double) -> Double? { rate > 0 ? costPerTry / rate : nil }

    /// Headroom levels, the engine's (published_scores.headroom): saturated at a best of 90 % or more, lots at 60 % or less.
    public static func headroomLevel(best: Double) -> String { best >= 0.9 ? "saturated" : best <= 0.6 ? "lots" : "some" }
}

// MARK: - GSM8K's marking, mirrored (Inspect match(numeric=True), location "end")

public enum EvalExactMatch {
    /// The answer Inspect reads out of a reply for a numeric target, and whether it equals the target: $ £ € * _ and
    /// thousands commas removed, a full stop that ends a number dropped, then the LAST whitespace-separated word that is
    /// a number, compared as a number (5 significant digits). Words like "seventy-two" and "72%" are not numbers.
    public static func gsm8k(_ reply: String, target: String) -> (read: String, right: Bool) {
        let t = normalize(strip(target.trimmingCharacters(in: .whitespacesAndNewlines))) ?? target
        let words = strip(reply.trimmingCharacters(in: .whitespacesAndNewlines)).split(whereSeparator: \.isWhitespace).map(String.init)
        let read = words.reversed().lazy.compactMap(normalize).first ?? ""
        return (read, !read.isEmpty && read == t)
    }

    static func strip(_ s: String) -> String {
        var x = s.replacingOccurrences(of: #"\\([$,£€*_])"#, with: "$1", options: .regularExpression)
        x = x.replacingOccurrences(of: "[$,£€*_]", with: "", options: .regularExpression)
        return x.replacingOccurrences(of: #"\.(?=\s|$|\D)"#, with: "", options: .regularExpression)
    }

    static func normalize(_ word: String) -> String? {
        let w = word.trimmingCharacters(in: CharacterSet(charactersIn: "!?:;()[]{}'\"`"))
        guard !w.isEmpty, w.allSatisfy({ $0.isASCII }), let v = Double(w), v.isFinite else { return nil }
        return String(format: "%.5g", v)
    }
}

// MARK: - In your runs (real runs from this Mac that show the lesson)

public enum EvalLessonExamples {
    public struct Row: Equatable, Sendable {
        public var run: String
        public var title: String
        public var score: Double
        public var n: Int
        public var lo: Double
        public var hi: Double
        public var small: Bool { EvalStats.isSmall(n) }
        /// "34–100 % · n=2".
        public var rangeText: String { EvalLessonMath.rangeText((lo, hi)) + " · n=\(n)" }
    }

    static func row(_ r: EvalResult) -> Row? {
        guard r.status == "done", let p = r.primary, let v = p.value, p.ciMethod == "wilson", let n = p.n, n > 0 else { return nil }
        let ci = p.ci95.flatMap { $0.count == 2 ? ($0[0], $0[1]) : nil } ?? EvalStats.wilson(v, n: n)
        let who = r.contestant?.name ?? EvalModels.short(r.model ?? "?")
        return Row(run: r.id, title: "\(EvalBenchmark.taskLabel(r.task ?? "?")) × \(who)", score: v, n: n, lo: ci.0, hi: ci.1)
    }

    /// Up to three runs that illustrate the lesson, and one sentence read from them. Range-type lessons pick small-n
    /// runs first and the largest run last (HP: "one small-n and one large-n example").
    public static func pick(_ lesson: String, results: [EvalResult]) -> (rows: [Row], sentence: String?) {
        let done = results.filter { $0.status == "done" }
        let all = done.compactMap(row)
        func smallAndLarge(_ xs: [Row]) -> [Row] {
            let small = xs.filter(\.small).sorted { $0.n < $1.n }.prefix(2)
            let large = xs.filter { !$0.small }.max { $0.n < $1.n }
            return Array(small) + (large.map { [$0] } ?? [])
        }
        switch lesson {
        case "range", "stderr", "accuracy-chance", "first-eval":
            let rows = lesson == "first-eval"
                ? Array(done.filter { $0.task == "gsm8k" }.compactMap(row).prefix(3))
                : smallAndLarge(all)
            return (rows, sentenceRange(rows))
        case "compare", "harness":
            // Two contestants on the same task: the latest run of each, on the task with the most contestants.
            var byTask: [String: [Row]] = [:]
            for r in done { if let x = row(r), let t = r.task, !(byTask[t]?.contains { $0.title == x.title } ?? false) { byTask[t, default: []].append(x) } }
            guard let best = byTask.values.filter({ $0.count >= 2 }).max(by: { $0.count < $1.count }) else { return ([], nil) }
            let rows = Array(best.prefix(3))
            let a = rows[0], b = rows[1]
            let overlap = a.lo <= b.hi && b.lo <= a.hi
            return (rows, overlap
                    ? "\(a.title) and \(b.title): the ranges overlap, so the scores alone do not show which is better. Compare them question by question."
                    : "\(a.title) and \(b.title): the ranges do not overlap, so the difference is very likely real.")
        case "passk", "attempts":
            let rows = Array(done.filter { ($0.epochs ?? 1) > 1 || ($0.primary?.metric.hasPrefix("pass") ?? false) }.compactMap(row).prefix(3))
            return (rows, rows.isEmpty ? nil : "These runs answered each question more than once.")
        case "judges", "labels":
            let js = done.filter { $0.judgeAgreement != nil }
            let rows = Array(js.compactMap(row).prefix(3))
            guard let j = js.first?.judgeAgreement else { return ([], nil) }
            return (rows, "The judge " + j.short + ".")
        case "cost":
            let paid = done.filter { $0.costPerCorrect != nil }.sorted { ($0.costPerCorrect ?? 0) < ($1.costPerCorrect ?? 0) }
            let rows = Array(paid.compactMap(row).prefix(3))
            guard let lo = paid.first, let hi = paid.last, lo.id != hi.id, let a = lo.costPerCorrect, let b = hi.costPerCorrect else { return (rows, nil) }
            return (rows, String(format: "From $%.4f to $%.4f per right answer on this Mac: a %.0f× spread.", a, b, b / max(a, 1e-9)))
        case "golden-sets", "frozen":
            let rows = Array(done.filter { $0.setName != nil }.compactMap(row).prefix(3))
            return (rows, rows.isEmpty ? nil : "Runs on your own sets, each on one frozen version.")
        case "exact-match":
            let rows = Array(done.filter { $0.task == "gsm8k" }.compactMap(row).prefix(3))
            return (rows, rows.isEmpty ? nil : "GSM8K runs: open one and look at how each answer was read.")
        case "saturation":
            let rows = Array(all.filter { $0.score >= 0.9 }.sorted { $0.n > $1.n }.prefix(3))
            return (rows, rows.isEmpty ? nil : "Scores of 90 % or more leave little room above them.")
        default:
            return ([], nil)
        }
    }

    /// Final QA: identical ranges are said once ("each one's range is 34–100 %"), different ones listed "a, b and c".
    static func rangesPhrase(_ ranges: [String]) -> String {
        var seen = Set<String>(); let u = ranges.filter { seen.insert($0).inserted }
        if u.count == 1 { return "each one's range is " + u[0] }
        return "their ranges are " + u.dropLast().joined(separator: ", ") + " and " + u.last!
    }

    /// "The two 100 % runs say almost nothing. The 72 % on 100 questions is a real measurement."
    static func sentenceRange(_ rows: [Row]) -> String? {
        let small = rows.filter(\.small), large = rows.filter { !$0.small }
        var parts: [String] = []
        if !small.isEmpty {
            let ranges = small.map { EvalLessonMath.rangeText(($0.lo, $0.hi)) }
            parts.append(small.count == 1
                         ? "The run on \(small[0].n) question\(small[0].n == 1 ? "" : "s") says almost nothing: its range is \(ranges[0])."
                         : "The \(small.count) runs on fewer than 30 questions say almost nothing: " + Self.rangesPhrase(ranges) + ".")
        }
        if let l = large.first {
            parts.append("The \(EvalStats.pctText(l.score)) on \(l.n) questions is a real measurement.")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " ")
    }
}

extension EvalStats {
    static func pctText(_ x: Double) -> String { "\(Int((x * 100).rounded())) %" }
}

// MARK: - Your first eval, free (the checklist, ticked from real state)

public enum EvalFirstEval {
    public struct Step: Equatable, Sendable {
        public var title: String
        public var detail: String
        public var done: Bool
    }

    /// 1 a free stand-in GSM8K run finished · 2 a score read in Results · 3 one question opened · 4 a paid GSM8K run and
    /// a comparison made. `opened…` and `compared` are remembered by the app when they happen.
    public static func steps(results: [EvalResult], openedResults: Bool, openedQuestion: Bool, compared: Bool) -> [Step] {
        let free = results.contains { $0.status == "done" && $0.task == "gsm8k" && ($0.model ?? "").hasPrefix("mockllm/") }
        let paid = results.contains { $0.status == "done" && $0.task == "gsm8k" && !$0.isFree }
        return [
            Step(title: "Run 5 GSM8K questions on the free stand-in", detail: "", done: free),
            Step(title: "Read the score:", detail: "0 %, but up to 43 %", done: free && openedResults),
            Step(title: "Open a question:", detail: "prompt, answer, marking", done: free && openedQuestion),
            Step(title: "Same 5 on a cheap model, then compare", detail: "", done: paid && compared),
        ]
    }

    /// The step Continue goes to (1-based); nil when all four are done.
    public static func current(_ s: [Step]) -> Int? { s.firstIndex { !$0.done }.map { $0 + 1 } }

    /// Today's two buttons (1.9.37 Learn): step 1 free, step 4 on a cheap model with a 5-cent cap.
    public static let freePlan = EvalRunPlan(tasks: ["gsm8k"], models: ["mockllm/model"], limit: 5, cap: 0)
    public static let cheapPlan = EvalRunPlan(tasks: ["gsm8k"], models: ["anthropic/claude-haiku-5-5"], limit: 5, cap: 0.05)
    /// Today's walkthrough text, kept word for word.
    public static let walkthrough = "1. Run 5 GSM8K math questions on the stand-in model (it always gives the same wrong answer, and costs nothing). 2. Open Results: the score is 0 %, but the 95 % range goes up to 43 % — five questions say very little. 3. Open a question to see the prompt, the answer and how it was scored. 4. Then run the same 5 questions on a real, cheap model and compare the two runs."
}

// MARK: - Hover explanations (every number links to its lesson)

public enum EvalHover {
    public enum Kind: String, CaseIterable, Sendable {
        case score, range, n, canTell, passK, costPerRight, cost, floor, chance, headroom, agreement, compare, stderr
    }

    /// The lesson each kind of number opens.
    public static func lesson(_ k: Kind) -> String {
        switch k {
        case .score, .floor, .chance: return "accuracy-chance"
        case .range, .n: return "range"
        case .canTell: return "attempts"
        case .passK: return "passk"
        case .costPerRight, .cost: return "cost"
        case .headroom: return "saturation"
        case .agreement: return "labels"
        case .compare: return "compare"
        case .stderr: return "stderr"
        }
    }

    /// The first line: what this kind of number is.
    public static func definition(_ k: Kind) -> String {
        switch k {
        case .score: return "Score: the share of answers marked right."
        case .range: return "95 % range: where the true score probably is."
        case .n: return "n: how many answers the score is based on."
        case .canTell: return "What a run can tell: the smallest difference that is not noise."
        case .passK: return "pass@k: at least one of k attempts passed."
        case .costPerRight: return "$ / right: dollars spent for each answer marked right."
        case .cost: return "Cost: what the run spent, from the provider's prices."
        case .floor: return "Floor: what you get with no real model."
        case .chance: return "Chance: what guessing alone scores."
        case .headroom: return "Headroom: room left above the best published score."
        case .agreement: return "Judge agreement: how often the judge marks answers the way you did."
        case .compare: return "Paired difference: A minus B on the same questions."
        case .stderr: return "Standard error: how much the score moves between samples."
        }
    }

    static func p(_ x: Double) -> String { EvalStats.pctText(x) }

    /// "75 % on 20 questions: the true score is probably between 53 % and 89 %."
    /// `unit`: "question" (benchmarks), "case" (your sets) or "answer" (when either).
    public static func range(score: Double, n: Int, lo: Double, hi: Double, unit: String = "question") -> String {
        let what = n == 1 ? unit : unit + "s"
        var s = "\(p(score)) on \(n) \(what): the true score is probably between \(p(lo)) and \(p(hi))."
        if EvalStats.isSmall(n) { s += " Under 30: read it as a rough guide." }
        return s
    }

    public static func score(score: Double, n: Int?) -> String {
        guard let n, n > 0 else { return "\(p(score)) of the answers were marked right." }
        let right = Int((score * Double(n)).rounded())
        return "\(right) of \(n) answers marked right (\(p(score)))." + (EvalStats.isSmall(n) ? " Few answers: see the range." : "")
    }

    public static func canTell(points: Double) -> String {
        "About ±\(Int(points.rounded())) points: two contestants closer than that cannot be told apart on this run."
    }

    public static func costPerRight(_ usd: Double) -> String {
        String(format: "$%.4f for each answer marked right. A cheaper run that gets fewer right can cost more per right answer.", usd)
    }

    public static func cost(_ text: String) -> String {
        switch text {
        case "seat": return "Run on your plan's seat: no per-token bill for this run."
        case "free": return "Free: the stand-in or a model on this Mac."
        default: return "\(text) for the whole run."
        }
    }

    public static func floor(share: Double?, right: Int? = nil, of: Int? = nil, kind: String? = nil) -> String {
        let what = kind == "chance" ? "Guessing" : "No model at all (naming the files changed most often)"
        if let right, let of { return "\(what) gets \(right) of \(of) right. A score near it means little." }
        if let share { return "\(what) scores \(p(share)). A score near it means little." }
        return "A score near the floor means little."
    }

    public static func chance(_ text: String) -> String { "Here: \(text). A score near it is no better than guessing." }

    public static func headroom(_ text: String, saturated: Bool) -> String {
        text + (saturated ? ". Top models are too close to tell apart here." : ". There is room for better models to show.")
    }

    public static func agreement(_ a: EvalJudgeAgreement) -> String {
        "The judge \(a.short)." + (a.trustworthy ? "" : " Under 10 held-back labels: label more before trusting it.")
    }

    public static func compare(diff: Double, lo: Double, hi: Double, paired: Bool) -> String {
        let d = Int((diff * 100).rounded()), l = Int((lo * 100).rounded()), h = Int((hi * 100).rounded())
        let words = lo > 0 ? "A is better." : hi < 0 ? "B is better." : "The range includes 0: not distinguishable."
        return "\(d >= 0 ? "+" : "")\(d) points, 95 % range \(l >= 0 ? "+" : "")\(l) to \(h >= 0 ? "+" : "")\(h)\(paired ? " (paired)" : " (unpaired)"). " + words
    }
}
