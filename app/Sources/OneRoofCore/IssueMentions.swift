import Foundation

/// LAB-511: the Linear issues a session worked on without having them attached. Its Ticket tab said "No Linear issue
/// yet" for a session whose opening message read "work on bugs 298 and 460"; it now lists what the session mentions
/// (its name, opening message, objective, notes and terminal output) so each can be attached with one click.
public enum IssueMentions {
    private static let keyRegex = try! NSRegularExpression(pattern: #"(?<![A-Za-z0-9-])([A-Z][A-Z0-9]{1,4})-(\d{1,5})(?![0-9])"#)
    private static let bareRegex = try! NSRegularExpression(
        pattern: #"(?i)\b(?:bugs?|issues?|tickets?|defects?)\s+#?(\d{2,5}(?:\s*(?:,|and|&)\s*#?\d{2,5})*)"#)
    private static let numberRegex = try! NSRegularExpression(pattern: #"\d{2,5}"#)

    /// The team a session's bare issue numbers belong to: its ticket's team, else its project code's first part.
    public static func team(of s: Session) -> String? {
        if let t = s.ticketTeam, !t.isEmpty { return t.uppercased() }
        return s.workstream?.split(separator: "-").first.map { $0.uppercased() }
    }

    /// Keys in order of first mention, without duplicates or the session's own issues. `teams` limits full keys to
    /// real team keys (so "UTF-8" or "SHA-256" are not issues); empty = any. Bare numbers after "bug", "issues", "ticket"
    /// … take `team`.
    public static func keys(in texts: [String], team: String?, teams: Set<String> = [], excluding: [String] = []) -> [String] {
        var found: [(Int, Int, String)] = []   // (text index, offset, key) to keep the order of mention
        for (ti, text) in texts.enumerated() {
            let ns = text as NSString
            for m in keyRegex.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
                let t = ns.substring(with: m.range(at: 1))
                guard teams.isEmpty || teams.contains(t) else { continue }
                found.append((ti, m.range.location, t + "-" + ns.substring(with: m.range(at: 2))))
            }
            guard let team, !team.isEmpty else { continue }
            for m in bareRegex.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
                let list = ns.substring(with: m.range(at: 1))
                for n in numberRegex.matches(in: list, range: NSRange(location: 0, length: (list as NSString).length)) {
                    found.append((ti, m.range.location + n.range.location, team.uppercased() + "-" + (list as NSString).substring(with: n.range)))
                }
            }
        }
        let own = Set(excluding.map { $0.uppercased() })
        var seen = Set<String>(), out: [String] = []
        for (_, _, k) in found.sorted(by: { ($0.0, $0.1) < ($1.0, $1.1) }) {
            let n = k.split(separator: "-").last.flatMap { Int($0) } ?? 0
            guard n > 0, !own.contains(k), seen.insert(k).inserted else { continue }
            out.append(k)
        }
        return out
    }

    /// What to read for a session: name, opening message, objective, notes, then the terminal text (if any).
    public static func texts(_ s: Session, terminal: String? = nil) -> [String] {
        [s.name, s.openingMessage, s.objective, s.notes] + (terminal.map { [$0] } ?? [])
    }
}
