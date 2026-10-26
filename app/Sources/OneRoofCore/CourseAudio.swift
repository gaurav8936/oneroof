import Foundation

/// The audio for Learn's player: narrated deck cards (one clip per scene, listed in the card page's `__TTS__`) and the
/// narration folders of extra Learn folders (classic window). Read where it lives; never copied. (The name is older than
/// 1.9.2, which removed the course itself, LAB-1274.)
public struct CourseTrack: Equatable, Sendable {
    public var title: String
    public var path: String       // absolute .mp3
    public init(title: String, path: String) { self.title = title; self.path = path }
}

public enum CourseAudio {
    /// A narrated skill page's clips in play order. The page embeds `window.__TTS__={"openai": {"<hash>": "<rel>.mp3",
    /// …}}` in scene order; titles come from the sibling `spec.json` (section · scene heading) when the counts agree.
    public static func tracks(page htmlPath: String) -> [CourseTrack] {
        // LAB-1233: the deck's pages write `window.__TTS__ = {` (spaces around "="); older pages had none.
        guard let html = try? String(contentsOfFile: htmlPath, encoding: .utf8),
              let start = html.range(of: #"window\.__TTS__\s*=\s*"#, options: .regularExpression) else { return [] }
        let tail = html[start.upperBound...]
        let block = tail.prefix(while: { $0 != "\n" && $0 != "<" })
        let dir = (htmlPath as NSString).deletingLastPathComponent
        // Keys in file order (JSONSerialization would lose it).
        let re = try! NSRegularExpression(pattern: #""[0-9a-zA-Z_-]+":\s*"([^"]+\.mp3)""#)
        let s = String(block)
        var seen = Set<String>()
        let rels = re.matches(in: s, range: NSRange(s.startIndex..., in: s)).compactMap { m -> String? in
            Range(m.range(at: 1), in: s).map { String(s[$0]) }
        }.filter { seen.insert($0).inserted }
        let titles = sceneTitles(spec: dir + "/spec.json")
        return rels.enumerated().compactMap { i, rel in
            let p = dir + "/" + rel
            guard FileManager.default.fileExists(atPath: p) else { return nil }
            return CourseTrack(title: titles.count == rels.count ? titles[i] : "Part \(i + 1)", path: p)
        }
    }

    /// "Section · scene heading" for every scene that has narration, in order.
    static func sceneTitles(spec path: String) -> [String] {
        guard let d = FileManager.default.contents(atPath: path),
              let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
              let sections = j["sections"] as? [[String: Any]] else { return [] }
        return sections.flatMap { sec -> [String] in
            let st = sec["title"] as? String ?? ""
            return (sec["scenes"] as? [[String: Any]] ?? []).filter { ($0["narration"] as? String)?.isEmpty == false }.map { sc in
                let h = sc["heading"] as? String ?? sc["kicker"] as? String ?? ""
                return st.isEmpty ? h : h.isEmpty ? st : st + " · " + h
            }
        }
    }

    /// A folder of narration clips named `<slug>-<hash>.mp3`: "intro" first, then by name; titles from the slug.
    public static func tracks(folder: String) -> [CourseTrack] {
        let names = ((try? FileManager.default.contentsOfDirectory(atPath: folder)) ?? []).filter { $0.hasSuffix(".mp3") }
        return names.sorted { a, b in
            let ai = a.hasPrefix("intro"), bi = b.hasPrefix("intro")
            return ai != bi ? ai : a < b
        }.map { CourseTrack(title: title(slugFile: $0), path: folder + "/" + $0) }
    }

    /// "what-s-next-extending-the-mvp-f9ee69e0b8df.mp3" → "What's next extending the MVP".
    public static func title(slugFile name: String) -> String {
        var slug = (name as NSString).deletingPathExtension
        // "03-check-after-every-hop" (numbered clips in a narration folder) → "check-after-every-hop"
        if let dash = slug.firstIndex(of: "-"), slug[..<dash].count == 2, slug[..<dash].allSatisfy(\.isNumber) {
            slug = String(slug[slug.index(after: dash)...])
        }
        if let dash = slug.lastIndex(of: "-"), slug[slug.index(after: dash)...].allSatisfy(\.isHexDigit),
           slug.distance(from: dash, to: slug.endIndex) > 6 { slug = String(slug[..<dash]) }
        let words = slug.replacingOccurrences(of: "-s-", with: "'s-").split(separator: "-").map(String.init)
        let small: Set<String> = ["mvp", "cli", "api", "ui", "ml", "llm", "ai", "faq"]
        let fixed = words.map { small.contains($0) ? $0.uppercased() : $0 }
        guard let first = fixed.first else { return name }
        return ([first.prefix(1).uppercased() + first.dropFirst()] + fixed.dropFirst()).joined(separator: " ")
    }
}

/// Where the owner left off in each Learn page's audio (track index and seconds), saved by the app.
public struct CourseProgress: Codable, Equatable, Sendable {
    public var track: Int
    public var seconds: Double
    public init(track: Int, seconds: Double) { self.track = track; self.seconds = seconds }
}
