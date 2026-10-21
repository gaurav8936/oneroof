import XCTest
@testable import OneRoofCore

/// LAB-310: roofd's memory guard (session holders reached 2–6 GB each on 10-21 and froze the Mac).
final class MemoryWatchdogTests: XCTestCase {
    let mb = MemoryWatchdog.mb

    func testUnderTheLineIsOk() {
        var d = MemoryWatchdog(warnBytes: 100 * mb, limitBytes: 200 * mb)
        XCTAssertEqual(d.check(footprint: 10 * mb), .ok)
        XCTAssertFalse(d.warned)
    }

    func testWarnsOnceThenStopsAtTheLimit() {
        var d = MemoryWatchdog(warnBytes: 100 * mb, limitBytes: 200 * mb)
        XCTAssertEqual(d.check(footprint: 120 * mb), .warn)
        XCTAssertTrue(d.warned)
        XCTAssertEqual(d.check(footprint: 150 * mb), .ok, "reported once, not every check")
        XCTAssertEqual(d.check(footprint: 200 * mb), .stop)
        XCTAssertEqual(d.check(footprint: 5000 * mb), .stop)
    }

    func testWarnsAgainOnlyAfterFallingClearlyBelow() {
        var d = MemoryWatchdog(warnBytes: 100 * mb, limitBytes: 200 * mb)
        XCTAssertEqual(d.check(footprint: 101 * mb), .warn)
        XCTAssertEqual(d.check(footprint: 95 * mb), .ok)
        XCTAssertTrue(d.warned, "just under the line: still the same episode")
        XCTAssertEqual(d.check(footprint: 101 * mb), .ok)
        XCTAssertEqual(d.check(footprint: 50 * mb), .ok)
        XCTAssertFalse(d.warned)
        XCTAssertEqual(d.check(footprint: 101 * mb), .warn)
    }

    func testWarnLineNeverAboveTheLimit() {
        var d = MemoryWatchdog(warnBytes: 500 * mb, limitBytes: 200 * mb)
        XCTAssertEqual(d.warnBytes, d.limitBytes)
        XCTAssertEqual(d.check(footprint: 300 * mb), .stop)
    }

    func testLimitsFromTheEnvironmentElseDefaults() {
        let d = MemoryWatchdog.from(env: ["ROOFD_SESSION_MEM_WARN_MB": "8", "ROOFD_SESSION_MEM_LIMIT_MB": "16"],
                                    prefix: "ROOFD_SESSION", warnMB: 1024, limitMB: 2048)
        XCTAssertEqual(d.warnBytes, 8 * mb)
        XCTAssertEqual(d.limitBytes, 16 * mb)
        let e = MemoryWatchdog.from(env: ["ROOFD_SESSION_MEM_LIMIT_MB": "nonsense"], prefix: "ROOFD_SESSION",
                                    warnMB: MemoryWatchdog.holderWarnMB, limitMB: MemoryWatchdog.holderLimitMB)
        XCTAssertEqual(e.warnBytes, 1024 * mb)
        XCTAssertEqual(e.limitBytes, 2048 * mb, "the default limit is about 2 GB")
    }

    func testReadsThisProcessFootprint() throws {
        let f = try XCTUnwrap(MemoryWatchdog.footprint())
        XCTAssertGreaterThan(f, 1 * mb)
        XCTAssertLessThan(f, 64 * 1024 * mb)
    }

    func testLogLineSaysWhoAndHowMuch() {
        let line = MemoryWatchdog.logLine(at: Date(timeIntervalSince1970: 0), who: "session roof-1", footprint: 2100 * mb, action: .stop)
        XCTAssertTrue(line.hasPrefix("1970-01-01T00:00:00Z session roof-1 pid "), line)
        XCTAssertTrue(line.contains("footprint 2100 MB: over the limit, stopping"), line)
        XCTAssertTrue(line.hasSuffix("\n"))
    }
}
