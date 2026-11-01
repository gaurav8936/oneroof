import Foundation

// LAB-2044 · LAB-2045 · LAB-2046 · History (⌃⌘9): the read-only record of every session's important moments, newest
// first. Moments come from the store (feed, decisions, handover events, 30 days), so sessions that closed or were
// deleted keep theirs, with their name from `history_sessions`. This file holds the rules (kinds and their look,
// filters, sort, dates, the handover signals); UI/V2/V2History.swift only draws them.

/// A session as History remembers it: written when it starts and when it is renamed, kept after it is deleted.
public struct HistorySession: Codable, Equatable, Sendable {
    public var id: String
    public var name: String
    public var agent: AgentKind
    public var account: String?
    public var isLoop: Bool
    public var firstAt: Date?
    public var lastAt: Date?
    public init(id: String, name: String, agent: AgentKind, account: String? = nil, isLoop: Bool = false, firstAt: Date? = nil, lastAt: Date? = nil) {
        self.id = id; self.name = name; self.agent = agent; self.account = account; self.isLoop = isLoop; self.firstAt = firstAt; self.lastAt = lastAt
    }
}

/// A handover moment that is not in the FYI feed (stored in `history_events`).
public struct HistoryEvent: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var at: Date
    public var sessionId: String
    public var kind: ScrollEntry.Kind
    public var text: String
    public init(id: String, at: Date, sessionId: String, kind: ScrollEntry.Kind, text: String) {
        self.id = id; self.at = at; self.sessionId = sessionId; self.kind = kind; self.text = text
    }
}

// MARK: Kinds and their look (LAB-2045)

/// The colour a kind's word is drawn in, as a token role (the view resolves it in its panel theme).
public enum HistoryColour: String, Sendable { case needs, errorText, accent, text2, done, now, handover }

/// How a row is set apart: a 3 pt bar on its left, a tinted fill, or a centred divider (handovers).
public enum HistoryTreatment: Equatable, Sendable { case plain, bar(HistoryColour), errorFill, divider }

public struct HistoryStyle: Equatable, Sendable {
    public var glyph: String
    public var word: String
    public var colour: HistoryColour
    public var treatment: HistoryTreatment
}

public enum HistoryKindGroup: String, CaseIterable, Codable, Sendable {
    case asks, answers, errors, done, found, steps, handovers
    public var title: String {
        switch self {
        case .asks: return "Asks"; case .answers: return "Your answers"; case .errors: return "Errors"; case .done: return "Done"
        case .found: return "Found"; case .steps: return "Steps"; case .handovers: return "Handovers"
        }
    }
    /// What the group holds, shown under its name in the Kind menu.
    public var detail: String {
        switch self {
        case .asks: return "Asks you, Question, Finished"; case .answers: return "What you answered"; case .errors: return "Error"
        case .done: return "Done"; case .found: return "Found"; case .steps: return "Step, Chose, Subagents"
        case .handovers: return "Session started or closed, handed off, handoff written, release"
        }
    }
    public func matches(_ e: ScrollEntry) -> Bool {
        switch self {
        case .asks: return [.ask, .question, .finished].contains(e.kind)
        case .answers: return e.answer != nil
        case .errors: return e.kind == .error || e.kind == .releaseFailed
        case .done: return e.kind == .done
        case .found: return e.kind == .finding
        case .steps: return [.step, .choice, .subagents].contains(e.kind)
        case .handovers: return e.kind.isHandover
        }
    }
}

extension ScrollEntry.Kind {
    /// Session started / closed, handed off, handoff written, release started / finished (LAB-2046).
    public var isHandover: Bool {
        [.sessionStarted, .sessionClosed, .rotated, .handoffWritten, .releaseStarted, .releaseFinished, .releaseFailed].contains(self)
    }

    /// Colour + glyph + word for every kind, so colour is never the only cue (LAB-2045).
    public var style: HistoryStyle {
        switch self {
        case .error: return HistoryStyle(glyph: "✕", word: "Error", colour: .errorText, treatment: .errorFill)
        case .ask: return HistoryStyle(glyph: "?", word: "Asks you", colour: .accent, treatment: .bar(.accent))
        case .question: return HistoryStyle(glyph: "?", word: "Question", colour: .accent, treatment: .bar(.accent))
        case .finished: return HistoryStyle(glyph: "◆", word: "Finished", colour: .accent, treatment: .bar(.accent))
        case .done: return HistoryStyle(glyph: "✓", word: "Done", colour: .done, treatment: .plain)
        case .finding: return HistoryStyle(glyph: "★", word: "Found", colour: .now, treatment: .plain)
        case .step: return HistoryStyle(glyph: "•", word: "Step", colour: .text2, treatment: .plain)
        case .choice: return HistoryStyle(glyph: "•", word: "Chose", colour: .text2, treatment: .plain)
        case .subagents: return HistoryStyle(glyph: "⋔", word: "Subagents", colour: .text2, treatment: .plain)
        case .sessionStarted: return HistoryStyle(glyph: "▶", word: "Session started", colour: .handover, treatment: .divider)
        case .sessionClosed: return HistoryStyle(glyph: "■", word: "Session closed", colour: .handover, treatment: .divider)
        case .rotated: return HistoryStyle(glyph: "↪", word: "Handed off", colour: .handover, treatment: .divider)
        case .handoffWritten: return HistoryStyle(glyph: "✎", word: "Handoff written", colour: .handover, treatment: .divider)
        case .releaseStarted: return HistoryStyle(glyph: "⇡", word: "Release started", colour: .handover, treatment: .divider)
        case .releaseFinished: return HistoryStyle(glyph: "✓", word: "Release finished", colour: .handover, treatment: .divider)
        case .releaseFailed: return HistoryStyle(glyph: "✕", word: "Release failed", colour: .needs, treatment: .divider)
        }
    }

    /// The "You" row under an answered ask.
    public static let answerStyle = HistoryStyle(glyph: "↩", word: "You", colour: .text2, treatment: .plain)
}

extension HistoryColour {
    /// The colour in a panel theme (tokens only; `statusDone` and `scheduledPill` as the rest of the app draws them).
    public func rgb(_ k: ThemeTokens) -> RGB {
        switch self {
        case .needs: return k.needsText
        case .errorText: return k.diffDelText   // red that holds 4.5:1 on the tinted error row (needsText was 4.37:1 in Graphite)
        case .accent: return k.accentText
        case .text2: return k.text2
        case .done: return k.statusDone
        case .now: return k.now
        case .handover: return StatusPalette.scheduledPill(theme: k.name).text
        }
    }
    /// A 3 pt bar's colour (the accent itself, not its text tint; needs keeps its red).
    public func bar(_ k: ThemeTokens) -> RGB { self == .accent ? k.accent : rgb(k) }
}

extension ThemeTokens {
    /// A card or field on a panel: Daylight's surface is the window colour, so cards there use surface2.
    public var card: RGB { isDark ? surface : surface2 }
    /// Done / allowed green (v0.1 status token name).
    public var statusDone: RGB { isDark ? StatusPalette.dot(.done) : diffAddText }
    /// An error row's fill (LAB-2045): the diff's delete tint over the card.
    public var historyErrorFill: RGB { diffDelFill.over(card) }
    /// A hovered row: the selection token at 50 % over the card (keyboard focus and hover; pressed is the full token).
    public var rowHover: RGB { RGB(selection.over(card).hex, alpha: 0.5).over(card) }
}

// MARK: Dates (LAB-2046)

public enum HistoryRange: Equatable, Codable, Sendable {
    case today, yesterday, last7, last30
    case custom(from: Date, to: Date)

    public static let presets: [HistoryRange] = [.today, .yesterday, .last7, .last30]
    public var title: String {
        switch self {
        case .today: return "Today"; case .yesterday: return "Yesterday"; case .last7: return "Last 7 days"; case .last30: return "Last 30 days"
        case .custom(let f, let t): return HistoryFormat.day(f) + " – " + HistoryFormat.day(t)
        }
    }
    public var isDefault: Bool { self == .last7 }

    /// [from, to) for the range. Custom days are inclusive of both ends.
    public func bounds(now: Date = Date(), calendar: Calendar = .current) -> (from: Date, to: Date) {
        let today = calendar.startOfDay(for: now)
        func day(_ n: Int, _ d: Date = today) -> Date { calendar.date(byAdding: .day, value: n, to: d) ?? d }
        switch self {
        case .today: return (today, day(1))
        case .yesterday: return (day(-1), today)
        case .last7: return (day(-6), day(1))
        case .last30: return (day(-29), day(1))
        case .custom(let f, let t):
            let a = calendar.startOfDay(for: min(f, t)), b = calendar.startOfDay(for: max(f, t))
            return (a, day(1, b))
        }
    }
    public func contains(_ d: Date, now: Date = Date(), calendar: Calendar = .current) -> Bool {
        let b = bounds(now: now, calendar: calendar)
        return d >= b.from && d < b.to
    }
}

public enum HistoryOrder: String, Codable, CaseIterable, Sendable {
    case newestFirst, oldestFirst
    public var title: String { self == .newestFirst ? "Newest first" : "Oldest first" }
}

public enum HistoryFormat {
    /// "Sat 31 Oct · 23:06" (12 or 24 h as the system says).
    public static func stamp(_ d: Date, locale: Locale = .current, timeZone: TimeZone = .current) -> String {
        day(d, locale: locale, timeZone: timeZone) + " · " + time(d, locale: locale, timeZone: timeZone)
    }
    /// "Sat 31 Oct".
    public static func day(_ d: Date, locale: Locale = .current, timeZone: TimeZone = .current) -> String {
        let f = DateFormatter(); f.locale = locale; f.timeZone = timeZone
        f.setLocalizedDateFormatFromTemplate("EEEdMMM")
        return f.string(from: d).replacingOccurrences(of: ",", with: "")
    }
    public static func time(_ d: Date, locale: Locale = .current, timeZone: TimeZone = .current) -> String {
        let f = DateFormatter(); f.locale = locale; f.timeZone = timeZone
        f.timeStyle = .short; f.dateStyle = .none
        return f.string(from: d)
    }
    /// The tooltip: the full timestamp with seconds.
    public static func full(_ d: Date, locale: Locale = .current, timeZone: TimeZone = .current) -> String {
        let f = DateFormatter(); f.locale = locale; f.timeZone = timeZone
        f.dateStyle = .full; f.timeStyle = .medium
        return f.string(from: d)
    }
    /// A sticky day header: "Today", "Yesterday", or "Thu 29 Oct".
    public static func dayHeader(_ d: Date, now: Date = Date(), calendar: Calendar = .current) -> String {
        if calendar.isDate(d, inSameDayAs: now) { return "Today" }
        if let y = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(d, inSameDayAs: y) { return "Yesterday" }
        return day(d, timeZone: calendar.timeZone)
    }
    /// VoiceOver: "<time>, <kind>, <session>: <text>" (the word, never the glyph).
    public static func accessibility(_ e: ScrollEntry, session: String) -> String {
        var s = "\(stamp(e.at)), \(e.kind.style.word), \(session): \(e.text)"
        if let a = e.answer { s += ". You answered: " + a }
        if e.needsInput { s += ". Waiting in the Inbox" }
        return s
    }
    /// "128 moments · 6 sessions".
    public static func resultLine(moments: Int, sessions: Int) -> String {
        moments == 0 ? "No moments match." : "\(moments) moment\(moments == 1 ? "" : "s") · \(sessions) session\(sessions == 1 ? "" : "s")"
    }
    /// Page subtitle: "<n> sessions · <m> moments · newest first".
    public static func subtitle(sessions: Int, moments: Int, order: HistoryOrder) -> String {
        "\(sessions) session\(sessions == 1 ? "" : "s") · \(moments) moment\(moments == 1 ? "" : "s") · " + order.title.lowercased()
    }
    /// The "N new ↑" pill when you have scrolled down and moments arrived at the top.
    public static func newPill(_ n: Int) -> String { "\(n) new ↑" }
    /// A closed or deleted session's name.
    public static func closedName(_ name: String) -> String { name + " (closed)" }
}

// MARK: The query (LAB-2046)

/// Search, sort and filters. Filters and sort are remembered per window; the search text is not.
public struct HistoryQuery: Equatable, Codable, Sendable {
    public var text: String = ""
    public var sessions: Set<String> = []
    public var agents: Set<AgentKind> = []
    public var kinds: Set<HistoryKindGroup> = []
    public var range: HistoryRange = .last7
    public var order: HistoryOrder = .newestFirst

    public init(text: String = "", sessions: Set<String> = [], agents: Set<AgentKind> = [], kinds: Set<HistoryKindGroup> = [],
                range: HistoryRange = .last7, order: HistoryOrder = .newestFirst) {
        self.text = text; self.sessions = sessions; self.agents = agents; self.kinds = kinds; self.range = range; self.order = order
    }

    enum CodingKeys: String, CodingKey { case sessions, agents, kinds, range, order }   // text is not remembered

    /// Any filter beyond the defaults (the chips row and Clear all).
    public var isFiltered: Bool { !sessions.isEmpty || !agents.isEmpty || !kinds.isEmpty || !range.isDefault }
    public mutating func clearFilters() { sessions = []; agents = []; kinds = []; range = .last7 }

    /// The matching moments in order. `session` resolves a session id to what History knows of it.
    public func apply(_ entries: [ScrollEntry], session: (String) -> HistorySession?, now: Date = Date(), calendar: Calendar = .current) -> [ScrollEntry] {
        let b = range.bounds(now: now, calendar: calendar)
        let needle = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        var out = entries.filter { e in
            guard e.at >= b.from, e.at < b.to else { return false }
            if !sessions.isEmpty, !sessions.contains(e.sessionId) { return false }
            if !agents.isEmpty { guard let a = session(e.sessionId)?.agent, agents.contains(a) else { return false } }
            if !kinds.isEmpty, !kinds.contains(where: { $0.matches(e) }) { return false }
            if !needle.isEmpty {
                let hay = e.text.lowercased()
                if !hay.contains(needle), !(e.answer?.lowercased().contains(needle) ?? false),
                   !(session(e.sessionId)?.name.lowercased().contains(needle) ?? false) { return false }
            }
            return true
        }
        out.sort { a, b in
            if a.at == b.at { return order == .newestFirst ? a.id > b.id : a.id < b.id }
            return order == .newestFirst ? a.at > b.at : a.at < b.at
        }
        return out
    }

    /// The chips under the bar ("Session: oneroof-1937", "Kind: Errors"), each with what removing it does.
    public func chips(session: (String) -> String) -> [(label: String, remove: HistoryChip)] {
        var out: [(String, HistoryChip)] = []
        for s in sessions.sorted(by: { session($0) < session($1) }) { out.append(("Session: " + session(s), .session(s))) }
        for a in agents.sorted(by: { $0.displayName < $1.displayName }) { out.append(("Agent: " + a.displayName, .agent(a))) }
        for k in HistoryKindGroup.allCases where kinds.contains(k) { out.append(("Kind: " + k.title, .kind(k))) }
        if !range.isDefault { out.append(("Date: " + range.title, .range)) }
        return out
    }

    public mutating func remove(_ c: HistoryChip) {
        switch c {
        case .session(let s): sessions.remove(s)
        case .agent(let a): agents.remove(a)
        case .kind(let k): kinds.remove(k)
        case .range: range = .last7
        }
    }
}

public enum HistoryChip: Equatable, Sendable {
    case session(String), agent(AgentKind), kind(HistoryKindGroup), range
}

/// A run of one session's moments in the list (each is drawn as its own card).
public struct HistoryGroup: Identifiable, Equatable, Sendable {
    public var id: String
    public var sessionId: String
    public var day: Date
    public var entries: [ScrollEntry]
}

public struct HistoryDay: Identifiable, Equatable, Sendable {
    public var id: String
    public var day: Date
    public var groups: [HistoryGroup]
}

public enum HistoryPaging {
    /// Rows per page: the list shows this many more each time you near its end.
    public static let pageSize = 500

    /// Days (sticky headers) holding runs of one session's moments, in the list's order.
    public static func days(_ entries: [ScrollEntry], calendar: Calendar = .current) -> [HistoryDay] {
        var out: [HistoryDay] = []
        for e in entries {
            let d = calendar.startOfDay(for: e.at)
            if out.last?.day != d { out.append(HistoryDay(id: "day-\(d.timeIntervalSince1970)", day: d, groups: [])) }
            if out[out.count - 1].groups.last?.sessionId == e.sessionId {
                out[out.count - 1].groups[out[out.count - 1].groups.count - 1].entries.append(e)
            } else {
                out[out.count - 1].groups.append(HistoryGroup(id: "grp-" + e.id, sessionId: e.sessionId, day: d, entries: [e]))
            }
        }
        return out
    }
}

// MARK: Building the moments

public enum HistoryFeed {
    /// How long History keeps moments (LAB-2046: 30 days, was 7).
    public static let retentionDays = 30

    /// Every moment, oldest first: feed events, finished steps (chapters, for sessions that have them), asks with your
    /// answers, and handover events. `isLoop` says whether a session is a loop round (nil = unknown, kept: a session
    /// that was deleted still shows). Loop rounds stay out (LAB-1933).
    public static func entries(feed: [FeedEvent], chapters: [String: [Chapter]], decisions: [Decision], events: [HistoryEvent],
                               isLoop: (String) -> Bool?) -> [ScrollEntry] {
        var known: [String: Bool] = [:]
        func shown(_ id: String) -> Bool {
            if let k = known[id] { return k }
            let ok = !(isLoop(id) ?? false)
            known[id] = ok
            return ok
        }
        var out: [ScrollEntry] = []
        var seen = Set<String>()
        func add(_ e: ScrollEntry) { if seen.insert(e.id).inserted { out.append(e) } }
        for e in feed where shown(e.sessionId) {
            if e.kind == .stepDone, chapters[e.sessionId]?.isEmpty == false { continue }
            add(ScrollEntry(id: "feed-" + e.id.uuidString, at: e.at, sessionId: e.sessionId, kind: ScrollFeed.kind(e.kind), text: e.text, open: false))
        }
        for (sid, chs) in chapters where shown(sid) {
            for c in chs {
                guard let ended = c.ended else { continue }
                let summary = c.summary.trimmingCharacters(in: .whitespacesAndNewlines)
                add(ScrollEntry(id: "step-\(sid)-\(c.index)", at: ended, sessionId: sid, kind: .step,
                                text: summary.isEmpty ? c.title : c.title + " · " + summary, open: false))
            }
        }
        for d in decisions where shown(d.sessionId) {
            let k: ScrollEntry.Kind = d.isFinished ? .finished : d.isQuestion || d.isMenu ? .question : .ask
            add(ScrollEntry(id: "ask-" + d.id.uuidString, at: d.askedAt, sessionId: d.sessionId, kind: k,
                            text: ScrollFeed.askText(d), decisionId: d.id, open: d.isOpen, answer: ScrollFeed.answerText(d), answeredAt: d.answeredAt))
        }
        for e in events where shown(e.sessionId) {
            add(ScrollEntry(id: "hist-" + e.id, at: e.at, sessionId: e.sessionId, kind: e.kind, text: e.text, open: false))
        }
        out.sort { $0.at == $1.at ? $0.id < $1.id : $0.at < $1.at }
        return out
    }
}

// MARK: Handover signals (LAB-2046)

public enum HistorySignals {
    /// Folders a handoff is written to.
    public static let handoffFolders = ["/next-session-handoff/", "/next-steps/"]
    /// Commands that start a release or a ship.
    public static let releaseCommands = ["oneroof-release", "cicd-trace.sh", "ship-domain", "oneroof-install.sh"]

    public static func isHandoff(path: String) -> Bool { handoffFolders.contains { path.contains($0) } }

    public static func releaseCommand(_ command: String) -> String? {
        releaseCommands.first { command.contains($0) }
    }

    public struct Release: Equatable, Sendable {
        public var command: String
        /// nil = still running (no later tool call or end of turn yet).
        public var ok: Bool?
    }

    /// Handoffs written and releases run in a session's terminal text (its tool calls). A release has finished when a
    /// later tool call follows it or the turn ended (`finished`); it failed when a line between says so.
    public static func scan(_ text: String, finished: Bool) -> (handoffs: [String], releases: [Release]) {
        let lines = TerminalText.lines(text)
        let calls = CaptionEngine.toolCalls(in: lines)
        var handoffs: [String] = []
        var releases: [Release] = []
        for (n, c) in calls.enumerated() {
            if c.kind == .edit, isHandoff(path: c.path) { handoffs.append(c.path) }
            if c.kind == .bash, let _ = releaseCommand(c.argument) {
                let end = n + 1 < calls.count ? calls[n + 1].line : (finished ? lines.count : nil)
                var ok: Bool?
                if let end {
                    let between = lines[min(c.line + 1, lines.count)..<min(max(end, c.line + 1), lines.count)]
                    ok = !between.contains { failed($0) }
                }
                releases.append(Release(command: c.argument, ok: ok))
            }
        }
        return (handoffs, releases)
    }

    static func failed(_ line: String) -> Bool {
        let l = line.lowercased()
        return l.range(of: #"exit code [1-9]"#, options: .regularExpression) != nil || l.contains("error:") || l.contains("✗") || l.contains(" failed")
    }

    /// A stable id, so seeing the same call again on the next tick records nothing new.
    public static func eventId(_ sessionId: String, _ kind: ScrollEntry.Kind, _ key: String) -> String {
        var h: UInt64 = 1469598103934665603
        for b in (sessionId + "|" + kind.rawValue + "|" + key).utf8 { h = (h ^ UInt64(b)) &* 1099511628211 }
        return "\(kind.rawValue)-\(String(h, radix: 16))"
    }
}
