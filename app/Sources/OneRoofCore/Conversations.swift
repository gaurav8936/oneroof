import Foundation

/// A Claude conversation on disk that a new session can `--resume` (bringing work from another terminal into One Roof).
public struct Conversation: Identifiable, Equatable, Sendable {
    public var id: String          // session id = file name without .jsonl
    public var title: String
    public var lastPrompt: String?
    public var modified: Date

    /// Active in the last 15 minutes: probably still open in another terminal.
    public func maybeOpen(now: Date = Date()) -> Bool { now.timeIntervalSince(modified) < 15 * 60 }
}

public enum ConversationIndex {
    /// Claude stores conversations per launch folder: ~/.claude/projects/<folder with non-alphanumerics → "-">.
    /// (~/.claude-2/projects is a symlink to the same place on the owner's Mac.)
    public static func folder(forLaunchDirectory dir: String, configDir: String? = nil) -> String {
        let base = configDir ?? (NSHomeDirectory() as NSString).appendingPathComponent(".claude")
        let mangled = String(dir.map { $0.isLetter || $0.isNumber ? $0 : "-" })
        return ((base as NSString).appendingPathComponent("projects") as NSString).appendingPathComponent(mangled)
    }

    /// The most recently modified conversations in `folder`, newest first.
    public static func recent(in folder: String, limit: Int = 40) -> [Conversation] {
        let fm = FileManager.default
        guard let names = try? fm.contentsOfDirectory(atPath: folder) else { return [] }
        var files: [(String, Date)] = []
        for n in names where n.hasSuffix(".jsonl") {
            let p = (folder as NSString).appendingPathComponent(n)
            if let a = try? fm.attributesOfItem(atPath: p), let d = a[.modificationDate] as? Date,
               (a[.size] as? Int ?? 0) > 0 {
                files.append((p, d))
            }
        }
        files.sort { $0.1 > $1.1 }
        return files.prefix(limit).compactMap { path, date in
            guard let tail = readTail(path, bytes: 96 * 1024) else { return nil }
            let (title, prompt) = parse(tail)
            let id = ((path as NSString).lastPathComponent as NSString).deletingPathExtension
            guard title != nil || prompt != nil else { return nil }   // nothing said yet: not resumable
            return Conversation(id: id, title: title ?? String(prompt!.prefix(60)), lastPrompt: prompt, modified: date)
        }
    }

    static func readTail(_ path: String, bytes: Int) -> Data? {
        guard let h = FileHandle(forReadingAtPath: path) else { return nil }
        defer { try? h.close() }
        let size = (try? h.seekToEnd()) ?? 0
        let start = size > UInt64(bytes) ? size - UInt64(bytes) : 0
        try? h.seek(toOffset: start)
        return try? h.readToEnd()
    }

    /// The last `ai-title` and `last-prompt` in a chunk of JSONL (a partial first line is skipped).
    public static func parse(_ data: Data) -> (title: String?, lastPrompt: String?) {
        var title: String?, prompt: String?
        for line in data.split(separator: 0x0A) {
            guard line.first == UInt8(ascii: "{"),
                  let obj = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any],
                  let type = obj["type"] as? String else { continue }
            if type == "ai-title", let t = obj["aiTitle"] as? String, !t.isEmpty { title = t }
            if type == "last-prompt", let p = obj["lastPrompt"] as? String, !p.isEmpty { prompt = p }
        }
        return (title, prompt)
    }
}
