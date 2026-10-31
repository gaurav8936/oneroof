import Foundation

/// LAB-1921 · describe a loop in plain words and get a draft: name, goal, check, trigger and limits, plus a dry-run
/// preview of what the first run would do before you save.
///
/// An agent drafts it when one is available (the command in `ONEROOF_LOOP_DRAFTER`, else `claude -p`), answering
/// with one JSON object. Without an agent, or when its answer cannot be read, a rule-based drafter reads the words
/// ("every night at 3", "when quiet", "when a new bug comes in", "until the tests pass", "at most 5 rounds") so the
/// form is never left empty. Either way you see the draft in the editor and change it before saving; nothing runs
/// until you press Save (or Save and run).
public enum LoopDrafter {
    public struct Draft: Equatable, Sendable {
        public var name: String
        public var goal: String
        public var check: String
        public var trigger: LoopTrigger
        public var limits: LoopLimits
        public var roundPrompt: String
        /// Plain-words notes: what the drafter assumed or could not fill.
        public var notes: [String]
        /// "agent" or "rules".
        public var source: String

        public func apply(to loop: Loop) -> Loop {
            var l = loop
            if !name.isEmpty { l.name = name }
            l.goal = goal
            if !check.isEmpty { l.check = check }
            l.trigger = trigger; l.limits = limits
            if !roundPrompt.isEmpty { l.roundPrompt = roundPrompt }
            return l
        }
    }

    // MARK: Rules

    public static func rules(_ text: String) -> Draft {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let low = t.lowercased()
        var notes: [String] = []
        var trigger: LoopTrigger = .untilDone(everyMinutes: 0)
        let hm = clock(in: low)
        let weekday = ["monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday"].first { low.contains("every " + $0) || low.contains("on " + $0 + "s") }
        if let e = event(in: low) {
            trigger = .onEvent(e)
        } else if low.contains("when quiet") || low.contains("when it's quiet") || low.contains("when i'm away") || low.contains("when idle") || low.contains("no session") {
            let w = window(in: low)
            trigger = .whenQuiet(quietMinutes: minutes(after: ["quiet for", "idle for"], in: low) ?? 15, fromHour: w?.0, toHour: w?.1)
        } else if low.contains("every night") || low.contains("nightly") || low.contains("each night") || low.contains("every day")
                    || low.contains("daily") || low.contains("every morning") || weekday != nil || hm != nil {
            let (h, m) = hm ?? (low.contains("morning") ? (7, 0) : (2, 0))
            trigger = .at(hour: h, minute: m)
            if hm == nil { notes.append("No time given: it runs at \(Schedule.clock(h, m)); change it under Runs.") }
            if let d = weekday { notes.append("One Roof runs loops every day; for \(d.capitalized)s only, make it an ae loop (cron) or have the check skip other days.") }
        } else if let every = minutes(after: ["every"], in: low) {
            trigger = .untilDone(everyMinutes: every)
        }
        var check = ""
        for (needle, cmd) in [("swift test", "swift test"), ("npm test", "npm test"), ("pytest", "pytest -q"), ("cargo test", "cargo test"),
                              ("go test", "go test ./..."), ("make test", "make test"), ("vitest", "npx vitest run")] where low.contains(needle) {
            check = cmd; break
        }
        if check.isEmpty, let q = quoted(t) { check = q }
        if check.isEmpty { notes.append("Set the check: the command that exits 0 when the goal is met (Test the check runs it once).") }
        var limits = LoopLimits()
        if let r = number(before: ["rounds", "round", "tries", "attempts"], in: low) { limits.maxRounds = max(1, min(r, 50)) }
        if let h = number(before: ["hours", "hour"], in: low) { limits.maxDuration = TimeInterval(max(1, min(h, 24)) * 3600) }
        else if let m = number(before: ["minutes", "min"], in: low), !(trigger.isQuiet) { limits.maxDuration = TimeInterval(max(15, min(m, 1440)) * 60) }
        if trigger.isArmed && limits.maxRounds == LoopLimits().maxRounds && check.isEmpty { limits.maxRounds = 3 }
        let goal = sentence(withoutTrigger(t))
        return Draft(name: Loop.slug(String(goal.split(separator: " ").prefix(5).joined(separator: " "))), goal: goal, check: check,
                     trigger: trigger, limits: limits, roundPrompt: "", notes: notes, source: "rules")
    }

    /// The words without the opening "when / how often" clause, so the goal and name say what the loop is for.
    static func withoutTrigger(_ t: String) -> String {
        let patterns = [
            #"^(every|each) (night|day|morning|monday|tuesday|wednesday|thursday|friday|saturday|sunday)( at [0-9:]+( ?[ap]m)?)?[,;]?\s+"#,
            #"^(nightly|daily)( at [0-9:]+( ?[ap]m)?)?[,;]?\s+"#,
            #"^when (it'?s )?(quiet|idle|i'?m away)( for [0-9]+ \w+)?( between [0-9]+ and [0-9]+)?[,;]?\s+"#,
            #"^(when|after|on) (a |every )?(new (bug|issue)( comes in| is created)?|ci fails|the pipeline fails|a push|push|a release|release)[,;]?\s+"#,
        ]
        var out = t.trimmingCharacters(in: .whitespacesAndNewlines)
        for p in patterns {
            if let r = out.range(of: p, options: [.regularExpression, .caseInsensitive]), r.lowerBound == out.startIndex {
                let rest = String(out[r.upperBound...])
                if rest.count >= 8 { out = rest }
            }
        }
        return out
    }

    static func event(in low: String) -> String? {
        if low.contains("new bug") || low.contains("new issue") || low.contains("issue is created") || low.contains("issue comes in") { return "linear.issue.created" }
        if low.contains("ci fails") || low.contains("ci is red") || low.contains("pipeline fails") || low.contains("build fails") || low.contains("red build") { return "woodpecker.pipeline.failed" }
        if low.contains("after a push") || low.contains("on push") || low.contains("when i push") || low.contains("after every push") { return "git.push" }
        if low.contains("after a release") || low.contains("after every release") || low.contains("on release") { return "oneroof.release" }
        return nil
    }

    /// "at 3", "at 3:30", "at 3 am", "at 11 pm", "at 23:15".
    static func clock(in low: String) -> (Int, Int)? {
        let words = low.replacingOccurrences(of: ",", with: " ").split(separator: " ").map(String.init)
        for (i, w) in words.enumerated() where w == "at" && i + 1 < words.count {
            let tok = words[i + 1].trimmingCharacters(in: CharacterSet(charactersIn: ".!?"))
            var digits = tok, suffix = i + 2 < words.count ? words[i + 2] : ""
            for s in ["am", "pm"] where tok.hasSuffix(s) { digits = String(tok.dropLast(2)); suffix = s }
            let parts = digits.split(separator: ":").map(String.init)
            guard var h = Int(parts[0]), h >= 0, h <= 23 else { continue }
            let m = parts.count > 1 ? (Int(parts[1]) ?? 0) : 0
            if suffix.hasPrefix("pm"), h < 12 { h += 12 }
            if suffix.hasPrefix("am"), h == 12 { h = 0 }
            return (h, max(0, min(m, 59)))
        }
        return nil
    }

    /// "between 1 and 6" → (1, 6).
    static func window(in low: String) -> (Int, Int)? {
        let words = low.split(separator: " ").map(String.init)
        for (i, w) in words.enumerated() where w == "between" && i + 3 < words.count && words[i + 2] == "and" {
            if let a = Int(words[i + 1].filter(\.isNumber)), let b = Int(words[i + 3].filter(\.isNumber)), a < 24, b < 24 { return (a, b) }
        }
        return nil
    }

    static func minutes(after keys: [String], in low: String) -> Int? {
        for k in keys {
            guard let r = low.range(of: k + " ") else { continue }
            let rest = low[r.upperBound...].split(separator: " ").map(String.init)
            guard let n = rest.first.flatMap({ Int($0) }) else { continue }
            let unit = rest.count > 1 ? rest[1] : "minutes"
            return unit.hasPrefix("h") ? n * 60 : n
        }
        return nil
    }

    static func number(before units: [String], in low: String) -> Int? {
        let words = low.split(separator: " ").map { $0.trimmingCharacters(in: CharacterSet(charactersIn: ".,;")) }
        for (i, w) in words.enumerated() where i > 0 && units.contains(w) {
            if let n = Int(words[i - 1]) { return n }
        }
        return nil
    }

    static func quoted(_ t: String) -> String? {
        guard let a = t.firstIndex(of: "`") else { return nil }
        let rest = t[t.index(after: a)...]
        guard let b = rest.firstIndex(of: "`") else { return nil }
        let q = String(rest[..<b]).trimmingCharacters(in: .whitespaces)
        return q.isEmpty ? nil : q
    }

    static func sentence(_ t: String) -> String {
        let one = t.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespaces)
        guard let f = one.first else { return "" }
        return String(f).uppercased() + one.dropFirst()
    }

    // MARK: Agent

    /// The instruction the drafting agent gets (it answers with one JSON object, no prose).
    public static func agentPrompt(_ text: String, repo: String) -> String {
        """
        Draft a One Roof loop from this description. A loop repeats work until a check (a shell command run in the \
        repo's loop worktree, exit 0 = done) passes, or starts on a trigger. Answer with ONE JSON object and nothing \
        else, with these keys:
        {"name": "short-kebab-name", "goal": "one sentence: the end state", "check": "a shell command that exits 0 when the goal holds", \
        "trigger": {"when": "until-done" | "nightly" | "quiet" | "event", "hour": 0-23, "minute": 0-59, "quietMinutes": 15, \
        "fromHour": null, "toHour": null, "event": "linear.issue.created" | "woodpecker.pipeline.failed" | "git.push" | "oneroof.release"}, \
        "maxRounds": 1-50, "maxMinutes": 15-1440, "roundPrompt": "extra instructions for every round, or empty", \
        "notes": ["anything you assumed"]}
        The check must run unaided with no person present and must be a command, not a sentence. Prefer a check that \
        tests the goal itself, not that a record was written.
        Repo: \(repo)
        Description: \(text)
        """
    }

    /// Read the agent's answer (the first `{…}` object in it). nil when it is not a usable draft.
    public static func parse(agentOutput out: String) -> Draft? {
        guard let a = out.firstIndex(of: "{"), let b = out.lastIndex(of: "}"), a < b,
              let data = String(out[a...b]).data(using: .utf8),
              let o = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        let goal = (o["goal"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !goal.isEmpty else { return nil }
        let tr = o["trigger"] as? [String: Any] ?? [:]
        func int(_ v: Any?) -> Int? { (v as? Int) ?? (v as? Double).map(Int.init) ?? (v as? String).flatMap(Int.init) }
        let trigger: LoopTrigger
        switch (tr["when"] as? String ?? "until-done").lowercased() {
        case "nightly", "clock", "daily": trigger = .at(hour: max(0, min(int(tr["hour"]) ?? 2, 23)), minute: max(0, min(int(tr["minute"]) ?? 0, 59)))
        case "quiet": trigger = .whenQuiet(quietMinutes: max(1, int(tr["quietMinutes"]) ?? 15), fromHour: int(tr["fromHour"]), toHour: int(tr["toHour"]))
        case "event":
            let e = tr["event"] as? String ?? ""
            trigger = LoopTrigger.knownEvents.contains(e) ? .onEvent(e) : .untilDone(everyMinutes: 0)
        default: trigger = .untilDone(everyMinutes: 0)
        }
        var limits = LoopLimits()
        if let r = int(o["maxRounds"]) { limits.maxRounds = max(1, min(r, 50)) }
        if let m = int(o["maxMinutes"]) { limits.maxDuration = TimeInterval(max(15, min(m, 1440)) * 60) }
        let name = Loop.slug(o["name"] as? String ?? goal)
        let check = LoopSpecLint.clean(o["check"] as? String ?? "")
        return Draft(name: name, goal: goal, check: check, trigger: trigger, limits: limits,
                     roundPrompt: (o["roundPrompt"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
                     notes: (o["notes"] as? [String]) ?? [], source: "agent")
    }

    /// The drafting command (prompt as its last argument): `ONEROOF_LOOP_DRAFTER`, else `claude -p`; nil = none.
    public static func command(environment env: [String: String] = ProcessInfo.processInfo.environment) -> [String]? {
        if let c = env["ONEROOF_LOOP_DRAFTER"], !c.isEmpty { return [c] }
        return LoopHarvest.which("claude", environment: env).map { [$0, "-p", "--output-format", "text"] }
    }

    /// Draft with the agent, falling back to the rules (with a note saying why). Blocking: call off the main thread.
    public static func draft(_ text: String, repo: String, command: [String]? = LoopDrafter.command(),
                             environment: [String: String] = ProcessInfo.processInfo.environment, timeout: TimeInterval = 120) -> Draft {
        guard let cmd = command, let exe = cmd.first else {
            var d = rules(text); d.notes.insert("No drafting agent found: drafted from your words by rules.", at: 0); return d
        }
        let (rc, out) = Foundations.run(exe, Array(cmd.dropFirst()) + [agentPrompt(text, repo: repo)], cwd: repo, timeout: timeout, environment: environment)
        if rc == 0, let d = parse(agentOutput: out) { return d }
        var d = rules(text)
        d.notes.insert(rc == 0 ? "The agent's draft could not be read: drafted from your words by rules." : "The drafting agent failed (exit \(rc)): drafted from your words by rules.", at: 0)
        return d
    }

    // MARK: Dry run

    /// What the first run would do, in order, without running anything but (optionally) the check.
    public static func preview(_ loop: Loop, now: Date = Date()) -> [String] {
        var out: [String] = []
        switch loop.trigger {
        case .untilDone: out.append("Starts when you press Run now.")
        case .at(let h, let m): out.append("Starts tonight at \(Schedule.clock(h, m)) (only while this Mac is awake), once a night.")
        case .whenQuiet(let q, let f, let t):
            out.append("Starts once no session of yours has been working or waiting on you for \(Schedule.every(q))"
                       + (f != nil && t != nil ? ", between \(Schedule.clock(f!, 0)) and \(Schedule.clock(t!, 0))" : "") + ", at most once a "
                       + (f != nil && t != nil ? "night." : "day."))
        case .onEvent(let e): out.append("Starts when \(e) is fired (`ae loops fire \(e)`), once per event.")
        }
        out.append("Makes its own worktree \((loop.worktreePath as NSString).abbreviatingWithTildeInPath) on branch \(loop.branch); never your checkout.")
        out.append("Runs the check first: `\(loop.check.isEmpty ? "(no check yet)" : loop.check)`. If it already passes, no round is needed.")
        out.append("Otherwise round 1 starts a \(loop.agent.displayName) session told:")
        var probe = loop
        if probe.id.isEmpty { probe.id = Loop.slug(probe.name.isEmpty ? "new-loop" : probe.name) }
        out.append(LoopPrompt.render(probe, round: 1, rounds: []))
        out.append("Stops after \(loop.limits.label). Nothing is pushed or merged: commits wait in Today for your approval.")
        return out
    }
}
