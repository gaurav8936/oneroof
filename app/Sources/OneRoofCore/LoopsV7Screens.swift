import Foundation

// LAB-ONEROOF-v2.0.6 · Loops v7 (Claude Design handover), lane B: the pure logic behind 7e This week, 7f Today,
// 7g Tonight, 7j Runs and their rounds and 7k A run's report. Real numbers only: the views draw what these return.
//   LAB-2291  7e  week range and labels, the grid's cells for any week, the tiles and the "Is it worth it?" sentence
//   LAB-2292  7f  lanes on a 24 h axis (runs, missed, to come, a band for frequent loops), the headline, next up,
//                 while you slept · 7g tonight's list (loop runs from their schedules + scheduled sessions)
//   LAB-2293  7j  one runs feed for kit and roofd runs (ledger + rounds.jsonl), result filter, a run's steps
//                 7k  a report's findings, step tags, "if it had been live" and the one-line "what it means"

// MARK: - 7e · This week

extension LoopsV7 {
    /// The seven days of the week `offset` weeks back (0 = the seven days ending today): [start, end).
    public static func weekRange(offset: Int = 0, now: Date = Date(), calendar cal: Calendar = .current) -> (start: Date, end: Date) {
        let today = cal.startOfDay(for: now)
        let end = cal.date(byAdding: .day, value: 1 + 7 * min(0, offset), to: today)!
        return (cal.date(byAdding: .day, value: -7, to: end)!, end)
    }

    /// "Oct 31 – Nov 6" (the last day included).
    public static func weekLabel(start: Date, end: Date, calendar cal: Calendar = .current) -> String {
        let last = cal.date(byAdding: .day, value: -1, to: end) ?? end
        return monthDay(start, cal) + " – " + monthDay(last, cal)
    }

    /// A day column's head: "FRI 31".
    public static func dayHead(_ d: Date, calendar cal: Calendar = .current) -> String {
        weekday(d, cal).uppercased() + " \(cal.component(.day, from: d))"
    }

    /// LP-8 for any week: seven cells from `start` (runs, missed slots while the loop is on, still to come today).
    /// `runs` should reach back before `start` (missed slots count only after the loop's first run seen).
    public static func weekCells(row: LoopRow, runs: [LoopRun7], cron: CronSpec?, start: Date, now: Date = Date(), days: Int = 7,
                                 calendar cal: Calendar = .current) -> [DayCell] {
        let first = runs.map(\.started).min()
        return (0..<days).map { i in
            let d0 = cal.date(byAdding: .day, value: i, to: start)!, d1 = cal.date(byAdding: .day, value: 1, to: d0)!
            var c = DayCell(day: d0)
            for r in runs where r.started >= d0 && r.started < d1 {
                switch r.result { case .failed: c.failed += 1; case .trial: c.trial += 1; default: c.passed += 1 }
            }
            if row.on, let cr = cron, d0 < now {
                if let first {
                    let exp = cr.times(from: d0, to: min(d1, now.addingTimeInterval(-600)), calendar: cal).filter { $0 > first }
                    c.missed = missed(expected: exp, runs: runs).count
                }
                if d1 > now { c.toCome = cr.times(from: max(now, d0), to: d1, calendar: cal).count }
            }
            return c
        }
    }

    /// A day as a breadcrumb names it: "Wed Nov 4".
    public static func dayTitle(_ d: Date, calendar cal: Calendar = .current) -> String { weekday(d, cal) + " " + monthDay(d, cal) }

    /// The runs a cell shows as a number: everything that ran (passed, failed, trial).
    public static func ran(_ c: DayCell) -> Int { c.passed + c.failed + c.trial }

    /// The four tiles and the answer of 7e, for the loops the filter shows.
    public struct WeekSummary: Equatable, Sendable {
        public var runs = 0
        public var trialRuns = 0
        /// Trial runs of loops that are off (a dry run by hand, or a loop switched off since).
        public var offTrialRuns = 0
        public var failed = 0
        public var failedLoops = 0
        public var missed = 0
        public var missedLoops = 0
        public var cost = 0.0
        /// False when no run in the week recorded a cost (the tile then says "not recorded", never $0.00).
        public var costRecorded = false
        public var staged = 0
        /// IS IT WORTH IT? One sentence from these numbers only.
        public var answer = ""
        public init() {}
    }

    /// `rows`: the loops shown (filtered, on and off). `runs`: their runs in the week. `cells`: each on loop's cells.
    /// `staged`: outcomes of these loops still waiting for a decision.
    public static func weekSummary(rows: [LoopRow], runs: [LoopRun7], cells: [String: [DayCell]], staged: Int) -> WeekSummary {
        var s = WeekSummary()
        let byId = Dictionary(rows.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let mine = runs.filter { byId[$0.loop] != nil }
        s.runs = mine.count
        s.trialRuns = mine.filter { $0.result == .trial }.count
        s.offTrialRuns = mine.filter { $0.result == .trial && byId[$0.loop]?.on == false }.count
        let failed = mine.filter { $0.result == .failed }
        s.failed = failed.count
        s.failedLoops = Set(failed.map(\.loop)).count
        let costs = mine.compactMap(\.cost)
        s.costRecorded = !costs.isEmpty
        s.cost = costs.reduce(0, +)
        for (id, cs) in cells where byId[id] != nil {
            let m = cs.reduce(0) { $0 + $1.missed }
            s.missed += m
            if m > 0 { s.missedLoops += 1 }
        }
        s.staged = staged
        s.answer = worthIt(s, runs: mine, names: byId.mapValues(\.name))
        return s
    }

    /// "Mostly: 9 loops passed every live run; One Roof nightly bugs failed 6 of 7. 15 results still wait for you."
    static func worthIt(_ s: WeekSummary, runs: [LoopRun7], names: [String: String]) -> String {
        guard !runs.isEmpty else { return "Nothing to judge yet: no runs this week." }
        let live = runs.filter { $0.result != .trial }
        var out: String
        if live.isEmpty {
            out = "Too early to say: all \(runs.count) run\(runs.count == 1 ? " was a trial" : "s were trials"), so nothing acted yet."
        } else {
            let byLoop = Dictionary(grouping: live, by: \.loop)
            struct Bad { var id: String; var failed: Int; var n: Int }
            var bad: [Bad] = []
            for (id, rs) in byLoop {
                let f = rs.filter { $0.result == .failed }.count
                if f > 0 { bad.append(Bad(id: id, failed: f, n: rs.count)) }
            }
            bad.sort { a, b in
                if a.failed != b.failed { return a.failed > b.failed }
                return (names[a.id] ?? a.id) < (names[b.id] ?? b.id)
            }
            let clean = byLoop.count - bad.count
            if bad.isEmpty {
                out = "Yes so far: all \(live.count) live run\(live.count == 1 ? "" : "s") passed"
                out += s.missed > 0 ? ", but \(s.missed) scheduled run\(s.missed == 1 ? " was" : "s were") missed." : "."
            } else {
                let worst = bad[0]
                let who = (names[worst.id] ?? worst.id) + " failed \(worst.failed) of \(worst.n)"
                let more = bad.count > 1 ? " (and \(bad.count - 1) more loop\(bad.count == 2 ? "" : "s"))" : ""
                out = clean > 0
                    ? "Mostly: \(clean) loop\(clean == 1 ? "" : "s") passed every live run; \(who)\(more)."
                    : "Not yet: \(who)\(more)."
            }
        }
        if s.staged > 0 { out += " \(s.staged) result\(s.staged == 1 ? "" : "s") still wait\(s.staged == 1 ? "s" : "") for you." }
        return out
    }

    /// The grid's rows: loops that are on, by kind (Watch, Check, Improve, Report, Other), then name.
    public static func weekRows(_ rows: [LoopRow]) -> [LoopRow] {
        rows.filter(\.on).sorted { a, b in
            let ia = laneOrder.firstIndex(of: a.family) ?? laneOrder.count, ib = laneOrder.firstIndex(of: b.family) ?? laneOrder.count
            return ia != ib ? ia < ib : a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
        }
    }

    /// Each loop's runs in [from, to) from the ledger (paging back a week reads the weeks before the board's 8 days).
    public static func runsByLoop(_ ledger: LoopLedger?, from: Date, to: Date) -> [String: [LoopRun7]] {
        guard let ledger else { return [:] }
        return Dictionary(grouping: ledger.runs(from: from, to: to, limit: 40000).compactMap(LoopRun7.init), by: \.loop)
    }
}

// MARK: - 7f · Today (by the hour)

extension LoopsV7 {
    /// One dot on a lane: a run (with its id), a missed slot or a time still to come; a label beside failures,
    /// misses and a first trial.
    public struct DayMark: Equatable, Sendable, Identifiable {
        public var at: Date
        public var result: LoopRun7.Result
        public var runId: String?
        public var label: String?
        public var id: String { runId ?? "\(result.rawValue)-\(at.timeIntervalSince1970)" }
    }

    public struct DayLane: Equatable, Sendable, Identifiable {
        public var row: LoopRow
        public var marks: [DayMark]
        /// "every 10 min →" for a loop that runs more often than hourly: drawn as a band from `bandFrom`, not as dots.
        public var band: String?
        public var bandFrom: Date?
        public var id: String { row.id }
    }

    /// 7g → 7f: scheduled sessions in [start, end) as one more lane of hollow dots ("Scheduled sessions"), nil when none.
    public static func sessionLane(_ sessions: [TonightSession], start: Date, end: Date, calendar cal: Calendar = .current) -> DayLane? {
        let marks = sessions.filter { $0.at >= start && $0.at < end }.sorted { $0.at < $1.at }
            .map { DayMark(at: $0.at, result: .toCome, runId: nil, label: clock($0.at, cal) + " " + $0.name) }
        guard !marks.isEmpty else { return nil }
        let row = LoopRow(id: "scheduled-sessions", name: "Scheduled sessions", family: LoopKinds.otherFamily.id, kind: nil, mine: true,
                          engine: .oneRoof, on: true, mode: .live, state: .fine, schedule: "one-off", goal: "", lastRun: nil, nextRun: marks.first?.at,
                          strip: [], missed: 0, firstMissed: nil)
        return DayLane(row: row, marks: marks, band: nil, bandFrom: nil)
    }

    /// True for a schedule that runs more often than once an hour.
    public static func isFrequent(_ c: CronSpec?) -> Bool {
        guard let c else { return false }
        return c.minutes.count > 1 && c.hours.count >= 12
    }

    /// The lanes of 7f over [start, end): one per loop that is on (plus any loop that ran in the window), frequent loops
    /// first, then by their first mark.
    public static func dayLanes(rows: [LoopRow], runs: [String: [LoopRun7]], crons: [String: CronSpec], start: Date, end: Date,
                                now: Date = Date(), calendar cal: Calendar = .current) -> [DayLane] {
        var lanes: [DayLane] = []
        for r in rows {
            let all = (runs[r.id] ?? []).sorted { $0.started < $1.started }
            let inWin = all.filter { $0.started >= start && $0.started < end }
            guard r.on || !inWin.isEmpty else { continue }
            var marks = inWin.map { run -> DayMark in
                var label: String?
                if run.result == .failed { label = "failed" + (shortSummary(run.summary, row: r).map { " · " + $0 } ?? "") }
                return DayMark(at: run.started, result: run.result, runId: run.id, label: label)
            }
            let cron = r.on ? crons[r.id] : nil
            let frequent = isFrequent(cron)
            if let c = cron, let first = all.first?.started {
                let exp = c.times(from: max(start, first.addingTimeInterval(60)), to: min(end, now.addingTimeInterval(-600)), calendar: cal)
                let miss = missed(expected: exp, runs: all)
                marks += miss.map { DayMark(at: $0, result: .missed, runId: nil, label: frequent ? nil : "missed " + clock($0, cal)) }
            }
            var band: String?, bandFrom: Date?
            if let c = cron, end > now {
                if frequent {
                    band = LoopSchedule.words(c) + " →"; bandFrom = max(now, start)
                } else {
                    let next = c.times(from: max(now, start), to: end, calendar: cal)
                    for (i, t) in next.enumerated() {
                        var label: String?
                        if i == 0, all.isEmpty { label = clock(t, cal) + (r.mode == .shadow ? " first trial" : "") }
                        marks.append(DayMark(at: t, result: .toCome, runId: nil, label: label))
                    }
                }
            }
            marks.sort { $0.at < $1.at }
            lanes.append(DayLane(row: r, marks: marks, band: band, bandFrom: bandFrom))
        }
        return lanes.sorted { a, b in
            if (a.band != nil) != (b.band != nil) { return a.band != nil }
            let fa = a.marks.first?.at ?? .distantFuture, fb = b.marks.first?.at ?? .distantFuture
            return fa != fb ? fa < fb : a.row.name.localizedCaseInsensitiveCompare(b.row.name) == .orderedAscending
        }
    }

    /// A run's summary without the loop's name, in a few words ("4 findings", "same failure twice").
    static func shortSummary(_ summary: String, row: LoopRow) -> String? {
        var r = row
        r.lastRun = LoopRun7(id: "", loop: row.id, engine: row.engine, started: Date(), ended: nil, result: .failed, cost: nil, summary: summary)
        r.state = .failing; r.missed = 0
        let s = subLine(r)
        guard !s.isEmpty, s != "last run failed" else { return nil }
        if s.hasPrefix("The same failure twice") { return "same failure twice" }
        return s.count > 48 ? String(s.prefix(46)) + "…" : s
    }

    /// 7f's head: the bold part and the rest. Today: "Overnight: 9 loops ran, 2 failed, 1 missed." + "Since 8:00: 34
    /// runs from 3 loops." Another day: "Wed Nov 4: 40 runs from 9 loops, 2 failed." The last 24 h: the same over 24 h.
    public static func dayHeadline(lanes: [DayLane], start: Date, end: Date, now: Date = Date(), last24h: Bool = false,
                                   calendar cal: Calendar = .current) -> (lead: String, bold: String, rest: String) {
        func tally(_ from: Date, _ to: Date) -> (loops: Int, runs: Int, failed: Int, missed: Int) {
            var loops = 0, runs = 0, failed = 0, missed = 0
            for l in lanes {
                let m = l.marks.filter { $0.at >= from && $0.at < to }
                let ran = m.filter { $0.runId != nil }
                if !ran.isEmpty { loops += 1 }
                runs += ran.count
                failed += ran.filter { $0.result == .failed }.count
                missed += m.filter { $0.result == .missed }.count
            }
            return (loops, runs, failed, missed)
        }
        func words(_ t: (loops: Int, runs: Int, failed: Int, missed: Int)) -> String {
            var p = ["\(t.loops) loop\(t.loops == 1 ? "" : "s") ran"]
            if t.failed > 0 { p.append("\(t.failed) failed") }
            if t.missed > 0 { p.append("\(t.missed) missed") }
            return p.joined(separator: ", ")
        }
        let longDay = fullWeekday(start, cal) + " " + monthDay(start, cal)
        if last24h {
            let t = tally(start, end)
            return ("The last 24 hours.", words(t) + ".", " \(t.runs) run\(t.runs == 1 ? "" : "s") in all.")
        }
        let isToday = cal.isDate(start, inSameDayAs: now)
        guard isToday else {
            let t = tally(start, end)
            return (longDay + ".", words(t) + ".", " \(t.runs) run\(t.runs == 1 ? "" : "s") in all.")
        }
        let eight = cal.date(bySettingHour: 8, minute: 0, second: 0, of: start)!
        let night = tally(start, eight)
        var rest = ""
        if now > eight {
            let since = lanes.compactMap { l -> (String, Int)? in
                let n = l.marks.filter { $0.at >= eight && $0.at < now && $0.runId != nil }.count
                return n > 0 ? (l.row.name, n) : nil
            }.sorted { $0.1 > $1.1 }
            let total = since.reduce(0) { $0 + $1.1 }
            rest = total == 0 ? " Nothing has run since 8:00."
                : " Since 8:00: \(total) run\(total == 1 ? "" : "s") from " + (since.count <= 2 ? since.map(\.0).joined(separator: " and ") : "\(since.count) loops") + "."
        }
        return (longDay + ".", "Overnight: " + words(night) + ".", rest)
    }

    static func fullWeekday(_ d: Date, _ cal: Calendar) -> String {
        ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"][(cal.component(.weekday, from: d) - 1) % 7]
    }

    /// NEXT UP: each loop's next run (one per loop), soonest first.
    public struct Departure: Equatable, Sendable, Identifiable {
        public var loop: String
        public var name: String
        public var at: Date
        public var engine: LoopEngine
        /// "in 5 min", "in 1 h 25", "today", "tomorrow", or "trial" for a loop in trial.
        public var tag: String
        public var trial: Bool
        public var id: String { loop }
    }

    public static func departures(rows: [LoopRow], crons: [String: CronSpec], now: Date = Date(), limit: Int = 5,
                                  calendar cal: Calendar = .current) -> [Departure] {
        rows.filter(\.on).compactMap { r -> Departure? in
            guard let c = crons[r.id], let at = c.times(from: now, to: now.addingTimeInterval(8 * 86400), calendar: cal).first else { return nil }
            return Departure(loop: r.id, name: r.name, at: at, engine: r.engine, tag: r.mode == .shadow ? "trial" : timeToGo(at, now: now, calendar: cal),
                             trial: r.mode == .shadow)
        }
        .sorted { $0.at != $1.at ? $0.at < $1.at : $0.name < $1.name }
        .prefix(limit).map { $0 }
    }

    /// "in 5 min", "in 1 h 25", "in 2 h" (under 3 h), else "today" / "tomorrow" / the weekday.
    public static func timeToGo(_ at: Date, now: Date = Date(), calendar cal: Calendar = .current) -> String {
        let m = Int((at.timeIntervalSince(now) / 60).rounded(.up))
        if m < 60 { return "in \(max(1, m)) min" }
        if m < 180 { return "in \(m / 60) h" + (m % 60 == 0 ? "" : " \(m % 60)") }
        let days = cal.dateComponents([.day], from: cal.startOfDay(for: now), to: cal.startOfDay(for: at)).day ?? 0
        return days == 0 ? "today" : days == 1 ? "tomorrow" : weekday(at, cal)
    }

    /// WHILE YOU SLEPT: overnight failures and misses, one item per loop, worst first.
    public struct SleptItem: Equatable, Sendable, Identifiable {
        public enum Kind: String, Equatable, Sendable { case failed, missed }
        public var loop: String
        public var name: String
        public var kind: Kind
        public var line: String
        /// The failed run, for Open.
        public var runId: String?
        public var id: String { loop + "-" + kind.rawValue }
    }

    /// Over [from, to) (the night): from the lanes' marks. The span of the night's marks is returned for the title.
    public static func whileYouSlept(lanes: [DayLane], from: Date, to: Date, calendar cal: Calendar = .current)
        -> (items: [SleptItem], span: (Date, Date)?) {
        var items: [SleptItem] = []
        var times: [Date] = []
        for l in lanes {
            let m = l.marks.filter { $0.at >= from && $0.at < to && $0.result != .toCome }
            times += m.filter { $0.runId != nil || $0.result == .missed }.map(\.at)
            if let f = m.last(where: { $0.result == .failed }) {
                let streak = failStreak(l.row)
                var line = f.label.map { $0.replacingOccurrences(of: "failed · ", with: "") } ?? "the run failed"
                if line == "failed" { line = "the run failed" }
                if streak > 1 { line = "\(streak) failed runs in a row: " + line }
                items.append(SleptItem(loop: l.row.id, name: l.row.name, kind: .failed, line: line, runId: f.runId))
            } else if let miss = m.first(where: { $0.result == .missed }) {
                let since = l.row.lastRun.map { "no run since " + monthDay($0.started, cal) } ?? "no run yet"
                items.append(SleptItem(loop: l.row.id, name: l.row.name, kind: .missed,
                                       line: "missed \(clock(miss.at, cal)) · on, but " + since, runId: nil))
            }
        }
        items.sort { $0.kind != $1.kind ? $0.kind == .failed : $0.name < $1.name }
        let span = times.isEmpty ? nil : (times.min()!, times.max()!)
        return (items, span)
    }
}

// MARK: - 7g · Tonight

extension LoopsV7 {
    public struct TonightItem: Equatable, Sendable, Identifiable {
        public enum Tag: String, Equatable, Sendable { case trial, failing, oneOff, nightlySession }
        public var id: String
        public var at: Date
        public var name: String
        public var line: String
        /// "by kit" / "by One Roof".
        public var by: String
        public var tag: Tag?
        /// The dot: the loop's state (fine, failing, trial), or running blue for a session.
        public var dot: LoopRow.State
        public var isSession: Bool
        public var loops: [String]
        public init(id: String, at: Date, name: String, line: String, by: String, tag: Tag?, dot: LoopRow.State, isSession: Bool, loops: [String] = []) {
            self.id = id; self.at = at; self.name = name; self.line = line; self.by = by; self.tag = tag; self.dot = dot
            self.isSession = isSession; self.loops = loops
        }
    }

    /// A scheduled session as Tonight lists it.
    public struct TonightSession: Equatable, Sendable {
        public var id: String, name: String, line: String, at: Date, nightly: Bool
        public init(id: String, name: String, line: String, at: Date, nightly: Bool) {
            self.id = id; self.name = name; self.line = line; self.at = at; self.nightly = nightly
        }
    }

    /// Tonight: from 18:00 (or now, if later) to 8:00 the next morning; before 8:00, from now to 8:00 today.
    public static func tonightWindow(now: Date = Date(), calendar cal: Calendar = .current) -> (start: Date, end: Date) {
        let today = cal.startOfDay(for: now)
        let eight = cal.date(bySettingHour: 8, minute: 0, second: 0, of: today)!
        if now < eight { return (now, eight) }
        let six = cal.date(bySettingHour: 18, minute: 0, second: 0, of: today)!
        return (max(now, six), cal.date(byAdding: .day, value: 1, to: eight)!)
    }

    /// The list in time order (loops from their schedules, scheduled sessions) and the loops that run more than once
    /// tonight ("Cost watch (hourly)"), which are not listed one by one.
    public static func tonight(rows: [LoopRow], crons: [String: CronSpec], sessions: [TonightSession], now: Date = Date(),
                               calendar cal: Calendar = .current) -> (items: [TonightItem], frequent: [String]) {
        let (start, end) = tonightWindow(now: now, calendar: cal)
        var items: [TonightItem] = []
        var frequent: [String] = []
        for r in rows where r.on {
            guard let c = crons[r.id] else { continue }
            let times = c.times(from: start, to: end, calendar: cal)
            guard !times.isEmpty else { continue }
            // More than once a night (every few minutes, hourly, every 4 h): one line under the list, not a row per run.
            if isFrequent(c) || times.count > 1 { frequent.append(r.name + " (" + LoopSchedule.words(c) + ")"); continue }
            let streak = failStreak(r)
            let tag: TonightItem.Tag? = r.state == .failing ? .failing : r.mode == .shadow ? .trial : nil
            var line = LoopSchedule.words(c)
            if tag == .failing { line = streak > 1 ? "failed the last \(streak) runs" : "failed its last run" }
            else if tag == .trial { line = "trial · it only writes what it would do" + (r.missed > 0 ? " · missed \(r.missed)" : "") }
            for t in times {
                items.append(TonightItem(id: r.id + "-\(t.timeIntervalSince1970)", at: t, name: r.name, line: line,
                                         by: r.engine == .kit ? "by kit" : "by One Roof", tag: tag,
                                         dot: tag == .failing ? .failing : tag == .trial ? .trial : .fine, isSession: false, loops: [r.id]))
            }
        }
        // Loops at the same time with nothing to flag share a row ("Morning health check · GitHub stats").
        var merged: [TonightItem] = []
        for i in items.sorted(by: { $0.at != $1.at ? $0.at < $1.at : $0.name < $1.name }) {
            if i.tag == nil, let j = merged.lastIndex(where: { $0.at == i.at && $0.tag == nil && !$0.isSession && $0.by == i.by }) {
                merged[j].name += " · " + i.name
                merged[j].loops += i.loops
                if merged[j].line != i.line { merged[j].line = "nightly" }
            } else { merged.append(i) }
        }
        for s in sessions where s.at >= start && s.at < end {
            merged.append(TonightItem(id: "session-" + s.id, at: s.at, name: "Session · " + s.name, line: s.line, by: "by One Roof",
                                      tag: s.nightly ? .nightlySession : .oneOff, dot: .running, isSession: true))
        }
        merged.sort { $0.at != $1.at ? $0.at < $1.at : ($0.isSession ? 1 : 0) > ($1.isSession ? 1 : 0) }
        return (merged, frequent.sorted())
    }

    /// "9 things run tonight, from 1:00 to 7:30." (the rest of the sentence is fixed copy).
    public static func tonightHeadline(_ items: [TonightItem], calendar cal: Calendar = .current) -> String {
        guard let a = items.first?.at, let b = items.last?.at else { return "Nothing is scheduled tonight." }
        let n = items.reduce(0) { $0 + max(1, $1.loops.count) }
        let span = a == b ? "at " + clock(a, cal) : "from " + clock(a, cal) + " to " + clock(b, cal)
        return "\(n) thing\(n == 1 ? " runs" : "s run") tonight, \(span)."
    }
}

// MARK: - 7j · Runs and their rounds

extension LoopsV7 {
    public struct FeedRun: Equatable, Sendable, Identifiable {
        public enum Result: String, CaseIterable, Equatable, Sendable { case running, passed, done, failed, stopped, missed, trial }
        public var id: String
        public var loop: String
        public var name: String
        public var family: String
        public var engine: LoopEngine
        public var started: Date
        public var ended: Date?
        public var result: Result
        /// roofd: rounds this run took (0 = the check passed first); nil for a kit run (it has no rounds).
        public var rounds: Int?
        public var summary: String
        public var journalRef: String
        /// roofd's run id inside rounds.jsonl (`roofd-<loop>-<runId>` in the ledger).
        public var roofdRunId: String?
        public var seconds: TimeInterval? { ended.map { $0.timeIntervalSince(started) } }
    }

    /// The runs filter's result chips (7j): Any · Running · Failed or stopped · Missed · Trial.
    public enum FeedFilter: String, CaseIterable, Equatable, Sendable {
        case any, running, failedOrStopped, missed, trial
        public var label: String {
            switch self {
            case .any: return "Any result"
            case .running: return "Running"
            case .failedOrStopped: return "Failed or stopped"
            case .missed: return "Missed"
            case .trial: return "Trial"
            }
        }
        public func matches(_ r: FeedRun.Result) -> Bool {
            switch self {
            case .any: return true
            case .running: return r == .running
            case .failedOrStopped: return r == .failed || r == .stopped
            case .missed: return r == .missed
            case .trial: return r == .trial
            }
        }
    }

    /// The roofd run id of a ledger row (`roofd-<loop>-<runId>`), nil for a kit run.
    public static func roofdRunId(_ ledgerId: String, loop: String) -> String? {
        let p = "roofd-" + loop + "-"
        return ledgerId.hasPrefix(p) ? String(ledgerId.dropFirst(p.count)) : nil
    }

    /// One feed for both engines over [from, now]: the ledger's runs (kit and roofd), roofd runs still going (from
    /// rounds.jsonl and the loop's current run), and missed slots of loops that are on. Newest first.
    public static func runsFeed(runs: [LoopRun7], rounds: [String: [LoopRound]], rows: [LoopRow], crons: [String: CronSpec],
                                current: [String: (id: String, started: Date)] = [:], from: Date, now: Date = Date(),
                                calendar cal: Calendar = .current) -> [FeedRun] {
        let byId = Dictionary(rows.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        var out: [FeedRun] = []
        var seen = Set<String>()
        for r in runs where r.started >= from && r.started <= now {
            let row = byId[r.loop]
            let rid = roofdRunId(r.id, loop: r.loop)
            if let rid { seen.insert(r.loop + "\u{1}" + rid) }
            let lines = rid.map { id in (rounds[r.loop] ?? []).filter { $0.runId == id } } ?? []
            let res: FeedRun.Result
            switch r.result {
            case .trial: res = .trial
            case .failed: res = rid != nil && stoppedByLimit(r.summary) ? .stopped : .failed
            default: res = rid != nil ? .done : .passed
            }
            out.append(FeedRun(id: r.id, loop: r.loop, name: row?.name ?? r.loop, family: row?.family ?? LoopKinds.otherFamily.id,
                               engine: r.engine, started: r.started, ended: r.ended, result: res,
                               rounds: rid != nil ? lines.filter { $0.kind == .round }.count : nil, summary: r.summary,
                               journalRef: r.journalRef, roofdRunId: rid))
        }
        // roofd runs going now: the loop's current run, with what rounds.jsonl has of it so far.
        for (loop, run) in current where !seen.contains(loop + "\u{1}" + run.id) {
            let lines = (rounds[loop] ?? []).filter { $0.runId == run.id }
            guard !lines.contains(where: { $0.kind == .stop }) else { continue }
            let row = byId[loop]
            out.append(FeedRun(id: "roofd-\(loop)-\(run.id)", loop: loop, name: row?.name ?? loop, family: row?.family ?? LoopKinds.otherFamily.id,
                               engine: .oneRoof, started: run.started, ended: nil, result: .running,
                               rounds: lines.filter { $0.kind == .round }.count, summary: "", journalRef: "\(loop)/rounds.jsonl", roofdRunId: run.id))
        }
        // Missed slots (loops that are on, after their first run seen), as rows says.
        for r in rows where r.on {
            guard let c = crons[r.id] else { continue }
            let mine = runs.filter { $0.loop == r.id }
            guard let first = mine.map(\.started).min() else { continue }
            let exp = c.times(from: max(from, first.addingTimeInterval(60)), to: now.addingTimeInterval(-600), calendar: cal)
            for t in missed(expected: exp, runs: mine) {
                out.append(FeedRun(id: "missed-\(r.id)-\(Int(t.timeIntervalSince1970))", loop: r.id, name: r.name, family: r.family,
                                   engine: r.engine, started: t, ended: nil, result: .missed, rounds: nil,
                                   summary: "On, but no run was recorded for this slot", journalRef: "", roofdRunId: nil))
            }
        }
        return out.sorted { $0.started != $1.started ? $0.started > $1.started : $0.id < $1.id }
    }

    /// roofd's words for a run a limit or the same-failure rule stopped (not a plain failure).
    static func stoppedByLimit(_ summary: String) -> Bool {
        let s = summary.lowercased()
        return ["same failure", "limit", "stopped", "max rounds", "rounds reached", "time is up"].contains { s.contains($0) }
    }

    /// The feed filtered by the bar (search, kind) and the result chip.
    public static func filterFeed(_ feed: [FeedRun], rows: [LoopRow], filter f: LoopFilter, result: FeedFilter) -> [FeedRun] {
        let keep = Set(LoopsV7.filter(rows, LoopFilter(query: f.query, family: f.family, state: nil)).map(\.id))
        let unknownOK = f.query.trimmingCharacters(in: .whitespaces).isEmpty && f.family == nil
        let known = Set(rows.map(\.id))
        return feed.filter { run in (keep.contains(run.loop) || (unknownOK && !known.contains(run.loop))) && result.matches(run.result) }
    }

    /// The head's counts: "1 running · 26 rounds this week · 209 runs".
    public static func feedCounts(_ feed: [FeedRun], rounds: [String: [LoopRound]], now: Date = Date()) -> String {
        let running = feed.filter { $0.result == .running }.count
        let from = now.addingTimeInterval(-7 * 86400)
        let r = rounds.values.joined().filter { $0.kind == .round && $0.started >= from }.count
        let runs = feed.filter { $0.result != .missed && $0.result != .running }.count
        return "\(running) running · \(r) round\(r == 1 ? "" : "s") this week · \(runs) run\(runs == 1 ? "" : "s")"
    }

    /// A row's second line: "Nov 6 · 3:00 → 3:14 · 2 rounds · by One Roof", "today · 6:00 · 7 s · by kit".
    public static func feedLine(_ r: FeedRun, now: Date = Date(), calendar cal: Calendar = .current) -> String {
        let days = cal.dateComponents([.day], from: cal.startOfDay(for: r.started), to: cal.startOfDay(for: now)).day ?? 0
        var parts = [r.result == .running ? "now" : days == 0 ? "today" : days == 1 ? "yest." : monthDay(r.started, cal)]
        var when = clock(r.started, cal)
        if let e = r.ended, e.timeIntervalSince(r.started) >= 60 { when += " → " + clock(e, cal) }
        parts.append(when)
        if r.result == .missed { parts.append("no run") }
        else if let n = r.rounds { parts.append(n == 0 ? "check only" : "\(n) round\(n == 1 ? "" : "s")") }
        else if let s = r.seconds { parts.append(duration(s)) }
        parts.append(r.engine == .kit ? "by kit" : "by One Roof")
        return parts.joined(separator: " · ")
    }

    /// "0.2 s", "7 s", "4 min", "1 h 12 min".
    public static func duration(_ s: TimeInterval) -> String {
        if s < 1 { return String(format: "%.1f s", max(0, s)) }
        if s < 60 { return "\(Int(s.rounded())) s" }
        let m = Int((s / 60).rounded())
        return m < 60 ? "\(m) min" : "\(m / 60) h" + (m % 60 == 0 ? "" : " \(m % 60) min")
    }

    /// One step of a run as 7j lists it.
    public struct RunStep: Equatable, Sendable, Identifiable {
        public enum Tone: String, Equatable, Sendable { case normal, pass, fail, running, trial }
        public var id: Int
        public var at: Date?
        public var title: String
        public var line: String
        public var code: String?
        public var sessionId: String?
        public var agent: AgentKind?
        public var tone: Tone
    }

    /// A run's steps: started (by whom), then roofd's check and rounds from rounds.jsonl, or a kit run's report steps,
    /// then how it ended. `schedule`: the loop's schedule words; `check`: its check command (shown while running).
    public static func runSteps(_ r: FeedRun, rounds: [LoopRound], report: LoopReport?, schedule: String, check: String = "",
                                calendar cal: Calendar = .current) -> [RunStep] {
        var out: [RunStep] = []
        func add(_ at: Date?, _ title: String, _ line: String, code: String? = nil, session: String? = nil, agent: AgentKind? = nil, _ tone: RunStep.Tone = .normal) {
            out.append(RunStep(id: out.count, at: at, title: title, line: line, code: code, sessionId: session, agent: agent, tone: tone))
        }
        if r.result == .missed {
            add(r.started, "Expected on schedule", "The schedule (\(schedule)) expected a run here; none was recorded.", .fail)
            return out
        }
        let trigger = report?.steps.first { $0.step == "trigger" }?.what ?? ""
        let byHand = trigger.hasPrefix("by hand")
        let who = r.engine == .kit ? "The kit (launchd) started it" : "roofd started it"
        add(r.started, byHand ? "Started by hand" : "Started on schedule", who + (schedule == "manual" ? "." : ": \(schedule)."))
        if r.engine == .oneRoof {
            let lines = rounds.filter { $0.runId == r.roofdRunId }.sorted { $0.started < $1.started }
            for l in lines {
                switch l.kind {
                case .check:
                    let ok = l.checkPassed ?? false
                    add(l.started, l.n == 0 ? "Check before work" : "Check after round \(l.n)",
                        (ok ? "Passed" : "Failed") + (l.exitCode.map { " (exit \($0))" } ?? "") + " · " + duration(l.ended.timeIntervalSince(l.started)),
                        code: lastLine(l.checkOutput), ok ? .pass : .fail)
                case .round:
                    let ok = l.checkPassed
                    add(l.started, "Round \(l.n)" + (l.agent.map { " · " + $0.rawValue.capitalized } ?? ""),
                        duration(l.ended.timeIntervalSince(l.started)) + (ok == nil ? "" : ok! ? " · check passed after it" : " · check still failing")
                        + (l.note.map { " · " + $0 } ?? ""),
                        session: l.sessionId, agent: l.agent, ok == true ? .pass : ok == false ? .fail : .normal)
                case .stop:
                    add(l.ended, r.result == .done ? "Done" : "Stopped", l.note ?? r.summary, r.result == .done ? .pass : .fail)
                }
            }
            if r.result == .running {
                add(nil, lines.isEmpty ? "Check running" : "Running", lines.isEmpty ? "The check runs first; a round starts only if it fails." : "Round \(lines.filter { $0.kind == .round }.count + 1) or the check is running.",
                    code: check.isEmpty ? nil : check, .running)
            } else if !lines.contains(where: { $0.kind == .stop }) {
                add(r.ended, r.result == .done ? "Done" : r.result == .stopped ? "Stopped" : "Failed", r.summary.isEmpty ? "No stop line in rounds.jsonl for this run." : r.summary,
                    r.result == .done ? .pass : .fail)
            }
            return out
        }
        if let rep = report {
            for s in rep.steps where s.step != "trigger" && s.step != "inputs" && s.step != "cost" {
                let at = Double(s.t.replacingOccurrences(of: "s", with: "")).map { r.started.addingTimeInterval($0) }
                let tone: RunStep.Tone
                switch reportTag(s) {
                case "pass": tone = .pass
                case "fail": tone = .fail
                case "shadow": tone = .trial
                default: tone = .normal
                }
                add(at, s.step.prefix(1).uppercased() + s.step.dropFirst(), s.what, tone)
            }
        } else {
            add(r.ended, r.result == .failed ? "Failed" : r.result == .trial ? "Trial run ended" : "Passed",
                (r.summary.isEmpty ? "No report written for this run." : r.summary) + (r.seconds.map { " · " + duration($0) } ?? ""),
                r.result == .failed ? .fail : r.result == .trial ? .trial : .pass)
        }
        return out
    }

    static func lastLine(_ s: String) -> String? {
        let l = s.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.last { !$0.isEmpty }
        return l.map { $0.count > 140 ? String($0.prefix(138)) + "…" : $0 }
    }

    /// The one-line explanation 7j shows under a run's title.
    public static func runSentence(_ r: FeedRun, family: String) -> String {
        let kind = LoopKinds.family(family)?.title ?? "A"
        switch r.result {
        case .running: return r.engine == .kit ? "A \(kind) loop run by the kit: it is running now." : "A \(kind) loop run by One Roof: it is running now (the check first; rounds only when it fails)."
        case .missed: return "The loop is on, but the run its schedule expected did not happen."
        case .trial: return "A trial run: it only wrote what it would have done; nothing acted."
        case .done: return (r.rounds ?? 0) == 0 ? "The check already passed: no round was needed." : "Done after \(r.rounds!) round\(r.rounds == 1 ? "" : "s"): the check passes."
        case .stopped: return "Stopped by a limit: " + (r.summary.isEmpty ? "see the steps." : r.summary)
        case .failed, .passed: return r.summary.isEmpty ? (r.result == .failed ? "The run failed." : "The run passed.") : r.summary
        }
    }
}

// MARK: - 7k · A run's report

extension LoopReport {
    /// A finding line "- [medium] text → p-859b": its severity, text and where it went.
    public struct Finding: Equatable, Sendable {
        public var severity: String
        public var text: String
        public var outcome: String
    }

    public var parsedFindings: [Finding] {
        findings.map { f in
            var s = f, sev = "info", out = ""
            if s.hasPrefix("["), let e = s.firstIndex(of: "]") {
                sev = String(s[s.index(after: s.startIndex)..<e]); s = String(s[s.index(after: e)...]).trimmingCharacters(in: .whitespaces)
            }
            if let a = s.range(of: " → ", options: .backwards) { out = String(s[a.upperBound...]); s = String(s[..<a.lowerBound]) }
            return Finding(severity: sev, text: s, outcome: out)
        }
    }

    /// The run's result word from the head ("pass", "fail", "dry"), else from its steps.
    public var resultWord: String {
        if let r = meta["Result"], !r.isEmpty { return r.lowercased() }
        let c = result.lowercased()
        return c.hasPrefix("pass") ? "pass" : c.hasPrefix("fail") ? "fail" : c
    }

    public var isTrial: Bool { resultWord == "dry" || resultWord == "shadow" || title.lowercased().contains("dry run") }

    /// The total time: the last step's t ("0.19 s").
    public var totalTime: String {
        guard let t = steps.last?.t, let v = Double(t.replacingOccurrences(of: "s", with: "")) else { return "" }
        return LoopsV7.duration(v)
    }

    /// IF IT HAD BEEN LIVE: what a trial run says it would have done or sent (its "would do" and "would send" lines).
    public var ifLive: [String] {
        steps.filter { $0.step == "would do" || $0.what.hasPrefix("would send") || $0.step == "shadow" }.map { s in
            s.what.replacingOccurrences(of: "would send ", with: "Would send ")
        }
    }

    /// WHAT IT MEANS: one sentence and why, from the result, the stop line and the findings only.
    public var meaning: (headline: String, why: String) {
        let fs = parsedFindings
        let notable = fs.filter { $0.severity != "info" }
        let stop = steps.last { $0.step == "stop" }?.what ?? ""
        let setup = fs.first { f in
            let t = f.text.lowercased()
            return t.contains("not configured") || t.contains("no commands configured") || t.contains("nothing configured") || t.contains("not set")
        }
        let timeout = steps.first { $0.step == "agent" && $0.what.contains("timeout") }
        if let s = setup {
            return ("It ran, but it couldn't check anything: it is not set up yet.",
                    "The check passed because there was nothing to compare: " + s.text + ". Until that is set, every run will look like this.")
        }
        switch resultWord {
        case "fail", "failed", "error":
            let n = steps.filter { $0.step == "check" }.count
            var head = n > 1 ? "It failed: the check still failed after \(n) tries." : "It failed: the check did not pass."
            if let t = timeout {
                let after = t.what.range(of: #"timeout after \d+s"#, options: .regularExpression).map { " (" + String(t.what[$0]) + ")" } ?? ""
                head = "It failed: the agent ran out of time" + after + "."
            }
            let why = notable.first { $0.severity == "high" }?.text ?? notable.first?.text ?? stop
            return (head, why.isEmpty ? "See what happened below." : why + ".")
        case "dry", "shadow":
            let n = fs.count
            return ("A trial run: \(n == 0 ? "no finding" : "\(n) finding\(n == 1 ? "" : "s")"), and nothing acted.",
                    "In trial a loop only writes what it would have done; nothing outside the journal is written." + (notable.first.map { " Worth a look: " + $0.text + "." } ?? ""))
        default:
            if notable.isEmpty {
                return ("All clear: the check passed and nothing needs you.",
                        fs.isEmpty ? "No findings." : "\(fs.count) finding\(fs.count == 1 ? " was" : "s were") recorded for the record.")
            }
            let proposals = steps.first { $0.step == "did" }?.what.range(of: #"^\d+ proposal"#, options: .regularExpression)
            let did = steps.first { $0.step == "did" }.flatMap { s in proposals.map { String(s.what[$0]) } }
            return ("It passed, with \(notable.count) finding\(notable.count == 1 ? "" : "s") worth a look" + (did.map { " and \($0)(s) for you" } ?? "") + ".",
                    notable[0].text + ".")
        }
    }

    /// The tag a step shows in WHAT HAPPENED: started · pass · fail · info · shadow (nil = none).
    public static func stepTag(_ s: Step, trial: Bool) -> String? { LoopsV7.reportTag(s, trial: trial) }
}

extension LoopsV7 {
    static func reportTag(_ s: LoopReport.Step, trial: Bool = false) -> String? {
        let w = s.what.lowercased()
        switch s.step {
        case "trigger": return "started"
        case "check": return w.hasPrefix("pass") ? "pass" : w.hasPrefix("fail") ? "fail" : nil
        case "findings": return w.hasPrefix("0 ") ? nil : "info"
        case "would do", "shadow": return "shadow"
        case "notify": return w.hasPrefix("would") ? "shadow" : nil
        case "stop": return w.contains("still failing") ? "fail" : nil
        default: return trial && s.step == "did" ? "shadow" : nil
        }
    }

    /// The facts chip of 7k: "Built-in · Watch · by hand · Nov 4, 19:38 · no agent".
    public static func reportFacts(_ r: LoopReport, family: String?, started: Date?, calendar cal: Calendar = .current) -> String {
        var p: [String] = []
        if let l = r.meta["Loop"], let o = l.range(of: #"\(([^)]+)\)"#, options: .regularExpression) {
            p.append(String(l[o]).trimmingCharacters(in: CharacterSet(charactersIn: "()")))
        }
        if let f = family, let t = LoopKinds.family(f)?.title { p.append(t) }
        let trig = r.steps.first { $0.step == "trigger" }?.what ?? ""
        if trig.hasPrefix("by hand") { p.append("by hand") } else if trig.hasPrefix("scheduled") { p.append("on schedule") }
        if let d = started { p.append(monthDay(d, cal) + ", " + clock(d, cal)) }
        let agent = r.meta["Agent"] ?? ""
        p.append(agent.isEmpty || agent == "none" ? "no agent" : agent)
        return p.joined(separator: " · ")
    }

    /// The journal report of a run, from the ledger's ref (a kit run's `runs/YYYY/MM/….md`), resolved against the
    /// journal roots. nil when the run has no report file (roofd runs keep rounds.jsonl instead).
    public static func reportPath(_ ref: String, roots: [String], exists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }) -> String? {
        guard ref.hasSuffix(".md"), let p = AEConfig.resolveJournal(ref, roots: roots, exists: exists), exists(p) else { return nil }
        return p
    }
}
