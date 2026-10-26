import XCTest
@testable import OneRoofCore

/// LAB-1253 · All cards › By folder (the skills folder as packaged) and LAB-1247 · Radio home routing.
final class LearnFoldersTests: XCTestCase {
    private var root = ""

    override func setUpWithError() throws {
        root = NSTemporaryDirectory() + "learn-folders-" + UUID().uuidString
        let fm = FileManager.default
        func write(_ rel: String, _ text: String = "x") throws {
            let p = root + "/" + rel
            try fm.createDirectory(atPath: (p as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
            try text.write(toFile: p, atomically: true, encoding: .utf8)
        }
        for (track, slug) in [("doctrine", "approval-gate"), ("doctrine", "done-when"), ("rhythms", "nightly")] {
            let d = "skills/\(track)/\(slug)/"
            try write(d + "SKILL.md", "---\nname: \(slug)\n---\n# \(slug)\n")
            try write(d + "spec.json", "{}")
            try write(d + "video.yaml", "scenes: []\n")
            try write(d + "\(slug).html", "<html></html>")
        }
        try write("skills/doctrine/approval-gate/approval-gate_audio/openai/1.mp3")
        try write("skills/doctrine/approval-gate/approval-gate_audio/openai/2.mp3")
        try write("skills/doctrine/approval-gate/approval-gate_audio/openai/notes.txt")
        try write("skills/doctrine/not-in-catalog/SKILL.md")
        try write("skills/README.md", "# skills/\n")
        try write("skills/.DS_Store")
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(atPath: root) }

    private func card(_ slug: String, _ track: String, _ title: String, secs: Int) -> String {
        #"{"slug": "\#(slug)", "track": "\#(track)", "title": "\#(title)", "skill": "skills/\#(track)/\#(slug)/SKILL.md", "#
            + #""spec": "skills/\#(track)/\#(slug)/spec.json", "html": "skills/\#(track)/\#(slug)/\#(slug).html", "est_seconds": \#(secs)}"#
    }

    private func deck() throws -> LearnDeck {
        let json = """
        {"version": "0.2.0", "suits": [{"id": "s", "tracks": ["doctrine", "rhythms"]}],
         "tracks": [{"id": "doctrine", "suit": "s", "intro": "The methodology", "cards": ["done-when", "approval-gate"]},
                    {"id": "rhythms", "suit": "s", "intro": "Daily", "cards": ["nightly"]}],
         "cards": [\(card("approval-gate", "doctrine", "Approval Gate", secs: 130)), \(card("done-when", "doctrine", "Done-when", secs: 60)),
                   \(card("nightly", "rhythms", "Nightly", secs: 300))]}
        """
        return try XCTUnwrap(LearnDeck.parse(Data(json.utf8), root: root))
    }

    func testRootIsTheSkillsFolderNamedFromTheCatalogPaths() throws {
        let d = try deck()
        XCTAssertEqual(DeckFolders.skillsDir(d), "skills")
        XCTAssertEqual(DeckFolders.rootLabel(d), "skills/")
    }

    func testTopLevelListsTrackFoldersThenFilesWithBandAndSkillCount() throws {
        let d = try deck()
        let top = DeckFolders.children(in: d)
        XCTAssertEqual(top.map(\.name), ["doctrine", "rhythms", "README.md"], "folders first, hidden files left out")
        let doctrine = try XCTUnwrap(top.first)
        XCTAssertEqual(doctrine.kind, .track)
        XCTAssertEqual(doctrine.id, "skills/doctrine")
        XCTAssertEqual(doctrine.depth, 0)
        XCTAssertEqual(doctrine.what, LearnDeck.trackNames["doctrine"]?.name ?? LearnDeck.label("doctrine"))
        XCTAssertEqual(doctrine.band, DeckFolders.band(ofTrack: "doctrine")?.id)
        XCTAssertEqual(doctrine.size, "3 skills", "every skill folder on disk counts, catalogued or not")
        XCTAssertEqual(top[1].size, "1 skill")
        XCTAssertEqual(top[2].kind, .readme)
        XCTAssertEqual(top[2].what, "The index of every folder")
        XCTAssertTrue(top[2].readable)
    }

    func testSkillFolderAndItsFiles() throws {
        let d = try deck()
        let skills = DeckFolders.children(of: "skills/doctrine", in: d)
        XCTAssertEqual(skills.map(\.name), ["approval-gate", "done-when", "not-in-catalog"])
        XCTAssertEqual(skills[0].kind, .skill)
        XCTAssertEqual(skills[0].what, "Approval Gate")
        XCTAssertEqual(skills[0].size, "2 min")
        XCTAssertEqual(skills[0].slug, "approval-gate")
        XCTAssertEqual(skills[2].what, "Not in catalog")
        XCTAssertEqual(skills[2].size, "")

        let files = DeckFolders.children(of: "skills/doctrine/approval-gate", in: d)
        XCTAssertEqual(files.map(\.name), ["approval-gate_audio", "approval-gate.html", "SKILL.md", "spec.json", "video.yaml"])
        XCTAssertEqual(files.map(\.kind), [.audio, .card, .skillFile, .spec, .video])
        XCTAssertEqual(files.map(\.what), ["Narration", "The card", "Skill definition", "Scenes and narration", "Video render"])
        XCTAssertEqual(files[0].size, "2 clips")
        XCTAssertTrue(files.allSatisfy { $0.slug == "approval-gate" && $0.track == "doctrine" && $0.depth == 2 })
        XCTAssertFalse(files[1].readable, "the card page opens the card station instead")
        XCTAssertTrue(files[2].readable)

        let audio = DeckFolders.children(of: "skills/doctrine/approval-gate/approval-gate_audio/openai", in: d)
        XCTAssertEqual(audio.map(\.kind), [.clip, .clip, .file])
        XCTAssertTrue(audio[2].readable)
    }

    func testRowsExpandDepthFirst() throws {
        let d = try deck()
        XCTAssertEqual(DeckFolders.rows(in: d, expanded: []).map(\.id), ["skills/doctrine", "skills/rhythms", "skills/README.md"])
        let rows = DeckFolders.rows(in: d, expanded: ["skills/doctrine", "skills/doctrine/approval-gate"]).map(\.id)
        XCTAssertEqual(rows, ["skills/doctrine", "skills/doctrine/approval-gate",
                              "skills/doctrine/approval-gate/approval-gate_audio", "skills/doctrine/approval-gate/approval-gate.html",
                              "skills/doctrine/approval-gate/SKILL.md", "skills/doctrine/approval-gate/spec.json", "skills/doctrine/approval-gate/video.yaml",
                              "skills/doctrine/done-when", "skills/doctrine/not-in-catalog", "skills/rhythms", "skills/README.md"])
        // A collapsed parent hides an expanded child.
        XCTAssertEqual(DeckFolders.rows(in: d, expanded: ["skills/doctrine/approval-gate"]).count, 3)
    }

    func testTrackCardsInDiskOrderAndEntryLookup() throws {
        let d = try deck()
        XCTAssertEqual(DeckFolders.cards(inTrack: "doctrine", deck: d), ["approval-gate", "done-when"], "disk order, catalogued cards only")
        XCTAssertEqual(DeckFolders.entry("skills/doctrine/done-when/SKILL.md", in: d)?.kind, .skillFile)
        XCTAssertEqual(DeckFolders.entry("skills/rhythms", in: d)?.kind, .track)
        XCTAssertNil(DeckFolders.entry("skills/nope", in: d))
        XCTAssertEqual(DeckFolders.ancestors(of: "skills/doctrine/done-when/SKILL.md"), ["skills", "skills/doctrine", "skills/doctrine/done-when"])
        XCTAssertEqual(DeckFolders.text(root + "/skills/README.md"), "# skills/\n")
        XCTAssertNil(DeckFolders.text(root + "/missing"))
    }

    func testMissingFolderIsEmpty() throws {
        let d = try XCTUnwrap(LearnDeck.parse(Data(#"{"cards": [{"slug": "a", "track": "t", "skill": "skills/t/a/SKILL.md"}]}"#.utf8), root: root + "/nowhere"))
        XCTAssertEqual(DeckFolders.rows(in: d, expanded: ["skills/t"]), [])
    }

    // LAB-1247: Radio home's band keys and chips navigate; only play controls play.
    func testRadioBandKeyAndChipOpenTheBandAndNeverPlay() {
        XCTAssertEqual(LearnRadioRoute.bandKey("context"), .openBand("context", track: nil))
        XCTAssertEqual(LearnRadioRoute.chip(band: "context", track: "vault"), .openBand("context", track: "vault"))
        XCTAssertEqual(LearnRadioRoute.dial("loops-first"), .play("loops-first"))
        for b in LearnDeck.bands {
            if case .play = LearnRadioRoute.bandKey(b.id) { XCTFail("a band key must not play") }
            for tr in b.tracks { if case .play = LearnRadioRoute.chip(band: b.id, track: tr) { XCTFail("a chip must not play") } }
        }
        XCTAssertEqual(LearnRadioRoute.anchor(track: "vault"), "track:vault")
    }
}
