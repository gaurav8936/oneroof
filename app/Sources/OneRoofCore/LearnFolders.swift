import Foundation

// LAB-1253 · Learn › All cards › By folder: the deck's skills folder exactly as it is packaged in this build
// (`<deck>/skills/<track>/<slug>/` with the card's page, SKILL.md, spec.json, video.yaml and its `<slug>_audio/`
// clips). Read from disk, nothing invented: the folder names and files are what is there; the WHAT IT IS, BAND and
// SIZE columns are looked up in the catalog (track plain name, card title, band, minutes) or counted on disk.

public struct DeckFolderEntry: Equatable, Sendable, Identifiable {
    public enum Kind: String, Equatable, Sendable {
        /// `<skills>/<track>/`
        case track
        /// `<skills>/<track>/<slug>/`
        case skill
        /// `<slug>_audio/` (and any folder below it)
        case audio
        /// Any other folder.
        case folder
        /// `<slug>.html`, the card page.
        case card
        /// `SKILL.md`
        case skillFile
        /// `spec.json`
        case spec
        /// `video.yaml`
        case video
        /// `README.md` (and other Markdown)
        case readme
        /// A narration clip under an audio folder.
        case clip
        /// Anything else.
        case file
    }

    /// The path relative to the deck root ("skills/doctrine/approval-gate/SKILL.md"); also the row's identity.
    public var id: String
    public var name: String
    public var path: String
    public var isDir: Bool
    public var kind: Kind
    /// 0 for a track folder or a file at the skills root.
    public var depth: Int
    /// WHAT IT IS.
    public var what: String
    /// BAND (band id), for track folders.
    public var band: String?
    /// SIZE ("18 skills", "2 min", "5 clips"), or "".
    public var size: String
    /// The track the entry is in, if any.
    public var track: String?
    /// The card the entry belongs to (a skill folder and everything in it), if any.
    public var slug: String?

    /// True for files whose text can be read in the panel.
    public var readable: Bool { [.skillFile, .spec, .video, .readme].contains(kind) || (kind == .file && DeckFolders.textExtensions.contains((name as NSString).pathExtension.lowercased())) }
}

public enum DeckFolders {
    static let audioExtensions: Set<String> = ["mp3", "m4a", "wav", "aac", "ogg", "aiff", "caf"]
    static let textExtensions: Set<String> = ["md", "json", "yaml", "yml", "txt", "toml"]

    /// The skills folder relative to the deck root, from the catalog's own paths ("skills/comms/x/SKILL.md" → "skills").
    public static func skillsDir(_ deck: LearnDeck) -> String {
        let firsts = deck.cards.values.compactMap { c -> String? in
            let p = c.skill.isEmpty ? c.html : c.skill
            return p.split(separator: "/").first.map(String.init)
        }
        // The most common first component (all of them, in a well-formed deck).
        let counts = Dictionary(firsts.map { ($0, 1) }, uniquingKeysWith: +)
        return counts.max { $0.value < $1.value || ($0.value == $1.value && $0.key > $1.key) }?.key ?? "skills"
    }

    /// The tree's root label ("skills/"): the folder's own name on disk.
    public static func rootLabel(_ deck: LearnDeck) -> String { skillsDir(deck) + "/" }

    /// The band a track sits on, if any.
    public static func band(ofTrack track: String) -> DeckBand? { LearnDeck.bands.first { $0.tracks.contains(track) } }

    /// The entries directly inside `rel` (a path relative to the deck root; the skills folder itself when nil):
    /// folders first, then files, each in Finder order. Hidden files are left out.
    public static func children(of rel: String? = nil, in deck: LearnDeck, fm: FileManager = .default) -> [DeckFolderEntry] {
        let skills = skillsDir(deck)
        let dir = rel ?? skills
        let abs = deck.root + "/" + dir
        guard let names = try? fm.contentsOfDirectory(atPath: abs) else { return [] }
        // Where `dir` sits: skills/<track>/<slug>/...
        let parts = dir.split(separator: "/").map(String.init)
        let below = Array(parts.dropFirst(skills.split(separator: "/").count))
        let depth = below.count
        let track = below.first
        let slug = below.count >= 2 ? below[1] : nil
        let inAudio = below.count >= 3 && below[2].hasSuffix("_audio")
        var dirs: [DeckFolderEntry] = [], files: [DeckFolderEntry] = []
        for n in names where !n.hasPrefix(".") {
            let path = abs + "/" + n
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: path, isDirectory: &isDir) else { continue }
            let id = dir + "/" + n
            var e = DeckFolderEntry(id: id, name: n, path: path, isDir: isDir.boolValue, kind: isDir.boolValue ? .folder : .file, depth: depth,
                                    what: "", band: nil, size: "", track: track, slug: slug)
            if isDir.boolValue {
                switch depth {
                case 0:
                    e.kind = .track; e.track = n
                    e.what = LearnDeck.trackNames[n]?.name ?? LearnDeck.label(n)
                    e.band = band(ofTrack: n)?.id
                    let k = skillFolders(path, fm: fm)
                    e.size = "\(k) skill" + (k == 1 ? "" : "s")
                case 1:
                    e.kind = .skill; e.slug = n
                    e.what = deck.cards[n]?.title ?? LearnDeck.label(n)
                    e.size = deck.cards[n].map { LearnDeck.minutes($0.estSeconds) } ?? ""
                default:
                    if inAudio || n.hasSuffix("_audio") {
                        e.kind = .audio
                        e.what = inAudio ? "Voice · " + n : "Narration"
                        let c = clips(path, fm: fm)
                        e.size = "\(c) clip" + (c == 1 ? "" : "s")
                    }
                }
                dirs.append(e)
            } else {
                let ext = (n as NSString).pathExtension.lowercased()
                if inAudio, audioExtensions.contains(ext) {
                    e.kind = .clip; e.what = "Narration clip"
                } else if n == "SKILL.md" {
                    e.kind = .skillFile; e.what = "Skill definition"
                } else if n == "spec.json" {
                    e.kind = .spec; e.what = "Scenes and narration"
                } else if n == "video.yaml" {
                    e.kind = .video; e.what = "Video render"
                } else if ext == "html", let slug, n == slug + ".html" {
                    e.kind = .card; e.what = "The card"
                } else if ext == "md" {
                    e.kind = .readme
                    e.what = n == "README.md" && depth == 0 ? "The index of every folder" : n == "README.md" ? "Read me" : ""
                }
                files.append(e)
            }
        }
        let order: (DeckFolderEntry, DeckFolderEntry) -> Bool = { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        return dirs.sorted(by: order) + files.sorted(by: order)
    }

    /// The visible rows: the skills folder's entries, and below each expanded folder its own, depth first.
    public static func rows(in deck: LearnDeck, expanded: Set<String>, fm: FileManager = .default) -> [DeckFolderEntry] {
        var out: [DeckFolderEntry] = []
        func walk(_ rel: String?) {
            for e in children(of: rel, in: deck, fm: fm) {
                out.append(e)
                if e.isDir, expanded.contains(e.id), e.depth < 6 { walk(e.id) }
            }
        }
        walk(nil)
        return out
    }

    /// The catalog cards in a track folder, in the folder's order on disk (skill folders the catalog lacks are left out).
    public static func cards(inTrack track: String, deck: LearnDeck, fm: FileManager = .default) -> [String] {
        children(of: skillsDir(deck) + "/" + track, in: deck, fm: fm).filter { $0.kind == .skill }.compactMap(\.slug).filter { deck.cards[$0] != nil }
    }

    /// The entry for a path relative to the deck root (its parent is listed to describe it).
    public static func entry(_ id: String, in deck: LearnDeck, fm: FileManager = .default) -> DeckFolderEntry? {
        let parent = (id as NSString).deletingLastPathComponent
        let rel: String? = parent == skillsDir(deck) ? nil : parent
        return children(of: rel, in: deck, fm: fm).first { $0.id == id }
    }

    /// The folders above `id` ("skills/a/b/c" → "skills", "skills/a", "skills/a/b"), for expanding the tree down to it.
    public static func ancestors(of id: String) -> [String] {
        let parts = id.split(separator: "/").map(String.init)
        guard parts.count > 1 else { return [] }
        return (1..<parts.count).map { parts[0..<$0].joined(separator: "/") }
    }

    /// A file's text for the panel (at most `limit` bytes; nil for a folder or a file that is not UTF-8).
    public static func text(_ path: String, limit: Int = 200_000) -> String? {
        guard let h = FileHandle(forReadingAtPath: path) else { return nil }
        defer { try? h.close() }
        let d = (try? h.read(upToCount: limit)) ?? Data()
        guard var s = String(data: d, encoding: .utf8) else { return nil }
        if d.count == limit { s += "\n…" }
        return s
    }

    private static func skillFolders(_ path: String, fm: FileManager) -> Int {
        ((try? fm.contentsOfDirectory(atPath: path)) ?? []).filter { n in
            var d: ObjCBool = false
            return !n.hasPrefix(".") && fm.fileExists(atPath: path + "/" + n, isDirectory: &d) && d.boolValue
        }.count
    }

    /// Audio files anywhere below `path`.
    static func clips(_ path: String, fm: FileManager) -> Int {
        guard let e = fm.enumerator(atPath: path) else { return 0 }
        var n = 0
        for case let rel as String in e where audioExtensions.contains((rel as NSString).pathExtension.lowercased()) { n += 1 }
        return n
    }
}

// MARK: Radio home routing (LAB-1247)

/// What a click on Radio home does. The owner (LAB-1247): the home page is the navigation, so a band key and an
/// "On this band" chip open the band page (the chip at its track) and never start playback; only the play controls
/// (▶ key, a line on the dial, a programme's Play, a card's ▶) play.
public enum LearnRadioRoute: Equatable, Sendable {
    /// Show the band page, scrolled to `track` when given.
    case openBand(String, track: String?)
    /// Tune to `slug` and play it with the rest of its band after it.
    case play(String)

    public static func bandKey(_ band: String) -> LearnRadioRoute { .openBand(band, track: nil) }
    public static func chip(band: String, track: String) -> LearnRadioRoute { .openBand(band, track: track) }
    public static func dial(_ slug: String) -> LearnRadioRoute { .play(slug) }

    /// The band page's scroll target for a track group.
    public static func anchor(track: String) -> String { "track:" + track }
}
