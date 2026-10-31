import XCTest
@testable import OneRoofCore

/// LAB-1893 · the shared Learn page asks the app (`oneroof-learn://hub/app/…`) for what One Roof's native screens knew: its
/// search ranking, the owner's posts (hub cache + Learn folders) and a post's text, the deck folder on disk with previews, and
/// it hears the player's state. A temporary deck, post folders and hub cache stand in for the app's.
final class LearnSharedAppTests: XCTestCase {
    var root = ""

    private func card(_ slug: String, _ track: String, title: String, sub: String = "", desc: String = "", triggers: [String] = []) -> String {
        let trig = triggers.map { "\"\($0)\"" }.joined(separator: ", ")
        return #"{"slug": "\#(slug)", "track": "\#(track)", "title": "\#(title)", "subtitle": "\#(sub)", "description": "\#(desc)", "triggers": [\#(trig)], "#
            + #""skill": "content/cards/\#(track)/\#(slug)/SKILL.md", "spec": "content/cards/\#(track)/\#(slug)/spec.json", "html": "content/cards/\#(track)/\#(slug)/\#(slug).html", "#
            + #""sections": [], "scenes": 3, "est_seconds": 120}"#
    }

    private func deck() throws -> LearnDeck {
        let j = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(LearnDeckFixture.catalogJSON.utf8)) as? [String: Any])
        let bands = String(decoding: try JSONSerialization.data(withJSONObject: j["bands"] ?? []), as: UTF8.self)
        let json = """
        {"version": "0.2.0", "bands": \(bands),
         "tracks": [{"id": "infra", "intro": "Dev", "name": "Dev environment", "question": "Repos, git, worktrees, planning.", "cards": ["worktree-lane"]},
                    {"id": "rhythms", "intro": "Daily", "cards": ["next-session-handoff", "done-when"]}],
         "cards": [\(card("worktree-lane", "infra", title: "Worktree lane", sub: "One unit of work per git worktree", desc: "Run parallel sessions without collisions.", triggers: ["parallel agents"])),
                   \(card("next-session-handoff", "rhythms", title: "Next-session handoff", sub: "Write the opening message", desc: "So a fresh session resumes cold.")),
                   \(card("done-when", "rhythms", title: "Done when", sub: "A goal with a stop condition", desc: "The check that proves it."))]}
        """
        return try XCTUnwrap(LearnDeck.parse(Data(json.utf8), root: root + "/deck"))
    }

    override func setUpWithError() throws {
        root = NSTemporaryDirectory() + "learn-app-\(UUID().uuidString)"
        let fm = FileManager.default
        for d in ["deck/content/cards/rhythms/done-when/done-when_audio", "deck/content/cards/rhythms/next-session-handoff", "posts/20261001_my-notes", "hub/agentic-engineering", "hub/one-workspace"] {
            try fm.createDirectory(atPath: root + "/" + d, withIntermediateDirectories: true)
        }
        func put(_ p: String, _ s: String) { fm.createFile(atPath: root + "/" + p, contents: Data(s.utf8)) }
        put("deck/content/cards/rhythms/done-when/SKILL.md", "---\nname: done-when\n---\n# Done when\nBody.")
        put("deck/content/cards/rhythms/done-when/video.yaml", "fps: 30\n")
        put("deck/content/cards/rhythms/done-when/done-when.html", "<html></html>")
        put("deck/content/cards/rhythms/done-when/done-when_audio/01.mp3", "0123")
        put("deck/content/cards/rhythms/done-when/done-when_audio/02.mp3", "4567")
        put("deck/content/cards/rhythms/done-when/.DS_Store", "x")
        fm.createFile(atPath: root + "/deck/content/cards/rhythms/done-when/photo.webp", contents: Data([0xFF, 0xD8, 0x00, 0x9F]))
        put("deck/content/cards/rhythms/done-when/long.txt", (1...450).map { "line \($0)" }.joined(separator: "\n"))
        put("posts/20261001_my-notes/index.md", "---\ntitle: My own notes\ndate: 2026-10-01\nstatus: published\n---\nIntro.\n\n## First part\n![d](diagram.png)\n")
        put("posts/20261001_my-notes/diagram.png", "png")
        put("hub/agentic-engineering/index.md", "---\ntitle: Agentic engineering\ndate: 2026-08-20\nstatus: published\nseries: Agentic engineering\ncanonical: https://console.zibajoon.com/blog/agentic-engineering\nsource: Zibajoon blog\n---\nThe body.\n")
        put("hub/one-workspace/index.md", "---\ntitle: One workspace\ndate: 2026-09-25\nstatus: published\nsource: Zibajoon blog\n---\nWorkspace body.\n")
        put("saved-posts.json", #"{"posts":[{"slug":"agentic-engineering","title":"Agentic engineering (saved)","date":"2026-08-20","minutes":5,"canonical":"https://console.zibajoon.com/blog/agentic-engineering"}]}"#)
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(atPath: root) }

    func json(_ r: LearnShared.Response?) throws -> [String: Any] {
        let r = try XCTUnwrap(r)
        XCTAssertEqual(r.status, 200)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: r.body) as? [String: Any])
    }

    func app(posts: [LearnPost]? = nil) throws -> LearnSharedApp {
        LearnSharedApp(deck: try deck(), deckRoot: root + "/deck", posts: posts, postsNote: "note", postsOffline: false)
    }

    // MARK: (7) search: One Roof's ranking

    func test_search_every_word_first_else_the_best_matches() throws {
        let a = try app()
        XCTAssertEqual(a.search("parallel agents"), ["worktree-lane"], "every word in one card: that card")
        XCTAssertEqual(a.search("how do I run two agents in parallel?").first, "worktree-lane", "no card has every word: ranked")
        XCTAssertEqual(a.search("   "), [])
        let r = try json(a.respond(path: "/app/search", query: "q=stop%20condition"))
        XCTAssertEqual(r["cards"] as? [String], ["done-when"])
        XCTAssertNil(a.respond(path: "/ae/api/catalog", query: nil), "not an app path: LearnShared answers it")
    }

    // MARK: (1)(2) posts

    func test_posts_merge_learn_folders_and_the_hub_cache_local_flagged() throws {
        let posts = LearnSharedApp.posts(folders: [root + "/posts"], hubCache: root + "/hub", saved: root + "/saved-posts.json")
        XCTAssertEqual(posts.map(\.slug), ["agentic-engineering", "one-workspace", "my-notes"])
        let r = try json(try app(posts: posts).respond(path: "/app/posts", query: nil))
        let list = try XCTUnwrap(r["posts"] as? [[String: Any]])
        XCTAssertEqual(list.map { $0["local"] as? Bool }, [false, false, true])
        XCTAssertEqual(list[0]["title"] as? String, "Agentic engineering", "the hub's cache, not the saved list")
        XCTAssertEqual(r["note"] as? String, "note")
        XCTAssertEqual(r["offline"] as? Bool, false)
    }

    func test_posts_never_synced_fall_back_to_the_list_saved_at_build() throws {
        let posts = LearnSharedApp.posts(folders: [root + "/posts"], hubCache: root + "/no-cache", saved: root + "/saved-posts.json")
        XCTAssertEqual(posts.map(\.slug), ["agentic-engineering", "my-notes"])
        XCTAssertEqual(posts[0].source, "saved")
        let r = try XCTUnwrap(try app(posts: posts).respond(path: "/app/post/agentic-engineering", query: nil))
        XCTAssertEqual(r.status, 404, "a saved entry has no text on this Mac")
    }

    func test_posts_not_read_yet_answer_null() throws {
        let r = try json(try app(posts: nil).respond(path: "/app/posts", query: nil))
        XCTAssertTrue(r["posts"] is NSNull)
    }

    func test_post_text_for_the_reader_and_its_files() throws {
        let a = try app(posts: LearnSharedApp.posts(folders: [root + "/posts"], hubCache: root + "/hub", saved: nil))
        let r = try json(a.respond(path: "/app/post/my-notes", query: nil))
        XCTAssertEqual(r["markdown"] as? String, "Intro.\n\n## First part\n![d](diagram.png)\n")
        XCTAssertEqual(r["sections"] as? [String], ["First part"])
        XCTAssertEqual(r["base"] as? String, "oneroof-learn://hub/app/post-file/my-notes")
        XCTAssertEqual(r["status"] as? String, "published")
        let hub = try json(a.respond(path: "/app/post/agentic-engineering", query: nil))
        XCTAssertEqual(hub["canonical"] as? String, "https://console.zibajoon.com/blog/agentic-engineering")
        let img = try XCTUnwrap(a.respond(path: "/app/post-file/my-notes/diagram.png", query: nil))
        XCTAssertEqual(img.status, 200); XCTAssertEqual(img.mime, "image/png"); XCTAssertEqual(img.body, Data("png".utf8))
        XCTAssertEqual(a.respond(path: "/app/post-file/my-notes/../../hub/one-workspace/index.md", query: nil)?.status, 404)
        XCTAssertEqual(a.respond(path: "/app/post/nope", query: nil)?.status, 404)
        XCTAssertEqual(a.respond(path: "/app/post/..%2f", query: nil)?.status, 404)
    }

    func test_posts_note_says_where_they_came_from() throws {
        let posts = LearnSharedApp.posts(folders: [root + "/posts"], hubCache: root + "/hub", saved: nil)
        let hubOnly = posts.filter { !$0.source.isEmpty }
        XCTAssertEqual(LearnSharedApp.postsNote(posts, feed: .reached, savedAt: "10:42", blog: "Zibajoon blog"), "From the Zibajoon blog · updated 10:42 · plus your Learn folders")
        XCTAssertEqual(LearnSharedApp.postsNote(hubOnly, feed: .offline("timed out"), savedAt: "yesterday", blog: "Zibajoon blog"), "Offline · the copy saved yesterday")
        XCTAssertEqual(LearnSharedApp.postsNote(hubOnly, feed: .loading, savedAt: "", blog: "Zibajoon blog"), "From the Zibajoon blog · checking for new posts…")
        XCTAssertEqual(LearnSharedApp.postsNote([], feed: .reached, savedAt: "", blog: "Zibajoon blog"), "The Zibajoon blog has no posts yet.")
        XCTAssertTrue(LearnSharedApp.postsNote([], feed: .offline("x"), savedAt: "", blog: "Zibajoon blog").hasPrefix("Can't reach the Zibajoon blog (x)"))
    }

    // MARK: (6) the deck folder on disk

    func test_folder_lists_the_disk_folders_first_hidden_left_out_with_sizes() throws {
        let a = try app()
        let r = try json(a.respond(path: "/app/folder", query: "path=content/cards/rhythms/done-when"))
        let e = try XCTUnwrap(r["entries"] as? [[String: Any]])
        XCTAssertEqual(e.map { $0["name"] as? String }, ["done-when_audio", "done-when.html", "long.txt", "photo.webp", "SKILL.md", "video.yaml"])
        XCTAssertEqual(e[0]["size"] as? String, "2 clips"); XCTAssertEqual(e[0]["dir"] as? Bool, true); XCTAssertEqual(e[0]["kind"] as? String, "audio")
        XCTAssertEqual(e[0]["path"] as? String, "content/cards/rhythms/done-when/done-when_audio")
        XCTAssertEqual(e.first { $0["name"] as? String == "video.yaml" }?["size"] as? String, "8 B")
        let up = try json(a.respond(path: "/app/folder", query: "path=content/cards/rhythms"))
        XCTAssertEqual((up["entries"] as? [[String: Any]])?.map { "\($0["name"]!) \($0["size"]!)" }, ["done-when 6 items", "next-session-handoff 0 items"])
        XCTAssertEqual(a.respond(path: "/app/folder", query: "path=../")?.status, 404)
        XCTAssertEqual(a.respond(path: "/app/folder", query: "path=content/cards/rhythms/done-when/SKILL.md")?.status, 404, "a file is not a folder")
        XCTAssertEqual(a.respond(path: "/app/folder", query: "path=%2Fetc")?.status, 404)
    }

    func test_file_preview_text_markdown_cut_and_not_text() throws {
        let a = try app()
        let md = try json(a.respond(path: "/app/file", query: "path=content/cards/rhythms/done-when/SKILL.md"))
        XCTAssertEqual(md["text"] as? String, "---\nname: done-when\n---\n# Done when\nBody.")
        XCTAssertEqual(md["markdown"] as? Bool, true); XCTAssertEqual(md["cut"] as? Bool, false)
        let long = try json(a.respond(path: "/app/file", query: "path=content/cards/rhythms/done-when/long.txt"))
        XCTAssertEqual((long["text"] as? String)?.split(separator: "\n").count, 400)
        XCTAssertEqual(long["cut"] as? Bool, true)
        XCTAssertEqual(a.respond(path: "/app/file", query: "path=content/cards/rhythms/done-when/photo.webp")?.status, 415)
        XCTAssertEqual(a.respond(path: "/app/file", query: "path=../../etc/hosts")?.status, 404)
    }

    func test_bytes_label() {
        XCTAssertEqual(LearnSharedApp.bytes(812), "812 B")
        XCTAssertEqual(LearnSharedApp.bytes(3 * 1024 + 100), "3 KB")
        XCTAssertEqual(LearnSharedApp.bytes(1_300_000), "1.2 MB")
    }

    // MARK: (3)(4)(5) the player's state

    func test_now_playing_counts_time_into_the_card_and_clamps() {
        let np = LearnSharedApp.nowPlaying(slug: "done-when", playing: true, index: 1, count: 4, clipElapsed: 15, total: 120, rate: 1.5, kicker: "The check")
        XCTAssertEqual(np["slug"] as? String, "done-when"); XCTAssertEqual(np["index"] as? Int, 1); XCTAssertEqual(np["count"] as? Int, 4)
        XCTAssertEqual(np["elapsed"] as? Double, 45); XCTAssertEqual(np["total"] as? Int, 120); XCTAssertEqual(np["rate"] as? Double, 1.5)
        XCTAssertEqual(np["kicker"] as? String, "The check")
        let over = LearnSharedApp.nowPlaying(slug: "x", playing: false, index: 9, count: 3, clipElapsed: 500, total: 60, rate: 1, kicker: "")
        XCTAssertEqual(over["index"] as? Int, 2); XCTAssertEqual(over["elapsed"] as? Double, 60); XCTAssertNil(over["kicker"])
        let none = LearnSharedApp.nowPlaying(slug: nil, playing: false, index: 0, count: 0, clipElapsed: 0, total: 0, rate: 1.25, kicker: nil)
        XCTAssertEqual(none["slug"] as? String, ""); XCTAssertEqual(none["rate"] as? Double, 1.25)
    }

    // MARK: The host page's bridge

    func test_host_page_offers_the_new_bridge_members() {
        let p = LearnShared.hostPage
        for m in ["subscribe:", "toggle:", "rate:", "refreshPosts:", "terminal:", "posts:", "post:", "folder:", "file:", "search:", "window.oneroofLearnEmit",
                  "\"app/posts\"", "app/folder?path=", "app/file?path=", "app/search?q=", "app/post/", "scene: typeof scene === \"number\" ? scene : -1"] {
            XCTAssertTrue(p.contains(m), "host page lacks \(m)")
        }
    }

    func test_query_params_decode() {
        XCTAssertEqual(LearnSharedApp.params("q=a%20b+c&path=content%2Fcards&x"), ["q": "a b c", "path": "content/cards", "x": ""])
        XCTAssertEqual(LearnSharedApp.params(nil), [:])
    }

    // MARK: The bridge's messages (the controller's handlers act on these)

    func test_bridge_messages_parse_play_with_scene_toggle_rate_terminal() {
        XCTAssertEqual(LearnBridgeMessage.parse(["type": "play", "slug": "done-when", "queue": ["a", "../x", "b"], "scene": 2]),
                       .play(slug: "done-when", queue: ["a", "b"], scene: 2))
        XCTAssertEqual(LearnBridgeMessage.parse(["type": "play", "slug": "done-when", "queue": [], "scene": -1]), .play(slug: "done-when", queue: [], scene: nil))
        XCTAssertEqual(LearnBridgeMessage.parse(["type": "play", "slug": "done-when"]), .play(slug: "done-when", queue: [], scene: nil), "an older page sends no scene")
        XCTAssertNil(LearnBridgeMessage.parse(["type": "play", "slug": "../etc"]))
        XCTAssertEqual(LearnBridgeMessage.parse(["type": "toggle"]), .toggle)
        XCTAssertEqual(LearnBridgeMessage.parse(["type": "rate"]), .rate)
        XCTAssertEqual(LearnBridgeMessage.parse(["type": "subscribed"]), .subscribed)
        XCTAssertEqual(LearnBridgeMessage.parse(["type": "refreshPosts"]), .refreshPosts)
        XCTAssertEqual(LearnBridgeMessage.parse(["type": "terminal", "path": "content/cards"]), .terminal("content/cards"))
        XCTAssertEqual(LearnBridgeMessage.parse(["type": "useInSession", "slug": "done-when"]), .useInSession("done-when"))
        XCTAssertNil(LearnBridgeMessage.parse(["type": "useInSession", "slug": "Bad Slug"]))
        XCTAssertEqual(LearnBridgeMessage.parse(["type": "error"]), .error("the page could not load"))
        XCTAssertNil(LearnBridgeMessage.parse(["type": "nope"]))
        XCTAssertNil(LearnBridgeMessage.parse("not a dictionary"))
    }

    func test_terminal_folder_must_be_a_deck_folder_and_rates_cycle() {
        let deck = root + "/deck"
        XCTAssertEqual(LearnShared.folderInDeck("content/cards/rhythms/done-when", deck: deck), (deck as NSString).standardizingPath + "/content/cards/rhythms/done-when")
        XCTAssertEqual(LearnShared.folderInDeck("", deck: deck), (deck as NSString).standardizingPath)
        XCTAssertNil(LearnShared.folderInDeck("content/cards/rhythms/done-when/SKILL.md", deck: deck), "a file")
        XCTAssertNil(LearnShared.folderInDeck("../posts", deck: deck))
        XCTAssertNil(LearnShared.folderInDeck("/tmp", deck: deck))
        let r: [Float] = [0.75, 1, 1.25, 1.5, 1.75, 2]
        XCTAssertEqual(LearnShared.nextRate(after: 1, in: r), 1.25)
        XCTAssertEqual(LearnShared.nextRate(after: 2, in: r), 0.75)
        XCTAssertEqual(LearnShared.nextRate(after: 1.1, in: r), 1.25, "an odd speed steps as the native key did")
    }
}
