import Foundation

// LAB-ONEROOF-v2.0.6 · Loops v7 lane C (Claude Design 7h · 7i · 7m · 7n): how a loop is set up. Pure: the views draw what
// this returns.
//   7h  Library (definitions): one row per loop, same columns whoever made it; kind tabs; state chips; the setup panel
//   7i  New loop: a kind guessed from the description, the trial runs and where the loop will show
//   7m  Edit: Set kind (LP-2) per engine, owner suggestions for the kind-less loops, the delete copy
//   7n  States: the banners (roofd down, paused, kit unknown, a write failed) and the needs-setup list (LP-11)

public enum LoopsV7Setup {

    // MARK: - 7h · Library rows

    /// The Library's state chips: Any · On · Off · Needs setup · Failing.
    public enum LibraryState: String, CaseIterable, Equatable, Sendable {
        case on, off, needsSetup, failing
        public var label: String {
            switch self {
            case .on: return "On"
            case .off: return "Off"
            case .needsSetup: return "Needs setup"
            case .failing: return "Failing"
            }
        }
    }

    /// One loop's definition as the Library shows it.
    public struct LibraryRow: Equatable, Sendable, Identifiable {
        public var id: String
        public var name: String
        /// "mine" or "built-in".
        public var origin: String
        public var engine: LoopEngine
        /// watch · check · improve · report · other.
        public var family: String
        /// "Watch · Sentinel", "Other · no kind".
        public var kindWords: String
        /// The kind's own title ("Sentinel"), or "no kind".
        public var subtype: String
        /// What it watches or does: its goal's first sentence.
        public var watches: String
        public var goal: String
        /// Schedule words ("every 10 min", "nightly 3:00", "manual", "on git.push").
        public var when: String
        /// "report", "issue", "proposals", "commits", "prompt you".
        public var mayAct: String
        public var stateLabel: String
        public var tone: LoopLook.Tone
        /// The loop's file (a kit file's .loop.yaml, or One Roof's loop.json), nil for a built-in the kit keeps.
        public var file: String?
        public var on: Bool
        public var needsSetup: Bool
        public var failing: Bool
        /// "mine · by kit".
        public var originLine: String { origin + " · by " + (engine == .kit ? "kit" : "One Roof") }
    }

    /// "Watch · Sentinel" for a known kind, "Other · no kind" otherwise.
    public static func kindWords(family: String, kind: String?) -> String {
        let f = LoopKinds.family(family)?.title ?? "Other"
        return f + " · " + (LoopKinds.kind(kind)?.title ?? "no kind")
    }

    /// May act by, in plain words: the kit's `act.by` (none · issue · pr · prompt) for its loops; a One Roof loop commits on
    /// its own branch. A learner that acts by nothing still leaves proposals for you.
    public static func mayAct(act: String?, kind: String?, engine: LoopEngine) -> String {
        switch act {
        case "issue": return "issue"
        case "pr": return "proposals"
        case "prompt": return "prompt you"
        case "commit", "commits": return "commits"
        case "none", nil:
            if kind == "learner" { return "proposals" }
            if act == nil && engine == .oneRoof { return "commits" }
            return "report"
        default: return act ?? "report"
        }
    }

    /// The sentence the setup panel shows for May act by.
    public static func mayActSentence(_ words: String) -> String {
        switch words {
        case "issue": return "Opening an issue with what it found. It never pushes, merges or deploys."
        case "proposals": return "Proposals you approve or reject in Needs you. Nothing is merged without you."
        case "prompt you": return "Prompting you. It never acts on its own."
        case "commits": return "Commits on its own branch; a pull request opens only after you approve it in Needs you."
        default: return "A report in the journal only. It changes nothing."
        }
    }

    /// "every 10 min, by the kit (ae, on launchd)." · "nightly 3:00, by One Roof (roofd), with the app open or closed."
    public static func whoRuns(when: String, engine: LoopEngine) -> String {
        engine == .kit ? "\(when), by the kit (ae, on launchd)." : "\(when), by One Roof (roofd), with the app open or closed."
    }

    /// One Roof's engine has no shadow mode: its first runs are labelled trial (they work only on the loop's own branch and
    /// nothing leaves it without you). True while the loop is on and has fewer than `trialRuns` runs since it was made.
    public static func oneRoofTrial(on: Bool, runsSinceCreated: Int) -> Bool { on && runsSinceCreated < trialRuns }

    /// The number of trial (shadow) runs a loop starts with (LP-12, LPO-3).
    public static let trialRuns = 3

    /// The state words and their tone: needs setup (with the key, elsewhere) wins over off; kit loops say "kit state
    /// unknown" when the kit could not be read, never a guessed off.
    public static func state(_ r: LoopRow, needsSetup: Bool, kitKnown: Bool, oneRoofTrial: Bool = false) -> (label: String, tone: LoopLook.Tone) {
        if r.engine == .kit && !kitKnown { return ("kit state unknown", .off) }
        if needsSetup { return (r.on ? "on · needs setup" : "needs setup", .needsYou) }
        guard r.on else { return ("off", .off) }
        if r.state == .failing { return ("on · failing", .failing) }
        if r.mode == .shadow || oneRoofTrial { return ("on · trial", .trial) }
        if r.state == .running { return ("on · running", .running) }
        return ("on · live", .fine)
    }

    public static func libraryRow(_ r: LoopRow, loop: Loop?, act: String?, needsSetup: Bool, kitKnown: Bool,
                                  oneRoofTrial: Bool = false, file: String?) -> LibraryRow {
        let (label, tone) = state(r, needsSetup: needsSetup, kitKnown: kitKnown, oneRoofTrial: oneRoofTrial)
        return LibraryRow(id: r.id, name: r.name, origin: r.mine ? "mine" : "built-in", engine: r.engine, family: r.family,
                          kindWords: kindWords(family: r.family, kind: r.kind), subtype: LoopKinds.kind(r.kind)?.title ?? "no kind",
                          watches: LoopsV7.shortGoal(r.goal.isEmpty ? r.name : r.goal), goal: r.goal, when: when(r, loop: loop),
                          mayAct: mayAct(act: act, kind: r.kind, engine: r.engine), stateLabel: label, tone: tone, file: file,
                          on: r.on, needsSetup: needsSetup, failing: r.state == .failing)
    }

    /// Schedule words, with the triggers a cron can't say ("on git.push", "when quiet", "until done").
    public static func when(_ r: LoopRow, loop: Loop?) -> String {
        if r.schedule != "manual" { return r.schedule }
        guard let l = loop else { return r.schedule }
        if let ext = l.externalSchedule, ext.hasPrefix("on ") || ext.hasPrefix("when quiet") {
            return ext.hasPrefix("when quiet") ? "when quiet" : ext
        }
        if l.isKitFile || l.origin == .builtIn { return "manual" }
        switch l.trigger {
        case .onEvent(let e): return "on " + e
        case .whenQuiet: return "when quiet"
        case .untilDone: return "until done"
        case .at(let h, let m): return String(format: "nightly %d:%02d", h, m)
        }
    }

    /// Kind tabs: All first, then Watch · Check · Improve · Report · Other with their counts.
    public static func kindCounts(_ rows: [LibraryRow]) -> [(id: String, title: String, count: Int)] {
        [("all", "All", rows.count)] + LoopsV7.laneOrder.map { fid in
            (fid, LoopKinds.family(fid)?.title ?? fid, rows.filter { $0.family == fid }.count)
        }
    }

    /// Search (name, what it watches or does, its kind and subtype, its file) and the kind and state chips.
    public static func filter(_ rows: [LibraryRow], query: String, family: String?, state: LibraryState?) -> [LibraryRow] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        return rows.filter { r in
            if let f = family, f != "all", r.family != f { return false }
            switch state {
            case .on?: if !r.on || r.needsSetup { return false }
            case .off?: if r.on || r.needsSetup { return false }
            case .needsSetup?: if !r.needsSetup { return false }
            case .failing?: if !r.failing { return false }
            case nil: break
            }
            guard !q.isEmpty else { return true }
            return [r.name, r.id, r.watches, r.goal, r.kindWords, r.subtype, r.file ?? ""].contains { $0.lowercased().contains(q) }
        }
    }

    /// "31 of 31".
    public static func countLine(shown: Int, all: Int) -> String { "\(shown) of \(all)" }

    /// The empty line under a filter that matched nothing.
    public static func emptyLine(query: String, family: String?, state: LibraryState?) -> String {
        var parts: [String] = []
        let q = query.trimmingCharacters(in: .whitespaces)
        if !q.isEmpty { parts.append("“\(q)”") }
        if let f = family, f != "all" { parts.append(LoopKinds.family(f)?.title ?? f) }
        if let s = state { parts.append(s.label.lowercased()) }
        return "No loop matches " + (parts.isEmpty ? "this filter" : parts.joined(separator: " · ")) + "."
    }

    /// Library order: Watch · Check · Improve · Report · Other; inside a kind, loops that are on first, then by name.
    public static func ordered(_ rows: [LibraryRow]) -> [LibraryRow] {
        let order = Dictionary(uniqueKeysWithValues: LoopsV7.laneOrder.enumerated().map { ($1, $0) })
        return rows.sorted { a, b in
            let (fa, fb) = (order[a.family] ?? 9, order[b.family] ?? 9)
            if fa != fb { return fa < fb }
            if a.on != b.on { return a.on }
            return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
        }
    }

    // MARK: - 7i · New loop

    /// A kind from the words of a description (a starting point the owner changes in part 3): fix → Fixer, watch/alert →
    /// Sentinel, a site or release → Prober, a summary → Reporter, a check against a rule or "is green" → Auditor.
    public static func guessKind(_ text: String) -> String? {
        let s = text.lowercased()
        func has(_ words: [String]) -> Bool { words.contains { s.contains($0) } }
        if has(["fix ", "fix,", "fixes", "repair", "until the check passes", "until it passes"]) { return "fixer" }
        if has(["summar", "digest", "report", "brief", "recap"]) { return "reporter" }
        if has(["refresh", "update the data", "keep current", "upstream"]) { return "refresher" }
        if has(["site", "release", "backup", "probe", "ping"]) { return "prober" }
        if has(["watch", "alert", "spend", "cost", "memory", "usage", "threshold"]) { return "sentinel" }
        if has(["triage", "review new", "verdict", "label"]) { return "judge" }
        if has(["check", "green", "audit", "lint", "drift", "test", "passes"]) { return "auditor" }
        return nil
    }

    /// The first `count` times a loop's trigger would start it from `now` (nightly: the next nights; when quiet: the next
    /// nights in its window), nil for loops started by hand or by an event (their trial runs are the next ones, whenever).
    public static func nextStarts(_ trigger: LoopTrigger, now: Date, count: Int, calendar cal: Calendar = .current) -> [Date]? {
        let hm: (Int, Int)
        switch trigger {
        case .at(let h, let m): hm = (h, m)
        case .whenQuiet(_, let from, _): hm = (from ?? 1, 0)
        case .untilDone, .onEvent: return nil
        }
        guard let c = CronSpec("\(hm.1) \(hm.0) * * *") else { return nil }
        return Array(c.times(from: now, to: now.addingTimeInterval(Double(count + 2) * 86400), calendar: cal).prefix(count))
    }

    /// 7i's trial card: three trial runs, then "goes live if you say so". Dates when the trigger has them, else run numbers.
    public static func trialPlan(_ trigger: LoopTrigger, now: Date, calendar cal: Calendar = .current) -> [(when: String, what: String)] {
        let times = nextStarts(trigger, now: now, count: trialRuns + 1, calendar: cal)
        func day(_ i: Int) -> String {
            guard let t = times, i < t.count else {
                switch trigger {
                case .onEvent: return "event \(i + 1)"
                default: return "run \(i + 1)"
                }
            }
            let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.calendar = cal; f.timeZone = cal.timeZone
            f.dateFormat = "EEE d"
            return f.string(from: t[i])
        }
        var out: [(String, String)] = []
        for i in 0..<trialRuns {
            out.append((day(i), i == 0 ? "trial 1: checks, says what it would do" : "trial \(i + 1)"))
        }
        out.append((day(trialRuns), "goes live if you say so"))
        return out
    }

    /// "Check goes from 2 / 8 to 3 / 9 on." for the kind a new loop lands in.
    public static func laneChange(family: String, rows: [LoopRow], turnsOn: Bool) -> String {
        let mine = rows.filter { $0.family == family }
        let on = mine.filter(\.on).count, all = mine.count
        let title = LoopKinds.family(family)?.title ?? "Other"
        return "\(title) goes from \(on) / \(all) to \(on + (turnsOn ? 1 : 0)) / \(all + 1) on."
    }

    // MARK: - 7m · Set kind (LP-2)

    /// How a loop's kind can be changed: in the kit's file through `ae loops edit` (the kit validates it; One Roof never
    /// rewrites a kit file), in One Roof's loop.json through LoopStore, or not at all (a built-in shows its catalog kind).
    public enum KindEdit: Equatable, Sendable {
        case kitFile(String)
        case oneRoof
        case builtIn(String?)
    }

    public static func kindEdit(_ l: Loop) -> KindEdit {
        if l.origin == .builtIn { return .builtIn(l.kind) }
        if let f = l.specFile { return .kitFile(f) }
        return .oneRoof
    }

    /// The owner's suggested kinds for the four loops with none (LPO-6, 2026-11-06). A suggestion only: pre-selected in the
    /// picker, never written without the owner pressing Set kind.
    public static let ownerSuggestions: [String: String] = [
        "oneroof-nightly-bugs": "fixer",
        "my-agent-xray": "reporter",
        "my-weekly-review": "reporter",
        "oneroof-nightly-compare": "judge",
    ]

    /// The kind to pre-select: the loop's own, else the owner's suggestion, else nil.
    public static func suggestedKind(_ l: Loop) -> String? {
        if let k = l.kind, LoopKinds.kind(k) != nil { return k }
        return ownerSuggestions[l.id]
    }

    /// "Improve · Fixer fits." under the Kind field of a loop with none.
    public static func suggestionLine(_ l: Loop) -> String? {
        guard LoopKinds.kind(l.kind) == nil, let k = ownerSuggestions[l.id], let kind = LoopKinds.kind(k) else { return nil }
        return "Set one to move it into a lane: " + (kind.family?.title ?? "Other") + " · " + kind.title + " fits."
    }

    public static func validKind(_ k: String) -> Bool { LoopKinds.kind(k) != nil }

    /// `python3 -m ae.loops edit <name> --set kind=<kind>`, run in the kit repo.
    public static func setKindCommand(name: String, kind: String) -> [String] {
        ["python3", "-m", "ae.loops", "edit", name, "--set", "kind=" + kind]
    }

    // MARK: - 7m · Delete

    /// The delete dialog's copy (exact, from the 2.0.5 alert).
    public static func deleteMessage(worktree: String, branch: String) -> String {
        "Its loop.json, state.json and round log are removed. Its worktree \(worktree) and branch \(branch) stay, with any work in them."
    }

    /// The staged-items warning: commits one loop left waiting, and other staged outcomes.
    public static func stagedWarning(_ staged: [LoopLedger.Outcome]) -> String? {
        let open = staged.filter { $0.status == "staged" }
        guard !open.isEmpty else { return nil }
        let commits = open.filter { $0.kind == "commit" }.count, other = open.count - commits
        var parts: [String] = []
        if commits > 0 { parts.append("\(commits) commit\(commits == 1 ? "" : "s") on that branch \(commits == 1 ? "is" : "are")") }
        if other > 0 { parts.append("\(other) other item\(other == 1 ? "" : "s") \(other == 1 ? "is" : "are")") }
        return parts.joined(separator: " and ") + " still waiting for you. They stay, but leave Needs you."
    }

    // MARK: - 7n · Needs setup (LP-11)

    public struct SetupItem: Equatable, Sendable, Identifiable {
        public var id: String { loop + "|" + (key ?? tool ?? need) }
        public var loop: String
        public var title: String
        /// "Needs the commands to run", "Needs a tool that isn't installed".
        public var need: String
        /// The config key, `loops.settings.<loop>.<key>`.
        public var key: String?
        public var tool: String?
        /// "Set up" (open the config at that key) or "Install".
        public var button: String { tool == nil ? "Set up" : "Install" }
    }

    static func needWords(_ setting: String) -> String {
        switch setting {
        case "commands": return "Needs the commands to run"
        case "usd_per_mtok": return "Needs a price table"
        case "limits": return "Needs a spend limit"
        default: return "Needs a setting"
        }
    }

    /// Every loop missing a setting or a tool, one line per missing thing (from LoopSetup's needs and the kit config).
    public static func setupItems(loops: [Loop], config: String?, toolInstalled: (String) -> Bool) -> [SetupItem] {
        var out: [SetupItem] = []
        for l in loops {
            for n in LoopSetup.needs(l.id) {
                if let key = n.setting {
                    let set = config.flatMap { AEConfig.node(["loops", "settings", l.id] + key, in: $0) }?.isSet ?? false
                    if !set {
                        out.append(SetupItem(loop: l.id, title: l.displayTitle, need: needWords(key.last ?? ""),
                                             key: (["loops", "settings", l.id] + key).joined(separator: "."), tool: nil))
                    }
                }
                if let tool = n.tool, !toolInstalled(tool) {
                    out.append(SetupItem(loop: l.id, title: l.displayTitle, need: "Needs a tool that isn't installed", key: nil, tool: tool))
                }
            }
        }
        return out
    }

    /// "4 loops need a setting before they can run".
    public static func setupTitle(_ items: [SetupItem]) -> String {
        let n = Set(items.map(\.loop)).count
        return "\(n) loop\(n == 1 ? " needs" : "s need") a setting before \(n == 1 ? "it" : "they") can run"
    }

    // MARK: - 7n · Banners

    public enum Banner: Equatable, Sendable {
        /// roofd is not answering: its own status line, and One Roof's loops that wait for it.
        case roofdDown(line: String, waiting: [String])
        /// Every One Roof loop that runs on its own is paused: how many, and what is skipped.
        case paused(count: Int, skipped: [String])
        /// `ae loops list` could not be read.
        case kitUnknown
        /// A write failed: the action and the reason.
        case writeFailed(action: String, reason: String)
    }

    /// "Save: could not save …" → ("Save", "could not save …").
    public static func splitError(_ e: String) -> (action: String, reason: String) {
        guard let r = e.range(of: ": ") else { return ("A change", e) }
        return (String(e[..<r.lowerBound]), String(e[r.upperBound...]))
    }

    /// The banners to show, most serious first.
    public static func banners(roofdOK: Bool, roofdLine: String, loops: [Loop], rows: [LoopRow], kitKnown: Bool, error: String?) -> [Banner] {
        var out: [Banner] = []
        if let e = error, !e.isEmpty { let s = splitError(e); out.append(.writeFailed(action: s.action, reason: s.reason)) }
        if !roofdOK {
            let waiting = rows.filter { $0.engine == .oneRoof && $0.on }.map(\.name).sorted()
            out.append(.roofdDown(line: roofdLine, waiting: waiting))
        }
        let own = loops.filter { !$0.isKitFile && $0.origin != .builtIn }
        let paused = own.filter { $0.state == .paused }
        if !paused.isEmpty, !own.contains(where: { $0.state.isActive }) {
            out.append(.paused(count: paused.count, skipped: paused.map(\.displayTitle).sorted()))
        }
        if !kitKnown { out.append(.kitUnknown) }
        return out
    }

    /// "One Roof nightly bugs, my-morning-brief +1".
    public static func names(_ n: [String], max: Int = 3) -> String {
        n.count <= max ? n.joined(separator: ", ") : n.prefix(max).joined(separator: ", ") + " +\(n.count - max)"
    }
}

// MARK: - Kit action: Set kind

extension KitLoops {
    /// `ae loops edit <name> --set kind=<kind>` in the kit repo: the kit validates the file and writes it (One Roof never
    /// rewrites a kit file itself). Blocking (seconds): call off the main thread. `run` is injectable for tests.
    public static func setKind(_ name: String, kind: String, repo: String = LoopBuiltIns.defaultRepoPath(),
                               run: (String, [String], String) -> (Int32, String) = { exe, args, cwd in
                                   Foundations.run(exe, args, cwd: cwd, timeout: 60)
                               }) throws {
        guard LoopsV7Setup.validKind(kind) else { throw LoopStoreError("\(kind) is not a loop kind") }
        guard Loop.validId(name) else { throw LoopStoreError("bad loop name \(name)") }
        let (rc, out) = run("/usr/bin/env", LoopsV7Setup.setKindCommand(name: name, kind: kind), repo)
        KitLoopsCache.shared.invalidate()
        let last = out.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        guard rc == 0 else { throw LoopStoreError("the kit refused kind=\(kind) for \(name): " + (last.last ?? "exit \(rc)")) }
    }
}

// MARK: - Kit action: Turn off (7m)

extension KitLoops {
    /// `ae loops off <name>`: the kit removes it from loops.enabled and its launchd entry. Blocking: call off the main thread.
    public static func turnOff(_ name: String, repo: String = LoopBuiltIns.defaultRepoPath()) throws {
        guard Loop.validId(name) else { throw LoopStoreError("bad loop name \(name)") }
        let (rc, out) = Foundations.run("/usr/bin/env", command("off", name), cwd: repo, timeout: 60)
        KitLoopsCache.shared.invalidate()
        let last = out.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        guard rc == 0 else { throw LoopStoreError("the kit could not turn \(name) off: " + (last.last ?? "exit \(rc)")) }
    }
}

// MARK: - 7n · Set up: the config line for a key

extension LoopsV7Setup {
    /// The 1-based line of the deepest part of `key` ("loops.settings.fleet-sweep.commands") found in the YAML text, each
    /// part looked for below the one before it (deeper indent). nil when not even `loops:` is there.
    public static func configLine(_ key: String, in text: String) -> Int? {
        let parts = key.split(separator: ".").map(String.init)
        let lines = text.components(separatedBy: "\n")
        var from = 0, indent = -1, found: Int?
        for p in parts {
            var hit: Int?
            var i = from
            while i < lines.count {
                let raw = lines[i]
                let t = raw.trimmingCharacters(in: .whitespaces)
                let ind = raw.prefix(while: { $0 == " " }).count
                if !t.isEmpty && !t.hasPrefix("#") && ind <= indent { break }   // left the parent block
                if ind > indent && (t.hasPrefix(p + ":") || t.hasPrefix("\"" + p + "\":")) { hit = i; indent = ind; break }
                i += 1
            }
            guard let h = hit else { break }
            found = h + 1; from = h + 1
        }
        return found
    }
}
