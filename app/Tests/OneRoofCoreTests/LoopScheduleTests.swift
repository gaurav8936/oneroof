import XCTest
@testable import OneRoofCore

/// LAB-254: loops (Every N minutes).
final class LoopScheduleTests: XCTestCase {
    let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    func testEveryIsStoredAsMinutesAndReadBack() {
        let s = Schedule.every(minutes: 60)
        XCTAssertEqual(s.kind, "every")
        XCTAssertEqual(s.stored.minute, 60)
        XCTAssertEqual(Schedule(kind: s.kind, hour: s.stored.hour, minute: s.stored.minute), s)
        XCTAssertNil(Schedule(kind: "every", hour: nil, minute: 0))
        XCTAssertEqual(s.label, "Every 1 h")
        XCTAssertEqual(Schedule.every(90), "1 h 30 min")
        XCTAssertEqual(Schedule.every(15), "15 min")
    }

    func testRoundsComeAnIntervalAfterTheLastOne() {
        var r = ScheduleRecord(sessionId: "s", schedule: .every(minutes: 30), armedAt: t0)
        XCTAssertEqual(ScheduleClock.action(r, now: t0.addingTimeInterval(29 * 60)), .nothing)
        XCTAssertEqual(ScheduleClock.action(r, now: t0.addingTimeInterval(30 * 60)), .run)
        r.lastRun = t0.addingTimeInterval(30 * 60)
        XCTAssertEqual(ScheduleClock.nextFire(r, now: t0), t0.addingTimeInterval(60 * 60))
        // Late after sleep: just the next round, never "missed".
        XCTAssertEqual(ScheduleClock.action(r, now: t0.addingTimeInterval(10 * 3600)), .run)
    }

    func testALiveRoundWaitsForTheAgentAndGivesUpAfterAnInterval() {
        let r = ScheduleRecord(sessionId: "s", schedule: .every(minutes: 60), armedAt: t0)
        let due = t0.addingTimeInterval(3600)
        XCTAssertEqual(ScheduleClock.liveRound(r, status: "idle", ready: true, now: due), .send)
        XCTAssertEqual(ScheduleClock.liveRound(r, status: "done", ready: true, now: due), .send)
        XCTAssertEqual(ScheduleClock.liveRound(r, status: "working", ready: true, now: due), .wait)
        XCTAssertEqual(ScheduleClock.liveRound(r, status: "blocked", ready: true, now: due), .wait)
        XCTAssertEqual(ScheduleClock.liveRound(r, status: "idle", ready: false, now: due), .wait)
        XCTAssertEqual(ScheduleClock.liveRound(r, status: "working", ready: true, now: due.addingTimeInterval(3600)), .skip)
    }

    func testRowLabelShowsTheNextRoundAndHidesARunTonight() {
        let r = ScheduleRecord(sessionId: "s", schedule: .every(minutes: 60), armedAt: t0)
        XCTAssertTrue(ScheduleClock.rowLabel(r, now: t0)?.hasSuffix(" · every 1 h") == true)
        var once = ScheduleRecord(sessionId: "s", schedule: .tonight(hour: 2, minute: 0), armedAt: t0)
        XCTAssertEqual(ScheduleClock.rowLabel(once, now: t0), "2:00 AM")
        once.lastRun = t0
        XCTAssertNil(ScheduleClock.rowLabel(once, now: t0))
    }
}
