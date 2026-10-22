import Foundation

/// LAB-513: what the plan panel's Artifacts tab shows, all of it this session's own: files its agent wrote or edited,
/// its objective's plan, handoffs whose names carry its project code or one of its issue keys (whole id), and the
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
    public static func handoffs(in dir: String, project: String?, tickets: [String], limit: Int = 3) -> [String] {
        let keys = (tickets + [project].compactMap { $0 }).map { $0.lowercased() }.filter { !$0.isEmpty }
        guard !keys.isEmpty else { return [] }
        let files = ((try? FileManager.default.contentsOfDirectory(atPath: dir)) ?? []).filter { !$0.hasPrefix(".") }.sorted()
        func names(_ f: String) -> Bool {
            keys.contains { k in
                f.lowercased().range(of: "(?<![a-z0-9])" + NSRegularExpression.escapedPattern(for: k) + "(?![a-z0-9])", options: .regularExpression) != nil
            }
        }
        return files.reversed().filter(names).prefix(limit).map { dir + "/" + $0 }
    }

    /// Everything for one session, files that no longer exist left out.
    public static func list(_ s: Session, plan: String?, handoffDir: String,
                            exists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }) -> [Item] {
        var out: [Item] = []
        if let plan { out.append(Item(path: plan, kind: .plan)) }
        out += s.writtenFiles.map { Item(path: $0, kind: .written) }
        out += handoffs(in: handoffDir, project: s.workstream, tickets: s.allTickets.map(\.key)).map { Item(path: $0, kind: .handoff) }
        out += screenshots(in: s.openingMessage).map { Item(path: $0, kind: .screenshot) }
        var seen = Set<String>()
        return out.filter { exists($0.path) && seen.insert($0.path).inserted }
    }
}
