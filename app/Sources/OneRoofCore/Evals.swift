import Foundation

// LAB-EVALS: the Evals place. The engine is `roof_eval.py` (Inspect AI, run outside the app; ADR
// docs/decisions/20261031_02_eval-engine-inspect.md). This file holds what the views need and nothing that draws:
// the engine call, the shapes of its --json output, filtering, intervals and comparisons.

// MARK: - Engine

public enum EvalEngine {
    /// The launcher: Resources/evals/roof_eval.py in the app, app/Resources/evals in a debug build's checkout.
    public static var script: String? {
        AppResources.path(bundled: "evals/roof_eval.py", checkout: "app/Resources/evals/roof_eval.py")
    }

    /// ~/Library/Application Support/One Roof/evals (ONEROOF_EVALS_DIR overrides, as the engine does).
    public static var dataDir: String {
        if let d = ProcessInfo.processInfo.environment["ONEROOF_EVALS_DIR"], !d.isEmpty { return d }
        return NSHomeDirectory() + "/Library/Application Support/One Roof/evals"
    }

    /// A python3 that can run the launcher (standard library only): the engine's own once installed, then the usual
    /// installs. /usr/bin/python3 comes last: without the command line tools it opens an install prompt.
    public static func python(fm: FileManager = .default) -> String? {
        let candidates = [dataDir + "/venv/bin/python", "/opt/homebrew/bin/python3", "/usr/local/bin/python3",
                          "/Library/Frameworks/Python.framework/Versions/Current/bin/python3", "/usr/bin/python3"]
        return candidates.first { fm.isExecutableFile(atPath: $0) }
    }

    public struct Output: Sendable { public var code: Int32; public var stdout: Data; public var stderr: String }

    /// Run `roof_eval.py <args>`; blocking, so callers use a background queue. The provider keys never pass through
    /// the app: the engine reads them from the key files the owner chose.
    public static func run(_ args: [String], timeout: TimeInterval = 600) -> Output {
        guard let py = python(), let s = script else {
            return Output(code: 127, stdout: Data(), stderr: "python3 or the eval engine launcher was not found")
        }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: py)
        p.arguments = [s] + args
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:" + (env["PATH"] ?? "/usr/bin:/bin")   // uv, docker
        p.environment = env
        let out = Pipe(), err = Pipe()
        p.standardOutput = out; p.standardError = err
        do { try p.run() } catch { return Output(code: 126, stdout: Data(), stderr: "\(error)") }
        var o = Data(), e = Data()
        let g = DispatchGroup()
        g.enter(); DispatchQueue.global().async { o = out.fileHandleForReading.readDataToEndOfFile(); g.leave() }
        g.enter(); DispatchQueue.global().async { e = err.fileHandleForReading.readDataToEndOfFile(); g.leave() }
        if g.wait(timeout: .now() + timeout) == .timedOut { p.terminate() }
        p.waitUntilExit()
        return Output(code: p.terminationStatus, stdout: o, stderr: String(decoding: e, as: UTF8.self))
    }

    /// Decode a --json answer; an engine error ({"error": …}) or bad JSON comes back as the message.
    public static func decode<T: Decodable>(_ type: T.Type, _ o: Output) -> Result<T, EvalError> {
        if let err = try? JSONDecoder().decode(EvalError.self, from: o.stdout), !err.message.isEmpty { return .failure(err) }
        do { return .success(try JSONDecoder().decode(T.self, from: o.stdout)) }
        catch {
            let msg = o.stderr.split(separator: "\n").last.map(String.init) ?? "the engine gave no answer (exit \(o.code))"
            return .failure(EvalError(message: msg.replacingOccurrences(of: "roof eval: ", with: ""), code: Int(o.code)))
        }
    }
}

public struct EvalError: Error, Decodable, Equatable, Sendable {
    public var message: String
    public var code: Int
    enum CodingKeys: String, CodingKey { case message = "error", code }
    public init(message: String, code: Int) { self.message = message; self.code = code }
    public init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        message = try c.decode(String.self, forKey: .message)
        code = try c.decodeIfPresent(Int.self, forKey: .code) ?? 1
    }
}

// MARK: - Engine state (doctor)

public struct EvalDoctor: Decodable, Equatable, Sendable {
    public struct Engine: Decodable, Equatable, Sendable {
        public var ready: Bool
        public var inspectAI: String?
        public var inspectEvals: String?
        enum CodingKeys: String, CodingKey { case ready, inspectAI = "inspect_ai", inspectEvals = "inspect_evals" }
    }
    public struct Provider: Decodable, Equatable, Sendable { public var ready: Bool; public var source: String? }
    public var engine: Engine
    public var uv: String?
    public var docker: String
    public var providers: [String: Provider]
    public var pricesChecked: String?
    /// Where code-running benchmarks can execute: local (Docker), daytona, modal → ready (LAB-2000).
    public var places: [String: Bool]
    enum CodingKeys: String, CodingKey { case engine, uv, docker, providers, pricesChecked = "prices_checked", places = "where" }
    public init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        engine = try c.decode(Engine.self, forKey: .engine); uv = try c.decodeIfPresent(String.self, forKey: .uv)
        docker = try c.decode(String.self, forKey: .docker); providers = try c.decode([String: Provider].self, forKey: .providers)
        pricesChecked = try c.decodeIfPresent(String.self, forKey: .pricesChecked)
        places = try c.decodeIfPresent([String: Bool].self, forKey: .places) ?? ["local": true]
    }
    public var readyProviders: [String] { providers.filter(\.value.ready).map(\.key).sorted() }
    /// The order the run sheet offers them: this Mac first.
    public static let placeOrder = ["local", "daytona", "modal"]
    public static func placeTitle(_ p: String) -> String {
        switch p { case "local": return "This Mac (Docker)"; case "daytona": return "Daytona (cloud)"; case "modal": return "Modal (cloud)"; default: return p }
    }
}

// MARK: - Catalog

public struct EvalCatalog: Decodable, Equatable, Sendable {
    public var inspectEvals: String?
    public var count: Int
    public var tasks: Int
    public var categories: [String]
    public var benchmarks: [EvalBenchmark]
    enum CodingKeys: String, CodingKey { case inspectEvals = "inspect_evals", count, tasks, categories, benchmarks }

    /// Categories in shelf order first, then the rest alphabetically.
    public var allCategories: [String] {
        let present = Set(benchmarks.map(\.category))
        return categories.filter(present.contains) + present.subtracting(categories).sorted()
    }
}

public struct EvalBenchmark: Decodable, Equatable, Identifiable, Sendable {
    public struct Task: Decodable, Equatable, Sendable {
        public struct Baseline: Decodable, Equatable, Sendable { public var metric: String?; public var score: Double?; public var source: String? }
        public var name: String
        public var samples: Int?
        public var humanBaseline: Baseline?
        enum CodingKeys: String, CodingKey { case name, samples, humanBaseline = "human_baseline" }
    }
    public struct Starter: Decodable, Equatable, Sendable { public var task: String; public var teaches: String; public var rank: Int; public var milestone: String? }
    public var folder: String
    public var title: String?
    public var group: String?
    public var description: String
    public var arxiv: String?
    public var tags: [String]
    public var extra: String?
    public var sandbox: Bool
    public var internet: Bool
    public var supportsK8s: Bool
    public var tasks: [Task]
    public var starter: [Starter]
    public var category: String
    public var id: String { folder }
    public var name: String { title ?? folder }
    /// Questions a first run uses: 50, or all of a smaller set (your own 20-question set is priced and run at 20).
    public var firstRunLimit: Int { min(50, tasks.first(where: { $0.name == defaultTask })?.samples ?? 50) }
    /// A task as people read it: your own eval sets run from a task file, shown by its name, not its path (LAB-1995).
    public static func taskLabel(_ task: String) -> String {
        task.hasSuffix(".py") ? String((task as NSString).lastPathComponent.dropLast(3)) : task
    }
    public var isStarter: Bool { !starter.isEmpty }
    /// Shelf picks first (LAB-1974); the benchmark's first task otherwise.
    public var defaultTask: String { starter.min { $0.rank < $1.rank }?.task ?? tasks.first?.name ?? folder }
    enum CodingKeys: String, CodingKey {
        case folder, title, group, description, arxiv, tags, extra, sandbox, internet, tasks, starter, category
        case supportsK8s = "supports_k8s"
    }
    public init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        folder = try c.decode(String.self, forKey: .folder)
        title = try c.decodeIfPresent(String.self, forKey: .title)
        group = try c.decodeIfPresent(String.self, forKey: .group)
        description = try c.decodeIfPresent(String.self, forKey: .description) ?? ""
        arxiv = try c.decodeIfPresent(String.self, forKey: .arxiv)
        tags = (try? c.decodeIfPresent([String].self, forKey: .tags)) ?? []
        extra = try? c.decodeIfPresent(String.self, forKey: .extra)
        sandbox = try c.decodeIfPresent(Bool.self, forKey: .sandbox) ?? false
        internet = try c.decodeIfPresent(Bool.self, forKey: .internet) ?? false
        supportsK8s = try c.decodeIfPresent(Bool.self, forKey: .supportsK8s) ?? false
        tasks = try c.decodeIfPresent([Task].self, forKey: .tasks) ?? []
        starter = try c.decodeIfPresent([Starter].self, forKey: .starter) ?? []
        category = try c.decodeIfPresent(String.self, forKey: .category) ?? (group ?? "Other")
    }
}

public struct EvalCatalogFilter: Equatable, Sendable {
    public var category: String?
    public var search = ""
    public var starterOnly = false
    public var noSandbox = false
    public init(category: String? = nil, search: String = "", starterOnly: Bool = false, noSandbox: Bool = false) {
        self.category = category; self.search = search; self.starterOnly = starterOnly; self.noSandbox = noSandbox
    }

    public func apply(_ bs: [EvalBenchmark]) -> [EvalBenchmark] {
        let q = search.trimmingCharacters(in: .whitespaces).lowercased()
        return bs.filter { b in
            (category == nil || b.category == category) && (!starterOnly || b.isStarter) && (!noSandbox || !b.sandbox)
                && (q.isEmpty || [b.folder, b.name, b.description, b.category, b.tags.joined(separator: " "),
                                  b.tasks.map(\.name).joined(separator: " ")].joined(separator: " ").lowercased().contains(q))
        }
    }
}

// MARK: - Runs, estimates, results

public struct EvalEstimate: Decodable, Equatable, Sendable {
    public struct Tokens: Decodable, Equatable, Sendable { public var input: Int; public var output: Int }
    public var task: String
    public var model: String
    public var calls: Int
    public var tokensPerSample: Tokens
    public var tokenBasis: String
    public struct Part: Decodable, Equatable, Sendable {
        public var usd: Double
        public var basis: String
        public var models: [String]?
        public var where_: String?
        public var secondsPerQuestion: Double?
        enum CodingKeys: String, CodingKey { case usd, basis, models, where_ = "where", secondsPerQuestion = "seconds_per_question" }
    }
    public var usd: Double?
    public var modelUSD: Double?
    /// What the cap is checked against: model + grader × 1.5 + sandbox (grading is not stopped mid-run; LAB-2012).
    public var capCheckUSD: Double?
    public var grader: Part?
    public var sandbox: Part?
    public var pricesChecked: String?
    public var note: String?
    enum CodingKeys: String, CodingKey {
        case task, model, calls, usd, note, grader, sandbox
        case tokensPerSample = "tokens_per_sample", tokenBasis = "token_basis", pricesChecked = "prices_checked"
        case modelUSD = "model_usd", capCheckUSD = "cap_check_usd"
    }
    /// One line for the run sheet: "model $0.10 · grader $0.03 · sandbox $0.0004".
    public var breakdown: String {
        var p: [String] = []
        if let m = modelUSD { p.append(String(format: "model $%.4f", m)) }
        if let g = grader, g.usd > 0 || !(g.models ?? []).isEmpty { p.append(String(format: "grader $%.4f", g.usd)) }
        if let s = sandbox { p.append(String(format: "sandbox $%.4f", s.usd)) }
        return p.joined(separator: " · ")
    }
}

public struct EvalRunRow: Decodable, Equatable, Identifiable, Sendable {
    public var id: String
    public var task: String?
    public var model: String?
    public var limit: Int?
    public var epochs: Int?
    public var status: String?
    public var created: String?
    public var finished: String?
    public var progress: String
    public var isActive: Bool { status == "running" || status == "queued" }
    public var canResume: Bool { status == "interrupted" || status == "cancelled" || status == "failed" }
    /// "12/50" → 0.24; nil when unknown.
    public var fraction: Double? {
        let p = progress.split(separator: "/").compactMap { Double($0) }
        return p.count == 2 && p[1] > 0 ? min(p[0] / p[1], 1) : nil
    }
}

public struct EvalMetric: Decodable, Equatable, Sendable {
    public var scorer: String
    public var metric: String
    public var value: Double?
    public var stderr: Double?
    public var n: Int?
    public var ci95: [Double]?
    public var ciMethod: String
    public var note: String?
    enum CodingKeys: String, CodingKey { case scorer, metric, value, stderr, n, ci95, note, ciMethod = "ci_method" }
    public var label: String { scorer == metric ? metric : "\(scorer) · \(metric)" }
}

/// A judge run's agreement with the owner's held-back labels (LAB-1996), shown next to the judged score.
public struct EvalJudgeAgreement: Decodable, Equatable, Sendable {
    public var mode: String
    public var n: Int
    public var agreement: Double?
    public var tpr: Double?
    public var tnr: Double?
    public var positionConsistency: Double?
    public var judgedPassRate: Double?
    public var selfPreference: String?
    /// Whose labels the headline is measured on: "you", or "model:<id>" (silver labels, named as such).
    public var reference: String?
    public struct CodeCheck: Decodable, Equatable, Sendable {
        public var failsWhatCodeFails: Double?
        public var codeFail: Int
        enum CodingKeys: String, CodingKey { case failsWhatCodeFails = "fails_what_code_fails", codeFail = "code_fail" }
    }
    /// Against a fact code checked (the note points at no changed file): how often the judge failed those too.
    public var code: CodeCheck?
    enum CodingKeys: String, CodingKey {
        case mode, n, agreement, tpr, tnr, reference, code
        case positionConsistency = "position_consistency", judgedPassRate = "judged_pass_rate", selfPreference = "self_preference"
    }
    /// "you", or the labelling model's short name + "'s labels".
    public var against: String {
        guard let r = reference, r.hasPrefix("model:") else { return "you" }
        return (r.dropFirst(6).split(separator: ",").first.map { String($0.split(separator: "/").last ?? $0) } ?? "a model") + "'s labels"
    }
    /// Fewer than 10 held-back labels: the agreement is shown but marked as not yet trustworthy.
    public var trustworthy: Bool { n >= 10 }
    private static func pct(_ x: Double?) -> String { x.map { "\(Int(($0 * 100).rounded())) %" } ?? "–" }
    /// "agrees with you 85 % (n=20) · good 90 % · bad 78 %" — overall, true positive and true negative rates.
    public var short: String {
        var s = "agrees with \(against) \(Self.pct(agreement)) (n=\(n))"
        if mode == "pairwise" { s += " · same winner both orders \(Self.pct(positionConsistency))" }
        else { s += " · good \(Self.pct(tpr)) · bad \(Self.pct(tnr))" }
        if let c = code, c.codeFail > 0 { s += " · fails \(Self.pct(c.failsWhatCodeFails)) of \(c.codeFail) wrong-file notes" }
        if !trustworthy { s += " · too few labels" }
        if selfPreference != nil { s += " · grades its own answers" }
        return s
    }
}

public struct EvalResult: Decodable, Equatable, Identifiable, Sendable {
    public var id: String
    public var task: String?
    public var model: String?
    public var status: String?
    public var started: String?
    public var finished: String?
    public var limitN: Int?
    public var epochs: Int?
    public var seed: Int?
    public var temperature: Double?
    public var samplesDone: Int?
    public var samplesTotal: Int?
    public var inputTokens: Int?
    public var outputTokens: Int?
    public var cost: Double?
    public var estCost: Double?
    public var inspectEvals: String?
    public var error: String?
    public var metrics: [EvalMetric]
    public var judgeAgreement: EvalJudgeAgreement?
    enum CodingKeys: String, CodingKey {
        case id, task, model, status, started, finished, epochs, seed, temperature, cost, error, metrics
        case judgeAgreement = "judge_agreement"
        case limitN = "limit_n", samplesDone = "samples_done", samplesTotal = "samples_total", inputTokens = "input_tokens"
        case outputTokens = "output_tokens", estCost = "est_cost", inspectEvals = "inspect_evals"
    }
    /// The headline number: the first metric with a value.
    public var primary: EvalMetric? { metrics.first { $0.value != nil } }
    public var isFree: Bool { EvalModels.isFree(model ?? "") }
    /// Seconds from start to finish (ISO 8601 times from the log).
    public var duration: TimeInterval? {
        let f = ISO8601DateFormatter()
        guard let a = started.flatMap(f.date(from:)), let b = finished.flatMap(f.date(from:)) else { return nil }
        return b.timeIntervalSince(a)
    }
    /// Dollars per correct answer: cost ÷ (primary score × answers), for proportion metrics only.
    public var costPerCorrect: Double? {
        guard let c = cost, let p = primary, let v = p.value, p.ciMethod == "wilson", let n = samplesDone, v > 0, n > 0 else { return nil }
        return c / (v * Double(n))
    }
}

public struct EvalSample: Decodable, Equatable, Identifiable, Sendable {
    public var sampleID: String
    public var epoch: Int
    public var score: Double?
    public var answer: String?
    public var target: String?
    public var input: String?
    public var output: String?
    public var explanation: String?
    public var time: Double?
    public var inputTokens: Int?
    public var outputTokens: Int?
    public var error: String?
    public var id: String { "\(sampleID)#\(epoch)" }
    enum CodingKeys: String, CodingKey {
        case sampleID = "id", epoch, score, answer, target, input, output, explanation, time, error
        case inputTokens = "input_tokens", outputTokens = "output_tokens"
    }
}

public struct EvalTranscript: Decodable, Equatable, Sendable {
    public struct Message: Decodable, Equatable, Sendable {
        public struct Call: Decodable, Equatable, Sendable { public var function: String; public var arguments: String }
        public var role: String
        public var text: String
        public var toolCalls: [Call]
        enum CodingKeys: String, CodingKey { case role, text, toolCalls = "tool_calls" }
    }
    public struct Score: Decodable, Equatable, Sendable { public var value: String; public var answer: String?; public var explanation: String? }
    public var id: String?
    public var epoch: Int?
    public var target: String?
    public var messages: [Message]
    public var scores: [String: Score]
    public var time: Double?
    public var error: String?
    public init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(String.self, forKey: .id); epoch = try c.decodeIfPresent(Int.self, forKey: .epoch)
        target = try c.decodeIfPresent(String.self, forKey: .target)
        messages = try c.decodeIfPresent([Message].self, forKey: .messages) ?? []
        scores = try c.decodeIfPresent([String: Score].self, forKey: .scores) ?? [:]
        time = try c.decodeIfPresent(Double.self, forKey: .time); error = try c.decodeIfPresent(String.self, forKey: .error)
    }
    enum CodingKeys: String, CodingKey { case id, epoch, target, messages, scores, time, error }
}

// MARK: - Models offered in the run sheet

public enum EvalModels {
    /// Suggestions only; any Inspect model name works ("provider/model"). Prices come from the engine.
    public static let suggestions: [(group: String, models: [String])] = [
        ("Free", ["mockllm/model"]),
        ("Anthropic", ["anthropic/claude-haiku-5-5", "anthropic/claude-sonnet-5-5", "anthropic/claude-opus-5-5"]),
        ("OpenAI", ["openai/gpt-5-nano", "openai/gpt-5-mini", "openai/gpt-5"]),
        ("Google", ["google/gemini-3.8-flash", "google/gemini-3.1-pro-preview"]),
        ("Open weights (OpenRouter)", ["openrouter/qwen/qwen3-coder", "openrouter/deepseek/deepseek-chat", "openrouter/meta-llama/llama-3.3-70b-instruct"]),
        ("On this Mac", ["ollama/qwen3:1.7b"]),
    ]
    public static let freePrefixes = ["mockllm/", "ollama/", "openai-api/local/", "hf/", "llama-cpp-python/", "vllm/", "sglang/"]
    public static func isFree(_ model: String) -> Bool { freePrefixes.contains { model.hasPrefix($0) } }
    public static func provider(_ model: String) -> String { String(model.split(separator: "/").first ?? "") }
    /// A short name for tables: the part after the provider.
    public static func short(_ model: String) -> String {
        let parts = model.split(separator: "/")
        guard parts.count > 1, !isFree(model) else { return model }   // "mockllm/model", not "model"
        return parts.dropFirst().joined(separator: "/")
    }

    /// "2026-10-31T22:28:07Z" or "…+00:00" → "Oct 31 15:28" in local time; the input when it is not a date.
    public static func when(_ iso: String?) -> String {
        guard let iso, let d = ISO8601DateFormatter().date(from: iso) else { return iso ?? "" }
        let f = DateFormatter(); f.dateFormat = "MMM d HH:mm"
        return f.string(from: d)
    }
}

// MARK: - Statistics

public enum EvalStats {
    /// 95 % Wilson interval for a proportion p over n (honest at 0 %, 100 % and small n). Same formula as the engine.
    public static func wilson(_ p: Double, n: Int, z: Double = 1.96) -> (lo: Double, hi: Double) {
        guard n > 0 else { return (0, 1) }
        let nn = Double(n), den = 1 + z * z / nn
        let mid = (p + z * z / (2 * nn)) / den
        let half = z * ((p * (1 - p) / nn + z * z / (4 * nn * nn)).squareRoot()) / den
        return (max(0, mid - half), min(1, mid + half))
    }

    public struct Comparison: Equatable, Sendable {
        public enum Verdict: String, Sendable { case aBetter = "A is better", bBetter = "B is better", noise = "not distinguishable" }
        public var diff: Double          // mean(A) − mean(B)
        public var lo: Double            // 95 % interval of the difference
        public var hi: Double
        public var n: Int                // paired questions, or the smaller run when unpaired
        public var paired: Bool
        public var verdict: Verdict
    }

    /// Paired difference over the questions both runs answered (each question's attempts averaged first): the
    /// right test when two models saw the same questions. Unpaired (Welch-style) when they share none.
    public static func compare(_ a: [EvalSample], _ b: [EvalSample]) -> Comparison? {
        func means(_ s: [EvalSample]) -> [String: Double] {
            Dictionary(grouping: s.filter { $0.score != nil }, by: \.sampleID)
                .mapValues { xs in xs.compactMap(\.score).reduce(0, +) / Double(xs.count) }
        }
        let ma = means(a), mb = means(b)
        let shared = Set(ma.keys).intersection(mb.keys).sorted()
        if shared.count >= 2 {
            let d = shared.map { ma[$0]! - mb[$0]! }
            let n = Double(d.count), mean = d.reduce(0, +) / n
            let sd = (d.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / (n - 1)).squareRoot()
            let half = 1.96 * sd / n.squareRoot()
            return Comparison(diff: mean, lo: mean - half, hi: mean + half, n: d.count, paired: true, verdict: verdict(mean - half, mean + half))
        }
        let xa = Array(ma.values), xb = Array(mb.values)
        guard xa.count >= 2, xb.count >= 2 else { return nil }
        func mv(_ x: [Double]) -> (Double, Double) {
            let m = x.reduce(0, +) / Double(x.count)
            return (m, x.map { ($0 - m) * ($0 - m) }.reduce(0, +) / Double(x.count - 1))
        }
        let (m1, v1) = mv(xa), (m2, v2) = mv(xb)
        let se = (v1 / Double(xa.count) + v2 / Double(xb.count)).squareRoot()
        let diff = m1 - m2
        return Comparison(diff: diff, lo: diff - 1.96 * se, hi: diff + 1.96 * se, n: min(xa.count, xb.count), paired: false,
                          verdict: verdict(diff - 1.96 * se, diff + 1.96 * se))
    }

    static func verdict(_ lo: Double, _ hi: Double) -> Comparison.Verdict { lo > 0 ? .aBetter : (hi < 0 ? .bBetter : .noise) }

    /// The latest finished run per (model, task): the cells of the results matrix.
    public static func matrix(_ runs: [EvalResult]) -> [String: [String: EvalResult]] {
        var m: [String: [String: EvalResult]] = [:]
        for r in runs where r.status == "done" {
            guard let model = r.model, let task = r.task else { continue }
            if let old = m[model]?[task], (old.started ?? "") >= (r.started ?? "") { continue }
            m[model, default: [:]][task] = r
        }
        return m
    }

    /// Fewer than 30 answers: the cell is drawn as "few samples" (the interval is wide).
    public static func isSmall(_ n: Int?) -> Bool { (n ?? 0) < 30 }
}

// MARK: - Plain explanations (LAB-1988)

/// Short explanations shown beside the numbers they explain. App help, not Agentic Engineering content.
public enum EvalGlossary {
    public struct Entry: Equatable, Identifiable, Sendable {
        public var id: String
        public var title: String
        public var body: String
        public var example: String
    }

    public static let all: [Entry] = [
        Entry(id: "accuracy", title: "Accuracy",
              body: "The share of questions answered correctly. It means little without knowing chance level: four-option multiple choice gives 25 % by guessing, MMLU-Pro's ten options give 10 %.",
              example: "43 right out of 50 → 0.86."),
        Entry(id: "interval", title: "The 95 % range",
              body: "Running the same model on a different set of questions would give a different score. The range shows where the true score probably lies. Few questions → wide range. One Roof uses the Wilson range for proportions: it stays honest at 0 % and 100 %.",
              example: "0 right out of 5 still allows up to 43 %; 80 % on 1,000 questions is about ±2.5 points."),
        Entry(id: "stderr", title: "Standard error",
              body: "How much the score would move between repeated samples of questions. The 95 % range is roughly the score ± 2 standard errors.",
              example: "Accuracy 0.70 with stderr 0.03 → about 0.64 to 0.76."),
        Entry(id: "compare", title: "Is the difference real?",
              body: "Two scores whose ranges overlap may be noise. When both models answered the same questions, compare them question by question (paired): it removes the questions' own difficulty and finds smaller real differences.",
              example: "A 0.82 vs B 0.78 on 50 shared questions: the paired range of the difference −0.03 to +0.11 includes 0 → not distinguishable."),
        Entry(id: "passk", title: "pass@1 and pass@k",
              body: "For code, the program is run against tests. pass@1: the first attempt passes. pass@k: at least one of k attempts passes. pass@k is always higher; it measures what the model can do, pass@1 what it will usually do.",
              example: "MBPP answers each question 5 times by default to estimate pass@k."),
        Entry(id: "epochs", title: "Attempts per question (epochs)",
              body: "Running each question several times shows how stable the model is, and makes the score's range narrower. It multiplies cost by the number of attempts.",
              example: "50 questions × 3 attempts = 150 calls."),
        Entry(id: "contamination", title: "Contamination",
              body: "If a benchmark's questions were in the model's training data, the score measures memory, not skill. Newer, date-sliced benchmarks (LiveCodeBench) and private test sets reduce it.",
              example: "A model scoring far higher on an old benchmark than on a fresh one of the same kind is a warning sign."),
        Entry(id: "judge", title: "A model as the grader",
              body: "Some benchmarks (SimpleQA, StrongREJECT) use a second model to grade answers. That grader has its own errors and biases, and costs money too. Check it against a person's labels before trusting it.",
              example: "StrongREJECT asks a grader model how harmful and how specific each answer is."),
        Entry(id: "harness", title: "The harness matters",
              body: "The same model scores differently with a different prompt, answer format, number of examples shown, or agent around it. Compare only runs made the same way; One Roof records the benchmark version and engine version with every run.",
              example: "Claude Code on Sonnet and Sonnet alone are two different things to measure on SWE-bench."),
        Entry(id: "frameworks", title: "Two frameworks, one benchmark",
              body: "The same benchmark run by two frameworks is two measurements. They word the question differently, ask for the answer in a different format, read it back differently, and may score multiple choice by asking for an answer or by comparing each option's probability. A small model is sensitive to all of it. Compare a model's scores only within one framework; when the frameworks disagree, look at the questions they disagree on.",
              example: "ARC-Challenge, the same first 100 test questions, Qwen3-1.7B on this Mac (2026-10-31): Inspect 72 %, lm-evaluation-harness 64 %. 14 questions differ, 11 to 3 for Inspect, so the gap is borderline (p ≈ 0.06). Inspect asks for 'ANSWER: X'; lm-eval asks the reply to end 'The best answer is X'. As shipped, lm-eval scored 0 %: its chat task pre-fills the reply and expects only the letter back, which a server without pre-fill (llama-server) never sends. One Roof reads the letter with a pattern. lm-eval's usual scoring compares option probabilities, which this server cannot return."),
        Entry(id: "cost", title: "Cost per correct answer",
              body: "Dollars spent divided by the number of correct answers. A cheaper model that gets fewer right can still be the better buy, or the worse one.",
              example: "$0.40 for 40 right → 1 cent per correct answer."),
        Entry(id: "chance", title: "Chance level and ceilings",
              body: "Know the floor (guessing) and the ceiling (human experts, or label noise) before reading a score. GPQA Diamond: experts reach about 70 %.",
              example: "A score near chance means the model is guessing; near the ceiling, the benchmark is saturated."),
    ]

    public static func entry(_ id: String) -> Entry? { all.first { $0.id == id } }
}
