import XCTest
@testable import OneRoofCore

/// LAB-1762 · Learn is the shared Agentic Engineering page, saved in the app at build (LAB-1834) and served to its web view from
/// `oneroof-learn://hub/…` (LAB-1835). A temporary learn folder and deck stand in for the app's Resources.
final class LearnSharedTests: XCTestCase {
    var root = ""
    var loc: LearnShared.Location { LearnShared.Location(learn: root + "/learn", deck: root + "/deck") }
    let js = Data("window.GGAE={mount:function(){return function(){}},version:'3'};".utf8)

    override func setUpWithError() throws {
        root = NSTemporaryDirectory() + "learn-shared-\(UUID().uuidString)"
        let fm = FileManager.default
        try fm.createDirectory(atPath: root + "/learn/cards", withIntermediateDirectories: true)
        try fm.createDirectory(atPath: root + "/deck/content/cards/ship/evidence-check/evidence-check_audio", withIntermediateDirectories: true)
        try fm.createDirectory(atPath: root + "/deck/content/cards/influences/amodei", withIntermediateDirectories: true)
        try fm.createDirectory(atPath: root + "/deck/content/field-manual", withIntermediateDirectories: true)
        func put(_ p: String, _ s: String) { fm.createFile(atPath: root + "/" + p, contents: Data(s.utf8)) }
        put("deck/content/catalog.json", "{}")
        put("deck/content/cards/ship/evidence-check/evidence-check.html", "<html>card</html>")
        put("deck/content/cards/ship/evidence-check/evidence-check_audio/01.mp3", "0123456789")
        put("deck/content/cards/influences/amodei/photo.webp", "img")
        put("deck/content/field-manual/home.html", "<html>home</html>")
        put("deck/.deck-ref", "origin/main 70b453c\n")
        let cdn = "https://content.gabblegrid.ai"
        let card: (String, String) -> String = { slug, path in
            #"{"slug":"\#(slug)","title":"\#(slug)","scenes":4,"minutes":3,"url":"\#(cdn)/\#(path)","triggers":[]}"#
        }
        put("learn/catalog.json", #"""
        {"site":"zibajoon","version":"0.4.4","edition":"2026-10-30","from":"origin/main 70b453c","home":"\#(cdn)/content/field-manual/home.html",
         "bands":[{"id":"evidence","start_here":[\#(card("evidence-check", "content/cards/ship/evidence-check/evidence-check.html"))],
           "tracks":[{"id":"ship","cards":[\#(card("evidence-check", "content/cards/ship/evidence-check/evidence-check.html")),
             \#(card("not-bundled", "content/cards/ship/not-bundled/not-bundled.html"))]},
             {"id":"influences","cards":[{"slug":"amodei","title":"Dario Amodei","scenes":3,"minutes":2,"url":"\#(cdn)/content/cards/influences/amodei/amodei.html","photo":"\#(cdn)/content/cards/influences/amodei/photo.webp","triggers":[]}]}]}],
         "paths":[],"counts":{"cards":3,"tracks":2}}
        """#)
        put("learn/posts.json", #"{"site":"zibajoon","posts":[{"slug":"agentic-engineering","title":"A","date":"2026-08-20","minutes":5,"canonical":"https://console.zibajoon.com/blog/agentic-engineering"},{"slug":"no-canonical","title":"B","date":"2026-08-21","minutes":3}]}"#)
        put("learn/cards/evidence-check.json", #"{"slug":"evidence-check","skill":"---\nname: evidence-check\n---\nBody","dependencies":[],"scenes":[],"profile":null,"sources":[]}"#)
        put("learn/cards/amodei.json", #"{"slug":"amodei","skill":"","dependencies":[],"scenes":[],"profile":null,"sources":[]}"#)
        put("learn/ggae.css", ".ae-root{}")
        fm.createFile(atPath: root + "/learn/ggae.js", contents: js)
        writeManifest(sha: sha256Hex(js), details: 2)
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(atPath: root) }

    func writeManifest(sha: String, details: Int) {
        let m = #"{"hub":"https://console.zibajoon.com","site":"zibajoon","fetchedAt":"2026-10-30T20:00:00Z","edition":"2026-10-30","version":"0.4.4","catalogFrom":"origin/main 70b453c","deckRef":"70b453c","ggaeSha256":"\#(sha)","ggaeCssSha256":"x","ggaeFrom":"hub","cards":3,"cardDetails":\#(details),"posts":2}"#
        FileManager.default.createFile(atPath: root + "/learn/learn-manifest.json", contents: Data(m.utf8))
    }

    func json(_ r: LearnShared.Response) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: r.body) as? [String: Any])
    }

    // MARK: Manifest check (LAB-1834)

    func test_manifest_complete_folder_has_no_problems_and_locates() {
        XCTAssertEqual(LearnShared.problems(learn: loc.learn), [])
        XCTAssertEqual(LearnShared.locate(ae: root, deck: root + "/deck", environment: [:]), loc)
        XCTAssertEqual(LearnShared.manifest(learn: loc.learn)?.cards, 3)
        XCTAssertEqual(LearnShared.deckRef(deck: loc.deck), "70b453c")
    }

    func test_manifest_sha_mismatch_missing_file_and_missing_details_are_problems() throws {
        writeManifest(sha: String(repeating: "0", count: 64), details: 2)
        XCTAssertEqual(LearnShared.problems(learn: loc.learn), ["ggae.js does not match the manifest's sha256"])
        writeManifest(sha: sha256Hex(js), details: 5)
        XCTAssertEqual(LearnShared.problems(learn: loc.learn), ["2 card details saved, the manifest says 5"])
        try FileManager.default.removeItem(atPath: loc.learn + "/posts.json")
        XCTAssertEqual(LearnShared.problems(learn: loc.learn), ["posts.json missing"])
        XCTAssertNil(LearnShared.locate(ae: root, deck: loc.deck, environment: [:]), "an incomplete copy falls back to the classic screens")
        XCTAssertNil(LearnShared.locate(ae: root, deck: nil, environment: [:]), "no deck: classic screens")
    }

    func test_manifest_env_override_points_at_another_folder() {
        XCTAssertEqual(LearnShared.locate(ae: "/nowhere", deck: loc.deck, environment: ["ONEROOF_LEARN_DIR": loc.learn])?.learn, loc.learn)
    }

    func test_sha256_known_vector() {
        XCTAssertEqual(sha256Hex(Data("abc".utf8)), "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    }

    // MARK: Scheme handler routes (LAB-1835)

    func test_scheme_host_page_mounts_the_saved_embed_as_oneroof_with_the_bridge() {
        let r = LearnShared.respond(path: "/index.html", at: loc)
        XCTAssertEqual(r.status, 200)
        XCTAssertTrue(r.mime.hasPrefix("text/html"))
        let html = String(decoding: r.body, as: UTF8.self)
        for s in ["embed/ggae.css", "embed/ggae.js", #"site: "oneroof""#, #"api: "oneroof-learn://hub""#, "player: true", "bridge: bridge",
                  "useInSession", "openFolder", "openExternal", "messageHandlers.oneroofLearn"] {
            XCTAssertTrue(html.contains(s), s)
        }
        XCTAssertFalse(html.contains("http://") || html.contains("https://"), "the host page loads nothing from the network")
        XCTAssertEqual(LearnShared.respond(path: "/", at: loc).body, r.body)
    }

    func test_scheme_embed_files() {
        let r = LearnShared.respond(path: "/embed/ggae.js", at: loc)
        XCTAssertEqual(r.status, 200)
        XCTAssertEqual(r.body, js)
        XCTAssertTrue(r.mime.hasPrefix("text/javascript"))
        XCTAssertTrue(LearnShared.respond(path: "/blog/embed/ggae.css", at: loc).mime.hasPrefix("text/css"))
    }

    func test_scheme_catalog_rewrite_points_card_pages_photos_and_home_at_the_deck() throws {
        let r = LearnShared.respond(path: "/ae/api/catalog", at: loc)
        XCTAssertEqual(r.status, 200)
        let c = try json(r)
        XCTAssertEqual(c["home"] as? String, "oneroof-learn://hub/deck/content/field-manual/home.html")
        let band = try XCTUnwrap((c["bands"] as? [[String: Any]])?.first)
        XCTAssertEqual((band["start_here"] as? [[String: Any]])?.first?["url"] as? String,
                       "oneroof-learn://hub/deck/content/cards/ship/evidence-check/evidence-check.html")
        let tracks = try XCTUnwrap(band["tracks"] as? [[String: Any]])
        let ship = try XCTUnwrap(tracks[0]["cards"] as? [[String: Any]])
        XCTAssertEqual(ship[1]["url"] as? String, "https://content.gabblegrid.ai/content/cards/ship/not-bundled/not-bundled.html",
                       "a page the deck lacks is left as it was")
        let amodei = try XCTUnwrap((tracks[1]["cards"] as? [[String: Any]])?.first)
        XCTAssertEqual(amodei["photo"] as? String, "oneroof-learn://hub/deck/content/cards/influences/amodei/photo.webp")
        XCTAssertEqual((c["counts"] as? [String: Any])?["cards"] as? Int, 3, "everything else is untouched")
    }

    func test_scheme_card_details_saved_missing_and_bad_slug() throws {
        let ok = LearnShared.respond(path: "/ae/api/card/evidence-check", at: loc)
        XCTAssertEqual(ok.status, 200)
        XCTAssertEqual(try json(ok)["slug"] as? String, "evidence-check")
        let missing = LearnShared.respond(path: "/ae/api/card/not-bundled", at: loc)
        XCTAssertEqual(missing.status, 404)
        XCTAssertEqual(try json(missing)["error"] as? String, "no details for this card")
        XCTAssertEqual(LearnShared.respond(path: "/ae/api/card/..%2Fx", at: loc).status, 400)
        XCTAssertEqual(LearnShared.respond(path: "/ae/api/card/Bad_Slug", at: loc).status, 400)
    }

    func test_scheme_posts_are_the_saved_list() throws {
        let r = LearnShared.respond(path: "/blog/api/posts", at: loc)
        XCTAssertEqual(r.status, 200)
        XCTAssertEqual((try json(r)["posts"] as? [Any])?.count, 2)
    }

    func test_scheme_deck_files_with_byte_ranges_and_no_escape() {
        let page = LearnShared.respond(path: "/deck/content/cards/ship/evidence-check/evidence-check.html", at: loc)
        XCTAssertEqual(page.status, 200)
        XCTAssertEqual(String(decoding: page.body, as: UTF8.self), "<html>card</html>")
        let audio = LearnShared.respond(path: "/deck/content/cards/ship/evidence-check/evidence-check_audio/01.mp3", range: "bytes=2-5", at: loc)
        XCTAssertEqual(audio.status, 206)
        XCTAssertEqual(String(decoding: audio.body, as: UTF8.self), "2345")
        XCTAssertEqual(audio.headers["Content-Range"], "bytes 2-5/10")
        XCTAssertEqual(audio.mime, "audio/mpeg")
        XCTAssertEqual(audio.allHeaders["Content-Length"], "4")
        XCTAssertEqual(LearnShared.respond(path: "/deck/content/../../learn/ggae.js", at: loc).status, 404, "no path out of the deck")
        XCTAssertEqual(LearnShared.respond(path: "/deck/content/cards", at: loc).status, 404, "a folder is not a file")
    }

    func test_scheme_missing_file_is_404() {
        XCTAssertEqual(LearnShared.respond(path: "/deck/content/cards/nope.html", at: loc).status, 404)
        XCTAssertEqual(LearnShared.respond(path: "/something/else", at: loc).status, 404)
        try? FileManager.default.removeItem(atPath: loc.learn + "/catalog.json")
        XCTAssertEqual(LearnShared.respond(path: "/ae/api/catalog", at: loc).status, 503)
    }

    func test_byte_ranges() {
        XCTAssertEqual(LearnShared.byteRange("bytes=0-", size: 10), 0..<10)
        XCTAssertEqual(LearnShared.byteRange("bytes=0-1", size: 10), 0..<2)
        XCTAssertEqual(LearnShared.byteRange("bytes=-3", size: 10), 7..<10)
        XCTAssertEqual(LearnShared.byteRange("bytes=4-99", size: 10), 4..<10)
        XCTAssertNil(LearnShared.byteRange("bytes=10-", size: 10))
        XCTAssertNil(LearnShared.byteRange("bytes=0-1,4-5", size: 10))
        XCTAssertNil(LearnShared.byteRange("items=0-1", size: 10))
    }

    // MARK: Links that leave the page, deep links, theme

    func test_external_links() {
        let hub = "https://console.zibajoon.com"
        XCTAssertEqual(LearnShared.external("oneroof-learn://hub/blog/agentic-engineering", at: loc, hub: hub)?.absoluteString,
                       "https://console.zibajoon.com/blog/agentic-engineering")
        XCTAssertEqual(LearnShared.external("oneroof-learn://hub/blog/no-canonical", at: loc, hub: hub)?.absoluteString, "\(hub)/blog/no-canonical")
        XCTAssertEqual(LearnShared.external("oneroof-learn://hub/deck/content/field-manual/home.html", at: loc, hub: hub)?.isFileURL, true)
        XCTAssertNil(LearnShared.external("oneroof-learn://hub/deck/content/../../etc/passwd", at: loc, hub: hub))
        XCTAssertEqual(LearnShared.external("https://example.com/x", at: loc, hub: hub)?.host, "example.com")
        XCTAssertNil(LearnShared.external("javascript:alert(1)", at: loc, hub: hub))
        XCTAssertNil(LearnShared.external("file:///etc/passwd", at: loc, hub: hub))
    }

    func test_deep_link_hashes() {
        XCTAssertEqual(LearnShared.hash(.card("loops-first")), "#ae/card/loops-first")
        XCTAssertEqual(LearnShared.hash(.band("context", track: "vault")), "#ae/band/context/vault")
        XCTAssertEqual(LearnShared.hash(.band("context", track: nil)), "#ae/band/context")
        XCTAssertEqual(LearnShared.hash(.radio), "#ae/radio")
        XCTAssertNil(LearnShared.hash(.help("/x/help.md")))
        XCTAssertNil(LearnShared.hash(.none))
        XCTAssertEqual(LearnShared.pageURL(hash: "#ae/radio").absoluteString, "oneroof-learn://hub/index.html#ae/radio")
    }

    func test_theme_vars_cover_every_colour_role_and_follow_dark() throws {
        let roles = ["bg", "panel", "panel2", "line", "ink", "muted", "acc", "acc2", "warn", "hot", "blue", "heat0", "heat1", "heat2", "heat3", "heat4"]
        let light = LearnShared.vars(ThemeName.daylight.tokens), dark = LearnShared.vars(ThemeName.midnight.tokens)
        XCTAssertEqual(Set(light.keys), Set(roles))
        XCTAssertEqual(light["bg"], ThemeName.daylight.tokens.window.css)
        XCTAssertNotEqual(light["bg"], dark["bg"])
        let o = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(LearnShared.mountOptions(ThemeName.midnight.tokens).utf8)) as? [String: Any])
        XCTAssertEqual(o["dark"] as? Bool, true)
        XCTAssertNotNil((o["fonts"] as? [String: String])?["mono"])
    }

    /// LAB-1894 · the classic screens and their toggle are gone: a settings file saved by 1.9.32–1.9.34 with `learnClassic`
    /// (on or off) still loads, keeps every other Learn setting, and the key is not written back.
    func test_settings_old_learn_classic_key_is_ignored_and_dropped() throws {
        let old = #"{"learnClassic": true, "learnAutoAdvance": false, "learnFolders": ["~/notes"]}"#
        let s = try JSONDecoder().decode(AppSettings.self, from: Data(old.utf8))
        XCTAssertFalse(s.learnAutoAdvance)
        XCTAssertEqual(s.learnFolders, ["~/notes"])
        let written = String(decoding: try JSONEncoder().encode(s), as: UTF8.self)
        XCTAssertFalse(written.contains("learnClassic"))
        XCTAssertNoThrow(try JSONDecoder().decode(AppSettings.self, from: Data(#"{"learnClassic": false}"#.utf8)))
    }
}
