import Darwin
import Foundation

/// Loops as plain files in the shared folder (I12): `<shared>/loops/<id>/loop.json` (the spec and its state) and
/// `<shared>/loops/<id>/rounds.jsonl` (one line per round). Both the app (owner edits, Run now / Pause / Stop) and roofd
/// (the engine) change loop.json, so every change is a read-modify-write under a file lock; rounds are appended.
public struct LoopStore: Sendable {
    public let root: String
    public let builtIns: [Loop]

    public init(root: String = LoopStore.defaultRoot, builtIns: [Loop]? = nil) {
        self.root = root
        self.builtIns = builtIns ?? (root == LoopStore.defaultRoot ? LoopBuiltIns.load() : [])
    }

    /// `<shared>/loops`, the shared folder the app uses (Settings › Foundations, default `<projects>/_common`).
    public static var defaultRoot: String { (Workspace.sharedRoot as NSString).appendingPathComponent("loops") }

    public func folder(_ id: String) -> String { (root as NSString).appendingPathComponent(id) }
    func specPath(_ id: String) -> String { folder(id) + "/loop.json" }
    func roundsPath(_ id: String) -> String { folder(id) + "/rounds.jsonl" }
    public func hasDiskOverride(_ id: String) -> Bool { FileManager.default.fileExists(atPath: specPath(id)) }

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
        let allIds = Array(Set(diskIds).union(builtIns.map(\.id)))
        return allIds.compactMap(load).sorted { a, b in
            if a.pinned != b.pinned { return a.pinned }
            if a.origin != b.origin { return a.origin == .mine }
            return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
        }
    }

    public func load(_ id: String) -> Loop? {
        guard Loop.validId(id) else { return nil }
        let builtIn = builtIns.first { $0.id == id }
        if let d = FileManager.default.contents(atPath: specPath(id)),
           var disk = try? Self.decoder.decode(Loop.self, from: d) {
            if let builtIn {
                disk.origin = .builtIn
                if disk.title == nil { disk.title = builtIn.title }
            }
            return disk
        }
        return builtIn
    }

    /// Write the whole loop (a new loop, or the editor's Save). Use `update` for state changes.
    public func save(_ loop: Loop) throws {
        guard Loop.validId(loop.id) else { throw LoopStoreError("bad loop id \(loop.id)") }
        try withLock(loop.id) { try write(loop) }
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
        while FileManager.default.fileExists(atPath: folder(id)) || builtIns.contains(where: { $0.id == id }) {
            id = "\(base)-\(n)"; n += 1
        }
        return id
    }

    private func write(_ l: Loop) throws {
        try FileManager.default.createDirectory(atPath: folder(l.id), withIntermediateDirectories: true)
        let data = try Self.encoder.encode(l)
        let tmp = specPath(l.id) + ".tmp"
        guard FileManager.default.createFile(atPath: tmp, contents: data) else { throw LoopStoreError("could not write \(tmp)") }
        guard rename(tmp, specPath(l.id)) == 0 else { throw LoopStoreError("could not save \(specPath(l.id))") }
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
