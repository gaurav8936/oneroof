import Foundation

/// LAB-1274 · 1.9.2: Learn in the v2 window is three views, Radio · Writing · All cards (owner, 2026-10-26). There is no
/// Pages list any more, so every way into Learn that used to open a page (a link, Search, the Plan panel, Foundations ›
/// Skills, the player's title, the mini player) lands on what the three views show: a card's station, a band, Radio, or
/// One Roof's Help page. Pure logic, tested in `LearnRouteTests`.
public enum LearnTargetRoute: Equatable, Sendable {
    /// A deck card's station.
    case card(String)
    /// A band page, scrolled to `track` when given (a field-manual track page).
    case band(String, track: String?)
    /// Radio home (the field manual's home page).
    case radio
    /// A One Roof Help page: the window's Help page (B4.1), open at that page.
    case help(String)
    /// Nothing in the three views shows it (an extra-folder page; the course is gone). Learn stays where it is.
    case none
}

public extension LearnDeck {
    /// Where a Learn target (a page path, as `AppModel.learnTarget` carries it) opens in the v2 window.
    func route(_ target: String, helpFolder: String?) -> LearnTargetRoute {
        if let slug = slug(forPage: target) { return .card(slug) }
        let name = ((target as NSString).lastPathComponent as NSString).deletingPathExtension
        let parent = ((target as NSString).deletingLastPathComponent as NSString).lastPathComponent
        // A skill's page or SKILL.md read from another copy of the deck (Foundations › Skills, the palette's skills).
        if target.hasSuffix(".html"), cards[name] != nil { return .card(name) }
        if (target as NSString).lastPathComponent == "SKILL.md", cards[parent] != nil { return .card(parent) }
        if let help = helpFolder, !help.isEmpty, target.hasPrefix(help.hasSuffix("/") ? help : help + "/") { return .help(target) }
        // The field manual: home → Radio; a track page → the band that plays that track, at the track.
        if target.contains("/content/field-manual/") {
            if let b = bands.first(where: { $0.tracks.contains(name) }) { return .band(b.id, track: name) }
            return .radio
        }
        return .none
    }

    /// "How do I…": the cards that best answer `question`, best first. Ranked by `LearnMatch` over each card's title,
    /// subtitle, description, triggers and track; cards that contain every word (`search`) follow.
    func bestCards(for question: String, limit: Int = 8) -> [String] {
        let docs = dial.compactMap { k -> LearnMatch.Doc? in
            guard let c = cards[k] else { return nil }
            let track = trackNames[c.track].map { $0.name + " " + $0.question } ?? c.track
            return LearnMatch.Doc(id: k, title: c.title + " " + k.replacingOccurrences(of: "-", with: " "),
                                  text: ([c.subtitle, c.description, track] + c.triggers).joined(separator: " "))
        }
        var out = LearnMatch.rank(question, docs, limit: limit)
        for k in search(question) where out.count < limit && !out.contains(k) { out.append(k) }
        return out
    }
}

/// LAB-1272 · a band page's dial names each track under its first card. A track with one or two cards left its name
/// under the next one ("FOUNDATIONS" over "VAULT" on Context). Each label now gets its own text width: it goes on the first
/// row when that row is free from its left edge to its end, else on a second row (staggered), else it is shortened with
/// "…" to the room left before the dial's end, or hidden when less than `minWidth` is left. The full name is the tooltip.
public enum DialLabels {
    public struct Placed: Equatable, Sendable {
        /// 0 = first row, 1 = second row.
        public var row: Int
        /// The width the label takes; 0 = hidden.
        public var width: Double
        /// The label's full text width.
        public var full: Double
        public var hidden: Bool { width <= 0 }
        public var truncated: Bool { width > 0 && width < full }
    }

    /// `labels`: each label's left edge and full text width, in order along the dial. `total`: the dial's width.
    /// `gap`: the space kept between two labels on a row.
    public static func place(_ labels: [(x: Double, width: Double)], total: Double, gap: Double = 6, minWidth: Double = 24) -> [Placed] {
        var end = [-Double.infinity, -Double.infinity]   // where each row's last label ends
        return labels.map { l in
            let free = (0..<2).filter { l.x >= end[$0] + gap }
            if let r = free.first(where: { _ in l.x + l.width <= total }) {
                end[r] = l.x + l.width
                return Placed(row: r, width: l.width, full: l.width)
            }
            // Too long for the room left before the dial's end: shorten it on the first free row.
            if let r = free.first, total - l.x >= minWidth {
                end[r] = total
                return Placed(row: r, width: total - l.x, full: l.width)
            }
            return Placed(row: 0, width: 0, full: l.width)
        }
    }
}
