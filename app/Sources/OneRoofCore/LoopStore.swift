import Darwin
import Foundation

/// Loops as plain files in the shared folder (I12): `<shared>/loops/<id>/loop.json` (the spec and its state) and
/// `<shared>/loops/<id>/rounds.jsonl` (one line per round). Both the app (owner edits, Run now / Pause / Stop) and roofd
/// (the engine) change loop.json, so every change is a read-modify-write under a file lock; rounds are appended.
public struct LoopStore: Sendable {
    public let root: String
    public let builtIns: [Loop]
    /// LAB-1843: your `ae` loops in the same folder (`<root>/*.loop.yaml`), shown as Mine.
    public let fileLoops: [Loop]

    public init(root: String = LoopStore.defaultRoot, builtIns: [Loop]? = nil, fileLoops: [Loop]? = nil) {
        self.root = root
        self.builtIns = builtIns ?? (root == LoopStore.defaultRoot ? LoopBuiltIns.load() : [])
        let ids = Set(self.builtIns.map(\.id))
        self.fileLoops = (fileLoops ?? LoopFiles.load(folder: root)).filter { !ids.contains($0.id) }
    }

    /// `<shared>/loops`, the shared folder the app uses (Settings › Foundations, default `<projects>/_common`).
    public static var defaultRoot: String { (Workspace.sharedRoot as NSString).appendingPathComponent("loops") }

    public func folder(_ id: String) -> String { (root as NSString).appendingPathComponent(id) }
    func specPath(_ id: String) -> String { folder(id) + "/loop.json" }
    /// LAB-1942: run state (state, run, lastRunAt, stopReason …), written by roofd every round and by Run now / Pause /
    /// Stop; `loop.json` holds only the definition and changes only when you edit the loop, so it can live in git.
    func statePath(_ id: String) -> String { folder(id) + "/state.json" }
    func roundsPath(_ id: String) -> String { folder(id) + "/rounds.jsonl" }
    public func hasDiskOverride(_ id: String) -> Bool {
        FileManager.default.fileExists(atPath: specPath(id)) || FileManager.default.fileExists(atPath: statePath(id))
    }

    static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return e
    }()
    static let lineEncoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return e
    }()
    static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    // MARK: Loops

    /// Every loop: pinned first, then Mine before Built-in, then by name. Unreadable folders are skipped.
    public func all() -> [Loop] {
        let diskIds = ((try? FileManager.default.contentsOfDirectory(atPath: root)) ?? []).filter(Loop.validId)
        let allIds = Array(Set(diskIds).union(builtIns.map(\.id)).union(fileLoops.map(\.id)))
        return allIds.compactMap(load).sorted { a, b in
            if a.pinned != b.pinned { return a.pinned }
            if a.origin != b.origin { return a.origin == .mine }
            return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
        }
    }

    public func load(_ id: String) -> Loop? {
        guard Loop.validId(id) else { return nil }
        let builtIn = builtIns.first { $0.id == id }
        let file = builtIn == nil ? fileLoops.first { $0.id == id } : nil
        let fm = FileManager.default
        var def: Loop?
        var legacy = false
        if let d = fm.contents(atPath: specPath(id)), var disk = try? Self.decoder.decode(Loop.self, from: d) {
            legacy = LoopRunState.isLegacy(d)
            if let builtIn {
                disk.origin = .builtIn
                if disk.title == nil { disk.title = builtIn.title }
                disk.kind = disk.kind ?? builtIn.kind; disk.act = disk.act ?? builtIn.act
            }
            def = disk
        }
        var state: LoopRunState?
        if let d = fm.contents(atPath: statePath(id)) { state = try? Self.decoder.decode(LoopRunState.self, from: d) }
        // LAB-1942 · migrate a loop.json that still holds run state, once: back it up, move the state to state.json and
        // leave the definition in loop.json.
        if legacy, state == nil, let disk = def {
            state = LoopRunState(disk)
            migrate(id, disk, state: state!)
        }
        if let file {
            // The file is the spec (ae owns it); the folder only holds One Roof's run state for it.
            var l = file
            if let disk = def { LoopRunState(disk).apply(to: &l); l.pinned = disk.pinned }
            state?.apply(to: &l)
            return def == nil && state == nil ? file : l
        }
        guard var l = def ?? builtIn else { return nil }
        state?.apply(to: &l)
        return l
    }

    /// Back up the old loop.json (once), then write state.json and the definition-only loop.json. Safe to race: both
    /// writers produce the same files.
    private func migrate(_ id: String, _ l: Loop, state: LoopRunState) {
        let fm = FileManager.default
        let backup = specPath(id) + ".pre-split.bak"
        if !fm.fileExists(atPath: backup) { try? fm.copyItem(atPath: specPath(id), toPath: backup) }
        try? atomicWrite(statePath(id), Self.encoder.encode(state))
        if let d = try? definitionData(l) { try? atomicWrite(specPath(id), d) }
    }

    /// The definition part of a loop as loop.json bytes (no run state, nothing derived from a kit file).
    func definitionData(_ l: Loop) throws -> Data {
        let full = try Self.encoder.encode(l)
        guard var o = try JSONSerialization.jsonObject(with: full) as? [String: Any] else { return full }
        for k in LoopRunState.keys + ["specFile", "externalSchedule"] { o.removeValue(forKey: k) }
        return try JSONSerialization.data(withJSONObject: o, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
    }

    private func atomicWrite(_ path: String, _ data: Data) throws {
        let tmp = path + ".tmp"
        guard FileManager.default.createFile(atPath: tmp, contents: data) else { throw LoopStoreError("could not write \(tmp)") }
        guard rename(tmp, path) == 0 else { throw LoopStoreError("could not save \(path)") }
    }

    /// True when `id` is a `.loop.yaml` loop (its folder, if any, holds run state only).
    public func isFileLoop(_ id: String) -> Bool { fileLoops.contains { $0.id == id } }

    /// Write the whole loop (a new loop, or the editor's Save), its goal, check and prompt cleaned. Use `update` for state changes.
    public func save(_ loop: Loop) throws {
        guard Loop.validId(loop.id) else { throw LoopStoreError("bad loop id \(loop.id)") }
        try withLock(loop.id) { try write(LoopSpecLint.cleaned(loop)) }
    }

    /// Change a loop under its lock: re-read, mutate, write. Returns the loop as written (nil = no such loop).
    @discardableResult
    public func update(_ id: String, _ change: (inout Loop) -> Void) throws -> Loop? {
        guard Loop.validId(id) else { return nil }
        return try withLock(id) {
            guard var l = load(id) else { return nil }
            change(&l)
            try write(l)
            return l
        }
    }

    /// The owner's edit: the spec fields from `edited`, the run state as it is on disk now.
    @discardableResult
    public func saveEdit(_ edited: Loop) throws -> Loop {
        guard Loop.validId(edited.id) else { throw LoopStoreError("bad loop id \(edited.id)") }
        return try withLock(edited.id) {
            let existing = load(edited.id)
            var l = existing ?? edited
            l.name = edited.name; l.title = edited.title ?? l.title; l.origin = existing?.origin ?? edited.origin
            l.goal = edited.goal; l.check = edited.check; l.repoPath = edited.repoPath
            l.agent = edited.agent; l.model = edited.model; l.account = edited.account; l.roundPrompt = edited.roundPrompt
            l.trigger = edited.trigger; l.limits = edited.limits; l.pinned = edited.pinned; l.checkTimeout = edited.checkTimeout
            if existing == nil { l.state = edited.state; l.runRequested = edited.runRequested }
            l = LoopSpecLint.cleaned(l)      // what a terminal copy adds to goal, check and prompt (LAB-1846)
            try write(l)
            return l
        }
    }

    /// Remove a loop's files (its worktree and branch stay: they may hold work). For a Built-in loop, removing its
    /// override folder resets it to the default Built-in state (`.stopped`).
    public func delete(_ id: String) {
        guard Loop.validId(id) else { return }
        try? FileManager.default.removeItem(atPath: folder(id))
    }

    /// An id for a new loop named `name`, not used yet: "fix-ci", "fix-ci-2", …
    public func newId(for name: String) -> String {
        let base = Loop.slug(name)
        var id = base, n = 2
        while FileManager.default.fileExists(atPath: folder(id)) || builtIns.contains(where: { $0.id == id })
                || fileLoops.contains(where: { $0.id == id }) {
            id = "\(base)-\(n)"; n += 1
        }
        return id
    }

    /// LAB-1942: run state always goes to state.json; loop.json is rewritten only when the definition changed (never
    /// for a `.loop.yaml` loop, and for a Built-in only once it differs from the kit's default).
    private func write(_ l: Loop) throws {
        let fm = FileManager.default
        try fm.createDirectory(atPath: folder(l.id), withIntermediateDirectories: true)
        try atomicWrite(statePath(l.id), Self.encoder.encode(LoopRunState(l)))
        if isFileLoop(l.id) {
            // Only a pin is kept for a kit-file loop besides its state (the definition stays in its .loop.yaml).
            guard l.pinned || fm.fileExists(atPath: specPath(l.id)) else { return }
            let pin = try JSONSerialization.data(withJSONObject: ["id": l.id, "pinned": l.pinned], options: [.prettyPrinted, .sortedKeys])
            if fm.contents(atPath: specPath(l.id)) != pin { try atomicWrite(specPath(l.id), pin) }
            return
        }
        let def = try definitionData(l)
        if let existing = fm.contents(atPath: specPath(l.id)) {
            if existing != def { try atomicWrite(specPath(l.id), def) }
            return
        }
        if let b = builtIns.first(where: { $0.id == l.id }), try definitionData(b.with { $0.origin = l.origin }) == def { return }
        try atomicWrite(specPath(l.id), def)
    }

    private func withLock<T>(_ id: String, _ body: () throws -> T) throws -> T {
        try FileManager.default.createDirectory(atPath: folder(id), withIntermediateDirectories: true)
        let fd = open(folder(id) + "/.lock", O_CREAT | O_RDWR, 0o644)
        guard fd >= 0 else { throw LoopStoreError("could not lock loop \(id)") }
        defer { close(fd) }
        flock(fd, LOCK_EX)
        defer { flock(fd, LOCK_UN) }
        return try body()
    }

    // MARK: Rounds

    public func rounds(_ id: String) -> [LoopRound] {
        guard Loop.validId(id), let d = FileManager.default.contents(atPath: roundsPath(id)) else { return [] }
        return String(decoding: d, as: UTF8.self).split(separator: "\n").compactMap { line in
            try? Self.decoder.decode(LoopRound.self, from: Data(line.utf8))
        }
    }

    public func append(_ round: LoopRound, to id: String) throws {
        guard Loop.validId(id) else { throw LoopStoreError("bad loop id \(id)") }
        try FileManager.default.createDirectory(atPath: folder(id), withIntermediateDirectories: true)
        var data = try Self.lineEncoder.encode(round)
        data.append(0x0A)
        let fd = open(roundsPath(id), O_CREAT | O_WRONLY | O_APPEND, 0o644)
        guard fd >= 0 else { throw LoopStoreError("could not open \(roundsPath(id))") }
        defer { close(fd) }
        let n = data.withUnsafeBytes { Darwin.write(fd, $0.baseAddress, $0.count) }
        guard n == data.count else { throw LoopStoreError("could not append a round to \(id)") }
    }
}

public struct LoopStoreError: Error, CustomStringConvertible {
    public let description: String
    public init(_ d: String) { description = d }
}

/// The check: `/bin/zsh -lc <check>` in the loop's worktree, with a timeout, keeping the end of its output. The same
/// code runs a loop's check in roofd and the editor's Test the check.
public enum LoopCheck {
    public static let tailLines = 40
    public static let tailChars = 4000
    public static let unreadableExitCodes = "One Roof cannot read exit codes in this process (SIGCHLD is ignored), so the check was not run."

    public static func run(_ command: String, in folder: String, timeout: TimeInterval = 600) -> LoopCheckResult {
        let started = Date()
        let cmd = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cmd.isEmpty else { return LoopCheckResult(passed: false, exitCode: 2, output: "No check command set.") }
        guard Foundations.childExitCodesReadable else {
            return LoopCheckResult(passed: false, exitCode: 125, output: LoopCheck.unreadableExitCodes)
        }
        var dir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: folder, isDirectory: &dir), dir.boolValue else {
            return LoopCheckResult(passed: false, exitCode: 2, output: "Folder not found: \(folder)")
        }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/zsh")
        p.arguments = ["-lc", cmd]
        p.currentDirectoryURL = URL(fileURLWithPath: folder)
        p.standardInput = FileHandle.nullDevice
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        let buffer = TailBuffer(limit: 64 * 1024)
        let eof = DispatchSemaphore(value: 0)
        pipe.fileHandleForReading.readabilityHandler = { h in
            let d = h.availableData
            if d.isEmpty { h.readabilityHandler = nil; eof.signal() } else { buffer.append(d) }
        }
        let done = DispatchSemaphore(value: 0)
        p.terminationHandler = { _ in done.signal() }
        do { try p.run() } catch {
            pipe.fileHandleForReading.readabilityHandler = nil
            return LoopCheckResult(passed: false, exitCode: 127, output: "\(error)")
        }
        var timedOut = false
        if done.wait(timeout: .now() + timeout) == .timedOut {
            timedOut = true
            let pid = p.processIdentifier
            _ = Foundations.run("/usr/bin/pkill", ["-TERM", "-P", String(pid)], timeout: 5)
            p.terminate()
            if done.wait(timeout: .now() + 3) == .timedOut {
                _ = Foundations.run("/usr/bin/pkill", ["-KILL", "-P", String(pid)], timeout: 5)
                kill(pid, SIGKILL)
                _ = done.wait(timeout: .now() + 3)
            }
        }
        // Let the reader drain what is left; never block on a pipe a background child of the check still holds.
        _ = eof.wait(timeout: .now() + 1)
        pipe.fileHandleForReading.readabilityHandler = nil
        var out = buffer.text
        let code: Int32 = timedOut ? 124 : p.terminationStatus
        if timedOut { out += (out.isEmpty ? "" : "\n") + "One Roof: the check timed out after \(Int(timeout)) s and was stopped." }
        return LoopCheckResult(passed: !timedOut && code == 0, exitCode: code, output: out, timedOut: timedOut,
                               duration: Date().timeIntervalSince(started))
    }

    /// The last lines of an output, as kept in rounds.jsonl and shown in round prompts.
    public static func tail(_ s: String, lines: Int = tailLines, chars: Int = tailChars) -> String {
        let all = s.replacingOccurrences(of: "\r\n", with: "\n").split(separator: "\n", omittingEmptySubsequences: false)
        var t = all.suffix(lines).joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        if t.count > chars { t = "…" + String(t.suffix(chars)) }
        return t
    }

    /// Same key = same failure: the exit code plus a hash of the last few output lines with numbers, hex ids and
    /// spacing smoothed away (timings, line numbers and addresses change between runs; the failure does not).
    public static func failureKey(_ r: LoopCheckResult) -> String {
        if r.timedOut { return "timed out" }
        let lines = r.output.split(separator: "\n").map { normalise(String($0)) }.filter { !$0.isEmpty }.suffix(6)
        return "exit \(r.exitCode) · " + fnv(lines.joined(separator: "\n"))
    }

    static func normalise(_ s: String) -> String {
        var out = ""
        var lastWasSpace = false, lastWasNum = false
        for ch in s.lowercased() {
            if ch.isWhitespace {
                if !lastWasSpace && !out.isEmpty { out.append(" ") }
                lastWasSpace = true; lastWasNum = false
            } else if ch.isNumber || (lastWasNum && ch.isHexDigit) {
                if !lastWasNum { out.append("#") }
                lastWasNum = true; lastWasSpace = false
            } else {
                out.append(ch); lastWasSpace = false; lastWasNum = false
            }
        }
        return out.trimmingCharacters(in: .whitespaces)
    }

    static func fnv(_ s: String) -> String {
        var h: UInt32 = 2_166_136_261
        for b in s.utf8 { h = (h ^ UInt32(b)) &* 16_777_619 }
        return String(format: "%08x", h)
    }
}

/// Keeps the last `limit` bytes of a stream.
final class TailBuffer: @unchecked Sendable {
    private var data = Data()
    private let limit: Int
    private let lock = NSLock()
    init(limit: Int) { self.limit = limit }
    func append(_ d: Data) {
        lock.lock(); defer { lock.unlock() }
        data.append(d)
        if data.count > limit { data.removeFirst(data.count - limit) }
    }
    var text: String { lock.lock(); defer { lock.unlock() }; return String(decoding: data, as: UTF8.self) }
}

/// A loop's own worktree: `<repo>/.worktrees/loop-<name>` on branch `loop/<name>`, made from the repo's current branch,
/// where `<name>` is the loop id without a leading "loop-" (so loop "loop-smoke" works in `loop-smoke` on `loop/smoke`,
/// not `loop-loop-smoke`). A worktree or branch made by an earlier version under the doubled name keeps being used.
/// The live checkout is never edited; nothing is pushed or merged.
public enum LoopWorktree {
    /// The id without a leading "loop-" (an id that is only "loop-…" with nothing after it keeps its full id).
    static func name(_ id: String) -> String {
        id.hasPrefix("loop-") && id.count > 5 ? String(id.dropFirst(5)) : id
    }

    /// The branch for a new worktree. `branch(_:repo:)` also finds a branch made under the old doubled name.
    public static func branch(_ id: String) -> String { "loop/" + name(id) }
    static func legacyBranch(_ id: String) -> String { "loop/" + id }

    static func folder(repo: String) -> String { (repo as NSString).appendingPathComponent(".worktrees") }
    static func newPath(repo: String, id: String) -> String { (folder(repo: repo) as NSString).appendingPathComponent("loop-" + name(id)) }
    static func legacyPath(repo: String, id: String) -> String { (folder(repo: repo) as NSString).appendingPathComponent("loop-" + id) }

    /// Where the loop works: the worktree an earlier version made under the doubled name when it is still there,
    /// otherwise `<repo>/.worktrees/loop-<name>`.
    public static func path(repo: String, id: String) -> String {
        let legacy = legacyPath(repo: repo, id: id)
        if legacy != newPath(repo: repo, id: id), isWorktree(legacy) { return legacy }
        return newPath(repo: repo, id: id)
    }

    /// The branch the loop's worktree is on, as far as it can be told without running git: the old doubled name when
    /// the loop still works in the old doubled folder.
    public static func branch(_ id: String, repo: String) -> String {
        path(repo: repo, id: id) == legacyPath(repo: repo, id: id) && legacyPath(repo: repo, id: id) != newPath(repo: repo, id: id)
            ? legacyBranch(id) : branch(id)
    }

    /// A folder that is a git checkout (its `.git` file or folder is there).
    static func isWorktree(_ dir: String) -> Bool {
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: dir, isDirectory: &isDir) && isDir.boolValue
            && FileManager.default.fileExists(atPath: (dir as NSString).appendingPathComponent(".git"))
    }

    /// The worktree, made if missing. Throws with git's words when it cannot be made, and never returns a folder that
    /// is not there: git's exit code alone is not trusted (LAB-677: in roofd, with SIGCHLD ignored, every exit code
    /// read as 0, a failed `git worktree add` looked like success and round 1 started in a folder that did not exist).
    @discardableResult
    public static func ensure(repo: String, id: String) throws -> String {
        let wt = path(repo: repo, id: id)
        let git = "/usr/bin/git"
        if isWorktree(wt) { return wt }
        guard FileManager.default.fileExists(atPath: (repo as NSString).appendingPathComponent(".git")) else {
            throw LoopStoreError("\(repo) is not a git repo")
        }
        do {
            try FileManager.default.createDirectory(atPath: folder(repo: repo), withIntermediateDirectories: true)
        } catch {
            throw LoopStoreError("could not make \(folder(repo: repo)): \(error.localizedDescription)")
        }
        let prune = Foundations.run(git, ["-C", repo, "worktree", "prune"], timeout: 20)
        // The branch to check out: the new name, else one an earlier version made under the doubled name, else a
        // new branch from HEAD. Told by what rev-parse prints (the commit), not by its exit code alone.
        func exists(_ b: String) -> Bool {
            let (rc, out) = Foundations.run(git, ["-C", repo, "rev-parse", "--verify", "--quiet", "refs/heads/" + b], timeout: 10)
            return rc == 0 && !out.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        let existing = [branch(id), legacyBranch(id)].first(where: exists)
        let args = existing.map { ["-C", repo, "worktree", "add", wt, $0] }
            ?? ["-C", repo, "worktree", "add", "-b", branch(id), wt, "HEAD"]
        let (rc, out) = Foundations.run(git, args, timeout: 120)
        let said = [prune.1, out].map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }.joined(separator: "\n")
        guard rc == 0 else { throw LoopStoreError("git worktree add failed (exit \(rc)): " + (said.isEmpty ? "no output" : said)) }
        guard isWorktree(wt) else {
            throw LoopStoreError("git worktree add reported success but \(wt) is not there. git said: " + (said.isEmpty ? "nothing" : said))
        }
        return wt
    }
}

/// LAB-1865 · fired events for One Roof's loops: `<loops>/.events/<epoch>-<event>.json` ({"event", "at", "detail"}),
/// written by the kit's `ae loops fire <event>` (the adapter a webhook receiver or a git hook calls) or by `fire`
/// below. roofd reads them on every pass and starts each loop listening for one, once per event after its last run.
public enum LoopEvents {
    public static func folder(_ root: String) -> String { (root as NSString).appendingPathComponent(".events") }

    /// Every readable event, oldest first.
    public static func read(root: String) -> [LoopEventFire] {
        let dir = folder(root)
        let names = ((try? FileManager.default.contentsOfDirectory(atPath: dir)) ?? []).filter { $0.hasSuffix(".json") }
        let d = JSONDecoder()
        d.dateDecodingStrategy = .custom { dec in
            let c = try dec.singleValueContainer()
            if let n = try? c.decode(Double.self) { return Date(timeIntervalSince1970: n) }
            let s = try c.decode(String.self)
            if let date = LoopInbox.iso(s) { return date }
            throw DecodingError.dataCorruptedError(in: c, debugDescription: "bad date \(s)")
        }
        return names.compactMap { n in
            FileManager.default.contents(atPath: (dir as NSString).appendingPathComponent(n)).flatMap { try? d.decode(LoopEventFire.self, from: $0) }
        }
        .sorted { $0.at < $1.at }
    }

    /// Record an event (the same file the kit writes).
    @discardableResult
    public static func fire(_ event: String, root: String, at: Date = Date(), detail: String? = nil) throws -> String {
        let dir = folder(root)
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let safe = event.filter { $0.isLetter || $0.isNumber || $0 == "." || $0 == "-" || $0 == "_" }
        let path = (dir as NSString).appendingPathComponent("\(Int(at.timeIntervalSince1970 * 1000))-\(safe).json")
        var o: [String: Any] = ["event": event, "at": LoopLedger.iso(at)]
        if let detail { o["detail"] = detail }
        let data = try JSONSerialization.data(withJSONObject: o, options: [.sortedKeys])
        guard FileManager.default.createFile(atPath: path, contents: data) else { throw LoopStoreError("could not write \(path)") }
        return path
    }

    /// Remove events older than `age` (roofd keeps a day: a loop that missed one has had its chance).
    public static func prune(root: String, olderThan age: TimeInterval = 86_400, now: Date = Date()) {
        let dir = folder(root)
        for n in (try? FileManager.default.contentsOfDirectory(atPath: dir)) ?? [] where n.hasSuffix(".json") {
            let p = (dir as NSString).appendingPathComponent(n)
            let ms = Double(n.prefix(while: { $0.isNumber })) ?? 0
            if ms > 0, now.timeIntervalSince1970 - ms / 1000 > age { try? FileManager.default.removeItem(atPath: p) }
        }
    }
}


/// LAB-1942 · a loop's run state, kept apart from its definition (`<loops>/<id>/state.json`).
public struct LoopRunState: Codable, Equatable, Sendable {
    public var state: LoopState
    public var run: LoopRun?
    public var runRequested: Bool
    public var lastRunAt: Date?
    public var stopReason: String?
    public var failureSeenAt: Date?

    /// The loop.json keys that are run state (a loop.json holding any of them is from before the split).
    public static let keys = ["state", "run", "runRequested", "lastRunAt", "stopReason", "failureSeenAt"]

    public init(_ l: Loop) {
        state = l.state; run = l.run; runRequested = l.runRequested; lastRunAt = l.lastRunAt; stopReason = l.stopReason
        failureSeenAt = l.failureSeenAt
    }

    public func apply(to l: inout Loop) {
        l.state = state; l.run = run; l.runRequested = runRequested; l.lastRunAt = lastRunAt; l.stopReason = stopReason
        l.failureSeenAt = failureSeenAt
    }

    static func isLegacy(_ data: Data) -> Bool {
        guard let o = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return false }
        return keys.contains { o[$0] != nil }
    }
}
