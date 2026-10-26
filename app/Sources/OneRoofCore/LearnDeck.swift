import Foundation

// LAB-1233 · Learn Radio (handover A12.2): the Agentic Engineering deck as read from the bundled `content/catalog.json`,
// arranged on the four bands of the dial (Context · Loops · Evidence · Procedure) the way the Learn prototype draws them.
// Everything here is read where it lives; nothing is copied or made up. The band names, their one-line definitions,
// their "start here" cards and the plain track names are the design's editorial layer over the catalog (the catalog has
// suits and tracks, not bands); a card the catalog does not have is simply left out.

public struct DeckCard: Equatable, Sendable {
    public struct Section: Equatable, Sendable { public var title: String; public var scenes: Int }
    public var slug: String
    public var track: String
    public var title: String
    public var subtitle: String
    public var description: String
    public var triggers: [String]
    /// Paths relative to the deck root.
    public var skill: String
    public var spec: String
    public var html: String
    public var sections: [Section]
    public var scenes: Int
    public var estSeconds: Int
}

public struct DeckTrack: Equatable, Sendable { public var id: String; public var suit: String; public var intro: String; public var cards: [String] }
public struct DeckSuit: Equatable, Sendable { public var id: String; public var symbol: String; public var label: String; public var tracks: [String] }
public struct DeckPath: Equatable, Sendable { public var id: String; public var title: String; public var tag: String; public var why: String; public var slugs: [String] }

/// One band of the dial.
public struct DeckBand: Equatable, Sendable, Identifiable {
    public var id: String
    public var n: String
    public var zone: String
    public var title: String
    public var sub: String
    public var def: String
    public var tracks: [String]
    /// The four cards to hear first.
    public var key: [String]
    /// Posts (by slug) that belong to this band, when a Learn folder has them.
    public var posts: [String]
}

public struct LearnDeck: Sendable {
    public var root: String
    public var version: String
    public var cards: [String: DeckCard]
    public var tracks: [String: DeckTrack]
    public var suits: [DeckSuit]
    public var paths: [DeckPath]
    /// slug → band id.
    public var partOf: [String: String]
    /// band id → its cards in dial order (start-here cards first, then the band's tracks in catalog order).
    public var lists: [String: [String]]
    /// Every card on the dial, band by band.
    public var dial: [String]

    public var count: Int { cards.count }

    // MARK: The design's bands (One Roof Learn.dc.html, PARTS / TI / KINDS)

    public static let bands: [DeckBand] = [
        DeckBand(id: "context", n: "01", zone: "BEFORE THE WORK", title: "Context", sub: "What the agent knows at the first prompt",
                 def: "Every session starts cold. What it knows is whatever it loaded: instruction files, notes, the last handoff. Context is a structure on disk, designed once and then enforced.",
                 tracks: ["foundations", "vault", "influences"], key: ["context-as-structure", "knowledge-notes", "docs-phonebook", "the-2x2-map"],
                 posts: ["agentic-engineering", "one-workspace"]),
        DeckBand(id: "loops", n: "02", zone: "BEFORE THE WORK", title: "Loops", sub: "A unit of work with a stop condition",
                 def: "Hand the agent a loop, not a task: a goal written as an end state, a check that runs without a person, and a condition that says stop, whether or not it succeeded.",
                 tracks: ["rhythms", "pipeline", "model-craft", "modality"], key: ["loops-first", "done-when", "feedback-loop", "orchestration"],
                 posts: ["loops-with-a-stop-condition", "one-roof-builds-one-roof"]),
        DeckBand(id: "evidence", n: "03", zone: "AFTER THE WORK", title: "Evidence", sub: "Proof the unit is done",
                 def: "Agents report success in the same fluent voice whether or not they succeeded. Separate the claim from the proof, and put the proof where the agent can't write it.",
                 tracks: ["ship", "debug", "safety"], key: ["evidence-check", "test-first", "smoke-prod", "audit-trail"],
                 posts: ["evidence-not-confidence", "one-roof-builds-one-roof"]),
        DeckBand(id: "procedure", n: "04", zone: "AFTER THE WORK", title: "Procedure", sub: "What the next session inherits",
                 def: "A lesson that lives in one session dies with it. Written as a skill, it reaches every agent at its next start; narrated as a card, it teaches a person the same thing.",
                 tracks: ["doctrine", "comms", "infra", "play"], key: ["compounding-instincts", "gotcha-log", "decision-record", "spawn-doctrine"],
                 posts: ["one-library-every-agent"]),
    ]

    /// Plain names and the question each track answers (handover GAPS D6: the catalog does not carry them yet).
    public static let trackNames: [String: (name: String, question: String)] = [
        "foundations": ("Big ideas", "What makes agentic engineering different?"),
        "vault": ("Notes & memory", "Where does what we know live?"),
        "influences": ("People worth hearing", "Whose thinking is this built on?"),
        "rhythms": ("Daily loops", "What runs every session and every night?"),
        "pipeline": ("Ticket to merged PR", "How does work move from idea to code?"),
        "model-craft": ("Working with models", "How do I get more out of the model itself?"),
        "modality": ("Beyond text", "Voice, vision, documents, computer use."),
        "ship": ("Shipping", "How do I know it is live, and right?"),
        "debug": ("Debugging", "Something's wrong. Where?"),
        "safety": ("Guardrails", "What stops an agent doing damage?"),
        "doctrine": ("How we work", "The rules a team of agents follows."),
        "comms": ("Messages & channels", "How agents talk to people."),
        "infra": ("Dev environment", "Repos, git, worktrees, planning."),
        "play": ("Walkthroughs", "Low-stakes animated tours. No grading."),
    ]

    /// All cards › By kind.
    public static let kinds: [(title: String, sub: String, tracks: [String])] = [
        ("Ideas & rules", "The thinking, and the rules that follow from it", ["foundations", "doctrine"]),
        ("Skills agents run", "Procedures you can hand to an agent today", ["rhythms", "pipeline", "ship", "debug", "safety", "model-craft", "modality", "comms", "vault", "infra"]),
        ("People", "The voices the ideas come from", ["influences"]),
        ("Walkthroughs", "Tours, for fun", ["play"]),
    ]

    // MARK: Loading

    public static func load(deck: String?) -> LearnDeck? {
        guard let deck, let d = FileManager.default.contents(atPath: deck + "/content/catalog.json") else { return nil }
        return parse(d, root: deck)
    }

    public static func parse(_ data: Data, root: String) -> LearnDeck? {
        guard let j = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        func strs(_ v: Any?) -> [String] { v as? [String] ?? [] }
        var cards: [String: DeckCard] = [:]
        for c in j["cards"] as? [[String: Any]] ?? [] {
            guard let slug = c["slug"] as? String else { continue }
            let secs = (c["sections"] as? [[String: Any]] ?? []).map { DeckCard.Section(title: $0["title"] as? String ?? "", scenes: $0["scenes"] as? Int ?? 0) }
            cards[slug] = DeckCard(slug: slug, track: c["track"] as? String ?? "", title: (c["title"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? label(slug),
                                   subtitle: c["subtitle"] as? String ?? "", description: c["description"] as? String ?? "",
                                   triggers: strs(c["triggers"]), skill: c["skill"] as? String ?? "", spec: c["spec"] as? String ?? "",
                                   html: c["html"] as? String ?? "", sections: secs, scenes: c["scenes"] as? Int ?? secs.reduce(0) { $0 + $1.scenes },
                                   estSeconds: c["est_seconds"] as? Int ?? 0)
        }
        var tracks: [String: DeckTrack] = [:]
        for t in j["tracks"] as? [[String: Any]] ?? [] {
            guard let id = t["id"] as? String else { continue }
            tracks[id] = DeckTrack(id: id, suit: t["suit"] as? String ?? "", intro: t["intro"] as? String ?? "", cards: strs(t["cards"]))
        }
        let suits = (j["suits"] as? [[String: Any]] ?? []).compactMap { s -> DeckSuit? in
            guard let id = s["id"] as? String else { return nil }
            return DeckSuit(id: id, symbol: s["symbol"] as? String ?? "", label: s["label"] as? String ?? id, tracks: strs(s["tracks"]))
        }
        let paths = (j["paths"] as? [[String: Any]] ?? []).compactMap { p -> DeckPath? in
            guard let id = p["id"] as? String else { return nil }
            return DeckPath(id: id, title: p["title"] as? String ?? id, tag: p["tag"] as? String ?? "", why: p["why"] as? String ?? "", slugs: strs(p["slugs"]))
        }
        guard !cards.isEmpty else { return nil }
        // Bands: a track's cards belong to its band; a band's start-here cards belong to it whatever their track.
        var partOf: [String: String] = [:]
        for b in bands { for t in b.tracks { for k in tracks[t]?.cards ?? [] { partOf[k] = b.id } } }
        for b in bands { for k in b.key { partOf[k] = b.id } }
        let order = suits.flatMap(\.tracks).flatMap { tracks[$0]?.cards ?? [] }.filter { cards[$0] != nil }
        var lists: [String: [String]] = [:]
        for b in bands {
            let key = b.key.filter { cards[$0] != nil }
            var seen = Set(key)
            lists[b.id] = key + order.filter { partOf[$0] == b.id && seen.insert($0).inserted }
        }
        let dial = bands.flatMap { lists[$0.id] ?? [] }
        return LearnDeck(root: root, version: j["version"] as? String ?? "", cards: cards, tracks: tracks, suits: suits, paths: paths,
                         partOf: partOf, lists: lists, dial: dial)
    }

    // MARK: Lookups

    public func band(of slug: String) -> DeckBand { Self.bands.first { $0.id == partOf[slug] } ?? Self.bands[1] }
    public func band(id: String) -> DeckBand { Self.bands.first { $0.id == id } ?? Self.bands[1] }
    public func htmlPath(_ slug: String) -> String { root + "/" + (cards[slug]?.html ?? "") }
    public func specPath(_ slug: String) -> String { root + "/" + (cards[slug]?.spec ?? "") }
    public func skillPath(_ slug: String) -> String { root + "/" + (cards[slug]?.skill ?? "") }

    /// The card whose page is `htmlPath` (the player's page id), if it is one of this deck's.
    public func slug(forPage htmlPath: String) -> String? {
        let slug = ((htmlPath as NSString).lastPathComponent as NSString).deletingPathExtension
        guard let c = cards[slug], htmlPath == root + "/" + c.html else { return nil }
        return slug
    }

    /// Cards matching every word of `query` in title, subtitle, description, slug or triggers, in dial order.
    public func search(_ query: String) -> [String] {
        let words = query.lowercased().split(whereSeparator: { $0.isWhitespace }).map(String.init)
        guard !words.isEmpty else { return [] }
        return dial.filter { k in
            guard let c = cards[k] else { return false }
            let hay = ([c.title, c.subtitle, c.description, c.slug] + c.triggers).joined(separator: " ").lowercased()
            return words.allSatisfy { hay.contains($0) }
        }
    }

    // MARK: Formatting

    /// "model-craft" → "Model craft".
    public static func label(_ s: String) -> String {
        let t = s.replacingOccurrences(of: "-", with: " ")
        return t.prefix(1).uppercased() + t.dropFirst()
    }
    /// "6 min" (at least 1).
    public static func minutes(_ seconds: Int) -> String { "\(max(1, Int((Double(seconds) / 60).rounded()))) min" }
    public static func clock(_ seconds: Double) -> String {
        let s = max(0, seconds.isFinite ? Int(seconds) : 0)
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}

// MARK: Card scenes (spec.json)

public struct DeckScene: Equatable, Sendable {
    public struct Node: Equatable, Sendable { public var id: String; public var title: String; public var sub: String }
    public var sectionIndex: Int
    public var section: String
    public var kicker: String
    public var heading: String
    public var lede: String
    public var points: [String]
    /// Ids of the section diagram's nodes this scene lights up.
    public var highlight: [String]
    public var narration: String
    /// The section's diagram nodes (empty when the section has none).
    public var nodes: [Node]
}

public enum DeckSpec {
    /// Every scene of a card's spec.json in order. Without the file, one placeholder scene per catalog scene, titled
    /// by its section, so chapters and the scene count still line up.
    public static func scenes(path: String, fallback: DeckCard? = nil) -> [DeckScene] {
        if let d = FileManager.default.contents(atPath: path),
           let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
           let sections = j["sections"] as? [[String: Any]] {
            var out: [DeckScene] = []
            for (si, sec) in sections.enumerated() {
                let title = clean(sec["title"] as? String ?? "")
                let nodes = ((sec["diagram"] as? [String: Any])?["nodes"] as? [[String: Any]] ?? []).compactMap { n -> DeckScene.Node? in
                    guard let id = n["id"] as? String else { return nil }
                    return .init(id: id, title: clean(n["title"] as? String ?? ""), sub: clean(n["sub"] as? String ?? ""))
                }
                for sc in sec["scenes"] as? [[String: Any]] ?? [] {
                    out.append(DeckScene(sectionIndex: si, section: title, kicker: clean(sc["kicker"] as? String ?? ""),
                                         heading: clean(sc["heading"] as? String ?? ""), lede: clean(sc["lede"] as? String ?? ""),
                                         points: (sc["points"] as? [Any] ?? []).compactMap { ($0 as? String).map(clean) },
                                         highlight: sc["highlight"] as? [String] ?? [], narration: sc["narration"] as? String ?? "", nodes: nodes))
                }
            }
            if !out.isEmpty { return out }
        }
        guard let c = fallback else { return [] }
        return c.sections.enumerated().flatMap { si, s in
            (0..<max(0, s.scenes)).map { _ in DeckScene(sectionIndex: si, section: s.title, kicker: s.title, heading: s.title, lede: "", points: [],
                                                        highlight: [], narration: "", nodes: []) }
        }
    }

    /// Emoji and doubled spaces removed (the deck's headings carry track emoji; the design draws none).
    public static func clean(_ s: String) -> String {
        let kept = s.unicodeScalars.filter { u in
            !(u.properties.isEmojiPresentation || (0x1F000...0x1FAFF).contains(u.value) || (0x2600...0x27BF).contains(u.value) || u.value == 0xFE0F)
        }
        return String(String.UnicodeScalarView(kept)).split(whereSeparator: { $0 == " " }).joined(separator: " ").trimmingCharacters(in: .whitespaces)
    }
}

// MARK: Skill file (SKILL.md)

public struct DeckSkill: Equatable, Sendable {
    public struct Field: Equatable, Sendable { public var key: String; public var value: String }
    /// Top-level frontmatter fields (lists joined with ", "; `metadata` left out).
    public var front: [Field]
    /// The Markdown after the frontmatter.
    public var body: String
    /// `dependencies:` entries.
    public var dependencies: [String]

    public static func load(_ path: String) -> DeckSkill? {
        guard let text = try? String(contentsOfFile: path, encoding: .utf8) else { return nil }
        return parse(text)
    }

    public static func parse(_ text: String) -> DeckSkill {
        let t = text.replacingOccurrences(of: "\r\n", with: "\n")
        var lines = t.components(separatedBy: "\n")
        guard lines.first == "---", let end = lines.dropFirst().firstIndex(of: "---") else { return DeckSkill(front: [], body: t, dependencies: []) }
        let fm = Array(lines[1..<end])
        lines = Array(lines[(end + 1)...])
        var front: [Field] = [], deps: [String] = []
        var i = 0
        while i < fm.count {
            let l = fm[i]
            guard let c = l.firstIndex(of: ":"), !l.hasPrefix(" "), !l.hasPrefix("-") else { i += 1; continue }
            let key = String(l[..<c]).trimmingCharacters(in: .whitespaces)
            var value = String(l[l.index(after: c)...]).trimmingCharacters(in: .whitespaces)
            var list: [String] = []
            var j = i + 1
            while j < fm.count, fm[j].hasPrefix(" ") || fm[j].hasPrefix("-") {
                let item = fm[j].trimmingCharacters(in: .whitespaces)
                if item.hasPrefix("- ") { list.append(String(item.dropFirst(2))) }
                j += 1
            }
            if value.isEmpty { value = list.joined(separator: ", ") }
            if value.hasPrefix("[") && value.hasSuffix("]") {
                list = value.dropFirst().dropLast().split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            }
            if key == "dependencies" { deps = list }
            value = value.trimmingCharacters(in: CharacterSet(charactersIn: "'\""))
            if key != "metadata" { front.append(Field(key: key, value: value.isEmpty ? "…" : value)) }
            i = j
        }
        return DeckSkill(front: front, body: lines.joined(separator: "\n").trimmingCharacters(in: .newlines), dependencies: deps)
    }
}

// MARK: Writing (posts found in Learn folders)

/// A post: a `<folder>/index.md` with a title and a date in its frontmatter, found in one of the owner's Learn folders
/// (the app ships no posts of its own).
public struct LearnPost: Equatable, Sendable, Identifiable {
    public var id: String { slug }
    public var slug: String
    public var file: String
    public var title: String
    public var subtitle: String
    public var summary: String
    public var date: String
    public var status: String
    public var series: String
    public var tags: [String]
    public var minutes: Int
    /// The post's `## ` headings, for "In this post".
    public var sections: [String]
    public var published: Bool { status == "published" }
}

public enum LearnPosts {
    public static func scan(_ folders: [String]) -> [LearnPost] {
        let fm = FileManager.default
        var out: [LearnPost] = [], seen = Set<String>()
        for folder in folders {
            let root = ((folder as NSString).expandingTildeInPath as NSString).standardizingPath
            guard let e = fm.enumerator(atPath: root) else { continue }
            for case let rel as String in e {
                let parts = rel.split(separator: "/")
                if parts.contains(where: { $0 == "node_modules" || $0.hasPrefix(".") }) { e.skipDescendants(); continue }
                if parts.count > 4 { e.skipDescendants(); continue }
                guard (rel as NSString).lastPathComponent == "index.md", parts.count >= 2,
                      let p = post(root + "/" + rel), seen.insert(p.slug).inserted else { continue }
                out.append(p)
            }
        }
        return out.sorted { $0.date < $1.date }
    }

    public static func post(_ file: String) -> LearnPost? {
        guard let text = try? String(contentsOfFile: file, encoding: .utf8) else { return nil }
        let meta = Foundations.frontmatter(text)
        guard let title = meta["title"], !title.isEmpty, let date = meta["date"], date.count >= 10 else { return nil }
        let folder = ((file as NSString).deletingLastPathComponent as NSString).lastPathComponent
        // "20261024_loops-with-a-stop-condition" → "loops-with-a-stop-condition"
        var slug = folder
        if let u = folder.firstIndex(of: "_"), folder[..<u].allSatisfy(\.isNumber) { slug = String(folder[folder.index(after: u)...]) }
        let body = MarkdownDoc.stripFrontmatter(text)
        let words = body.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count
        let heads = body.components(separatedBy: "\n").filter { $0.hasPrefix("## ") }.map { String($0.dropFirst(3)) }.filter { $0 != "Links" }
        let tags = (meta["tags"] ?? "").trimmingCharacters(in: CharacterSet(charactersIn: "[]")).split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        return LearnPost(slug: slug, file: file, title: title, subtitle: meta["subtitle"] ?? "", summary: meta["summary"] ?? "",
                         date: String(date.prefix(10)), status: meta["status"] ?? "", series: meta["series"] ?? "", tags: tags,
                         minutes: max(1, Int((Double(words) / 230).rounded())), sections: heads)
    }

    /// AIRED · NEXT · n DAYS · SCHEDULED, as the broadcast schedule labels a post on `today` (yyyy-MM-dd).
    public static func state(_ p: LearnPost, in all: [LearnPost], today: String) -> (label: String, isNext: Bool) {
        if p.published { return ("AIRED", false) }
        let next = all.sorted { $0.date < $1.date }.first { $0.date >= today && !$0.published }
        if next?.slug == p.slug, let a = day(today), let b = day(p.date) {
            return ("NEXT · \(Int((b.timeIntervalSince(a) / 86_400).rounded())) DAYS", true)
        }
        return ("SCHEDULED", false)
    }

    public static func day(_ s: String) -> Date? {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX"); f.timeZone = TimeZone(identifier: "UTC"); f.dateFormat = "yyyy-MM-dd"
        return f.date(from: String(s.prefix(10)))
    }
}
