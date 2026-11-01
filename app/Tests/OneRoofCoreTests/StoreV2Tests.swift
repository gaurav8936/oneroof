import SQLite3
import XCTest
@testable import OneRoofCore

final class StoreV2Tests: XCTestCase {
    var path = ""
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    override func setUp() { path = NSTemporaryDirectory() + "oneroof-v2-\(UUID().uuidString).sqlite" }
    override func tearDown() {
        for ext in ["", "-wal", "-shm"] { try? FileManager.default.removeItem(atPath: path + ext) }
    }

    /// A v0.1 file: sessions table with one row, user_version 0.
    func makeV01(sessionId: String) {
        var db: OpaquePointer?
        XCTAssertEqual(sqlite3_open(path, &db), SQLITE_OK)
        let json = #"{"id":"\#(sessionId)","name":"old","agent":"claude","repoPath":"/p"}"#
        sqlite3_exec(db, "CREATE TABLE sessions (id TEXT PRIMARY KEY, json TEXT NOT NULL, updated REAL NOT NULL); INSERT INTO sessions VALUES('\(sessionId)', '\(json)', 0);", nil, nil, nil)
        sqlite3_close(db)
    }

    func testMigrationSeedsMainWithOldSessionsAndIsIdempotent() throws {
        makeV01(sessionId: "old-1")
        do {
            let store = try SessionStore(path: path)
            XCTAssertEqual(store.schemaVersion, SessionStore.migrations.count)
            XCTAssertEqual(store.all().map(\.id), ["old-1"])                    // v0.1 data untouched
            XCTAssertEqual(store.allWorkspaces().map(\.name), ["Main"])
            XCTAssertEqual(store.sessionWorkspaces()["old-1"], RoofWorkspace.mainId)
        }
        let again = try SessionStore(path: path)
        XCTAssertEqual(again.allWorkspaces().count, 1)
        XCTAssertEqual(again.schemaVersion, SessionStore.migrations.count)
    }

    func testWorkspacesMoveAndDelete() throws {
        let store = try SessionStore(path: path)
        XCTAssertEqual(store.workspaceId(forSession: "new"), RoofWorkspace.mainId)   // never moved → Main
        let w = RoofWorkspace(name: "Nightshift", colour: "blue", order: 1, layout: #"{"split":0.3}"#)
        store.save(w)
        store.move(session: "new", to: w.id)
        XCTAssertEqual(store.workspaceId(forSession: "new"), w.id)
        XCTAssertEqual(store.allWorkspaces().last, w)
        store.deleteWorkspace(id: w.id)
        XCTAssertEqual(store.workspaceId(forSession: "new"), RoofWorkspace.mainId)
        store.deleteWorkspace(id: RoofWorkspace.mainId)                                // refused
        XCTAssertEqual(store.allWorkspaces().map(\.name), ["Main"])
    }

    func testCaptionsLatestOnly() throws {
        let store = try SessionStore(path: path)
        store.saveCaption(Caption(text: "Editing a.swift", updatedAt: now), session: "s1")
        store.saveCaption(Caption(text: "Step 2 of 4 · Tests", step: 2, steps: 4, now: "Running swift test", updatedAt: now, source: .model), session: "s1")
        let c = store.caption(session: "s1")
        XCTAssertEqual(c, Caption(text: "Step 2 of 4 · Tests", step: 2, steps: 4, now: "Running swift test", updatedAt: now, source: .model))
        XCTAssertEqual(store.allCaptions().count, 1)
        XCTAssertNil(store.caption(session: "nope"))
    }

    func testFeedNewestFirstAndPrune() throws {
        let store = try SessionStore(path: path)
        let old = FeedEvent(at: now.addingTimeInterval(-31 * 86_400), sessionId: "s", kind: .done, text: "old")   // LAB-2046: 30 days
        let mid = FeedEvent(at: now.addingTimeInterval(-3600), sessionId: "s", kind: .finding, text: "mid", chapter: 2)
        let new = FeedEvent(at: now, sessionId: "s", kind: .error, text: "new")
        [old, mid, new].forEach(store.append)
        store.append(new)                                                              // same id ignored
        XCTAssertEqual(store.recentFeed().map(\.text), ["new", "mid", "old"])
        XCTAssertEqual(store.recentFeed().dropFirst().first, mid)
        store.pruneFeed(now: now)
        XCTAssertEqual(store.recentFeed().map(\.text), ["new", "mid"])
        XCTAssertEqual(store.recentFeed(limit: 1).count, 1)
    }

    func testDecisionsAnswersAndHistory() throws {
        let store = try SessionStore(path: path)
        func decision(_ ago: Double) -> Decision {
            Decision(sessionId: "s", agent: .codex, kind: .runCommand, command: "swift test", why: "w", touches: "t", risk: .low,
                     ifNo: "n", where_: "ENG-1", pattern: "swift test", repo: "acme/web", askedAt: now.addingTimeInterval(-ago))
        }
        let ds = [decision(300), decision(200), decision(100)]
        ds.forEach(store.save)
        for d in ds { store.answer(decision: d.id, .allowOnce, at: now) }
        let open = decision(10)
        store.save(open)
        let loaded = store.openDecisions(now: now)
        XCTAssertEqual(loaded.map(\.id), [open.id])
        XCTAssertEqual(loaded.first?.history.ruleSuggestion, "Always allow swift test in acme/web")
        XCTAssertEqual(loaded.first?.agent, .codex)
        XCTAssertEqual(store.decision(id: ds[0].id)?.answer, .allowOnce)
        XCTAssertEqual(store.decisions(since: now.addingTimeInterval(-250)).count, 3)

        store.answer(decision: open.id, .reply, reply: "run only the store tests", at: now)
        XCTAssertEqual(store.decision(id: open.id)?.replyText, "run only the store tests")
        let h = store.decisionHistory(pattern: "swift test", repo: "acme/web", now: now)
        XCTAssertEqual(h.similarAllowed, 3)
        XCTAssertEqual(h.similarDenied, 1)
        XCTAssertNil(h.ruleSuggestion)
    }

    func testRules() throws {
        let store = try SessionStore(path: path)
        let r = DecisionRule(pattern: "swift test", repo: "acme/web", createdAt: now)
        store.save(r)
        XCTAssertEqual(store.decisionRules(), [r])
        store.deleteRule(id: r.id)
        XCTAssertTrue(store.decisionRules().isEmpty)
    }

    func testReviewComments() throws {
        let store = try SessionStore(path: path)
        var c = ReviewComment(sessionId: "s", path: "Sources/a.swift", line: 12, text: "Use a guard here")
        store.save(c)
        c.sentAt = now
        store.save(c)
        store.save(ReviewComment(sessionId: "s", path: "Sources/a.swift", line: 3, text: "Name this", savedAsNote: true))
        let all = store.reviewComments(session: "s")
        XCTAssertEqual(all.map(\.line), [3, 12])
        XCTAssertEqual(all.last?.sentAt, now)
        XCTAssertTrue(all.first?.savedAsNote ?? false)
        store.deleteReviewComment(id: c.id)
        XCTAssertEqual(store.reviewComments(session: "s").count, 1)
    }

    func testSchedules() throws {
        let store = try SessionStore(path: path)
        store.save(ScheduleRecord(sessionId: "s1", schedule: .tonight(hour: 2, minute: 0), armedAt: now))
        store.save(ScheduleRecord(sessionId: "s2", schedule: .onDemand, armedAt: now))
        XCTAssertEqual(store.schedules().map(\.schedule), [.tonight(hour: 2, minute: 0), .onDemand])
        store.recordScheduledRun(session: "s1", at: now, result: "4 of 4 done")
        XCTAssertEqual(store.schedule(session: "s1")?.lastResult, "4 of 4 done")
        XCTAssertEqual(store.schedule(session: "s1")?.lastRun, now)
        store.deleteSchedule(session: "s2")
        XCTAssertEqual(store.schedules().count, 1)
    }
}
