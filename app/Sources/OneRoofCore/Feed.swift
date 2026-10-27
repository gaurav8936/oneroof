import Foundation

// The FYI feed (v2, ENGINES §2): what happened across all windows, newest first. It never asks for input; anything
// that needs a reply becomes a Decision instead. 200 events in memory, 7 days in SQLite (SessionStore.pruneFeed).

public enum FeedKind: String, Codable, CaseIterable, Sendable {
    case stepDone, finding, choice, subagents, done, rotated, error

    /// The model's event names ("step finished", "subagents started", …) → a kind.
    public init?(modelName: String) {
        let n = modelName.lowercased().filter { $0.isLetter }
        switch n {
        case "stepdone", "stepfinished", "step": self = .stepDone
        case "finding", "found": self = .finding
        case "choice", "decision", "chose": self = .choice
        case "subagents", "subagent", "subagentsstarted", "subagentstarted": self = .subagents
        case "done", "finished": self = .done
        case "rotated", "rotation", "handedoff": self = .rotated
        case "error", "failed", "failure": self = .error
        default: return nil
        }
    }
}

public struct FeedEvent: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var at: Date
    public var sessionId: String
    public var kind: FeedKind
    public var text: String
    /// The chapter that produced it, so a click opens the session scrolled there.
    public var chapter: Int?

    public init(id: UUID = UUID(), at: Date = Date(), sessionId: String, kind: FeedKind, text: String, chapter: Int? = nil) {
        self.id = id; self.at = at; self.sessionId = sessionId; self.kind = kind; self.text = text; self.chapter = chapter
    }
}

/// The in-memory feed: newest first, de-duplicated (same kind + session within 60 s), capped at 200, with mutes.
/// Muting hides; un-muting brings the events back.
public struct FeedBuffer: Sendable {
    public static let capacity = 200
    public static let dedupWindow: TimeInterval = 60

    public private(set) var events: [FeedEvent] = []
    public private(set) var mutedSessions: Set<String> = []
    /// Workspace (window) ids muted from the Overview rail.
    public private(set) var mutedWindows: Set<String> = []

    public init(events: [FeedEvent] = []) {
        for e in events.sorted(by: { $0.at < $1.at }) { add(e) }
    }

    /// Adds an event unless the same kind for the same session arrived within 60 s. Returns whether it was added.
    /// LAB-659: an event that only repeats the session's latest one (same kind, same words, e.g. "X finished" every
    /// few minutes while a session with background agents wakes and rests) replaces it, so the feed shows it once,
    /// at its newest time, instead of a column of copies.
    @discardableResult
    public mutating func add(_ e: FeedEvent) -> Bool {
        if events.contains(where: { $0.sessionId == e.sessionId && $0.kind == e.kind && abs($0.at.timeIntervalSince(e.at)) < Self.dedupWindow }) {
            return false
        }
        if let j = events.firstIndex(where: { $0.sessionId == e.sessionId }), events[j].at <= e.at,
           events[j].kind == e.kind, events[j].text == e.text {
            events.remove(at: j)
        }
        let i = events.firstIndex(where: { $0.at <= e.at }) ?? events.count
        events.insert(e, at: i)
        if events.count > Self.capacity { events.removeLast(events.count - Self.capacity) }
        return true
    }

    public mutating func mute(session: String) { mutedSessions.insert(session) }
    public mutating func unmute(session: String) { mutedSessions.remove(session) }
    public mutating func mute(window: String) { mutedWindows.insert(window) }
    public mutating func unmute(window: String) { mutedWindows.remove(window) }
    public func isMuted(session: String, window: String?) -> Bool {
        mutedSessions.contains(session) || window.map { mutedWindows.contains($0) } ?? false
    }

    /// What the rail shows: newest first, mutes applied. `windowOf` maps a session to its workspace id.
    public func visible(windowOf: (String) -> String? = { _ in nil }, limit: Int = FeedBuffer.capacity) -> [FeedEvent] {
        Array(events.filter { !isMuted(session: $0.sessionId, window: windowOf($0.sessionId)) }.prefix(limit))
    }

    public mutating func removeAll(session: String) { events.removeAll { $0.sessionId == session } }
}

/// Feed events from hard signals: runtime status changes, plan steps, subagents, rotation, schedule runs.
public enum FeedSignals {
    /// A status change → events. Blocked is not here: it becomes a Decision.
    public static func statusChange(from old: SessionStatus?, to new: SessionStatus, sessionId: String, name: String,
                                    caption: Caption? = nil, chapter: Int? = nil, at: Date = Date()) -> [FeedEvent] {
        guard old != new else { return [] }
        switch (old, new) {
        case (.some(.running), .done), (.some(.needsYou), .done):
            var text = "\(name) finished"
            if let c = caption, c.text.hasPrefix("Ready · ") { text += ": " + c.text.dropFirst("Ready · ".count) }
            return [FeedEvent(at: at, sessionId: sessionId, kind: .done, text: text, chapter: chapter)]
        case (.some(.running), .exited), (.some(.needsYou), .exited):
            return [FeedEvent(at: at, sessionId: sessionId, kind: .error, text: "\(name) exited while working", chapter: chapter)]
        default:
            return []
        }
    }

    public static func stepDone(sessionId: String, step: Int, of steps: Int, title: String, at: Date = Date(), chapter: Int? = nil) -> FeedEvent {
        FeedEvent(at: at, sessionId: sessionId, kind: .stepDone, text: "Step \(step) of \(steps) done · \(title)", chapter: chapter)
    }

    public static func subagentsStarted(sessionId: String, names: [String], at: Date = Date()) -> FeedEvent? {
        guard !names.isEmpty else { return nil }
        let list = names.prefix(3).joined(separator: ", ") + (names.count > 3 ? " +\(names.count - 3)" : "")
        let noun = names.count == 1 ? "subagent" : "subagents"
        return FeedEvent(at: at, sessionId: sessionId, kind: .subagents, text: "Started \(names.count) \(noun): \(list)")
    }

    public static func rotated(sessionId: String, from: String, to: String, at: Date = Date()) -> FeedEvent {
        FeedEvent(at: at, sessionId: sessionId, kind: .rotated, text: "Handed from \(from) to \(to) near its limit")
    }

    public static func scheduleRan(sessionId: String, name: String, ok: Bool, result: String, at: Date = Date()) -> FeedEvent {
        FeedEvent(at: at, sessionId: sessionId, kind: ok ? .done : .error, text: "Scheduled run of \(name): \(result)")
    }

    public static func scheduleMissed(sessionId: String, name: String, time: String, at: Date = Date()) -> FeedEvent {
        FeedEvent(at: at, sessionId: sessionId, kind: .error, text: "\(name) missed its \(time) run · run now?")
    }
}

/// LAB-591/659: what one feed row says, split into fields: what happened (the action), the detail of it without the
/// session's name (the row shows the session once, on its own line), and when.
public struct FeedLine: Equatable, Sendable {
    /// "Finished", "Error", "Step done", "Subagents", …
    public var action: String
    /// What was done: the result words, without "<session name> finished".
    public var detail: String

    public init(action: String, detail: String) { self.action = action; self.detail = detail }

    public static func action(_ k: FeedKind) -> String {
        switch k {
        case .stepDone: return "Step done"
        case .finding: return "Finding"
        case .choice: return "Choice"
        case .subagents: return "Subagents"
        case .done: return "Finished"
        case .rotated: return "Handed off"
        case .error: return "Error"
        }
    }

    /// `name` is the session's name now; the event's text may carry the name it had when it happened.
    public static func describe(kind: FeedKind, text: String, sessionName: String) -> FeedLine {
        var d = text.trimmingCharacters(in: .whitespacesAndNewlines)
        switch kind {
        case .done:
            if let r = d.range(of: " finished: ") { d = String(d[r.upperBound...]) }
            else if d.hasSuffix(" finished") || d == "finished" { d = "Finished its turn" }
        case .error:
            if d.hasSuffix(" exited while working") { d = "Exited while it was working" }
        default:
            if !sessionName.isEmpty, d.hasPrefix(sessionName + " ") { d = String(d.dropFirst(sessionName.count + 1)) }
        }
        if let f = d.first, f.isLowercase { d = f.uppercased() + d.dropFirst() }
        return FeedLine(action: action(kind), detail: d.isEmpty ? action(kind) : d)
    }

    /// "1:13 PM" today, "Yesterday 1:13 PM", else "Oct 22 1:13 PM" (the feed covers 7 days; a bare 12-hour time read
    /// as out of order).
    public static func timeLabel(_ at: Date, now: Date = Date(), calendar: Calendar = .current, locale: Locale = .current) -> String {
        // LAB-1338 follow-up: two DateFormatters were made per feed row on every redraw (3 % of the installed app's main
        // thread with agents working). They are kept per locale and time zone.
        let (time, day) = formatters(locale: locale, zone: calendar.timeZone)
        let t = time.string(from: at)
        if calendar.isDate(at, inSameDayAs: now) { return t }
        if let y = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(at, inSameDayAs: y) { return "Yesterday " + t }
        return day.string(from: at) + " " + t
    }

    private static let formatterLock = NSLock()
    nonisolated(unsafe) private static var formatterCache: [String: (DateFormatter, DateFormatter)] = [:]
    private static func formatters(locale: Locale, zone: TimeZone) -> (DateFormatter, DateFormatter) {
        let key = locale.identifier + "|" + zone.identifier
        formatterLock.lock(); defer { formatterLock.unlock() }
        if let f = formatterCache[key] { return f }
        let time = DateFormatter()
        time.locale = locale; time.timeZone = zone
        time.dateStyle = .none; time.timeStyle = .short
        let day = DateFormatter()
        day.locale = locale; day.timeZone = zone
        day.setLocalizedDateFormatFromTemplate("MMMd")
        formatterCache[key] = (time, day)
        return (time, day)
    }
}
