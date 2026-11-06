import Foundation

// LAB-2258 · Evals v3 (One Roof 2.0.5, Claude Design "Evals v3.0" 13A, adapted so nothing in 2.0.4 is lost): two kinds of job
// (one-shot · agent), three sources of evidence (public tests · our tests · our loop runs). Pure names, rules and counts; the
// views live in Sources/OneRoof/UI/Evals/. Decisions D1–D13: scratchpad brief; summary in docs/evals-v3-coverage.md.

/// The two kinds of job. One-shot: one prompt to a model, one answer back (no tools, no repo). Agent: an agent CLI (Claude
/// Code, Codex …) on a model, reading our code, following our setup, changing files.
public enum EvalJobKind: String, CaseIterable, Identifiable, Codable, Sendable {
    case oneShot, agent
    public var id: String { rawValue }
    /// "One-shot jobs" / "Agent jobs" (breadcrumb, Set up a test switch).
    public var title: String { self == .oneShot ? "One-shot jobs" : "Agent jobs" }
    /// The sheet's tag (upper-cased by the view).
    public var tag: String { self == .oneShot ? "One-shot jobs" : "Agent jobs" }
    /// The sheet's title.
    public var sheetTitle: String { self == .oneShot ? "The model, answering once" : "The agent, as we use it" }
    /// The short switch label in Set up a test.
    public var short: String { self == .oneShot ? "One-shot" : "Agent" }
    /// What each sheet is made of, top to bottom (v3 LayerStack). The last band (the loop) is drawn dashed.
    public var stack: [(name: String, detail: String)] {
        switch self {
        case .oneShot:
            return [("the model", "Opus, Sonnet, gpt-5…"), ("+ the loop", "schedule · instructions · stop rule")]
        case .agent:
            return [("the model", "Opus, Sonnet, gpt-5…"), ("+ the agent", "Claude Code or Codex"), ("+ our code", "the repos our tasks come from"),
                    ("+ our setup", "CLAUDE.md · skills · settings"), ("+ the loop", "schedule · instructions · stop rule")]
        }
    }

    /// A result's kind: an agent answered (or the contestant is an agent) → agent; else the model alone.
    public static func of(_ r: EvalResult) -> EvalJobKind { (r.agent != nil || r.contestant?.kind == .agent) ? .agent : .oneShot }
    public static func of(_ r: EvalRunRow) -> EvalJobKind { r.agent != nil ? .agent : .oneShot }
    /// A Compare row: the model layer is one-shot; an agent on a model (rules on or off) is agent.
    public static func of(_ r: EvalSetupRow) -> EvalJobKind { r.layer == .model ? .oneShot : .agent }
    public static func of(_ u: EvalsAUntested) -> EvalJobKind { u.agent != nil ? .agent : .oneShot }
}

/// Where a job's evidence comes from. Colour means source only (amber · blue · light blue), never anything else.
public enum EvalEvidenceSource: String, CaseIterable, Identifiable, Codable, Sendable {
    case publicTests, ours, loopRuns
    public var id: String { rawValue }
    /// Bar segment label (and the breadcrumb's last step).
    public func label(_ kind: EvalJobKind, narrow: Bool = false) -> String {
        switch self {
        case .publicTests: return "Public tests"
        case .ours: return narrow || kind == .oneShot ? "Ours" : "Our tests"
        case .loopRuns: return kind == .oneShot || narrow ? "Loops" : "Our loop runs"
        }
    }
    /// The breadcrumb / page tag.
    public var title: String {
        switch self { case .publicTests: return "Public tests"; case .ours: return "Our tests"; case .loopRuns: return "Loop runs" }
    }
    public var tag: String { switch self { case .publicTests: return "Public"; case .ours: return "Ours"; case .loopRuns: return "Loop runs" } }
    public var legend: String { switch self { case .publicTests: return "public tests"; case .ours: return "our tests"; case .loopRuns: return "our loop runs" } }
    /// The sources a kind's bar has, in order. Agent jobs have no public segment (nobody else has our code or setup).
    public static func sources(_ kind: EvalJobKind) -> [EvalEvidenceSource] { kind == .oneShot ? [.publicTests, .ours, .loopRuns] : [.ours, .loopRuns] }
}

// MARK: - Loops by kind of job (D1)

/// Where a loop sits. By its definition, never by its name: no prompt = a code check (no model); a kit loop with a prompt
/// = one-shot (the model answers once from the collected findings; the kit acts); a One Roof loop starts an agent session
/// in a worktree = agent, unless it only reads (act none).
public enum EvalLoopPlace: String, CaseIterable, Codable, Sendable {
    case oneShot, agent, noModel
    public var jobKind: EvalJobKind? { switch self { case .oneShot: return .oneShot; case .agent: return .agent; case .noModel: return nil } }

    /// `hasPrompt`: the kit loop names a prompt (catalog roundPrompt or `prompt:` in its .loop.yaml). nil for One Roof loops.
    public static func classify(isKitLoop: Bool, hasPrompt: Bool, act: String?) -> EvalLoopPlace {
        if isKitLoop { return hasPrompt ? .oneShot : .noModel }
        return (act ?? "").lowercased() == "none" ? .oneShot : .agent
    }

    public static func classify(_ l: Loop) -> EvalLoopPlace {
        let kit = l.check.contains("ae.loops run") || l.specFile != nil || l.origin == .builtIn
        var prompt = !l.roundPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if !prompt, let f = l.specFile, let text = try? String(contentsOfFile: f, encoding: .utf8) {
            prompt = MiniYAML.parse(text).string("prompt") != nil
        }
        return classify(isKitLoop: kit, hasPrompt: prompt, act: l.act)
    }

    /// "Good run: …" by the loop's kind (v3 OVERVIEW § What a good run is). Agent loops with no kind fix code.
    public static func goodRun(kind: String?, place: EvalLoopPlace) -> String {
        switch (kind ?? "").lowercased() {
        case "reporter", "writer", "researcher": return "it was right and you read it"
        case "judge": return "its verdicts matched yours"
        case "auditor": return "the gaps it found were real"
        case "sentinel", "prober": return "it spoke up when it mattered, and stayed quiet when not"
        case "learner": return "the rule it proposed was kept"
        case "refresher", "fixer": return "the change passed its check and stayed in"
        default: return place == .agent ? "the fix passed its check and stayed in" : "it did its job (rule not set)"
        }
    }
}

/// One loop's runs over the window, from the outcome ledger. "Good" is not recorded yet (EV-12), so the page shows runs,
/// finished, failed and dry, and says "good run: not recorded" — never an invented good / runs.
public struct EvalLoopRuns: Identifiable, Equatable, Sendable {
    public var loop: String
    public var title: String
    public var kind: String?
    public var place: EvalLoopPlace
    /// Live runs (not dry): finished + failed + other.
    public var runs: Int
    public var finished: Int
    public var failed: Int
    public var dry: Int
    public var lastStarted: String?
    /// Good / bad per run (EV-12): nil until recorded.
    public var good: Int?
    public var id: String { loop }
    public init(loop: String, title: String, kind: String?, place: EvalLoopPlace, runs: Int, finished: Int, failed: Int, dry: Int,
                lastStarted: String? = nil, good: Int? = nil) {
        self.loop = loop; self.title = title; self.kind = kind; self.place = place; self.runs = runs; self.finished = finished
        self.failed = failed; self.dry = dry; self.lastStarted = lastStarted; self.good = good
    }
    public var goodRun: String { EvalLoopPlace.goodRun(kind: kind, place: place) }
    /// "7 runs · 1 failed · 2 dry" (or "no live runs · 1 dry").
    public var countLine: String {
        var parts: [String] = []
        parts.append(runs == 0 ? "no live runs" : EvalsAWords.count(runs, "run"))
        if failed > 0 { parts.append("\(failed) failed") }
        if dry > 0 { parts.append("\(dry) dry") }
        return parts.joined(separator: " · ")
    }

    /// result → bucket. The ledger writes pass · done · promoted (finished), fail · failed, dry (or mode dry).
    public static func bucket(result: String, mode: String) -> String {
        let r = result.lowercased(), m = mode.lowercased()
        if m == "dry" || m == "shadow" || r == "dry" { return "dry" }
        if r == "fail" || r == "failed" || r == "error" { return "failed" }
        if r == "pass" || r == "done" || r == "promoted" || r == "ok" { return "finished" }
        return "other"
    }

    /// From the ledger's window counts (LoopLedger.counts(since:)): the whole window, never capped.
    public static func summarize(loops: [Loop], counts: [LoopLedger.WindowCount]) -> [EvalLoopRuns] {
        var by: [String: [LoopLedger.WindowCount]] = [:]
        for c in counts { by[c.loop, default: []].append(c) }
        return loops.map { l in
            var fin = 0, fail = 0, dry = 0, other = 0
            for c in by[l.id] ?? [] {
                switch bucket(result: c.result, mode: c.mode) {
                case "finished": fin += c.n; case "failed": fail += c.n; case "dry": dry += c.n; default: other += c.n
                }
            }
            return EvalLoopRuns(loop: l.id, title: l.displayTitle, kind: l.kind, place: EvalLoopPlace.classify(l),
                                runs: fin + fail + other, finished: fin, failed: fail, dry: dry, lastStarted: (by[l.id] ?? []).map(\.last).max())
        }
    }

    /// Group ledger runs by loop; loops with no run in the window still get a row (runs 0) so nothing is hidden.
    public static func summarize(loops: [Loop], runs: [LoopLedger.Run]) -> [EvalLoopRuns] {
        var byLoop: [String: [LoopLedger.Run]] = [:]
        for r in runs { byLoop[r.loop, default: []].append(r) }
        return loops.map { l in
            let rs = (byLoop[l.id] ?? [])
            var fin = 0, fail = 0, dry = 0, other = 0
            for r in rs {
                switch bucket(result: r.result, mode: r.mode) {
                case "finished": fin += 1; case "failed": fail += 1; case "dry": dry += 1; default: other += 1
                }
            }
            return EvalLoopRuns(loop: l.id, title: l.displayTitle, kind: l.kind, place: EvalLoopPlace.classify(l),
                                runs: fin + fail + other, finished: fin, failed: fail, dry: dry, lastStarted: rs.map(\.started).max())
        }
    }

    /// The page's one-sentence answer: never claims "good"; names the loop that failed most, else the busiest.
    public static func answer(_ rows: [EvalLoopRuns], kind: EvalJobKind) -> String {
        let live = rows.filter { $0.runs > 0 }
        guard !live.isEmpty else {
            return kind == .oneShot ? "None of our one-shot loops has run for real in the last 30 days, so there is nothing to judge yet."
                                    : "None of our agent loops has run for real in the last 30 days, so there is nothing to judge yet."
        }
        let total = live.reduce(0) { $0 + $1.runs }
        var s = "\(EvalsAWords.count(total, "live run")) in 30 days across \(EvalsAWords.count(live.count, "loop")). Whether each run was good is not recorded yet."
        if let worst = live.filter({ $0.failed > 0 }).max(by: { Double($0.failed) / Double($0.runs) < Double($1.failed) / Double($1.runs) }) {
            s += " \(worst.title) is the one to look at: \(worst.failed) of its \(worst.runs) runs failed."
        }
        return s
    }
}

// MARK: - Evidence per kind of job (EV-13): segment widths

public struct EvalEvidence: Equatable, Sendable {
    public var publicTests: Int
    public var ours: Int
    public var loopRuns: Int
    /// Our runs that are still waiting / queued (shown in the hover, not counted as evidence).
    public var waiting: Int
    /// mockllm stand-in runs on our tasks (counted apart: they test the plumbing, not a model).
    public var standIn: Int
    public init(publicTests: Int = 0, ours: Int = 0, loopRuns: Int = 0, waiting: Int = 0, standIn: Int = 0) {
        self.publicTests = publicTests; self.ours = ours; self.loopRuns = loopRuns; self.waiting = waiting; self.standIn = standIn
    }
    public func count(_ s: EvalEvidenceSource) -> Int {
        switch s { case .publicTests: return publicTests; case .ours: return ours; case .loopRuns: return loopRuns }
    }
    public var total: Int { publicTests + ours + loopRuns }

    /// Share of each source in a bar (0…1). Empty sources still get a sliver so their button can open the page.
    public func shares(_ kind: EvalJobKind) -> [EvalEvidenceSource: Double] {
        let srcs = EvalEvidenceSource.sources(kind)
        let tot = srcs.reduce(0) { $0 + count($1) }
        guard tot > 0 else { return Dictionary(uniqueKeysWithValues: srcs.map { ($0, 1.0 / Double(srcs.count)) }) }
        return Dictionary(uniqueKeysWithValues: srcs.map { ($0, Double(count($0)) / Double(tot)) })
    }

    /// Widths that sum to `total` minus gaps, each at least `minimum` (so its label fits).
    public static func widths(shares: [Double], total: Double, gap: Double, minimum: Double) -> [Double] {
        let n = shares.count
        guard n > 0 else { return [] }
        let room = max(0, total - gap * Double(n - 1))
        var w = shares.map { max(minimum, $0 * room) }
        let over = w.reduce(0, +) - room
        if over > 0 {
            let flex = w.enumerated().filter { $0.element > minimum }.map(\.offset)
            let flexTotal = flex.reduce(0) { $0 + w[$1] - minimum }
            if flexTotal > 0 { for i in flex { w[i] -= over * (w[i] - minimum) / flexTotal } }
        }
        return w
    }

    static func isGrader(_ t: String?) -> Bool { let t = t ?? ""; return t.hasPrefix("judge_") || t.hasPrefix("labeller_") }
    static func isStand(_ m: String?) -> Bool { (m ?? "").hasPrefix("mockllm/") }

    /// From the run store and the ledger: public = finished public runs of that kind; ours = finished own-task runs of that
    /// kind (graders and stand-ins apart); loop runs = live ledger runs of that kind's loops in the window.
    public static func count(results: [EvalResult], runs: [EvalRunRow], loops: [EvalLoopRuns], kind: EvalJobKind) -> EvalEvidence {
        let done = results.filter { $0.status == "done" && !isGrader($0.task) && EvalJobKind.of($0) == kind }
        // One own/public rule everywhere (2.0.5 review P2): an older own_<set> run with no set name is ours.
        let own = done.filter { !EvalResultKind.isPublic($0) }
        let pub = done.filter { EvalResultKind.isPublic($0) && !isStand($0.model) }
        let waiting = runs.filter { $0.isActive && $0.setName != nil && EvalJobKind.of($0) == kind }.count
        return EvalEvidence(publicTests: kind == .agent ? 0 : pub.count,
                            ours: own.filter { !isStand($0.model) }.count,
                            loopRuns: loops.filter { $0.place.jobKind == kind }.reduce(0) { $0 + $1.runs },
                            waiting: waiting, standIn: own.filter { isStand($0.model) }.count)
    }

    /// Public agent-harness runs (SWE-bench and the like): kept outside the agent bar (D3), shown on its own button.
    public static func publicAgentRuns(_ results: [EvalResult]) -> Int {
        results.filter { $0.status == "done" && EvalResultKind.isPublic($0) && EvalJobKind.of($0) == .agent }.count
    }
    public static func graderRuns(_ results: [EvalResult]) -> Int { results.filter { $0.status == "done" && isGrader($0.task) }.count }
}

// MARK: - Navigation (no tabs: the launch view is the navigation)

/// Every v3 screen. Segment pages are (kind, source); `agentPublic` is the public agent benchmarks page (D3).
public enum EvalsV3Screen: String, CaseIterable, Sendable {
    case launch, oneShotPublic, oneShotOurs, oneShotLoops, agentOurs, agentLoops, agentPublic
    case changes, realHistory, oneTest, allResults, ourTasks, oneTask, grader, benchmarks, oneBenchmark, setup, lessons

    public var segment: (EvalJobKind, EvalEvidenceSource)? {
        switch self {
        case .oneShotPublic: return (.oneShot, .publicTests); case .oneShotOurs: return (.oneShot, .ours); case .oneShotLoops: return (.oneShot, .loopRuns)
        case .agentOurs: return (.agent, .ours); case .agentLoops: return (.agent, .loopRuns)
        default: return nil
        }
    }
    public static func segment(_ k: EvalJobKind, _ s: EvalEvidenceSource) -> EvalsV3Screen {
        switch (k, s) {
        case (.oneShot, .publicTests): return .oneShotPublic; case (.oneShot, .ours): return .oneShotOurs; case (.oneShot, .loopRuns): return .oneShotLoops
        case (.agent, .publicTests): return .agentPublic; case (.agent, .ours): return .agentOurs; case (.agent, .loopRuns): return .agentLoops
        }
    }

    /// ⌃⌥ digit (D8): 0 launch, 1–5 the segment pages in v3 order, 6 public agent benchmarks, 7 Changes, 8 Real history.
    public var keyDigit: Character? {
        switch self {
        case .launch: return "0"; case .oneShotPublic: return "1"; case .oneShotOurs: return "2"; case .oneShotLoops: return "3"
        case .agentOurs: return "4"; case .agentLoops: return "5"; case .agentPublic: return "6"; case .changes: return "7"; case .realHistory: return "8"
        default: return nil
        }
    }

    public var title: String {
        switch self {
        case .launch: return "Evals"
        case .oneShotPublic, .oneShotOurs, .oneShotLoops, .agentOurs, .agentLoops: return segment!.1.title
        case .agentPublic: return "Public agent benchmarks"
        case .changes: return "Changes"; case .realHistory: return "Real history"; case .oneTest: return "One test"
        case .allResults: return "All results"; case .ourTasks: return "Our tasks"; case .oneTask: return "One task"
        case .grader: return "Check the grader"; case .benchmarks: return "Public benchmarks"; case .oneBenchmark: return "A public benchmark"
        case .setup: return "Set up a test"; case .lessons: return "Lessons"
        }
    }
    public var isSheet: Bool { self == .setup || self == .lessons }

    /// The kebab-case self-test name.
    public var selfTestName: String {
        switch self {
        case .launch: return "launch"; case .oneShotPublic: return "oneshot-public"; case .oneShotOurs: return "oneshot-ours"
        case .oneShotLoops: return "oneshot-loops"; case .agentOurs: return "agent-ours"; case .agentLoops: return "agent-loops"
        case .agentPublic: return "agent-public"; case .changes: return "changes"; case .realHistory: return "real-history"
        case .oneTest: return "one-test"; case .allResults: return "all-results"; case .ourTasks: return "our-tasks"; case .oneTask: return "one-task"
        case .grader: return "grader"; case .benchmarks: return "benchmarks"; case .oneBenchmark: return "one-benchmark"
        case .setup: return "setup"; case .lessons: return "lessons"
        }
    }

    /// ONEROOF_SELFTEST_EVALS_TAB: the v3 names, and every 2.0.4 / 2.0.3 / 1.9.37 name at its v3 home. `part` as 2.0.4.
    public static func selfTest(_ raw: String) -> (screen: EvalsV3Screen, part: String?)? {
        let v = raw.lowercased().trimmingCharacters(in: .whitespaces)
        if let s = allCases.first(where: { $0.selfTestName == v }) { return (s, nil) }
        switch v {
        case "home", "evals": return (.launch, nil)
        case "public-agent", "agent-benchmarks": return (.agentPublic, nil)
        // 2.0.4 tabs
        case "overview": return (.launch, nil)
        case "compare", "results": return (.oneShotOurs, nil)
        case "public-benchmarks": return (.oneShotPublic, nil)
        default: break
        }
        guard let old = EvalsScreen.selfTest(v) else { return nil }
        let map: [EvalsScreen: EvalsV3Screen] = [
            .overview: .launch, .compare: .oneShotOurs, .oneTest: .oneTest, .allResults: .allResults, .changes: .changes,
            .realHistory: .realHistory, .ourTasks: .ourTasks, .oneTask: .oneTask, .grader: .grader, .benchmarks: .benchmarks,
            .oneBenchmark: .oneBenchmark, .setup: .setup, .lessons: .lessons]
        return map[old.screen].map { ($0, old.part) }
    }
}

/// The breadcrumb: "Evals › One-shot jobs › Our tests (› One test)". Every step but the last opens its page.
public enum EvalsCrumbs {
    public struct Step: Equatable, Sendable {
        public var title: String
        public var target: EvalsV3Screen?
        public init(_ title: String, _ target: EvalsV3Screen?) { self.title = title; self.target = target }
    }
    public static func kind(of s: EvalsV3Screen) -> EvalJobKind? {
        if let k = s.segment?.0 { return k }
        switch s { case .agentPublic, .changes, .realHistory: return .agent; default: return nil }
    }
    public static func steps(page: EvalsV3Screen, trail: [EvalsV3Screen], drill: String?) -> [Step] {
        var out = [Step("Evals", .launch)]
        let pages = (trail + [page]).filter { $0 != .launch }
        var lastKind: EvalJobKind?
        for p in pages {
            if let k = kind(of: p), k != lastKind {
                out.append(Step(k.title, .segment(k, .ours)))   // the kind opens its Our tests
                lastKind = k
            }
            out.append(Step(p.title, p))
        }
        if let d = drill { out.append(Step(d, nil)) }
        if out.count > 1, drill == nil { out[out.count - 1].target = nil }
        return out
    }
}

// MARK: - The three evidence colours (tokens only; colour means source, never anything else)

public extension ThemeTokens {
    /// Fill and label of a source's bar segment / tag: public = the peach sticker's amber, ours = `accent`, loop runs = `accent`
    /// at 45 % on `surface`. The label is whichever of `text`, `onAccent` and `surface` reads best on the fill (dark looks).
    func evidence(_ s: EvalEvidenceSource) -> (fill: RGB, ink: RGB) {
        let fill: RGB
        switch s {
        case .publicTests: fill = (Pastel.named("peach") ?? Pastel.all[1]).darkFill   // amber in every look
        case .ours: fill = accent
        case .loopRuns: fill = accent.opacity(isDark ? 0.55 : 0.45).over(surface)
        }
        let ink = [text, onAccent, surface, (Pastel.named("peach") ?? Pastel.all[1]).lightInk].max { RGB.contrast(fill, $0) < RGB.contrast(fill, $1) } ?? text
        return (fill, ink)
    }
    /// The sheet tags: one-shot = slate (`text2`), agent = ink (`text`), label on them = `surface`.
    func jobTag(_ k: EvalJobKind) -> (fill: RGB, ink: RGB) { (k == .oneShot ? text2 : text, surface) }
}

// MARK: - Each segment page opens with its question and a one-sentence answer (v3 QuestionHead), by rule

public enum EvalsV3Answers {
    public static func question(_ s: EvalsV3Screen) -> String {
        switch s {
        case .oneShotPublic: return "Which models are worth trying?"
        case .oneShotOurs: return "Which model does our one-shot jobs well enough, for the least?"
        case .oneShotLoops: return "Are our one-shot loops doing their job?"
        case .agentOurs: return "How does the agent, as we use it, do on our bugs?"
        case .agentLoops: return "Are our agent loops worth what they cost?"
        case .agentPublic: return "How do agents do out of the box?"
        default: return s.title
        }
    }
    /// The page's footer line (what counts here).
    public static func foot(_ s: EvalsV3Screen) -> String {
        switch s {
        case .oneShotPublic: return "Used to pick candidates, never to decide."
        case .oneShotOurs: return "Each test is the model alone, one prompt, on our bugs."
        case .oneShotLoops, .agentLoops: return "Every run is a test. Last 30 days, from the loops' outcome ledger."
        case .agentOurs: return "Our code and setup aren't public, so only our tests can answer this. Agent tests use our rules unless you pick clean."
        case .agentPublic: return "Out of the box: no CLAUDE.md, skills or settings of ours. Context only."
        default: return ""
        }
    }
    public static let publicOneShot = "Public scores shortlist models for one-shot jobs. They never decide: that is what our tests and loop runs are for."
    public static let publicAgent = "Public agent benchmarks run an agent on other people's code, with none of our files. They can't tell you how our setup does; only our tests can."

    /// Some tasks could not be read: speak only for the ones read, never "none finished" overall (2.0.5 re-review).
    public static func oursPartial(_ boards: [EvalSetupLeaderboard], kind: EvalJobKind, unread: Int) -> String {
        let note = "\(EvalsAWords.count(unread, "task")) could not be read, so this is not the whole answer; see below."
        let any = boards.contains { $0.rows.contains { $0.isDone && EvalJobKind.of($0) == kind } }
        return any ? ours(boards, kind: kind) + " " + note : note
    }

    /// Our tests: per task, the best finished setup of that kind against the blind guess; else what is waiting; else not run.
    public static func ours(_ boards: [EvalSetupLeaderboard], kind: EvalJobKind) -> String {
        var parts: [String] = []
        var waiting = 0
        for lb in boards {
            let rows = lb.rows.filter { EvalJobKind.of($0) == kind }
            waiting += rows.filter { ["waiting", "queued", "running"].contains($0.status) }.count
            guard let best = rows.filter(\.isDone).max(by: { ($0.share ?? 0) < ($1.share ?? 0) }), let score = best.scoreText else { continue }
            var s = "\(best.label) got \(score) on \u{201C}\(lb.title ?? lb.task)\u{201D}"
            if let f = lb.floor { s += " (a blind guess gets \(EvalScoreText.count(Double(f.right))))" }
            if let v = EvalVerdicts.againstFloor(EvalVerdicts.Side(best), floor: lb.floor?.share) { s += ": " + v.text.prefix(1).lowercased() + v.text.dropFirst() }
            parts.append(s)
        }
        if parts.isEmpty {
            let who = kind == .oneShot ? "No model" : "No agent"
            var s = "\(who) has finished one of our tasks yet."
            if waiting > 0 { s += " \(EvalsAWords.count(waiting, "test")) waiting: open the queue to see why." }
            return s
        }
        var s = parts.joined(separator: ". ") + "."
        if waiting > 0 { s += " \(EvalsAWords.count(waiting, "more test")) waiting." }
        return s
    }
}
