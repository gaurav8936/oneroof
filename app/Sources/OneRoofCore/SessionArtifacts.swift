import Foundation

/// LAB-513: what the plan panel's Artifacts tab shows, all of it this session's own: files its agent wrote or edited,
/// its objective's plan, handoffs it wrote (named for its project code or one of its issue keys, whole id), and the
/// screenshots given to it in its opening message. It used to list any handoff whose name merely contained the project
/// code, from any session, and nothing the session itself wrote.
public enum SessionArtifacts {
    public enum Kind: String, Sendable { case written = "Written by this session", plan = "Plan", handoff = "Handoff", screenshot = "Screenshot you gave it" }

    public struct Item: Equatable, Hashable, Sendable {
        public var path: String
        public var kind: Kind
        public init(path: String, kind: Kind) { self.path = path; self.kind = kind }
    }

    /// The most files kept per session.
    public static let cap = 60

    /// Fold newly seen edits (path → when) into the stored list: newest first, no duplicates, at most `cap`.
    public static func merge(_ stored: [String], edits: [String: Date]) -> [String] {
        let fresh = edits.sorted { $0.value > $1.value }.map(\.key)
        var seen = Set<String>(), out: [String] = []
        for p in fresh + stored where seen.insert(p).inserted { out.append(p) }
        return Array(out.prefix(cap))
    }

    /// Image paths in an opening message (screenshots pasted or dropped into the New session sheet).
    public static func screenshots(in opening: String) -> [String] {
        let ns = opening as NSString
        let re = try! NSRegularExpression(pattern: #"(/[^\s"'`<>()]+\.(?:png|jpe?g|gif|webp|heic|tiff?))"#, options: [.caseInsensitive])
        var out: [String] = []
        for m in re.matches(in: opening, range: NSRange(location: 0, length: ns.length)) {
            let p = ns.substring(with: m.range(at: 1))
            if !out.contains(p) { out.append(p) }
        }
        return out
    }

    /// Handoffs in `dir` that name the project or one of the issues (whole id, anywhere in the name), newest first.
    public static func handoffs(in dir: String, project: String?, tickets: [String], since: Date? = nil, limit: Int = 3) -> [String] {
        let keys = (tickets + [project].compactMap { $0 }).map { $0.lowercased() }.filter { !$0.isEmpty }
        guard !keys.isEmpty else { return [] }
        let files = ((try? FileManager.default.contentsOfDirectory(atPath: dir)) ?? []).filter { !$0.hasPrefix(".") }.sorted()
        // One pattern for every key, compiled once per scan (0.4.8 compiled one per file per key on every redraw).
        let alts = keys.map { NSRegularExpression.escapedPattern(for: $0) }.joined(separator: "|")
        guard let re = try? NSRegularExpression(pattern: "(?<![a-z0-9])(?:" + alts + ")(?![a-z0-9])") else { return [] }
        func names(_ f: String) -> Bool {
            let l = f.lowercased()
            return re.firstMatch(in: l, range: NSRange(l.startIndex..., in: l)) != nil
        }
        // LAB-510: written during the session (after it launched), not the older handoffs it started from.
        return files.reversed().filter(names).map { dir + "/" + $0 }.filter { p in since.map { Workspace.writtenSince(p, $0) } ?? true }
            .prefix(limit).map { $0 }
    }

    /// Everything for one session, files that no longer exist left out.
    public static func list(_ s: Session, plan: String?, handoffDir: String,
                            exists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }) -> [Item] {
        var out: [Item] = []
        if let plan { out.append(Item(path: plan, kind: .plan)) }
        out += s.writtenFiles.map { Item(path: $0, kind: .written) }
        out += handoffs(in: handoffDir, project: s.workstream, tickets: s.allTickets.map(\.key), since: s.launchedAt ?? s.createdAt)
            .map { Item(path: $0, kind: .handoff) }
        out += screenshots(in: s.openingMessage).map { Item(path: $0, kind: .screenshot) }
        var seen = Set<String>()
        return out.filter { exists($0.path) && seen.insert($0.path).inserted }
    }
}
