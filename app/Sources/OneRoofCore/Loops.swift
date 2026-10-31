import Foundation

// Loops (I12 slice 1, LAB-86 / LAB-676): work that repeats until a check passes, or every night at a set time, on this
// Mac. A loop is a plain file (`<shared>/loops/<id>/loop.json`) plus one line per round (`rounds.jsonl`). The controller
// below is deterministic and clock-free (every call takes `now`), like ScheduleClock: One Roof, not a model, runs the
// check, counts rounds, enforces the limits and decides whether to go again. roofd runs it (LoopEngine) with the app
// open or closed; the app only reads and edits the files. Loops never push, merge or deploy: each works in its own
// worktree on branch `loop/<id>`.

/// When a loop runs.
public enum LoopTrigger: Codable, Equatable, Hashable, Sendable {
    /// Started with Run now; rounds go on until the check passes or a limit is hit, `everyMinutes` apart (0 = at once).
    case untilDone(everyMinutes: Int)
    /// Every night at this time: one run of rounds, until the check passes or a limit is hit.
    case at(hour: Int, minute: Int)
    /// LAB-1369 · When quiet: once no session a person started has been working or waiting on you for `quietMinutes`,
    /// optionally only between `fromHour` and `toHour` (local, may wrap midnight; nil = any time), at most once per
    /// window (once per day without one). A session that becomes active during the run does not stop it (v1).
    case whenQuiet(quietMinutes: Int, fromHour: Int?, toHour: Int?)
    /// LAB-1865 · On an event (`linear.issue.created`, `woodpecker.pipeline.failed`, `git.push`, `oneroof.release`):
    /// `ae loops fire <event>` (the kit's adapter, called by a webhook receiver or a git hook) drops it in
    /// `<loops>/.events/`, and roofd starts one run per event that came after the loop's last run.
    case onEvent(String)

    public var label: String {
        switch self {
        case .untilDone(let m): return m <= 0 ? "Until done" : "Until done · every " + Schedule.every(m)
        case .at(let h, let m): return "Nightly " + Schedule.clock(h, m)
        case .whenQuiet(let q, let f, let t):
            let window = (f != nil && t != nil) ? " · \(Schedule.clock(f!, 0))–\(Schedule.clock(t!, 0))" : ""
            return "When quiet \(Schedule.every(q))" + window
        case .onEvent(let e): return "On " + e
        }
    }

    public var isNightly: Bool { if case .at = self { return true }; return false }
    /// Starts runs on its own (a clock, quiet or an event), so a saved loop is armed (waiting) rather than stopped.
    public var isArmed: Bool { if case .untilDone = self { return false }; return true }
    public var isQuiet: Bool { if case .whenQuiet = self { return true }; return false }
    public var event: String? { if case .onEvent(let e) = self { return e }; return nil }

    /// The kit's event names (`kit/loops/README.md`, Triggers).
    public static let knownEvents = ["linear.issue.created", "woodpecker.pipeline.failed", "git.push", "oneroof.release"]
}

/// LAB-1369 · LAB-1865: what roofd knows besides the clock when it decides whether a loop starts.
public struct LoopContext: Equatable, Sendable {
    /// How long no manual session has been working or waiting on you (nil = unknown or busy now: never quiet).
    public var quietFor: TimeInterval?
    /// Events fired so far (name, when), newest last.
    public var events: [LoopEventFire]
    public init(quietFor: TimeInterval? = nil, events: [LoopEventFire] = []) { self.quietFor = quietFor; self.events = events }
}

/// One `ae loops fire <event>` (or a One Roof release): `<loops>/.events/<epoch>-<event>.json`.
public struct LoopEventFire: Codable, Equatable, Sendable {
    public var event: String
    public var at: Date
    public var detail: String?
    public init(event: String, at: Date, detail: String? = nil) { self.event = event; self.at = at; self.detail = detail }
}

/// When a run stops on its own.
public struct LoopLimits: Codable, Equatable, Hashable, Sendable {
    public var maxRounds: Int
    /// Wall-clock time of one run, from its start.
    public var maxDuration: TimeInterval
    /// Stop when this many rounds in a row end with the same failure (0 = never).
    public var sameFailureStop: Int

    public init(maxRounds: Int = 8, maxDuration: TimeInterval = 3 * 3600, sameFailureStop: Int = 2) {
        self.maxRounds = maxRounds; self.maxDuration = maxDuration; self.sameFailureStop = sameFailureStop
    }

    /// "8 rounds · 3 h · same failure twice".
    public var label: String {
        let mins = Int(maxDuration / 60)
        let same: String
        switch sameFailureStop {
        case ..<1: same = "no same-failure stop"
        case 1: same = "stop on any failure"
        case 2: same = "same failure twice"
        default: same = "same failure \(sameFailureStop)×"
        }
        return "\(maxRounds) round\(maxRounds == 1 ? "" : "s") · \(Schedule.every(mins)) · \(same)"
    }
}

public enum LoopState: String, Codable, CaseIterable, Sendable {
    case running      // a round's session is working
    case waiting      // between rounds, or until the next night
    case paused       // by the owner; nothing starts until Resume
    case needsYou     // a round's session asks something (it shows in Decisions)
    case done         // the check passed
    case failed       // a limit stopped the run
    case stopped      // the owner stopped it (or it was never started)

    public var label: String {
        switch self {
        case .running: return "Running"
        case .waiting: return "Waiting"
        case .paused: return "Paused"
        case .needsYou: return "Needs you"
        case .done: return "Done"
        case .failed: return "Stopped at a limit"
        case .stopped: return "Not running"
        }
    }

    /// The session status whose pill and dot colours a loop in this state borrows (contrast-tested in every theme).
    public var pillStatus: SessionStatus {
        switch self {
        case .running: return .running
        case .waiting: return .idle
        case .paused, .stopped: return .doNotUse
        case .needsYou, .failed: return .needsYou
        case .done: return .done
        }
    }

    /// States in which the loop may start rounds (on its trigger or Run now).
    public var isActive: Bool { [.running, .waiting, .needsYou].contains(self) }
}

/// The round a loop is waiting on: its session.
public struct LoopActiveRound: Codable, Equatable, Sendable {
    public var n: Int
    public var sessionId: String
    public var runtimeId: String
    public var started: Date
    public init(n: Int, sessionId: String, runtimeId: String, started: Date) {
        self.n = n; self.sessionId = sessionId; self.runtimeId = runtimeId; self.started = started
    }
}

/// One run: from Run now (or the nightly time) until done or a limit.
public struct LoopRun: Codable, Equatable, Sendable {
    public var id: String
    public var started: Date
    public var active: LoopActiveRound?
    public init(id: String = String(UUID().uuidString.prefix(8)).lowercased(), started: Date, active: LoopActiveRound? = nil) {
        self.id = id; self.started = started; self.active = active
    }
}

/// Where a loop comes from (LAB-1663): Built-in (from the Agentic Engineering kit, ships off, read-only default) or
/// Mine (user-defined in `<shared>/loops`).
public enum LoopOrigin: String, Codable, Equatable, Hashable, Sendable {
    case builtIn = "built-in"
    case mine = "user"

    public var label: String {
        switch self {
        case .builtIn: return "Built-in"
        case .mine: return "Mine"
        }
    }
}

public struct Loop: Codable, Identifiable, Equatable, Sendable {
    public var id: String
    public var name: String
    public var title: String?
    public var origin: LoopOrigin
    public var goal: String
    /// A shell command (zsh -lc) run in the loop's worktree; exit 0 = done.
    public var check: String
    /// The repo the loop works on; rounds run in `<repo>/.worktrees/loop-<name>` on branch `loop/<name>` (LoopWorktree).
    public var repoPath: String
    public var agent: AgentKind
    public var model: String?
    public var hostedConnection: HostedConnection?
    public var hostedRuntime: HostedRuntimeConfiguration?
    public var account: String?
    /// Extra instructions added to every round's prompt (the goal, check and last output are always included).
    public var roundPrompt: String
    public var trigger: LoopTrigger
    public var limits: LoopLimits
    public var pinned: Bool
    public var state: LoopState
    public var createdAt: Date
    /// Seconds a check may run before it counts as failed.
    public var checkTimeout: TimeInterval
    /// The run in progress, if any.
    public var run: LoopRun?
    /// Run now was pressed: the engine starts a run (or the next round at once) on its next tick.
    public var runRequested: Bool
    /// When the last run started (a nightly loop runs once per night).
    public var lastRunAt: Date?
    /// Why the last run ended, in plain words.
    public var stopReason: String?
    /// LAB-1866: when you marked the last failure as seen in Needs you (it leaves Needs you until the loop fails again).
    public var failureSeenAt: Date?
    /// LAB-1843: the kit loop file (`<loops>/<name>.loop.yaml`) this loop comes from; `ae` owns the file and its
    /// schedule, One Roof shows it and can run it (Run now) but edits it only in the file.
    public var specFile: String?
    /// The kit's schedule for a `.loop.yaml` loop ("cron 0 17 * * 5"), run by `ae` (launchd), never by roofd.
    public var externalSchedule: String?
    /// LAB-1867: the branch a harvested PR targets (nil = `develop` when the remote has it, else its default branch).
    public var harvestBase: String?
    /// LAB-1922: the kit's kind (reporter, prober, fixer, judge …) and how it acts (none · issue · pr), when known.
    public var kind: String?
    public var act: String?

    public var displayTitle: String {
        if let t = title?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty { return t }
        return name
    }

    public init(id: String, name: String, title: String? = nil, origin: LoopOrigin = .mine, goal: String = "", check: String = "",
                repoPath: String, agent: AgentKind = .claude, model: String? = nil, account: String? = nil, roundPrompt: String = "",
                trigger: LoopTrigger = .untilDone(everyMinutes: 0), limits: LoopLimits = LoopLimits(), pinned: Bool = false,
                state: LoopState = .stopped, createdAt: Date = Date(), checkTimeout: TimeInterval = 600) {
        self.id = id; self.name = name; self.title = title; self.origin = origin; self.goal = goal; self.check = check
        self.repoPath = repoPath; self.agent = agent; self.model = model; self.account = account; self.roundPrompt = roundPrompt
        self.hostedConnection = nil; self.hostedRuntime = nil
        self.trigger = trigger; self.limits = limits; self.pinned = pinned; self.state = state; self.createdAt = createdAt
        self.checkTimeout = checkTimeout; self.run = nil; self.runRequested = false; self.lastRunAt = nil; self.stopReason = nil
        self.failureSeenAt = nil; self.specFile = nil; self.externalSchedule = nil; self.harvestBase = nil; self.kind = nil; self.act = nil
    }

    enum CodingKeys: String, CodingKey {
        case id, name, title, origin, goal, check, repoPath, agent, model, hostedConnection, hostedRuntime, account, roundPrompt, trigger, limits, pinned, state,
             createdAt, checkTimeout, run, runRequested, lastRunAt, stopReason, failureSeenAt, specFile, externalSchedule, harvestBase, kind, act
    }

    /// The failure Needs you shows (LAB-1866): the run stopped at a limit and you have not marked it seen since.
    public var failureUnseen: Bool {
        guard state == .failed else { return false }
        guard let seen = failureSeenAt else { return true }
        return seen < (lastRunAt ?? .distantPast)
    }

    public init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? id
        title = try c.decodeIfPresent(String.self, forKey: .title)
        origin = try c.decodeIfPresent(LoopOrigin.self, forKey: .origin) ?? .mine
        goal = try c.decodeIfPresent(String.self, forKey: .goal) ?? ""
        check = try c.decodeIfPresent(String.self, forKey: .check) ?? ""
        repoPath = try c.decodeIfPresent(String.self, forKey: .repoPath) ?? ""
        agent = try c.decodeIfPresent(AgentKind.self, forKey: .agent) ?? .claude
        model = try c.decodeIfPresent(String.self, forKey: .model)
        hostedConnection = try c.decodeIfPresent(HostedConnection.self, forKey: .hostedConnection)
        hostedRuntime = try c.decodeIfPresent(HostedRuntimeConfiguration.self, forKey: .hostedRuntime)
        account = try c.decodeIfPresent(String.self, forKey: .account)
        roundPrompt = try c.decodeIfPresent(String.self, forKey: .roundPrompt) ?? ""
        trigger = try c.decodeIfPresent(LoopTrigger.self, forKey: .trigger) ?? .untilDone(everyMinutes: 0)
        limits = try c.decodeIfPresent(LoopLimits.self, forKey: .limits) ?? LoopLimits()
        pinned = try c.decodeIfPresent(Bool.self, forKey: .pinned) ?? false
        state = try c.decodeIfPresent(LoopState.self, forKey: .state) ?? .stopped
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        checkTimeout = try c.decodeIfPresent(TimeInterval.self, forKey: .checkTimeout) ?? 600
        run = try c.decodeIfPresent(LoopRun.self, forKey: .run)
        runRequested = try c.decodeIfPresent(Bool.self, forKey: .runRequested) ?? false
        lastRunAt = try c.decodeIfPresent(Date.self, forKey: .lastRunAt)
        stopReason = try c.decodeIfPresent(String.self, forKey: .stopReason)
        failureSeenAt = try c.decodeIfPresent(Date.self, forKey: .failureSeenAt)
        specFile = try c.decodeIfPresent(String.self, forKey: .specFile)
        externalSchedule = try c.decodeIfPresent(String.self, forKey: .externalSchedule)
        harvestBase = try c.decodeIfPresent(String.self, forKey: .harvestBase)
        kind = try c.decodeIfPresent(String.self, forKey: .kind)
        act = try c.decodeIfPresent(String.self, forKey: .act)
    }

    /// The loop's own branch and worktree (never the live checkout).
    public var branch: String { LoopWorktree.branch(id, repo: repoPath) }
    public var worktreePath: String { LoopWorktree.path(repo: repoPath, id: id) }

    /// A file-safe id from a name: "Fix CI (web)" → "fix-ci-web".
    public static func slug(_ name: String) -> String {
        let lowered = name.lowercased()
        var out = ""
        var dash = false
        for ch in lowered {
            if ch.isASCII && (ch.isLetter || ch.isNumber) { out.append(ch); dash = false }
            else if !dash && !out.isEmpty { out.append("-"); dash = true }
        }
        while out.hasSuffix("-") { out.removeLast() }
        return String(out.prefix(40)).isEmpty ? "loop" : String(out.prefix(40))
    }

    /// A valid id: lowercase letters, digits and dashes only (it names a folder and a branch).
    public static func validId(_ id: String) -> Bool {
        !id.isEmpty && id.count <= 64 && id.allSatisfy { ($0.isASCII && ($0.isLowercase || $0.isNumber)) || $0 == "-" }
            && !id.hasPrefix("-")
    }
}

/// One line of `rounds.jsonl`: a round (the agent worked, then the check ran), a check on its own (before the first
/// round of a run), or the line written when a run stops (what was tried).
public struct LoopRound: Codable, Equatable, Sendable {
    public enum Kind: String, Codable, Sendable { case round, check, stop }
    public var kind: Kind
    /// The run this line belongs to.
    public var runId: String
    /// Round number in its run (0 for a check before the first round, and for the stop line).
    public var n: Int
    public var started: Date
    public var ended: Date
    public var sessionId: String?
    public var agent: AgentKind?
    public var checkPassed: Bool?
    public var exitCode: Int32?
    /// The last lines of the check's output.
    public var checkOutput: String
    /// Same key = same failure (see LoopCheck.failureKey); nil when the check passed.
    public var failureKey: String?
    public var note: String?

    public init(kind: Kind, runId: String, n: Int, started: Date, ended: Date, sessionId: String? = nil, agent: AgentKind? = nil,
                checkPassed: Bool? = nil, exitCode: Int32? = nil, checkOutput: String = "", failureKey: String? = nil, note: String? = nil) {
        self.kind = kind; self.runId = runId; self.n = n; self.started = started; self.ended = ended; self.sessionId = sessionId
        self.agent = agent; self.checkPassed = checkPassed; self.exitCode = exitCode; self.checkOutput = checkOutput
        self.failureKey = failureKey; self.note = note
    }
}

/// What a check run produced.
public struct LoopCheckResult: Equatable, Sendable {
    public var passed: Bool
    public var exitCode: Int32
    public var output: String
    public var timedOut: Bool
    public var duration: TimeInterval
    public init(passed: Bool, exitCode: Int32, output: String, timedOut: Bool = false, duration: TimeInterval = 0) {
        self.passed = passed; self.exitCode = exitCode; self.output = output; self.timedOut = timedOut; self.duration = duration
    }
}

/// The round session as roofd sees it.
public enum LoopRoundStatus: Equatable, Sendable {
    case none        // no round in flight
    case working     // the agent is on it (or still starting)
    case needsYou    // a permission prompt or question
    case finished    // the agent is back at its prompt, quiet: run the check
    case gone        // the session exited or vanished

    /// From a holder's `info` answer (nil = no answer: the session is gone). `quiet` = how long the session must have
    /// been still before a finished turn counts (one turn can pause between tool calls).
    public static func from(info: [String: Any]?, now: Date, quiet: TimeInterval = 20) -> LoopRoundStatus {
        guard let info, info["exited"] == nil else { return .gone }
        let status = info["status"] as? String ?? "unknown"
        let opening = info["opening"] as? String ?? "none"
        if status == "blocked" || opening == "failed" { return .needsYou }
        let ready = info["ready"] as? Bool ?? false
        let active = (info["active"] as? Double).map { Date(timeIntervalSince1970: $0) } ?? .distantPast
        if ["done", "none"].contains(opening), ready, ["done", "idle"].contains(status), now.timeIntervalSince(active) >= quiet {
            return .finished
        }
        return .working
    }
}

public enum LoopDecision: Equatable, Sendable {
    case wait
    /// Run the check: before the first round of a run (it may already pass), or after a round finished.
    case runCheck
    case startRound(Int)
    case needsYou
    case done
    case stop(String)
}

public enum LoopController {
    /// What a loop should do now. `rounds` = its whole `rounds.jsonl` (only the current run's lines count).
    public static func next(_ loop: Loop, rounds: [LoopRound], now: Date, round: LoopRoundStatus,
                            calendar: Calendar = .current, context: LoopContext = LoopContext()) -> LoopDecision {
        if loop.state == .paused { return .wait }
        guard let run = loop.run else {
            // Not in a run: start one on Run now, at a nightly loop's time, once it is quiet, or on its event.
            if loop.runRequested || nightlyDue(loop, now: now, calendar: calendar)
                || quietDue(loop, now: now, quietFor: context.quietFor, calendar: calendar)
                || eventDue(loop, events: context.events) != nil { return .runCheck }
            return .wait
        }
        let mine = rounds.filter { $0.runId == run.id }
        let overTime = now.timeIntervalSince(run.started) >= loop.limits.maxDuration
        if run.active != nil {
            switch round {
            case .finished, .gone: return .runCheck
            case .needsYou: return overTime ? .stop(timeReason(loop)) : .needsYou
            case .working, .none: return overTime ? .stop(timeReason(loop)) : .wait
            }
        }
        if let last = mine.last(where: { $0.kind != .stop }), last.checkPassed == true { return .done }
        guard let lastCheck = mine.last(where: { $0.kind != .stop }) else { return .runCheck }   // the check before round 1
        let agentRounds = mine.filter { $0.kind == .round }
        if overTime { return .stop(timeReason(loop)) }
        if agentRounds.count >= loop.limits.maxRounds {
            return .stop("Round limit reached: \(agentRounds.count) of \(loop.limits.maxRounds) rounds and the check still fails")
        }
        if let key = repeatedFailure(agentRounds, times: loop.limits.sameFailureStop) {
            return .stop("The same failure \(loop.limits.sameFailureStop == 2 ? "twice" : "\(loop.limits.sameFailureStop) times") in a row (\(key)): a new approach is needed")
        }
        if loop.runRequested { return .startRound(agentRounds.count + 1) }        // Run now skips the wait
        if case .untilDone(let every) = loop.trigger, every > 0,
           now < lastCheck.ended.addingTimeInterval(TimeInterval(every * 60)) {
            return .wait
        }
        return .startRound(agentRounds.count + 1)
    }

    static func timeReason(_ loop: Loop) -> String {
        "Time limit reached: \(Schedule.every(Int(loop.limits.maxDuration / 60))) and the check still fails"
    }

    /// The failure key when the last `times` rounds all failed the same way.
    static func repeatedFailure(_ rounds: [LoopRound], times: Int) -> String? {
        guard times > 0, rounds.count >= times else { return nil }
        let tail = rounds.suffix(times)
        guard let key = tail.first?.failureKey, tail.allSatisfy({ $0.checkPassed == false && $0.failureKey == key }) else { return nil }
        return key
    }

    /// A nightly loop's time has come and it has not run tonight (late by more than the scheduler's grace = skipped:
    /// the Mac was asleep; it runs the next night).
    public static func nightlyDue(_ loop: Loop, now: Date, calendar: Calendar = .current) -> Bool {
        guard case .at(let h, let m) = loop.trigger, loop.state != .stopped, loop.state != .paused,
              let occ = ScheduleClock.occurrence(atOrBefore: now, hour: h, minute: m, calendar: calendar) else { return false }
        let since = max(loop.createdAt, loop.lastRunAt ?? .distantPast)
        return occ > since && now.timeIntervalSince(occ) <= ScheduleClock.grace
    }

    /// LAB-1369: a When-quiet loop starts once no manual session has been active for its quiet time, inside its window,
    /// and not already run in this window (once per day without a window).
    public static func quietDue(_ loop: Loop, now: Date, quietFor: TimeInterval?, calendar: Calendar = .current) -> Bool {
        guard case .whenQuiet(let q, let f, let t) = loop.trigger, loop.state != .stopped, loop.state != .paused,
              let quiet = quietFor, quiet >= TimeInterval(max(q, 0) * 60),
              let start = quietWindowStart(from: f, to: t, now: now, calendar: calendar) else { return false }
        return (loop.lastRunAt ?? .distantPast) < start
    }

    /// The start of the window `now` is in (nil = outside it). No window: the start of today.
    public static func quietWindowStart(from: Int?, to: Int?, now: Date, calendar: Calendar = .current) -> Date? {
        guard let f = from, let t = to, f != t else { return calendar.startOfDay(for: now) }
        let h = calendar.component(.hour, from: now)
        let inside = f < t ? (h >= f && h < t) : (h >= f || h < t)
        guard inside else { return nil }
        return ScheduleClock.occurrence(atOrBefore: now, hour: f, minute: 0, calendar: calendar)
    }

    /// LAB-1865: the newest fired event this loop listens for that came after its last run (and after it was made).
    public static func eventDue(_ loop: Loop, events: [LoopEventFire]) -> LoopEventFire? {
        guard let name = loop.trigger.event, loop.state != .stopped, loop.state != .paused else { return nil }
        let since = max(loop.createdAt, loop.lastRunAt ?? .distantPast)
        return events.filter { $0.event == name && $0.at > since }.max { $0.at < $1.at }
    }

    /// When the loop starts something next, for the list (nil = nothing planned).
    public static func nextStart(_ loop: Loop, rounds: [LoopRound], now: Date, calendar: Calendar = .current) -> Date? {
        guard loop.state != .paused, loop.state != .stopped else { return nil }
        if let run = loop.run {
            guard run.active == nil, case .untilDone(let every) = loop.trigger,
                  let last = rounds.last(where: { $0.runId == run.id && $0.kind != .stop }) else { return nil }
            return last.ended.addingTimeInterval(TimeInterval(every * 60))
        }
        if case .at(let h, let m) = loop.trigger { return ScheduleClock.occurrence(after: now, hour: h, minute: m, calendar: calendar) }
        return nil
    }

    // MARK: Applying a decision (pure: the engine does the I/O, these say what the files become)

    /// A run begins (the check before round 1 is about to run).
    public static func begin(_ loop: Loop, now: Date, runId: String = String(UUID().uuidString.prefix(8)).lowercased()) -> Loop {
        var l = loop
        l.run = LoopRun(id: runId, started: now)
        l.lastRunAt = now
        l.runRequested = false
        l.stopReason = nil
        l.state = .waiting
        return l
    }

    /// A round's session was started.
    public static func started(_ loop: Loop, n: Int, sessionId: String, runtimeId: String, now: Date) -> Loop {
        var l = loop
        l.run?.active = LoopActiveRound(n: n, sessionId: sessionId, runtimeId: runtimeId, started: now)
        l.runRequested = false
        l.state = .running
        return l
    }

    /// The check ran: the round's line (or the check-only line before round 1) and the loop with no round in flight.
    public static func checked(_ loop: Loop, result: LoopCheckResult, now: Date) -> (Loop, LoopRound) {
        var l = loop
        let runId = l.run?.id ?? ""
        let line: LoopRound
        if let a = l.run?.active {
            line = LoopRound(kind: .round, runId: runId, n: a.n, started: a.started, ended: now, sessionId: a.sessionId,
                             agent: l.agent, checkPassed: result.passed, exitCode: result.exitCode,
                             checkOutput: LoopCheck.tail(result.output), failureKey: result.passed ? nil : LoopCheck.failureKey(result),
                             note: result.timedOut ? "check timed out" : nil)
        } else {
            line = LoopRound(kind: .check, runId: runId, n: 0, started: now.addingTimeInterval(-result.duration), ended: now,
                             checkPassed: result.passed, exitCode: result.exitCode, checkOutput: LoopCheck.tail(result.output),
                             failureKey: result.passed ? nil : LoopCheck.failureKey(result),
                             note: result.passed ? "already passing: no round needed" : "check before round 1")
        }
        l.run?.active = nil
        if l.state != .paused { l.state = .waiting }
        return (l, line)
    }

    /// The run ends (done, a limit, or the owner's Stop): the loop's new state and the line recording what was tried.
    public static func ended(_ loop: Loop, rounds: [LoopRound], outcome: LoopDecision, now: Date, byOwner: Bool = false) -> (Loop, LoopRound) {
        var l = loop
        let runId = l.run?.id ?? ""
        let mine = rounds.filter { $0.runId == runId && $0.kind == .round }
        let reason: String
        switch outcome {
        case .done: reason = mine.isEmpty ? "Done: the check already passed" : "Done: the check passed after \(mine.count) round\(mine.count == 1 ? "" : "s")"
        case .stop(let r): reason = r
        default: reason = "Stopped"
        }
        let left = l.run?.active.map { " Round \($0.n)'s session was left running for you." } ?? ""
        let line = LoopRound(kind: .stop, runId: runId, n: 0, started: l.run?.started ?? now, ended: now,
                             checkPassed: outcome == .done ? true : nil, note: reason + left + " " + tried(mine))
        l.run = nil
        l.runRequested = false
        l.stopReason = reason
        l.state = byOwner ? .stopped : (outcome == .done ? .done : .failed)
        return (l, line)
    }

    /// "Tried: #1 ✗ exit 1 · a1b2c3d4, #2 ✗ same failure, #3 ✓."
    public static func tried(_ rounds: [LoopRound]) -> String {
        guard !rounds.isEmpty else { return "No rounds ran." }
        var parts: [String] = []
        var prev: String?
        for r in rounds {
            if r.checkPassed == true { parts.append("#\(r.n) ✓"); prev = nil; continue }
            let k = r.failureKey ?? "failed"
            parts.append("#\(r.n) ✕ " + (k == prev ? "same failure" : k))
            prev = k
        }
        return "Tried: " + parts.joined(separator: ", ") + "."
    }

    /// The state to show after a wait / needs-you decision.
    public static func settle(_ loop: Loop, _ d: LoopDecision) -> Loop {
        var l = loop
        guard l.state != .paused else { return l }
        switch d {
        case .needsYou: l.state = .needsYou
        case .wait:
            if let run = l.run { l.state = run.active == nil ? .waiting : .running }
        default: break
        }
        return l
    }

    // MARK: Owner actions (the Loops screen)

    public static func runNow(_ loop: Loop) -> Loop {
        var l = loop
        l.runRequested = true
        if !l.state.isActive { l.state = .waiting }
        return l
    }

    public static func pause(_ loop: Loop) -> Loop {
        var l = loop
        // Anything that may still start rounds: a run in progress, or an armed loop (clock, quiet, event) not stopped.
        if l.state.isActive || (l.trigger.isArmed && l.state != .stopped) { l.state = .paused }
        return l
    }

    public static func resume(_ loop: Loop) -> Loop {
        var l = loop
        guard l.state == .paused || l.state == .stopped else { return l }
        l.state = l.run?.active != nil ? .running : .waiting
        return l
    }
}

/// The message each round's session opens with: the goal, the check, the rules and what the last check said.
public enum LoopPrompt {
    public static func render(_ loop: Loop, round n: Int, rounds: [LoopRound]) -> String {
        let runId = loop.run?.id
        let mine = rounds.filter { $0.runId == runId && $0.kind != .stop }
        let agentRounds = mine.filter { $0.kind == .round }
        var out: [String] = []
        out.append("One Roof loop \"\(loop.name)\" · round \(n) of at most \(loop.limits.maxRounds). The loop runs the check and decides whether another round starts; you do the work.")
        out.append("Goal: " + (loop.goal.isEmpty ? loop.name : loop.goal))
        out.append("Done when this check passes (exit 0), run in this folder: " + loop.check)
        out.append("Work only in this worktree: \(loop.worktreePath) (branch \(loop.branch)). You may commit here. Never push, merge or deploy, and never touch the main checkout; ask before anything that cannot be undone.")
        if let last = mine.last, last.checkPassed == false {
            let label = last.kind == .check ? "The check before round 1" : "The check after round \(last.n)"
            out.append("\(label) failed (exit \(last.exitCode.map(String.init) ?? "?")). Its output ends with:\n```\n\(last.checkOutput)\n```")
        }
        if !agentRounds.isEmpty { out.append(LoopController.tried(agentRounds)) }
        let lastTwo = Array(mine.suffix(2))
        if lastTwo.count == 2, lastTwo.allSatisfy({ $0.checkPassed == false }), let k = lastTwo[0].failureKey, lastTwo[1].failureKey == k {
            out.append("The last round ended with the same failure as before: try a different approach.")
        }
        let extra = loop.roundPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        if !extra.isEmpty { out.append(extra) }
        out.append("When you are done with this round, run the check yourself, then say in one line what you changed and stop.")
        return out.joined(separator: "\n\n")
    }
}

/// Starter loops (L7, slice 1: two).
public struct LoopTemplate: Identifiable, Equatable, Sendable {
    public var id: String
    public var title: String
    public var summary: String
    public var name: String
    public var goal: String
    public var check: String
    public var roundPrompt: String
    public var trigger: LoopTrigger
    public var limits: LoopLimits

    public func apply(to loop: Loop) -> Loop {
        var l = loop
        if l.name.isEmpty { l.name = name }
        l.goal = goal; if !check.isEmpty { l.check = check }; l.roundPrompt = roundPrompt; l.trigger = trigger; l.limits = limits
        return l
    }
}

public enum LoopTemplates {
    public static let fixUntilGreen = LoopTemplate(
        id: "fix-until-green", title: "Fix until green",
        summary: "Rounds until your test command passes (set it as the check); stops after 8 rounds, 3 h, or the same failure twice.",
        name: "fix-until-green", goal: "The test suite passes on this repo.",
        check: "",
        roundPrompt: "Read the failing output, find the cause and fix it with the smallest change. Do not delete or skip tests to make them pass.",
        trigger: .untilDone(everyMinutes: 0), limits: LoopLimits())

    public static let nightlyTidy = LoopTemplate(
        id: "nightly-tidy", title: "Nightly tidy",
        summary: "Every night at 2:00 AM: fix warnings and drifted docs, commit on the loop branch.",
        name: "nightly-tidy", goal: "The repo builds without warnings and every tidy-up is committed on the loop branch.",
        check: "test -z \"$(git status --porcelain)\"",
        roundPrompt: "Tidy up: fix compiler and lint warnings, remove dead code, update docs that no longer match the code. Commit each tidy-up on this branch with a plain one-line message. Keep changes small and safe.",
        trigger: .at(hour: 2, minute: 0), limits: LoopLimits(maxRounds: 3, maxDuration: 3600, sameFailureStop: 2))

    public static let all = [fixUntilGreen, nightlyTidy]

    /// Templates derived from the built-in kit loops so "+ New loop" can also clone any built-in loop as Mine.
    public static func builtInTemplates(catalogPath: String? = AEFolder.loopsCatalog()) -> [LoopTemplate] {
        LoopBuiltIns.entries(from: catalogPath).map { e in
            LoopTemplate(
                id: e.id, title: e.title,
                summary: e.goal,
                name: "my-\(e.id)", goal: e.goal,
                check: e.check, roundPrompt: e.roundPrompt,
                trigger: .at(hour: e.hour, minute: e.minute),
                limits: LoopLimits(maxRounds: max(1, e.maxRounds), maxDuration: TimeInterval(max(1, e.maxMinutes) * 60), sameFailureStop: 2))
        }
    }
}

/// LAB-1663 · Built-in loops from the Agentic Engineering kit (`kit/loops/catalog.json` in the bundled deck or repo,
/// with an embedded fallback of the 8 built-in loops). Built-in loops always ship OFF (`.stopped`) so a kit update
/// never turns a loop on by surprise.
public enum LoopBuiltIns {
    public static let referenceDate = Date(timeIntervalSince1970: 1_761_782_400)

    public struct Entry: Codable, Equatable, Sendable {
        public var id: String
        public var name: String
        public var title: String
        public var origin: String
        public var goal: String
        public var check: String
        public var cron: String
        public var hour: Int
        public var minute: Int
        public var maxRounds: Int
        public var maxMinutes: Int
        public var costCapUsd: Double
        public var roundPrompt: String
        /// LAB-1922: the library's kind, how it acts, its trigger and what it writes (optional in older catalogs).
        public var kind: String?
        public var act: String?
        public var trigger: String?
        public var event: String?
        public var manual: Bool?
        public var library: Bool?
        public var writes: [String]?
        public var dryRun: String?

        public init(id: String, title: String, goal: String, cron: String, hour: Int, minute: Int,
                    maxRounds: Int = 1, maxMinutes: Int = 15, costCapUsd: Double = 0, roundPrompt: String = "") {
            self.id = id; self.name = id; self.title = title; self.origin = "built-in"; self.goal = goal
            self.check = "python3 -m ae.loops run \(id) --no-agent"; self.cron = cron; self.hour = hour; self.minute = minute
            self.maxRounds = maxRounds; self.maxMinutes = maxMinutes; self.costCapUsd = costCapUsd; self.roundPrompt = roundPrompt
        }
    }

    private struct CatalogFile: Codable {
        var version: Int?
        var loops: [Entry]
    }

    public static let fallbackEntries: [Entry] = [
        Entry(id: "cost-watch", title: "Cost watch",
              goal: "Spend per provider stays under the owner's limits, with a warning at 80 % and an alert on any usage-limit error.",
              cron: "0 9-23 * * *", hour: 9, minute: 0, maxRounds: 1, maxMinutes: 5),
        Entry(id: "dependency-security", title: "Dependency and security updates",
              goal: "Outdated or vulnerable dependencies in every repo are listed with a proposed update.",
              cron: "0 8 * * 1", hour: 8, minute: 0, maxRounds: 1, maxMinutes: 30),
        Entry(id: "docs-drift", title: "Docs drift",
              goal: "Always-on files, MEMORY.md and indexes are under their limits, links resolve and rendered files match their source, or each gap is proposed as a fix.",
              cron: "0 6 * * *", hour: 6, minute: 0, maxRounds: 1, maxMinutes: 10),
        Entry(id: "morning-health", title: "Morning health check",
              goal: "The stack starts, one real transaction passes and every reader shows the main edition, or a failure is reported before work starts.",
              cron: "30 7 * * *", hour: 7, minute: 30, maxRounds: 1, maxMinutes: 15),
        Entry(id: "nightly-reflection", title: "Nightly reflection",
              goal: "Every correction, repeated mistake and stale note from the last day is either proposed as a fix in proposals/ or recorded as \"nothing to change\".",
              cron: "30 2 * * *", hour: 2, minute: 30, maxRounds: 2, maxMinutes: 20, costCapUsd: 0.5),
        Entry(id: "regression-evals", title: "Regression evals",
              goal: "The golden task set still passes at or above its last baseline after any model, prompt or skill change.",
              cron: "0 3 * * *", hour: 3, minute: 0, maxRounds: 1, maxMinutes: 30, costCapUsd: 1.0),
        Entry(id: "usage-report", title: "Monthly usage report",
              goal: "Which Commands, hooks and loops fired this month, what they cost and what failed are recorded, with dead and missing items named.",
              cron: "0 9 1 * *", hour: 9, minute: 0, maxRounds: 1, maxMinutes: 20),
        Entry(id: "weekly-review", title: "Weekly review",
              goal: "Stale issues are re-planned, notes are pruned, repeated gotchas are proposed as rules, and the week's numbers are recorded: the four passes of the weekly-review card.",
              cron: "0 17 * * 5", hour: 17, minute: 0, maxRounds: 1, maxMinutes: 30, costCapUsd: 0.75),
    ]

    public static func entries(from catalogPath: String? = AEFolder.loopsCatalog()) -> [Entry] {
        if let p = catalogPath, let data = FileManager.default.contents(atPath: p),
           let decoded = try? JSONDecoder().decode(CatalogFile.self, from: data), !decoded.loops.isEmpty {
            return decoded.loops
        }
        return fallbackEntries
    }

    /// Where a built-in loop runs until you pick a repo: the Agentic Engineering checkout ONEROOF_AE_PATH names (a
    /// developer's own copy), else the shared folder (Settings › Foundations), else the projects folder.
    public static func defaultRepoPath(environment: [String: String] = ProcessInfo.processInfo.environment) -> String {
        let fm = FileManager.default
        if let e = environment["ONEROOF_AE_PATH"], !e.isEmpty {
            let p = (e as NSString).expandingTildeInPath
            if fm.fileExists(atPath: p + "/.git") { return p }
        }
        if let repo = Workspace.listRepos().first(where: { fm.fileExists(atPath: $0 + "/kit/loops/catalog.json") && fm.fileExists(atPath: $0 + "/.git") }) { return repo }
        if fm.fileExists(atPath: Workspace.sharedRoot + "/.git") { return Workspace.sharedRoot }
        return Workspace.projectsRoot
    }

    public static func load(catalogPath: String? = AEFolder.loopsCatalog(), repoPath: String? = nil) -> [Loop] {
        let repo = repoPath ?? defaultRepoPath()
        return entries(from: catalogPath).map { e in
            Loop(id: e.id, name: e.name, title: e.title, origin: .builtIn, goal: e.goal, check: e.check,
                 repoPath: repo, agent: .claude, roundPrompt: e.roundPrompt,
                 trigger: .at(hour: e.hour, minute: e.minute),
                 limits: LoopLimits(maxRounds: max(1, e.maxRounds), maxDuration: TimeInterval(max(1, e.maxMinutes) * 60), sameFailureStop: 2),
                 pinned: false, state: .stopped, createdAt: referenceDate)
            .with { $0.kind = e.kind; $0.act = e.act }
        }
    }
}

extension Loop {
    /// A changed copy (for building loops in one expression).
    public func with(_ change: (inout Loop) -> Void) -> Loop { var l = self; change(&l); return l }
}

/// LAB-1369 · how long the Mac has been quiet: no session a person started working or waiting on you. roofd probes
/// each live manual session (loop rounds are left out) and keeps the last time one was busy.
public enum LoopQuiet {
    /// One live manual session as its holder reports it: `status` (working · blocked · done · idle …) and its last
    /// activity.
    public struct Probe: Equatable, Sendable {
        public var status: String
        public var active: Date
        public init(status: String, active: Date) { self.status = status; self.active = active }
        public var busy: Bool { !["done", "idle"].contains(status) }
    }

    /// (quiet for, the new last-busy time). Busy now = nil (never quiet). Otherwise the time since the later of the
    /// last busy moment and the newest activity.
    public static func quietFor(now: Date, probes: [Probe], lastBusy: Date) -> (TimeInterval?, Date) {
        if probes.contains(where: \.busy) { return (nil, now) }
        let last = max(lastBusy, probes.map(\.active).max() ?? .distantPast)
        return (max(0, now.timeIntervalSince(last)), lastBusy)
    }
}
