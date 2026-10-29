import Foundation

/// LAB-1585 · find a session by what it worked on, not only by its name. Each session's text is its name, issue,
/// repo, window and opening message, plus what was said in its Claude conversation (your messages and Claude's
/// replies, trimmed). Ranking is word overlap (LearnMatch's stems: rare words count most, a match in the name counts
/// three times); the on-device model can widen a question with related words first ("frames freezing" → stall, hang,
/// jank), so meaning finds a session even when its words differ. Every hit carries the line that matched.
public enum SessionSearch {
    public struct Doc: Sendable {
        public var id: String
        public var title: String
        /// Name, issue, repo, window, opening message.
        public var meta: String
        /// The conversation's text, one line per message (may be empty).
        public var lines: [String]
        public init(id: String, title: String, meta: String, lines: [String]) {
            self.id = id; self.title = title; self.meta = meta; self.lines = lines
        }
    }

    public struct Hit: Equatable, Sendable {
        public var id: String
        public var score: Double
        /// The best matching line, shortened around the match ("" when only the name or details matched).
        public var snippet: String
    }

    /// Ranked hits for a question; `extra` are related words (from the model), counted at half weight.
    public static func rank(_ query: String, extra: [String] = [], docs: [Doc], limit: Int = 200) -> [Hit] {
        let main = Set(keys(query)), wide = Set(extra.flatMap(LearnMatch.words)).subtracting(main)
        guard !main.isEmpty || !wide.isEmpty else { return [] }
        // How many sessions use each word: a word in nearly every session says little.
        var df: [String: Int] = [:]
        let bags = docs.map { d -> (title: Set<String>, body: [String: Int]) in
            let title = Set(keys(d.title + " " + d.meta))
            var body: [String: Int] = [:]
            for l in d.lines { for w in keys(l) { body[w, default: 0] += 1 } }
            for w in title.union(body.keys) where main.contains(w) || wide.contains(w) { df[w, default: 0] += 1 }
            return (title, body)
        }
        let n = Double(max(docs.count, 1))
        func idf(_ w: String) -> Double { log(1 + (n - Double(df[w] ?? 0) + 0.5) / (Double(df[w] ?? 0) + 0.5)) }
        // BM25: a word's count saturates, and a long conversation is not rewarded just for being long.
        let lengths = bags.map { Double($0.body.values.reduce(0, +)) }
        let avg = max(lengths.reduce(0, +) / n, 1)
        var hits: [Hit] = []
        for (k, d) in docs.enumerated() {
            let bag = bags[k]
            var score = 0.0, matched = 0
            for (words, weight) in [(main, 1.0), (wide, 0.4)] {
                for w in words {
                    let inTitle = bag.title.contains(w), f = Double(bag.body[w] ?? 0)
                    guard inTitle || f > 0 else { continue }
                    if weight == 1 { matched += 1 }
                    let tf = f * 2.2 / (f + 1.2 * (0.25 + 0.75 * lengths[k] / avg))
                    score += weight * idf(w) * ((inTitle ? 3 : 0) + tf)
                }
            }
            // Every word of the question present beats most words present many times.
            if !main.isEmpty { score *= 0.3 + Double(matched) / Double(main.count) }
            guard score > 0 else { continue }
            hits.append(Hit(id: d.id, score: score, snippet: snippet(d.lines, main: main, wide: wide)))
        }
        return Array(hits.sorted { $0.score > $1.score }.prefix(limit))
    }

    /// The line with the most question words (then related words), cut to ~140 characters around the first match.
    static func snippet(_ lines: [String], main: Set<String>, wide: Set<String>) -> String {
        var best: (score: Int, line: String)? = nil
        for l in lines where !l.contains("Stay on this focus") {   // One Roof's own focus line says nothing about the work
            let ws = Set(keys(l))
            let s = ws.intersection(main).count * 3 + ws.intersection(wide).count
            if s > 0, s > (best?.score ?? 0) { best = (s, l) }
        }
        guard let line = best?.line else { return "" }
        let flat = line.replacingOccurrences(of: "\n", with: " ")
        guard flat.count > 140 else { return flat }
        let lower = flat.lowercased()
        let at = (main.union(wide)).compactMap { lower.range(of: String($0.prefix(5)))?.lowerBound }.min() ?? lower.startIndex
        let off = max(0, lower.distance(from: lower.startIndex, to: at) - 40)
        let start = flat.index(flat.startIndex, offsetBy: off)
        let end = flat.index(start, offsetBy: min(140, flat.distance(from: start, to: flat.endIndex)))
        return (off > 0 ? "…" : "") + flat[start..<end] + (end < flat.endIndex ? "…" : "")
    }

    /// LearnMatch's word stems, cut to their first five letters, so freeze, freezing and freezes meet.
    public static func keys(_ s: String) -> [String] { LearnMatch.words(s).map { String($0.prefix(5)) } }

    // MARK: Conversations

    /// Where a Claude conversation's transcript lives: <claude dir>/projects/<folder>/<id>.jsonl, in ~/.claude or
    /// any ~/.claude-* account folder.
    public static func transcript(id: String, home: String = NSHomeDirectory()) -> String? {
        let fm = FileManager.default
        for dir in ((try? fm.contentsOfDirectory(atPath: home)) ?? []).sorted() where dir == ".claude" || dir.hasPrefix(".claude-") {
            let projects = home + "/" + dir + "/projects"
            for p in (try? fm.contentsOfDirectory(atPath: projects)) ?? [] {
                let f = projects + "/" + p + "/" + id + ".jsonl"
                if fm.fileExists(atPath: f) { return f }
            }
        }
        return nil
    }

    /// The text of a Claude transcript, one line per message: what you asked and what Claude answered (tool calls and
    /// results left out), capped so one long session cannot crowd the index.
    public static func conversationLines(path: String, maxChars: Int = 60_000) -> [String] {
        guard let data = FileManager.default.contents(atPath: path), let text = String(data: data, encoding: .utf8) else { return [] }
        var out: [String] = [], total = 0
        for raw in text.split(separator: "\n") {
            guard raw.contains("\"message\""), let d = raw.data(using: .utf8),
                  let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
                  let type = o["type"] as? String, type == "user" || type == "assistant",
                  let m = o["message"] as? [String: Any] else { continue }
            var parts: [String] = []
            if let s = m["content"] as? String { parts = [s] }
            else if let arr = m["content"] as? [[String: Any]] {
                parts = arr.compactMap { $0["type"] as? String == "text" ? $0["text"] as? String : nil }
            }
            for p in parts {
                let t = p.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !t.isEmpty, !t.hasPrefix("<"), t.count < 8_000 else { continue }   // skip system/command wrappers
                let line = String(t.prefix(1_500))
                out.append(line); total += line.count
                if total > maxChars { return out }
            }
        }
        return out
    }

    // MARK: Widening with the model

    /// The prompt that asks the on-device model for related search words.
    public static func expansionBody(_ query: String) -> Data {
        let system = "You help search a developer's past coding-agent sessions. Given a search, reply with up to 12 "
            + "short related words or phrases a session about it would likely contain: synonyms, symptoms, technical "
            + "terms. Reply with the words only, comma separated."
        let body: [String: Any] = [
            "messages": [["role": "system", "content": system], ["role": "user", "content": query]],
            "temperature": 0, "max_tokens": 80,
            "chat_template_kwargs": ["enable_thinking": false],
        ]
        return (try? JSONSerialization.data(withJSONObject: body)) ?? Data()
    }

    static let filler: Set<String> = ["technical terms", "coding agent", "session", "sessions", "synonyms", "symptoms"]

    /// The model's answer → words (comma or newline separated, quotes and numbering dropped).
    public static func parseExpansion(_ s: String?) -> [String] {
        guard let s else { return [] }
        return s.split(whereSeparator: { $0 == "," || $0 == "\n" })
            .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: " \t\"'-*.0123456789)")) }
            .map { $0.replacingOccurrences(of: "_", with: " ") }
            .filter { !$0.isEmpty && $0.count < 40 && !filler.contains($0.lowercased()) }
            .reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }
            .prefix(12).map { $0 }
    }
}

public extension LocalModel {
    /// LAB-1585 · related words for a session search, or [] when the model is unavailable. Call off the main thread.
    func expandSearch(_ query: String, modelPath: String = LocalModel.modelPath) -> [String] {
        guard ensureRunning(modelPath: modelPath) else { return [] }
        var req = URLRequest(url: URL(string: "http://127.0.0.1:\(Self.port)/v1/chat/completions")!, timeoutInterval: 15)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = SessionSearch.expansionBody(query)
        let sem = DispatchSemaphore(value: 0)
        var answer: String?
        URLSession.shared.dataTask(with: req) { d, _, _ in
            if let d, let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
               let c = (j["choices"] as? [[String: Any]])?.first, let m = c["message"] as? [String: Any] {
                answer = m["content"] as? String
            }
            sem.signal()
        }.resume()
        _ = sem.wait(timeout: .now() + 16)
        return SessionSearch.parseExpansion(answer)
    }
}
