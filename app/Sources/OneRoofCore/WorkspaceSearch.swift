import Foundation

/// Global search: text across the workspace's git repos with `git grep` (tracked and untracked files,
/// .gitignore respected, binaries skipped). No extra tool to install: git is always there.
public struct SearchHit: Equatable, Identifiable, Sendable {
    public var id: String { path + ":\(line)" }
    public var repo: String
    public var path: String        // absolute
    public var line: Int
    public var text: String
}

public enum WorkspaceSearch {
    /// Folders under ~/Projects (two levels: domain/repo, plus repos at the top) that are git repos. Data folders
    /// and archives are skipped.
    public static func repos(root: String = Workspace.projectsRoot) -> [String] {
        let fm = FileManager.default
        func isRepo(_ p: String) -> Bool { fm.fileExists(atPath: p + "/.git") }
        func skip(_ name: String) -> Bool { name.hasPrefix(".") || name.hasSuffix("-data") || name.hasPrefix("_archive") || name == "node_modules" }
        var out: [String] = []
        for a in ((try? fm.contentsOfDirectory(atPath: root)) ?? []).sorted() where !skip(a) {
            let p = root + "/" + a
            if isRepo(p) { out.append(p); continue }
            for b in ((try? fm.contentsOfDirectory(atPath: p)) ?? []).sorted() where !skip(b) {
                let q = p + "/" + b
                if isRepo(q) { out.append(q) }
            }
        }
        return out
    }

    /// Search `repos` in parallel; at most `limit` hits in all, `perRepo` per repo. Fixed-string match.
    public static func search(_ query: String, repos: [String], caseSensitive: Bool = false,
                              limit: Int = 500, perRepo: Int = 200) -> [SearchHit] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard q.count >= 2 else { return [] }
        var results = [[SearchHit]](repeating: [], count: repos.count)
        let lock = NSLock()
        DispatchQueue.concurrentPerform(iterations: repos.count) { i in
            let repo = repos[i]
            var args = ["-C", repo, "-c", "core.quotepath=off", "grep", "-n", "-I", "-z", "--untracked", "--fixed-strings",
                        "--max-count", "20", "-e", q]
            if !caseSensitive { args.insert("-i", at: 5) }
            let (code, out) = Foundations.run(GitDiff.git, args, timeout: 15)
            guard code == 0 else { return }     // 1 = no match
            let hits = Array(parse(out, repo: repo).prefix(perRepo))
            lock.lock(); results[i] = hits; lock.unlock()
        }
        return Array(results.joined().prefix(limit))
    }

    /// `git grep -n -z` lines: "path\0line\0text".
    static func parse(_ out: String, repo: String) -> [SearchHit] {
        out.split(separator: "\n", omittingEmptySubsequences: true).compactMap { line in
            let f = line.split(separator: "\0", maxSplits: 2, omittingEmptySubsequences: false)
            guard f.count == 3, let n = Int(f[1]) else { return nil }
            let text = f[2].trimmingCharacters(in: .whitespaces)
            return SearchHit(repo: repo, path: repo + "/" + f[0], line: n, text: String(text.prefix(300)))
        }
    }
}
