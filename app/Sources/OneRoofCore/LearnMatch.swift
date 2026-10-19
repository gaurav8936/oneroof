import Foundation

/// "How do I…": rank Learn pages (field manual, skills, Help, extra folders) for a question or for a session's
/// name and objective. Plain word overlap, no model: title words count three times as much as summary words, and a
/// word that appears on nearly every page counts for little. Fast enough to run on every keystroke over ~250 pages.
public enum LearnMatch {
    public struct Doc: Sendable {
        public var id: String
        public var title: String
        public var text: String
        public init(id: String, title: String, text: String) { self.id = id; self.title = title; self.text = text }
    }

    static let stop: Set<String> = ["how", "do", "does", "can", "the", "and", "for", "with", "this", "that", "what",
                                    "when", "where", "why", "who", "into", "from", "your", "you", "are", "was", "use",
                                    "using", "make", "get", "set", "one", "all", "any", "out", "via", "per", "its", "our",
                                    "should", "would", "about", "help", "want", "need", "new", "page", "skill"]

    /// Lowercased word stems: letters and digits, 3+ characters, stop words dropped, plural/-ing/-ed trimmed.
    public static func words(_ s: String) -> [String] {
        s.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init)
            .filter { $0.count >= 3 && !stop.contains($0) }.map(stem)
    }

    static func stem(_ w: String) -> String {
        guard w.count > 4 else { return w }
        if w.hasSuffix("ies") { return String(w.dropLast(3)) + "y" }
        if w.hasSuffix("ing") && w.count > 6 { return String(w.dropLast(3)) }
        if w.hasSuffix("ed") && w.count > 5 { return String(w.dropLast(2)) }
        // "matches" → "match", but "worktrees" → "worktree".
        if w.hasSuffix("es"), ["s", "x", "z", "ch", "sh"].contains(where: { w.dropLast(2).hasSuffix($0) }) { return String(w.dropLast(2)) }
        if w.hasSuffix("s") && !w.hasSuffix("ss") { return String(w.dropLast()) }
        return w
    }

    /// The best `limit` documents for `query`, best first; documents sharing no word with it are left out.
    public static func rank(_ query: String, _ docs: [Doc], limit: Int = 8) -> [String] {
        let q = Set(words(query))
        guard !q.isEmpty, !docs.isEmpty else { return [] }
        let bags = docs.map { (Set(words($0.title)), Set(words($0.text))) }
        // Rarer words weigh more (inverse document frequency over this set of pages).
        var df: [String: Int] = [:]
        for (t, x) in bags { for w in t.union(x) where q.contains(w) { df[w, default: 0] += 1 } }
        let n = Double(docs.count)
        func weight(_ w: String) -> Double { log(1 + n / Double(df[w] ?? 1)) }
        let scored = docs.indices.compactMap { i -> (String, Double)? in
            let (t, x) = bags[i]
            let s = q.reduce(0.0) { acc, w in acc + (t.contains(w) ? 3 * weight(w) : x.contains(w) ? weight(w) : 0) }
            return s > 0 ? (docs[i].id, s) : nil
        }
        return scored.sorted { $0.1 != $1.1 ? $0.1 > $1.1 : $0.0 < $1.0 }.prefix(limit).map(\.0)
    }
}
