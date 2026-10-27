import XCTest
@testable import OneRoofCore

/// LAB-1302: the narrow session column shows only live sessions.
final class SessionStatusLiveTests: XCTestCase {
    func testLiveStatuses() {
        XCTAssertEqual(Set(SessionStatus.allCases.filter(\.isLive)), [.running, .needsYou, .done, .idle])
        XCTAssertFalse(SessionStatus.exited.isLive)
        XCTAssertFalse(SessionStatus.doNotUse.isLive)
        XCTAssertFalse(SessionStatus.planned.isLive)
    }
}
