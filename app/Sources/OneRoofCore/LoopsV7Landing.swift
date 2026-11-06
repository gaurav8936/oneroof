import Foundation

// LAB-ONEROOF-v2.0.6 · Loops makeover (Claude Design v7), 7a: the landing (kinds as lanes), the shell's lines and the
// one filter every v7 list uses. Pure: the app builds the rows (LoopsV7.rows) and the Needs you items off the main
// thread and hands them in; the views draw what these return.
//   LAB-2286  7a lanes: per kind on/all, the loops that are on, their last runs, last · next · by, and For you
//   LAB-2286  one Needs you count everywhere (= the Needs you items, one per decision)

/// The one filter bar's state (search · kind · state), one per screen.
public struct LoopFilter: Equatable, Sendable {
    /// on · off · trial · failing · missed · running · fine (nil = any).
    public enum State: String, CaseIterable, Equatable, Sendable {
        case on, trial, failing, missed, running, fine, off
        public var label: String {
            switch self {
            case .on: return "On"
            case .trial: return "Trial"
            case .failing: return "Failing"
            case .missed: return "Missed"
            case .running: return "Running"
            case .fine: return "Fine"
            case .off: return "Off"
            }
        }
    }
    public var query: String
    /// watch · check · improve · report · other (nil = every kind).
    public var family: String?
    public var state: State?
    public init(query: String = "", family: String? = nil, state: State? = nil) { self.query = query; self.family = family; self.state = state }
    public var isEmpty: Bool { query.trimmingCharacters(in: .whitespaces).isEmpty && family == nil && state == nil }
}

extension LoopsV7 {
    // MARK: Filter

    /// The rows that match a filter: search over the name, what it does (goal), its kind and its kind's family name.
    public static func filter(_ rows: [LoopRow], _ f: LoopFilter) -> [LoopRow] {
        let q = f.query.trimmingCharacters(in: .whitespaces).lowercased()
        return rows.filter { r in
            if let fam = f.family, r.family != fam { return false }
            if let s = f.state {
                switch s {
                case .on: if !r.on { return false }
                case .off: if r.on { return false }
                case .trial: if r.mode != .shadow || !r.on { return false }
                case .failing: if r.state != .failing { return false }
                case .missed: if r.missed == 0 { return false }
                case .running: if r.state != .running { return false }
                case .fine: if r.state != .fine { return false }
                }
            }
            guard !q.isEmpty else { return true }
            let hay = [r.name, r.id, r.goal, r.kind ?? "", LoopKinds.kind(r.kind)?.title ?? "", LoopKinds.family(r.family)?.title ?? ""]
                .joined(separator: " ").lowercased()
            return q.split(separator: " ").allSatisfy { hay.contains($0) }
        }
    }

    /// The empty line under a filtered list: "No loop matches “x” · Watch · failing."
    public static func emptyLine(_ f: LoopFilter) -> String {
        var parts: [String] = []
        let q = f.query.trimmingCharacters(in: .whitespaces)
        if !q.isEmpty { parts.append("“\(q)”") }
        if let fam = f.family { parts.append(LoopKinds.family(fam)?.title ?? fam) }
        if let s = f.state { parts.append(s.label.lowercased()) }
        return parts.isEmpty ? "No loops." : "No loop matches " + parts.joined(separator: " · ") + "."
    }

    // MARK: Needs you

    /// One count for Needs you everywhere: one per Needs you item. The items are built so each is one decision
    /// (LoopInbox.items: the commits one run left are one item, every other staged outcome one, a question one, a
    /// failure one, a loop with missed runs one).
    public static func needsCount(items: [LoopInbox.Item]) -> Int { items.count }

    /// "~N min", an estimate of the time Needs you takes: 5 min per PR (one run's commits, or a staged PR), 1 min per
    /// proposal, 30 s per report or anything else. Always shown as an estimate.
    public static func estimateSeconds(_ items: [LoopInbox.Item]) -> Int {
        items.reduce(0) { sum, i in
            switch (i.kind, i.outcomeKind) {
            case (.staged, "commit"), (.staged, "pr"): return sum + 300
            case (.staged, "proposal"): return sum + 60
            default: return sum + 30
            }
        }
    }

    public static func estimateLabel(_ seconds: Int) -> String {
        guard seconds > 0 else { return "" }
        return "~\(max(1, Int((Double(seconds) / 60).rounded()))) min"
    }

    // MARK: Status pills and lines

    public struct StatusCounts: Equatable, Sendable {
        public var failing = 0, needYou = 0, running = 0, fine = 0
        public var estimateSeconds = 0
        public var firstFailing: String?
        public init() {}
    }

    public static func statusCounts(rows: [LoopRow], items: [LoopInbox.Item]) -> StatusCounts {
        var c = StatusCounts()
        let failing = rows.filter { $0.state == .failing }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        c.failing = failing.count
        c.firstFailing = failing.first?.id
        c.running = rows.filter { $0.state == .running }.count
        c.fine = rows.filter { $0.state == .fine }.count
        c.needYou = needsCount(items: items)
        c.estimateSeconds = estimateSeconds(items)
        return c
    }

    /// "This week: 209 runs · $0.29 · 8 failed (2 loops)" over the last seven days (trial runs count as runs).
    public static func weekLine(runs: [LoopRun7], now: Date = Date()) -> String {
        let from = now.addingTimeInterval(-7 * 86400)
        let week = runs.filter { $0.started >= from && $0.started <= now }
        let cost = week.compactMap(\.cost).reduce(0, +)
        let failed = week.filter { $0.result == .failed }
        let loops = Set(failed.map(\.loop)).count
        var parts = ["This week: \(week.count) run\(week.count == 1 ? "" : "s")", String(format: "$%.2f", cost)]
        parts.append(failed.isEmpty ? "none failed" : "\(failed.count) failed (\(loops) loop\(loops == 1 ? "" : "s"))")
        return parts.joined(separator: " · ")
    }

    /// The status bar's loops part: "14 loops on · next: Mac resource watch 10:40" ("no loops on" when none).
    public static func statusBar(rows: [LoopRow], now: Date = Date(), calendar cal: Calendar = .current) -> String {
        let on = rows.filter(\.on)
        guard !on.isEmpty else { return "no loops on" }
        var s = "\(on.count) loop\(on.count == 1 ? "" : "s") on"
        if let n = on.filter({ $0.nextRun != nil }).min(by: { $0.nextRun! < $1.nextRun! }), let at = n.nextRun {
            s += " · next: \(n.name) " + when(at, now: now, calendar: cal)
        }
        return s
    }

    // MARK: A loop's line on a lane

    static func clock(_ d: Date, _ cal: Calendar) -> String {
        let c = cal.dateComponents([.hour, .minute], from: d)
        return String(format: "%d:%02d", c.hour ?? 0, c.minute ?? 0)
    }

    static func weekday(_ d: Date, _ cal: Calendar) -> String {
        ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"][(cal.component(.weekday, from: d) - 1) % 7]
    }

    static func monthDay(_ d: Date, _ cal: Calendar) -> String {
        let m = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"][(cal.component(.month, from: d) - 1) % 12]
        return "\(m) \(cal.component(.day, from: d))"
    }

    /// A time from now's point of view: "10:40" today, "7:30 tmrw", "Fri 17:00" within a week, else "Nov 14".
    public static func when(_ d: Date, now: Date = Date(), calendar cal: Calendar = .current) -> String {
        let days = cal.dateComponents([.day], from: cal.startOfDay(for: now), to: cal.startOfDay(for: d)).day ?? 0
        switch days {
        case 0: return clock(d, cal)
        case 1: return clock(d, cal) + " tmrw"
        case -1: return "yest. " + clock(d, cal)
        case -6 ... -2, 2...6: return weekday(d, cal) + " " + clock(d, cal)
        default: return monthDay(d, cal)
        }
    }

    /// How a lane line's right part reads.
    public enum Tone: String, Equatable, Sendable { case normal, failed, missed }

    /// "10:30 · every 10 min · by kit", "fail 2:30 · 2:30 tmrw · by kit", "missed · 1:00 tmrw · by kit",
    /// "today 17:00 · by One Roof", "first trial 16:30 · by kit". With the kit unread, a kit loop says so.
    public static func lastNextBy(_ r: LoopRow, kitKnown: Bool = true, now: Date = Date(), calendar cal: Calendar = .current) -> (text: String, tone: Tone) {
        var parts: [String] = []
        var tone = Tone.normal
        if r.state == .missed {
            parts.append("missed"); tone = .missed
        } else if let last = r.lastRun {
            let t = when(last.started, now: now, calendar: cal)
            if last.result == .failed { parts.append("fail " + t); tone = .failed } else { parts.append(t) }
        }
        if r.on, let next = r.nextRun {
            let frequent = r.schedule.hasPrefix("every") && r.schedule.hasSuffix("min")
            if r.lastRun == nil, r.mode == .shadow { parts.append("first trial " + when(next, now: now, calendar: cal)) }
            else if frequent { parts.append(r.schedule) }
            else {
                let w = when(next, now: now, calendar: cal)
                parts.append(r.lastRun == nil && cal.isDate(next, inSameDayAs: now) ? "today " + w : w)
            }
        } else if r.on {
            parts.append(r.schedule == "manual" ? "manual" : r.schedule)
        }
        if r.engine == .kit && !kitKnown { parts.append("kit state unknown") }
        else { parts.append(r.engine == .kit ? "by kit" : "by One Roof") }
        return (parts.joined(separator: " · "), tone)
    }

    /// The short line after a loop's name: what its last run said ("2 findings", "no finding"), or why there is none.
    public static func subLine(_ r: LoopRow, now: Date = Date(), calendar cal: Calendar = .current) -> String {
        if r.missed > 0, r.state == .missed {
            let since = r.lastRun.map { "no run since " + monthDay($0.started, cal) } ?? "no run yet"
            return since + " · \(r.missed) missed"
        }
        guard let last = r.lastRun else {
            if r.on, r.mode == .shadow { return "trial runs before going live" }
            return r.on ? "not run yet" : ""
        }
        var s = last.summary.trimmingCharacters(in: .whitespacesAndNewlines)
        if let nl = s.firstIndex(of: "\n") { s = String(s[..<nl]) }
        for prefix in [r.name + ": ", r.id + ": "] where s.hasPrefix(prefix) { s = String(s.dropFirst(prefix.count)) }
        // The kit's "<Title>: pass, 2 finding(s)" / "dry, 1 finding(s)" in plain words (its title may differ from ours).
        if let m = s.range(of: #"(pass|fail|dry|done|ok), (\d+) finding\(s\)$"#, options: .regularExpression),
           m.lowerBound == s.startIndex || s[..<m.lowerBound].hasSuffix(": ") {
            s = String(s[m.lowerBound...])
            let bits = s.components(separatedBy: ", ")
            let n = Int(bits[1].components(separatedBy: " ")[0]) ?? 0
            let found = n == 0 ? "no finding" : "\(n) finding\(n == 1 ? "" : "s")"
            return bits[0] == "dry" ? "trial · " + found : found
        }
        if s.hasPrefix("Done: the check already passed") { return "check passed" }
        if s.isEmpty { return last.result == .failed ? "last run failed" : "" }
        return s
    }

    /// How many of the newest runs failed in a row (the strip's tail).
    public static func failStreak(_ r: LoopRow) -> Int { r.strip.reversed().prefix { $0 == .failed }.count }

    // MARK: Lanes (7a)

    /// What a For you button does. Buttons route to existing actions; Set kind is not wired yet (LP-2) and says so.
    public enum AskAction: Equatable, Sendable {
        case runNow(String)          // a loop with missed runs
        case turnOn(String)          // an off loop that covers a gap (starts with trial runs)
        case setUp(String)           // an off loop that needs a setting or a tool first
        case review(loop: String, item: String?)   // Needs you, at the loop (or one item)
        case open(String)            // a failing loop
        case setKind([String])       // loops with no kind (LP-2, not wired yet)
        case kind(String)            // the kind's page (the rest of its off loops)
    }

    public struct Ask: Equatable, Sendable, Identifiable {
        public var id: String
        public var text: String
        public var button: String
        /// Primary when it decides something (Review), secondary otherwise.
        public var primary: Bool
        public var action: AskAction
        /// What an off loop would do (its goal's first sentence), for the tooltip.
        public var detail: String
        public init(id: String, text: String, button: String, primary: Bool, action: AskAction, detail: String = "") {
            self.id = id; self.text = text; self.button = button; self.primary = primary; self.action = action; self.detail = detail
        }
    }

    public struct Lane: Equatable, Sendable, Identifiable {
        public var family: LoopKinds.Family
        public var blurb: String
        public var on: Int
        public var all: Int
        /// The loops that are on: pinned first, then needing attention (failing, missed), then by name.
        public var rows: [LoopRow]
        public var asks: [Ask]
        public var gaps: [Ask]
        public var id: String { family.id }
    }

    /// The landing's one-line blurbs (7a), shorter than the family cards'.
    public static func laneBlurb(_ family: String) -> String {
        switch family {
        case "watch": return "Speaks up when a number or a live thing goes wrong."
        case "check": return "Measures work against a rule or a bar."
        case "improve": return "Fixes, refreshes, proposes rules."
        case "report": return "Writes something for you to read."
        default: return "No kind set."
        }
    }

    /// The lane order on 7a.
    public static let laneOrder = ["watch", "check", "improve", "report", "other"]

    /// "4 proposals, 3 reports", "4 commits".
    static func outcomeWords(_ items: [LoopInbox.Item]) -> String {
        var counts: [String: Int] = [:]
        var order: [String] = []
        for o in items.flatMap(\.outcomes) {
            if counts[o.kind] == nil { order.append(o.kind) }
            counts[o.kind, default: 0] += 1
        }
        return order.map { k in
            let n = counts[k]!
            let word = k == "promotion" ? "go-live ask" : k
            return "\(n) \(word)\(n == 1 ? "" : "s")"
        }.joined(separator: ", ")
    }

    /// Every lane (Watch, Check, Improve, Report, then Other when it has loops) with its loops that are on and its
    /// For you asks and gaps. `setupMissing`: loops that need a setting or a tool (LAB-2100). `pinned`: pinned loop ids.
    public static func lanes(rows: [LoopRow], items: [LoopInbox.Item], pinned: Set<String> = [], setupMissing: Set<String> = [],
                             kitKnown: Bool = true, now: Date = Date(), calendar cal: Calendar = .current) -> [Lane] {
        laneOrder.compactMap { fid -> Lane? in
            guard let fam = LoopKinds.family(fid) else { return nil }
            let mine = rows.filter { $0.family == fid }
            if fid == "other" && mine.isEmpty { return nil }
            let ids = Set(mine.map(\.id))
            func rank(_ r: LoopRow) -> Int {
                if pinned.contains(r.id) { return 0 }
                switch r.state { case .failing, .running: return 1; default: return 2 }
            }
            // Pinned first, then failing or running, then the next to run first (no next run last), then by name.
            let on = mine.filter(\.on).sorted { a, b in
                let (ra, rb) = (rank(a), rank(b))
                if ra != rb { return ra < rb }
                let (na, nb) = (a.nextRun ?? .distantFuture, b.nextRun ?? .distantFuture)
                if na != nb { return na < nb }
                return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
            }
            var asks: [Ask] = []
            let laneItems = items.filter { ids.contains($0.loopId) }
            // Per loop: a failing loop (with what it left for you), commits as PRs, other staged outcomes, missed runs.
            for r in mine.sorted(by: { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }) {
                let its = laneItems.filter { $0.loopId == r.id }
                let commits = its.filter { $0.kind == .staged && ["commit", "pr"].contains($0.outcomeKind) }
                let others = its.filter { $0.kind == .staged && !["commit", "pr"].contains($0.outcomeKind) }
                let questions = its.filter { $0.kind == .asks }
                if r.state == .failing {
                    let n = failStreak(r)
                    let unit = r.schedule.hasPrefix("nightly") ? "night" : "run"
                    let failed = n > 1 ? "failed \(n) \(unit)s in a row" : "failed its last run"
                    if !others.isEmpty {
                        asks.append(Ask(id: "fail-review-" + r.id, text: "\(r.name) \(failed): \(outcomeWords(others)) waiting",
                                        button: "Review \(others.count)", primary: true, action: .review(loop: r.id, item: nil)))
                    } else {
                        asks.append(Ask(id: "fail-" + r.id, text: "\(r.name) \(failed)", button: "Open", primary: false, action: .open(r.id)))
                    }
                } else if !others.isEmpty {
                    asks.append(Ask(id: "review-" + r.id, text: "\(r.name): \(outcomeWords(others))", button: "Review \(others.count)",
                                    primary: true, action: .review(loop: r.id, item: nil)))
                }
                if !commits.isEmpty {
                    let n = commits.flatMap(\.outcomes).count
                    let since = commits.map(\.when).min().map { " since " + monthDay($0, cal) } ?? ""
                    let what = commits.allSatisfy { $0.outcomeKind == "commit" } ? "\(n) commit\(n == 1 ? "" : "s") waiting" : "\(commits.count) PR\(commits.count == 1 ? "" : "s") waiting"
                    asks.append(Ask(id: "pr-" + r.id, text: (r.state == .failing ? "" : r.name + ": ") + what + since,
                                    button: commits.count == 1 ? "Review PR" : "Review \(commits.count) PRs", primary: true,
                                    action: .review(loop: r.id, item: commits.count == 1 ? commits[0].id : nil)))
                }
                if !questions.isEmpty {
                    asks.append(Ask(id: "ask-" + r.id, text: "\(r.name): a round asks you something", button: "Answer", primary: true,
                                    action: .review(loop: r.id, item: questions[0].id)))
                }
                if r.on, r.missed > 0, r.state == .missed {
                    let unit = r.schedule.hasPrefix("nightly") ? "night" : "run"
                    asks.append(Ask(id: "missed-" + r.id, text: "\(r.name): \(r.missed) \(unit)\(r.missed == 1 ? "" : "s") missed",
                                    button: "Run now", primary: false, action: .runNow(r.id)))
                }
            }
            if fid == "other" {
                let n = mine.count
                asks.append(Ask(id: "setkind", text: "Set a kind for \(n) loop\(n == 1 ? "" : "s")", button: "Set kind", primary: false,
                                action: .setKind(mine.map(\.id))))
            }
            // Gaps: one off loop that would cover this kind (ready to turn on first, then one needing setup), and the
            // rest on the kind's page. Only when the kit could be read (otherwise "off" is not known).
            var gaps: [Ask] = []
            let off = mine.filter { !$0.on && (kitKnown || $0.engine == .oneRoof) && fid != "other" }
                .sorted { a, b in
                    let (sa, sb) = (setupMissing.contains(a.id), setupMissing.contains(b.id))
                    if sa != sb { return !sa }
                    let (ma, mb) = (a.schedule == "manual", b.schedule == "manual")
                    if ma != mb { return !ma }
                    return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
                }
            if let g = off.first {
                let needs = setupMissing.contains(g.id)
                gaps.append(Ask(id: "gap-" + g.id, text: "\(g.name) is off" + (needs ? " and needs setup" : ""),
                                button: needs ? "Set up" : "Turn on", primary: false, action: needs ? .setUp(g.id) : .turnOn(g.id),
                                detail: shortGoal(g.goal)))
                if off.count > 1 {
                    gaps.append(Ask(id: "more-" + fid, text: "\(off.count - 1) more off", button: "\(off.count - 1) more off ›", primary: false, action: .kind(fid)))
                }
            }
            return Lane(family: fam, blurb: laneBlurb(fid), on: mine.filter(\.on).count, all: mine.count, rows: on, asks: asks, gaps: gaps)
        }
    }

    /// A goal cut to its first sentence, at most 70 characters.
    static func shortGoal(_ g: String) -> String {
        var s = g.trimmingCharacters(in: .whitespacesAndNewlines)
        if let nl = s.firstIndex(of: "\n") { s = String(s[..<nl]) }
        if let dot = s.range(of: ". ") { s = String(s[..<dot.lowerBound]) }
        if s.hasSuffix(".") { s.removeLast() }
        if s.count > 120 { s = String(s.prefix(119)) + "…" }
        guard let f = s.first else { return s }
        return f.lowercased() + s.dropFirst()
    }
}

// MARK: - The kit's on/off read, shared

/// LP-1 · `ae loops list --json`, read at most every `maxAge` seconds and shared by the Loops page and the Needs you
/// count (one subprocess, never on the main thread). nil = the kit could not be read: "kit state unknown".
public final class KitLoopsCache: @unchecked Sendable {
    public static let shared = KitLoopsCache()
    private let lock = NSLock()
    private var value: [KitLoopStatus]?
    private var at: Date = .distantPast
    private let reader: @Sendable () -> [KitLoopStatus]?

    public init(reader: @escaping @Sendable () -> [KitLoopStatus]? = { KitLoops.read() }) { self.reader = reader }

    /// The cached read when it is fresh enough, else a new read (blocking: call off the main thread).
    public func get(maxAge: TimeInterval = 30, now: Date = Date()) -> [KitLoopStatus]? {
        lock.lock(); defer { lock.unlock() }
        if now.timeIntervalSince(at) < maxAge { return value }
        value = reader(); at = now
        return value
    }

    /// Forget the read (after the app turned a kit loop on or ran one).
    public func invalidate() { lock.lock(); at = .distantPast; lock.unlock() }
}

// MARK: - Needs you items for missed runs

extension LoopInbox {
    /// A loop that is on but missed runs its schedule expected (LP-3): one item per loop.
    public static func missed(_ rows: [LoopRow]) -> [Item] {
        rows.filter { $0.on && $0.missed > 0 && $0.state == .missed }.map { r in
            Item(id: "missed-" + r.id, kind: .missed, loopId: r.id, loopTitle: r.name,
                 headline: "Loop \(r.name) missed \(r.missed) scheduled run\(r.missed == 1 ? "" : "s")",
                 detail: "It is on (\(r.engine == .kit ? "run by the kit" : "run by One Roof"), \(r.schedule)), but no run was recorded"
                    + (r.firstMissed.map { " since " + LoopsV7.monthDay($0, .current) } ?? "") + ".",
                 when: r.firstMissed ?? Date())
        }
        .sorted { $0.when < $1.when }
    }
}

// MARK: - Kit actions (the kit owns its loops: One Roof asks it, never writes its files)

extension KitLoops {
    /// The command line for a kit action (shown in confirmations, so what is written is said before it is).
    public static func command(_ verb: String, _ name: String) -> [String] {
        switch verb {
        case "run": return ["python3", "-m", "ae.loops", "run", name, "--scheduled"]
        default: return ["python3", "-m", "ae.loops", verb, name]
        }
    }

    /// `ae loops on <name>`: the kit sets loops.enabled and its launchd entry; a loop turned on starts in shadow (trial)
    /// nights first (LP-12). Blocking (seconds): call off the main thread. Returns the kit's last line.
    public static func turnOn(_ name: String, repo: String = LoopBuiltIns.defaultRepoPath()) throws -> String {
        let (rc, out) = Foundations.run("/usr/bin/env", command("on", name), cwd: repo, timeout: 60)
        KitLoopsCache.shared.invalidate()
        let last = out.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        guard rc == 0 else { throw LoopStoreError("the kit could not turn \(name) on: " + (last.last ?? "exit \(rc)")) }
        return last.first { $0.hasPrefix("mode:") } ?? last.last ?? "On."
    }

    /// `ae loops run <name> --scheduled`: one run now, as launchd would start it (a loop that is off does nothing; in
    /// shadow it only says what it would do). Started in the background; the run shows in the ledger when it ends.
    public static func runNow(_ name: String, repo: String = LoopBuiltIns.defaultRepoPath()) throws {
        guard FileManager.default.fileExists(atPath: repo + "/ae") else { throw LoopStoreError("the kit is not at \(repo)") }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        p.arguments = command("run", name)
        p.currentDirectoryURL = URL(fileURLWithPath: repo)
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        p.standardInput = FileHandle.nullDevice
        try p.run()
        KitLoopsCache.shared.invalidate()
    }
}

extension LoopsV7 {
    /// Each loop's ledger runs over the last `days` (the landing's strips, missed runs and This week).
    public static func runsByLoop(_ ledger: LoopLedger?, now: Date = Date(), days: Double = 8) -> [String: [LoopRun7]] {
        guard let ledger else { return [:] }
        let runs = ledger.runs(from: now.addingTimeInterval(-days * 86400), to: now.addingTimeInterval(60), limit: 20000).compactMap(LoopRun7.init)
        return Dictionary(grouping: runs, by: \.loop)
    }
}
