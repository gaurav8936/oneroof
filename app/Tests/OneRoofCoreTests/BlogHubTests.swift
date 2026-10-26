import XCTest
@testable import OneRoofCore

/// LAB-1251 · Learn › Writing from the Zibajoon blog hub: the API's JSON, the post HTML as Markdown, and the cache
/// LearnPosts reads. Fixtures are trimmed copies of the hub's real replies (2026-10-26); no network.
final class BlogHubTests: XCTestCase {
    static let base = "https://hub.test"

    static let listJSON = #"""
    {"site":"zibajoon","generatedAt":"2026-10-26T18:00:00.000Z","posts":[
     {"slug":"one-roof-builds-one-roof","title":"One Roof builds One Roof: 48 hours of a self-hosting dev loop","subtitle":"One engineer, 48 hours.","summary":"A measured case study.","date":"2026-10-19","updated":null,"authors":["Gaurav Narasimhan"],"status":"published","tags":["agents","velocity"],"series":"Field notes","minutes":15,"links":[],"hero":null,"heroAlt":null,"pdf":null,"canonical":"https://hub.test/blog/one-roof-builds-one-roof"},
     {"slug":"agentic-engineering","title":"Agentic engineering","subtitle":"The system around the agent.","summary":"Part 1.","date":"2026-08-20","updated":null,"authors":["Gaurav Narasimhan"],"status":"published","tags":["series"],"series":"Agentic engineering","minutes":6,"links":[],"hero":null,"heroAlt":null,"pdf":null,"canonical":"https://hub.test/blog/agentic-engineering"},
     {"slug":"../escape","title":"Bad","date":"2026-08-21"}
    ]}
    """#

    static let postHTML = #"""
    <div class="bl-chart" data-spec="{&#x22;kind&#x22;:&#x22;kpis&#x22;,&#x22;title&#x22;:&#x22;One engineer · 48 hours&#x22;,&#x22;sub&#x22;:&#x22;tmp/<project>/&#x22;}"><p class="bl-stepdiagram-loading">One engineer · 48 hours</p></div>
    <aside class="bl-callout" data-kind="note">
    <p class="bl-callout-title">What "landed" means</p>
    <p>A commit counts once it is on <code>ganarasi/live</code>.</p>
    </aside>
    <p>The <a href="/blog/agentic-engineering">first post</a> said <em>why</em>; see <a href="/about">about</a> &amp; <strong>One Roof </strong>today.</p>
    <h2 id="self-hosting">Self-hosting: the IDE<a href="#self-hosting" class="bl-anchor" aria-label="Link to this section">#</a></h2>
    <figure class="bl-figure"><img src="https://hub.test/blog/assets/one-roof-builds-one-roof/desk-board.png" alt="Linear &amp; One Roof&#x27;s Board" loading="lazy"><figcaption>The Board groups every session.</figcaption></figure>
    <p><img src="https://elsewhere.test/x.png" alt="other"></p>
    <ul>
    <li>what the agent <strong>already knows</strong>,
    <ul><li>nested one</li></ul></li>
    <li>2. and a literal * star_</li>
    </ul>
    <ol start="3"><li><p>Third</p></li><li>Fourth</li></ol>
    <table><thead><tr><th></th><th>Hosted</th></tr></thead><tbody><tr><td><strong>Where</strong></td><td>a | pipe</td></tr></tbody></table>
    <div class="bl-code"><pre><code class="hljs language-markdown"><span class="hljs-section"># Title</span>
    a &lt;b&gt; line</code></pre></div>
    <p>Odds <span class="katex"><span class="katex-mathml"><math><semantics><mrow><mi>p</mi></mrow><annotation encoding="application/x-tex">p^2</annotation></semantics></math></span><span class="katex-html">p2</span></span> here.</p>
    <p>1. Not a list</p>
    <blockquote>
    <p><strong>Done when:</strong> the suite passes.</p>
    </blockquote>
    <div class="bl-stepdiagram" data-spec="{&#x22;title&#x22;:&#x22;The self-hosting loop&#x22;}"><p class="bl-stepdiagram-loading">The self-hosting loop</p></div>
    """#

    static func postJSON(_ slug: String, title: String, html: String, date: String = "2026-10-19") -> String {
        let h = String(data: try! JSONSerialization.data(withJSONObject: [html], options: [.fragmentsAllowed]), encoding: .utf8)!.dropFirst().dropLast()
        return #"{"site":"zibajoon","post":{"slug":"\#(slug)","title":"\#(title)","subtitle":"Sub","summary":"Sum","date":"\#(date)","updated":null,"#
            + #""authors":["G"],"status":"published","tags":["agents"],"series":"Field notes","minutes":15,"links":[],"hero":null,"#
            + #""canonical":"https://hub.test/blog/\#(slug)"},"html":\#(h),"toc":[],"words":100,"needs":{"diagrams":true},"newer":null,"older":null}"#
    }

    func testTheSiteIsNamedLikeTheHubsDomain() {
        XCTAssertEqual(BlogHub.site(forBase: "https://console.zibajoon.com"), "zibajoon")
        XCTAssertEqual(BlogHub.site(forBase: "http://localhost:3954"), "")
        XCTAssertEqual(BlogHub.site(forBase: "http://127.0.0.1:9"), "")
        XCTAssertEqual(BlogHub.name(site: ""), "blog")
        XCTAssertEqual(BlogHub.name(site: "zibajoon"), "Zibajoon blog")
        XCTAssertEqual(BlogHub.defaultBase, "https://console.zibajoon.com", "the hub the owner chose (LAB-1251)")
    }

    func testListDecodesAndDropsUnsafeSlugs() throws {
        let posts = try XCTUnwrap(BlogHub.decodeList(Data(Self.listJSON.utf8)))
        XCTAssertEqual(posts.map(\.slug), ["one-roof-builds-one-roof", "agentic-engineering"])
        XCTAssertEqual(posts[0].minutes, 15)
        XCTAssertEqual(posts[1].series, "Agentic engineering")
        XCTAssertNil(BlogHub.decodeList(Data("<html>not json</html>".utf8)))
        XCTAssertEqual(BlogHub.listURL(base: "https://x.test", site: "zibajoon")?.absoluteString, "https://x.test/blog/api/posts?site=zibajoon")
        XCTAssertEqual(BlogHub.postURL(base: "https://x.test", slug: "a-b", site: "zibajoon")?.absoluteString, "https://x.test/blog/api/posts/a-b?site=zibajoon")
    }

    func testPostHTMLBecomesMarkdownTheViewerReads() throws {
        let md = BlogHub.markdown(html: Self.postHTML, base: Self.base, canonical: "https://hub.test/blog/p") { url in
            url.hasSuffix("desk-board.png") ? "desk-board.png" : url
        }
        // Site-only blocks: one line naming them, with the web version.
        XCTAssertTrue(md.hasPrefix("*Chart: One engineer · 48 hours. Drawn on the web version ([open it](https://hub.test/blog/p)).*"), md)
        XCTAssertTrue(md.contains("*Diagram: The self-hosting loop. Drawn on the web version"))
        XCTAssertFalse(md.contains("<project>"))
        // Callout → quote with its title in bold.
        XCTAssertTrue(md.contains("> **What \"landed\" means**\n>\n> A commit counts once it is on `ganarasi/live`."), md)
        // Links: post links stay /blog/ (the reader opens them in place); other site paths get the hub's address.
        XCTAssertTrue(md.contains("The [first post](/blog/agentic-engineering) said *why*; see [about](https://hub.test/about) \\& **One Roof** today."), md)
        // Headings lose the anchor link.
        XCTAssertTrue(md.contains("\n## Self-hosting: the IDE\n"))
        // Figures: the cached file name and the caption; a foreign image keeps its address.
        XCTAssertTrue(md.contains("![Linear & One Roof's Board](desk-board.png)\n\n*The Board groups every session.*"), md)
        XCTAssertTrue(md.contains("![other](https://elsewhere.test/x.png)"))
        // Lists, nested and ordered with a start; Markdown characters in text stay text.
        XCTAssertTrue(md.contains("- what the agent **already knows**,\n  - nested one\n- 2\\. and a literal \\* star\\_"), md)
        XCTAssertTrue(md.contains("3. Third\n4. Fourth"), md)
        // Tables (escaped pipe), code (language, entities decoded, highlight spans dropped), maths as code.
        XCTAssertTrue(md.contains("|   | Hosted |\n| --- | --- |\n| **Where** | a \\| pipe |"), md)
        XCTAssertTrue(md.contains("```markdown\n# Title\na <b> line\n```"), md)
        XCTAssertTrue(md.contains("Odds `p^2` here."), md)
        XCTAssertTrue(md.contains("\n1\\. Not a list\n"), md)
        XCTAssertTrue(md.contains("> **Done when:** the suite passes."))

        // And the app's Markdown reader sees the intended blocks.
        let blocks = MarkdownDoc.parse(md)
        XCTAssertTrue(blocks.contains(.heading(level: 2, text: "Self-hosting: the IDE", anchor: MarkdownDoc.slug("Self-hosting: the IDE"))))
        XCTAssertTrue(blocks.contains(.image(alt: "Linear & One Roof's Board", source: "desk-board.png")))
        XCTAssertTrue(blocks.contains { if case .table(let h, _, let rows) = $0 { return h == ["", "Hosted"] && rows == [["**Where**", "a | pipe"]] }; return false })
        XCTAssertTrue(blocks.contains { if case .code("markdown", _) = $0 { return true }; return false })
        XCTAssertTrue(blocks.contains { if case .list(true, 3, let items) = $0 { return items.map(\.text) == ["Third", "Fourth"] }; return false })
        XCTAssertTrue(blocks.contains { if case .quote = $0 { return true }; return false })
    }

    func testImageURLsAreOnlyThisPostsAssets() {
        let imgs = BlogHub.imageURLs(Self.postHTML + #"<img src="/blog/assets/one-roof-builds-one-roof/two%20b.png"><img src="/blog/assets/other/x.png"><img src="/blog/assets/one-roof-builds-one-roof/..%2Fx">"#,
                                     base: Self.base, slug: "one-roof-builds-one-roof")
        XCTAssertEqual(imgs.map(\.file), ["desk-board.png"], "spaces, other posts' folders and path tricks are not cached")
        XCTAssertEqual(imgs.first?.url, "https://hub.test/blog/assets/one-roof-builds-one-roof/desk-board.png")
    }

    func testSyncFillsTheCacheAndLearnFoldersWinOnTheSameSlug() async throws {
        let root = NSTemporaryDirectory() + "bloghub-\(UUID().uuidString)"
        let cache = root + "/cache"
        // A post the hub no longer lists, left by an earlier sync: removed. A folder the sync did not write: kept.
        try FileManager.default.createDirectory(atPath: cache + "/gone-post", withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: cache + "/gone-post/.from-hub", contents: Data())
        try FileManager.default.createDirectory(atPath: cache + "/not-ours", withIntermediateDirectories: true)
        let replies: [String: Data] = [
            "https://hub.test/blog/api/posts?site=zibajoon": Data(Self.listJSON.utf8),
            "https://hub.test/blog/api/posts/one-roof-builds-one-roof?site=zibajoon":
                Data(Self.postJSON("one-roof-builds-one-roof", title: "One Roof builds One Roof: 48 hours", html: Self.postHTML).utf8),
            "https://hub.test/blog/api/posts/agentic-engineering?site=zibajoon":
                Data(Self.postJSON("agentic-engineering", title: "Agentic engineering", html: "<h2>Prompting is not the job</h2><p>Body.</p>", date: "2026-08-20").utf8),
            "https://hub.test/blog/assets/one-roof-builds-one-roof/desk-board.png": Data([0x89, 0x50, 0x4E, 0x47]),
        ]
        let r = await BlogHub.sync(base: Self.base, site: "zibajoon", cache: cache) { url in
            guard let d = replies[url.absoluteString] else { throw URLError(.fileDoesNotExist) }
            return d
        }
        XCTAssertEqual(r, BlogHub.SyncResult(reached: true, posts: 2, failed: 0, error: nil))
        let fm = FileManager.default
        XCTAssertTrue(fm.fileExists(atPath: cache + "/one-roof-builds-one-roof/desk-board.png"))
        XCTAssertFalse(fm.fileExists(atPath: cache + "/gone-post"))
        XCTAssertTrue(fm.fileExists(atPath: cache + "/not-ours"))
        XCTAssertNotNil(BlogHub.lastSync(cache: cache))
        let index = try String(contentsOfFile: cache + "/one-roof-builds-one-roof/index.md", encoding: .utf8)
        XCTAssertTrue(index.contains("![Linear & One Roof's Board](desk-board.png)"), "a cached image is read from beside index.md")

        let hub = LearnPosts.all(folders: [], hubCache: cache)
        XCTAssertEqual(hub.map(\.slug), ["agentic-engineering", "one-roof-builds-one-roof"])
        let p = try XCTUnwrap(hub.last)
        XCTAssertEqual(p.title, "One Roof builds One Roof: 48 hours")
        XCTAssertEqual(p.minutes, 15, "the hub's reading time, not a word count")
        XCTAssertEqual(p.series, "Field notes")
        XCTAssertEqual(p.tags, ["agents"])
        XCTAssertEqual(p.canonical, "https://hub.test/blog/one-roof-builds-one-roof")
        XCTAssertEqual(p.source, "Zibajoon blog")
        XCTAssertTrue(p.published)
        XCTAssertEqual(p.sections, ["Self-hosting: the IDE"])
        XCTAssertEqual(hub.first?.sections, ["Prompting is not the job"])

        // A Learn folder with the same slug wins; its other posts merge in.
        let local = root + "/learn"
        try fm.createDirectory(atPath: local + "/20261019_one-roof-builds-one-roof", withIntermediateDirectories: true)
        try "---\ntitle: My draft\ndate: 2026-10-19\nstatus: scheduled\n---\n\nDraft.\n".write(toFile: local + "/20261019_one-roof-builds-one-roof/index.md", atomically: true, encoding: .utf8)
        let merged = LearnPosts.all(folders: [local], hubCache: cache)
        XCTAssertEqual(merged.count, 2)
        XCTAssertEqual(merged.first { $0.slug == "one-roof-builds-one-roof" }?.title, "My draft")
        XCTAssertEqual(merged.first { $0.slug == "one-roof-builds-one-roof" }?.source, "")

        // Offline: nothing changes on disk and the result says why.
        let off = await BlogHub.sync(base: Self.base, site: "zibajoon", cache: cache) { _ in throw URLError(.notConnectedToInternet) }
        XCTAssertFalse(off.reached)
        XCTAssertNotNil(off.error)
        XCTAssertEqual(LearnPosts.all(folders: [], hubCache: cache).count, 2, "the saved copy still reads offline")
        // No cache at all: no posts (the view then says the blog could not be reached).
        XCTAssertEqual(LearnPosts.all(folders: [], hubCache: root + "/never"), [])
    }

    func testOnePostFailingKeepsItsSavedCopy() async throws {
        let cache = NSTemporaryDirectory() + "bloghub-\(UUID().uuidString)"
        let list = Data(Self.listJSON.utf8)
        let good = Data(Self.postJSON("agentic-engineering", title: "Agentic engineering", html: "<p>v1</p>").utf8)
        let first = await BlogHub.sync(base: Self.base, site: "zibajoon", cache: cache) { url in
            if url.absoluteString.contains("/posts?") { return list }
            if url.absoluteString.contains("agentic-engineering") { return good }
            throw URLError(.timedOut)
        }
        XCTAssertEqual(first.failed, 1)
        let again = await BlogHub.sync(base: Self.base, site: "zibajoon", cache: cache) { url in
            if url.absoluteString.contains("/posts?") { return list }
            throw URLError(.timedOut)
        }
        XCTAssertEqual(again.failed, 2)
        XCTAssertEqual(LearnPosts.all(folders: [], hubCache: cache).map(\.slug), ["agentic-engineering"])
    }

    func testIndexFileFrontmatterSurvivesColonsAndNewLines() {
        let m = BlogHub.Meta(slug: "a", title: "One: two", subtitle: "line\nbreak", summary: nil, date: "2026-10-19", updated: nil,
                             status: nil, tags: ["x, y", "z"], series: "Field notes", minutes: 3, canonical: nil)
        let f = BlogHub.indexFile(m, body: "Hello.")
        let meta = Foundations.frontmatter(f)
        XCTAssertEqual(meta["title"], "One: two")
        XCTAssertEqual(meta["subtitle"], "line break")
        XCTAssertEqual(meta["status"], "published")
        XCTAssertEqual(meta["tags"], "[x  y, z]")
        XCTAssertEqual(MarkdownDoc.stripFrontmatter(f), "Hello.\n")
    }
}
