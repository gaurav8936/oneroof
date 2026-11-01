import Foundation

/// LAB-2098 · Home as the morning front page (owner-approved mockup, 2026-11-01): a masthead, a ticker (seats, Mac,
/// version), the lead story and side stories written as findings (not counts), "Decide now" (what waits on you), and the
/// overnight river (what ran, when). Built from real data the app already holds (loop ledger runs, loop items, History's
/// moments, the Inbox, seats, Linear issues of linked projects, the Mac's memory and disk). Nothing here is specific to
/// one person's workspace: with no data a section says so plainly. Pure: the app gathers `Inputs` off the main thread.
public enum HomeFrontPage {

    // MARK: Inputs

    public struct LoopRun: Equatable, Sendable {
        public var loop: String
        public var title: String
        public var started: Date
        public var result: String
        public var summary: String
        public init(loop: String, title: String, started: Date, result: String, summary: String) {
            self.loop = loop; self.title = title; self.started = started; self.result = result; self.summary = summary
        }
    }

    /// One of your sessions' moments from History (a finding, a handoff, a release, an error…).
    public struct Moment: Equatable, Sendable {
        public var at: Date
        public var kind: ScrollEntry.Kind
        public var text: String
        public var session: String
        public init(at: Date, kind: ScrollEntry.Kind, text: String, session: String) {
            self.at = at; self.kind = kind; self.text = text; self.session = session
        }
    }

    /// Something waiting on you (the Inbox's blocks, in its order).
    public struct Ask: Equatable, Sendable {
        public enum Kind: String, Sendable { case question, permission, finished, plan, loopFailed, loopAsks, loopStaged }
        public var id: String
        public var kind: Kind
        public var title: String
        public var detail: String
        public var at: Date
        public var sessionId: String?
        public var loopId: String?
        public init(id: String, kind: Kind, title: String, detail: String, at: Date, sessionId: String? = nil, loopId: String? = nil) {
            self.id = id; self.kind = kind; self.title = title; self.detail = detail; self.at = at; self.sessionId = sessionId; self.loopId = loopId
        }
    }

    /// A Linear issue of a project a session is linked to (only those waiting on you: in review or blocked).
    public struct Issue: Equatable, Sendable {
        public var identifier: String
        public var title: String
        public var state: String
        public init(identifier: String, title: String, state: String) { self.identifier = identifier; self.title = title; self.state = state }
    }

    public struct Inputs: Equatable, Sendable {
        public var now: Date
        public var runs: [LoopRun] = []
        public var moments: [Moment] = []
        public var asks: [Ask] = []
        public var issues: [Issue] = []
        public var seats: [SeatUsage] = []
        public var mac: MacMemory?
        public var diskFree: Int64?
        public var version: String?
        public var liveSessions = 0
        public var working = 0
        public init(now: Date) { self.now = now }
    }

    // MARK: Output

    public enum Tone: String, Sendable { case bad, warn, good, info }

    public enum Target: Equatable, Sendable {
        case inbox, history, sessions, projects, machine, evals, settings
        case loops(String?)
        case session(String)
        case runLoopAgain(String)
    }

    public struct Action: Equatable, Sendable {
        public var title: String
        public var target: Target
        public var primary: Bool
        public init(_ title: String, _ target: Target, primary: Bool = false) { self.title = title; self.target = target; self.primary = primary }
    }

    public struct Story: Equatable, Sendable {
        public var kicker: String
        public var headline: String
        public var body: String
        public var tone: Tone
        public var actions: [Action]
    }

    public struct DecideRow: Equatable, Sendable, Identifiable {
        public var id: String
        public var tag: String
        public var text: String
        public var action: Action
    }

    public struct TickerItem: Equatable, Sendable {
        public var label: String
        public var value: String
        public var tone: Tone
    }

    public struct Mark: Equatable, Sendable, Identifiable {
        public var id: String
        /// 0…1 across the window.
        public var x: Double
        public var label: String
        public var tone: Tone
        public var count: Int
        /// Whether the label is drawn (crowded or repeated labels are left off; the dot and VoiceOver keep them).
        public var shown = true
    }

    public struct Lane: Equatable, Sendable, Identifiable {
        public var id: String { name }
        public var name: String
        public var marks: [Mark]
    }

    public struct River: Equatable, Sendable {
        public var start: Date
        public var end: Date
        public var lanes: [Lane]
        public var ticks: [(x: Double, label: String)]
        public var isEmpty: Bool { lanes.allSatisfy { $0.marks.isEmpty } }
        public static func == (a: River, b: River) -> Bool {
            a.start == b.start && a.end == b.end && a.lanes == b.lanes && a.ticks.map(\.label) == b.ticks.map(\.label) && a.ticks.map(\.x) == b.ticks.map(\.x)
        }
    }

    public struct Page: Equatable, Sendable {
        public var masthead: String
        public var windowLine: String
        public var ticker: [TickerItem]
        public var lead: Story
        public var side: [Story]
        public var decide: [DecideRow]
        public var moreWaiting: Int
        public var river: River
    }

    // MARK: Window

    /// Overnight: since midnight, or the last 12 hours when it is not yet 06:00.
    public static func window(now: Date, calendar: Calendar = .current) -> (start: Date, end: Date) {
        let midnight = calendar.startOfDay(for: now)
        let start = calendar.component(.hour, from: now) < 6 ? now.addingTimeInterval(-12 * 3600) : midnight
        return (start, now)
    }

    // MARK: Results

    public static func isBad(_ r: String) -> Bool { ["fail", "failed", "capped", "error", "stopped", "timeout"].contains(r.lowercased()) }
    public static func isQuiet(_ r: String) -> Bool { ["noop", "skip", "skipped", "nothing", "idle", "no-op"].contains(r.lowercased()) }

    // MARK: Build

    public static func build(_ i: Inputs, calendar: Calendar = .current) -> Page {
        let w = window(now: i.now, calendar: calendar)
        let runs = i.runs.filter { $0.started >= w.start && $0.started <= w.end }
        let moments = i.moments.filter { $0.at >= w.start && $0.at <= w.end }
        let releases = moments.filter { [.releaseFinished, .releaseFailed].contains($0.kind) }
        let sessionsSeen = Set(moments.filter { !$0.session.isEmpty }.map(\.session)).count

        // Masthead
        let df = DateFormatter(); df.calendar = calendar; df.timeZone = calendar.timeZone
        df.locale = Locale(identifier: "en_GB"); df.dateFormat = "EEEE d MMMM"
        let tf = DateFormatter(); tf.calendar = calendar; tf.timeZone = calendar.timeZone; tf.dateFormat = "HH:mm"
        let hour = calendar.component(.hour, from: i.now)
        let part = hour < 12 ? "THE MORNING" : hour < 18 ? "THE AFTERNOON" : "THE EVENING"
        let masthead = "\(part) · \(df.string(from: i.now).uppercased())"
        let windowLine = "\(hour < 6 ? "last 12 h" : "since midnight") \(tf.string(from: w.start)) → \(tf.string(from: w.end)) · "
            + plural(sessionsSeen, "session") + " · " + plural(Set(runs.map(\.loop)).count, "loop") + " · "
            + plural(releases.filter { $0.kind == .releaseFinished }.count, "release")

        let ticker = tickerItems(i)
        var stories = candidateStories(i, runs: runs, moments: moments, releases: releases)
        let lead = stories.isEmpty ? quietStory(runs: runs, i: i) : stories.removeFirst()
        let side = Array(stories.prefix(3))

        let decide = i.asks.prefix(4).map(decideRow)
        let river = makeRiver(start: w.start, end: w.end, runs: runs, moments: moments, asks: i.asks, calendar: calendar)
        return Page(masthead: masthead, windowLine: windowLine, ticker: ticker, lead: lead, side: side, decide: Array(decide),
                    moreWaiting: max(0, i.asks.count - 4), river: river)
    }

    /// A seat figure older than 6 hours is left out (SeatUsage.stale, measured from `now` so the page is testable).
    static func stale(_ s: SeatUsage, _ now: Date) -> Bool { now.timeIntervalSince(s.updated) > 6 * 3600 }

    static func plural(_ n: Int, _ w: String) -> String { "\(n) \(w)\(n == 1 ? "" : "s")" }

    // MARK: Ticker

    static func tickerItems(_ i: Inputs) -> [TickerItem] {
        var out: [TickerItem] = []
        let seats = i.seats.filter { !stale($0, i.now) }
        if !seats.isEmpty {
            let v = seats.map { s -> String in
                let parts = [s.fiveHour.map { "\(Int($0.rounded())) % 5 h" }, s.sevenDay.map { "\(Int($0.rounded())) % week" }].compactMap { $0 }
                return "\(s.seat) " + (parts.isEmpty ? "no figures" : parts.joined(separator: ", "))
            }.joined(separator: " · ")
            let worst = seats.compactMap(\.worst).max() ?? 0
            out.append(TickerItem(label: "Seats", value: v, tone: worst >= 90 ? .bad : worst >= 75 ? .warn : .info))
        } else {
            out.append(TickerItem(label: "Seats", value: "no usage figures yet", tone: .info))
        }
        if let m = i.mac {
            let gb = { (b: UInt64) in String(format: "%.0f", Double(b) / 1_073_741_824) }
            var v = "\(gb(m.used)) / \(gb(m.total)) GB"
            if let d = i.diskFree { v += " · \(d / 1_000_000_000) GB free" }
            let tone: Tone = m.pressure == .critical ? .bad : (m.pressure == .warn || (i.diskFree ?? .max) < 20_000_000_000) ? .warn : .info
            out.append(TickerItem(label: "Mac", value: v, tone: tone))
        } else if let d = i.diskFree {
            out.append(TickerItem(label: "Mac", value: "\(d / 1_000_000_000) GB free", tone: d < 20_000_000_000 ? .warn : .info))
        }
        out.append(TickerItem(label: "Sessions", value: "\(i.liveSessions) open · \(i.working) working", tone: .info))
        if let v = i.version { out.append(TickerItem(label: "One Roof", value: "\(v) running", tone: .info)) }
        return out
    }

    // MARK: Stories (findings, most important first)

    static func candidateStories(_ i: Inputs, runs: [LoopRun], moments: [Moment], releases: [Moment]) -> [Story] {
        var out: [Story] = []
        // 1. Loops that failed overnight.
        let failed = lastPerLoop(runs).filter { isBad($0.result) }
        if let f = failed.first {
            let others = failed.dropFirst().map(\.title)
            let head = failed.count == 1 ? "\(f.title) failed overnight" : "\(failed.count) loops failed overnight: \(f.title) and \(others.count == 1 ? others[0] : "\(others.count) more")"
            let body = (f.summary.isEmpty ? "Its last run ended \(f.result)." : sentence(f.summary))
                + (others.isEmpty ? "" : " Also failed: \(others.joined(separator: ", ")).") + " It will fail again tonight unless the cause or its check changes."
            out.append(Story(kicker: "LEAD · LOOPS", headline: head, body: body, tone: .bad,
                             actions: [Action("Run it again now", .runLoopAgain(f.loop), primary: true), Action("Open the loop", .loops(f.loop))]))
        }
        // 2. A release that failed.
        if let r = releases.last(where: { $0.kind == .releaseFailed }) {
            out.append(Story(kicker: "SHIPPING", headline: "A release failed" + (r.session.isEmpty ? "" : " in \(r.session)"),
                             body: r.text, tone: .bad, actions: [Action("Open History", .history, primary: true)]))
        }
        // 3. Loop items waiting (asks / staged work for your approval).
        let staged = i.asks.filter { $0.kind == .loopStaged || $0.kind == .loopAsks }
        if let s = staged.first {
            let loops = Set(staged.compactMap(\.loopId)).count
            out.append(Story(kicker: "LOOPS", headline: staged.count == 1 ? "\(s.title): \(lower(s.detail.isEmpty ? "waits for your decision" : s.detail))"
                                                                       : "Loops left \(staged.count) things for your approval",
                             body: staged.count == 1 ? "Nothing is merged or applied until you approve it." :
                                "From \(plural(loops, "loop")); first: \(s.title). Nothing is merged or applied until you approve it.",
                             tone: .warn, actions: [Action("Review them", .inbox, primary: true), Action("Open Loops", .loops(s.loopId))]))
        }
        // 4. Releases that shipped.
        let shipped = releases.filter { $0.kind == .releaseFinished }
        if let r = shipped.last {
            out.append(Story(kicker: "SHIPPED OVERNIGHT", headline: shipped.count == 1 ? "Shipped: \(short(r.text, 80))" : "\(shipped.count) releases shipped; last: \(short(r.text, 60))",
                             body: shipped.count > 1 ? shipped.dropLast().map { short($0.text, 60) }.joined(separator: " · ") : (r.session.isEmpty ? "" : "From \(r.session)."),
                             tone: .good, actions: [Action("Open History", .history)]))
        }
        // 5. Projects waiting on you.
        let review = i.issues.filter { $0.state.lowercased().contains("review") }
        let blocked = i.issues.filter { $0.state.lowercased().contains("block") }
        if !review.isEmpty || !blocked.isEmpty {
            var parts: [String] = []
            if !review.isEmpty { parts.append("\(review.count) in review") }
            if !blocked.isEmpty { parts.append("\(blocked.count) blocked") }
            let first = (blocked.first ?? review.first)!
            out.append(Story(kicker: "PROJECTS", headline: "\(parts.joined(separator: ", ")) wait on you",
                             body: "\(first.identifier) \(first.title) (\(first.state))" + ((review + blocked).count > 1 ? " and \((review + blocked).count - 1) more." : "."),
                             tone: blocked.isEmpty ? .warn : .bad, actions: [Action("Open Projects", .projects)]))
        }
        // 6. Your sessions overnight: errors first, then findings and handoffs.
        let errors = moments.filter { $0.kind == .error }
        let findings = moments.filter { $0.kind == .finding }
        let handoffs = moments.filter { $0.kind == .handoffWritten || $0.kind == .rotated }
        if let e = errors.last {
            out.append(Story(kicker: "YOUR SESSIONS", headline: errors.count == 1 ? "\(e.session.isEmpty ? "A session" : e.session) hit an error" : "\(errors.count) errors in your sessions",
                             body: short(e.text, 220), tone: .warn, actions: [Action("Open History", .history)]))
        } else if let f = findings.last {
            out.append(Story(kicker: "YOUR SESSIONS", headline: short(f.text, 90),
                             body: (findings.count > 1 ? "One of \(findings.count) findings" : "A finding") + (f.session.isEmpty ? "." : " in \(f.session).")
                                + (handoffs.isEmpty ? "" : " \(plural(handoffs.count, "handoff")) written."),
                             tone: .info, actions: [Action("Open History", .history)]))
        } else if !handoffs.isEmpty {
            out.append(Story(kicker: "YOUR SESSIONS", headline: "\(plural(handoffs.count, "handoff")) written",
                             body: short(handoffs.last!.text, 200), tone: .info, actions: [Action("Open History", .history)]))
        }
        // 7. Seats close to a limit.
        if let s = i.seats.filter({ !stale($0, i.now) && ($0.worst ?? 0) >= 75 }).max(by: { ($0.worst ?? 0) < ($1.worst ?? 0) }) {
            let week = (s.sevenDay ?? 0) >= (s.fiveHour ?? 0)
            let pct = Int((s.worst ?? 0).rounded())
            let resets = week ? s.sevenDayResets : s.fiveHourResets
            out.append(Story(kicker: "SEATS", headline: "\(s.seat) is at \(pct) % of its \(week ? "weekly" : "5-hour") window",
                             body: "Route new work to another seat" + (resets.map { "; it resets \(relative($0, from: i.now))." } ?? "."),
                             tone: pct >= 90 ? .bad : .warn, actions: [Action("Open Sessions", .sessions)]))
        }
        // 8. The Mac.
        if let m = i.mac, m.pressure != .normal || m.swapUsed > 4 << 30 {
            out.append(Story(kicker: "MAC", headline: m.pressure == .critical ? "The Mac is out of memory" : "The Mac is short of memory",
                             body: "\(m.used >> 30) of \(m.total >> 30) GB in use, \(m.swapUsed >> 30) GB swapped. Resources shows what holds it.",
                             tone: m.pressure == .critical ? .bad : .warn, actions: [Action("Open Resources", .machine)]))
        } else if let d = i.diskFree, d < 20_000_000_000 {
            out.append(Story(kicker: "MAC", headline: "Only \(d / 1_000_000_000) GB free on this Mac", body: "Builds and downloads may fail below 10 GB.",
                             tone: .warn, actions: [Action("Open Resources", .machine)]))
        }
        // 9. Loops that ran but did nothing.
        let quiet = lastPerLoop(runs).filter { isQuiet($0.result) }
        if !quiet.isEmpty {
            out.append(Story(kicker: "LOOPS", headline: quiet.count == 1 ? "\(quiet[0].title) ran and did nothing" : "\(quiet.count) loops you switched on did nothing",
                             body: quiet.map { $0.title + ($0.summary.isEmpty ? "" : ": " + short($0.summary, 80)) }.joined(separator: "; ") + ".",
                             tone: .warn, actions: [Action("Open Loops", .loops(quiet[0].loop))]))
        }
        return out
    }

    static func quietStory(runs: [LoopRun], i: Inputs) -> Story {
        let clean = lastPerLoop(runs)
        if clean.isEmpty {
            return Story(kicker: "LEAD", headline: i.asks.isEmpty ? "A quiet night: nothing ran and nothing waits for you" : "Nothing ran overnight",
                         body: "No loop ran and no session left a finding, error or release since the window opened. Loops you switch on show here the morning after.",
                         tone: .info, actions: [Action("Open Loops", .loops(nil))])
        }
        return Story(kicker: "LEAD · LOOPS", headline: "A clean night: \(plural(clean.count, "loop")) ran without a failure",
                     body: clean.prefix(6).map(\.title).joined(separator: ", ") + (clean.count > 6 ? " and \(clean.count - 6) more." : "."),
                     tone: .good, actions: [Action("Open Loops", .loops(nil))])
    }

    static func decideRow(_ a: Ask) -> DecideRow {
        switch a.kind {
        case .question: return DecideRow(id: a.id, tag: "ANSWER", text: "\(a.title): \(a.detail)", action: Action("Answer", a.sessionId.map(Target.session) ?? .inbox, primary: true))
        case .permission: return DecideRow(id: a.id, tag: "GO?", text: "\(a.title): \(a.detail)", action: Action("Decide", .inbox, primary: true))
        case .finished: return DecideRow(id: a.id, tag: "SIGN OFF", text: "\(a.title) finished: \(a.detail)", action: Action("Open it", a.sessionId.map(Target.session) ?? .inbox))
        case .plan: return DecideRow(id: a.id, tag: "PLAN", text: "\(a.title): a plan waits for your approval", action: Action("Review", .inbox))
        case .loopFailed: return DecideRow(id: a.id, tag: "LOOK", text: "\(a.title): \(a.detail)", action: Action("Open", .loops(a.loopId)))
        case .loopAsks: return DecideRow(id: a.id, tag: "ANSWER", text: "\(a.title): \(a.detail)", action: Action("Open", .loops(a.loopId)))
        case .loopStaged: return DecideRow(id: a.id, tag: "REVIEW", text: "\(a.title): \(a.detail)", action: Action("Review", .inbox))
        }
    }

    /// The latest run of each loop, in the order the loops last ran.
    static func lastPerLoop(_ runs: [LoopRun]) -> [LoopRun] {
        var last: [String: LoopRun] = [:]
        for r in runs { if (last[r.loop]?.started ?? .distantPast) <= r.started { last[r.loop] = r } }
        return last.values.sorted { $0.started < $1.started }
    }

    static func short(_ s: String, _ n: Int) -> String {
        let one = s.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespaces)
        return one.count <= n ? one : String(one.prefix(n - 1)) + "…"
    }

    /// A summary as a sentence (ends with . ! ? or …), so the next sentence joins cleanly.
    static func sentence(_ s: String) -> String {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let last = t.last else { return t }
        return ".!?…".contains(last) ? t : t + "."
    }

    static func lower(_ s: String) -> String { s.prefix(1).lowercased() + s.dropFirst() }

    static func relative(_ d: Date, from now: Date) -> String {
        let h = Int(d.timeIntervalSince(now) / 3600)
        if h < 1 { return "within the hour" }
        if h < 24 { return "in \(h) h" }
        return "in \(h / 24) day\(h / 24 == 1 ? "" : "s")"
    }

    // MARK: River

    /// Marks closer than this (share of the width) merge into one ("a · b", or "a +2").
    public static let mergeGap = 0.035

    public static func makeRiver(start: Date, end: Date, runs: [LoopRun], moments: [Moment], asks: [Ask], calendar: Calendar = .current) -> River {
        let span = max(end.timeIntervalSince(start), 60)
        func x(_ d: Date) -> Double { min(1, max(0, d.timeIntervalSince(start) / span)) }
        let mine = moments.filter { [.finding, .done, .handoffWritten, .rotated, .error, .sessionStarted].contains($0.kind) }
        let sessionMarks = mine.map { m in
            Mark(id: "s\(m.at.timeIntervalSince1970)\(m.session)", x: x(m.at), label: m.session.isEmpty ? m.kind.rawValue : short(m.session, 22),
                 tone: m.kind == .error ? .bad : .info, count: 1)
        }
        let loopMarks = runs.map { r in
            Mark(id: "l\(r.loop)\(r.started.timeIntervalSince1970)", x: x(r.started), label: short(r.title, 22),
                 tone: isBad(r.result) ? .bad : isQuiet(r.result) ? .warn : .good, count: 1)
        }
        let releaseMarks = moments.filter { [.releaseFinished, .releaseFailed].contains($0.kind) }.map { m in
            Mark(id: "r\(m.at.timeIntervalSince1970)", x: x(m.at), label: short(releaseName(m.text), 22), tone: m.kind == .releaseFailed ? .bad : .good, count: 1)
        }
        let askMarks = asks.filter { $0.at >= start && $0.at <= end }.map { a in
            Mark(id: "a\(a.id)", x: x(a.at), label: short(a.title, 22), tone: .warn, count: 1)
        }
        var lanes = [Lane(name: "Your sessions", marks: declutter(merge(sessionMarks))), Lane(name: "Loops", marks: declutter(merge(loopMarks))),
                     Lane(name: "Releases", marks: declutter(merge(releaseMarks)))]
        if !askMarks.isEmpty { lanes.append(Lane(name: "Asked you", marks: declutter(merge(askMarks)))) }
        // Hour ticks: every 2 h (every hour on a short window, every 4 h on a long one).
        let hours = span / 3600
        let step = hours <= 4 ? 1 : hours <= 12 ? 2 : 4
        var ticks: [(x: Double, label: String)] = []
        var t = calendar.dateInterval(of: .hour, for: start)?.start ?? start
        if t < start { t = t.addingTimeInterval(3600) }
        let tf = DateFormatter(); tf.calendar = calendar; tf.timeZone = calendar.timeZone; tf.dateFormat = "HH:mm"
        while t <= end {
            if calendar.component(.hour, from: t) % step == 0 { ticks.append((x(t), tf.string(from: t))) }
            t = t.addingTimeInterval(3600)
        }
        return River(start: start, end: end, lanes: lanes, ticks: ticks)
    }

    /// Merge marks closer than `mergeGap`: the worst tone wins, labels join ("a · b" or "a +2").
    public static func merge(_ marks: [Mark]) -> [Mark] {
        var out: [Mark] = []
        var group: [Mark] = []
        func flush() {
            guard let first = group.first else { return }
            let names = group.map(\.label).reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }
            let label = names.count <= 2 ? names.joined(separator: " · ") : "\(names[0]) +\(names.count - 1)"
            let tone: Tone = group.contains { $0.tone == .bad } ? .bad : group.contains { $0.tone == .warn } ? .warn : first.tone
            out.append(Mark(id: first.id, x: group.map(\.x).reduce(0, +) / Double(group.count), label: label, tone: tone,
                            count: group.reduce(0) { $0 + $1.count }))
            group = []
        }
        for m in marks.sorted(by: { $0.x < $1.x }) {
            if let f = group.first, m.x - f.x > mergeGap { flush() }
            group.append(m)
        }
        flush()
        return out
    }

    /// Labels closer than this (share of the width) to the last drawn one are left off.
    public static let labelGap = 0.06

    /// Draw a label only when it is far enough from the last drawn one and says something new (the same session's
    /// name again within a quarter of the window is left off); bad marks always keep theirs.
    public static func declutter(_ marks: [Mark]) -> [Mark] {
        var lastX = -1.0, lastLabel = ""
        return marks.map { m in
            var m = m
            let repeated = m.label == lastLabel && m.x - lastX < 0.25
            m.shown = m.tone == .bad || (m.x - lastX >= labelGap && !repeated)
            if m.shown { lastX = m.x; lastLabel = m.label }
            return m
        }
    }

    /// "bash …/release.sh 1.9.37" → "release 1.9.37"; anything else shortened.
    static func releaseName(_ text: String) -> String {
        let words = text.split(separator: " ").map(String.init)
        if let v = words.last(where: { $0.first?.isNumber == true && $0.contains(".") }) { return "release \(v)" }
        return text
    }
}
