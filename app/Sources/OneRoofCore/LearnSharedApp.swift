import Foundation

// LAB-1893 · what One Roof's native Learn screens knew that the shared page (the hub's saved copy, LearnShared) does not: the
// owner's posts (the hub's, refreshed while the app runs, plus their own post folders) and a post's text for the in-page
// reader, the deck folder as it is on disk with file previews, One Roof's own "How do I…" ranking, and its player's state.
// The host page's bridge (LearnShared.hostPage) asks for them at `oneroof-learn://hub/app/…`, answered here from a snapshot the
// app keeps current (`LearnSharedApp`); the player's state is pushed to the page as a `player` event (`nowPlaying`).
//
//   /app/search?q=<text>        {"cards": [slug, …]}: every word in a card, else the best matches (One Roof's All cards search)
//   /app/posts                  {"posts": [...], "note": "From the … blog · updated 10:42 · plus your Learn folders", "offline": false}
//   /app/post/<slug>            {"slug", "markdown", "canonical", "status", "sections", "base"} (base: /app/post-file/<slug>)
//   /app/post-file/<slug>/<f>   a file next to the post (its images)
//   /app/folder?path=<rel>      {"entries": [{"name", "path", "dir", "size", "kind"}, …]}: the deck folder on disk
//   /app/file?path=<rel>        {"text", "cut", "markdown"}: a deck file's first 400 lines (415 when it is not text)
public struct LearnSharedApp: Sendable {
    public var deck: LearnDeck?
    /// The bundled deck's root (LearnShared.Location.deck).
    public var deckRoot: String
    /// Nil until the app has read them (the page then shows "Loading…" and asks again on the `posts` event).
    public var posts: [LearnPost]?
    public var postsNote: String
    public var postsOffline: Bool

    public init(deck: LearnDeck?, deckRoot: String, posts: [LearnPost]? = nil, postsNote: String = "", postsOffline: Bool = false) {
        self.deck = deck; self.deckRoot = deckRoot; self.posts = posts; self.postsNote = postsNote; self.postsOffline = postsOffline
    }

    public static let prefix = "/app/"

    /// The answer for an `/app/…` path (nil: not one of these, LearnShared.respond answers it).
    public func respond(path: String, query: String?) -> LearnShared.Response? {
        guard path.hasPrefix(Self.prefix) else { return nil }
        let q = Self.params(query)
        let rest = String(path.dropFirst(Self.prefix.count))
        switch rest {
        case "search": return LearnShared.json(200, ["cards": search(q["q"] ?? "")])
        case "posts":
            let list: Any = posts.map { $0.map(Self.postJSON) } ?? NSNull()
            return LearnShared.json(200, ["posts": list, "note": postsNote, "offline": postsOffline])
        case "folder":
            guard let rel = q["path"], let entries = folder(rel) else { return LearnShared.notFound }
            return LearnShared.json(200, ["entries": entries])
        case "file":
            guard let rel = q["path"] else { return LearnShared.notFound }
            guard let full = LearnShared.inside(deckRoot, rel) else { return LearnShared.notFound }
            guard let f = Self.fileText(full) else { return LearnShared.json(415, ["error": "not text"]) }
            return LearnShared.json(200, ["text": f.text, "cut": f.cut, "markdown": (full as NSString).pathExtension.lowercased() == "md"])
        default: break
        }
        if rest.hasPrefix("post/") {
            let slug = String(rest.dropFirst(5))
            guard LearnShared.isSlug(slug), let p = posts?.first(where: { $0.slug == slug }), !p.file.isEmpty,
                  let text = try? String(contentsOfFile: p.file, encoding: .utf8) else { return LearnShared.json(404, ["error": "no text for this post"]) }
            return LearnShared.json(200, ["slug": slug, "markdown": MarkdownDoc.stripFrontmatter(text), "canonical": p.canonical,
                                          "status": p.status, "sections": p.sections, "base": "\(LearnShared.origin)/app/post-file/\(slug)"])
        }
        if rest.hasPrefix("post-file/") {
            let parts = rest.dropFirst(10).split(separator: "/", maxSplits: 1).map(String.init)
            guard parts.count == 2, LearnShared.isSlug(parts[0]), let p = posts?.first(where: { $0.slug == parts[0] }), !p.file.isEmpty,
                  let f = LearnShared.inside((p.file as NSString).deletingLastPathComponent, parts[1]) else { return LearnShared.notFound }
            return LearnShared.file(f, range: nil)
        }
        return LearnShared.notFound
    }

    // MARK: Search (One Roof's All cards › How do I…)

    /// Every word in a card (in dial order); when no card has them all, the best matches (`bestCards`, 12).
    public func search(_ q: String) -> [String] {
        let query = q.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let deck, !query.isEmpty else { return [] }
        let exact = deck.search(query)
        return exact.isEmpty ? deck.bestCards(for: query, limit: 12) : exact
    }

    // MARK: Posts

    static func postJSON(_ p: LearnPost) -> [String: Any] {
        ["slug": p.slug, "title": p.title, "subtitle": p.subtitle, "summary": p.summary, "date": p.date, "series": p.series,
         "minutes": p.minutes, "tags": p.tags, "status": p.status, "canonical": p.canonical, "local": p.source.isEmpty]
    }

    /// The posts Learn shows: the owner's post folders and the hub's cache (LearnPosts.all); when the cache holds none yet (never
    /// online on this Mac), the list saved in the app at build (`posts.json`) so Writing is never emptier than the shared page.
    public static func posts(folders: [String], hubCache: String?, saved: String?) -> [LearnPost] {
        var all = LearnPosts.all(folders: folders, hubCache: hubCache)
        guard !all.contains(where: { !$0.source.isEmpty }), let saved,
              let d = FileManager.default.contents(atPath: saved),
              let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any], let list = o["posts"] as? [[String: Any]] else { return all }
        let have = Set(all.map(\.slug))
        for x in list {
            guard let slug = x["slug"] as? String, !have.contains(slug), let title = x["title"] as? String, let date = x["date"] as? String else { continue }
            all.append(LearnPost(slug: slug, file: "", title: title, subtitle: x["subtitle"] as? String ?? "", summary: x["summary"] as? String ?? "",
                                 date: String(date.prefix(10)), status: x["status"] as? String ?? "published", series: x["series"] as? String ?? "",
                                 tags: x["tags"] as? [String] ?? [], minutes: x["minutes"] as? Int ?? 1, sections: [],
                                 canonical: x["canonical"] as? String ?? "", source: "saved"))
        }
        return all.sorted { $0.date < $1.date }
    }

    /// Whether the hub answered (Writing's "From the … blog" line).
    public enum Feed: Equatable, Sendable { case loading, reached, offline(String) }

    /// Writing's source line, as the native screen said it: "From the <site> blog · updated 10:42", "Offline · the copy saved
    /// <when>", "… · checking for new posts…", then " · plus your Learn folders"; no posts at all: loading / none / can't reach.
    public static func postsNote(_ posts: [LearnPost], feed: Feed, savedAt: String, blog: String) -> String {
        let hub = posts.contains { !$0.source.isEmpty }, local = posts.contains { $0.source.isEmpty }
        if !hub && !local {
            switch feed {
            case .loading: return "Loading posts from the \(blog)…"
            case .reached: return "The \(blog) has no posts yet."
            case .offline(let why): return "Can't reach the \(blog) (\(why)) and no copy is saved on this Mac yet. Posts show here once One Roof is online."
            }
        }
        var parts: [String] = []
        if hub {
            switch feed {
            case .offline: parts.append("Offline · the copy saved " + savedAt)
            case .loading: parts.append("From the \(blog) · checking for new posts…")
            case .reached: parts.append("From the \(blog) · updated " + savedAt)
            }
        }
        if local { parts.append("plus your Learn folders") }
        return parts.joined(separator: " · ")
    }

    // MARK: The deck folder on disk (One Roof's All cards › By folder)

    /// The entries directly in `rel` (a folder of the deck, from its root): folders first, then files, in Finder order; hidden
    /// ones left out. Nil when `rel` is not a folder inside the deck.
    public func folder(_ rel: String) -> [[String: Any]]? {
        let fm = FileManager.default
        let base = (deckRoot as NSString).standardizingPath
        let full = ((base as NSString).appendingPathComponent(rel) as NSString).standardizingPath
        var isDir: ObjCBool = false
        guard !rel.isEmpty, !rel.hasPrefix("/"), full.hasPrefix(base + "/"), fm.fileExists(atPath: full, isDirectory: &isDir), isDir.boolValue,
              let names = try? fm.contentsOfDirectory(atPath: full) else { return nil }
        let clean = String(full.dropFirst(base.count + 1))
        var dirs: [[String: Any]] = [], files: [[String: Any]] = []
        for n in names.sorted(by: { $0.localizedStandardCompare($1) == .orderedAscending }) where !n.hasPrefix(".") {
            let p = full + "/" + n
            var d: ObjCBool = false
            guard fm.fileExists(atPath: p, isDirectory: &d) else { continue }
            if d.boolValue {
                let clips = n.hasSuffix("_audio") ? DeckFolders.clips(p, fm: fm) : 0
                let count = ((try? fm.contentsOfDirectory(atPath: p)) ?? []).filter { !$0.hasPrefix(".") }.count
                dirs.append(["name": n, "path": clean + "/" + n, "dir": true, "kind": n.hasSuffix("_audio") ? "audio" : "folder",
                             "size": n.hasSuffix("_audio") ? "\(clips) clip" + (clips == 1 ? "" : "s") : "\(count) item" + (count == 1 ? "" : "s")])
            } else {
                let bytes = (try? fm.attributesOfItem(atPath: p)[.size] as? Int) ?? 0
                files.append(["name": n, "path": clean + "/" + n, "dir": false, "kind": "file", "size": Self.bytes(bytes)])
            }
        }
        return dirs + files
    }

    /// "812 B", "3 KB", "1.2 MB".
    public static func bytes(_ n: Int) -> String {
        if n < 1024 { return "\(n) B" }
        if n < 1024 * 1024 { return "\(Int((Double(n) / 1024).rounded())) KB" }
        return String(format: "%.1f MB", Double(n) / 1024 / 1024)
    }

    static let textExtensions: Set<String> = ["md", "json", "yaml", "yml", "txt", "toml", "html", "css", "js", "py", "sh", "swift", "csv"]

    /// A text file's first 400 lines (nil: not one of the text kinds, or not UTF-8).
    public static func fileText(_ path: String) -> (text: String, cut: Bool)? {
        guard textExtensions.contains((path as NSString).pathExtension.lowercased()), let t = DeckFolders.text(path) else { return nil }
        let p = CodeText.preview(t)
        return (p.text, p.cut || t.hasSuffix("\n…"))
    }

    // MARK: The player (pushed to the page)

    /// The page's `player` event: what One Roof's player has loaded (`slug` "" = nothing), the scene and how many, the time into
    /// the card (earlier scenes at the card's estimate per scene, plus the clip being heard, as Radio's native display counted it),
    /// the card's length and the speed.
    public static func nowPlaying(slug: String?, playing: Bool, index: Int, count: Int, clipElapsed: Double, total: Int, rate: Float,
                                  kicker: String?) -> [String: Any] {
        guard let slug else { return ["slug": "", "playing": false, "index": 0, "count": 0, "elapsed": 0, "total": 0, "rate": Double(rate)] }
        let t = Double(max(1, total)), n = max(1, count), i = min(max(0, index), n - 1)
        let elapsed = min(t, t * Double(i) / Double(n) + max(0, clipElapsed))
        var o: [String: Any] = ["slug": slug, "playing": playing, "index": i, "count": n, "elapsed": (elapsed * 10).rounded() / 10,
                                "total": Int(t), "rate": Double(rate)]
        if let kicker, !kicker.isEmpty { o["kicker"] = kicker }
        return o
    }

    // MARK: Helpers

    /// "q=a%20b&x=1" → ["q": "a b", "x": "1"].
    static func params(_ query: String?) -> [String: String] {
        var out: [String: String] = [:]
        for pair in (query ?? "").split(separator: "&") {
            let kv = pair.split(separator: "=", maxSplits: 1).map(String.init)
            guard let k = kv.first?.removingPercentEncoding else { continue }
            out[k] = (kv.count > 1 ? kv[1] : "").replacingOccurrences(of: "+", with: " ").removingPercentEncoding ?? ""
        }
        return out
    }
}

// MARK: - The page's messages (LAB-1836, LAB-1893)

/// A message the host page posts to the app (`window.webkit.messageHandlers.oneroofLearn`), read once here so the controller
/// only acts. Unknown or malformed messages are nil (ignored).
public enum LearnBridgeMessage: Equatable, Sendable {
    case ready, mounted, subscribed
    case hash(String)
    case error(String)
    case net(String)
    /// A page (or a card frame) started its own audio.
    case mediaPlay
    /// Play in One Roof: `slug`, then `queue` (empty: the rest of its band), from `scene` (nil: toggle / from the start).
    case play(slug: String, queue: [String], scene: Int?)
    case useInSession(String)
    case openFolder(String)
    case openExternal(String)
    /// LAB-1893 · the app's player: play / pause, the next speed.
    case toggle, rate
    case refreshPosts
    /// LAB-1893 · a new terminal session in that deck folder.
    case terminal(String)

    public static func parse(_ body: Any) -> LearnBridgeMessage? {
        guard let m = body as? [String: Any], let type = m["type"] as? String else { return nil }
        let s = { (k: String) in m[k] as? String ?? "" }
        switch type {
        case "ready": return .ready
        case "mounted": return .mounted
        case "subscribed": return .subscribed
        case "hash": return .hash(s("hash"))
        case "error": return .error(m["message"] as? String ?? "the page could not load")
        case "net": return .net(s("url"))
        case "mediaPlay": return .mediaPlay
        case "play":
            let slug = s("slug")
            guard LearnShared.isSlug(slug) else { return nil }
            let scene = (m["scene"] as? Int).flatMap { $0 >= 0 ? $0 : nil }
            return .play(slug: slug, queue: (m["queue"] as? [String] ?? []).filter(LearnShared.isSlug), scene: scene)
        case "useInSession": return LearnShared.isSlug(s("slug")) ? .useInSession(s("slug")) : nil
        case "openFolder": return .openFolder(s("path"))
        case "openExternal": return .openExternal(s("url"))
        case "toggle": return .toggle
        case "rate": return .rate
        case "refreshPosts": return .refreshPosts
        case "terminal": return .terminal(s("path"))
        default: return nil
        }
    }
}

public extension LearnShared {
    /// A folder of the deck (`rel` from its root; "" = the root itself), or nil when it escapes the deck or is not a folder.
    static func folderInDeck(_ rel: String, deck: String) -> String? {
        let base = (deck as NSString).standardizingPath
        let full = ((base as NSString).appendingPathComponent(rel) as NSString).standardizingPath
        var dir: ObjCBool = false
        guard !rel.hasPrefix("/"), full == base || full.hasPrefix(base + "/"), FileManager.default.fileExists(atPath: full, isDirectory: &dir), dir.boolValue else { return nil }
        return full
    }

    /// The next speed after `rate` (One Roof's player: 0.75 → 1 → 1.25 → 1.5 → 1.75 → 2 → 0.75).
    static func nextRate(after rate: Float, in rates: [Float]) -> Float {
        guard !rates.isEmpty else { return rate }
        return rates[((rates.firstIndex(of: rate) ?? 1) + 1) % rates.count]   // as the native speed key
    }
}
