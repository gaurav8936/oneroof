import Foundation

/// LAB-1606 · an agent that ends its turn with a plain-text question ("Should I commit this?") is waiting for you, as
/// much as one at a permission prompt: Needs you shows it, marked as a question. roofd reads the turn's last message
/// when Claude's Stop hook fires (from the hook, or the tail of the conversation file it names).
public enum EndOfTurn {
    /// The question a message ends with: its last sentence, at most 300 characters; nil when the last thing it says
    /// is not a question (a statement, a list, code).
    public static func question(_ message: String) -> String? {
        var s = message.trimmingCharacters(in: .whitespacesAndNewlines)
        // An odd number of fences: the message ends inside a code block.
        guard s.components(separatedBy: "```").count % 2 == 1 else { return nil }
        while let c = s.last, "*_`\"'\u{201D}\u{2019}) \t".contains(c) { s.removeLast() }
        guard s.hasSuffix("?") else { return nil }
        var line = String(s.split(separator: "\n", omittingEmptySubsequences: true).last ?? Substring(s))
            .trimmingCharacters(in: .whitespaces)
        for p in ["> ", "- ", "* ", "• ", "**", "__", "#"] where line.hasPrefix(p) {
            line = String(line.dropFirst(p.count)).trimmingCharacters(in: .whitespaces)
        }
        // The last sentence: after the last ". ", "! " or "? " before the closing question mark.
        let body = line.dropLast()
        var start = body.startIndex
        for end in [". ", "! ", "? "] {
            if let r = body.range(of: end, options: .backwards), r.upperBound > start { start = r.upperBound }
        }
        let q = (String(body[start...]) + "?").trimmingCharacters(in: .whitespaces)
        guard q.count >= 4 else { return nil }
        return String(q.prefix(300))
    }

    /// Claude's last reply text in the tail of its conversation file (JSON lines, newest last); nil when the newest
    /// entry with text is the owner's prompt (the turn said nothing).
    public static func lastClaudeText(transcriptTail: String) -> String? {
        for line in transcriptTail.split(separator: "\n").reversed() {
            guard let d = line.data(using: .utf8),
                  let j = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any],
                  let message = j["message"] as? [String: Any] else { continue }
            let type = j["type"] as? String
            if type == "user" {
                if message["content"] is String { return nil }   // the owner's prompt: nothing said after it
                continue                                          // a tool result
            }
            guard type == "assistant", let content = message["content"] as? [[String: Any]] else { continue }
            let text = content.compactMap { $0["type"] as? String == "text" ? $0["text"] as? String : nil }.joined(separator: "\n")
            if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return text }
        }
        return nil
    }

    /// The last `bytes` of a file (the start of the first, partial line is dropped).
    public static func tail(path: String, bytes: Int = 262_144) -> String? {
        guard let h = FileHandle(forReadingAtPath: path) else { return nil }
        defer { try? h.close() }
        let size = (try? h.seekToEnd()) ?? 0
        let from = size > UInt64(bytes) ? size - UInt64(bytes) : 0
        try? h.seek(toOffset: from)
        guard let d = try? h.readToEnd(), var s = String(data: d, encoding: .utf8) ?? String(data: d.dropFirst(min(4, d.count)), encoding: .utf8) else { return nil }
        if from > 0, let nl = s.firstIndex(of: "\n") { s = String(s[s.index(after: nl)...]) }
        return s
    }

    /// The question at the end of a Claude turn, from the Stop hook's payload: its own last message when the hook
    /// carries one, else the conversation file's tail.
    public static func question(stopPayload p: [String: Any]) -> String? {
        let text = (p["last_assistant_message"] as? String)
            ?? (p["transcript_path"] as? String).flatMap { tail(path: $0) }.flatMap { lastClaudeText(transcriptTail: $0) }
        return text.flatMap(question)
    }
}
