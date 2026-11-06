import Foundation

// LAB-ONEROOF-v2.0.6 · Loops v7 (Claude Design handover), Lane A: the pure logic behind four screens. The app builds the
// rows (LoopsV7.rows), the Needs you items (LoopInbox.items) and reads the rounds off the main thread; these return what
// the views draw.
//   LAB-2287  7b a kind's page: head line, For you / this week / gap cards, on and off groups, its own state chips
//   LAB-2288  7c one loop · Now: state and facts chips, last run step by step, runs grouped, what you can do, next run
//   LAB-2289  7d Needs you: type tabs, rows, questions first, By kind, Stale after 7 days (LP-5), the title and estimate
//   LAB-2290  7l a round asks permission: the question card's words, the command from the prompt, the loop's allow rule

// MARK: - 7b · a kind's page

extension LoopsV7 {
    /// 7b's state chips (All · On · Off · Needs setup), applied on top of the search.
    public enum KindChip: String, CaseIterable, Equatable, Sendable {
        case all, on, off, needsSetup
        public var label: String {
            switch self { case .all: return "All"; case .on: return "On"; case .off: return "Off"; case .needsSetup: return "Needs setup" }
        }
    }

    /// A card on 7b: a micro label, a bold line, a plain line and (for For you and the gap) a button.
    public struct KindCard: Equatable, Sendable {
        public var label: String
        public var title: String
        public var text: String
        public var asks: [Ask]
        public init(label: String, title: String, text: String, asks: [Ask] = []) {
            self.label = label; self.title = title; self.text = text; self.asks = asks
        }
    }

    public struct KindPage: Equatable, Sendable {
        public var family: LoopKinds.Family
        public var on: Int
        public var all: Int
        /// "Sentinel · Prober".
        public var subtypes: String
        public var blurb: String
        /// The bold sentences on how the kind is doing (real counts and dates).
        public var status: String
        public var forYou: KindCard
        public var week: KindCard
        public var gap: KindCard
        /// True when the gap card is "Ready" (every loop of the kind is on).
        public var ready: Bool
        public var onRows: [LoopRow]
        public var offRows: [LoopRow]
    }

    /// "CAUGHT THIS WEEK" (Watch, Check), "KEPT THIS WEEK" (Improve), "WRITTEN THIS WEEK" (Report), "THIS WEEK".
    public static func kindWeekLabel(_ family: String) -> String {
        switch family {
        case "watch", "check": return "Caught this week"
        case "improve": return "Kept this week"
        case "report": return "Written this week"
        default: return "This week"
        }
    }

    /// How many findings a run's summary reports ("pass, 2 finding(s)" → 2); nil when it does not say.
    public static func findings(_ summary: String) -> Int? {
        guard let m = summary.range(of: #"(\d+) finding\(s\)"#, options: .regularExpression) else { return nil }
        return Int(summary[m].split(separator: " ")[0])
    }

    /// 7b for one kind: the head, the three cards and the on / off groups (filter applied by the view).
    public static func kindPage(family fid: String, rows: [LoopRow], items: [LoopInbox.Item], weekRuns: [LoopRun7],
                                pinned: Set<String> = [], setupMissing: Set<String> = [], kitKnown: Bool = true,
                                now: Date = Date(), calendar cal: Calendar = .current) -> KindPage {
        let fam = LoopKinds.family(fid) ?? LoopKinds.otherFamily
        let mine = rows.filter { $0.family == fid }
        let lane = lanes(rows: rows, items: items, pinned: pinned, setupMissing: setupMissing, kitKnown: kitKnown, now: now, calendar: cal)
            .first { $0.id == fid }
        let byName: (LoopRow, LoopRow) -> Bool = { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        let onRows = lane?.rows ?? mine.filter(\.on).sorted(by: byName)
        let offRows = mine.filter { !$0.on }.sorted { a, b in
            let (sa, sb) = (setupMissing.contains(a.id), setupMissing.contains(b.id))
            if sa != sb { return sa }   // needs setup first (as the shot), then by name
            return byName(a, b)
        }

        // Status: the live ones and their last run, then each failing or missed loop by name, with its date.
        var status: [String] = []
        let live = onRows.filter { $0.mode == .live }
        let liveFailed = live.filter { $0.lastRun?.result == .failed }
        if onRows.isEmpty {
            status.append(kitKnown || fid == "other" ? "None is on." : "None is on that One Roof knows of: the kit could not be read.")
        } else if !live.isEmpty {
            if liveFailed.isEmpty {
                let ran = live.filter { $0.lastRun != nil }.count
                status.append(ran == live.count
                              ? (live.count == 1 ? "The live one passed its last run." : "All \(live.count) live ones passed their last run.")
                              : "\(ran) of \(live.count) live ones have run; every run passed.")
            } else {
                let names = liveFailed.map(\.name).joined(separator: ", ")
                let n = liveFailed.count
                status.append("\(n) of \(live.count) live \(n == 1 ? "one" : "ones") failed \(n == 1 ? "its" : "their") last run: \(names).")
            }
        }
        for r in onRows where r.state == .missed {
            let since = r.lastRun.map { "hasn't run since " + monthDay($0.started, cal) } ?? "hasn't run yet"
            status.append(r.name + (r.mode == .shadow ? ", in its trial, " : " ") + since + ".")
        }
        for r in onRows where r.mode == .shadow && r.state != .missed {
            status.append(r.name + " is in its trial" + (r.lastRun == nil ? ", first run " + (r.nextRun.map { when($0, now: now, calendar: cal) } ?? "not scheduled") : "") + ".")
        }

        // For you: the lane's asks (Run now, Review, Open, Answer …); none → "Nothing for you".
        let asks = lane?.asks.filter { if case .setKind = $0.action { return fid == "other" }; return true } ?? []
        let forYou: KindCard
        if let first = asks.first {
            let more = asks.count > 1 ? " And \(asks.count - 1) more." : ""
            forYou = KindCard(label: "For you", title: first.text, text: first.detail.isEmpty ? String(more.dropFirst()) : first.detail + "." + more,
                              asks: Array(asks.prefix(3)))
        } else {
            forYou = KindCard(label: "For you", title: "Nothing waits for you", text: "No item from a \(fam.title) loop is in Needs you.")
        }

        // This week: what the kind's loops found in their runs of the last 7 days (findings from each run's summary).
        let ids = Set(onRows.map(\.id))
        let week = weekRuns.filter { ids.contains($0.loop) && $0.started >= now.addingTimeInterval(-7 * 86400) && $0.started <= now }
        let nameOf = Dictionary(mine.map { ($0.id, $0.name) }, uniquingKeysWith: { a, _ in a })
        var found: [(name: String, n: Int, at: Date)] = []
        var quiet: [String] = []
        var quietRuns = 0
        for id in onRows.map(\.id) {
            let rs = week.filter { $0.loop == id }.sorted { $0.started < $1.started }
            guard !rs.isEmpty else { continue }
            let hits = rs.filter { (findings($0.summary) ?? 0) > 0 }
            if let last = hits.last, let n = findings(last.summary) { found.append((nameOf[id] ?? id, n, last.started)) }
            else { quiet.append(nameOf[id] ?? id); quietRuns += rs.count }
        }
        let failedRuns = week.filter { $0.result == .failed }.count
        let weekCard: KindCard
        if week.isEmpty {
            weekCard = KindCard(label: kindWeekLabel(fid), title: "No runs this week", text: onRows.isEmpty ? "No \(fam.title) loop is on." : "None of its loops has run in the last 7 days.")
        } else {
            let total = found.map(\.n).reduce(0, +)
            let title = total == 0
                ? "Nothing found: \(week.count) quiet run\(week.count == 1 ? "" : "s")"
                : "\(total) finding\(total == 1 ? "" : "s") from \(found.count) loop\(found.count == 1 ? "" : "s")" + (failedRuns > 0 ? " · \(failedRuns) failed" : "")
            var parts = found.prefix(3).map { "\($0.name), \($0.n) at \(when($0.at, now: now, calendar: cal))" }
            if !quiet.isEmpty {
                parts.append(listWords(quiet) + ": \(quietRuns) quiet run\(quietRuns == 1 ? "" : "s")")
            }
            weekCard = KindCard(label: kindWeekLabel(fid), title: title, text: parts.joined(separator: ". ") + ".")
        }

        // Gap: one off loop that would cover this kind (ready to turn on first, then one needing setup) or Ready.
        let gapAsk = lane?.gaps.first { if case .kind = $0.action { return false }; return true }
        let gapRow = gapAsk.flatMap { a -> LoopRow? in
            switch a.action { case .turnOn(let id), .setUp(let id): return mine.first { $0.id == id }; default: return nil }
        }
        let gap: KindCard
        if let a = gapAsk, let g = gapRow {
            let needs = setupMissing.contains(g.id)
            let what = shortGoal(g.goal)
            gap = KindCard(label: "Gap", title: "Off: " + (what.isEmpty ? g.name : what),
                           text: g.name + (needs ? " needs setup first." : " is ready to turn on; it starts with trial runs."),
                           asks: [Ask(id: a.id, text: a.text, button: (needs ? "Set up " : "Turn on ") + g.name, primary: false, action: a.action, detail: a.detail)])
        } else if fid == "other" {
            gap = KindCard(label: "No kind", title: "\(mine.count) loop\(mine.count == 1 ? " has" : "s have") no kind",
                           text: "A kind puts a loop in its lane. Setting it is not connected yet (LP-2).")
        } else if offRows.isEmpty {
            gap = KindCard(label: "Ready", title: "Every \(fam.title) loop is on", text: "Nothing of this kind is off.")
        } else {
            gap = KindCard(label: "Gap", title: "\(offRows.count) off", text: kitKnown ? "Turn one on from the list below." : "The kit could not be read, so off is not known.")
        }

        return KindPage(family: fam, on: onRows.count, all: mine.count, subtypes: fam.kindTitles, blurb: fam.blurb,
                        status: status.joined(separator: " "), forYou: forYou, week: weekCard, gap: gap,
                        ready: gapAsk == nil && offRows.isEmpty && fid != "other", onRows: onRows, offRows: offRows)
    }

    /// "A", "A and B", "A, B and C".
    static func listWords(_ xs: [String]) -> String {
        guard xs.count > 1 else { return xs.first ?? "" }
        return xs.dropLast().joined(separator: ", ") + " and " + xs.last!
    }

    /// 7b's chips over rows that already passed the search.
    public static func kindChip(_ rows: [LoopRow], _ chip: KindChip, setupMissing: Set<String>) -> [LoopRow] {
        switch chip {
        case .all: return rows
        case .on: return rows.filter(\.on)
        case .off: return rows.filter { !$0.on }
        case .needsSetup: return rows.filter { setupMissing.contains($0.id) }
        }
    }

    /// 7b's search: name, what it watches (its goal), its subtype (kind title).
    public static func kindSearch(_ rows: [LoopRow], _ query: String) -> [LoopRow] {
        filter(rows, LoopFilter(query: query))
    }

    /// An off row's RUNS cell: "trial Nov 4" (its last trial run), "last Nov 2", or "never run".
    public static func offRuns(_ r: LoopRow, calendar cal: Calendar = .current) -> String {
        guard let last = r.lastRun else { return "never run" }
        return (last.result == .trial ? "trial " : "last ") + monthDay(last.started, cal)
    }

    /// An on row's sub line: "Sentinel · swap 5.7 GB" (subtype · what its last run said).
    public static func kindSubLine(_ r: LoopRow, now: Date = Date(), calendar cal: Calendar = .current) -> String {
        let sub = subLine(r, now: now, calendar: cal)
        let kind = LoopKinds.kind(r.kind)?.title
        return [kind, sub.isEmpty ? (r.on ? nil : (r.mine ? "mine" : "built-in")) : sub].compactMap { $0 }.joined(separator: " · ")
    }
}

// MARK: - 7c · one loop · Now

extension LoopsV7 {
    /// "failing · 6 nights", "missed · 5 runs", "on · trial", "running", "fine", "off", "not run yet".
    public static func stateChip(_ r: LoopRow) -> (text: String, tone: LoopLook.Tone) {
        let unit = r.schedule.hasPrefix("nightly") ? "night" : "run"
        switch r.state {
        case .failing:
            let n = max(1, failStreak(r))
            return ("failing · \(n) \(unit)\(n == 1 ? "" : "s")", .failing)
        case .missed: return ("missed · \(r.missed) \(unit)\(r.missed == 1 ? "" : "s")", .needsYou)
        case .running: return ("running", .running)
        case .trial: return ("on · trial", .trial)
        case .fine: return ("fine", .fine)
        case .notRun: return ("on · not run yet", .fine)
        case .off: return ("off", .off)
        }
    }

    /// "Mine · One Roof (roofd) · nightly 3:00 · live" — origin · engine · schedule · mode.
    public static func factsChip(_ r: LoopRow, kitKnown: Bool = true) -> String {
        let engine = r.engine == .kit ? "kit (ae, launchd)" : "One Roof (roofd)"
        let mode: String
        if r.engine == .kit && !kitKnown { mode = "kit state unknown" }
        else if !r.on { mode = "off" }
        else { mode = r.mode == .shadow ? "trial" : "live" }
        return [r.mine ? "Mine" : "Built-in", engine, r.schedule, mode].joined(separator: " · ")
    }

    /// One card of "Last run, step by step" (When · Work · Check · Stop · You).
    public struct Step: Equatable, Sendable, Identifiable {
        public enum Who: String, Equatable, Sendable { case oneRoof = "One Roof", kit = "kit", agent = "Agent", you = "You" }
        public enum Tint: String, Equatable, Sendable { case none, failed, you }
        public var id: String { label }
        public var label: String
        public var title: String
        public var text: String
        public var who: Who?
        public var tint: Tint
        public init(label: String, title: String, text: String, who: Who?, tint: Tint = .none) {
            self.label = label; self.title = title; self.text = text; self.who = who; self.tint = tint
        }
    }

    /// The last run as five steps. `rounds` are the loop's round lines (One Roof loops; empty for the kit's), `waiting`
    /// the loop's Needs you items. The kit records a run as one line, so its Work step says so.
    public static func steps(row r: LoopRow, agent: String, branch: String, rounds: [LoopRound], waiting: [LoopInbox.Item],
                             now: Date = Date(), calendar cal: Calendar = .current) -> [Step] {
        guard let last = r.lastRun else {
            let next = r.nextRun.map { "Next: " + when($0, now: now, calendar: cal) + "." } ?? (r.on ? "Runs when started." : "It is off.")
            return [Step(label: "When", title: "Not run yet", text: next, who: r.engine == .kit ? .kit : .oneRoof)]
        }
        let engineWho: Step.Who = r.engine == .kit ? .kit : .oneRoof
        let runner = r.engine == .kit ? "the kit" : "One Roof"
        var out: [Step] = []
        let start = clock(last.started, cal)
        out.append(Step(label: "When", title: start + (cal.isDate(last.started, inSameDayAs: now) ? ", today" : ", " + monthDay(last.started, cal)),
                        text: "Started by \(runner)" + (r.schedule == "manual" ? "." : " (\(r.schedule))."), who: engineWho))
        // The run's rounds: the last run id in the round log (the ledger's run id is the round log's for roofd loops).
        // roofd's run id inside the ledger's (LAB-2293's roofdRunId), else the same id, else the newest run in the log.
        let runId = [roofdRunId(last.id, loop: r.id), last.id].compactMap { $0 }.first { id in rounds.contains { $0.runId == id } }
            ?? rounds.last?.runId
        let runRounds = rounds.filter { $0.runId == runId }
        let work = runRounds.filter { $0.kind == .round }
        if r.engine == .kit {
            out.append(Step(label: "Work", title: "The kit's own check", text: "A kit loop runs its check and writes the result; it starts no agent rounds.", who: .kit))
        } else if work.isEmpty {
            out.append(Step(label: "Work", title: "No rounds", text: "The check ran first; no agent round was needed.", who: .oneRoof))
        } else {
            let ns = work.map(\.n)
            let span = ns.count == 1 ? "round \(ns[0])" : "rounds \(ns.min()!)–\(ns.max()!)"
            out.append(Step(label: "Work", title: "\(agent), \(span)", text: "Worked on \(branch).", who: .agent))
        }
        let check = runRounds.last { $0.kind != .stop }
        let failed = last.result == .failed
        if let c = check, r.engine == .oneRoof {
            let passed = c.checkPassed == true
            // The failure key is "exit 1 · 8972283f" already (roofd's), else the exit code alone.
            let key = c.failureKey?.trimmingCharacters(in: .whitespaces) ?? ""
            let title = passed ? "passed" : key.hasPrefix("exit") ? key : "exit \(c.exitCode.map(String.init) ?? "?")" + (key.isEmpty ? "" : " · " + String(key.prefix(12)))
            out.append(Step(label: "Check", title: title, text: passed ? (c.note ?? "The check passed.") : "The check failed" + (work.count > 1 ? " after \(work.count) rounds." : "."),
                            who: .oneRoof, tint: passed ? .none : .failed))
        } else {
            let said = subLine(r, now: now, calendar: cal)
            out.append(Step(label: "Check", title: failed ? "failed" : last.result == .trial ? "trial" : "passed",
                            text: said.isEmpty ? (failed ? "The check failed." : "The check passed.") : said, who: engineWho, tint: failed ? .failed : .none))
        }
        let stop = runRounds.last { $0.kind == .stop }
        // The ledger's end, else the round log's stop line (a run that stopped is never "still running").
        let endAt = last.ended ?? stop?.ended
        let secs = last.seconds ?? endAt.map { $0.timeIntervalSince(last.started) }
        let ended = endAt.map { "Ended at " + clock($0, cal) + (secs.map { $0 > 0 ? ", " + runTime($0) : "" } ?? "") + "." } ?? "Still running."
        var note = stop?.note?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if let nl = note.firstIndex(of: "\n") { note = String(note[..<nl]) }
        if let cut = note.range(of: ": a new approach") ?? note.range(of: " Tried:") { note = String(note[..<cut.lowerBound]) + "." }
        if note.count > 90 { note = String(note.prefix(89)) + "…" }
        let rule = note.lowercased().contains("same") ? "Stop rule hit" : failed ? "Stopped" : "Done"
        out.append(Step(label: "Stop", title: note.isEmpty ? rule : rule, text: note.isEmpty ? ended : note + " " + ended, who: engineWho))
        let decide = waiting.filter { $0.kind == .staged || $0.kind == .asks }
        if decide.isEmpty {
            out.append(Step(label: "You", title: "Nothing waits", text: "No outcome of this loop waits for you.", who: nil))
        } else {
            let words = outcomeWords(decide.filter { $0.kind == .staged })
            let asks = decide.contains { $0.kind == .asks }
            let since = decide.map(\.when).min().map { " since " + monthDay($0, cal) } ?? ""
            out.append(Step(label: "You", title: asks ? "A round asks you" : (words.isEmpty ? "\(decide.count) waiting" : words + " waiting"),
                            text: "In Needs you" + since + ".", who: .you, tint: .you))
        }
        return out
    }

    /// "14 min", "40 s", "1 h 05".
    public static func runTime(_ s: TimeInterval) -> String {
        let n = Int(s.rounded())
        if n < 60 { return "\(n) s" }
        if n < 3600 { return "\(n / 60) min" }
        return String(format: "%d h %02d", n / 3600, (n % 3600) / 60)
    }

    /// Runs on 7c, newest first; neighbours with the same result and the same line fold into one ("failed ×4").
    public struct RunGroup: Equatable, Sendable, Identifiable {
        public var id: String { newest.id }
        public var newest: LoopRun7
        public var oldest: LoopRun7
        public var count: Int
        /// "Nov 6 3:00" or "Nov 3 … Oct 31".
        public var dates: String
        /// "failed", "failed ×4", "passed", "trial".
        public var result: String
        public var line: String
        /// Time per run (LP-14): "14 min", or "14 min avg" for a group; "" when not recorded.
        public var time: String
    }

    public static func runGroups(_ runs: [LoopRun7], calendar cal: Calendar = .current) -> [RunGroup] {
        let newestFirst = runs.sorted { $0.started > $1.started }
        func line(_ r: LoopRun7) -> String {
            var s = r.summary.trimmingCharacters(in: .whitespacesAndNewlines)
            if let nl = s.firstIndex(of: "\n") { s = String(s[..<nl]) }
            return s.isEmpty ? (r.result == .failed ? "Failed, no summary" : "No summary") : s
        }
        var groups: [[LoopRun7]] = []
        for r in newestFirst {
            if let g = groups.last, let p = g.last, p.result == r.result, line(p) == line(r) { groups[groups.count - 1].append(r) }
            else { groups.append([r]) }
        }
        return groups.map { g in
            let n = g[0], o = g[g.count - 1]
            let word: String
            switch n.result { case .failed: word = "failed"; case .trial: word = "trial"; case .missed: word = "missed"; default: word = "passed" }
            let dates = g.count == 1 ? monthDay(n.started, cal) + " " + clock(n.started, cal)
                : cal.isDate(n.started, inSameDayAs: o.started) ? monthDay(n.started, cal) + " " + clock(o.started, cal) + "–" + clock(n.started, cal)
                : monthDay(n.started, cal) + " … " + monthDay(o.started, cal)
            let secs = g.compactMap(\.seconds)
            let time = secs.isEmpty ? "" : runTime(secs.reduce(0, +) / Double(secs.count)) + (g.count > 1 ? " avg" : "")
            return RunGroup(newest: n, oldest: o, count: g.count, dates: dates, result: word + (g.count > 1 ? " ×\(g.count)" : ""),
                            line: line(n), time: time)
        }
    }

    /// The plain paragraph under 7c's name: what the loop does (its goal) and what is wrong, if anything.
    public static func loopParagraph(_ r: LoopRow, stopReason: String?, calendar cal: Calendar = .current) -> (does: String, wrong: String) {
        var does = r.goal.trimmingCharacters(in: .whitespacesAndNewlines)
        if let nl = does.firstIndex(of: "\n") { does = String(does[..<nl]) }
        if does.isEmpty { does = "No goal written for this loop." }
        if !does.hasSuffix(".") { does += "." }
        var wrong = ""
        switch r.state {
        case .failing:
            let n = max(1, failStreak(r))
            wrong = n > 1 ? "Its last \(n) runs failed." : "Its last run failed."
            if let s = stopReason, !s.isEmpty { wrong += " " + (s.hasSuffix(".") ? s : s + ".") }
        case .missed:
            wrong = "It is on but missed \(r.missed) scheduled run\(r.missed == 1 ? "" : "s")" + (r.firstMissed.map { " since " + monthDay($0, cal) } ?? "") + "."
        case .off: wrong = "It is off."
        case .trial: wrong = "It is in its trial: runs only say what they would do."
        default: break
        }
        return (does, wrong)
    }

    /// "Why it stopped": only when a rule stopped it (the same failure twice, or a limit).
    public static func whyStopped(_ stopReason: String?) -> String? {
        guard let s = stopReason?.lowercased(), !s.isEmpty else { return nil }
        if s.contains("same") { return "A loop stops when the same check fails the same way twice in a row. Trying again would only burn time. That is the stop rule working, not a crash." }
        if s.contains("round") || s.contains("limit") || s.contains("time") || s.contains("duration") {
            return "A loop stops at its limits (rounds or time) so a run can never go on without you. That is a limit working, not a crash."
        }
        return nil
    }

    /// What you can do on 7c, in order.
    public enum DoAction: Equatable, Sendable {
        case review(String)       // a Needs you item
        case reviewAll            // Needs you, this loop
        case runNow, pause, turnOn, setUp, open
    }

    public struct DoItem: Equatable, Sendable, Identifiable {
        public var id: String { title }
        public var title: String
        public var text: String
        public var action: DoAction
    }

    public static func whatYouCanDo(_ r: LoopRow, waiting: [LoopInbox.Item], needsSetup: Bool, engine: LoopEngine,
                                    calendar cal: Calendar = .current) -> [DoItem] {
        var out: [DoItem] = []
        if let q = waiting.first(where: { $0.kind == .asks }) {
            out.append(DoItem(title: "Answer the round's question", text: "The round is on hold until you answer.", action: .review(q.id)))
        }
        let commits = waiting.filter { $0.kind == .staged && ["commit", "pr"].contains($0.outcomeKind) }
        for c in commits.prefix(2) {
            let n = c.outcomes.count
            out.append(DoItem(title: c.outcomeKind == "pr" ? "Review the staged PR" : "Review the \(n) commit\(n == 1 ? "" : "s") from \(monthDay(c.when, cal))",
                              text: "One PR to its base branch after the gate passes; nothing is merged.", action: .review(c.id)))
        }
        let others = waiting.filter { $0.kind == .staged && !["commit", "pr"].contains($0.outcomeKind) }
        if !others.isEmpty {
            out.append(DoItem(title: "Decide \(outcomeWords(others))", text: "Approve or reject each; the loop reads it next run.", action: .reviewAll))
        }
        if needsSetup { out.append(DoItem(title: "Set it up", text: "It needs a setting or a tool before a run checks anything.", action: .setUp)) }
        switch r.state {
        case .missed: out.append(DoItem(title: "Run it now", text: "One run now, as its schedule would.", action: .runNow))
        case .failing:
            out.append(DoItem(title: "Run it again", text: "A new run, the check first.", action: .runNow))
            if engine == .oneRoof { out.append(DoItem(title: "Pause it", text: "Stops its scheduled runs; keeps its branch.", action: .pause)) }
        case .off where !needsSetup: out.append(DoItem(title: "Turn it on", text: "It starts with trial runs that only say what they would do.", action: .turnOn))
        default: break
        }
        return out
    }

    /// The Next run card: "Tonight 3:00" / "10:40" / "Fri 17:00", and one line on what can change it.
    public static func nextRunCard(_ r: LoopRow, maxRounds: Int?, maxHours: Double?, now: Date = Date(), calendar cal: Calendar = .current) -> (title: String, text: String) {
        guard r.on else { return ("Off", "No run is scheduled while it is off.") }
        guard let next = r.nextRun else { return (r.schedule == "manual" ? "When you start it" : r.schedule, "No scheduled time: it runs on Run now or its event.") }
        let h = cal.component(.hour, from: next)
        var title = when(next, now: now, calendar: cal)
        if cal.isDate(next, inSameDayAs: now) && h >= 18 { title = "Tonight " + clock(next, cal) }
        else if cal.isDate(next, inSameDayAs: now) { title = "Today " + clock(next, cal) }
        else if let d = cal.date(byAdding: .day, value: 1, to: now), cal.isDate(next, inSameDayAs: d) { title = (h < 6 ? "Tonight " : "Tomorrow ") + clock(next, cal) }
        var text = r.engine == .kit ? "The kit starts it on launchd" : "One Roof starts it"
        text += r.mode == .shadow ? ", as a trial run." : "."
        if let m = maxRounds, r.engine == .oneRoof {
            text += " Up to \(m) round\(m == 1 ? "" : "s")" + (maxHours.map { " or " + ($0 == $0.rounded() ? "\(Int($0)) h" : String(format: "%.1f h", $0)) } ?? "") + "."
        }
        return (title, text)
    }
}

// MARK: - 7d · Needs you

extension LoopsV7 {
    /// 7d's type tabs (All · Questions · Commits · Proposals · Reports · Missed · Failures).
    public enum NeedsType: String, CaseIterable, Equatable, Sendable {
        case all, questions, commits, proposals, reports, missed, failures
        public var label: String {
            switch self {
            case .all: return "All"
            case .questions: return "Questions"
            case .commits: return "Commits"
            case .proposals: return "Proposals"
            case .reports: return "Reports"
            case .missed: return "Missed"
            case .failures: return "Failures"
            }
        }
    }

    public static func needsType(_ i: LoopInbox.Item) -> NeedsType {
        switch i.kind {
        case .asks: return .questions
        case .failed: return .failures
        case .missed: return .missed
        case .staged:
            switch i.outcomeKind {
            case "commit", "pr": return .commits
            case "report", "slack": return .reports
            default: return .proposals   // proposal · issue · file · promotion: a yes or no
            }
        }
    }

    public static func needsCounts(_ items: [LoopInbox.Item]) -> [NeedsType: Int] {
        var c: [NeedsType: Int] = [.all: items.count]
        for i in items { c[needsType(i), default: 0] += 1 }
        return c
    }

    /// LP-5: a staged item older than 7 days is stale (it folds into Stale; expiring it is the owner's press, never automatic).
    public static let staleAfter: TimeInterval = 7 * 86400
    public static func isStale(_ i: LoopInbox.Item, now: Date = Date()) -> Bool {
        i.kind == .staged && i.when > .distantPast && now.timeIntervalSince(i.when) > staleAfter
    }

    /// Sort order: questions first (a round waits on them), then failures, commits, proposals, reports, missed; oldest first in a type.
    static func needsRank(_ t: NeedsType) -> Int {
        switch t { case .questions: return 0; case .failures: return 1; case .commits: return 2; case .proposals: return 3; case .reports: return 4; case .missed: return 5; case .all: return 6 }
    }

    /// The rows 7d shows: by type, kind, loop and search; fresh ones and the stale ones (folded) apart.
    public static func needsList(_ items: [LoopInbox.Item], type: NeedsType = .all, family: String? = nil, loop: String? = nil,
                                 query: String = "", rows: [LoopRow] = [], now: Date = Date()) -> (fresh: [LoopInbox.Item], stale: [LoopInbox.Item]) {
        let fam = Dictionary(rows.map { ($0.id, $0.family) }, uniquingKeysWith: { a, _ in a })
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        let shown = items.filter { i in
            if type != .all && needsType(i) != type { return false }
            if let loop, i.loopId != loop { return false }
            if let family, (fam[i.loopId] ?? "other") != family { return false }
            guard !q.isEmpty else { return true }
            let hay = ([i.loopTitle, i.loopId, i.headline, i.detail, needsTitle(i)] + i.outcomes.map(\.title)).joined(separator: " ").lowercased()
            return q.split(separator: " ").allSatisfy { hay.contains($0) }
        }
        .sorted { a, b in
            let (ra, rb) = (needsRank(needsType(a)), needsRank(needsType(b)))
            return ra != rb ? ra < rb : a.when < b.when
        }
        return (shown.filter { !isStale($0, now: now) }, shown.filter { isStale($0, now: now) })
    }

    /// A row's title in plain words.
    public static func needsTitle(_ i: LoopInbox.Item) -> String {
        switch i.kind {
        case .asks: return i.headline.contains("command") ? i.headline : "A round asks you something"
        case .failed: return "\(i.loopTitle) stopped at a limit"
        case .missed:
            return i.headline.replacingOccurrences(of: "Loop ", with: "")
        case .staged:
            let n = i.outcomes.count
            switch i.outcomeKind {
            case "commit": return "Review a PR of \(n) commit\(n == 1 ? "" : "s")"
            case "pr": return "Review a staged PR"
            case "report", "slack": return "Read a report"
            case "promotion": return "Let it go live?"
            case "issue": return "Accept or reject an issue"
            case "file": return "Apply a data or file update?"
            default: return "Accept or reject a proposal"
            }
        }
    }

    /// The from line: "Docs drift · skills list and MEMORY.md".
    public static func needsFrom(_ i: LoopInbox.Item) -> String {
        var detail: String
        switch i.kind {
        case .staged:
            detail = i.outcomes.first?.title ?? ""
            if i.outcomeKind == "commit", let b = i.outcomes.first?.detailValue("branch") { detail = b + " · " + detail }
        default: detail = i.detail
        }
        detail = detail.trimmingCharacters(in: .whitespacesAndNewlines)
        if let nl = detail.firstIndex(of: "\n") { detail = String(detail[..<nl]) }
        if detail.count > 90 { detail = String(detail.prefix(89)) + "…" }
        return detail.isEmpty ? i.loopTitle : i.loopTitle + " · " + detail
    }

    /// The row's dot: red for a failure, grey for missed runs, amber for anything you decide (questions included).
    public static func needsDot(_ i: LoopInbox.Item) -> LoopLook.Tone {
        switch i.kind { case .failed: return .failing; case .missed: return .off; default: return .needsYou }
    }

    /// "16 things wait for you. About 11 minutes." (the minutes are an estimate; the view says so).
    public static func needsHeadline(count n: Int, seconds: Int) -> String {
        guard n > 0 else { return "Nothing waits for you." }
        let mins = max(1, Int((Double(seconds) / 60).rounded()))
        return "\(n) thing\(n == 1 ? " waits" : "s wait") for you. About \(mins) minute\(mins == 1 ? "" : "s")."
    }

    /// By kind: per lane, the count and what it is ("5 · 1 question, 4 commits"); every kind is listed, 0 included.
    public static func needsByKind(_ items: [LoopInbox.Item], rows: [LoopRow]) -> [(family: String, count: Int, words: String)] {
        let fam = Dictionary(rows.map { ($0.id, $0.family) }, uniquingKeysWith: { a, _ in a })
        return laneOrder.map { fid in
            let its = items.filter { (fam[$0.loopId] ?? "other") == fid }
            var counts: [NeedsType: Int] = [:]
            var order: [NeedsType] = []
            for i in its { let t = needsType(i); if counts[t] == nil { order.append(t) }; counts[t, default: 0] += 1 }
            func noun(_ t: NeedsType, _ n: Int) -> String {
                let w: String
                switch t {
                case .questions: w = "question"; case .commits: w = "PR"; case .proposals: w = "proposal"
                case .reports: w = "report"; case .missed: w = "missed run"; case .failures: w = "failure"; case .all: w = "item"
                }
                return "\(n) \(w)\(n == 1 ? "" : "s")"
            }
            let words = order.map { noun($0, counts[$0]!) }.joined(separator: ", ")
            return (fid, its.count, words)
        }
    }
}

// MARK: - 7l · a round asks permission

extension LoopsV7 {
    /// How long ago (7d's rows, 7l's card).
    /// "2 min", "3 h", "1 day", "5 days".
    public static func age(_ d: Date, now: Date = Date()) -> String {
        guard d > .distantPast else { return "" }
        let m = max(0, Int(now.timeIntervalSince(d) / 60))
        if m < 60 { return "\(max(1, m)) min" }
        if m < 1440 { return "\(m / 60) h" }
        let days = m / 1440
        return "\(days) day\(days == 1 ? "" : "s")"
    }
}


/// The question card's content, from a loop's "asks" item, the loop and (when the engine read one) the round's open
/// permission prompt. Never invented: no prompt read means no command shown.
public struct LoopQuestion: Equatable, Sendable {
    public var itemId: String
    public var loopId: String
    public var loopTitle: String
    public var round: Int
    public var command: String?
    public var worktree: String
    public var branch: String
    /// The agent's own reason, when it gave one.
    public var reason: String?
    public var agent: AgentKind?
    public var askedAt: Date
    public var sessionId: String?

    public init(itemId: String, loopId: String, loopTitle: String, round: Int, command: String?, worktree: String, branch: String,
                reason: String?, agent: AgentKind?, askedAt: Date, sessionId: String?) {
        self.itemId = itemId; self.loopId = loopId; self.loopTitle = loopTitle; self.round = round; self.command = command
        self.worktree = worktree; self.branch = branch; self.reason = reason; self.agent = agent; self.askedAt = askedAt; self.sessionId = sessionId
    }

    /// "One Roof nightly bugs, round 3, wants to run a command it isn't allowed to run yet".
    public var title: String {
        let r = round > 0 ? ", round \(round)," : ""
        return command != nil ? "\(loopTitle)\(r) wants to run a command it isn't allowed to run yet" : "\(loopTitle)\(r) asks you something"
    }

    /// The Needs you row: "Round 3 asks to run a command".
    public var rowTitle: String {
        let who = round > 0 ? "Round \(round)" : "A round"
        return who + (command != nil ? " asks to run a command" : " asks you something")
    }

    /// The question for an item: the round number from the loop's active round (or the headline), the command and
    /// reason from the open prompt (its command, else read off its screen).
    public static func make(item: LoopInbox.Item, loop: Loop?, prompt: Decision?) -> LoopQuestion {
        var round = loop?.run?.active?.n ?? 0
        if round == 0, let m = item.headline.range(of: #"round (\d+)"#, options: .regularExpression) {
            round = Int(item.headline[m].split(separator: " ")[1]) ?? 0
        }
        let cmd = prompt?.command?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? prompt?.screen.flatMap(command(fromScreen:))
        let why = prompt.flatMap { $0.whyMissing ? nil : $0.why.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty }
        return LoopQuestion(itemId: item.id, loopId: item.loopId, loopTitle: item.loopTitle, round: round, command: cmd,
                            worktree: loop?.worktreePath ?? "", branch: loop?.branch ?? "", reason: why,
                            agent: prompt?.agent ?? loop?.agent, askedAt: prompt?.askedAt ?? item.when, sessionId: item.sessionId ?? prompt?.sessionId)
    }

    /// The command of a permission prompt as drawn ("Bash command" then the command, indented), or nil.
    public static func command(fromScreen lines: [String]) -> String? {
        let trimmed = lines.map { $0.trimmingCharacters(in: .whitespaces) }
        guard let h = trimmed.firstIndex(where: { $0.lowercased().hasPrefix("bash command") || $0.lowercased() == "shell command" || $0.lowercased().hasPrefix("run command") }) else { return nil }
        for l in trimmed[(h + 1)...] where !l.isEmpty {
            if l.lowercased().hasPrefix("do you want") || l.hasPrefix("❯") { return nil }
            return l
        }
        return nil
    }
}

/// LAB-2290 · "Always for this loop": an allow rule in the loop's own agent settings (its worktree's
/// `.claude/settings.local.json`, permissions.allow), written only for Claude and an exact command. Every other agent
/// keeps its rules elsewhere, so the button stays off with the reason.
public enum LoopAllowRule {
    /// `Bash(swift package resolve)`, or nil when this agent's allow list can't be written here.
    public static func rule(agent: AgentKind?, command: String?) -> String? {
        guard agent == .claude, let c = command?.trimmingCharacters(in: .whitespacesAndNewlines), !c.isEmpty,
              !c.contains("\n"), !c.contains(")") else { return nil }
        return "Bash(\(c))"
    }

    /// Why "Always for this loop" is off, or nil when it can be written.
    public static func unavailable(agent: AgentKind?, command: String?, worktree: String) -> String? {
        guard command?.isEmpty == false else { return "No command was read from the prompt; answer it in the round's terminal." }
        guard agent == .claude else { return "Only a Claude round's allow list (the loop worktree's .claude/settings.local.json) can be written from here." }
        guard rule(agent: agent, command: command) != nil else { return "This command can't be written as one exact allow rule." }
        guard !worktree.isEmpty else { return "The loop's worktree is not known." }
        return nil
    }

    public static func settingsPath(worktree: String) -> String { (worktree as NSString).appendingPathComponent(".claude/settings.local.json") }

    /// The settings file with the rule added to permissions.allow (other keys and rules kept; no duplicate).
    public static func merged(existing: Data?, adding rule: String) throws -> Data {
        var obj: [String: Any] = [:]
        if let d = existing, !d.isEmpty {
            guard let o = try JSONSerialization.jsonObject(with: d) as? [String: Any] else { throw LoopStoreError("the settings file is not a JSON object") }
            obj = o
        }
        var perms = obj["permissions"] as? [String: Any] ?? [:]
        var allow = perms["allow"] as? [String] ?? []
        if !allow.contains(rule) { allow.append(rule) }
        perms["allow"] = allow
        obj["permissions"] = perms
        return try JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys])
    }

    /// Write the rule into the worktree's settings (creates `.claude/` when needed). Blocking: call off the main thread.
    public static func write(rule: String, worktree: String) throws {
        let path = settingsPath(worktree: worktree)
        let fm = FileManager.default
        guard fm.fileExists(atPath: worktree) else { throw LoopStoreError("the worktree \(worktree) is not there") }
        try fm.createDirectory(atPath: (path as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
        let data = try merged(existing: fm.contents(atPath: path), adding: rule)
        try data.write(to: URL(fileURLWithPath: path), options: .atomic)
    }
}

extension String {
    fileprivate var nilIfEmpty: String? { isEmpty ? nil : self }
}
