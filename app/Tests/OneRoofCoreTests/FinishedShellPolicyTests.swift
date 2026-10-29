import XCTest
@testable import OneRoofCore

/// LAB-1524: the shells finished agents leave behind are closed only when it is safe and the owner's setting says so.
final class FinishedShellPolicyTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    func close(_ minutes: Int, idleMinutes: Double?, live: Bool = false, pinned: Bool = false, prompt: Bool = true, finished: Bool = true) -> Bool {
        FinishedShellPolicy.shouldClose(finishedShell: finished, liveAgent: live, pinned: pinned, atPrompt: prompt,
                                        lastActive: idleMinutes.map { now.addingTimeInterval(-$0 * 60) }, minutes: minutes, now: now)
    }

    func test_LAB1524_closesAfterTheChosenTimeOnly() {
        XCTAssertFalse(close(60, idleMinutes: 59))
        XCTAssertTrue(close(60, idleMinutes: 61))
        XCTAssertTrue(close(0, idleMinutes: 0))
        XCTAssertTrue(close(0, idleMinutes: nil))
        XCTAssertFalse(close(60, idleMinutes: nil))
    }

    func test_LAB1524_neverWhenUnsafeOrOff() {
        XCTAssertFalse(close(-1, idleMinutes: 9999))                 // Keep the shell
        XCTAssertFalse(close(60, idleMinutes: 999, live: true))      // an agent is running
        XCTAssertFalse(close(60, idleMinutes: 999, pinned: true))    // pinned
        XCTAssertFalse(close(60, idleMinutes: 999, prompt: false))   // something runs in the shell
        XCTAssertFalse(close(60, idleMinutes: 999, finished: false)) // not a finished session
    }

    func test_LAB1524_atPrompt() {
        XCTAssertTrue(FinishedShellPolicy.atPrompt(shellPid: 10, foreground: [10]))
        XCTAssertFalse(FinishedShellPolicy.atPrompt(shellPid: 10, foreground: [10, 44]))   // a command in the foreground
        XCTAssertFalse(FinishedShellPolicy.atPrompt(shellPid: 10, foreground: [44]))
        XCTAssertFalse(FinishedShellPolicy.atPrompt(shellPid: nil, foreground: [10]))
        XCTAssertFalse(FinishedShellPolicy.atPrompt(shellPid: 10, foreground: []))
    }

    func test_LAB1524_olderSettingsGetTheHourDefault() throws {
        var json = try XCTUnwrap(try JSONSerialization.jsonObject(with: JSONEncoder().encode(AppSettings())) as? [String: Any])
        json["closeFinishedAfterMinutes"] = nil
        let s = try JSONDecoder().decode(AppSettings.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertEqual(s.closeFinishedAfterMinutes, 60)
        XCTAssertTrue(FinishedShellPolicy.choices.contains { $0.minutes == s.closeFinishedAfterMinutes })
    }
}
