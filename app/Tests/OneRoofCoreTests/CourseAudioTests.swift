import XCTest
@testable import OneRoofCore

final class CourseAudioTests: XCTestCase {
    func testSkillPageTracksInFileOrderWithSceneTitles() throws {
        let dir = NSTemporaryDirectory() + "course-\(UUID().uuidString)"
        let audio = dir + "/demo_audio/openai"
        try FileManager.default.createDirectory(atPath: audio, withIntermediateDirectories: true)
        for n in ["9", "1", "5"] { FileManager.default.createFile(atPath: audio + "/\(n).mp3", contents: Data([0])) }
        let html = """
        <html><body><script>
        window.__TTS__={"openai": {"9": "demo_audio/openai/9.mp3", "1": "demo_audio/openai/1.mp3", "5": "demo_audio/openai/5.mp3"}};
        </script></body></html>
        """
        try html.write(toFile: dir + "/demo.html", atomically: true, encoding: .utf8)
        let spec = #"{"sections": [{"title": "Intro", "scenes": [{"heading": "Why", "narration": "a"}, {"heading": "What", "narration": "b"}]},"# +
                   #" {"title": "Recap", "scenes": [{"heading": "", "narration": "c"}, {"heading": "Silent", "narration": ""}]}]}"#
        try spec.write(toFile: dir + "/spec.json", atomically: true, encoding: .utf8)
        let t = CourseAudio.tracks(page: dir + "/demo.html")
        XCTAssertEqual(t.map { ($0.path as NSString).lastPathComponent }, ["9.mp3", "1.mp3", "5.mp3"], "file order, not sorted")
        XCTAssertEqual(t.map(\.title), ["Intro · Why", "Intro · What", "Recap"])
        try FileManager.default.removeItem(atPath: dir + "/spec.json")
        XCTAssertEqual(CourseAudio.tracks(page: dir + "/demo.html").map(\.title), ["Part 1", "Part 2", "Part 3"])
        XCTAssertEqual(CourseAudio.tracks(page: dir + "/missing.html"), [])
    }

    func testFolderTracksAndTitles() throws {
        XCTAssertEqual(CourseAudio.title(slugFile: "what-s-next-extending-the-mvp-f9ee69e0b8df.mp3"), "What's next extending the MVP")
        XCTAssertEqual(CourseAudio.title(slugFile: "run-it-here-25b510a792dd.mp3"), "Run it here")
        XCTAssertEqual(CourseAudio.title(slugFile: "plain.mp3"), "Plain")
        let dir = NSTemporaryDirectory() + "narr-\(UUID().uuidString)"
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        for n in ["b-setup-aaaaaaaaaaaa.mp3", "intro-bbbbbbbbbbbb.mp3", "a-why-cccccccccccc.mp3", "notes.txt"] {
            FileManager.default.createFile(atPath: dir + "/" + n, contents: Data([0]))
        }
        XCTAssertEqual(CourseAudio.tracks(folder: dir).map(\.title), ["Intro", "A why", "B setup"])
    }
}

final class AutoApproveTests: XCTestCase {
    func testOffByDefaultRoundTripsAndOldObjectivesDecodeOff() throws {
        var o = Objective(title: "Ship it")
        XCTAssertFalse(o.autoApprove)
        o.autoApprove = true
        let back = try JSONDecoder().decode(Objective.self, from: JSONEncoder().encode(o))
        XCTAssertTrue(back.autoApprove)
        let old = try JSONDecoder().decode(Objective.self, from: Data(#"{"id": "x", "title": "Old"}"#.utf8))
        XCTAssertFalse(old.autoApprove)
        XCTAssertEqual(AgentKind.claude.autoApproveArgs, ["--permission-mode", "auto"])
        XCTAssertEqual(AgentKind.shell.autoApproveArgs, [])
        XCTAssertTrue(AgentKind.allCases.filter(\.isAgent).allSatisfy { !$0.autoApproveArgs.isEmpty })
    }
}
