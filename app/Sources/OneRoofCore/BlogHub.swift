import Foundation

// LAB-1251 · Learn › Writing reads the author's posts from the blog hub (owner decision, 1.8.2). Posts are published
// once and served by the hub, which the author's sites read; One Roof reads the same public API:
//   GET <base>/blog/api/posts?site=<site>          → {site, generatedAt, posts: [meta]}
//   GET <base>/blog/api/posts/<slug>?site=<site>   → {site, post: meta, html, toc, words, needs, newer, older}
//   GET <base>/blog/assets/<slug>/<file>             → an image
// The hub serves the body as HTML only, so each post is turned into Markdown here and saved as
// `<cache>/<slug>/index.md` (frontmatter + body) with its images beside it. `LearnPosts.scan` then reads the cache like
// any Learn folder, so Writing, the post reader, band posts and the schedule work offline and show at once; the app
// refreshes the cache in the background. The site-only diagrams and charts (`bl-stepdiagram`, `bl-chart`) become one
// line naming them, with a link to the web version.

public enum BlogHub {
    /// The hub: the one place its address is written. Override for testing with
    /// `defaults write <bundle id> learn.blogHubURL http://localhost:…` (or ONEROOF_BLOG_HUB for a self-test).
    public static let defaultBase = "https://console.zibajoon.com"
    public static let baseKey = "learn.blogHubURL"
    /// The hub serves several sites; One Roof reads the one named like the hub's domain ("console.example.com" →
    /// "example"), unless `learn.blogHubSite` says otherwise.
    public static let siteKey = "learn.blogHubSite"

    public static var site: String {
        if let s = UserDefaults.standard.string(forKey: siteKey)?.trimmingCharacters(in: .whitespaces), !s.isEmpty { return s }
        return site(forBase: base)
    }

    public static func site(forBase base: String) -> String {
        let labels = (URL(string: base)?.host ?? "").split(separator: ".")
        guard labels.count >= 2, !labels.allSatisfy({ $0.allSatisfy(\.isNumber) }) else { return "" }   // an IP or a bare host name
        return String(labels[labels.count - 2])
    }

    /// "Example blog", for the page's copy and the posts' `source` ("blog" when the site has no name).
    public static func name(site: String) -> String {
        guard let f = site.first, f.isLetter else { return "blog" }
        return (site.prefix(1).uppercased() + site.dropFirst()) + " blog"
    }
    public static var name: String { name(site: site) }
    /// Marker file in each post folder the hub sync wrote (only those are ever removed by a sync).
    static let marker = ".from-hub"

    /// `ONEROOF_BLOG_HUB` (self-tests), else the `learn.blogHubURL` default, else the hub.
    public static var base: String {
        let env = ProcessInfo.processInfo.environment["ONEROOF_BLOG_HUB"]
        let s = (env ?? UserDefaults.standard.string(forKey: baseKey) ?? "").trimmingCharacters(in: .whitespaces)
        return s.isEmpty ? defaultBase : (s.hasSuffix("/") ? String(s.dropLast()) : s)
    }

    /// `~/Library/Caches/OneRoof/blog` (the app's cache convention, beside `OneRoof/pastes`); `ONEROOF_BLOG_CACHE`
    /// points a self-test at a scratch folder.
    public static var cacheDir: String {
        if let e = ProcessInfo.processInfo.environment["ONEROOF_BLOG_CACHE"], !e.isEmpty { return (e as NSString).expandingTildeInPath }
        return FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("OneRoof/blog").path
    }

    // MARK: API shapes

    public struct Meta: Decodable, Equatable, Sendable {
        public var slug: String
        public var title: String
        public var subtitle: String?
        public var summary: String?
        public var date: String
        public var updated: String?
        public var status: String?
        public var tags: [String]?
        public var series: String?
        public var minutes: Int?
        public var canonical: String?
    }

    struct ListReply: Decodable { var posts: [Meta] }
    struct PostReply: Decodable { var post: Meta; var html: String? }

    public static func listURL(base: String, site: String) -> URL? { URL(string: "\(base)/blog/api/posts?site=\(site)") }
    public static func postURL(base: String, slug: String, site: String) -> URL? { URL(string: "\(base)/blog/api/posts/\(slug)?site=\(site)") }

    /// The list reply's posts (nil when it is not the hub's JSON). Posts with an unsafe slug are dropped.
    public static func decodeList(_ data: Data) -> [Meta]? {
        guard let r = try? JSONDecoder().decode(ListReply.self, from: data) else { return nil }
        return r.posts.filter { safeSlug($0.slug) && !$0.title.isEmpty && $0.date.count >= 10 }
    }

    public static func decodePost(_ data: Data) -> (meta: Meta, html: String)? {
        guard let r = try? JSONDecoder().decode(PostReply.self, from: data), safeSlug(r.post.slug) else { return nil }
        return (r.post, r.html ?? "")
    }

    /// Slugs become folder names: lower-case letters, digits and dashes only.
    public static func safeSlug(_ s: String) -> Bool {
        !s.isEmpty && s.count <= 120 && s.first != "-" && s.allSatisfy { ($0.isASCII && ($0.isLowercase || $0.isNumber)) || $0 == "-" }
    }

    static func safeFile(_ s: String) -> Bool {
        !s.isEmpty && s.count <= 200 && !s.hasPrefix(".") && s.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || "._-".contains($0)) }
    }

    // MARK: The cached post file

    /// `index.md` for a post: frontmatter `LearnPosts.post` reads, then the body.
    public static func indexFile(_ m: Meta, body: String, source: String = BlogHub.name) -> String {
        func clean(_ s: String?) -> String {
            (s ?? "").replacingOccurrences(of: "\r", with: " ").replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespaces)
        }
        var fm = ["title: \(clean(m.title))", "date: \(clean(m.date))"]
        if let v = m.subtitle, !clean(v).isEmpty { fm.append("subtitle: \(clean(v))") }
        if let v = m.summary, !clean(v).isEmpty { fm.append("summary: \(clean(v))") }
        fm.append("status: \(clean(m.status ?? "published"))")
        if let v = m.series, !clean(v).isEmpty { fm.append("series: \(clean(v))") }
        if let t = m.tags, !t.isEmpty { fm.append("tags: [\(t.map { clean($0).replacingOccurrences(of: ",", with: " ") }.joined(separator: ", "))]") }
        if let n = m.minutes, n > 0 { fm.append("minutes: \(n)") }
        if let v = m.updated, !clean(v).isEmpty { fm.append("updated: \(clean(v))") }
        if let v = m.canonical, !clean(v).isEmpty { fm.append("canonical: \(clean(v))") }
        fm.append("source: \(clean(source))")
        return "---\n" + fm.joined(separator: "\n") + "\n---\n\n" + body.trimmingCharacters(in: .whitespacesAndNewlines) + "\n"
    }

    /// The hub's images for a post (`<base>/blog/assets/<slug>/<file>`, absolute or site-relative), in order, once each.
    public static func imageURLs(_ html: String, base: String, slug: String) -> [(url: String, file: String)] {
        var out: [(String, String)] = [], seen = Set<String>()
        HTMLDoc.parse(html).walk { n in
            guard n.tag == "img" else { return }
            let abs = absolute(n.attr("src"), base: base)
            guard let file = assetFile(abs, base: base, slug: slug), seen.insert(abs).inserted else { return }
            out.append((abs, file))
        }
        return out
    }

    /// "<base>/blog/assets/<slug>/x.png" → "x.png"; anything else (another host, another post's folder) → nil.
    static func assetFile(_ url: String, base: String, slug: String) -> String? {
        let prefix = base + "/blog/assets/" + slug + "/"
        guard url.hasPrefix(prefix) else { return nil }
        var f = String(url.dropFirst(prefix.count))
        if let q = f.firstIndex(where: { $0 == "?" || $0 == "#" }) { f = String(f[..<q]) }
        f = f.removingPercentEncoding ?? f
        return safeFile(f) ? f : nil
    }

    static func absolute(_ href: String, base: String) -> String {
        if href.hasPrefix("//") { return "https:" + href }
        if href.hasPrefix("/") { return base + href }
        return href
    }

    // MARK: HTML → Markdown

    /// The hub's post HTML as Markdown the app's viewer renders. `image` maps an absolute image URL to what the
    /// Markdown should point at (a file beside index.md once cached, else the URL itself).
    public static func markdown(html: String, base: String = BlogHub.defaultBase, canonical: String? = nil,
                                image: @escaping (String) -> String = { $0 }) -> String {
        let w = MarkdownWriter(base: base, canonical: canonical, image: image)
        return w.blocks(HTMLDoc.parse(html).kids).joined(separator: "\n\n")
    }

    // MARK: Sync

    public struct SyncResult: Equatable, Sendable {
        /// The list was read (the hub answered).
        public var reached: Bool
        /// Posts in the hub's list.
        public var posts: Int
        /// Posts or images that could not be fetched this time (the cached copy, if any, stays).
        public var failed: Int
        public var error: String?
    }

    public typealias Fetch = @Sendable (URL) async throws -> Data

    /// A plain GET with a 20 s timeout that only accepts HTTP 200.
    public static let download: Fetch = { url in
        var req = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        req.setValue("application/json, image/*", forHTTPHeaderField: "Accept")
        let (data, resp) = try await URLSession.shared.data(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard code == 200 else { throw URLError(.badServerResponse, userInfo: [NSLocalizedDescriptionKey: "HTTP \(code)"]) }
        return data
    }

    /// Fetch the list, every post and its images into `cache`. A post that fails keeps its cached copy; posts the
    /// hub no longer lists are removed (only folders this sync wrote). Never throws: the result says what happened.
    public static func sync(base: String = BlogHub.base, site: String? = nil, cache: String = BlogHub.cacheDir,
                            fetch: Fetch = BlogHub.download) async -> SyncResult {
        let site = site ?? (base == BlogHub.base ? BlogHub.site : BlogHub.site(forBase: base))
        guard let lu = listURL(base: base, site: site) else { return SyncResult(reached: false, posts: 0, failed: 0, error: "bad hub address \(base)") }
        let list: [Meta]
        do {
            guard let l = decodeList(try await fetch(lu)) else { return SyncResult(reached: false, posts: 0, failed: 0, error: "the hub's reply was not a post list") }
            list = l
        } catch {
            let why = error.localizedDescription.trimmingCharacters(in: .whitespaces)
            return SyncResult(reached: false, posts: 0, failed: 0, error: why.hasSuffix(".") ? String(why.dropLast()) : why)
        }
        let fm = FileManager.default
        try? fm.createDirectory(atPath: cache, withIntermediateDirectories: true)
        var failed = 0
        for m in list {
            let dir = cache + "/" + m.slug
            guard let pu = postURL(base: base, slug: m.slug, site: site),
                  let data = try? await fetch(pu), let (meta, html) = decodePost(data), meta.slug == m.slug else { failed += 1; continue }
            try? fm.createDirectory(atPath: dir, withIntermediateDirectories: true)
            var local = Set<String>()
            for img in imageURLs(html, base: base, slug: m.slug) {
                let path = dir + "/" + img.file
                if fm.fileExists(atPath: path) { local.insert(img.url); continue }
                if let u = URL(string: img.url), let bytes = try? await fetch(u), (try? bytes.write(to: URL(fileURLWithPath: path), options: .atomic)) != nil {
                    local.insert(img.url)
                } else { failed += 1 }
            }
            let body = markdown(html: html, base: base, canonical: meta.canonical) { url in
                local.contains(url) ? (assetFile(url, base: base, slug: m.slug) ?? url) : url
            }
            do {
                try indexFile(meta, body: body, source: name(site: site)).write(toFile: dir + "/index.md", atomically: true, encoding: .utf8)
                fm.createFile(atPath: dir + "/" + marker, contents: Data())
            } catch { failed += 1 }
        }
        let keep = Set(list.map(\.slug))
        for name in (try? fm.contentsOfDirectory(atPath: cache)) ?? [] where !keep.contains(name) {
            if fm.fileExists(atPath: cache + "/" + name + "/" + marker) { try? fm.removeItem(atPath: cache + "/" + name) }
        }
        let stamp: [String: Any] = ["base": base, "site": site, "fetchedAt": ISO8601DateFormatter().string(from: Date()), "posts": list.count]
        if let d = try? JSONSerialization.data(withJSONObject: stamp, options: [.sortedKeys]) {
            try? d.write(to: URL(fileURLWithPath: cache + "/hub.json"), options: .atomic)
        }
        return SyncResult(reached: true, posts: list.count, failed: failed, error: nil)
    }

    /// When the cache was last filled from the hub (nil: never).
    public static func lastSync(cache: String = BlogHub.cacheDir) -> Date? {
        guard let d = FileManager.default.contents(atPath: cache + "/hub.json"),
              let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any], let s = o["fetchedAt"] as? String else { return nil }
        return ISO8601DateFormatter().date(from: s)
    }
}

// MARK: - A small HTML reader (enough for the hub's generated post HTML)

/// A node of parsed HTML: an element (`tag` lower-case) or a text node (`tag` empty, `text` decoded).
final class HTMLNode {
    let tag: String
    var attrs: [String: String] = [:]
    var kids: [HTMLNode] = []
    var text = ""
    init(tag: String) { self.tag = tag }

    func attr(_ k: String) -> String { attrs[k] ?? "" }
    func hasClass(_ c: String) -> Bool { attr("class").split(separator: " ").contains { $0 == c } }
    var textContent: String { tag.isEmpty ? text : kids.map(\.textContent).joined() }
    func walk(_ f: (HTMLNode) -> Void) { f(self); for k in kids { k.walk(f) } }
    func first(_ p: (HTMLNode) -> Bool) -> HTMLNode? {
        for k in kids { if p(k) { return k }; if let f = k.first(p) { return f } }
        return nil
    }
}

enum HTMLDoc {
    static let void: Set<String> = ["img", "br", "hr", "input", "meta", "link", "source", "wbr", "col", "area", "base", "embed", "track"]
    static let raw: Set<String> = ["script", "style", "template"]

    static func parse(_ html: String) -> HTMLNode {
        let s = Array(html.unicodeScalars)
        let n = s.count
        let root = HTMLNode(tag: "#root")
        var stack = [root]
        var i = 0
        func isNameChar(_ c: Unicode.Scalar) -> Bool { CharacterSet.alphanumerics.contains(c) || c == "-" || c == ":" || c == "_" }
        func isSpace(_ c: Unicode.Scalar) -> Bool { c == " " || c == "\n" || c == "\t" || c == "\r" || c == "\u{0C}" }
        func starts(_ p: String, at j: Int) -> Bool {
            let ps = Array(p.unicodeScalars)
            guard j + ps.count <= n else { return false }
            for k in 0..<ps.count where String(s[j + k]).lowercased() != String(ps[k]) { return false }
            return true
        }
        func find(_ p: String, from j: Int) -> Int? {
            var k = j
            while k < n { if starts(p, at: k) { return k }; k += 1 }
            return nil
        }
        func addText(_ t: String) {
            guard !t.isEmpty else { return }
            let node = HTMLNode(tag: ""); node.text = decode(t)
            stack.last!.kids.append(node)
        }
        var textStart = 0
        func flushText(_ upTo: Int) {
            if upTo > textStart { addText(String(String.UnicodeScalarView(s[textStart..<upTo]))) }
        }
        while i < n {
            guard s[i] == "<", i + 1 < n else { i += 1; continue }
            let c = s[i + 1]
            if starts("<!--", at: i) {
                flushText(i)
                i = (find("-->", from: i + 4).map { $0 + 3 }) ?? n; textStart = i; continue
            }
            if c == "!" || c == "?" {
                flushText(i)
                i = (find(">", from: i).map { $0 + 1 }) ?? n; textStart = i; continue
            }
            if c == "/" {
                var j = i + 2, name = ""
                while j < n, isNameChar(s[j]) { name.unicodeScalars.append(s[j]); j += 1 }
                guard !name.isEmpty else { i += 1; continue }
                flushText(i)
                name = name.lowercased()
                if let at = stack.lastIndex(where: { $0.tag == name }), at > 0 { stack.removeLast(stack.count - at) }
                i = (find(">", from: j).map { $0 + 1 }) ?? n; textStart = i; continue
            }
            guard CharacterSet.letters.contains(c) else { i += 1; continue }
            flushText(i)
            var j = i + 1, name = ""
            while j < n, isNameChar(s[j]) { name.unicodeScalars.append(s[j]); j += 1 }
            let node = HTMLNode(tag: name.lowercased())
            var selfClose = false
            while j < n {
                while j < n, isSpace(s[j]) { j += 1 }
                guard j < n else { break }
                if s[j] == ">" { j += 1; break }
                if s[j] == "/" { selfClose = true; j += 1; continue }
                var key = ""
                while j < n, !isSpace(s[j]), s[j] != "=", s[j] != ">", s[j] != "/" { key.unicodeScalars.append(s[j]); j += 1 }
                if key.isEmpty { j += 1; continue }
                while j < n, isSpace(s[j]) { j += 1 }
                var value = ""
                if j < n, s[j] == "=" {
                    j += 1
                    while j < n, isSpace(s[j]) { j += 1 }
                    if j < n, s[j] == "\"" || s[j] == "'" {
                        let q = s[j]; j += 1
                        let st = j
                        while j < n, s[j] != q { j += 1 }
                        value = String(String.UnicodeScalarView(s[st..<min(j, n)])); j += 1
                    } else {
                        while j < n, !isSpace(s[j]), s[j] != ">" { value.unicodeScalars.append(s[j]); j += 1 }
                    }
                }
                node.attrs[key.lowercased()] = decode(value)
            }
            stack.last!.kids.append(node)
            i = j; textStart = i
            if raw.contains(node.tag) {
                let end = find("</" + node.tag, from: i) ?? n
                i = (find(">", from: end).map { $0 + 1 }) ?? n; textStart = i
                continue
            }
            if !selfClose && !void.contains(node.tag) { stack.append(node) }
        }
        flushText(n)
        return root
    }

    static let named: [String: String] = [
        "amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'", "nbsp": "\u{00A0}", "mdash": "—", "ndash": "–",
        "hellip": "…", "rsquo": "’", "lsquo": "‘", "rdquo": "”", "ldquo": "“", "middot": "·", "rarr": "→", "larr": "←",
        "times": "×", "copy": "©", "trade": "™", "bull": "•", "deg": "°", "minus": "−", "le": "≤", "ge": "≥",
    ]

    static func decode(_ t: String) -> String {
        guard t.contains("&") else { return t }
        var out = "", i = t.startIndex
        while i < t.endIndex {
            if t[i] == "&", let semi = t[i...].prefix(12).firstIndex(of: ";") {
                let name = String(t[t.index(after: i)..<semi])
                var rep: String?
                if name.hasPrefix("#x") || name.hasPrefix("#X") {
                    rep = UInt32(name.dropFirst(2), radix: 16).flatMap(Unicode.Scalar.init).map { String(Character($0)) }
                } else if name.hasPrefix("#") {
                    rep = UInt32(name.dropFirst()).flatMap(Unicode.Scalar.init).map { String(Character($0)) }
                } else { rep = named[name] }
                if let rep { out += rep; i = t.index(after: semi); continue }
            }
            out.append(t[i]); i = t.index(after: i)
        }
        return out
    }
}

// MARK: - Writer

struct MarkdownWriter {
    let base: String
    let canonical: String?
    let image: (String) -> String

    static let blockTags: Set<String> = ["p", "h1", "h2", "h3", "h4", "h5", "h6", "ul", "ol", "blockquote", "aside", "figure", "table",
                                         "pre", "div", "hr", "section", "article", "header", "footer", "details", "figcaption", "dl", "main", "nav"]

    func isBlock(_ n: HTMLNode) -> Bool {
        if Self.blockTags.contains(n.tag) { return true }
        if n.tag == "span", n.hasClass("katex-display") { return true }
        return false
    }

    func blocks(_ kids: [HTMLNode]) -> [String] {
        var out: [String] = [], run: [HTMLNode] = []
        func flush(_ w: MarkdownWriter) {
            let s = w.inline(run).trimmingCharacters(in: .whitespaces)
            if !s.isEmpty { out.append(Self.escapeLead(s)) }
            run = []
        }
        for k in kids {
            if isBlock(k) { flush(self); out += block(k) } else { run.append(k) }
        }
        flush(self)
        return out
    }

    func block(_ n: HTMLNode) -> [String] {
        switch n.tag {
        case "p":
            let s = inline(n.kids).trimmingCharacters(in: .whitespaces)
            return s.isEmpty ? [] : [Self.escapeLead(s)]
        case "h1", "h2", "h3", "h4", "h5", "h6":
            let level = Int(String(n.tag.last!)) ?? 2
            let s = inline(n.kids.filter { !($0.tag == "a" && $0.hasClass("bl-anchor")) }).trimmingCharacters(in: .whitespaces)
            return s.isEmpty ? [] : [String(repeating: "#", count: level) + " " + s]
        case "ul", "ol": return [list(n, ordered: n.tag == "ol")].filter { !$0.isEmpty }
        case "blockquote": return [Self.quote(blocks(n.kids))].filter { !$0.isEmpty }
        case "aside":
            let title = n.kids.first { $0.tag == "p" && $0.hasClass("bl-callout-title") }
            var inner = blocks(n.kids.filter { $0 !== title })
            if let title { let t = inline(title.kids).trimmingCharacters(in: .whitespaces); if !t.isEmpty { inner.insert("**" + t + "**", at: 0) } }
            return [Self.quote(inner)].filter { !$0.isEmpty }
        case "figure":
            var out: [String] = []
            n.walk { k in if k.tag == "img" { out.append(imageLine(k)) } }
            if let cap = n.first({ $0.tag == "figcaption" }) {
                let c = inline(cap.kids).trimmingCharacters(in: .whitespaces)
                if !c.isEmpty { out.append("*" + c + "*") }
            }
            return out
        case "table": return [table(n)].filter { !$0.isEmpty }
        case "pre": return [fence(n)]
        case "hr": return ["---"]
        case "span": return [code(tex(n))].filter { $0 != "``" }
        case "div":
            if n.hasClass("bl-stepdiagram") || n.hasClass("bl-chart") { return [placeholder(n)] }
            if let pre = n.kids.first(where: { $0.tag == "pre" }), n.hasClass("bl-code") { return [fence(pre)] }
            return blocks(n.kids)
        default: return blocks(n.kids)
        }
    }

    /// One line for a site-only diagram or chart: its title and where to see it.
    func placeholder(_ n: HTMLNode) -> String {
        let kind = n.hasClass("bl-chart") ? "Chart" : "Diagram"
        var title = ""
        if let d = n.attr("data-spec").data(using: .utf8), let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any] {
            title = (o["title"] as? String) ?? ""
        }
        if title.isEmpty { title = n.textContent.trimmingCharacters(in: .whitespacesAndNewlines) }
        var s = "*" + kind + (title.isEmpty ? "" : ": " + Self.escape(title)) + ". Drawn on the web version"
        if let c = canonical, !c.isEmpty { s += " ([open it](\(Self.href(c))))" }
        return s + ".*"
    }

    func list(_ n: HTMLNode, ordered: Bool) -> String {
        let start = Int(n.attr("start")) ?? 1
        var lines: [String] = []
        for (k, li) in n.kids.filter({ $0.tag == "li" }).enumerated() {
            let m = ordered ? "\(start + k). " : "- "
            let pad = String(repeating: " ", count: m.count)
            let bs = blocks(li.kids)
            if bs.isEmpty { lines.append(m.trimmingCharacters(in: .whitespaces)); continue }
            for (j, b) in bs.enumerated() {
                for (x, l) in b.components(separatedBy: "\n").enumerated() {
                    lines.append(j == 0 && x == 0 ? m + l : (l.isEmpty ? "" : pad + l))
                }
            }
        }
        return lines.joined(separator: "\n")
    }

    static func quote(_ blocks: [String]) -> String {
        guard !blocks.isEmpty else { return "" }
        return blocks.joined(separator: "\n\n").components(separatedBy: "\n").map { $0.isEmpty ? ">" : "> " + $0 }.joined(separator: "\n")
    }

    func table(_ n: HTMLNode) -> String {
        var rows: [(cells: [String], head: Bool)] = []
        n.walk { k in
            guard k.tag == "tr" else { return }
            let cells = k.kids.filter { $0.tag == "td" || $0.tag == "th" }
            rows.append((cells.map { inline($0.kids).trimmingCharacters(in: .whitespaces) }, cells.allSatisfy { $0.tag == "th" }))
        }
        guard let first = rows.first else { return "" }
        let width = rows.map(\.cells.count).max() ?? 0
        guard width > 0 else { return "" }
        func line(_ c: [String]) -> String {
            "| " + (c + Array(repeating: "", count: max(0, width - c.count))).map { $0.isEmpty ? " " : $0 }.joined(separator: " | ") + " |"
        }
        var out = [line(first.cells), "|" + Array(repeating: " --- |", count: width).joined()]
        for r in rows.dropFirst() { out.append(line(r.cells)) }
        return out.joined(separator: "\n")
    }

    func fence(_ pre: HTMLNode) -> String {
        let codeNode = pre.kids.first { $0.tag == "code" } ?? pre
        let lang = codeNode.attr("class").split(separator: " ").first { $0.hasPrefix("language-") }.map { String($0.dropFirst(9)) } ?? ""
        let text = codeNode.textContent.trimmingCharacters(in: .newlines)
        let f = text.contains("```") ? "~~~~" : "```"
        return f + lang + "\n" + text + "\n" + f
    }

    func imageLine(_ img: HTMLNode) -> String {
        let src = image(BlogHub.absolute(img.attr("src"), base: base))
        // The alt text is shown as it is (an accessibility label), so only what would end it is escaped.
        let alt = img.attr("alt").replacingOccurrences(of: "\n", with: " ").replacingOccurrences(of: "]", with: ")")
        return "![" + alt + "](" + Self.href(src) + ")"
    }

    /// KaTeX keeps the TeX source in an annotation; else the visible text.
    func tex(_ n: HTMLNode) -> String {
        if let a = n.first({ $0.tag == "annotation" }) { return a.textContent.trimmingCharacters(in: .whitespacesAndNewlines) }
        return n.textContent.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func code(_ s: String) -> String {
        let t = s.replacingOccurrences(of: "\n", with: " ")
        return t.contains("`") ? "`` " + t + " ``" : "`" + t + "`"
    }

    func inline(_ nodes: [HTMLNode]) -> String {
        var out = ""
        for n in nodes {
            switch n.tag {
            case "": out += Self.escape(Self.collapse(n.text))
            case "strong", "b": out += wrap(inline(n.kids), "**")
            case "em", "i": out += wrap(inline(n.kids), "*")
            case "del", "s": out += wrap(inline(n.kids), "~~")
            case "code", "kbd", "samp":
                let t = n.textContent
                if !t.isEmpty { out += code(t) }
            case "a":
                if n.hasClass("bl-anchor") { continue }
                let inner = inline(n.kids)
                var h = n.attr("href")
                if h.hasPrefix("/"), !h.hasPrefix("/blog/"), !h.hasPrefix("//") { h = base + h }
                if h.hasPrefix("//") { h = "https:" + h }
                out += h.isEmpty || inner.trimmingCharacters(in: .whitespaces).isEmpty ? inner : "[" + inner + "](" + Self.href(h) + ")"
            case "br": out += " "
            case "img": out += imageLine(n)
            case "span" where n.hasClass("katex"): out += code(tex(n))
            case "math": out += code(tex(n))
            case "script", "style", "template", "button": continue
            default: out += inline(n.kids)
            }
        }
        return out
    }

    /// "**…**" around the text, with surrounding spaces kept outside the markers (Markdown ignores "** x**").
    func wrap(_ s: String, _ m: String) -> String {
        let core = s.trimmingCharacters(in: .whitespaces)
        guard !core.isEmpty else { return s }
        let lead = s.prefix { $0 == " " }, trail = String(s.reversed().prefix { $0 == " " })
        return lead + m + core + m + trail
    }

    static func collapse(_ s: String) -> String {
        var out = "", space = false
        for ch in s {
            if ch == " " || ch == "\n" || ch == "\t" || ch == "\r" { if !space { out.append(" ") }; space = true }
            else { out.append(ch); space = false }
        }
        return out
    }

    /// Text that must stay text: Markdown punctuation gets a backslash.
    static func escape(_ s: String) -> String {
        var out = ""
        for ch in s {
            if "\\`*_[]<>|&".contains(ch) { out.append("\\") }
            out.append(ch)
        }
        return out
    }

    /// A paragraph that would start a heading, quote, list or rule gets its first marker escaped.
    static func escapeLead(_ s: String) -> String {
        guard let f = s.first else { return s }
        if "#>-+=".contains(f) { return "\\" + s }
        let digits = s.prefix { $0.isNumber }
        if !digits.isEmpty, digits.count <= 9 {
            let rest = s.dropFirst(digits.count)
            if let p = rest.first, p == "." || p == ")", rest.dropFirst().first == " " || rest.count == 1 { return digits + "\\" + rest }
        }
        return s
    }

    /// A link target Markdown keeps whole (spaces and parentheses encoded).
    static func href(_ s: String) -> String {
        s.replacingOccurrences(of: " ", with: "%20").replacingOccurrences(of: "(", with: "%28").replacingOccurrences(of: ")", with: "%29")
    }
}
