import XCTest
@testable import OneRoofCore

/// LAB-1942: a loop's definition (`loop.json`, changed only by your edits, fit for git) and its run state
/// (`state.json`, written by roofd every round) live apart; a loop.json from before the split migrates on first read.
final class LoopSplitTests: XCTestCase {
    var dir: String!
    override func setUp() {
        dir = NSTemporaryDirectory() + "loop-split-\(UUID().uuidString.prefix(8))"
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
    }
    override func tearDown() { try? FileManager.default.removeItem(atPath: dir) }

    func text(_ p: String) -> String { (try? String(contentsOfFile: dir + "/" + p, encoding: .utf8)) ?? "" }
    func keys(_ p: String) -> Set<String> {
        guard let d = FileManager.default.contents(atPath: dir + "/" + p),
              let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else { return [] }
        return Set(o.keys)
    }

    func test_runStateNeverRewritesTheDefinition() throws {
        let s = LoopStore(root: dir, builtIns: [], fileLoops: [])
        let l = Loop(id: "fix-ci", name: "fix-ci", goal: "green", check: "true", repoPath: "/p/acme", trigger: .at(hour: 3, minute: 0), state: .waiting)
        try s.save(l)
        let def = text("fix-ci/loop.json")
        XCTAssertTrue(keys("fix-ci/loop.json").isDisjoint(with: LoopRunState.keys), "\(keys("fix-ci/loop.json"))")
        XCTAssertEqual(keys("fix-ci/state.json").intersection(["state"]), ["state"])
        // What roofd does every round: state changes only.
        try s.update("fix-ci") { $0 = LoopController.begin($0, now: Date()) }
        try s.update("fix-ci") { $0 = LoopController.started($0, n: 1, sessionId: "s1", runtimeId: "roof-1", now: Date()) }
        try s.update("fix-ci") { $0 = LoopController.ended($0, rounds: [], outcome: .done, now: Date()).0 }
        XCTAssertEqual(text("fix-ci/loop.json"), def, "a run leaves the definition (git) untouched")
        let after = try XCTUnwrap(s.load("fix-ci"))
        XCTAssertEqual(after.state, .done); XCTAssertNotNil(after.lastRunAt); XCTAssertEqual(after.goal, "green")
        // Your edit changes the definition.
        var e = after; e.goal = "main is green"
        try s.saveEdit(e)
        XCTAssertNotEqual(text("fix-ci/loop.json"), def)
        XCTAssertEqual(s.load("fix-ci")?.state, .done)
    }

    func test_legacyLoopJsonMigratesOnFirstRead_keepsItsState_withBackup() throws {
        let legacy = """
        {"id": "nightly-bugs", "name": "nightly-bugs", "goal": "every bug fixed", "check": "bash tools/check.sh",
         "repoPath": "/p/acme", "agent": "claude", "roundPrompt": "one bug per round", "trigger": {"at": {"hour": 3, "minute": 0}},
         "limits": {"maxRounds": 8, "maxDuration": 10800, "sameFailureStop": 2}, "pinned": true, "state": "failed",
         "createdAt": "2026-10-29T10:00:00Z", "checkTimeout": 600, "runRequested": false, "lastRunAt": "2026-10-31T03:00:00Z",
         "stopReason": "The same failure twice in a row (x)"}
        """
        try FileManager.default.createDirectory(atPath: dir + "/nightly-bugs", withIntermediateDirectories: true)
        try legacy.write(toFile: dir + "/nightly-bugs/loop.json", atomically: true, encoding: .utf8)
        let s = LoopStore(root: dir, builtIns: [], fileLoops: [])
        let l = try XCTUnwrap(s.load("nightly-bugs"))
        XCTAssertEqual(l.state, .failed); XCTAssertEqual(l.stopReason, "The same failure twice in a row (x)")
        XCTAssertEqual(l.lastRunAt, ISO8601DateFormatter().date(from: "2026-10-31T03:00:00Z"))
        XCTAssertEqual(l.goal, "every bug fixed"); XCTAssertTrue(l.pinned); XCTAssertEqual(l.trigger, .at(hour: 3, minute: 0))
        XCTAssertEqual(text("nightly-bugs/loop.json.pre-split.bak"), legacy)
        XCTAssertTrue(keys("nightly-bugs/loop.json").isDisjoint(with: LoopRunState.keys))
        XCTAssertTrue(keys("nightly-bugs/loop.json").isSuperset(of: ["goal", "check", "roundPrompt", "trigger", "limits", "agent", "pinned"]))
        // Reading again changes nothing and loads the same loop.
        let def = text("nightly-bugs/loop.json"), st = text("nightly-bugs/state.json")
        XCTAssertEqual(s.load("nightly-bugs"), l)
        XCTAssertEqual(text("nightly-bugs/loop.json"), def); XCTAssertEqual(text("nightly-bugs/state.json"), st)
        XCTAssertEqual(s.all().map(\.id), ["nightly-bugs"])
    }

    func test_builtInRunWritesStateOnly_kitFileLoopNeverGetsADefinition() throws {
        let b = Loop(id: "docs-drift", name: "docs-drift", title: "Docs drift", origin: .builtIn, goal: "g", check: "c", repoPath: "/p",
                     trigger: .at(hour: 6, minute: 0), state: .stopped, createdAt: LoopBuiltIns.referenceDate)
        var f = Loop(id: "my-weekly", name: "my-weekly", origin: .mine, goal: "weekly", check: "python3 -m ae.loops run my-weekly --no-agent", repoPath: "/p")
        f.specFile = dir + "/my-weekly.loop.yaml"
        let s = LoopStore(root: dir, builtIns: [b], fileLoops: [f])
        try s.update("docs-drift") { $0 = LoopController.runNow($0) }
        try s.update("my-weekly") { $0 = LoopController.runNow($0) }
        XCTAssertFalse(FileManager.default.fileExists(atPath: dir + "/docs-drift/loop.json"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: dir + "/my-weekly/loop.json"))
        XCTAssertEqual(s.load("docs-drift")?.runRequested, true); XCTAssertEqual(s.load("docs-drift")?.origin, .builtIn)
        XCTAssertEqual(s.load("my-weekly")?.runRequested, true); XCTAssertEqual(s.load("my-weekly")?.goal, "weekly")
        try s.update("docs-drift") { $0.pinned = true }                     // an edit of a Built-in is a definition
        XCTAssertTrue(FileManager.default.fileExists(atPath: dir + "/docs-drift/loop.json"))
        XCTAssertEqual(s.load("docs-drift")?.pinned, true)
        try s.update("my-weekly") { $0.pinned = true }
        XCTAssertEqual(s.load("my-weekly")?.pinned, true); XCTAssertEqual(s.load("my-weekly")?.goal, "weekly")
        XCTAssertTrue(s.hasDiskOverride("my-weekly"))
        s.delete("my-weekly")
        XCTAssertEqual(s.load("my-weekly")?.runRequested, false)            // Reset: back to the file's loop
    }

    /// Proof on a copy of a real loop folder (never the live one): `ONEROOF_SPLIT_PROOF=<folder holding <id>/loop.json>`.
    func test_proofOnACopyOfARealLoop() throws {
        guard let root = ProcessInfo.processInfo.environment["ONEROOF_SPLIT_PROOF"] else { throw XCTSkip("set ONEROOF_SPLIT_PROOF to a copied loops folder") }
        let s = LoopStore(root: root, builtIns: [], fileLoops: [])
        for id in ((try? FileManager.default.contentsOfDirectory(atPath: root)) ?? []).filter(Loop.validId) {
            let before = try XCTUnwrap(FileManager.default.contents(atPath: root + "/\(id)/loop.json"))
            let old = try LoopStore.decoder.decode(Loop.self, from: before)
            let l = try XCTUnwrap(s.load(id))
            XCTAssertEqual(l, old, "\(id): same loop after the split")
            XCTAssertTrue(FileManager.default.fileExists(atPath: root + "/\(id)/state.json"))
            print("split-proof \(id): state \(l.state.rawValue) · lastRunAt \(l.lastRunAt.map { "\($0)" } ?? "-") · definition keys clean")
        }
    }
}
