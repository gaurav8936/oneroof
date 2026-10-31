import CommonCrypto
import Foundation

// LAB-1762 · Learn is the shared Agentic Engineering page (owner decision 2026-10-30): every site shows it from one copy, served
// by the blog hub as the `ggae` embed, and One Roof shows the same copy. Each One Roof build fetches it from the hub and saves it
// inside the app (`agentic_engineering/learn/`, written by scripts/learn-fetch.py), so Learn works offline and picks up changes
// with the next release. The app shows it in a web view whose pages come from `oneroof-learn://hub/…`, answered here:
//
//   /  or /index.html          the host page: loads the saved embed and mounts it (site "oneroof", player on, the app's bridge)
//   /embed/ggae.{js,css}       the saved embed (also /blog/embed/…)
//   /ae/api/catalog            the saved catalog, every card page, photo and the home page pointed at the bundled deck
//   /ae/api/card/<slug>        the saved card details (Transcript, Skill file, Profile); 404 when the build saved none
//   /blog/api/posts            the saved posts list (a post opens in the browser)
//   /deck/<path>               a file of the bundled deck (card pages, narration, photos), byte ranges for audio
//
// Pure logic (no WebKit): the app's scheme handler and tests call `respond`. Foundation only, so a capture script can compile
// this file on its own (scripts/learn-shot.swift).
public enum LearnShared {
    public static let scheme = "oneroof-learn"
    public static let host = "hub"
    public static var origin: String { "\(scheme)://\(host)" }
    /// The script message channel the host page posts to (`window.webkit.messageHandlers.oneroofLearn`).
    public static let handler = "oneroofLearn"
    /// The saved files, inside the learn folder.
    public static let required = ["ggae.js", "ggae.css", "catalog.json", "posts.json", "learn-manifest.json"]

    /// Where the saved page and the deck it plays are.
    public struct Location: Equatable, Sendable {
        public var learn: String
        public var deck: String
        public init(learn: String, deck: String) { self.learn = learn; self.deck = deck }
    }

    /// `ONEROOF_LEARN_DIR`, else `<ae>/learn`; with the deck (`<ae>/deck`). Nil when either is missing or the saved files are
    /// not all there (a build from source without the deck): Learn then shows the classic screens.
    public static func locate(ae: String, deck: String?, environment: [String: String] = ProcessInfo.processInfo.environment) -> Location? {
        guard let deck else { return nil }
        let dir = environment["ONEROOF_LEARN_DIR"].flatMap { $0.isEmpty ? nil : ($0 as NSString).expandingTildeInPath } ?? ae + "/learn"
        return problems(learn: dir).isEmpty ? Location(learn: dir, deck: deck) : nil
    }

    // MARK: The manifest

    /// `learn-manifest.json`, written by the build next to the saved files.
    public struct Manifest: Codable, Equatable, Sendable {
        public var hub: String
        public var site: String
        public var fetchedAt: String
        public var edition: String?
        public var version: String?
        /// The deck commit the hub's catalog was built from, and the one bundled in the app (`deck/.deck-ref`).
        public var catalogFrom: String?
        public var deckRef: String?
        public var ggaeSha256: String
        public var ggaeCssSha256: String?
        /// Where the embed came from: the hub, or a local folder (ONEROOF_GGAE_DIR, test builds only).
        public var ggaeFrom: String?
        public var cards: Int
        public var cardDetails: Int
        public var posts: Int
    }

    public static func manifest(learn: String) -> Manifest? {
        guard let d = FileManager.default.contents(atPath: learn + "/learn-manifest.json") else { return nil }
        return try? JSONDecoder().decode(Manifest.self, from: d)
    }

    /// What is wrong with a saved learn folder (empty: fine): a missing or empty file, an unreadable manifest, an embed whose
    /// sha256 is not the one the manifest recorded, a catalog with no cards, card details fewer than the manifest says.
    public static func problems(learn: String) -> [String] {
        let fm = FileManager.default
        var out: [String] = []
        for f in required {
            let size = (try? fm.attributesOfItem(atPath: learn + "/" + f)[.size] as? Int) ?? nil
            if size == nil { out.append("\(f) missing") } else if size == 0 { out.append("\(f) empty") }
        }
        guard out.isEmpty else { return out }
        guard let m = manifest(learn: learn) else { return ["learn-manifest.json unreadable"] }
        if let js = fm.contents(atPath: learn + "/ggae.js"), sha256Hex(js) != m.ggaeSha256.lowercased() {
            out.append("ggae.js does not match the manifest's sha256")
        }
        let cat = (fm.contents(atPath: learn + "/catalog.json")).flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
        if ((cat?["counts"] as? [String: Any])?["cards"] as? Int ?? 0) == 0 { out.append("catalog.json has no cards") }
        let details = ((try? fm.contentsOfDirectory(atPath: learn + "/cards")) ?? []).filter { $0.hasSuffix(".json") }.count
        if details < m.cardDetails { out.append("\(details) card details saved, the manifest says \(m.cardDetails)") }
        return out
    }

    // MARK: Responses

    public struct Response: Equatable, Sendable {
        public var status: Int
        public var mime: String
        public var body: Data
        public var headers: [String: String]
        public init(status: Int, mime: String, body: Data, headers: [String: String] = [:]) {
            self.status = status; self.mime = mime; self.body = body; self.headers = headers
        }
        public var allHeaders: [String: String] {
            var h = headers
            h["Content-Type"] = mime
            h["Content-Length"] = String(body.count)
            h["Cache-Control"] = "no-store"
            return h
        }
    }

    static func json(_ status: Int, _ obj: [String: Any]) -> Response {
        Response(status: status, mime: "application/json; charset=utf-8", body: (try? JSONSerialization.data(withJSONObject: obj)) ?? Data())
    }
    static let notFound = json(404, ["error": "not found"])

    /// The answer for `path` (the URL's path, percent-decoded). `range` is the request's Range header (audio seeks).
    public static func respond(path rawPath: String, range: String? = nil, at loc: Location) -> Response {
        let path = rawPath.isEmpty ? "/" : rawPath
        switch path {
        case "/", "/index.html":
            return Response(status: 200, mime: "text/html; charset=utf-8", body: Data(hostPage.utf8))
        case "/embed/ggae.js", "/blog/embed/ggae.js":
            return file(loc.learn + "/ggae.js", range: nil)
        case "/embed/ggae.css", "/blog/embed/ggae.css":
            return file(loc.learn + "/ggae.css", range: nil)
        case "/ae/api/catalog":
            guard let d = FileManager.default.contents(atPath: loc.learn + "/catalog.json") else { return json(503, ["error": "not saved in this build"]) }
            return Response(status: 200, mime: "application/json; charset=utf-8", body: rewriteCatalog(d, deck: loc.deck))
        case "/blog/api/posts":
            return file(loc.learn + "/posts.json", range: nil)
        default: break
        }
        if path.hasPrefix("/ae/api/card/") {
            let slug = String(path.dropFirst("/ae/api/card/".count))
            guard isSlug(slug) else { return json(400, ["error": "bad slug"]) }
            let f = loc.learn + "/cards/\(slug).json"
            return FileManager.default.fileExists(atPath: f) ? file(f, range: nil) : json(404, ["error": "no details for this card"])
        }
        if path.hasPrefix("/deck/"), let f = inside(loc.deck, String(path.dropFirst("/deck/".count))) {
            return file(f, range: range)
        }
        return notFound
    }

    /// "a-card-slug": what the hub accepts too.
    public static func isSlug(_ s: String) -> Bool {
        s.range(of: "^[a-z0-9][a-z0-9-]{0,80}$", options: .regularExpression) != nil
    }

    /// `rel` resolved under `root`, or nil when it escapes it (`..`, an absolute path) or is not a file.
    public static func inside(_ root: String, _ rel: String) -> String? {
        guard !rel.isEmpty, !rel.hasPrefix("/") else { return nil }
        let base = (root as NSString).standardizingPath
        let full = ((base as NSString).appendingPathComponent(rel) as NSString).standardizingPath
        guard full.hasPrefix(base + "/") else { return nil }
        var dir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: full, isDirectory: &dir), !dir.boolValue else { return nil }
        return full
    }

    static func file(_ path: String, range: String?) -> Response {
        guard let d = FileManager.default.contents(atPath: path) else { return notFound }
        let mime = mimeType(path)
        if let range, let r = byteRange(range, size: d.count) {
            return Response(status: 206, mime: mime, body: d.subdata(in: r),
                            headers: ["Content-Range": "bytes \(r.lowerBound)-\(r.upperBound - 1)/\(d.count)", "Accept-Ranges": "bytes"])
        }
        return Response(status: 200, mime: mime, body: d, headers: ["Accept-Ranges": "bytes"])
    }

    /// "bytes=a-b", "bytes=a-", "bytes=-n" → the half-open range in a body of `size` bytes (nil: not satisfiable or not one range).
    public static func byteRange(_ header: String, size: Int) -> Range<Int>? {
        let h = header.trimmingCharacters(in: .whitespaces)
        guard h.hasPrefix("bytes="), size > 0 else { return nil }
        let spec = h.dropFirst(6)
        guard !spec.contains(","), let dash = spec.firstIndex(of: "-") else { return nil }
        let a = Int(spec[..<dash].trimmingCharacters(in: .whitespaces)), b = Int(spec[spec.index(after: dash)...].trimmingCharacters(in: .whitespaces))
        switch (a, b) {
        case let (a?, b?) where a <= b && a < size: return a..<min(b + 1, size)
        case let (a?, nil) where a < size: return a..<size
        case let (nil, n?) where n > 0: return max(0, size - n)..<size
        default: return nil
        }
    }

    public static func mimeType(_ path: String) -> String {
        switch (path as NSString).pathExtension.lowercased() {
        case "html", "htm": return "text/html; charset=utf-8"
        case "js", "mjs": return "text/javascript; charset=utf-8"
        case "css": return "text/css; charset=utf-8"
        case "json": return "application/json; charset=utf-8"
        case "md", "txt", "yaml", "yml": return "text/plain; charset=utf-8"
        case "svg": return "image/svg+xml"
        case "png": return "image/png"
        case "jpg", "jpeg": return "image/jpeg"
        case "webp": return "image/webp"
        case "gif": return "image/gif"
        case "ico": return "image/x-icon"
        case "mp3": return "audio/mpeg"
        case "m4a": return "audio/mp4"
        case "wav": return "audio/wav"
        case "ogg": return "audio/ogg"
        case "mp4": return "video/mp4"
        case "woff2": return "font/woff2"
        case "woff": return "font/woff"
        default: return "application/octet-stream"
        }
    }

    // MARK: Catalog

    /// The hub's catalog with every card page, photo and the home page that the bundled deck has pointed at it
    /// (`https://<cdn>/content/…` → `oneroof-learn://hub/deck/content/…`), so cards play offline. A URL the deck has no file
    /// for is left alone (it opens in the browser).
    public static func rewriteCatalog(_ data: Data, deck: String) -> Data {
        guard let obj = try? JSONSerialization.jsonObject(with: data) else { return data }
        let out = rewrite(obj, deck: deck)
        return (try? JSONSerialization.data(withJSONObject: out)) ?? data
    }

    static let urlKeys: Set<String> = ["url", "photo", "home"]

    static func rewrite(_ v: Any, deck: String, key: String? = nil) -> Any {
        if let d = v as? [String: Any] {
            var o: [String: Any] = [:]
            for (k, x) in d { o[k] = rewrite(x, deck: deck, key: k) }
            return o
        }
        if let a = v as? [Any] { return a.map { rewrite($0, deck: deck) } }
        if let s = v as? String, let key, urlKeys.contains(key), let local = deckURL(s, deck: deck) { return local }
        return v
    }

    /// "https://cdn.example/content/cards/x/x.html" → "oneroof-learn://hub/deck/content/cards/x/x.html" when the deck has it.
    public static func deckURL(_ s: String, deck: String) -> String? {
        guard let u = URLComponents(string: s), u.scheme == "https" || u.scheme == "http" else { return nil }
        let rel = String(u.path.drop { $0 == "/" })
        guard rel.hasPrefix("content/"), inside(deck, rel) != nil else { return nil }
        var out = "\(origin)/deck/\(rel)"
        if let q = u.percentEncodedQuery, !q.isEmpty { out += "?" + q }
        if let f = u.percentEncodedFragment, !f.isEmpty { out += "#" + f }
        return out
    }

    // MARK: Links that leave the page

    /// Where a link the page hands the app goes: a bundled deck file opens from disk (as the classic Open in browser did), a
    /// post on its public page (its `canonical`, else `<hub>/blog/<slug>`), a web link as itself. Nil: nowhere (ignored).
    public static func external(_ s: String, at loc: Location, hub: String) -> URL? {
        guard let u = URL(string: s), let scheme = u.scheme?.lowercased() else { return nil }
        if scheme == "http" || scheme == "https" || scheme == "mailto" { return u }
        guard scheme == LearnShared.scheme else { return nil }
        let path = u.path
        if path.hasPrefix("/deck/"), let f = inside(loc.deck, String(path.dropFirst(6))) { return URL(fileURLWithPath: f) }
        if path.hasPrefix("/blog/") {
            let slug = String(path.dropFirst(6)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            guard isSlug(slug) else { return URL(string: hub + "/blog") }
            return canonical(slug, learn: loc.learn) ?? URL(string: "\(hub)/blog/\(slug)")
        }
        return nil
    }

    static func canonical(_ slug: String, learn: String) -> URL? {
        guard let d = FileManager.default.contents(atPath: learn + "/posts.json"),
              let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any], let posts = o["posts"] as? [[String: Any]],
              let p = posts.first(where: { $0["slug"] as? String == slug }), let c = p["canonical"] as? String, c.hasPrefix("https://") else { return nil }
        return URL(string: c)
    }

    public static func enc(_ s: String) -> String { s.addingPercentEncoding(withAllowedCharacters: .alphanumerics.union(CharacterSet(charactersIn: "-_.~"))) ?? s }

    /// The host page's URL, opened at `hash`.
    public static func pageURL(hash: String? = nil) -> URL {
        URL(string: "\(origin)/index.html" + (hash ?? ""))!
    }

    /// The deck commit as `deck/.deck-ref` records it ("origin/main abc1234" → "abc1234").
    public static func deckRef(deck: String) -> String? {
        (try? String(contentsOfFile: deck + "/.deck-ref", encoding: .utf8))?.split(separator: " ").last.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
    }

    // MARK: The host page

    /// The page the web view loads: the saved stylesheet and script, then `oneroofLearnMount(options)` (called by the app once
    /// the page is ready, and again on a theme change). The bridge posts to the app; links that leave the page go to the app
    /// too. Debug aid: every http(s) resource the page or a card frame loads is reported (`{type: "net"}`); offline there are none.
    public static let hostPage = """
    <!doctype html>
    <html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
    <title>Learn</title>
    <link rel="stylesheet" href="embed/ggae.css">
    <style>
    html,body{margin:0;min-height:100%;background:var(--or-bg,#f4f6fa);color:var(--or-ink,#0e1628)}
    #learn{min-height:100vh}
    </style>
    </head><body><div id="learn"></div>
    <script src="embed/ggae.js"></script>
    <script>
    (function () {
      function post(m) { try { window.webkit.messageHandlers.oneroofLearn.postMessage(m); } catch (e) { if (window.oneroofLearnPost) window.oneroofLearnPost(m); } }
      var bridge = {
        play: function (slug, queue) { post({ type: "play", slug: slug, queue: queue || [] }); },
        useInSession: function (slug) { post({ type: "useInSession", slug: slug }); },
        openFolder: function (path) { post({ type: "openFolder", path: path }); },
        openExternal: function (url) { post({ type: "openExternal", url: url }); }
      };
      var el = document.getElementById("learn"), unmount = null, dark = null;
      window.oneroofLearnTheme = function (vars) {
        for (var k in vars) document.documentElement.style.setProperty("--or-" + k, vars[k]);
      };
      window.oneroofLearnMount = function (o) {
        o = o || {};
        if (o.vars) window.oneroofLearnTheme(o.vars);
        if (typeof o.autoAdvance === "boolean") { try { localStorage.setItem("ggae.autoAdvance", o.autoAdvance ? "on" : "off"); } catch (e) {} }
        if (unmount && dark === !!o.dark) return;      // a colour change only: the CSS variables re-colour the page
        if (unmount) { unmount(); unmount = null; }
        dark = !!o.dark;
        if (!window.GGAE) { post({ type: "error", message: "the saved ggae.js did not load" }); return; }
        var tokens = {};
        ["bg","panel","panel2","line","ink","muted","acc","acc2","warn","hot","blue","heat0","heat1","heat2","heat3","heat4"].forEach(function (k) { tokens[k] = "var(--or-" + k + ")"; });
        unmount = window.GGAE.mount(el, { site: "oneroof", api: "\(origin)", player: true, skin: "oneroof", dark: dark,
          tokens: tokens, fonts: o.fonts, bridge: bridge });
        post({ type: "mounted", version: String(window.GGAE.version || "") });
        post({ type: "hash", hash: location.hash });
      };
      window.oneroofLearnSearch = function (q) {
        var i = document.querySelector(".ae-search input"); if (!i) return false;
        var set = Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, "value").set;
        set.call(i, q || ""); i.dispatchEvent(new Event("input", { bubbles: true })); i.focus(); return true;
      };
      window.oneroofLearnPauseMedia = function () {
        var docs = [document];
        document.querySelectorAll("iframe").forEach(function (f) { try { if (f.contentDocument) docs.push(f.contentDocument); } catch (e) {} });
        docs.forEach(function (d) { d.querySelectorAll("audio,video").forEach(function (m) { try { m.pause(); } catch (e) {} }); });
      };
      window.addEventListener("hashchange", function () { post({ type: "hash", hash: location.hash }); });
      if (window.oneroofLearnOptions) window.oneroofLearnMount(window.oneroofLearnOptions);
      else post({ type: "ready" });
    })();
    </script>
    </body></html>
    """

    /// Run in every frame before its own scripts (the card pages too): tells the app when a page starts playing audio (One
    /// Roof's player pauses, so audio never doubles), and reports any http(s) resource load (debug: offline there are none).
    public static let frameScript = """
    (function () {
      function post(m) { try { window.webkit.messageHandlers.oneroofLearn.postMessage(m); } catch (e) {} }
      document.addEventListener("play", function (e) { if (e.target && /^(AUDIO|VIDEO)$/.test(e.target.tagName)) post({ type: "mediaPlay" }); }, true);
      try {
        new PerformanceObserver(function (l) {
          l.getEntries().forEach(function (x) { if (/^https?:/i.test(x.name)) post({ type: "net", url: x.name }); });
        }).observe({ type: "resource", buffered: true });
      } catch (e) {}
    })();
    """
}

// MARK: - sha256

public func sha256Hex(_ data: Data) -> String {
    var digest = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
    data.withUnsafeBytes { _ = CC_SHA256($0.baseAddress, CC_LONG(data.count), &digest) }
    return digest.map { String(format: "%02x", $0) }.joined()
}
