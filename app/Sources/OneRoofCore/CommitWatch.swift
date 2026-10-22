import Foundation

/// Move a session's issue to In Review once a commit names it (LAB-474: a session can resolve several issues, each
/// committed as `KEY · [project] …`). The app reads recent commit subjects across the workspace repos; this decides
/// which pending issue a commit closes.
public enum CommitWatch {
    public struct Commit: Equatable, Sendable {
        public var sha: String
        public var subject: String
        public var time: Date
        public var repo: String
        public init(sha: String, subject: String, time: Date, repo: String) {
            self.sha = sha; self.subject = subject; self.time = time; self.repo = repo
        }
    }

    /// Sessions launched longer ago than this are no longer watched.
    public static let window: TimeInterval = 3 * 24 * 3600

    /// `git log` arguments for commits since `since`, all refs (worktrees and pushed branches included).
    public static func logArgs(repo: String, since: Date) -> [String] {
        ["-C", repo, "log", "--all", "--since=@\(Int(since.timeIntervalSince1970))", "-n", "300", "--format=%h%x1f%ct%x1f%s"]
    }

    public static func parseLog(_ out: String, repo: String) -> [Commit] {
        out.split(separator: "\n").compactMap { line in
            let f = line.split(separator: "\u{1f}", maxSplits: 2, omittingEmptySubsequences: false).map(String.init)
            guard f.count == 3, let t = Double(f[1]) else { return nil }
            return Commit(sha: f[0], subject: f[2], time: Date(timeIntervalSince1970: t), repo: repo)
        }
    }

    /// The subject names this exact key: LAB-47 is not LAB-474, and lab-474 counts.
    public static func names(_ subject: String, key: String) -> Bool {
        let k = NSRegularExpression.escapedPattern(for: key)
        return subject.range(of: "(?<![A-Za-z0-9-])\(k)(?![0-9])", options: [.regularExpression, .caseInsensitive]) != nil
    }

    /// The session's issues not yet moved to In Review.
    public static func pending(_ s: Session) -> [SessionIssue] {
        s.allTickets.filter { i in i.id != nil && !s.reviewedTickets.contains { $0.caseInsensitiveCompare(i.key) == .orderedSame } }
    }

    /// Whether the watch should look at this session now.
    public static func watches(_ s: Session, now: Date = Date()) -> Bool {
        guard let at = s.launchedAt, s.lifecycle != .doNotUse else { return false }
        return now.timeIntervalSince(at) < window && !pending(s).isEmpty
    }

    /// For each pending issue, the oldest commit made after the session launched that names it.
    public static func matches(_ s: Session, in commits: [Commit]) -> [(SessionIssue, Commit)] {
        guard let at = s.launchedAt else { return [] }
        let after = commits.filter { $0.time >= at.addingTimeInterval(-60) }.sorted { $0.time < $1.time }
        return pending(s).compactMap { i in after.first { names($0.subject, key: i.key) }.map { (i, $0) } }
    }
}
