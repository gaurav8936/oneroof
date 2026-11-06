import Foundation

// LAB-ONEROOF-v2.0.6 · Loops makeover (Claude Design v7), M1: the data every v7 screen reads. Pure where it can be:
// the app reads the kit, the loop files and the ledger off the main thread and hands them in.
//   LP-1  the kit's real on/off and mode (`ae loops list --json`), never assumed       → KitLoops, LoopRow.on/mode
//   LP-3  expected runs from each loop's schedule vs the ledger: missed and to come      → CronSpec, LoopSchedule
//   LP-4  one runs feed for both engines, time per run from started/ended (LP-14)        → LoopRun7
//   LP-8/9 by day (This week) and by hour (Today)                                         → LoopsV7.week, LoopsV7.day
//   LP-10 a journal run report (.md) as steps, findings and notes                        → LoopReport

/// Who runs a loop: the Agentic Engineering kit (`ae`, on launchd) or One Roof's own engine (roofd).
public enum LoopEngine: String, Equatable, Sendable { case kit, oneRoof }

/// A loop that is on either acts (live) or only says what it would do (shadow, "trial" in the UI).
public enum LoopMode: String, Equatable, Sendable { case live, shadow }

/// LP-1 · one row of `ae loops list --json`.
public struct KitLoopStatus: Equatable, Sendable {
    public var name: String
    public var origin: String
    public var on: Bool
    /// "live", "shadow" or "" (off, or a loop roofd runs).
    public var mode: String
    public var schedule: String
    /// "launchd", "roofd" or "-".
    public var scheduler: String
    public var last: String
    public var result: String
    public var title: String
    public init(name: String, origin: String = "", on: Bool, mode: String = "", schedule: String = "", scheduler: String = "-",
                last: String = "", result: String = "", title: String = "") {
        self.name = name; self.origin = origin; self.on = on; self.mode = mode; self.schedule = schedule
        self.scheduler = scheduler; self.last = last; self.result = result; self.title = title
    }
}

public enum KitLoops {
    /// `{"loops": [...]}` → statuses (unknown or malformed rows are skipped).
    public static func parse(_ data: Data) -> [KitLoopStatus] {
        guard let j = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let rows = j["loops"] as? [[String: Any]] else { return [] }
        return rows.compactMap { r in
            guard let name = r["name"] as? String, !name.isEmpty else { return nil }
            func s(_ k: String) -> String { (r[k] as? String) ?? "" }
            return KitLoopStatus(name: name, origin: s("origin"), on: (r["on"] as? Bool) ?? false, mode: s("mode"),
                                 schedule: s("schedule"), scheduler: s("scheduler"), last: s("last"), result: s("result"), title: s("title"))
        }
    }

    /// Runs `python3 -m ae.loops list --json` in the kit repo. nil when the kit is missing or the call fails (the
    /// screens then say "kit state unknown" instead of guessing). Call off the main thread.
    public static func read(repo: String = LoopBuiltIns.defaultRepoPath()) -> [KitLoopStatus]? {
        guard FileManager.default.fileExists(atPath: repo + "/ae") else { return nil }
        let (rc, out) = Foundations.run("/usr/bin/env", ["python3", "-m", "ae.loops", "list", "--json"], cwd: repo, timeout: 15)
        guard rc == 0, let start = out.firstIndex(of: "{") else { return nil }
        let rows = parse(Data(out[start...].utf8))
        return rows.isEmpty ? nil : rows
    }
}

// MARK: - LP-3 · schedules

/// A five-field cron line (minute hour day-of-month month day-of-week): `*`, `*/n`, `a-b`, `a-b/n`, `a,b`. Day of week
/// 0–7 (0 and 7 are Sunday). As in cron, when both day fields are restricted a time matches either.
public struct CronSpec: Equatable, Sendable {
    public var minutes: Set<Int>, hours: Set<Int>, days: Set<Int>, months: Set<Int>, weekdays: Set<Int>
    public var daysRestricted: Bool, weekdaysRestricted: Bool

    public init?(_ line: String) {
        var text = line.trimmingCharacters(in: .whitespaces)
        if text.hasPrefix("cron ") { text = String(text.dropFirst(5)) }
        let f = text.split(separator: " ").map(String.init)
        guard f.count == 5,
              let mi = Self.field(f[0], 0, 59), let h = Self.field(f[1], 0, 23), let d = Self.field(f[2], 1, 31),
              let mo = Self.field(f[3], 1, 12), var w = Self.field(f[4], 0, 7) else { return nil }
        if w.contains(7) { w.remove(7); w.insert(0) }
        minutes = mi; hours = h; days = d; months = mo; weekdays = w
        daysRestricted = f[2] != "*"; weekdaysRestricted = f[4] != "*"
    }

    static func field(_ s: String, _ lo: Int, _ hi: Int) -> Set<Int>? {
        var out = Set<Int>()
        for part in s.split(separator: ",") {
            let bits = part.split(separator: "/", maxSplits: 1).map(String.init)
            let step = bits.count == 2 ? Int(bits[1]) : 1
            guard let step, step > 0 else { return nil }
            var a = lo, b = hi
            if bits[0] != "*" {
                let r = bits[0].split(separator: "-").map(String.init)
                guard let x = Int(r[0]) else { return nil }
                a = x; b = r.count == 2 ? (Int(r[1]) ?? -1) : (bits.count == 2 ? hi : x)
            }
            guard a >= lo, b <= hi, a <= b else { return nil }
            out.formUnion(stride(from: a, through: b, by: step))
        }
        return out.isEmpty ? nil : out
    }

    public func matches(_ d: Date, _ cal: Calendar) -> Bool {
        let c = cal.dateComponents([.minute, .hour, .day, .month, .weekday], from: d)
        guard let mi = c.minute, let h = c.hour, let day = c.day, let mo = c.month, let wd = c.weekday else { return false }
        guard minutes.contains(mi), hours.contains(h), months.contains(mo) else { return false }
        let dayOK = days.contains(day), wdOK = weekdays.contains(wd - 1)
        if daysRestricted && weekdaysRestricted { return dayOK || wdOK }
        return dayOK && wdOK
    }

    /// Every matching minute in [from, to). Walks hours that can match, so a week of `*/10` stays cheap.
    public func times(from: Date, to: Date, calendar cal: Calendar = .current) -> [Date] {
        guard from < to else { return [] }
        var out: [Date] = []
        var hour = cal.dateInterval(of: .hour, for: from)?.start ?? from
        while hour < to {
            let c = cal.dateComponents([.hour, .day, .month, .weekday], from: hour)
            let dayOK = days.contains(c.day ?? 0), wdOK = weekdays.contains((c.weekday ?? 1) - 1)
            let dateOK = (daysRestricted && weekdaysRestricted) ? (dayOK || wdOK) : (dayOK && wdOK)
            if dateOK, hours.contains(c.hour ?? -1), months.contains(c.month ?? 0) {
                for m in minutes.sorted() {
                    let t = hour.addingTimeInterval(TimeInterval(m * 60))
                    if t >= from && t < to { out.append(t) }
                }
            }
            hour = hour.addingTimeInterval(3600)
        }
        return out
    }
}

public enum LoopSchedule {
    /// The schedule a loop really runs on: the kit's cron for kit loops, roofd's trigger for One Roof loops.
    /// nil for manual, event and when-quiet loops (nothing is expected, so nothing can be missed).
    public static func cron(_ loop: Loop, kit: KitLoopStatus?) -> CronSpec? {
        // The kit's word wins for kit loops ("manual" means nothing is expected); roofd loops use their own trigger.
        if let k = kit, k.scheduler != "roofd", !(k.scheduler == "-" && k.schedule.isEmpty) { return CronSpec(k.schedule) }
        if let ext = loop.externalSchedule, let c = CronSpec(ext) { return c }
        if case .at(let h, let m) = loop.trigger { return CronSpec("\(m) \(h) * * *") }
        if let k = kit, let c = CronSpec(k.schedule) { return c }
        return nil
    }

    /// Plain words for a schedule: "every 10 min", "hourly 9–23", "every 4 h", "nightly 2:30", "Fri 17:00", "manual".
    public static func words(_ c: CronSpec?) -> String {
        guard let c else { return "manual" }
        let mins = c.minutes.sorted(), hrs = c.hours.sorted()
        if mins.count > 1, hrs.count == 24, let a = mins.first, mins.count >= 2 { return "every \(mins[1] - a) min" }
        if mins.count == 1, hrs.count == 24 { return "hourly" }
        if mins.count == 1, hrs.count > 1, let lo = hrs.first, let hi = hrs.last {
            let steps = zip(hrs, hrs.dropFirst()).map { $1 - $0 }
            if Set(steps).count == 1, let s = steps.first, s > 1 { return "every \(s) h" }
            if hi - lo + 1 == hrs.count { return "hourly \(lo)–\(hi)" }
        }
        let time = String(format: "%d:%02d", hrs.first ?? 0, mins.first ?? 0)
        if c.daysRestricted, let d = c.days.sorted().first { return "monthly \(ordinal(d)) \(time)" }
        if c.weekdaysRestricted {
            let names = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
            return c.weekdays.sorted().map { names[$0] }.joined(separator: ", ") + " " + time
        }
        return "nightly \(time)"
    }

    static func ordinal(_ n: Int) -> String { n == 1 ? "1st" : n == 2 ? "2nd" : n == 3 ? "3rd" : "\(n)th" }

    /// How long after an expected time a run still counts for it: the gap to the next expected time, at most 90 min,
    /// at least 5 min.
    public static func tolerance(_ times: [Date], index i: Int) -> TimeInterval {
        let gap = i + 1 < times.count ? times[i + 1].timeIntervalSince(times[i]) : 3600
        return min(max(gap * 0.95, 300), 5400)
    }
}

// MARK: - LP-4 · runs

/// One run as the v7 screens show it (kit and roofd runs come from the same ledger table).
public struct LoopRun7: Equatable, Sendable, Identifiable {
    public enum Result: String, Equatable, Sendable { case passed, failed, trial, notRun, missed, toCome }
    public var id: String
    public var loop: String
    public var engine: LoopEngine
    public var started: Date
    public var ended: Date?
    public var result: Result
    public var cost: Double?
    public var summary: String
    /// LAB-2293 · the ledger's journal_ref (a kit run's report .md relative to the journal root; roofd: rounds.jsonl).
    public var journalRef: String = ""
    /// LP-14: time per run, from started and ended.
    public var seconds: TimeInterval? { ended.map { $0.timeIntervalSince(started) } }

    public init(id: String, loop: String, engine: LoopEngine, started: Date, ended: Date?, result: Result, cost: Double?, summary: String,
                journalRef: String = "") {
        self.id = id; self.loop = loop; self.engine = engine; self.started = started; self.ended = ended
        self.result = result; self.cost = cost; self.summary = summary; self.journalRef = journalRef
    }

    public init?(_ r: LoopLedger.Run) {
        guard let s = Self.date(r.started) else { return nil }
        let res: Result
        if r.mode == "shadow" || r.mode == "dry" || r.result == "dry" { res = .trial }
        else if ["fail", "failed", "error"].contains(r.result) { res = .failed }
        else { res = .passed }   // pass · done · promoted
        self.init(id: r.id, loop: r.loop, engine: r.engine == "roofd" ? .oneRoof : .kit, started: s, ended: Self.date(r.ended),
                  result: res, cost: r.cost, summary: r.summary, journalRef: r.journalRef)
    }

    public static func date(_ s: String) -> Date? {
        guard !s.isEmpty else { return nil }
        let f = ISO8601DateFormatter()
        if let d = f.date(from: s) { return d }
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.date(from: s)
    }
}

// MARK: - rows, week, day

/// One loop as every v7 list shows it (7a lanes, 7b, 7e, 7f, 7h). Built once per reload; never stored.
public struct LoopRow: Equatable, Sendable, Identifiable {
    public enum State: String, Equatable, Sendable { case running, failing, missed, trial, fine, off, notRun }
    public var id: String
    public var name: String
    /// watch · check · improve · report · other.
    public var family: String
    public var kind: String?
    public var mine: Bool
    public var engine: LoopEngine
    public var on: Bool
    public var mode: LoopMode?
    public var state: State
    public var schedule: String
    public var goal: String
    public var lastRun: LoopRun7?
    public var nextRun: Date?
    /// Newest last, up to 14: runs plus missed slots in time order.
    public var strip: [LoopRun7.Result]
    /// Expected runs in the window that never happened.
    public var missed: Int
    public var firstMissed: Date?
}

public enum LoopsV7 {
    public static func family(_ loop: Loop) -> String { LoopKinds.family(ofKind: loop.kind)?.id ?? LoopKinds.otherFamily.id }

    /// LP-1: kit loops take on/off and mode from the kit; One Roof loops from their own state (stopped/paused = off).
    public static func engineState(_ loop: Loop, kit: KitLoopStatus?) -> (engine: LoopEngine, on: Bool, mode: LoopMode?) {
        if let k = kit {
            if k.scheduler == "roofd" { return (.oneRoof, k.on, .live) }
            if k.on { return (.kit, true, k.mode == "shadow" ? .shadow : .live) }
            if loop.isKitFile || loop.origin == .builtIn { return (.kit, false, nil) }
        }
        if loop.isKitFile || loop.origin == .builtIn { return (.kit, false, nil) }
        let on = ![LoopState.stopped, .paused].contains(loop.state)
        return (.oneRoof, on, on ? .live : nil)
    }

    /// Expected times in [from, to) that no run answered, given the loop's runs (any result, trial included).
    public static func missed(expected: [Date], runs: [LoopRun7]) -> [Date] {
        expected.enumerated().compactMap { i, t in
            let tol = LoopSchedule.tolerance(expected, index: i)
            return runs.contains { $0.started >= t.addingTimeInterval(-300) && $0.started < t.addingTimeInterval(tol) } ? nil : t
        }
    }

    /// The rows for every loop. `runs` holds each loop's ledger runs (any order) for at least `window` back.
    public static func rows(loops: [Loop], kit: [KitLoopStatus]?, runs: [String: [LoopRun7]], now: Date = Date(),
                            window: TimeInterval = 7 * 86400, calendar cal: Calendar = .current) -> [LoopRow] {
        let k = Dictionary((kit ?? []).map { ($0.name, $0) }, uniquingKeysWith: { a, _ in a })
        return loops.map { l in
            let ks = k[l.id]
            let (engine, on, mode) = engineState(l, kit: ks)
            let rs = (runs[l.id] ?? []).sorted { $0.started < $1.started }
            let cron = LoopSchedule.cron(l, kit: ks)
            // Missed only counts while the loop is on, from its first run in the window (a proxy for when it was turned on).
            var miss: [Date] = []
            if on, let c = cron, let first = rs.first(where: { $0.started >= now.addingTimeInterval(-window) })?.started ?? rs.last?.started {
                let from = max(first.addingTimeInterval(60), now.addingTimeInterval(-window))
                let exp = c.times(from: from, to: now.addingTimeInterval(-600), calendar: cal)
                miss = missed(expected: exp, runs: rs)
            }
            var timeline: [(Date, LoopRun7.Result)] = rs.map { ($0.started, $0.result) } + miss.map { ($0, .missed) }
            timeline.sort { $0.0 < $1.0 }
            let last = rs.last
            let next = on ? cron?.times(from: now, to: now.addingTimeInterval(8 * 86400), calendar: cal).first : nil
            let state: LoopRow.State
            if !on { state = .off }
            else if l.state == .running || l.state == .needsYou { state = .running }
            else if last?.result == .failed { state = .failing }
            else if let lm = miss.last, lm > (last?.started ?? .distantPast) { state = .missed }
            else if mode == .shadow { state = .trial }
            else if last == nil { state = .notRun }
            else { state = .fine }
            return LoopRow(id: l.id, name: l.displayTitle, family: family(l), kind: l.kind, mine: l.origin != .builtIn,
                           engine: engine, on: on, mode: mode, state: state, schedule: LoopSchedule.words(cron), goal: l.goal,
                           lastRun: last, nextRun: next, strip: Array(timeline.suffix(14).map(\.1)), missed: miss.count,
                           firstMissed: miss.first)
        }
    }

    /// LP-8 · one cell of This week: a loop on a day.
    public struct DayCell: Equatable, Sendable {
        public var day: Date
        public var passed = 0, failed = 0, trial = 0, missed = 0, toCome = 0
        public var isEmpty: Bool { passed + failed + trial + missed + toCome == 0 }
    }

    /// LP-8 · seven days ending with `now`'s day, for one loop: runs, missed and still to come per day.
    public static func week(row: LoopRow, runs: [LoopRun7], cron: CronSpec?, now: Date = Date(), days: Int = 7,
                            calendar cal: Calendar = .current) -> [DayCell] {
        let today = cal.startOfDay(for: now)
        return (0..<days).reversed().map { back in
            let d0 = cal.date(byAdding: .day, value: -back, to: today)!, d1 = cal.date(byAdding: .day, value: 1, to: d0)!
            var c = DayCell(day: d0)
            for r in runs where r.started >= d0 && r.started < d1 {
                switch r.result { case .failed: c.failed += 1; case .trial: c.trial += 1; default: c.passed += 1 }
            }
            if row.on, let cr = cron {
                let exp = cr.times(from: d0, to: min(d1, now.addingTimeInterval(-600)), calendar: cal)
                if let first = runs.map(\.started).min() {
                    c.missed = missed(expected: exp.filter { $0 > first }, runs: runs).count
                }
                if d1 > now { c.toCome = cr.times(from: now, to: d1, calendar: cal).count }
            }
            return c
        }
    }

    /// LP-9 · Today: each run's time and result, plus the times still to come today (or in the 24 h window ending now).
    public static func day(runs: [LoopRun7], cron: CronSpec?, on: Bool, dayStart: Date, dayEnd: Date, now: Date = Date(),
                           calendar cal: Calendar = .current) -> [(at: Date, result: LoopRun7.Result)] {
        var out = runs.filter { $0.started >= dayStart && $0.started < dayEnd }.map { (at: $0.started, result: $0.result) }
        if on, let c = cron, dayEnd > now { out += c.times(from: max(now, dayStart), to: dayEnd, calendar: cal).map { (at: $0, result: .toCome) } }
        return out.sorted { $0.at < $1.at }
    }

    /// One count for Needs you everywhere (rail badge, landing chip, page title): one per decision you make. The
    /// commits one run left are one decision (one PR); every other staged outcome is one (a staged promotion is the
    /// kit asking "go live?", a decision too: auto-live promotions are written as applied, never staged); a question
    /// or a failure item is one; a loop with missed runs is one. Equals `needsCount(items:)` over LoopInbox.items.
    public static func needsCount(staged: [LoopLedger.Outcome], questions: Int, failures: Int, missedLoops: Int) -> Int {
        let open = staged.filter { $0.status == "staged" }
        let commitRuns = Set(open.filter { $0.kind == "commit" }.map { $0.loop + "\u{1}" + $0.runId })
        let other = open.filter { $0.kind != "commit" }.count
        return commitRuns.count + other + questions + failures + missedLoops
    }
}

// MARK: - LP-10 · a run's report

/// A journal run report (`<shared>/journal/runs/YYYY/MM/<date>_<loop>_<run>.md`) as 7k shows it.
public struct LoopReport: Equatable, Sendable {
    public struct Step: Equatable, Sendable { public var t: String, step: String, what: String }
    public var title = ""
    public var meta: [String: String] = [:]
    public var goal = ""
    public var steps: [Step] = []
    public var findings: [String] = []
    /// Any other section, in order ("Would do", "Notify" …).
    public var sections: [(title: String, lines: [String])] = []

    public static func == (a: LoopReport, b: LoopReport) -> Bool {
        a.title == b.title && a.meta == b.meta && a.goal == b.goal && a.steps == b.steps && a.findings == b.findings
            && a.sections.map(\.title) == b.sections.map(\.title) && a.sections.map(\.lines) == b.sections.map(\.lines)
    }

    /// The step that says how it ended ("check", else "stop").
    public var result: String { steps.last { $0.step == "check" }?.what ?? steps.last { $0.step == "stop" }?.what ?? "" }

    public static func parse(_ md: String) -> LoopReport {
        var r = LoopReport()
        var section = ""
        var buf: [String] = []
        func close() {
            let lines = buf.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            switch section.lowercased() {
            case "", "timeline": break
            case "findings": r.findings = lines.filter { $0.hasPrefix("- ") }.map { String($0.dropFirst(2)) }.filter { $0 != "none" }
            default: r.sections.append((section, lines))
            }
            buf = []
        }
        for raw in md.components(separatedBy: "\n") {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("# ") { r.title = String(line.dropFirst(2)); continue }
            if line.hasPrefix("## ") { close(); section = String(line.dropFirst(3)); continue }
            if section.isEmpty {
                if line.hasPrefix("> ") { r.goal = String(line.dropFirst(2)).replacingOccurrences(of: "Goal: ", with: "") }
                else if line.hasPrefix("**") {
                    for part in line.components(separatedBy: " · ") {
                        let p = part.replacingOccurrences(of: "**", with: "")
                        if let c = p.range(of: ":") { r.meta[String(p[..<c.lowerBound]).trimmingCharacters(in: .whitespaces)] = String(p[c.upperBound...]).trimmingCharacters(in: .whitespaces) }
                    }
                }
                continue
            }
            if section.lowercased() == "timeline", line.hasPrefix("|") {
                let cells = line.split(separator: "|", omittingEmptySubsequences: false).map { $0.trimmingCharacters(in: .whitespaces) }.dropFirst().dropLast()
                let c = Array(cells)
                if c.count >= 3, c[0] != "t", !c[0].hasPrefix("---") { r.steps.append(Step(t: c[0], step: c[1], what: c[2...].joined(separator: " | "))) }
                continue
            }
            buf.append(line)
        }
        close()
        return r
    }
}
