import Foundation

/// Git status badges for the file tree (S06 Files panel, COMPONENTS FileTreeRow): M · A · D · ? per path, from
/// `git status --porcelain=v2 -z`. Folders inherit the strongest badge of anything below them.
public enum GitBadge: String, Sendable, Comparable {
    case modified = "M", added = "A", deleted = "D", untracked = "?"

    private var rank: Int { switch self { case .deleted: return 3; case .added: return 2; case .modified: return 1; case .untracked: return 0 } }
    public static func < (a: GitBadge, b: GitBadge) -> Bool { a.rank < b.rank }
}

public enum GitStatus {
    /// Badges keyed by path relative to the repo root.
    public static func parse(_ porcelainV2Z: String) -> [String: GitBadge] {
        var out: [String: GitBadge] = [:]
        var fields = porcelainV2Z.split(separator: "\0", omittingEmptySubsequences: false).map(String.init)[...]
        while let rec = fields.popFirst() {
            guard let kind = rec.first else { continue }
            switch kind {
            case "1", "2":
                // 1 XY sub mH mI mW hH hI path   ·   2 XY sub mH mI mW hH hI Xscore path  (+ origPath as next field)
                let parts = rec.split(separator: " ", maxSplits: kind == "1" ? 8 : 9, omittingEmptySubsequences: false)
                guard parts.count >= (kind == "1" ? 9 : 10) else { continue }
                let xy = Array(parts[1])
                let path = String(parts[parts.count - 1])
                let b: GitBadge = xy.contains("D") ? .deleted : (xy.contains("A") ? .added : .modified)
                out[path] = b
                if kind == "2" { _ = fields.popFirst() }
            case "?":
                out[String(rec.dropFirst(2))] = .untracked
            default:
                continue
            }
        }
        return out
    }

    /// Run git status for a repo root (nil when it is not a repo).
    public static func badges(repo: String) -> [String: GitBadge]? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: GitDiff.git)
        p.arguments = ["-C", repo, "status", "--porcelain=v2", "-z", "--untracked-files=normal"]
        let out = Pipe()
        p.standardOutput = out
        p.standardError = Pipe()
        do { try p.run() } catch { return nil }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        guard p.terminationStatus == 0 else { return nil }
        return parse(String(decoding: data, as: UTF8.self))
    }

    /// The badge for a folder: the strongest badge of any path inside it.
    public static func folderBadge(_ rel: String, in badges: [String: GitBadge]) -> GitBadge? {
        let prefix = rel.isEmpty ? "" : rel + "/"
        return badges.filter { $0.key.hasPrefix(prefix) }.values.max()
    }
}
