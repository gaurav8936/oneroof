import Foundation

// Desktop notifications (LAB-197): the rules for when One Roof shows a macOS banner. Pure: the app's Notifier hands
// each event here with the owner's settings and what is on screen, and posts whatever Note comes back.
// Humans stay in the loop: a note only says something happened; clicking it shows the session, nothing more.

public enum NoteKind: String, Codable, CaseIterable, Sendable {
    /// An agent stopped on a question or permission prompt.
    case needsYou
    /// An agent finished its turn.
    case done
    /// A command in a terminal ran longer than the threshold and finished.
    case longCommand
    /// A program in a terminal asked for a notification itself (OSC 9 / OSC 777).
    case terminal
}

/// Something that might deserve a banner.
public struct NoteEvent: Equatable, Sendable {
    public var kind: NoteKind
    public var sessionId: String
    public var sessionName: String
    /// A line for the body (the decision's title, the caption, the program's own text).
    public var detail: String?
    /// The program's own title (OSC 777 carries one).
    public var title: String?
    /// How long the command ran, in seconds (long commands).
    public var duration: TimeInterval?
    /// The command's exit code, when the shell reported one.
    public var exitCode: Int?
    public var at: Date

    public init(kind: NoteKind, sessionId: String, sessionName: String, detail: String? = nil, title: String? = nil,
                duration: TimeInterval? = nil, exitCode: Int? = nil, at: Date = Date()) {
        self.kind = kind; self.sessionId = sessionId; self.sessionName = sessionName; self.detail = detail
        self.title = title; self.duration = duration; self.exitCode = exitCode; self.at = at
    }
}

/// The owner's switches (Settings › General › Notifications).
public struct NotePrefs: Equatable, Sendable {
    public var needsYou: Bool
    public var done: Bool
    /// Long commands and programs' own notifications (OSC 9 / 777).
    public var longCommands: Bool
    public var longCommandSeconds: Int

    public init(needsYou: Bool = true, done: Bool = true, longCommands: Bool = true, longCommandSeconds: Int = 30) {
        self.needsYou = needsYou; self.done = done; self.longCommands = longCommands; self.longCommandSeconds = longCommandSeconds
    }

    public init(_ s: AppSettings) {
        self.init(needsYou: s.notifyNeedsYou, done: s.notifyDone, longCommands: s.notifyLongCommands,
                  longCommandSeconds: s.longCommandSeconds)
    }

    public func allows(_ k: NoteKind) -> Bool {
        switch k {
        case .needsYou: return needsYou
        case .done: return done
        case .longCommand, .terminal: return longCommands
        }
    }
}

/// One banner to post.
public struct Note: Equatable, Sendable {
    /// "\(kind)-\(session)": a newer note of the same kind for the same session replaces the old one.
    public var identifier: String
    /// The session id: macOS groups a session's notes together.
    public var threadIdentifier: String
    public var title: String
    public var body: String
    public var sessionId: String
    public var kind: NoteKind
}

/// Decides, remembers what it sent, and keeps the rate down. One per app.
public struct NoteGate: Sendable {
    /// The same kind for the same session at most this often (a status flicker never sends twice).
    public var repeatInterval: TimeInterval
    /// At most this many notes in any minute across all sessions (a fleet finishing at once is one burst, not twenty).
    public var perMinute: Int
    public private(set) var lastSent: [String: Date] = [:]
    public private(set) var recent: [Date] = []
    /// The last body sent per identifier: an identical program notification is not repeated.
    private var lastBody: [String: String] = [:]

    public init(repeatInterval: TimeInterval = 20, perMinute: Int = 6) {
        self.repeatInterval = repeatInterval; self.perMinute = perMinute
    }

    public static func identifier(_ kind: NoteKind, session: String) -> String { "\(kind.rawValue)-\(session)" }

    /// The note to post for `e`, or nil. `appActive`: One Roof is the frontmost app; `focusedSession`: the session
    /// whose terminal (or row) has focus in the window in front. A note about what you are looking at is never sent.
    public mutating func decide(_ e: NoteEvent, prefs: NotePrefs, appActive: Bool, focusedSession: String?) -> Note? {
        guard prefs.allows(e.kind) else { return nil }
        if appActive, focusedSession == e.sessionId { return nil }
        if e.kind == .longCommand {
            guard let d = e.duration, d >= TimeInterval(max(1, prefs.longCommandSeconds)) else { return nil }
        }
        guard let note = Self.compose(e) else { return nil }
        if let last = lastSent[note.identifier], e.at.timeIntervalSince(last) < repeatInterval { return nil }
        if e.kind == .terminal, lastBody[note.identifier] == note.body,
           let last = lastSent[note.identifier], e.at.timeIntervalSince(last) < 300 { return nil }
        // An agent CLI's own "waiting for you" notification right after One Roof's needs-you / ready one says it twice.
        if e.kind == .terminal, [NoteKind.needsYou, .done].contains(where: { k in
            lastSent[Self.identifier(k, session: e.sessionId)].map { e.at.timeIntervalSince($0) < 60 } ?? false }) { return nil }
        recent = recent.filter { e.at.timeIntervalSince($0) < 60 }
        // Needs you always gets through (it blocks work); the rest wait their turn.
        if recent.count >= perMinute, e.kind != .needsYou { return nil }
        recent.append(e.at)
        lastSent[note.identifier] = e.at
        lastBody[note.identifier] = note.body
        return note
    }

    /// Forget a session's history (it was removed).
    public mutating func forget(session: String) {
        for k in NoteKind.allCases {
            let id = Self.identifier(k, session: session)
            lastSent[id] = nil; lastBody[id] = nil
        }
    }

    /// Title and body for an event; nil when there is nothing worth saying.
    public static func compose(_ e: NoteEvent) -> Note? {
        let name = e.sessionName.isEmpty ? "A session" : e.sessionName
        let detail = e.detail.map(Self.oneLine).flatMap { $0.isEmpty ? nil : $0 }
        let title: String, body: String
        switch e.kind {
        case .needsYou:
            title = "\(name) needs you"
            body = detail ?? "It is waiting on a question or a permission prompt."
        case .done:
            title = "\(name) is ready"
            body = detail ?? "It finished its turn."
        case .longCommand:
            let d = e.duration.map(Self.duration) ?? ""
            switch e.exitCode {
            case .some(0), .none: title = "Command finished in \(name)"
            case .some(let c): title = "Command failed in \(name) (exit \(c))"
            }
            body = detail ?? (d.isEmpty ? "Your command finished." : "It ran for \(d).")
        case .terminal:
            let t = e.title.map(Self.oneLine) ?? ""
            guard detail != nil || !t.isEmpty else { return nil }
            title = t.isEmpty ? name : "\(name): \(t)"
            body = detail ?? ""
        }
        let id = identifier(e.kind, session: e.sessionId)
        return Note(identifier: id, threadIdentifier: e.sessionId, title: title, body: String(body.prefix(240)),
                    sessionId: e.sessionId, kind: e.kind)
    }

    /// "45 s", "3 min", "1 h 5 min".
    public static func duration(_ s: TimeInterval) -> String {
        let n = Int(s.rounded())
        if n < 60 { return "\(n) s" }
        if n < 3600 { return "\(n / 60) min" }
        let m = (n % 3600) / 60
        return m == 0 ? "\(n / 3600) h" : "\(n / 3600) h \(m) min"
    }

    static func oneLine(_ s: String) -> String {
        s.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}

/// Which status changes are news (the app compares each row's status before and after a poll).
public enum NoteSignals {
    /// running/needs-you → ready is a finished turn. Needs you comes from the decision builder (it has the question).
    public static func statusChange(from old: SessionStatus?, to new: SessionStatus) -> NoteKind? {
        guard let old, old != new else { return nil }
        if new == .done, old == .running || old == .needsYou { return .done }
        return nil
    }
}

// MARK: Permission (LAB-718)

/// What macOS says about One Roof's notifications, without the UserNotifications types (so the rule is testable).
public enum NotePermissionStatus: Sendable, Equatable {
    case allowed, denied, notAsked, unavailable
}

/// What to do with a note, given what macOS says right now. The macOS prompt is only ever shown when macOS has never
/// been asked, and at most once per launch: 0.5.2 asked again whenever it hadn't asked in this run, so the owner saw
/// "Allow notifications" again and again although One Roof was allowed in System Settings.
public enum NotePermission {
    public enum Action: Equatable, Sendable { case deliver, drop, ask }

    public static func action(_ status: NotePermissionStatus, askedThisLaunch: Bool) -> Action {
        switch status {
        case .allowed: return .deliver
        case .denied, .unavailable: return .drop
        case .notAsked: return askedThisLaunch ? .drop : .ask
        }
    }

    /// The Settings line and its button: allowed → no button; denied → open System Settings; never asked → ask.
    public enum Button: Equatable, Sendable { case none, openSystemSettings, ask }

    public static func settings(_ status: NotePermissionStatus) -> (text: String, button: Button) {
        switch status {
        case .allowed: return ("Allowed", .none)
        case .denied: return ("Turned off in System Settings › Notifications › One Roof", .openSystemSettings)
        case .notAsked: return ("Not asked yet: One Roof asks the first time it has something to tell you", .ask)
        case .unavailable: return ("Not available in this build", .none)
        }
    }
}
