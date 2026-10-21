import Foundation

// "Tonight" runs (v2, ENGINES §6): a launchd user agent `com.oneroof.scheduler` calls `OneRoof --run-scheduled`, which
// asks roofd to launch the planned session exactly as Launch does. No run while the Mac sleeps: launchd catches up on
// wake, and a run found late is reported as "missed · run now?" instead. Schedules only start runs; nothing is merged.

public enum Schedule: Codable, Equatable, Hashable, Sendable {
    case tonight(hour: Int, minute: Int)    // one-off
    case nightly(hour: Int, minute: Int)
    case onDemand                            // "Run now" only
    /// A loop (LAB-254): every N minutes, launch the session, or send its opening message again when it is alive and
    /// waiting. Never while it is working or needs you.
    case every(minutes: Int)

    public static let everyChoices = [15, 30, 60, 120, 240]

    public var kind: String {
        switch self {
        case .tonight: return "tonight"; case .nightly: return "nightly"; case .onDemand: return "onDemand"; case .every: return "every"
        }
    }

    public var time: (hour: Int, minute: Int)? {
        switch self {
        case .tonight(let h, let m), .nightly(let h, let m): return (h, m)
        case .onDemand, .every: return nil
        }
    }

    /// The store's (hour, minute) columns; a loop keeps its interval in minutes.
    public var stored: (hour: Int?, minute: Int?) {
        switch self {
        case .every(let m): return (nil, m)
        default: return (time?.hour, time?.minute)
        }
    }

    public var interval: TimeInterval? {
        if case .every(let m) = self { return TimeInterval(max(m, 1) * 60) }
        return nil
    }

    /// "15 min" · "1 h" · "1 h 30 min".
    public static func every(_ m: Int) -> String {
        m < 60 ? "\(m) min" : m % 60 == 0 ? "\(m / 60) h" : "\(m / 60) h \(m % 60) min"
    }

    /// From the store's (kind, hour, minute).
    public init?(kind: String, hour: Int?, minute: Int?) {
        switch kind {
        case "tonight": guard let h = hour, let m = minute else { return nil }; self = .tonight(hour: h, minute: m)
        case "nightly": guard let h = hour, let m = minute else { return nil }; self = .nightly(hour: h, minute: m)
        case "onDemand": self = .onDemand
        case "every": guard let m = minute, m > 0 else { return nil }; self = .every(minutes: m)
        default: return nil
        }
    }

    /// "2:00 AM".
    public var timeText: String? { time.map { Self.clock($0.hour, $0.minute) } }

    public static func clock(_ h: Int, _ m: Int) -> String {
        let h12 = h % 12 == 0 ? 12 : h % 12
        return String(format: "%d:%02d %@", h12, m, h < 12 ? "AM" : "PM")
    }

    /// "Tonight 2:00 AM" · "Nightly 2:00 AM" · "On demand".
    public var label: String {
        switch self {
        case .tonight: return "Tonight " + (timeText ?? "")
        case .nightly: return "Nightly " + (timeText ?? "")
        case .onDemand: return "On demand"
        case .every(let m): return "Every " + Self.every(m)
        }
    }

    /// The caption of a scheduled session (ENGINES §1): "Runs at 2:00 AM".
    public var captionPrefix: String {
        switch self {
        case .tonight, .nightly: return "Runs at " + (timeText ?? "")
        case .onDemand: return "On demand · run now"
        case .every(let m): return "Repeats every " + Self.every(m)
        }
    }
}

/// A session's schedule as stored: when it was set, the last run and its result.
public struct ScheduleRecord: Codable, Equatable, Sendable {
    public var sessionId: String
    public var schedule: Schedule
    public var armedAt: Date
    public var lastRun: Date?
    public var lastResult: String?

    public init(sessionId: String, schedule: Schedule, armedAt: Date = Date(), lastRun: Date? = nil, lastResult: String? = nil) {
        self.sessionId = sessionId; self.schedule = schedule; self.armedAt = armedAt; self.lastRun = lastRun; self.lastResult = lastResult
    }
}

public enum ScheduleClock {
    /// How late `--run-scheduled` may start a run; later than this it is "missed" (the Mac was asleep).
    public static let grace: TimeInterval = 10 * 60

    /// First HH:MM strictly after `date`.
    public static func occurrence(after date: Date, hour: Int, minute: Int, calendar: Calendar = .current) -> Date? {
        calendar.nextDate(after: date, matching: DateComponents(hour: hour, minute: minute, second: 0), matchingPolicy: .nextTime)
    }

    /// Latest HH:MM at or before `date`.
    public static func occurrence(atOrBefore date: Date, hour: Int, minute: Int, calendar: Calendar = .current) -> Date? {
        guard let next = occurrence(after: date, hour: hour, minute: minute, calendar: calendar) else { return nil }
        return calendar.date(byAdding: .day, value: -1, to: next)
    }

    /// When the schedule fires next, or nil (on demand, or a one-off that already ran or was missed).
    public static func nextFire(_ r: ScheduleRecord, now: Date, calendar: Calendar = .current) -> Date? {
        switch r.schedule {
        case .onDemand: return nil
        case .tonight(let h, let m):
            guard r.lastRun == nil, let due = occurrence(after: r.armedAt, hour: h, minute: m, calendar: calendar) else { return nil }
            return due.addingTimeInterval(grace) < now ? nil : due
        case .nightly(let h, let m):
            return occurrence(after: now, hour: h, minute: m, calendar: calendar)
        case .every:
            return everyDue(r)
        }
    }

    /// A loop's next round: an interval after its last round (or after it was set up).
    static func everyDue(_ r: ScheduleRecord) -> Date? {
        r.schedule.interval.map { max(r.armedAt, r.lastRun ?? .distantPast).addingTimeInterval($0) }
    }

    /// The occurrence that should have run by `now` and has not, if any.
    static func pendingDue(_ r: ScheduleRecord, now: Date, calendar: Calendar) -> Date? {
        let since = max(r.armedAt, r.lastRun ?? .distantPast)
        switch r.schedule {
        case .onDemand: return nil
        case .tonight(let h, let m):
            guard r.lastRun == nil, let due = occurrence(after: r.armedAt, hour: h, minute: m, calendar: calendar), due <= now else { return nil }
            return due
        case .nightly(let h, let m):
            guard let due = occurrence(atOrBefore: now, hour: h, minute: m, calendar: calendar), due > since else { return nil }
            return due
        case .every:
            guard let due = everyDue(r), due <= now else { return nil }
            return due
        }
    }

    public enum Action: Equatable, Sendable { case run, missed(Date), nothing }

    /// What `--run-scheduled` (or the morning check) should do for one record now.
    public static func action(_ r: ScheduleRecord, now: Date, calendar: Calendar = .current) -> Action {
        guard let due = pendingDue(r, now: now, calendar: calendar) else { return .nothing }
        if case .every = r.schedule { return .run }   // a loop late after sleep just runs its next round
        return now.timeIntervalSince(due) <= grace ? .run : .missed(due)
    }

    /// What a due loop round does to a session that is already alive (LAB-254): send its message again when the agent
    /// waits at its prompt; wait while it works or needs you; give the round up once it is a whole interval late.
    public enum LiveRound: Equatable, Sendable { case send, wait, skip }

    public static func liveRound(_ r: ScheduleRecord, status: String?, ready: Bool, now: Date) -> LiveRound {
        if ["idle", "done"].contains(status ?? ""), ready { return .send }
        guard let due = everyDue(r), let i = r.schedule.interval else { return .wait }
        return now.timeIntervalSince(due) >= i ? .skip : .wait
    }

    /// The row's schedule pill: "2:00 AM" for a timed run, "3:40 PM · every 1 h" for a loop.
    public static func rowLabel(_ r: ScheduleRecord, now: Date = Date()) -> String? {
        if case .every(let m) = r.schedule {
            let next = max(everyDue(r) ?? now, now)
            return next.formatted(date: .omitted, time: .shortened) + " · every " + Schedule.every(m)
        }
        if case .tonight = r.schedule, r.lastRun != nil { return nil }   // a one-off that has run (or was missed)
        return r.schedule.timeText
    }

    public static func isMissed(_ r: ScheduleRecord, now: Date, calendar: Calendar = .current) -> Bool {
        if case .missed = action(r, now: now, calendar: calendar) { return true }
        return false
    }
}

/// The launchd user agent One Roof writes (never installed by this code).
public enum SchedulerAgent {
    public static let label = "com.oneroof.scheduler"

    public static var plistPath: String {
        (NSHomeDirectory() as NSString).appendingPathComponent("Library/LaunchAgents/\(label).plist")
    }

    /// The plist XML: one StartCalendarInterval per distinct HH:MM, calling `<executable> --run-scheduled`.
    public static func plist(executable: String, schedules: [Schedule], logPath: String? = nil) -> String {
        var seen = Set<Int>()
        let times = schedules.compactMap(\.time).filter { seen.insert($0.hour * 60 + $0.minute).inserted }
            .sorted { ($0.hour, $0.minute) < ($1.hour, $1.minute) }
        var dict: [String: Any] = [
            "Label": label,
            "ProgramArguments": [executable, "--run-scheduled"],
            "StartCalendarInterval": times.map { ["Hour": $0.hour, "Minute": $0.minute] },
            "RunAtLoad": false,
            "ProcessType": "Background",
        ]
        if let logPath { dict["StandardOutPath"] = logPath; dict["StandardErrorPath"] = logPath }
        guard let data = try? PropertyListSerialization.data(fromPropertyList: dict, format: .xml, options: 0) else { return "" }
        return String(decoding: data, as: UTF8.self)
    }
}
