import XCTest
@testable import OneRoofCore

/// LAB-1533: one setting for how long Claude keeps conversations, applied to every account's settings file.
final class ConversationRetentionTests: XCTestCase {
    var home = ""
    override func setUpWithError() throws {
        home = NSTemporaryDirectory() + "lab1533-\(UUID().uuidString)"
        let fm = FileManager.default
        for d in [".claude", ".claude-2", ".claude-max-1"] { try fm.createDirectory(atPath: "\(home)/\(d)", withIntermediateDirectories: true) }
        try #"{"hooks":{"Stop":[{"command":"x"}]},"model":"opus"}"#.write(toFile: "\(home)/.claude/settings.json", atomically: true, encoding: .utf8)
        try fm.createSymbolicLink(atPath: "\(home)/.claude-2/settings.json", withDestinationPath: "\(home)/.claude/settings.json")
        try fm.createSymbolicLink(atPath: "\(home)/.claude-max-1/settings.json", withDestinationPath: "\(home)/.claude/settings.json")
    }
    override func tearDown() { try? FileManager.default.removeItem(atPath: home) }

    func test_LAB1533_appliesThroughLinksKeepingOtherKeys() throws {
        XCTAssertNil(ConversationRetention.current(home: home))                       // not set: Claude's default
        let written = try ConversationRetention.apply(ConversationRetention.forever, home: home)
        XCTAssertEqual(written.count, 1)                                               // three accounts, one real file
        XCTAssertEqual(ConversationRetention.current(home: home), 36_500)
        let o = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: "\(home)/.claude/settings.json"))) as? [String: Any])
        XCTAssertEqual(o["model"] as? String, "opus")
        XCTAssertNotNil(o["hooks"])
        for d in [".claude-2", ".claude-max-1"] {
            XCTAssertEqual(try FileManager.default.destinationOfSymbolicLink(atPath: "\(home)/\(d)/settings.json"), "\(home)/.claude/settings.json")
        }
        try ConversationRetention.apply(nil, home: home)                                // back to Claude's default
        XCTAssertNil(ConversationRetention.current(home: home))
    }

    func test_LAB1533_loweringIsFlagged() {
        XCTAssertTrue(ConversationRetention.deletes(from: 365, to: nil))     // 1 year → 30 days
        XCTAssertTrue(ConversationRetention.deletes(from: ConversationRetention.forever, to: 90))
        XCTAssertFalse(ConversationRetention.deletes(from: nil, to: 365))
        XCTAssertFalse(ConversationRetention.deletes(from: 365, to: 365))
        XCTAssertEqual(ConversationRetention.label(nil), "Claude's default: 30 days")
        XCTAssertEqual(ConversationRetention.label(ConversationRetention.forever), "Forever")
    }
}
