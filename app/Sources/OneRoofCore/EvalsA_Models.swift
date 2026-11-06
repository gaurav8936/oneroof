import Foundation

// LAB-2242 · Evals v2, screen lane A (Overview · Compare · One test · All results · Changes · Real history): the pure parts
// of those screens, so every sentence, count and ordering is unit-tested (EvalsLaneATests). Nothing here draws; nothing
// here invents a number: every value comes from the engine's JSON (CONTRACT §1–§7) or from today's run store.

// MARK: - Shared words

public enum EvalsAWords {
    /// "Nov 1" from an ISO date ("2026-11-01T16:31:03+00:00", "…Z" or a bare "2026-11-01").
    public static func day(_ iso: String?) -> String {
        guard let iso, !iso.isEmpty else { return "–" }
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "MMM d"
        if let d = date(iso) { return f.string(from: d) }
        return String(iso.prefix(10))
    }
    public static func date(_ iso: String?) -> Date? {
        guard let iso, !iso.isEmpty else { return nil }
        let p = ISO8601DateFormatter()
        if let d = p.date(from: iso) { return d }
        if iso.count >= 19, let d = p.date(from: String(iso.prefix(19)) + "Z") { return d }
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.timeZone = TimeZone(identifier: "UTC"); f.dateFormat = "yyyy-MM-dd"
        return f.date(from: String(iso.prefix(10)))
    }
    /// "1 run" / "4 runs".
    public static func count(_ n: Int, _ one: String, _ many: String? = nil) -> String { "\(n) \(n == 1 ? one : (many ?? one + "s"))" }
    /// "a, b and c".
    public static func list(_ xs: [String]) -> String {
        switch xs.count {
        case 0: return ""
        case 1: return xs[0]
        default: return xs.dropLast().joined(separator: ", ") + " and " + xs.last!
        }
    }
    /// "$0.256" (three decimals; dollars under a tenth of a cent keep four).
    public static func dollars(_ x: Double?) -> String {
        guard let x else { return "–" }
        return x > 0 && x < 0.001 ? String(format: "$%.4f", x) : String(format: "$%.3f", x)
    }
    /// The agent CLIs a seat test can run today (OpenCode/Goose headless is not verified: never offered).
    public static let seatAgents: [(key: String, name: String, seat: String)] = [("claude_code", "Claude Code", "C1"), ("codex_cli", "Codex", "CX")]
}

// MARK: - E1 · the layer picture (CONTRACT §7)

public extension EvalOverviewLayer {
    init(layer: EvalStamp.Layer, insideRuns: Int, insideStandIn: Int? = nil, insideWaiting: Int? = nil, outsideRuns: Int, outsideBenchmarks: Int) {
        self.layer = layer; self.insideRuns = insideRuns; self.insideStandIn = insideStandIn; self.insideWaiting = insideWaiting
        self.outsideRuns = outsideRuns; self.outsideBenchmarks = outsideBenchmarks
    }
}

/// One band of the inside / outside picture: the layer in words, what is measured inside (our own tasks) and outside.
public struct EvalsALayerBand: Equatable, Identifiable, Sendable {
    /// measured = finished tests exist · waiting = only queued / waiting ones · gap = nothing (shown in the verdict colour).
    public enum Tone: String, Equatable, Sendable { case measured, waiting, gap }
    public var layer: EvalStamp.Layer
    public var kicker: String
    public var how: String
    public var inside: String
    public var insideTone: Tone
    public var insideNote: String
    public var outside: String
    public var outsideNote: String
    public var id: String { layer.rawValue }
}

public enum EvalsALayers {
    /// The three bands, top (narrowest) to base, from `overview.layers` (missing layers count as zero).
    public static func bands(_ layers: [EvalOverviewLayer]) -> [EvalsALayerBand] {
        EvalStamp.Layer.allCases.map { l in
            let x = layers.first { $0.layer == l } ?? EvalOverviewLayer(layer: l, insideRuns: 0, outsideRuns: 0, outsideBenchmarks: 0)
            return band(x)
        }
    }

    static func band(_ x: EvalOverviewLayer) -> EvalsALayerBand {
        let stand = x.insideStandIn ?? 0, wait = x.insideWaiting ?? 0
        switch x.layer {
        case .model:
            var inside = x.insideRuns > 0 ? EvalsAWords.count(x.insideRuns, "run") : "not run yet"
            if stand > 0 { inside += " · \(stand) stand-in" }
            return EvalsALayerBand(layer: .model, kicker: "Top · narrowest", how: "a model answering on its own, no tools",
                                   inside: inside, insideTone: x.insideRuns > 0 ? .measured : .gap,
                                   insideNote: x.insideRuns > 0 ? "on our own tasks" : "no model has answered our tasks yet",
                                   outside: EvalsAWords.count(x.outsideBenchmarks, "benchmark"),
                                   outsideNote: x.outsideRuns > 0 ? "\(EvalsAWords.count(x.outsideRuns, "run")) here, for context" : "for context")
        case .agentModel:
            var inside = "\(x.insideRuns) finished"
            if wait > 0 { inside += " · \(wait) waiting" }
            return EvalsALayerBand(layer: .agentModel, kicker: "Middle", how: "an agent CLI on one model, with its tools",
                                   inside: inside, insideTone: x.insideRuns > 0 ? .measured : (wait > 0 ? .waiting : .gap),
                                   insideNote: x.insideRuns > 0 ? "what we use day to day" : "no agent has finished one of our tasks",
                                   outside: EvalsAWords.count(x.outsideBenchmarks, "agent task"),
                                   outsideNote: x.outsideRuns > 0 ? "\(EvalsAWords.count(x.outsideRuns, "run")) here, for context" : "for context")
        case .full:
            return EvalsALayerBand(layer: .full, kicker: "Base · widest", how: "agent + model + your CLAUDE.md, skills, rules",
                                   inside: x.insideRuns > 0 ? EvalsAWords.count(x.insideRuns, "run") : "not recorded yet · LAB-2240",
                                   insideTone: x.insideRuns > 0 ? .measured : .gap,
                                   insideNote: "what you actually ship with",
                                   outside: x.outsideBenchmarks > 0 ? EvalsAWords.count(x.outsideBenchmarks, "benchmark") : "none",
                                   outsideNote: "only your own work can test this")
        }
    }

    /// Before the 2.0.4 engine answers `layers`: the same counts read from the run store (own sets = inside; graders apart).
    public static func derive(results: [EvalResult], runs: [EvalRunRow], benchmarks: Int, agentBenchmarks: Int) -> (layers: [EvalOverviewLayer], graders: Int) {
        let done = results.filter { $0.status == "done" }
        func isGrader(_ t: String?) -> Bool { let t = t ?? ""; return t.hasPrefix("judge_") || t.hasPrefix("labeller_") }
        let inside = done.filter { $0.setName != nil && !isGrader($0.task) }
        let outside = done.filter { $0.setName == nil && !isGrader($0.task) }
        func isAgent(_ r: EvalResult) -> Bool { r.agent != nil || r.contestant?.kind == .agent }
        func isStand(_ r: EvalResult) -> Bool { (r.model ?? "").hasPrefix("mockllm/") }
        let waiting = runs.filter { $0.isActive && $0.setName != nil && $0.agent != nil }.count
        let model = EvalOverviewLayer(layer: .model, insideRuns: inside.filter { !isAgent($0) && !isStand($0) }.count,
                                      insideStandIn: inside.filter(isStand).count, insideWaiting: 0,
                                      outsideRuns: outside.filter { !isAgent($0) }.count, outsideBenchmarks: benchmarks)
        let agent = EvalOverviewLayer(layer: .agentModel, insideRuns: inside.filter(isAgent).count, insideStandIn: 0, insideWaiting: waiting,
                                      outsideRuns: outside.filter(isAgent).count, outsideBenchmarks: agentBenchmarks)
        let full = EvalOverviewLayer(layer: .full, insideRuns: 0, outsideRuns: 0, outsideBenchmarks: 0)
        return ([model, agent, full], done.filter { isGrader($0.task) }.count)
    }

    /// "Grader runs: 2, counted apart (they check our notes, they are not a setup)".
    public static func graderLine(_ n: Int?) -> String? {
        guard let n, n > 0 else { return nil }
        return "Grader runs: \(n), counted apart: they study our notes, they are not a setup."
    }
}

// MARK: - E1 · the three questions, answered by rule

public struct EvalsAAnswer: Equatable, Sendable {
    /// call = a finding (green family) · gap = not recorded / not run (needs colour) · cantTell = measured but not settled.
    public enum Tone: String, Equatable, Sendable { case call, gap, cantTell, reading }
    public var tone: Tone
    public var headline: String
    public var body: String
    public init(tone: Tone, headline: String, body: String) { self.tone = tone; self.headline = headline; self.body = body }
}

/// One bar of a question card's mini-chart: a share 0–1, its words, the floor tick, muted when it is not a score.
public struct EvalsABar: Equatable, Identifiable, Sendable {
    public var label: String
    public var value: Double?
    public var text: String
    public var floor: Double?
    public var note: String?
    public var muted: Bool
    public var id: String { label }
    public init(label: String, value: Double?, text: String, floor: Double? = nil, note: String? = nil, muted: Bool = false) {
        self.label = label; self.value = value; self.text = text; self.floor = floor; self.note = note; self.muted = muted
    }
}

/// One line of "What a test records today": yes / partly / no.
public struct EvalsARecord: Equatable, Identifiable, Sendable {
    public enum State: String, Equatable, Sendable { case yes, partly, no }
    public var label: String
    public var state: State
    public var id: String { label }
    public init(label: String, state: State) { self.label = label; self.state = state }
}

public enum EvalsAQuestions {
    /// Q1 · Which setup does our work best? `boards`: our tasks' setup leaderboards, the default task (fix locator) first.
    public static func whichSetup(_ boards: [EvalSetupLeaderboard]) -> (answer: EvalsAAnswer, title: String, bars: [EvalsABar]) {
        let rows = boards.flatMap(\.rows)
        let done = rows.filter(\.isDone)
        guard let main = boards.first(where: { $0.rows.contains(where: \.isDone) }) ?? boards.first else {
            return (EvalsAAnswer(tone: .gap, headline: "Not run yet", body: "We have no task of our own yet. Build one from fixed bugs in Our tasks."), "", [])
        }
        let title = [main.title ?? main.task, main.n.map { "\($0) bugs" }, main.floor.map { "tick = " + $0.text }]
            .compactMap { $0 }.joined(separator: " · ")
        let bars = EvalsAQuestions.bars(main)
        guard !done.isEmpty else {
            return (EvalsAAnswer(tone: .gap, headline: "Not run yet", body: "No setup has finished a test on our tasks yet." + waitingSentence(rows)), title, bars)
        }
        let agentsDone = done.filter { $0.layer != .model }
        let floor = main.floor?.share
        if agentsDone.isEmpty {
            var body = "Every finished test on our tasks is a model on its own."
            body += waitingSentence(rows)
            if let best = main.ranked.first(where: \.isDone), let s = best.scoreText {
                body += " Best so far: \(best.label), \(s) on “\(main.title ?? main.task)”"
                if let f = main.floor { body += "; \(f.text)" }
                body += "."
                if let v = EvalVerdicts.againstFloor(EvalVerdicts.Side(best), floor: floor) { body += " " + v.text + "." }
            }
            return (EvalsAAnswer(tone: .gap, headline: "Can't tell yet for agents", body: body), title, bars)
        }
        let best = (main.ranked.first { $0.isDone && $0.layer != .model }) ?? agentsDone[0]
        let v = EvalVerdicts.againstFloor(EvalVerdicts.Side(best), floor: floor)
        let head = v?.kind == .beatsFloor ? "\(best.label) beats a blind guess" : "Can't tell yet"
        var body = "\(best.label): \(best.scoreText ?? "–") on “\(main.title ?? main.task)”"
        if let f = main.floor { body += "; \(f.text)" }
        body += "."
        if let v { body += " " + v.text + "." }
        body += " Pick two setups in Compare for the paired verdict."
        return (EvalsAAnswer(tone: v?.kind == .beatsFloor ? .call : .cantTell, headline: head, body: body), title, bars)
    }

    /// " Claude Code on its CLI default model has waited since Nov 1 (seat use unknown)."
    static func waitingSentence(_ rows: [EvalSetupRow]) -> String {
        let w = rows.filter(\.isActive)
        guard !w.isEmpty else { return "" }
        return " " + w.prefix(2).map { r in
            let verb = r.status == "running" ? "is running" : "has waited since \(EvalsAWords.day(r.started))"
            return "\(r.label) \(verb)" + (r.statusNote.map { " (\($0))" } ?? "")
        }.joined(separator: "; ") + "."
    }

    /// The mini-chart: finished setups best first (score bar, floor tick), then waiting ones (muted, "waiting").
    public static func bars(_ lb: EvalSetupLeaderboard, limit: Int = 4) -> [EvalsABar] {
        let floor = lb.floor?.share
        return lb.ranked.filter { $0.isDone || $0.isActive }.prefix(limit).map { r in
            if r.isDone {
                let v = EvalVerdicts.againstFloor(EvalVerdicts.Side(r), floor: floor)
                return EvalsABar(label: r.label, value: r.share, text: r.scoreText ?? "–", floor: floor, note: v?.text)
            }
            return EvalsABar(label: r.label, value: nil, text: r.status, floor: floor, note: r.statusNote.map { "\(r.status): \($0)" }, muted: true)
        }
    }

    /// What a test records today, read from the stamps the engine returns (derived stamps of old runs count as not recorded).
    public static func records(_ boards: [EvalSetupLeaderboard]) -> [EvalsARecord] {
        let stamps = boards.flatMap(\.rows).compactMap(\.stamp)
        let recorded = stamps.filter(\.recorded)
        let agents = recorded.filter { $0.effectiveLayer != .model }
        let anyAgentRow = stamps.contains { $0.effectiveLayer != .model }
        func st(_ yes: Bool, partly: Bool = false) -> EvalsARecord.State { yes ? .yes : (partly ? .partly : .no) }
        return [
            EvalsARecord(label: "Task and version", state: st(stamps.contains { $0.taskVersion != nil })),
            EvalsARecord(label: "Model, for a model on its own", state: st(stamps.contains { $0.effectiveLayer == .model && $0.model != nil })),
            EvalsARecord(label: "Model, for an agent", state: st(agents.contains { $0.model != nil },
                                                                 partly: anyAgentRow && stamps.contains { $0.effectiveLayer != .model && $0.model != nil })),
            EvalsARecord(label: "Agent CLI version", state: st(agents.contains { $0.agentVersion != nil })),
            EvalsARecord(label: "Our rules: on or off, which version", state: st(agents.contains { $0.rules != nil })),
        ]
    }

    /// Q2 · Did my last change help? Real changes only (nil while reading); stamps from the leaderboards.
    public static func didMyChangeHelp(_ boards: [EvalSetupLeaderboard], changes: [EvalChange]?) -> EvalsAAnswer {
        let stamped = boards.flatMap(\.rows).filter { ($0.stamp?.recorded ?? false) && $0.layer != .model }
        var tail = ""
        if let c = changes {
            let you = c.filter { $0.who == .you }.count
            tail = c.isEmpty ? " No change to your rules, skills or agents in the last 60 days."
                : " \(EvalsAWords.count(c.count, "change")) in the last 60 days (\(you) yours, \(c.count - you) from the vendor)."
        }
        if let both = changes?.first(where: \.testedAlone) {
            return EvalsAAnswer(tone: .cantTell, headline: "Tested before and after", body: "“\(both.what)” has a test before and after it: Changes shows which bugs flipped." + tail)
        }
        if stamped.isEmpty {
            return EvalsAAnswer(tone: .gap, headline: "Can't answer: not recorded",
                                body: "No test has recorded which version of our rules (CLAUDE.md, skills, permissions) it used, or the model the agent ran, so there is no before and after yet." + tail)
        }
        return EvalsAAnswer(tone: .cantTell, headline: "Can't tell yet",
                            body: "\(EvalsAWords.count(stamped.count, "agent test")) carry a stamp, but no change has a test on both sides. Test the same setup again after your next change." + tail)
    }

    /// Q3 · What does real history say? From X-ray rows (nil while git is read).
    public static func realHistory(_ rows: [EvalHistoryRow]?, repos: Int, days: Int, error: String? = nil) -> (answer: EvalsAAnswer, bars: [EvalsABar]) {
        guard let rows else {
            if let error { return (EvalsAAnswer(tone: .gap, headline: "Can't read git", body: error), []) }
            return (EvalsAAnswer(tone: .reading, headline: "Reading git…", body: "Reading \(EvalsAWords.count(repos, "repo")) over \(days) days (up to a minute)."), [])
        }
        let bars = rows.map { r in
            EvalsABar(label: (r.isUntagged ? "No agent name" : r.agent) + " · " + EvalsAWords.count(r.commits, "commit"),
                      value: r.fixup, text: EvalHistoryRow.pct(r.fixup), note: r.isUntagged ? "can't be split by agent" : nil, muted: r.isUntagged)
        }
        guard let top = EvalsAHistory.top(rows) else {
            return (EvalsAAnswer(tone: .gap, headline: "No agent commits found",
                                 body: "No commit in \(EvalsAWords.count(repos, "repo")) over \(days) days names an agent. Sessions One Roof starts sign them from 2.0.4 (LAB-2241)."), bars)
        }
        var body = "Last \(days) days, \(EvalsAWords.count(repos, "repo")). Reverted: \(EvalHistoryRow.pct(top.revert))."
        if let u = rows.first(where: \.isUntagged), u.commits > 0 {
            body += " \(EvalsAWords.count(u.commits, "more commit")) carry no agent name, so they can't be compared yet (LAB-2241)."
        }
        return (EvalsAAnswer(tone: .call, headline: EvalsAHistory.headline(top), body: body), bars)
    }
}

// MARK: - E2 · Compare: squares, headline, untested setups, the agent × model grid

/// One bug of one setup's test: right, wrong, or not answered (nil).
public struct EvalsASquare: Equatable, Identifiable, Sendable {
    public var id: String
    public var issue: String
    public var title: String?
    public var right: Bool?
    /// The attempts policy: the mean over this bug's attempts (0–1); a square between 0 and 1 is drawn part filled.
    public var score: Double?
    /// Before/after: the bug flipped between the two tests (drawn with a ring).
    public var flipped = false
    public init(id: String, issue: String, title: String? = nil, right: Bool?, score: Double? = nil, flipped: Bool = false) {
        self.id = id; self.issue = issue; self.title = title; self.right = right; self.flipped = flipped
        self.score = score ?? right.map { $0 ? 1 : 0 }
    }
    /// Right on some attempts, not all.
    public var isPartial: Bool { (score ?? 0) > 0 && (score ?? 1) < 1 }
}

public enum EvalsASquares {
    /// Right first, then wrong, then not answered; the set's order inside each group. So the blind-guess tick reads as a
    /// count: the squares left of it are what a guess gets.
    public static func ordered(cases: [EvalSetupLeaderboard.Case], perCase: [EvalSetupRow.CaseRight]) -> [EvalsASquare] {
        let all = inCaseOrder(cases: cases, perCase: perCase)
        func g(_ s: EvalsASquare) -> Int { s.score == nil ? 3 : s.right == true ? 0 : s.isPartial ? 1 : 2 }
        return all.enumerated().sorted { (g($0.element), $0.offset) < (g($1.element), $1.offset) }.map(\.element)
    }

    /// The set's order (before/after rows line up bug for bug). Cases the row never mentions are not answered.
    public static func inCaseOrder(cases: [EvalSetupLeaderboard.Case], perCase: [EvalSetupRow.CaseRight]) -> [EvalsASquare] {
        let by = Dictionary(perCase.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let base = cases.isEmpty ? perCase.map { EvalSetupLeaderboard.Case(id: $0.id, issue: nil, title: nil) } : cases
        return base.map { c in EvalsASquare(id: c.id, issue: c.issue ?? issue(c.id), title: c.title == c.id ? nil : c.title,
                                            right: by[c.id]?.right ?? nil, score: by[c.id]?.score) }
    }

    /// From one run's samples, right first. The attempts policy (as the engine's leaderboard): a bug's score is the mean
    /// over its attempts, right when every attempt was.
    public static func fromSamples(_ xs: [EvalSample]) -> [EvalsASquare] {
        let cases = caseScores(xs)
        return ordered(cases: cases.map { EvalSetupLeaderboard.Case(id: $0.id, issue: $0.issue, title: $0.title) },
                       perCase: cases.map { EvalSetupRow.CaseRight(id: $0.id, right: $0.score.map { $0 >= 1 }, score: $0.score) })
    }
    /// Per bug, in first-seen order: the mean of its scored attempts (nil when none is scored).
    public static func caseScores(_ xs: [EvalSample]) -> [(id: String, issue: String?, title: String?, score: Double?)] {
        var order: [String] = [], first: [String: EvalSample] = [:], vals: [String: [Double]] = [:]
        for s in xs {
            if first[s.sampleID] == nil { first[s.sampleID] = s; order.append(s.sampleID) }
            if let v = s.score { vals[s.sampleID, default: []].append(min(max(v, 0), 1)) }
        }
        return order.map { id in
            let v = vals[id] ?? []
            return (id, first[id]?.issue, first[id]?.title, v.isEmpty ? nil : v.reduce(0, +) / Double(v.count))
        }
    }
    /// Squares in the given order from per-case results (several attempts of one bug: their mean).
    public static func fromCaseResults(_ xs: [EvalCaseResult], order: [String]) -> [EvalsASquare] {
        var vals: [String: [Double]] = [:]
        for x in xs { if let r = x.right { vals[x.id, default: []].append(r ? 1 : 0) } }
        return order.map { id in
            let v = vals[id] ?? []
            let sc = v.isEmpty ? nil : v.reduce(0, +) / Double(v.count)
            return EvalsASquare(id: id, issue: issue(id), right: sc.map { $0 >= 1 }, score: sc)
        }
    }

    /// "LAB-2088" from "LAB-2088-4e2a7a8".
    public static func issue(_ id: String) -> String {
        let p = id.split(separator: "-")
        return p.count >= 3 ? p.prefix(2).joined(separator: "-") : id
    }

    /// How many squares sit left of the blind-guess tick: the floor's right answers, scaled to this row's bugs.
    public static func guessIndex(floor: EvalSetupLeaderboard.Floor?, n: Int) -> Int? {
        guard let f = floor, f.of > 0, n > 0 else { return nil }
        return f.of == n ? f.right : Int((Double(f.right) / Double(f.of) * Double(n)).rounded())
    }

    /// Before → after, in the set's order, with every bug that changed marked.
    public static func flips(before: [EvalsASquare], after: [EvalsASquare]) -> (before: [EvalsASquare], after: [EvalsASquare], toRight: [String], toWrong: [String]) {
        let b = Dictionary(before.map { ($0.id, $0.right) }, uniquingKeysWith: { a, _ in a })
        var toRight: [String] = [], toWrong: [String] = []
        let a2 = after.map { s -> EvalsASquare in
            var s = s
            if let old = b[s.id] ?? nil, let new = s.right, old != new {
                s.flipped = true
                if new { toRight.append(s.issue) } else { toWrong.append(s.issue) }
            }
            return s
        }
        let flipped = Set(a2.filter(\.flipped).map(\.id))
        let b2 = before.map { s -> EvalsASquare in var s = s; s.flipped = flipped.contains(s.id); return s }
        return (b2, a2, toRight, toWrong)
    }
}

/// A setup not tested on a task yet: an agent on a seat, or a model on its own seen on another of our tasks.
public struct EvalsAUntested: Equatable, Identifiable, Sendable {
    public var label: String
    public var agent: String?
    public var model: String?
    /// An agent with our rules on (the full setup).
    public var rules: Bool
    public var id: String { (agent.map { $0 + ":" + (model ?? "default") + (rules ? ":on" : ":off") }) ?? model ?? label }
    public init(label: String, agent: String?, model: String?, rules: Bool = false) {
        self.label = label; self.agent = agent; self.model = model; self.rules = rules && agent != nil
    }
    /// The setup the sheet pre-fills: an agent on its seat with this model (nil = CLI default) and rules, or the model alone.
    public var choice: EvalSetupChoice? {
        if let a = agent { return .seat(a, model: model, rules: rules) }
        return model.map { EvalSetupChoice.model($0) }
    }
}

public enum EvalsACompare {
    /// One line of meaning on top of Compare, chosen by rule from the ranked rows, the floor and the layers.
    public static func headline(_ lb: EvalSetupLeaderboard) -> String {
        let ranked = lb.ranked
        guard let best = ranked.first(where: \.isDone), let r = best.right.map(EvalScoreText.count), let n = best.n else {
            let w = ranked.first(where: \.isActive)
            return "No setup has finished this task yet." + (w.map { " \($0.label) is \($0.status)" + ($0.statusNote.map { ": \($0)" } ?? "") + "." } ?? "")
        }
        var s = "\(best.label.contains(",") ? best.label + "," : best.label) got \(r) of \(n) bugs right"
        if let f = lb.floor { s += "; \(f.text)" }
        s += "."
        if let v = EvalVerdicts.againstFloor(EvalVerdicts.Side(best), floor: lb.floor?.share) { s += " " + v.text + "." }
        let done = ranked.filter(\.isDone)
        if !done.contains(where: { $0.layer != .model }) {
            s += " No agent has finished this task yet."
        } else if done.count > 1 {
            s += " Pick two rows for the paired verdict."
        }
        return s
    }

    /// "Missed LAB-2088 and LAB-2094: nobody has solved those yet." (nil when it got every bug).
    public static func missedText(_ row: EvalSetupRow, in lb: EvalSetupLeaderboard) -> String? {
        guard row.isDone else { return nil }
        let wrong = row.perCase.filter { $0.right == false }.map(\.id)
        guard !wrong.isEmpty else { return nil }
        let solved = Set(lb.rows.filter(\.isDone).flatMap { r in r.perCase.filter { $0.right == true }.map(\.id) })
        let issues = wrong.map(EvalsASquares.issue)
        let shown = issues.count > 4 ? Array(issues.prefix(4)) + ["\(issues.count - 4) more"] : issues
        let nobody = wrong.allSatisfy { !solved.contains($0) }
        return "Missed \(EvalsAWords.list(shown))" + (nobody ? (wrong.count == 1 ? ": nobody has solved it yet." : ": nobody has solved those yet.") : ".")
    }

    /// A waiting / queued / failed / expired row's reason in words.
    public static func statusText(_ r: EvalSetupRow) -> String {
        let since = r.started.map { " since \(EvalsAWords.day($0))" } ?? ""
        let note = r.statusNote.map { ": \($0)" } ?? ""
        // QA #6: a note that already says since when ("stuck: waiting since 2026-11-01 …") is the whole sentence; never the date twice.
        if ["waiting", "queued"].contains(r.status), let n = r.statusNote, n.lowercased().contains("since") {
            return n.prefix(1).uppercased() + n.dropFirst()
        }
        switch r.status {
        case "waiting": return "Waiting\(since)\(note)"
        case "queued": return "Queued\(since)\(note)"
        case "running": return "Running\(note)"
        case "expired": return "Expired\(note.isEmpty ? ": waited 6 hours with seat use unknown" : note)"
        case "failed": return "Failed\(note)"
        default: return r.status
        }
    }

    /// The setups not tested on this task: the agent CLIs with no row (any status but failed / expired), then models that
    /// answered another of our tasks on their own.
    public static func untested(_ lb: EvalSetupLeaderboard, others: [EvalSetupLeaderboard]) -> [EvalsAUntested] {
        let live = lb.rows.filter { !["failed", "expired"].contains($0.status) }
        var out: [EvalsAUntested] = []
        for a in EvalsAWords.seatAgents {
            let has = live.contains { ($0.stamp?.agent ?? String($0.setupId.split(separator: ":").first ?? "")) == a.key }
            if !has { out.append(EvalsAUntested(label: "\(a.name), on your \(a.seat) seat", agent: a.key, model: nil)) }
        }
        let here = Set(live.map(\.setupId))
        var seen = Set<String>()
        for o in others where o.task != lb.task {
            for r in o.rows where r.layer == .model && r.isDone && !here.contains(r.setupId) && !seen.contains(r.setupId) {
                seen.insert(r.setupId)
                out.append(EvalsAUntested(label: r.label, agent: nil, model: providerModel(r)))
            }
        }
        return out
    }

    /// "anthropic/claude-haiku-5-5" from a model row's stamp (runs_on api:anthropic) or its setup id.
    public static func providerModel(_ r: EvalSetupRow) -> String? {
        let m = r.stamp?.model ?? (r.setupId.hasPrefix("model:") ? String(r.setupId.dropFirst(6)) : nil)
        guard let m else { return nil }
        if m.contains("/") { return m }
        if let on = r.stamp?.runsOn, on.hasPrefix("api:") { return String(on.dropFirst(4)) + "/" + m }
        return m
    }

    /// Set up a test, pre-filled with the untested setups on this task (nothing starts until Start).
    /// Each untested setup is carried whole (agent + model + rules) in `setups`, so the sheet never falls back to the CLI
    /// default for an agent whose model was chosen (review P2 #7); the 2.0.3 fields stay filled for old readers.
    public static func plan(_ xs: [EvalsAUntested], taskFile: String, cases: Int) -> EvalRunPlan {
        var p = EvalRunPlan(tasks: [taskFile], models: xs.filter { $0.agent == nil }.compactMap(\.model), limit: max(cases, 1), cap: 2.0,
                            agents: xs.compactMap(\.agent))
        p.setups = xs.compactMap(\.choice)
        return p
    }

    /// The paired difference from `compare <A> <B>` (unpaired runs share no bugs: never a winner).
    public static func paired(_ c: EvalCompareResult) -> EvalVerdicts.Paired {
        EvalVerdicts.Paired(diff: c.diff, lo: c.ci95.first ?? c.diff, hi: c.ci95.last ?? c.diff, shared: c.paired ? c.n : 0)
    }

    /// "Only Opus solved LAB-1612 and LAB-1620 · only Haiku solved none · 8 tied".
    public static func onlyLine(_ c: EvalCompareResult, a: String, b: String) -> String {
        func names(_ xs: [String]) -> String { xs.isEmpty ? "none" : EvalsAWords.list(xs.prefix(5).map(EvalsASquares.issue) + (xs.count > 5 ? ["\(xs.count - 5) more"] : [])) }
        return "Only \(a) solved \(names(c.onlyA)) · only \(b) solved \(names(c.onlyB)) · \(c.tied) tied"
    }
}

/// v1 screen 2: who does the work (rows) × the model (columns), one cell per setup on the same frozen bugs.
public struct EvalsAGrid: Equatable, Sendable {
    public struct Row: Equatable, Identifiable, Sendable {
        public var title: String
        public var sub: String
        public var agent: String?
        public var cells: [String: EvalSetupRow]
        public var id: String { agent ?? "model" }
    }
    public static let cliDefault = "CLI default"
    public var columns: [String]
    public var rows: [Row]

    /// Rules mode is a dimension of the grid (review P2 #8): `rules` false (the default, "off (clean)") shows only agent
    /// runs with no rules, so a layer-2 row never holds a rules-on result; true shows the full setups (layer 3). The model
    /// row is the same in both. Each cell is that setup's LATEST finished run (else its latest live one), never the
    /// highest score.
    public static func build(_ lb: EvalSetupLeaderboard, rules: Bool = false) -> EvalsAGrid {
        func agentOf(_ r: EvalSetupRow) -> String? {
            if let a = r.stamp?.agent { return a }
            if r.setupId.hasPrefix("model:") { return nil }
            return String(r.setupId.split(separator: ":").first ?? "")
        }
        func modelOf(_ r: EvalSetupRow) -> String {
            if let m = r.stamp?.model { return m }
            let p = r.setupId.split(separator: ":").map(String.init)
            if r.setupId.hasPrefix("model:") { return p.dropFirst().joined(separator: ":") }
            return p.count > 1 && p[1] != "default" ? p[1] : cliDefault
        }
        var cells: [String: [String: EvalSetupRow]] = [:]
        var columns: [String] = []
        // finished before live, newest first inside each: the first row a cell sees is the one it keeps
        let order = lb.rows.enumerated().sorted { x, y in
            let (a, b) = (x.element, y.element)
            if a.isDone != b.isDone { return a.isDone }
            let (sa, sb) = (a.started ?? "", b.started ?? "")
            return sa != sb ? sa > sb : x.offset < y.offset
        }.map(\.element)
        for r in order where !["failed"].contains(r.status) {
            let a = agentOf(r)
            if a != nil && (r.layer == .full) != rules { continue }
            let m = modelOf(r)
            if !columns.contains(m) { columns.append(m) }
            if cells[a ?? ""]?[m] == nil { cells[a ?? "", default: [:]][m] = r }
        }
        columns.sort { ($0 == cliDefault ? 1 : 0, $0) < ($1 == cliDefault ? 1 : 0, $1) }
        // QA #5 (D4/D5): plain words, no "layer N".
        let layer = rules ? "with our rules" : "clean (no rules)"
        var rows = [Row(title: "Model on its own", sub: "the API, no tools", agent: nil, cells: cells[""] ?? [:])]
        for a in EvalsAWords.seatAgents {
            rows.append(Row(title: a.name, sub: "\(layer) · on your \(a.seat) seat", agent: a.key, cells: cells[a.key] ?? [:]))
        }
        for (a, c) in cells.sorted(by: { $0.key < $1.key }) where !a.isEmpty && !EvalsAWords.seatAgents.contains(where: { $0.key == a }) {
            rows.append(Row(title: a, sub: layer, agent: a, cells: c))
        }
        return EvalsAGrid(columns: columns, rows: rows)
    }

    /// The setup an empty cell tests (review P2 #7): an agent row carries the column's model (the CLI default column: no
    /// model) and the grid's rules mode; nil when that agent's CLI cannot be asked for that model (the cell is disabled,
    /// never silently the default). The model row: the model alone, with its provider.
    public static func choice(agent: String?, column: String, rules: Bool, lb: EvalSetupLeaderboard) -> EvalSetupChoice? {
        guard let a = agent else {
            guard column != cliDefault else { return nil }
            let m = lb.rows.first { $0.layer == .model && ($0.stamp?.model ?? "") == column }.flatMap(EvalsACompare.providerModel) ?? column
            return .model(m)
        }
        if column == cliDefault { return .seat(a, model: nil, rules: rules) }
        guard EvalSetupChoice.supports(agent: a, model: column) else { return nil }
        return .seat(a, model: EvalSetupChoice.cliModel(column), rules: rules)
    }
}

// MARK: - E2.2 · one test, bug by bug

public enum EvalsAOneTest {
    /// The files the answer named and the files the fix changed (CONTRACT §4; the code check's lists before 2.0.4).
    public static func evidence(_ s: EvalSample) -> (named: [String], changed: [String]) {
        (s.named ?? s.code?.named ?? [], s.changed ?? s.code?.changed ?? [])
    }

    /// Why it was marked so, in words: checked by code, no model involved.
    public static func markLine(named: [String], changed: [String], right: Bool) -> String {
        if named.isEmpty { return right ? "Marked right by its scorer." : "It named no file, so it's marked wrong. Checked automatically, no model involved." }
        let hits = named.filter { n in changed.contains { $0 == n || $0.hasSuffix("/" + n) || n.hasSuffix("/" + $0) } }
        if right || !hits.isEmpty {
            let f = (hits.first.map { ($0 as NSString).lastPathComponent }) ?? "One of them"
            return "\(f) is a file the fix changed, so it's marked right. Checked automatically, no model involved."
        }
        let which = named.count == 1 ? "The file it named is not" : (named.count == 2 ? "Neither of the two is" : "None of the \(named.count) is")
        return "\(which) a file the fix changed, so it's marked wrong. Checked automatically, no model involved."
    }

    /// "8 of 10" (or "7.5 of 10") and the Wilson range, by the attempts policy: right = the sum of the bug scores, the range
    /// Wilson on that accuracy with n = the bugs (CONTRACT §3 note).
    public static func score(_ xs: [EvalsASquare]) -> (right: Double, n: Int, lo: Double, hi: Double)? {
        let answered = xs.filter { $0.score != nil }
        guard !answered.isEmpty else { return nil }
        let r = answered.reduce(0) { $0 + ($1.score ?? 0) }, n = answered.count
        let w = EvalStats.wilson(r / Double(n), n: n)
        return (r, n, w.lo, w.hi)
    }
}

/// `results --json` rows carry the stamp and setup id from 2.0.4 (EvalResult itself keeps its 2.0.3 shape).
public struct EvalsARunStamp: Decodable, Equatable, Sendable {
    public var id: String
    public var stamp: EvalStamp?
    public var setupId: String?
}

// MARK: - E2.3 · all results

public struct EvalsAAllGrid: Equatable, Sendable {
    public struct Column: Equatable, Identifiable, Sendable {
        public var key: String
        public var title: String
        /// Our own task (blue) — a set, or a grader / labeller study of our notes.
        public var own: Bool
        /// A grader: the cell is agreement with your labels, not a score.
        public var grader: Bool
        public var id: String { key }
    }
    public var columns: [Column]
    public var rows: [String]
    public var cells: [String: [String: EvalResult]]
    public var finished: Int
    public var tasks: Int

    public func cell(_ row: String, _ col: String) -> EvalResult? { cells[row]?[col] }

    /// The latest finished result per (who answered, task): our tasks first (sets, then graders), public after.
    public static func build(_ results: [EvalResult], sets: [EvalSetList.Entry]) -> EvalsAAllGrid {
        var cells: [String: [String: EvalResult]] = [:]
        var cols: [String: Column] = [:]
        var runsPer: [String: Int] = [:]
        var setOrder: [String: Int] = [:]
        for (i, s) in sets.enumerated() { setOrder[s.name] = i }
        let done = results.filter { $0.status == "done" }
        for r in done {
            guard let c = column(r, sets: sets) else { continue }
            let row = rowKey(r)
            cols[c.key] = c
            runsPer[c.key, default: 0] += 1
            if let old = cells[row]?[c.key], (old.started ?? "") >= (r.started ?? "") { continue }
            cells[row, default: [:]][c.key] = r
        }
        let ordered = cols.values.sorted { a, b in
            func g(_ c: Column) -> Int { c.own ? (c.key.contains("@v") ? 0 : 1) : 2 }   // our sets, then graders / labellers, then public
            if g(a) != g(b) { return g(a) < g(b) }
            if g(a) == 0 { return a.key < b.key }
            if g(a) == 2, runsPer[a.key] != runsPer[b.key] { return (runsPer[a.key] ?? 0) > (runsPer[b.key] ?? 0) }
            return a.key < b.key
        }
        let ownKeys = Set(ordered.filter(\.own).map(\.key))
        let rows = cells.keys.sorted { a, b in
            func g(_ k: String) -> Int {
                if k.hasPrefix("mockllm/") { return 3 }
                return (cells[k]?.keys.contains { ownKeys.contains($0) } ?? false) ? 0 : 1
            }
            return (g(a), a) < (g(b), b)
        }
        return EvalsAAllGrid(columns: ordered, rows: rows, cells: cells, finished: done.count, tasks: cols.count)
    }

    /// Who answered: the agent with its model, else the model ("claude-opus-5-5", "Codex · claude-haiku-5-5").
    public static func rowKey(_ r: EvalResult) -> String {
        if r.contestant?.kind == .agent, let n = r.contestant?.name {
            // The engine repeats the model for agents on an API model ("Codex · claude-haiku-5-5 · claude-haiku-5-5"): once is enough.
            var parts: [String] = []
            for p in n.components(separatedBy: " · ") where parts.last != p { parts.append(p) }
            return parts.joined(separator: " · ")
        }
        return EvalModels.short(r.model ?? r.contestant?.name ?? "?")
    }

    static func column(_ r: EvalResult, sets: [EvalSetList.Entry]) -> Column? {
        let task = r.task ?? ""
        if let s = r.setName {
            let kind = sets.first { $0.name == s }?.kindTitle ?? s
            return Column(key: "\(s)@v\(r.setVersion ?? 1)", title: "\(kind) v\(r.setVersion ?? 1)", own: true, grader: false)
        }
        if task.hasPrefix("judge_") || task.hasPrefix("labeller_") {
            let isJudge = task.hasPrefix("judge_")
            var rest = String(task.dropFirst(isJudge ? 6 : 9))
            if let v = rest.range(of: "_v", options: .backwards) { rest = String(rest[..<v.lowerBound]) }
            let name = rest.replacingOccurrences(of: "oneroof_", with: "").replacingOccurrences(of: "_", with: " ")
            // A grader's cell is its agreement with your labels; a labeller's is the share of notes it passed (neither is a score).
            return Column(key: task, title: isJudge ? "\(name) grader · agreement" : "\(name) labeller · share passed", own: true, grader: isJudge)
        }
        guard !task.isEmpty else { return nil }
        return Column(key: task, title: EvalBenchmark.taskLabel(task), own: false, grader: false)
    }
}

// MARK: - E3 · Changes

public enum EvalsAChanges {
    public static func who(_ c: EvalChange) -> String { c.who == .you ? "You" : "Vendor" }
    public static func status(_ c: EvalChange) -> String {
        if c.isSpan { return "covers \(c.tested?.spans?.count ?? 2) changes together — can't tell which one" }
        if c.testedBoth { return "tested before and after" }
        if c.tested?.before != nil { return "tested before only" }
        if c.tested?.after != nil { return "tested after only" }
        // review fix 3: the engine pairs only comparable runs (same task version, agent, models, rules mode)
        return "no comparable before/after tests"
    }
    /// No stamped test (recorded agent / full layer) yet: the page says "We can't tell yet".
    public static func canTell(_ boards: [EvalSetupLeaderboard]) -> Bool {
        boards.flatMap(\.rows).contains { ($0.stamp?.recorded ?? false) && $0.layer != .model && $0.isDone }
    }
    /// The plain lead before the rule's sentence: "Probably helped, not proven" while the range includes 0.
    public static func lead(diff: Double, verdict: EvalVerdicts.Verdict) -> String {
        switch verdict.kind {
        case .better, .betterOnlyMatchesFloor: return diff > 0 ? "Helped" : "Hurt"
        case .cantTell, .tooFewShared: return diff > 0 ? "Probably helped, not proven" : diff < 0 ? "Probably hurt, not proven" : "No change seen"
        default: return "Not run yet"
        }
    }
    /// The blind-guess floor of the pair's task version (re-review #5): read by the task + task_version the pair recorded,
    /// never by finding its runs in the latest boards (a repeat displaces them, a new version replaces the board).
    public enum Floor: Equatable, Sendable {
        case reading
        case known(Double)
        /// Not found (no task version on the pair, the board could not be read, it is another version, or it has no
        /// floor): a winner is named only with the caveat.
        case unknown
    }
    /// The engine call that reads the floor of the pair's task version; nil = the pair recorded none (floor unknown).
    public static func floorQuery(_ c: EvalChange) -> [String]? {
        guard let task = c.tested?.task, !task.isEmpty, let v = c.tested?.taskVersion else { return nil }
        return ["leaderboard", task, "--version", String(v), "--by", "setup"]
    }
    /// The floor from that board: only when it is the pair's own version and has a floor.
    public static func floor(of c: EvalChange, board: EvalSetupLeaderboard?) -> Floor {
        guard let b = board, let v = c.tested?.taskVersion, b.version == v, let share = b.floor?.share else { return .unknown }
        return .known(share)
    }
    public static let floorUnknownCaveat = "floor unknown — can't check it against a blind guess"
    /// One side of the before/after pair: its right answers (attempts policy) and its own Wilson range.
    public static func side(_ label: String, _ xs: [EvalsASquare]) -> EvalVerdicts.Side {
        guard let s = EvalsAOneTest.score(xs) else { return EvalVerdicts.Side(label: label, right: nil, n: nil, lo: nil, hi: nil, done: false) }
        return EvalVerdicts.Side(label: label, right: s.right, n: s.n, lo: s.lo, hi: s.hi)
    }
    /// The before/after verdict by rule: the paired compare, each side's Wilson bounds, and the floor of the pair's task
    /// version, so a winner that only matches a blind guess says so.
    public static func verdict(before: [EvalsASquare], after: [EvalsASquare], compare: EvalCompareResult?, floor: Double?) -> EvalVerdicts.Verdict {
        EvalVerdicts.compare(side("After", after), side("Before", before), paired: compare.map(EvalsACompare.paired), floor: floor)
    }
    /// The same, with the floor as read for the pair's task version: while it is unknown (or still being read) a verdict
    /// that names a winner carries the caveat "floor unknown — can't check it against a blind guess" (re-review #5).
    public static func verdict(before: [EvalsASquare], after: [EvalsASquare], compare: EvalCompareResult?, floor: Floor) -> EvalVerdicts.Verdict {
        if case .known(let f) = floor { return verdict(before: before, after: after, compare: compare, floor: f) }
        var v = verdict(before: before, after: after, compare: compare, floor: nil)
        if v.winner != nil { v.text += " (" + floorUnknownCaveat + ")" }
        return v
    }
    /// "3 bugs flipped to right, 1 flipped to wrong."
    public static func flipLine(toRight: Int, toWrong: Int) -> String {
        if toRight == 0 && toWrong == 0 { return "No bug flipped." }
        return "\(EvalsAWords.count(toRight, "bug")) flipped to right, \(toWrong) flipped to wrong."
    }
}

// MARK: - E4 · Real history

public enum EvalsAHistory {
    /// The untagged bar's words (QA m9): facts only, no guess at who made the commits.
    public static let untaggedLine = "Commits with no agent name: Codex, Kimi and hand edits don't add one yet (LAB-2241), so they can't be split by agent"
    /// The agent with the most signed commits (never the unattributed row).
    public static func top(_ rows: [EvalHistoryRow]) -> EvalHistoryRow? {
        rows.filter { !$0.isUntagged && $0.commits > 0 }.max { $0.commits < $1.commits }
    }
    /// "123 of Claude's 657 commits (18.7 %) were followed by a fix": the count is fixup × commits, the % one decimal.
    public static func headline(_ r: EvalHistoryRow) -> String {
        let n = r.followedByFix ?? 0
        return "\(n) of \(r.agent)'s \(r.commits) commits (\(EvalHistoryRow.pct(r.fixup))) were followed by a fix"
    }
    /// The page's headline sentence: the top agent, reverts, and what can't be read.
    public static func pageHeadline(_ rows: [EvalHistoryRow]) -> String {
        guard let t = top(rows) else {
            return rows.isEmpty ? "No commits in this window." : "No commit names an agent yet, so no agent can be read."
        }
        var s = headline(t) + "."
        let rev = t.reverted ?? 0
        s += rev == 0 ? " None was reverted." : " \(EvalsAWords.count(rev, "was", "were")) reverted (\(EvalHistoryRow.pct(t.revert)))."
        if let u = rows.first(where: \.isUntagged), u.commits > 0 { s += " \(EvalsAWords.count(u.commits, "commit")) carry no agent name, so other agents can't be read yet." }
        return s
    }
    /// Share of the bar: followed by a fix, the rest (reverted is drawn on its own, it is tiny).
    public static func split(_ r: EvalHistoryRow) -> (fix: Int, rest: Int) {
        let f = min(r.followedByFix ?? 0, r.commits)
        return (f, r.commits - f)
    }

    /// v1 screen 6: test vs history, side by side once both exist for the same setup.
    public struct JoinRow: Equatable, Identifiable, Sendable {
        public var setup: String
        public var test: String
        public var history: String
        public var reading: String
        public var id: String { setup }
    }

    public static func join(_ lb: EvalSetupLeaderboard?, history: [EvalHistoryRow]) -> [JoinRow] {
        EvalsAWords.seatAgents.map { a in
            let rows = lb?.rows.filter { ($0.stamp?.agent ?? String($0.setupId.split(separator: ":").first ?? "")) == a.key } ?? []
            let done = rows.first(where: \.isDone)
            let live = rows.first(where: \.isActive)
            let test: String
            if let d = done, let s = d.scoreText { test = s + (d.stamp?.model.map { " · \($0)" } ?? "") }
            else if let l = live { test = EvalsACompare.statusText(l) }
            else { test = "not run" }
            let first = a.name.split(separator: " ").first.map(String.init) ?? a.name
            let h = history.first { !$0.isUntagged && ($0.agent == a.name || $0.agent == first) }
            let hist = h.map { "\(EvalHistoryRow.pct($0.fixup)) followed by a fix · all models together" } ?? "unsigned commits"
            let reading: String
            if done != nil && h != nil { reading = "read them side by side: fair test vs real work" }
            else if h == nil { reading = "needs signed commits (LAB-2241)" }
            else { reading = "needs a finished test on this task" }
            return JoinRow(setup: "\(a.name) · \(done?.stamp?.model ?? "any model")", test: test, history: hist, reading: reading)
        }
    }
}
