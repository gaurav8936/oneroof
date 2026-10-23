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

    public var label: String {
        switch self {
        case .untilDone(let m): return m <= 0 ? "Until done" : "Until done · every " + Schedule.every(m)
        case .at(let h, let m): return "Nightly " + Schedule.clock(h, m)
        }
    }

    public var isNightly: Bool { if case .at = self { return true }; return false }
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

public struct Loop: Codable, Identifiable, Equatable, Sendable {
    public var id: String
    public var name: String
    public var goal: String
    /// A shell command (zsh -lc) run in the loop's worktree; exit 0 = done.
    public var check: String
    /// The repo the loop works on; rounds run in `<repo>/.worktrees/loop-<name>` on branch `loop/<name>` (LoopWorktree).
    public var repoPath: String
    public var agent: AgentKind
    public var model: String?
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

    public init(id: String, name: String, goal: String = "", check: String = "", repoPath: String,
                agent: AgentKind = .claude, model: String? = nil, account: String? = nil, roundPrompt: String = "",
                trigger: LoopTrigger = .untilDone(everyMinutes: 0), limits: LoopLimits = LoopLimits(), pinned: Bool = false,
                state: LoopState = .stopped, createdAt: Date = Date(), checkTimeout: TimeInterval = 600) {
        self.id = id; self.name = name; self.goal = goal; self.check = check; self.repoPath = repoPath
        self.agent = agent; self.model = model; self.account = account; self.roundPrompt = roundPrompt
        self.trigger = trigger; self.limits = limits; self.pinned = pinned; self.state = state; self.createdAt = createdAt
        self.checkTimeout = checkTimeout; self.run = nil; self.runRequested = false; self.lastRunAt = nil; self.stopReason = nil
    }

    enum CodingKeys: String, CodingKey {
        case id, name, goal, check, repoPath, agent, model, account, roundPrompt, trigger, limits, pinned, state, createdAt,
             checkTimeout, run, runRequested, lastRunAt, stopReason
    }

    public init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? id
        goal = try c.decodeIfPresent(String.self, forKey: .goal) ?? ""
        check = try c.decodeIfPresent(String.self, forKey: .check) ?? ""
        repoPath = try c.decodeIfPresent(String.self, forKey: .repoPath) ?? ""
        agent = try c.decodeIfPresent(AgentKind.self, forKey: .agent) ?? .claude
        model = try c.decodeIfPresent(String.self, forKey: .model)
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
                            calendar: Calendar = .current) -> LoopDecision {
        if loop.state == .paused { return .wait }
        guard let run = loop.run else {
            // Not in a run: start one on Run now, or at a nightly loop's time.
            if loop.runRequested || nightlyDue(loop, now: now, calendar: calendar) { return .runCheck }
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
        // Anything that may still start rounds: a run in progress, or a nightly loop that has not been stopped.
        if l.state.isActive || (l.trigger.isNightly && l.state != .stopped) { l.state = .paused }
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
}
