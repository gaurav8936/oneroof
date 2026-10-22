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
    @discardableResult
    public mutating func add(_ e: FeedEvent) -> Bool {
        if events.contains(where: { $0.sessionId == e.sessionId && $0.kind == e.kind && abs($0.at.timeIntervalSince(e.at)) < Self.dedupWindow }) {
            return false
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
