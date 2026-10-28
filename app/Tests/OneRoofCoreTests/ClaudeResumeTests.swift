import XCTest
@testable import OneRoofCore

/// LAB-1362: after Claude exits in a One Roof terminal, Resume continues that conversation in the same terminal.
final class ClaudeResumeTests: XCTestCase {
    let id = "3f2a9c1e-7b4d-4e8a-9c0f-1a2b3c4d5e6f"

    func test_LAB1362_sessionIdFromClaudesExitLine() {
        let screen = """
        > /exit
        Total cost: $1.20
        Resume this session with:
        claude --resume \(id)
        user@mac ~/Projects %
        """
        XCTAssertEqual(ClaudeResume.sessionId(fromScreen: screen), id)
        XCTAssertNil(ClaudeResume.sessionId(fromScreen: "no hint here"))
        // Two exits in the same terminal: the last one is the conversation that just ended.
        let other = "11111111-2222-3333-4444-555555555555"
        XCTAssertEqual(ClaudeResume.sessionId(fromScreen: "claude --resume \(other)\n…\nclaude --resume \(id)\n"), id)
    }

    func test_LAB1362_sessionIdFromTranscriptPath() {
        XCTAssertEqual(ClaudeResume.sessionId(transcriptPath: "/u/.claude/projects/-Users-x-Projects/\(id).jsonl"), id)
        XCTAssertNil(ClaudeResume.sessionId(transcriptPath: "/u/.claude/projects/x/notes.txt"))
    }

    func test_LAB1362_commandKeepsModelAndDropsOldResume() {
        XCTAssertEqual(ClaudeResume.command(launchArgs: ["--model", "opus"], sessionId: id),
                       "claude --model opus --resume \(id)")
        XCTAssertEqual(ClaudeResume.command(launchArgs: ["--resume", "old-id", "--model", "sonnet", "-c"], sessionId: id),
                       "claude --model sonnet --resume \(id)")
        XCTAssertEqual(ClaudeResume.command(launchArgs: ["-r", "old", "--session-id", "x", "--continue"], sessionId: id),
                       "claude --resume \(id)")
        XCTAssertEqual(ClaudeResume.command(launchArgs: ["--append-system-prompt", "be brief"], sessionId: id),
                       "claude --append-system-prompt 'be brief' --resume \(id)")
        // A new launch (terminal gone) gets the arguments themselves: a value with a space stays one argument.
        XCTAssertEqual(ClaudeResume.args(["--resume", "old", "--append-system-prompt", "be brief"], sessionId: id),
                       ["--append-system-prompt", "be brief", "--resume", id])
    }
}

/// LAB-1510: a session keeps its agent's conversation id and transcript, so it can be resumed (and listed in the session
/// catalog) after its terminal is gone or the app restarted.
final class ConversationMemoryTests: XCTestCase {
    let id = "3f2a9c1e-7b4d-4e8a-9c0f-1a2b3c4d5e6f"

    func test_LAB1510_conversationIdSurvivesTheStore() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("lab1504-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = try SessionStore(path: dir.appendingPathComponent("s.sqlite").path)
        var s = Session(name: "resume me", repoPath: "/p/a/b", lifecycle: .idle)
        s.conversationId = id
        s.conversationPath = "/Users/x/.claude/projects/-p-a-b/\(id).jsonl"
        store.save(s)
        let back = try XCTUnwrap(SessionStore(path: dir.appendingPathComponent("s.sqlite").path).all().first { $0.id == s.id })
        XCTAssertEqual(back.conversationId, id)
        XCTAssertEqual(back.conversationPath, s.conversationPath)
        XCTAssertEqual(ClaudeResume.sessionId(transcriptPath: back.conversationPath!), back.conversationId)
    }

    func test_LAB1510_olderRowsWithoutAConversationStillLoad() throws {
        var s = Session(name: "old", repoPath: "/p", lifecycle: .idle)
        s.conversationId = id
        var json = try XCTUnwrap(try JSONSerialization.jsonObject(with: JSONEncoder().encode(s)) as? [String: Any])
        json["conversationId"] = nil
        json["conversationPath"] = nil
        let old = try JSONDecoder().decode(Session.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertNil(old.conversationId)
        XCTAssertNil(old.conversationPath)
        XCTAssertEqual(old.name, "old")
    }
}

/// LAB-1516: roofd (Scheduler, Loops) and the app write the same session rows. roofd writes only the launch fields; an
/// app save made from a copy older than roofd's launch keeps that launch instead of erasing it.
final class LostUpdateTests: XCTestCase {
    private func store() throws -> (SessionStore, String) {
        let path = NSTemporaryDirectory() + "lab1516-\(UUID().uuidString).sqlite"
        return (try SessionStore(path: path), path)
    }

    func test_LAB1516_appSaveFromAStaleCopyKeepsRoofdsLaunch() throws {
        let (st, path) = try store(); defer { try? FileManager.default.removeItem(atPath: path) }
        var s = Session(name: "nightly", repoPath: "/p", lifecycle: .planned)
        st.save(s)
        let appCopy = s                                    // the app read the row before the scheduled start
        s.runtimeId = "roof-abc"; s.runtimeGroup = "g"; s.launchedAt = Date(); s.openingSent = true; s.lifecycle = .idle
        st.updateLaunch(s)                                 // roofd starts it
        var edited = appCopy; edited.notes = "renamed by the owner"
        let written = st.saveKeepingNewerLaunch(edited)    // the app saves its stale copy
        let row = try XCTUnwrap(st.all().first { $0.id == s.id })
        XCTAssertEqual(row.runtimeId, "roof-abc")          // the launch survived
        XCTAssertEqual(row.notes, "renamed by the owner")  // and so did the app's edit
        XCTAssertEqual(written.runtimeId, "roof-abc")      // the app learns it too
    }

    func test_LAB1516_roofdNeverOverwritesTheAppsFields() throws {
        let (st, path) = try store(); defer { try? FileManager.default.removeItem(atPath: path) }
        var s = Session(name: "a", repoPath: "/p", lifecycle: .planned)
        st.save(s)
        var app = s; app.name = "renamed"; app.notes = "n"; st.save(app)
        s.runtimeId = "roof-1"; s.launchedAt = Date(); st.updateLaunch(s)   // roofd's copy still says "a"
        let row = try XCTUnwrap(st.all().first { $0.id == s.id })
        XCTAssertEqual(row.name, "renamed"); XCTAssertEqual(row.notes, "n"); XCTAssertEqual(row.runtimeId, "roof-1")
    }

    func test_LAB1516_aNewerLaunchByTheAppWins() throws {
        let (st, path) = try store(); defer { try? FileManager.default.removeItem(atPath: path) }
        var s = Session(name: "a", repoPath: "/p", lifecycle: .idle)
        s.runtimeId = "old"; s.launchedAt = Date(timeIntervalSinceNow: -60); st.save(s)
        var relaunched = s; relaunched.runtimeId = "new"; relaunched.launchedAt = Date()
        st.saveKeepingNewerLaunch(relaunched)
        XCTAssertEqual(st.all().first { $0.id == s.id }?.runtimeId, "new")
    }
}
