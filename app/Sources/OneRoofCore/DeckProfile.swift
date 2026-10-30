import Foundation

// LAB-1668 · a person card's profile and sources, read from its spec.json (deck 0.2.4+, the deck repository's standard
// "a person's profile and sources on a card"): role, three bio lines, the big idea, the one thing to start with, where
// they publish, their contributions (sources) with links, photo credits, and the deeper pilot's entries. One Roof shows
// them next to the card; the card page itself renders its own Profile / Go deeper block.

public struct DeckProfile: Equatable, Sendable {
    public struct Link: Equatable, Sendable {
        public var title: String; public var url: String; public var type: String; public var year: Int?; public var line: String
    }
    public struct Photo: Equatable, Sendable {
        public var file: String?; public var name: String; public var credit: String; public var licence: String
        public var source: String; public var monogram: String
    }
    public var display: String
    public var role: String
    public var tagline: String
    public var bio: [String]
    public var bigIdea: String
    public var startHere: Link?
    public var publishes: [Link]
    public var sources: [Link]
    public var photos: [Photo]
    public var related: [String]
    public var checked: String
    /// Titles of the deeper pilot's entries (Amodei, Karpathy, Simon Willison).
    public var deeper: [String]

    public static func load(_ specPath: String) -> DeckProfile? {
        guard let d = FileManager.default.contents(atPath: specPath) else { return nil }
        return parse(d)
    }

    /// nil when the spec has no `profile` (a card that is not about a person).
    public static func parse(_ data: Data) -> DeckProfile? {
        guard let j = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let p = j["profile"] as? [String: Any] else { return nil }
        func s(_ v: Any?) -> String { v as? String ?? "" }
        func link(_ v: Any?) -> Link? {
            guard let d = v as? [String: Any], let url = d["url"] as? String, !url.isEmpty else { return nil }
            return Link(title: s(d["title"]).isEmpty ? s(d["label"]) : s(d["title"]), url: url, type: s(d["type"]),
                        year: d["year"] as? Int, line: s(d["line"]))
        }
        let photos = (p["photos"] as? [[String: Any]] ?? []).map {
            Photo(file: ($0["file"] as? String).flatMap { $0.isEmpty ? nil : $0 }, name: s($0["name"]), credit: s($0["photo_credit"]),
                  licence: s($0["photo_licence"]), source: s($0["photo_source"]), monogram: s($0["monogram"]))
        }
        return DeckProfile(display: s(p["display"]).isEmpty ? s(p["name"]) : s(p["display"]), role: s(p["role"]), tagline: s(p["tagline"]),
                           bio: p["bio"] as? [String] ?? [], bigIdea: s(p["big_idea"]), startHere: link(p["start_here"]),
                           publishes: (p["publishes"] as? [Any] ?? []).compactMap(link),
                           sources: (j["sources"] as? [Any] ?? []).compactMap(link), photos: photos,
                           related: p["related"] as? [String] ?? [], checked: s(p["checked"]),
                           deeper: (j["deeper"] as? [[String: Any]] ?? []).compactMap { $0["title"] as? String })
    }

    /// "talk · 2025" for a source line.
    public static func meta(_ l: Link) -> String { [l.type, l.year.map(String.init) ?? ""].filter { !$0.isEmpty }.joined(separator: " · ") }
}
