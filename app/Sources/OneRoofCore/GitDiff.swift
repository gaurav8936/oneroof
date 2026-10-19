import Foundation

/// The code review panel's data: what changed in a repo since its last commit, file by file and hunk by
/// hunk, read with the `git` CLI (never a shell). A hunk can be reverted on its own with `git apply -R`.
public struct DiffLine: Equatable, Sendable {
    public enum Kind: Sendable { case context, added, removed, note }
    public var kind: Kind
    public var text: String
    public var oldNo: Int?
    public var newNo: Int?
}

public struct DiffHunk: Equatable, Identifiable, Sendable {
    public var id: String { file + "@" + header }
    public var file: String
    public var header: String          // "@@ -10,6 +10,8 @@ func name"
    public var lines: [DiffLine]
    /// A patch with just this hunk (file header + hunk), for `git apply -R`.
    public var patch: String
    /// First changed line in the new file (for "file:line" in a review comment).
    public var firstNewLine: Int {
        lines.first(where: { $0.kind == .added })?.newNo ?? lines.first(where: { $0.newNo != nil })?.newNo ?? 1
    }
    public var added: Int { lines.filter { $0.kind == .added }.count }
    public var removed: Int { lines.filter { $0.kind == .removed }.count }
}

public struct FileDiff: Equatable, Identifiable, Sendable {
    public enum Change: String, Sendable { case modified, added, deleted, renamed, binary, untracked }
    public var id: String { path }
    public var path: String
    public var oldPath: String?
    public var change: Change
    public var hunks: [DiffHunk]
    public var added: Int { hunks.reduce(0) { $0 + $1.added } }
    public var removed: Int { hunks.reduce(0) { $0 + $1.removed } }
}

public struct DiffSnapshot: Equatable, Sendable {
    public var repo: String
    public var branch: String
    public var files: [FileDiff]
    public var error: String?
    public var added: Int { files.reduce(0) { $0 + $1.added } }
    public var removed: Int { files.reduce(0) { $0 + $1.removed } }
}

/// Branch and size of the uncommitted change in a repo, for the session rows.
public struct RepoStat: Equatable, Sendable {
    public var branch: String
    public var added: Int
    public var removed: Int
    public var files: Int
}

public enum GitDiff {
    public static var git = "/usr/bin/git"

    /// The top of the git repo containing `path`, or nil when it is not in one.
    public static func repoRoot(for path: String) -> String? {
        var dir: ObjCBool = false
        let folder = FileManager.default.fileExists(atPath: path, isDirectory: &dir) && !dir.boolValue
            ? (path as NSString).deletingLastPathComponent : path
        let (code, out) = Foundations.run(git, ["-C", folder, "rev-parse", "--show-toplevel"], timeout: 5)
        let root = out.trimmingCharacters(in: .whitespacesAndNewlines)
        return code == 0 && !root.isEmpty ? root : nil
    }

    /// Everything changed since HEAD (staged and unstaged), plus untracked files.
    public static func load(repo: String) -> DiffSnapshot {
        let (_, b) = Foundations.run(git, ["-C", repo, "rev-parse", "--abbrev-ref", "HEAD"], timeout: 5)
        let branch = b.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasHead = Foundations.run(git, ["-C", repo, "rev-parse", "--verify", "-q", "HEAD"], timeout: 5).0 == 0
        let args = ["-C", repo, "-c", "core.quotepath=off", "diff", "--no-color", "--no-ext-diff", "-M", "-U3"] + (hasHead ? ["HEAD"] : [])
        let (code, out) = Foundations.run(git, args, timeout: 20)
        if code != 0 { return DiffSnapshot(repo: repo, branch: branch, files: [], error: out.trimmingCharacters(in: .whitespacesAndNewlines)) }
        var files = parse(out)
        let (_, untracked) = Foundations.run(git, ["-C", repo, "-c", "core.quotepath=off", "ls-files", "--others", "--exclude-standard"], timeout: 10)
        for p in untracked.split(separator: "\n").map(String.init) where !p.isEmpty {
            files.append(FileDiff(path: p, oldPath: nil, change: .untracked, hunks: []))
        }
        return DiffSnapshot(repo: repo, branch: branch, files: files, error: nil)
    }

    /// Cheap summary for a sidebar row: branch + line counts since HEAD (`--numstat`), untracked files counted as files.
    public static func stat(repo: String) -> RepoStat? {
        // symbolic-ref also names the branch of a repo with no commits yet; a detached HEAD falls back to rev-parse.
        var (bc, b) = Foundations.run(git, ["-C", repo, "symbolic-ref", "--short", "-q", "HEAD"], timeout: 5)
        if bc != 0 { (bc, b) = Foundations.run(git, ["-C", repo, "rev-parse", "--short", "HEAD"], timeout: 5) }
        guard bc == 0 else { return nil }
        let hasHead = Foundations.run(git, ["-C", repo, "rev-parse", "--verify", "-q", "HEAD"], timeout: 5).0 == 0
        let (_, num) = Foundations.run(git, ["-C", repo, "diff", "--numstat", "--no-ext-diff"] + (hasHead ? ["HEAD"] : []), timeout: 10)
        var s = parseNumstat(num)
        s.branch = b.trimmingCharacters(in: .whitespacesAndNewlines)
        let (_, untracked) = Foundations.run(git, ["-C", repo, "ls-files", "--others", "--exclude-standard"], timeout: 10)
        s.files += untracked.split(separator: "\n").count
        return s
    }

    /// "12\t3\tpath" lines (binary files show "-\t-").
    static func parseNumstat(_ text: String) -> RepoStat {
        var s = RepoStat(branch: "", added: 0, removed: 0, files: 0)
        for line in text.split(separator: "\n") {
            let f = line.split(separator: "\t", maxSplits: 2)
            guard f.count == 3 else { continue }
            s.added += Int(f[0]) ?? 0; s.removed += Int(f[1]) ?? 0; s.files += 1
        }
        return s
    }

    /// Parse unified diff output (`git diff`) into files and hunks.
    public static func parse(_ text: String) -> [FileDiff] {
        var files: [FileDiff] = []
        var cur: FileDiff?
        var fileHeader: [String] = []
        var hunk: DiffHunk?
        var hunkText: [String] = []
        var oldNo = 0, newNo = 0

        func closeHunk() {
            guard var h = hunk, let f = cur else { return }
            h.file = f.path
            let header = (f.change == .added || f.change == .deleted) ? fileHeader
                : ["diff --git a/\(f.path) b/\(f.path)", "--- a/\(f.path)", "+++ b/\(f.path)"]
            h.patch = (header + hunkText).joined(separator: "\n") + "\n"
            cur?.hunks.append(h)
            hunk = nil; hunkText = []
        }
        func closeFile() {
            closeHunk()
            if let f = cur { files.append(f) }
            cur = nil; fileHeader = []
        }

        for raw in text.components(separatedBy: "\n") {
            let line = raw
            if line.hasPrefix("diff --git ") {
                closeFile()
                // "diff --git a/x b/y": take the b/ side.
                let parts = line.dropFirst("diff --git ".count)
                let path = parts.range(of: " b/").map { String(parts[$0.upperBound...]) } ?? String(parts)
                cur = FileDiff(path: path, oldPath: nil, change: .modified, hunks: [])
                fileHeader = [line]
                continue
            }
            guard cur != nil else { continue }
            if line.hasPrefix("@@") {
                closeHunk()
                let (o, n) = hunkStarts(line)
                oldNo = o; newNo = n
                hunk = DiffHunk(file: cur!.path, header: line, lines: [], patch: "")
                hunkText = [line]
                continue
            }
            if hunk == nil {
                // File header lines, before the first hunk.
                if line.hasPrefix("+++ b/") { cur?.path = String(line.dropFirst(6)) }
                else if line.hasPrefix("--- a/"), cur?.change == .deleted { cur?.path = String(line.dropFirst(6)) }
                if line.hasPrefix("new file mode") { cur?.change = .added }
                else if line.hasPrefix("deleted file mode") { cur?.change = .deleted }
                else if line.hasPrefix("rename from ") { cur?.change = .renamed; cur?.oldPath = String(line.dropFirst("rename from ".count)) }
                else if line.hasPrefix("Binary files ") { cur?.change = .binary }
                if !line.isEmpty { fileHeader.append(line) }
                continue
            }
            guard let first = line.first, " +-\\".contains(first) else { continue }
            hunkText.append(line)
            if line.hasPrefix("+") {
                hunk?.lines.append(DiffLine(kind: .added, text: String(line.dropFirst()), oldNo: nil, newNo: newNo)); newNo += 1
            } else if line.hasPrefix("-") {
                hunk?.lines.append(DiffLine(kind: .removed, text: String(line.dropFirst()), oldNo: oldNo, newNo: nil)); oldNo += 1
            } else if line.hasPrefix("\\") {
                hunk?.lines.append(DiffLine(kind: .note, text: String(line.dropFirst(2)), oldNo: nil, newNo: nil))
            } else {
                hunk?.lines.append(DiffLine(kind: .context, text: String(line.dropFirst()), oldNo: oldNo, newNo: newNo)); oldNo += 1; newNo += 1
            }
        }
        closeFile()
        return files
    }

    /// "@@ -10,6 +12,8 @@" → (10, 12)
    static func hunkStarts(_ header: String) -> (Int, Int) {
        let parts = header.split(separator: " ")
        func start(_ p: Substring?) -> Int { p.flatMap { Int($0.dropFirst().split(separator: ",").first ?? "") } ?? 1 }
        return (start(parts.first(where: { $0.hasPrefix("-") })), start(parts.first(where: { $0.hasPrefix("+") })))
    }

    /// Undo one hunk. When the file's staged copy matches the working file, both are undone (so the change does
    /// not ride the next commit); otherwise only the working file is. Returns nil on success, else git's message.
    public static func revert(_ hunk: DiffHunk, repo: String) -> String? {
        let file = NSTemporaryDirectory() + "oneroof-revert-\(UUID().uuidString).patch"
        defer { try? FileManager.default.removeItem(atPath: file) }
        do { try hunk.patch.write(toFile: file, atomically: true, encoding: .utf8) } catch { return "\(error)" }
        if Foundations.run(git, ["-C", repo, "apply", "-R", "--index", "--whitespace=nowarn", file], timeout: 10).0 == 0 { return nil }
        let (code, out) = Foundations.run(git, ["-C", repo, "apply", "-R", "--whitespace=nowarn", file], timeout: 10)
        return code == 0 ? nil : out.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The text sent to an agent for a review comment on a hunk.
    public static func reviewMessage(_ comment: String, hunk: DiffHunk) -> String {
        "Review comment on \(hunk.file):\(hunk.firstNewLine) (\(hunk.header)): \(comment)"
    }
}
