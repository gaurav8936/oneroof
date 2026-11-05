import CryptoKit
import Foundation

// LAB-2242 · Evals v2 screen lane B (One Roof 2.0.4): the pure parts of Our tasks (E5.1), One task (E5.2), Check the
// grader (E5.3), Public benchmarks (E6.1), Set up a test (E7) and the coverage map. Plain words per BRIEF; every number
// comes from the engine or from EvalStats / EvalPower (test-locked to the engine). Nothing here draws.

// MARK: - Our tasks: plain words

public enum EvalTaskWords {
    /// "Find the files a bug fix needs" · "Write a useful note on a new bug" (engine names in secondary text only).
    public static func title(kind: String) -> String {
        switch kind {
        case "fix-locator": return "Find the files a bug fix needs"
        case "triage": return "Write a useful note on a new bug"
        default: return kind.replacingOccurrences(of: "-", with: " ").capitalized
        }
    }
    public static func engineName(kind: String) -> String {
        kind == "triage" ? "bug triage" : kind == "fix-locator" ? "fix locator" : kind
    }
    /// Both kinds are checked by code: right when the answer names a file the fix changed. For triage, the grading model
    /// is a separate study of those notes (BRIEF: never "a grading model reads each note").
    public static let checkedBy = "checked by code"
    public static func howItWorks(kind: String) -> String {
        switch kind {
        case "triage":
            return "The agent reads a real bug report and the code from before the fix, and writes a short note on where the problem is. Right if the note names a file the fix changed. Checked by code."
        default:
            return "The agent reads a real bug report and the code from before the fix, and names up to 3 files. Right if one is a file the fix changed. Checked by code."
        }
    }
    /// "fix locator · version 2, frozen Nov 1".
    public static func meta(kind: String, version: Int, frozen: String?) -> String {
        "\(engineName(kind: kind)) · version \(version)" + (day(frozen).map { ", frozen \($0)" } ?? "")
    }
    /// "2026-11-01" or an ISO time → "Nov 1"; nil when it is not a date.
    public static func day(_ s: String?) -> String? {
        guard let s, s.count >= 10 else { return nil }
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.timeZone = TimeZone(identifier: "UTC"); f.dateFormat = "yyyy-MM-dd"
        guard let d = f.date(from: String(s.prefix(10))) else { return nil }
        let o = DateFormatter(); o.locale = Locale(identifier: "en_US_POSIX"); o.timeZone = TimeZone(identifier: "UTC"); o.dateFormat = "MMM d"
        return o.string(from: d)
    }
    /// The blind guess rule (engine `frequent_files_baseline`).
    public static let guessRule = "the 3 most-fixed files"
    /// "5 of 10 · 50 %".
    public static func guessText(right: Int, of: Int) -> String {
        "\(right) of \(of) · \(of > 0 ? Int((Double(right) / Double(of) * 100).rounded()) : 0) %"
    }

    /// Plain model names: "anthropic/claude-opus-5-5" → "Opus", "openai/gpt-5-mini" → "GPT-5 mini"; others as they are.
    public static func model(_ m: String) -> String {
        let s = m.split(separator: "/").last.map(String.init) ?? m
        for (k, v) in [("opus", "Opus"), ("sonnet", "Sonnet"), ("haiku", "Haiku")] where s.contains("claude") && s.contains(k) { return v }
        if s.hasPrefix("gpt-") {
            let rest = s.dropFirst(4).split(separator: "-")
            return "GPT-" + (rest.first.map(String.init) ?? "") + (rest.count > 1 ? " " + rest.dropFirst().joined(separator: " ") : "")
        }
        return s
    }
    /// The engine's contestant text as a setup name: a model alone reads "Opus, on its own"; an agent keeps its name.
    public static func contestant(_ c: String) -> String {
        let agents = EvalAgents.names.values
        if agents.contains(where: { c.hasPrefix($0) }) || c.contains(" · ") { return c }
        if c.hasPrefix("mockllm") { return "the free stand-in" }
        return model(c) + ", on its own"
    }
}

// MARK: - Our tasks: who has been tested on a task, per layer (E5.1 chips)

public struct EvalTaskCoverage: Equatable, Sendable {
    public struct Chip: Equatable, Sendable {
        public var layer: EvalStamp.Layer
        public var tested: Int
        public var active: Int
        public var waiting: Bool
        /// "1 tested" · "1 queued" / "1 waiting" · "not tested" · full setup: "not recorded".
        public var text: String {
            if tested > 0 { return "\(tested) tested" + (active > 0 ? " · \(active) \(waiting ? "waiting" : "queued")" : "") }
            if active > 0 { return "\(active) \(waiting ? "waiting" : "queued")" }
            return layer == .full ? EvalStamp.notRecorded : "not tested"
        }
        /// Shown in the verdict ("needs") colour: nothing recorded on this layer.
        public var isGap: Bool { tested == 0 && active == 0 && layer == .full }
        public var isActiveOnly: Bool { tested == 0 && active > 0 }
        public var title: String {
            switch layer { case .model: return "The model"; case .agentModel: return "Agent using a model"; case .full: return "Full setup" }
        }
    }

    /// A run belongs to a task version when its set and version match, or its task is `own_<set>_v<N>`.
    public static func matches(task: String?, setName: String?, setVersion: Int?, name: String, version: Int) -> Bool {
        if let s = setName, s == name { return (setVersion ?? version) == version }
        return task == "own_\(name)_v\(version)"
    }

    /// One chip per layer: finished runs (the free stand-in and the no-model baseline are not a layer) and runs going now.
    /// `rulesOn`: run ids whose stamp says rules "on" (full setup); without a stamp an agent run counts as agent + model.
    public static func chips(name: String, version: Int, results: [EvalResult], runs: [EvalRunRow], rulesOn: Set<String> = []) -> [Chip] {
        func layer(_ kind: EvalContestant.Kind?, _ id: String) -> EvalStamp.Layer? {
            switch kind {
            case .agent: return rulesOn.contains(id) ? .full : .agentModel
            case .model, .local: return .model
            default: return nil
            }
        }
        var tested: [EvalStamp.Layer: Int] = [:], active: [EvalStamp.Layer: Int] = [:], waiting: Set<EvalStamp.Layer> = []
        for r in results where r.status == "done" && matches(task: r.task, setName: r.setName, setVersion: r.setVersion, name: name, version: version) {
            if let l = layer(r.contestant?.kind, r.id) { tested[l, default: 0] += 1 }
        }
        for r in runs where r.isActive && matches(task: r.task, setName: r.setName, setVersion: r.setVersion, name: name, version: version) {
            if let l = layer(r.contestant?.kind ?? (r.agent != nil ? .agent : .model), r.id) {
                active[l, default: 0] += 1
                if r.status == "waiting" { waiting.insert(l) }
            }
        }
        return EvalStamp.Layer.allCases.map { Chip(layer: $0, tested: tested[$0] ?? 0, active: active[$0] ?? 0, waiting: waiting.contains($0)) }
    }
}

// MARK: - One task: the next version (E5.2)

public enum EvalNextVersion {
    /// "52 usable fixes in the last 120 days" (dry run, every fix in the window) or "1 bug fixed since v2" (extend).
    public static func headline(_ p: EvalBuildPreview, extend: Bool) -> String {
        if extend {
            return p.new.isEmpty ? "No new fixes since v\(p.baseVersion ?? p.nextVersion - 1)."
                : "\(p.new.count) bug\(p.new.count == 1 ? "" : "s") fixed since v\(p.baseVersion ?? p.nextVersion - 1)."
        }
        return "\(p.total) usable fix\(p.total == 1 ? "" : "es") in the last \(p.days) days."
    }
    /// The reports' source, and the owner's call (11-05): a version built from different report text is a new version of
    /// the same task, never a new task; results never mix versions.
    public static func sourceNote(_ p: EvalBuildPreview, current: Int, currentSource: String?) -> String {
        let src = p.reportSource
        var s = "Bug reports for v\(p.nextVersion) come from \(src)"
        if let c = currentSource, c != src { s += " (v\(current)'s came from \(c))" }
        return s + ". It is a new version of the same task: v\(current) stays frozen and results never mix versions."
    }
    /// "v2's 10 bugs give ±26 points; v3's 52 would give ±13." (power, Wilson at 50 %).
    public static func powerNote(current: Int, currentN: Int, next: Int, nextN: Int) -> String {
        let a = EvalPower.mirror(n: currentN, epochs: 1).plusMinusPoints, b = EvalPower.mirror(n: nextN, epochs: 1).plusMinusPoints
        return "v\(current)'s \(currentN) bugs tell setups apart to about ±\(Int(a.rounded())) points; v\(next)'s \(nextN) would give ±\(Int(b.rounded()))."
    }
    /// Where v<N>'s reports came from (set.json stats): "Linear issues", "commit subjects" or both.
    public static func source(linear: Int?, subject: Int?) -> String? {
        switch ((linear ?? 0) > 0, (subject ?? 0) > 0) {
        case (true, true): return "Linear issues and commit subjects"
        case (true, false): return "Linear issues"
        case (false, true): return "commit subjects"
        default: return nil
        }
    }
    /// The engine's arguments: extend (this version's bugs + the new fixes) or every usable fix in the window (`count`).
    public static func buildArguments(name: String, repo: String, kind: String, days: Int, extend: Bool, count: Int?,
                                      keyFile: String?, dryRun: Bool) -> [String] {
        var a = ["evalset", "build", "--name", name]
        a += extend ? ["--extend"] : ["--kind", kind, "--count", String(max(count ?? 200, 1))]
        a += ["--days", String(days)]
        if !repo.isEmpty { a += ["--repo", repo] }
        if let k = keyFile, !k.isEmpty { a += ["--linear-key-file", k] }
        if dryRun { a.append("--dry-run") }
        return a
    }
}

// MARK: - Check the grader (E5.3)

public enum EvalGraderWords {
    /// "Not trusted yet" until both rates reach 70 % and 10 of your labels are held back (judge.py `ready`).
    public static func verdictTitle(_ tr: EvalJudgeTrust) -> String { tr.ready ? "Trusted for now" : "Not trusted yet" }
    /// "It's lenient: it passes about half the notes that should fail, so triage scores read high. And these labels came
    /// from another model, not you." Built from the measured rates only.
    public static func verdictBody(_ tr: EvalJudgeTrust) -> String {
        var s: [String] = []
        if tr.run == nil { return "Not measured yet: run the grader on its held-back notes to see how often it agrees." }
        if let tnr = tr.tnr, tnr < 0.7 {
            s.append("It's lenient: it passes \(pct(1 - tnr)) of the notes that should fail, so its scores read high.")
        }
        if let tpr = tr.tpr, tpr < 0.7 {
            s.append("It's strict: it fails \(pct(1 - tpr)) of the notes that should pass, so its scores read low.")
        }
        if s.isEmpty, let a = tr.agreement { s.append("It agrees with the labels \(pct(a)) of the time.") }
        if tr.reference != "you" && tr.reference != "owner" { s.append("And these labels came from another model, not you.") }
        let need = max(0, 10 - (tr.heldBackYours ?? 0))
        if need > 0 { s.append("Label \(need) note\(need == 1 ? "" : "s") yourself to check it.") }
        return s.joined(separator: " ")
    }
    /// The labels the grader is measured against came from a model, not from you (QA m5).
    public static func byModel(_ tr: EvalJudgeTrust) -> Bool { tr.reference != "you" && tr.reference != "owner" }
    /// Our tasks' grader line: "agrees 70 % with another model's labels · not trusted yet · 0 of 40 labelled by you".
    public static func agreesLine(_ tr: EvalJudgeTrust) -> String {
        "agrees \(EvalJudgeTrust.pct(tr.agreement)) " + (byModel(tr) ? "with another model's labels" : "with your labels")
            + " · \(verdictTitle(tr).lowercased()) · \(tr.labelled) of \(tr.items) labelled by you"
    }
    /// The hover card on that line (QA m14): what the agreement is measured on, and against whose labels.
    public static func agreementHover(_ tr: EvalJudgeTrust) -> String {
        guard tr.agreement != nil else { return "Agreement with labels: not measured yet." }
        let who = byModel(tr) ? "another model's labels (they never count as yours)" : "your labels"
        return "Agrees with \(who) on \(ofText(tr.agreement, tr.n)) held-back notes. Label 10 notes yourself before trusting its marks."
    }
    /// The Our tasks banner: "The grading model isn't trusted yet. It passes 47 % of notes that should fail. Label 10
    /// notes yourself to check it." nil when it is trusted.
    public static func banner(_ tr: EvalJudgeTrust) -> String? {
        guard !tr.ready else { return nil }
        var s = "It is a separate study of these notes; the score above is still checked by code."
        if let tnr = tr.tnr, tnr < 0.7 {
            s = "It passes \(pct(1 - tnr)) of notes that should fail" + (byModel(tr) ? " (by another model's labels)" : "") + ". " + s
        }
        let need = max(0, 10 - (tr.heldBackYours ?? 0))
        if need > 0 { s += " Label \(need) notes yourself to check it." }
        return s
    }
    /// "Grades 40 notes · grading model gpt-5-mini · v1 · checked against 30 held-back labels".
    public static func subtitle(items: Int, model: String?, version: Int?, n: Int) -> String {
        var p = ["Grades \(items) notes"]
        if let m = model { p.append("grading model " + EvalModels.short(m)) }
        if let v = version { p.append("v\(v)") }
        if n > 0 { p.append("checked against \(n) held-back labels") }
        return p.joined(separator: " · ")
    }
    /// "21 of 30" under a rate (rounded from the measured share).
    public static func ofText(_ rate: Double?, _ n: Int) -> String {
        guard let r = rate, n > 0 else { return "n = \(n)" }
        return "\(Int((r * Double(n)).rounded())) of \(n)"
    }
    static func pct(_ x: Double) -> String { "\(Int((x * 100).rounded())) %" }
}

// MARK: - Public benchmarks (E6.1)

public struct EvalBenchmarkSummaryRow: Equatable, Identifiable, Sendable {
    public var id: String          // the benchmark folder
    public var name: String
    public var tests: String
    public var layer: EvalStamp.Layer
    public var bestRun: String     // "Haiku 5 of 5" · "3 runs" · "not run"
    public var bestN: Int?
    public var bestScore: Double?
    public var runs: Int

    /// Benchmarks this Mac has run (your own sets, graders and labellers are not public), best run first per benchmark.
    public static func rows(catalog: [EvalBenchmark], results: [EvalResult]) -> [EvalBenchmarkSummaryRow] {
        var out: [EvalBenchmarkSummaryRow] = []
        for b in catalog where !b.isOwn {
            let tasks = Set(b.tasks.map(\.name))
            let mine = results.filter { r in
                guard let t = r.task, tasks.contains(t) || tasks.contains(t.replacingOccurrences(of: "lm-eval:", with: "")) else { return false }
                return r.contestant?.kind != .baseline && !(r.model ?? "").hasPrefix("mockllm/")
            }
            guard !mine.isEmpty else { continue }
            // Only proportions (Wilson) read as "N of M"; a score on another scale is not a count of right answers.
            let done = mine.filter { $0.status == "done" && $0.primary?.value != nil && $0.primary?.ciMethod == "wilson" && ($0.primary?.n ?? 0) > 0 }
            let best = done.max { a, b in
                let (va, vb) = (a.primary?.value ?? 0, b.primary?.value ?? 0)
                return va != vb ? va < vb : (a.primary?.n ?? 0) < (b.primary?.n ?? 0)
            }
            let agent = b.shelf == "agent" || b.tags.contains("agent") || mine.contains { $0.contestant?.kind == .agent }
            // QA m8: always a score, or plainly "no finished score" — never a bare run count.
            func who(_ r: EvalResult) -> String {
                guard let c = r.contestant else { return EvalTaskWords.model(r.model ?? "?") }
                switch c.kind {
                case .agent: return c.name
                case .local: return String((c.model ?? c.name).split(separator: "/").last ?? "") + " on this Mac"
                default: return EvalTaskWords.model(c.model ?? c.name)
                }
            }
            let runs = "\(mine.count) run\(mine.count == 1 ? "" : "s")"
            var text = "no finished score · \(runs)"
            if let r = best, let v = r.primary?.value, let n = r.primary?.n {
                text = "\(who(r)) \(Int((v * Double(n)).rounded())) of \(n)"
            } else if let r = mine.filter({ $0.status == "done" && $0.primary?.value != nil })
                        .max(by: { ($0.primary?.value ?? 0) < ($1.primary?.value ?? 0) }), let v = r.primary?.value {
                // Another scale (NIAH's mean on 10): the value and its metric, never "N of M".
                text = "\(who(r)) \(String(format: "%.3g", v)) (\(r.primary?.metric ?? "score"))"
            }
            out.append(EvalBenchmarkSummaryRow(id: b.id, name: b.name, tests: b.madeOf ?? b.category, layer: agent ? .agentModel : .model,
                                               bestRun: text, bestN: best?.primary?.n, bestScore: best?.primary?.value, runs: mine.count))
        }
        return out.sorted { ($0.layer == .model ? 0 : 1, $0.name) < ($1.layer == .model ? 0 : 1, $1.name) }
    }

    /// "Your runs used 2–5 questions: too few to mean much. A score on 5 questions could be anything from 57 to 100 %."
    /// nil when every best run has 30 or more.
    public static func smallNote(_ rows: [EvalBenchmarkSummaryRow]) -> String? {
        let ns = rows.compactMap(\.bestN)
        guard let lo = ns.min(), let hi = ns.max(), hi < 30 else { return nil }
        let r = rows.first { $0.bestN == hi && $0.bestScore != nil }
        let score = r?.bestScore ?? 1
        let w = EvalStats.wilson(score, n: hi)
        let span = lo == hi ? "\(hi)" : "\(lo)–\(hi)"
        return "Your runs used \(span) questions: too few to mean much. A score on \(hi) questions could be anything from \(Int((w.lo * 100).rounded())) to \(Int((w.hi * 100).rounded())) %."
    }

    /// The best published score: "97 % (Llama 3.1 405B Instruct)"; "—" when the benchmark has no source.
    public static func published(_ s: EvalPublishedScores?) -> String {
        guard let s, let top = s.rows.max(by: { $0.score < $1.score }) else { return "—" }
        return "\(Int((top.score * 100).rounded())) % (\(top.contestant))"
    }
}

// MARK: - Set up a test (E7): a setup = agent + model + where it runs + our rules

public struct EvalSetupChoice: Hashable, Identifiable, Sendable {
    public enum RunsOn: String, Hashable, Sendable { case seat, api }
    /// nil = the model on its own.
    public var agent: String?
    /// A model alone or an agent on an API model: provider/model. An agent on its seat: nil = the CLI's default model.
    public var model: String?
    public var runsOn: RunsOn
    /// Our rules (the repo's CLAUDE.md / AGENTS.md at HEAD) on = your full setup. Seat runs only.
    public var rules: Bool

    public init(agent: String?, model: String?, runsOn: RunsOn, rules: Bool = false) {
        self.agent = agent; self.model = model; self.runsOn = runsOn; self.rules = rules && agent != nil && runsOn == .seat
    }
    public static func model(_ m: String) -> EvalSetupChoice { .init(agent: nil, model: m, runsOn: .api) }
    public static func seat(_ agent: String, model: String? = nil, rules: Bool = false) -> EvalSetupChoice {
        .init(agent: agent, model: model, runsOn: .seat, rules: rules)
    }
    public static func apiAgent(_ agent: String, model: String) -> EvalSetupChoice { .init(agent: agent, model: model, runsOn: .api) }

    /// CONTRACT §3's setup_id: "model:claude-opus-5-5" · "claude_code:claude-opus-5-5:off" · "claude_code:default:off";
    /// an agent on an API model adds "@api".
    public var id: String {
        guard let a = agent else { return "model:" + EvalSetupChoice.cliModel(model ?? "") }
        return "\(a):\(model.map(EvalSetupChoice.cliModel) ?? "default"):\(rules ? "on" : "off")" + (runsOn == .api ? "@api" : "")
    }
    public var layer: EvalStamp.Layer { agent == nil ? .model : rules ? .full : .agentModel }
    public var seat: String? { runsOn == .seat ? agent.flatMap(EvalAgents.seat) : nil }
    public var isSeat: Bool { runsOn == .seat && agent != nil }

    /// "Opus, on its own" · "Claude Code using Opus" · "Claude Code on its CLI default model" (+ ", with our rules").
    public var label: String {
        guard let a = agent else { return model.map { EvalModels.isFree($0) ? $0 + ", on this Mac" : EvalTaskWords.model($0) + ", on its own" } ?? "?" }
        let name = EvalAgents.name(a)
        let base = model.map { "\(name) using \(EvalTaskWords.model($0))" } ?? "\(name) on its CLI default model"
        return base + (rules ? ", with our rules" : "")
    }
    /// "seat C1" · "API key · anthropic" · "this Mac".
    public var runsOnText: String {
        if isSeat { return "seat " + (seat ?? "?") }
        guard let m = model else { return "?" }
        return EvalModels.isFree(m) ? "this Mac" : "API key · " + EvalModels.provider(m)
    }
    /// CONTRACT §1 runs_on.
    public var runsOnStamp: String {
        if isSeat { return "seat:" + (seat ?? "C1") }
        guard let m = model else { return "local" }
        if m.hasPrefix("mockllm/") { return "stand-in" }
        return EvalModels.isFree(m) ? "local" : "api:" + EvalModels.provider(m)
    }
    /// The 2.0.3 contestant (model, agent on an API model, agent on a seat).
    public var contestant: EvalRunPlan.Contestant {
        guard let a = agent else { return .model(model ?? "mockllm/model") }
        if runsOn == .api, let m = model { return .apiAgent(agent: a, model: m) }
        return .seat(agent: a)
    }

    /// `--model` for an agent CLI: the model id without an Inspect provider prefix (the engine's cli_model).
    public static func cliModel(_ m: String) -> String {
        var s = m.trimmingCharacters(in: .whitespaces)
        for p in ["anthropic/", "openai/"] where s.hasPrefix(p) { s.removeFirst(p.count) }
        return s
    }

    /// `roof eval run … --background --json` (CONTRACT §2): a seat run passes `--agent --seat`, `--model` only when one is
    /// chosen (omitted = the CLI's default) and `--rules on` only when on (off is the engine's default, so an engine
    /// without the flag still runs a clean setup). Models and agents on API models keep 2.0.3's arguments exactly.
    public func runArguments(task: String, plan: EvalRunPlan, seatLimit: Double = 90) -> [String] {
        guard isSeat, let a = agent else { return plan.arguments(task: task, contestant: contestant, seatLimit: seatLimit) }
        var args = ["run", task, "--agent", a, "--seat", seat ?? "C1", "--seat-limit", String(Int(seatLimit)), "--limit", String(plan.limit)]
        if let m = model { args += ["--model", EvalSetupChoice.cliModel(m)] }
        if rules { args += ["--rules", "on"] }
        if let e = plan.epochs { args += ["--epochs", String(e)] }
        if let q = plan.sampleID { args += ["--sample-id", q] }
        return args + ["--background", "--json"]
    }
    /// `roof eval estimate …` for this setup (CONTRACT §2: `--agent A [--model M]`).
    public func estimateArguments(task: String, plan: EvalRunPlan, seatLimit: Double = 90) -> [String] {
        guard isSeat, let a = agent else { return plan.estimateArguments(task: task, contestant: contestant, seatLimit: seatLimit) }
        var args = ["estimate", task, "--limit", String(plan.limit), "--epochs", String(plan.epochs ?? 1),
                    "--agent", a, "--seat", seat ?? "C1", "--seat-limit", String(Int(seatLimit))]
        if let m = model { args += ["--model", EvalSetupChoice.cliModel(m)] }
        return args + ["--json"]
    }

    /// What is recorded with each result (CONTRACT §1), as far as it is known before the start: "Agent using a model ·
    /// CLI default · Claude Code (version read at start) · rules off · v2".
    public func stampPreview(taskVersion: Int?, rulesHash: String?, rulesFiles: [String] = []) -> String {
        var p = [layer.title]
        p.append(model.map { agent == nil ? EvalModels.short($0) : EvalSetupChoice.cliModel($0) } ?? "CLI default (the model that answers is read from its output)")
        if let a = agent {
            p.append(EvalAgents.name(a) + " (its version is read at start)")
            p.append(rules ? "rules on @ " + (rulesHash ?? "hash read at start") + (rulesFiles.isEmpty ? "" : " (" + rulesFiles.joined(separator: ", ") + ")")
                     : "rules off (no CLAUDE.md or AGENTS.md in the case)")
            p.append(runsOnText)
        }
        p.append(taskVersion.map { "v\($0)" } ?? "task version")
        return p.joined(separator: " · ")
    }

    /// The setups a 2.0.3 plan names (pre-fill from Test them / Run both agents / Test a model on it…).
    public static func from(_ plan: EvalRunPlan) -> [EvalSetupChoice] {
        if !plan.setups.isEmpty { return plan.setups }   // the exact setups (agent + model + rules) win
        return plan.contestants.map { c in
            switch c {
            case .seat(let a): return .seat(a)
            case .apiAgent(let a, let m): return .apiAgent(a, model: m)
            case .model(let m): return .model(m)
            }
        }
    }
    /// The models an agent's CLI can be asked for (its own provider's suggestions), CLI default first (nil).
    public static func models(for agent: String) -> [String?] {
        let provider = agent == "claude_code" ? "Anthropic" : agent == "codex_cli" ? "OpenAI" : ""
        let ms = EvalModels.suggestions.first { $0.group == provider }?.models ?? []
        return [nil] + ms.reversed().map { Optional($0) }
    }
    /// Whether an agent's CLI can be asked for this model: its own provider's models only (Claude Code: Anthropic,
    /// Codex: OpenAI). nil (the CLI default) always can. An unsupported pair is disabled, never swapped for the default.
    public static func supports(agent: String, model: String?) -> Bool {
        guard let m = model.map(cliModel)?.lowercased(), !m.isEmpty else { return true }
        switch agent {
        case "claude_code": return m.hasPrefix("claude") || ["opus", "sonnet", "haiku"].contains(m)
        case "codex_cli": return m.hasPrefix("gpt") || m.hasPrefix("o1") || m.hasPrefix("o3") || m.hasPrefix("o4") || m.contains("codex")
        default: return false
        }
    }
    /// The sheet's note when a rules-on test is repeated: the repeat reads the rules at HEAD now, not the old copy.
    /// QA m4: the sheet never opens on an invalid default ("Start 0 tests"). Our own task with a seat agent installed:
    /// that agent on its CLI default model, rules off; anything else (a public benchmark, no agent): the free stand-in
    /// model on its own, which every task takes and which costs nothing.
    public static func defaults(task: String?, seatAgents: [String]) -> (layer: EvalStamp.Layer, choices: [EvalSetupChoice]) {
        if let t = task, EvalRunPlan.isOwnSet(t), let a = seatAgents.first { return (.agentModel, [.seat(a)]) }
        return (.model, [.model("mockllm/model")])
    }
    public static func repeatRulesNote(old: String?, now: String?) -> String {
        let was = (old?.isEmpty == false) ? " @ \(old!)" : ""
        let new = now.map { " @ \($0)" } ?? " (hash read at start)"
        if let o = old, let n = now, o == n { return "A repeat uses the rules at HEAD now\(new): the same as this test had." }
        return "A repeat uses the rules at HEAD now\(new), not the copy this test had\(was)."
    }
    /// Agents One Roof cannot test with yet (no verified headless mode), named so the sheet says why.
    public static let notYet = ["kimi_code": "Kimi", "gemini_cli": "Gemini CLI", "antigravity": "Antigravity", "opencode": "OpenCode", "goose": "Goose"]
    public static let notYetLine = "Kimi, Gemini CLI, Antigravity, OpenCode and Goose can't run tests yet (no verified headless mode)."
}

/// "What this test can tell you: 10 bugs × 1 try ≈ ±26 points" (from `power`, before the cost).
public enum EvalCanTell {
    public static func line(_ p: EvalPower, own: Bool, setups: Int) -> String {
        let unit = own ? (p.n == 1 ? "bug" : "bugs") : (p.n == 1 ? "question" : "questions")
        var s = "\(p.n) \(unit) × \(p.epochs) \(p.epochs == 1 ? "try" : "tries") ≈ ±\(Int(p.plusMinusPoints.rounded())) points"
        s += setups > 1 ? ", so only a gap bigger than that will show. Everyone gets the same \(own ? "bugs" : "questions"), so they're compared one by one."
            : ", so a score closer than that to another is noise."
        return s
    }
}

/// The rules hash the stamp records (CONTRACT §1): sha256 of the rules files' concatenated bytes, first 7 hex.
public enum EvalRulesHash {
    /// The engine's rules_state hash: sha256 over the files' bytes in path order, first 7 hex. No files = `empty`
    /// (re-review P2: "rules on, no rules files" is a recorded state, not "not recorded").
    public static let empty = "e3b0c44"
    public static func short(_ blobs: [Data]) -> String? {
        let all = blobs.reduce(Data(), +)
        return SHA256.hash(data: all).map { String(format: "%02x", $0) }.joined().prefix(7).description
    }
    /// The instruction file names the engine copies when rules are on (agent_runner RULE_NAMES).
    public static let names = ["CLAUDE.md", "AGENTS.md", "CLAUDE.local.md"]
    /// The instruction files tracked at HEAD in any folder, sorted (the engine's rule_files_at_head), from
    /// `git ls-tree -r --name-only HEAD`.
    public static func files(lsTree: String) -> [String] {
        lsTree.split(separator: "\n").map(String.init)
            .filter { p in names.contains(p.split(separator: "/").last.map(String.init) ?? p) }
            .sorted()
    }
}

/// A seat estimate's extra fields (engine 2.0.4: CONTRACT §2), decoded beside EvalEstimate.
public struct EvalSetupEstimate: Decodable, Equatable, Sendable {
    public var runsOn: String?
    public var apiCost: Double?
    public var cases: Int?
    public var seatNote: String?
    public var seatBasis: String?
    public var seatShare: Double?
    /// A share of the seat's 5-hour window, only when the engine measured it (never an invented share).
    public var measuredShare: Double? { seatBasis == "measured" ? seatShare : nil }
}

// MARK: - Coverage: every 2.0.4 Evals element and its 2.0.5 home, then every 2.0.3 feature and its 2.0.4 home
// (docs/evals-v3-coverage.md renders the same rows; docs/evals-v2-coverage.md is the 2.0.4 page, kept as it was)

public struct EvalsCoverageRow: Equatable, Identifiable, Sendable {
    public enum Status: String, CaseIterable, Sendable { case kept = "Kept", merged = "Merged", moved = "Moved", removed = "Removed", added = "New" }
    /// Which redesign the row belongs to: 2.0.4 → 2.0.5 (v3) or 2.0.3 → 2.0.4 (v2).
    public enum Release: String, CaseIterable, Sendable {
        case v3 = "2.0.4 → 2.0.5", v2 = "2.0.3 → 2.0.4"
        /// The column titles: "2.0.4 element" / "Now in 2.0.5".
        public var featureTitle: String { self == .v3 ? "2.0.4 element" : "2.0.3 feature" }
        public var homeTitle: String { self == .v3 ? "Now in 2.0.5" : "Now in 2.0.4" }
    }
    public var feature: String
    public var was: String
    public var home: String
    /// The 2.0.4 screen (v2 rows only).
    public var screen: EvalsScreen?
    public var status: Status
    public var release: Release
    /// Where the row opens in 2.0.5 (every row, old ones too; nil = every page or none).
    public var v3: EvalsV3Screen?
    public var id: String { feature }
    public init(feature: String, was: String, home: String, screen: EvalsScreen?, status: Status, release: Release = .v2, v3: EvalsV3Screen? = nil) {
        self.feature = feature; self.was = was; self.home = home; self.screen = screen; self.status = status; self.release = release
        self.v3 = v3 ?? screen.map(EvalsCoverage.v3Home)
    }
}

public enum EvalsCoverage {
    private static func r(_ f: String, _ was: String, _ home: String, _ s: EvalsScreen?, _ st: EvalsCoverageRow.Status) -> EvalsCoverageRow {
        EvalsCoverageRow(feature: f, was: was, home: home, screen: s, status: st)
    }
    private static func v(_ f: String, _ was: String, _ home: String, _ s: EvalsV3Screen?, _ st: EvalsCoverageRow.Status) -> EvalsCoverageRow {
        EvalsCoverageRow(feature: f, was: was, home: home, screen: nil, status: st, release: .v3, v3: s)
    }
    /// The whole map: 2.0.4 → 2.0.5 first, then 2.0.3 → 2.0.4.
    public static let rows: [EvalsCoverageRow] = v3Rows + v2Rows

    /// Where a 2.0.4 screen lives in 2.0.5 (the same map as EvalsV3Screen.selfTest).
    public static func v3Home(_ s: EvalsScreen) -> EvalsV3Screen {
        switch s {
        case .overview: return .launch; case .compare: return .oneShotOurs; case .oneTest: return .oneTest; case .allResults: return .allResults
        case .changes: return .changes; case .realHistory: return .realHistory; case .ourTasks: return .ourTasks; case .oneTask: return .oneTask
        case .grader: return .grader; case .benchmarks: return .benchmarks; case .oneBenchmark: return .oneBenchmark; case .setup: return .setup
        case .lessons: return .lessons
        }
    }

    /// NO_REGRESSION.md (all rows), then the 2.0.3 tabs, drill-downs and sheets not named there, then the v1 additions.
    public static let v2Rows: [EvalsCoverageRow] = [
        r("How to: 8 scenes, narration, read marks", "How to tab", "Lessons › How to; Overview's layer picture", .lessons, .merged),
        r("Overview scorecards per eval", "Overview", "Compare per task + All results", .compare, .merged),
        r("Hover card on every number + Lesson ›", "every tab", "Every number, every screen", nil, .kept),
        r("Overview: what changed since last time", "Overview", "Changes", .changes, .kept),
        r("Overview: running now", "Overview", "Set up a test › Running and recent (Running · N in the header)", .setup, .moved),
        r("Overview: one suggested next eval", "Overview", "Overview: \"To answer it properly\" on each question", .overview, .kept),
        r("Setup card: install engine with uv, uv/Docker status", "every tab", "Shown instead of the tabs until the engine is ready", nil, .kept),
        r("Busy and error lines", "every tab", "Under the header", nil, .kept),
        r("Subtitle counts", "header", "Overview subtitle + coverage", .overview, .kept),
        r("Your evals: set page facts", "Your evals › set", "One task › Built from · Picked · Blind guess gets · Best so far", .oneTask, .kept),
        r("Cases table, solved by, sort", "Your evals › set", "One task › the bugs table (hardest first, newest, issue)", .oneTask, .kept),
        r("Build next version: settings, left out on purpose, preview, freeze", "Your evals › set", "One task › Next version", .oneTask, .kept),
        r("Versions list", "Your evals › set", "One task › Versions", .oneTask, .kept),
        r("Start a new one: from fixed bugs (+ CLI)", "Your evals sidebar", "Our tasks › + New task · From fixed bugs in a repo; One task › command line", .ourTasks, .kept),
        r("Judge: Label queue, P/F/S, Why, undo", "Your evals › judge", "Check the grader › Label", .grader, .kept),
        r("Judge: How far to trust it, what would help, also checked", "Your evals › judge", "Check the grader › trust tiles + verdict; right column", .grader, .kept),
        r("Judge: Rubric, Agreement, Versions, Rebuild v2", "Your evals › judge", "Check the grader › Rule · Agreement · Versions; Rebuild grader", .grader, .kept),
        r("Explore: shelves, topics, more topics, graded by, filters, search, rescan", "Explore", "A public benchmark › the list on the left", .oneBenchmark, .kept),
        r("Benchmark: facts, how one question is scored, on this Mac, teaches, watch out, needs, cost, paper, source", "Explore › benchmark", "A public benchmark › How it works", .oneBenchmark, .kept),
        r("Benchmark: Questions (load prompt, gated sets)", "Explore › Questions", "A public benchmark › Questions", .oneBenchmark, .kept),
        r("Benchmark: Published scores, Check now", "Explore › Scores", "A public benchmark › Published scores", .oneBenchmark, .kept),
        r("Benchmark: Your runs", "Explore › Your runs", "A public benchmark › Your runs", .oneBenchmark, .kept),
        r("Run: What (sets, benchmarks, tasks, any benchmark)", "Run tab", "Set up a test › 1 Which task", .setup, .kept),
        r("Run: Who (agents with seat %, API models, on this Mac, any model id, agent on API model)", "Run tab", "Set up a test › 2 Which setups (layer, agent + model, runs on, rules)", .setup, .kept),
        r("Run: How much (questions, attempts, temperature, seed, cap, advanced)", "Run tab", "Set up a test › 3 How many", .setup, .kept),
        r("Run: What this run can tell you", "Run tab", "Set up a test › What this test can tell you (before the cost)", .setup, .kept),
        r("Run: Cost before you start, seat share, cap ×1.5, Start N", "Run tab", "Set up a test › Before you start", .setup, .kept),
        r("Run: Queue (two at a time, Run anyway, Cancel, Resume, Results, show all)", "Run tab", "Set up a test › Running and recent", .setup, .kept),
        r("Results: By eval leaderboard, version switch", "Results", "Compare (per task); versions in One task", .compare, .merged),
        r("Results: Compare A vs B, paired verdict, see the N cases", "Results", "Compare headline + Compare with…", .compare, .kept),
        r("Results: Over time, possible drop, re-run ×3", "Results", "Changes", .changes, .kept),
        r("Results: All × all + every run", "Results", "All results", .allResults, .kept),
        r("Results: X-ray", "Results", "Real history", .realHistory, .moved),
        r("Results: Export CSV · JSON", "Results", "All results", .allResults, .kept),
        r("Run detail: facts, score strip, answers list, filters, sort", "Run detail", "One test, bug by bug", .oneTest, .kept),
        r("Run detail: code check · judge · you, add to regression set, compare with, run again", "Run detail", "One test, bug by bug", .oneTest, .kept),
        r("Learn: 16 lessons, Try it, In your runs, first eval steps, where this shows up", "Learn tab", "Lessons (In your tests, Your first test)", .lessons, .kept),
        r("Keys, Hugging Face sign-in, providers", "Settings › Evals", "Settings › Evals (unchanged)", nil, .kept),
        r("Second Draft banner on drill-downs", "drill-downs", "One Draft tag by the title", nil, .removed),
        // 2.0.3 parts not named above
        r("Your evals: Judges list with trust and labels to go", "Your evals sidebar", "Our tasks › the grader banner on its task + Check the grader", .ourTasks, .moved),
        r("Your evals: From past sessions / From a file of questions (coming)", "Your evals sidebar", "Our tasks › the two + New task tiles marked coming", .ourTasks, .kept),
        r("Your evals: A judge for prose answers", "Your evals sidebar", "New test or task ▾ › New grader", .ourTasks, .moved),
        r("Explore: Judges shelf", "Explore", "A public benchmark › Judges shelf (opens Check the grader)", .oneBenchmark, .kept),
        r("Explore: Run this…", "Explore › benchmark", "A public benchmark › Test a model on it… (Set up a test pre-filled)", .oneBenchmark, .kept),
        r("Run: where its code runs (Docker, Modal, cloud sandboxes)", "Run tab", "Set up a test › 3 How many › Where its code runs", .setup, .kept),
        r("Run: Hugging Face gate on gated sets", "Run tab", "Set up a test › Before you start (Start stays off until signed in)", .setup, .kept),
        r("Learn: Try it widgets (16, local maths, no cost)", "Learn tab", "Lessons › Try it", .lessons, .kept),
        // v1 additions (v1_evals.html, v1_BUILD-NOTES.md)
        r("The stamp: layer · model · agent + CLI version · rules on/off @ hash · task version", "new in 2.0.4", "Every score; Set up a test previews it", .setup, .added),
        r("Our rules off (clean) or on @ hash", "new in 2.0.4", "Set up a test › 2 Which setups › Our rules", .setup, .added),
        r("Agent and model picked together (agent × model grid)", "new in 2.0.4", "Set up a test › 2 Which setups; Compare's grid", .setup, .added),
        r("Verdicts by rule (paired 95 % range, no winner under 10 shared bugs, blind guess)", "new in 2.0.4", "Compare, One task, Overview", .compare, .added),
        r("What a test can tell you before what it costs (power)", "new in 2.0.4", "Set up a test › 3 How many; One task › Next version", .setup, .added),
        r("Plain task names and the blind guess", "new in 2.0.4", "Our tasks, One task, Compare", .ourTasks, .added),
        r("Public benchmarks framed by purpose", "new in 2.0.4", "Public benchmarks › three purpose cards", .benchmarks, .added),
        r("Where everything went (this map)", "new in 2.0.4", "Lessons › Where everything went; docs/evals-v2-coverage.md", .lessons, .added),
    ]

    /// LAB-2261 · every 2.0.4 Evals element (the 330 of the 2.0.4 inventory) and its 2.0.5 home, then what 2.0.5 adds.
    /// docs/evals-v3-coverage.md renders the same rows; EvalsLaneBTests ties them.
    public static let v3Rows: [EvalsCoverageRow] = [
        v("Header: title and back crumb", "header", "Breadcrumb ‹ Evals › job › source (› item); each step but the last opens its page", nil, .moved),
        v("Header: one Draft tag", "header", "Header, unchanged", nil, .kept),
        v("Header: subtitle counts", "header", "Header subtitle (benchmarks · our tasks · graders · finished tests · running), unchanged", .launch, .kept),
        v("Header: six tabs", "header", "The launch view (one bar per kind of job) and the breadcrumb", .launch, .merged),
        v("Header: setup card and Install", "header", "Shown instead of every page until the engine is ready, unchanged", nil, .kept),
        v("Header: Checking the eval engine… line", "header", "Under the header, unchanged", nil, .kept),
        v("Header: Running · N", "header", "Header, unchanged: opens Set up a test › Running and recent", .setup, .kept),
        v("Header: New test or task ▾", "header", "Header, unchanged (the name stays, not + New)", .ourTasks, .kept),
        v("Header: Lessons button", "header", "Header, unchanged", .lessons, .kept),
        v("Header: busy and error lines", "header", "Under the header, unchanged", nil, .kept),
        v("Header: two sheets over any page", "header", "Set up a test and Lessons open over any page, unchanged", nil, .kept),
        v("Keys: Esc closes a sheet", "keys", "Unchanged", nil, .kept),
        v("Keys: ⌘[ back", "keys", "⌘[ goes back: a drill-down first, then the breadcrumb, then the launch view", nil, .kept),
        v("Keys: ⌃⌥1–6 open the six tabs", "keys", "⌃⌥0–8: the launch view, the five segment pages, Public agent benchmarks, Changes, Real history", .launch, .moved),
        v("Header: refresh every 3 seconds while tests run", "header", "Unchanged", nil, .kept),
        v("Header: a started test opens the queue", "header", "Unchanged: Start opens Set up a test › Running and recent", .setup, .kept),
        v("Settings: Redesigned Evals switch", "Settings › Evals", "Settings › Evals, unchanged: off still shows the 1.9.37 Evals", nil, .kept),
        v("Settings: Evals › Hugging Face", "Settings › Evals", "Settings › Evals, unchanged", nil, .kept),
        v("Self-test: the 13 screen names", "self-test", "18 names, one per 2.0.5 screen (below); each 2.0.4 name opens its 2.0.5 home", nil, .moved),
        v("Self-test: other 2.0.4 spellings", "self-test", "Still accepted, mapped below", nil, .kept),
        v("Self-test: the 25 names from 2.0.3 and 1.9.37", "self-test", "Still accepted, mapped below", nil, .kept),
        v("Self-test: the other variables (run, set, judge …)", "self-test", "Every ONEROOF_SELFTEST_EVALS_* variable keeps working", nil, .kept),
        v("Self-test: COMPARE_VIEW=grid", "self-test", "Opens the Agent × model grid on Agent jobs › Our tests", .agentOurs, .moved),
        v("Self-test: HOVER and QUESTION", "self-test", "Unchanged", nil, .kept),
        v("Overview: inside / outside layer picture", "Overview", "Launch view: one bar per kind of job, split by where its evidence comes from", .launch, .merged),
        v("Overview: top band, the model", "Overview", "Launch view: the One-shot jobs bar (Public tests · Ours · Loops)", .launch, .merged),
        v("Overview: middle band, the agent out of the box", "Overview", "Agent jobs › Our tests with Rules: clean, and Agent jobs › Public agent benchmarks", .agentOurs, .moved),
        v("Overview: stand-in count", "Overview", "Launch view subtitle hover; the stand-in line on Our tests", .launch, .moved),
        v("Overview: waiting count", "Overview", "Launch view bar hover; waiting rows on Our tests", .launch, .moved),
        v("Overview: N agent tasks outside", "Overview", "The Public agent benchmarks button under the agent bar", .agentPublic, .moved),
        v("Overview: grader runs counted apart", "Overview", "Launch view: grader runs counted apart from setups", .launch, .moved),
        v("Overview: counted from the run store note", "Overview", "Launch view bar hover", .launch, .moved),
        v("Overview: base band, the full setup", "Overview", "Launch view: the Agent jobs bar (Our tests · Our loop runs)", .launch, .merged),
        v("Overview: band clicks", "Overview", "Each bar segment opens its page", .launch, .kept),
        v("Overview: How to read Evals and the first-test link", "Overview", "Lessons (header button) › Your first test, free", .lessons, .moved),
        v("Overview: question 1, which setup does best", "Overview", "One-shot jobs › Our tests and Agent jobs › Our tests: the question and a one-sentence answer", .oneShotOurs, .moved),
        v("Overview: question 1 rules and the Open the queue fix", "Overview", "Agent jobs › Our tests: the answer and Open the queue", .agentOurs, .moved),
        v("Overview: question 1 mini-chart with the blind-guess tick", "Overview", "Our tests rows: squares with the blind-guess tick", .oneShotOurs, .merged),
        v("Overview: question 1, to answer it properly", "Overview", "Our tests pages, under the answer", .oneShotOurs, .moved),
        v("Overview: question 2, did my last change help", "Overview", "Agent jobs › Changes; the launch view's Did my last change help? button", .changes, .moved),
        v("Overview: what a test records today", "Overview", "Agent jobs › Our tests: What a test records today; Lessons", .agentOurs, .moved),
        v("Overview: question 2 fix (model per commit)", "Overview", "Agent jobs › Our tests: What a test records today", .agentOurs, .moved),
        v("Overview: question 3, what git says", "Overview", "Agent jobs › Real history; the launch view's What does git say about our real work? button", .realHistory, .moved),
        v("Overview: question 3 bars per agent", "Overview", "Real history: one card and bar per agent", .realHistory, .merged),
        v("Overview: question 3 fix (sign every commit)", "Overview", "Real history: the No agent name card", .realHistory, .merged),
        v("Overview: also suggested", "Overview", "Launch view (it still reads the overview answer)", .launch, .moved),
        v("Overview: error line", "Overview", "Under the header on the launch view", .launch, .moved),
        v("Overview: the overview engine call", "Overview", "Still read by the launch view: suggestions, the re-run ×3 card on Changes, the error line", .launch, .kept),
        v("Verdicts: two-setup sentences", "every page", "Same rules, every page that compares", .oneShotOurs, .kept),
        v("Verdicts: against the blind guess", "every page", "Same rules: Our tests, One task, One test", .oneShotOurs, .kept),
        v("Verdicts: on new bugs, expect L to H", "every page", "Same rules: Our tests, One test", .oneShotOurs, .kept),
        v("Verdicts: a blind guess gets N", "every page", "Same rules: Our tests, One task", .oneShotOurs, .kept),
        v("Verdicts: Changes lead and the unknown-floor caveat", "Changes", "Agent jobs › Changes, unchanged", .changes, .kept),
        v("Verdicts: how far to trust the grader", "Check the grader", "Check the grader, unchanged", .grader, .kept),
        v("Compare: task cards", "Compare", "One-shot jobs › Our tests and Agent jobs › Our tests: task cards, with a kind chip", .oneShotOurs, .kept),
        v("Compare: All results button", "Compare", "Our tests pages: All results ›; the launch view's Every result, one grid", .allResults, .kept),
        v("Compare: empty, error and reading states", "Compare", "One-shot jobs › Our tests and Agent jobs › Our tests, unchanged", .oneShotOurs, .kept),
        v("Compare: headline sentence", "Compare", "One-shot jobs › Our tests and Agent jobs › Our tests: the one-sentence answer", .oneShotOurs, .kept),
        v("Compare: By setup · Agent × model switch", "Compare", "Agent jobs › Our tests", .agentOurs, .kept),
        v("Compare: vN · frozen bugs note", "Compare", "One-shot jobs › Our tests and Agent jobs › Our tests, unchanged", .oneShotOurs, .kept),
        v("Compare: ranked setup rows, ↑ ↓ and Return", "Compare", "One-shot jobs › Our tests and Agent jobs › Our tests, unchanged", .oneShotOurs, .kept),
        v("Compare: row score and verdict against the blind guess", "Compare", "One-shot jobs › Our tests and Agent jobs › Our tests, unchanged", .oneShotOurs, .kept),
        v("Compare: tick two for the paired verdict", "Compare", "One-shot jobs › Our tests and Agent jobs › Our tests, unchanged", .oneShotOurs, .kept),
        v("Compare: row caption by layer", "Compare", "One-shot jobs › Our tests and Agent jobs › Our tests: tested as model · agent clean · agent with our rules", .oneShotOurs, .kept),
        v("Compare: stamp line on rows", "Compare", "One-shot jobs › Our tests and Agent jobs › Our tests, unchanged", .oneShotOurs, .kept),
        v("Compare: waiting, queued, expired and failed rows", "Compare", "One-shot jobs › Our tests and Agent jobs › Our tests, unchanged", .agentOurs, .kept),
        v("Compare: Open the queue and Resume or start again", "Compare", "One-shot jobs › Our tests and Agent jobs › Our tests, unchanged", .agentOurs, .kept),
        v("Compare: bug squares and the blind-guess tick", "Compare", "One-shot jobs › Our tests and Agent jobs › Our tests, unchanged", .oneShotOurs, .kept),
        v("Compare: missed-bugs sentence", "Compare", "One-shot jobs › Our tests and Agent jobs › Our tests, unchanged", .oneShotOurs, .kept),
        v("Compare: cost, $ per right answer, date", "Compare", "One-shot jobs › Our tests and Agent jobs › Our tests, unchanged", .oneShotOurs, .kept),
        v("Compare: legend and stand-in line", "Compare", "One-shot jobs › Our tests and Agent jobs › Our tests, unchanged", .oneShotOurs, .kept),
        v("Compare: paired card and its empty texts", "Compare", "One-shot jobs › Our tests and Agent jobs › Our tests, unchanged", .oneShotOurs, .kept),
        v("Compare: paired verdict, axis, only-line, See the N bugs", "Compare", "One-shot jobs › Our tests and Agent jobs › Our tests, unchanged", .oneShotOurs, .kept),
        v("Compare: Agent × model grid", "Compare", "Agent jobs › Our tests › Agent × model grid", .agentOurs, .moved),
        v("Compare: grid rules off / on picker", "Compare", "Agent × model grid: Rules: with our rules (default) · clean", .agentOurs, .kept),
        v("Compare: grid done cell", "Compare", "Agent × model grid, unchanged", .agentOurs, .kept),
        v("Compare: grid live cell", "Compare", "Agent × model grid, unchanged", .agentOurs, .kept),
        v("Compare: grid not run · Test cell", "Compare", "Agent × model grid, unchanged", .agentOurs, .kept),
        v("Compare: grid not available cell", "Compare", "Agent × model grid, unchanged", .agentOurs, .kept),
        v("Compare: grid No model floor row", "Compare", "Agent × model grid, unchanged", .agentOurs, .kept),
        v("Compare: grid CLI-default note", "Compare", "Agent × model grid, unchanged", .agentOurs, .kept),
        v("Compare: not tested on this task yet (N) and Test them", "Compare", "One-shot jobs › Our tests and Agent jobs › Our tests, unchanged", .oneShotOurs, .kept),
        v("Compare: engine leaderboard by setup, compare", "Compare", "Unchanged", .oneShotOurs, .kept),
        v("One test: opens on the newest test", "One test", "One test, bug by bug, unchanged", .oneTest, .kept),
        v("One test: title and subtitle", "One test", "One test, bug by bug, unchanged", .oneTest, .kept),
        v("One test: score strip and verdict", "One test", "One test, bug by bug, unchanged", .oneTest, .kept),
        v("One test: squares and tick, clickable", "One test", "One test, bug by bug, unchanged", .oneTest, .kept),
        v("One test: numbers line (expect, cost, $ per right, date, seed)", "One test", "One test, bug by bug, unchanged", .oneTest, .kept),
        v("One test: Compare with…", "One test", "One test, bug by bug, unchanged", .oneTest, .kept),
        v("One test: Test again", "One test", "One test, bug by bug, unchanged", .oneTest, .kept),
        v("One test: stamp line", "One test", "One test, bug by bug, unchanged", .oneTest, .kept),
        v("One test: facts line", "One test", "One test, bug by bug, unchanged", .oneTest, .kept),
        v("One test: Test again reading and unreadable notes", "One test", "One test, bug by bug, unchanged", .oneTest, .kept),
        v("One test: judged code score, trust line, metrics", "One test", "One test, bug by bug, unchanged", .oneTest, .kept),
        v("One test: failure line, What to do, Resume", "One test", "One test, bug by bug, unchanged", .oneTest, .kept),
        v("One test: toast", "One test", "One test, bug by bug, unchanged", .oneTest, .kept),
        v("One test: All · Wrong · Grader ≠ you chips", "One test", "One test, bug by bug, unchanged", .oneTest, .kept),
        v("One test: sort menu", "One test", "One test, bug by bug, unchanged", .oneTest, .kept),
        v("One test: N bugs where the two tests differ", "One test", "One test, bug by bug, unchanged", .oneTest, .kept),
        v("One test: answer rows, ↑ ↓ and W", "One test", "One test, bug by bug, unchanged", .oneTest, .kept),
        v("One test: bug header and Label for the grader", "One test", "One test, bug by bug, unchanged", .oneTest, .kept),
        v("One test: Add to next version sheet", "One test", "One test, bug by bug, unchanged", .oneTest, .kept),
        v("One test: what it named vs what the fix changed", "One test", "One test, bug by bug, unchanged", .oneTest, .kept),
        v("One test: attempt switcher", "One test", "One test, bug by bug, unchanged", .oneTest, .kept),
        v("One test: code check · grader · you boxes, P / F quick label", "One test", "One test, bug by bug, unchanged", .oneTest, .kept),
        v("One test: takeaway and B's answer", "One test", "One test, bug by bug, unchanged", .oneTest, .kept),
        v("One test: reasoning, transcript, tool calls, expected answer, scorers", "One test", "One test, bug by bug, unchanged", .oneTest, .kept),
        v("One test: refresh while a test runs", "One test", "One test, bug by bug, unchanged", .oneTest, .kept),
        v("One test: engine calls", "One test", "Unchanged", .oneTest, .kept),
        v("All results: Export CSV · JSON", "All results", "All results, unchanged", .allResults, .kept),
        v("All results: grid and its order", "All results", "All results, unchanged, plus a Kind column", .allResults, .kept),
        v("All results: cells, dashed under 30", "All results", "All results, unchanged", .allResults, .kept),
        v("All results: grader and labeller columns", "All results", "All results, unchanged", .allResults, .kept),
        v("All results: scroll note and legend", "All results", "All results, unchanged", .allResults, .kept),
        v("All results: empty state and Set up a test", "All results", "All results, unchanged", .allResults, .kept),
        v("All results: every test list, Show all", "All results", "All results, unchanged", .allResults, .kept),
        v("Changes: intro line", "Changes", "Agent jobs › Changes, unchanged", .changes, .kept),
        v("Changes: we can't tell yet, Test the baseline now", "Changes", "Agent jobs › Changes, unchanged", .changes, .kept),
        v("Changes: recent changes card", "Changes", "Agent jobs › Changes, unchanged", .changes, .kept),
        v("Changes: Read again", "Changes", "Agent jobs › Changes, unchanged", .changes, .kept),
        v("Changes: change rows and Test before & after", "Changes", "Agent jobs › Changes, unchanged", .changes, .kept),
        v("Changes: row status rule", "Changes", "Agent jobs › Changes, unchanged", .changes, .kept),
        v("Changes: empty, error and reading states", "Changes", "Agent jobs › Changes, unchanged", .changes, .kept),
        v("Changes: before / after squares and ring", "Changes", "Agent jobs › Changes, unchanged", .changes, .kept),
        v("Changes: verdict line", "Changes", "Agent jobs › Changes, unchanged", .changes, .kept),
        v("Changes: floor of the pair's own version", "Changes", "Agent jobs › Changes, unchanged", .changes, .kept),
        v("Changes: never draws a pair that spans several changes", "Changes", "Agent jobs › Changes, unchanged", .changes, .kept),
        v("Changes: same setup, tested again", "Changes", "Agent jobs › Changes, unchanged", .changes, .kept),
        v("Changes: Re-run ×3", "Changes", "Agent jobs › Changes, unchanged", .changes, .kept),
        v("Changes: re-test after every change switch", "Changes", "Agent jobs › Changes, unchanged", .changes, .kept),
        v("Changes: engine changes, compare, leaderboard", "Changes", "Unchanged", .changes, .kept),
        v("Real history: not a test line", "Real history", "Agent jobs › Real history, unchanged", .realHistory, .kept),
        v("Real history: repo picker (several repos, Add a repo, Back to our tasks' repos)", "Real history", "Agent jobs › Real history, unchanged", .realHistory, .kept),
        v("Real history: 30 / 60 / 90 days", "Real history", "Agent jobs › Real history, unchanged", .realHistory, .kept),
        v("Real history: Read again", "Real history", "Agent jobs › Real history, unchanged", .realHistory, .kept),
        v("Real history: empty, error and reading states", "Real history", "Agent jobs › Real history, unchanged", .realHistory, .kept),
        v("Real history: headline sentence", "Real history", "Agent jobs › Real history, unchanged", .realHistory, .kept),
        v("Real history: meta line with the computed date", "Real history", "Agent jobs › Real history, unchanged", .realHistory, .kept),
        v("Real history: agent card, commits and lines", "Real history", "Agent jobs › Real history, unchanged", .realHistory, .kept),
        v("Real history: split bar", "Real history", "Agent jobs › Real history, unchanged; its followed-by-a-fix part opens those commits", .realHistory, .kept),
        v("Real history: followed by a fix", "Real history", "Agent jobs › Real history, unchanged; See the N commits opens them", .realHistory, .kept),
        v("Real history: rewritten in N days", "Real history", "Agent jobs › Real history, unchanged; See the N commits opens them", .realHistory, .kept),
        v("Real history: fixes its own work", "Real history", "Agent jobs › Real history, unchanged", .realHistory, .kept),
        v("Real history: reverted", "Real history", "Agent jobs › Real history, unchanged; See the N commits opens them", .realHistory, .kept),
        v("Real history: model per commit, not recorded", "Real history", "Agent jobs › Real history, unchanged", .realHistory, .kept),
        v("Real history: No agent name card, hatched", "Real history", "Agent jobs › Real history, unchanged", .realHistory, .kept),
        v("Real history: how this fits with the tests", "Real history", "Agent jobs › Real history, unchanged", .realHistory, .kept),
        v("Real history: test-vs-history table", "Real history", "Agent jobs › Real history, unchanged", .realHistory, .kept),
        v("Real history: Open Compare", "Real history", "Agent jobs › Real history, unchanged, now a button", .realHistory, .kept),
        v("Real history: foot note (from git alone)", "Real history", "Agent jobs › Real history, unchanged", .realHistory, .kept),
        v("Real history: lesson hints on git numbers", "Real history", "Agent jobs › Real history, unchanged", .realHistory, .kept),
        v("Real history: engine xray", "Real history", "Unchanged, plus the commit lists", .realHistory, .kept),
        v("Our tasks: intro line", "Our tasks", "Our tasks, unchanged", .ourTasks, .kept),
        v("Our tasks: empty state", "Our tasks", "Our tasks, unchanged", .ourTasks, .kept),
        v("Our tasks: task card", "Our tasks", "Our tasks, unchanged, plus a kind chip", .ourTasks, .kept),
        v("Our tasks: N real bugs and the ± hover", "Our tasks", "Our tasks, unchanged", .ourTasks, .kept),
        v("Our tasks: layer chips per task", "Our tasks", "Our tasks: tested as chips (model · agent clean · agent with our rules)", .ourTasks, .kept),
        v("Our tasks: next version footer, Preview, See the bugs", "Our tasks", "Our tasks, unchanged", .ourTasks, .kept),
        v("Our tasks: grader banner, Check, Start labelling", "Our tasks", "Our tasks, unchanged", .ourTasks, .kept),
        v("Our tasks: + New task tiles (two coming)", "Our tasks", "Our tasks, unchanged", .ourTasks, .kept),
        v("Our tasks: graders list", "Our tasks", "Our tasks, unchanged", .ourTasks, .kept),
        v("Our tasks: New task sheet", "Our tasks", "Our tasks, unchanged", .ourTasks, .kept),
        v("Our tasks: coming sheets", "Our tasks", "Our tasks, unchanged", .ourTasks, .kept),
        v("Our tasks: New grader sheet", "Our tasks", "Our tasks, unchanged", .ourTasks, .kept),
        v("Our tasks: engine calls", "Our tasks", "Unchanged", .ourTasks, .kept),
        v("One task: title and meta", "One task", "One task, unchanged", .oneTask, .kept),
        v("One task: Test setups on it…", "One task", "One task, unchanged", .oneTask, .kept),
        v("One task: built from", "One task", "One task, unchanged", .oneTask, .kept),
        v("One task: picked and left out", "One task", "One task, unchanged", .oneTask, .kept),
        v("One task: blind guess gets, and its rule", "One task", "One task, unchanged", .oneTask, .kept),
        v("One task: best so far and its verdict", "One task", "One task, unchanged", .oneTask, .kept),
        v("One task: bugs table, sort, solved by", "One task", "One task, unchanged", .oneTask, .kept),
        v("One task: a bug row opens every setup's answer", "One task", "One task, unchanged", .oneTask, .kept),
        v("One task: note under the table", "One task", "One task, unchanged", .oneTask, .kept),
        v("One task: Next version card", "One task", "One task, unchanged", .oneTask, .kept),
        v("One task: Versions card", "One task", "One task, unchanged", .oneTask, .kept),
        v("One task: command line card", "One task", "One task, unchanged", .oneTask, .kept),
        v("One task: engine calls", "One task", "Unchanged", .oneTask, .kept),
        v("Check the grader: no grader yet", "Check the grader", "Check the grader, unchanged", .grader, .kept),
        v("Check the grader: title and subtitle", "Check the grader", "Check the grader, unchanged", .grader, .kept),
        v("Check the grader: Label · Rule · Agreement · Versions", "Check the grader", "Check the grader, unchanged", .grader, .kept),
        v("Check the grader: trust tiles", "Check the grader", "Check the grader, unchanged", .grader, .kept),
        v("Check the grader: verdict tile and Run the grader", "Check the grader", "Check the grader, unchanged", .grader, .kept),
        v("Check the grader: queue and progress", "Check the grader", "Check the grader, unchanged", .grader, .kept),
        v("Check the grader: labelled by you, Undo ⌘Z", "Check the grader", "Check the grader, unchanged", .grader, .kept),
        v("Check the grader: queue note (the first 10 teach)", "Check the grader", "Check the grader, unchanged", .grader, .kept),
        v("Check the grader: bug report and what the fix changed", "Check the grader", "Check the grader, unchanged", .grader, .kept),
        v("Check the grader: note, files named, what the grader and the other model said", "Check the grader", "Check the grader, unchanged", .grader, .kept),
        v("Check the grader: your label line", "Check the grader", "Check the grader, unchanged", .grader, .kept),
        v("Check the grader: A / B / T keys and buttons, ↑ ↓ in the queue", "Check the grader", "Check the grader, unchanged", .grader, .kept),
        v("Check the grader: every note labelled", "Check the grader", "Check the grader, unchanged", .grader, .kept),
        v("Check the grader: the rule and Edit", "Check the grader", "Check the grader, unchanged", .grader, .kept),
        v("Check the grader: versions and Rebuild", "Check the grader", "Check the grader, unchanged", .grader, .kept),
        v("Check the grader: what would help", "Check the grader", "Check the grader, unchanged", .grader, .kept),
        v("Check the grader: also checked", "Check the grader", "Check the grader, unchanged", .grader, .kept),
        v("Check the grader: rule draft and diff", "Check the grader", "Check the grader, unchanged", .grader, .kept),
        v("Check the grader: agreement per label source", "Check the grader", "Check the grader, unchanged", .grader, .kept),
        v("Check the grader: confusion grid", "Check the grader", "Check the grader, unchanged", .grader, .kept),
        v("Check the grader: a grid cell opens those notes", "Check the grader", "Check the grader, unchanged", .grader, .kept),
        v("Check the grader: Versions part", "Check the grader", "Check the grader, unchanged", .grader, .kept),
        v("Check the grader: engine calls", "Check the grader", "Unchanged", .grader, .kept),
        v("Public benchmarks: headline", "Public benchmarks", "One-shot jobs › Public tests (model benchmarks) and Agent jobs › Public agent benchmarks", .oneShotPublic, .moved),
        v("Public benchmarks: context, never the answer", "Public benchmarks", "One-shot jobs › Public tests, unchanged", .oneShotPublic, .kept),
        v("Public benchmarks: table with a Layer column", "Public benchmarks", "Public tests and Public agent benchmarks; the column reads Model or Agent, out of the box", .oneShotPublic, .kept),
        v("Public benchmarks: small-sample warning", "Public benchmarks", "One-shot jobs › Public tests, unchanged", .oneShotPublic, .kept),
        v("Public benchmarks: empty and reading states", "Public benchmarks", "Public tests and Public agent benchmarks, unchanged", .oneShotPublic, .kept),
        v("Public benchmarks: model rows before agent rows", "Public benchmarks", "Split: model rows on One-shot jobs › Public tests, agent rows on Public agent benchmarks", .agentPublic, .moved),
        v("Public benchmarks: three purpose cards", "Public benchmarks", "One-shot jobs › Public tests, unchanged", .oneShotPublic, .kept),
        v("Public benchmarks: engine calls", "Public benchmarks", "Unchanged", .oneShotPublic, .kept),
        v("Library: one of N line", "A public benchmark", "Public benchmarks › the library, unchanged", .benchmarks, .kept),
        v("Library: search ⌘F", "A public benchmark", "Public benchmarks › the library, unchanged", .benchmarks, .kept),
        v("Library: Start here shelf", "A public benchmark", "Public benchmarks › the library, unchanged", .benchmarks, .kept),
        v("Library: Your evals shelf", "A public benchmark", "Public benchmarks › the library, unchanged", .benchmarks, .kept),
        v("Library: Agent tasks shelf", "A public benchmark", "Public benchmarks › the library, unchanged; also reached from Public agent benchmarks", .benchmarks, .kept),
        v("Library: Judges shelf opens Check the grader", "A public benchmark", "Public benchmarks › the library, unchanged", .benchmarks, .kept),
        v("Library: topics and more topics", "A public benchmark", "Public benchmarks › the library, unchanged", .benchmarks, .kept),
        v("Library: graded by", "A public benchmark", "Public benchmarks › the library, unchanged", .benchmarks, .kept),
        v("Library: No Docker and I've run it filters", "A public benchmark", "Public benchmarks › the library, unchanged", .benchmarks, .kept),
        v("Library: benchmark rows, chips and hint", "A public benchmark", "Public benchmarks › the library, unchanged", .benchmarks, .kept),
        v("Library: footer, Rescan and versions", "A public benchmark", "Public benchmarks › the library, unchanged", .benchmarks, .kept),
        v("A public benchmark: header, Test a model on it, lock card", "A public benchmark", "A public benchmark, unchanged", .oneBenchmark, .kept),
        v("A public benchmark: the four parts", "A public benchmark", "A public benchmark, unchanged", .oneBenchmark, .kept),
        v("A public benchmark: facts strip and hovers", "A public benchmark", "A public benchmark, unchanged", .oneBenchmark, .kept),
        v("A public benchmark: how one question is scored", "A public benchmark", "A public benchmark, unchanged", .oneBenchmark, .kept),
        v("A public benchmark: on this Mac so far, Why", "A public benchmark", "A public benchmark, unchanged", .oneBenchmark, .kept),
        v("A public benchmark: teaches, watch out", "A public benchmark", "A public benchmark, unchanged", .oneBenchmark, .kept),
        v("A public benchmark: needs, cost, paper", "A public benchmark", "A public benchmark, unchanged", .oneBenchmark, .kept),
        v("A public benchmark: tasks list and people baseline", "A public benchmark", "A public benchmark, unchanged", .oneBenchmark, .kept),
        v("A public benchmark: own set version", "A public benchmark", "A public benchmark, unchanged", .oneBenchmark, .kept),
        v("A public benchmark: your runs", "A public benchmark", "A public benchmark, unchanged", .oneBenchmark, .kept),
        v("A public benchmark: engine calls", "A public benchmark", "Unchanged", .oneBenchmark, .kept),
        v("Questions: header, meta, source, lock", "A public benchmark › Questions", "A public benchmark, unchanged", .oneBenchmark, .kept),
        v("Questions: confirm download", "A public benchmark › Questions", "A public benchmark, unchanged", .oneBenchmark, .kept),
        v("Questions: gated card", "A public benchmark › Questions", "A public benchmark, unchanged", .oneBenchmark, .kept),
        v("Questions: downloading and failed", "A public benchmark › Questions", "A public benchmark, unchanged", .oneBenchmark, .kept),
        v("Questions: filter chips", "A public benchmark › Questions", "A public benchmark, unchanged", .oneBenchmark, .kept),
        v("Questions: R for 10 at random, ↑ ↓, pages", "A public benchmark › Questions", "A public benchmark, unchanged", .oneBenchmark, .kept),
        v("Questions: dot rows", "A public benchmark › Questions", "A public benchmark, unchanged", .oneBenchmark, .kept),
        v("Questions: legend and seed", "A public benchmark › Questions", "A public benchmark, unchanged", .oneBenchmark, .kept),
        v("Questions: question detail", "A public benchmark › Questions", "A public benchmark, unchanged", .oneBenchmark, .kept),
        v("Questions: what the model sees, how it's marked, runs that answered it", "A public benchmark › Questions", "A public benchmark, unchanged", .oneBenchmark, .kept),
        v("Questions: Add to an eval set, Run just this one", "A public benchmark › Questions", "A public benchmark, unchanged", .oneBenchmark, .kept),
        v("Questions: engine items and item", "A public benchmark › Questions", "Unchanged", .oneBenchmark, .kept),
        v("Published scores: Check now", "A public benchmark › Published scores", "A public benchmark, unchanged", .oneBenchmark, .kept),
        v("Published scores: table with Agent rows", "A public benchmark › Published scores", "A public benchmark, unchanged", .oneBenchmark, .kept),
        v("Published scores: failed, empty and weekly states", "A public benchmark › Published scores", "A public benchmark, unchanged", .oneBenchmark, .kept),
        v("Published scores: engine scores", "A public benchmark › Published scores", "Unchanged", .oneBenchmark, .kept),
        v("Set up a test: header, subtitle, Close", "Set up a test", "Set up a test, unchanged", .setup, .kept),
        v("Set up a test: what pre-fills it", "Set up a test", "Set up a test, unchanged", .setup, .kept),
        v("Set up a test: a valid default (never Start 0 tests)", "Set up a test", "Set up a test, unchanged", .setup, .kept),
        v("Set up a test: how one test works strip", "Set up a test", "Set up a test, unchanged", .setup, .kept),
        v("Set up a test: our sets", "Set up a test", "Set up a test, unchanged", .setup, .kept),
        v("Set up a test: graders as tasks", "Set up a test", "Set up a test, unchanged", .setup, .kept),
        v("Set up a test: public benchmarks and + a public benchmark", "Set up a test", "Set up a test, unchanged", .setup, .kept),
        v("Set up a test: layer switch (three layers)", "Set up a test", "Set up a test › 2: One-shot · Agent (an agent is picked with its model)", .setup, .moved),
        v("Set up a test: model rows and no-key hints", "Set up a test", "Set up a test, unchanged", .setup, .kept),
        v("Set up a test: + any model id", "Set up a test", "Set up a test, unchanged", .setup, .kept),
        v("Set up a test: seat agent rows, model menu, seat %", "Set up a test", "Set up a test, unchanged", .setup, .kept),
        v("Set up a test: + an agent with another model", "Set up a test", "Set up a test, unchanged", .setup, .kept),
        v("Set up a test: + an agent on an API key", "Set up a test", "Set up a test, unchanged", .setup, .kept),
        v("Set up a test: full setup rows, rules on", "Set up a test", "Set up a test › Agent: Rules: with our rules (the default)", .setup, .kept),
        v("Set up a test: rules off (clean)", "Set up a test", "Set up a test › Agent: Rules: clean", .setup, .kept),
        v("Set up a test: rules files line @ hash", "Set up a test", "Set up a test, unchanged", .setup, .kept),
        v("Set up a test: seats answer our own tasks only", "Set up a test", "Set up a test, unchanged", .setup, .kept),
        v("Set up a test: agents not ready yet", "Set up a test", "Set up a test, unchanged", .setup, .kept),
        v("Set up a test: how many fields", "Set up a test", "Set up a test, unchanged", .setup, .kept),
        v("Set up a test: where its code runs and set-up hints", "Set up a test", "Set up a test, unchanged", .setup, .kept),
        v("Set up a test: cloud sandbox price note", "Set up a test", "Set up a test, unchanged", .setup, .kept),
        v("Set up a test: Advanced › task arguments", "Set up a test", "Set up a test, unchanged", .setup, .kept),
        v("Set up a test: what this test can tell you", "Set up a test", "Set up a test, unchanged", .setup, .kept),
        v("Set up a test: seats ignore temperature and seed", "Set up a test", "Set up a test, unchanged", .setup, .kept),
        v("Set up a test: cost lines and seat share", "Set up a test", "Set up a test, unchanged", .setup, .kept),
        v("Set up a test: API cost and the cap ×1.5", "Set up a test", "Set up a test, unchanged", .setup, .kept),
        v("Set up a test: recorded with each result", "Set up a test", "Set up a test, unchanged", .setup, .kept),
        v("Set up a test: repeat rules note", "Set up a test", "Set up a test, unchanged", .setup, .kept),
        v("Set up a test: seat use unknown warning", "Set up a test", "Set up a test, unchanged", .setup, .kept),
        v("Set up a test: not-recorded note on Test again", "Set up a test", "Set up a test, unchanged", .setup, .kept),
        v("Set up a test: Start N and the reasons it is off", "Set up a test", "Set up a test, unchanged", .setup, .kept),
        v("Set up a test: two at a time, worktree, Codex note", "Set up a test", "Set up a test, unchanged", .setup, .kept),
        v("Set up a test: ↩ starts, Esc closes", "Set up a test", "Set up a test, unchanged", .setup, .kept),
        v("Set up a test: engine calls", "Set up a test", "Unchanged", .setup, .kept),
        v("Running and recent: list and empty state", "Set up a test", "Set up a test, unchanged", .setup, .kept),
        v("Running and recent: rows, status, progress", "Set up a test", "Set up a test, unchanged", .setup, .kept),
        v("Running and recent: Run anyway · Cancel · Resume · Results", "Set up a test", "Set up a test, unchanged", .setup, .kept),
        v("Running and recent: 8 recent and Show all", "Set up a test", "Set up a test, unchanged", .setup, .kept),
        v("Running and recent: why a test expired", "Set up a test", "Set up a test, unchanged", .setup, .kept),
        v("Lessons: header, subtitle, Close", "Lessons", "Lessons, unchanged", .lessons, .kept),
        v("Lessons: Lessons · How to · Where everything went", "Lessons", "Lessons, all three parts kept", .lessons, .kept),
        v("Lessons: lessons in six groups, with marks", "Lessons", "Lessons: 18 lessons in six groups (16 + 2 new)", .lessons, .kept),
        v("Lessons: lesson text", "Lessons", "Lessons, unchanged", .lessons, .kept),
        v("Lessons: Try it", "Lessons", "Lessons, unchanged", .lessons, .kept),
        v("Lessons: in your tests", "Lessons", "Lessons, unchanged", .lessons, .kept),
        v("Lessons: your first test, free", "Lessons", "Lessons, unchanged", .lessons, .kept),
        v("Lessons: where this shows up, Next", "Lessons", "Lessons, unchanged; links can open the 2.0.5 pages", .lessons, .kept),
        v("Lessons: done when read, saved", "Lessons", "Lessons, unchanged", .lessons, .kept),
        v("Lessons: falls back to the 1.9.37 Learn", "Lessons", "Lessons, unchanged", .lessons, .kept),
        v("How to: header", "Lessons › How to", "Lessons › How to, unchanged", .lessons, .kept),
        v("How to: narration Play, or narration coming", "Lessons › How to", "Lessons › How to, unchanged", .lessons, .kept),
        v("How to: N of 8 read, Start over", "Lessons › How to", "Lessons › How to, unchanged", .lessons, .kept),
        v("How to: AI voice note", "Lessons › How to", "Lessons › How to, unchanged", .lessons, .kept),
        v("How to: the 8 scenes", "Lessons › How to", "Lessons › How to, unchanged", .lessons, .kept),
        v("How to: per scene Open, Play, Mark as read", "Lessons › How to", "Lessons › How to, unchanged", .lessons, .kept),
        v("How to: read state saved", "Lessons › How to", "Lessons › How to, unchanged", .lessons, .kept),
        v("Where everything went: intro", "Lessons › Where everything went", "Lessons › Where everything went: now 2.0.4 → 2.0.5 first", .lessons, .kept),
        v("Where everything went: status filter", "Lessons › Where everything went", "Lessons › Where everything went, unchanged", .lessons, .kept),
        v("Where everything went: map table with links", "Lessons › Where everything went", "Lessons › Where everything went: each row has an Open button", .lessons, .kept),
        v("Where everything went: the docs page and its unit test", "Lessons › Where everything went", "docs/evals-v3-coverage.md (this page) and its unit test; the 2.0.4 page is kept as it was", .lessons, .kept),
        v("Hover card and Lesson ›", "every page", "Every number, every page, unchanged", nil, .kept),
        v("Right-click Explain and Open the lesson", "every page", "Unchanged", nil, .kept),
        v("Hover kinds and their lessons", "every page", "Unchanged", .lessons, .kept),
        v("Lesson hints on git numbers", "Real history", "Agent jobs › Real history, unchanged", .realHistory, .kept),
        v("Hover inside sheets", "every page", "Unchanged", nil, .kept),
        v("Engine: setup, doctor", "engine", "Unchanged", nil, .kept),
        v("Engine: catalog", "engine", "Unchanged", nil, .kept),
        v("Engine: status, results", "engine", "Unchanged", nil, .kept),
        v("Engine: estimate, power, run", "engine", "Unchanged", nil, .kept),
        v("Engine: cancel, run-anyway, resume", "engine", "Unchanged", nil, .kept),
        v("Engine: samples, sample", "engine", "Unchanged", nil, .kept),
        v("Engine: export", "engine", "Unchanged", nil, .kept),
        v("Engine: overview", "engine", "Still read by the launch view", .launch, .kept),
        v("Engine: leaderboard by setup", "engine", "Unchanged", nil, .kept),
        v("Engine: compare", "engine", "Unchanged", nil, .kept),
        v("Engine: changes", "engine", "Unchanged", nil, .kept),
        v("Engine: xray", "engine", "Unchanged, plus --commits (fixup, churn or revert) --agent NAME", nil, .kept),
        v("Engine: evalset", "engine", "Unchanged", nil, .kept),
        v("Engine: judge", "engine", "Unchanged", nil, .kept),
        v("Engine: anatomy, items, item, item-results", "engine", "Unchanged", nil, .kept),
        v("Engine: scores show and refresh", "engine", "Unchanged", nil, .kept),
        v("Engine: history", "engine", "Unchanged", nil, .kept),
        v("Engine: providers, prices, index, lmeval", "engine", "Unchanged", nil, .kept),
        v("Two kinds of job: one-shot and agent", "new in 2.0.5", "Evals (launch view): one bar per kind; every task and loop is sorted by kind", .launch, .added),
        v("Evidence bars: public tests · ours · loop runs (amber · blue · light blue)", "new in 2.0.5", "Evals (launch view); widths from real counts, the hover gives them", .launch, .added),
        v("Segment pages: One-shot jobs › Public tests · Our tests · Loop runs; Agent jobs › Our tests · Our loop runs", "new in 2.0.5", "One page per bar segment, each with its question and answer", .oneShotPublic, .added),
        v("Loop runs: runs, failed and dry per loop, good run: not recorded", "new in 2.0.5", "One-shot jobs › Loop runs and Agent jobs › Our loop runs; each row opens the loop in Loops", .oneShotLoops, .added),
        v("What a good run is, by loop kind", "new in 2.0.5", "Each loop's row on the Loop runs pages", .agentLoops, .added),
        v("Loops with no model, on a line of their own", "new in 2.0.5", "Evals (launch view): N loops use no model, so Evals doesn't judge them (opens Loops)", .launch, .added),
        v("Public agent benchmarks, outside the agent bar", "new in 2.0.5", "The button under the agent bar: out of the box, never our setup", .agentPublic, .added),
        v("Three answer buttons on the launch view", "new in 2.0.5", "Did my last change help? · What does git say about our real work? · Every result, one grid", .launch, .added),
        v("Breadcrumb", "new in 2.0.5", "The header on every page: ‹ Evals › job › source (› item)", nil, .added),
        v("Keys ⌃⌥0–8", "new in 2.0.5", "⌃⌥0 the launch view · ⌃⌥1–5 the five segment pages · ⌃⌥6 Public agent benchmarks · ⌃⌥7 Changes · ⌃⌥8 Real history", .launch, .added),
        v("Tested as chips: model · agent clean · agent with our rules", "new in 2.0.5", "Our tasks, Our tests rows, the stamp", .ourTasks, .added),
        v("Real history: the commits behind a count", "new in 2.0.5", "Real history: See the N commits under followed by a fix, rewritten and reverted (and the bar's fix part): each commit with the later commit that fixed, rewrote or reverted it", .realHistory, .added),
        v("All results: Kind column (one-shot · agent · public model · public agent)", "new in 2.0.5", "All results", .allResults, .added),
        v("Lesson: One-shot jobs and agent jobs", "new in 2.0.5", "Lessons › Agents vs models", .lessons, .added),
        v("Lesson: Loop runs as evidence", "new in 2.0.5", "Lessons › Our own tasks", .lessons, .added),
    ]

    /// Every self-test name One Roof 2.0.3 (and 1.9.37) answered to; each must still open a screen.
    public static let oldSelfTestNames = ["how-to", "howto", "overview", "your-evals", "yourevals", "build", "judge", "explore", "catalog",
                                          "question", "questions", "scores", "your-runs", "run", "runs", "sheet", "results", "run-detail",
                                          "one-run", "all-by-all", "allbyall", "matrix", "xray", "x-ray", "learn"]
    /// LAB-2261: every other name 2.0.5 still answers to: the 2.0.4 screen names, their other spellings, and v3 aliases.
    public static let v204SelfTestNames: [String] = EvalsScreen.allCases.map(\.selfTestName)
        + ["realhistory", "history", "ourtasks", "tasks", "allresults", "onetest", "test", "onetask", "task", "onebenchmark", "benchmark",
           "public-benchmarks", "set-up", "setup-sheet", "new-test", "home", "evals", "public-agent", "agent-benchmarks"]
}

// MARK: - Set up a test: why Start is off (E7)

public enum EvalSetupCheck {
    /// The first reason Start stays off, or nil. Agents on seats answer only your own tasks; then keys, the sandbox, seats
    /// too full, and the cap (the engine's estimate, grader counted ×1.5).
    public static func reason(tasks: [String], choices: [EvalSetupChoice], isOwn: (String) -> Bool, missingKeys: [String],
                              sandboxBlocked: String? = nil, fullSeats: [String] = [], overCap: Bool = false) -> String? {
        if tasks.isEmpty { return "Pick a task" }
        if choices.isEmpty { return "Pick at least one setup" }
        if choices.contains(where: \.isSeat), let t = tasks.first(where: { !isOwn($0) }) {
            return "Agents on your seats answer your own tasks: untick \(EvalBenchmark.taskLabel(t)) or the agents"
        }
        if let p = missingKeys.first { return "No key for \(p): roof eval providers set \(p) --key-file PATH" }
        if let s = sandboxBlocked { return s }
        if let s = fullSeats.first { return "\(s) is too full for this test: wait for its 5-hour window" }
        if overCap { return "Over the cap: lower the bugs or raise Stop at" }
        return nil
    }
    /// Providers a choice needs a key for and has none (free models need none).
    public static func missingKeys(_ choices: [EvalSetupChoice], ready: Set<String>) -> [String] {
        let need = choices.filter { !$0.isSeat }.compactMap(\.model).filter { !EvalModels.isFree($0) }.map(EvalModels.provider)
        return Array(Set(need.filter { !ready.contains($0) })).sorted()
    }
}
