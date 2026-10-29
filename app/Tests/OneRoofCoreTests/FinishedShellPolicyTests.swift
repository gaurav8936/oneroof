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
        XCTAssertEqual(s.closeFinishedAfterMinutes, 10)  // LAB-1535: 10 minutes is the default now
        XCTAssertTrue(FinishedShellPolicy.choices.contains { $0.minutes == s.closeFinishedAfterMinutes })
    }

    /// LAB-1535: settings saved by 1.9.16 with the old 60-minute default move to 10 minutes; a chosen value stays.
    func test_LAB1535_oldDefaultMovesToRightAway() throws {
        func decode(_ minutes: Int, version: Int?) throws -> AppSettings {
            var json = try XCTUnwrap(try JSONSerialization.jsonObject(with: JSONEncoder().encode(AppSettings())) as? [String: Any])
            json["closeFinishedAfterMinutes"] = minutes
            json["finishedPolicyVersion"] = version
            return try JSONDecoder().decode(AppSettings.self, from: JSONSerialization.data(withJSONObject: json))
        }
        XCTAssertEqual(try decode(60, version: nil).closeFinishedAfterMinutes, 10)
        XCTAssertEqual(try decode(240, version: nil).closeFinishedAfterMinutes, 240)
        XCTAssertEqual(try decode(-1, version: nil).closeFinishedAfterMinutes, -1)
        XCTAssertEqual(try decode(60, version: 2).closeFinishedAfterMinutes, 60)   // chosen after the change: kept
    }

    /// LAB-1535: a day untouched closes a resumable, idle session — never a working, waiting, pinned or loop one.
    func test_LAB1535_idleSessions() {
        let now = Date(timeIntervalSince1970: 1_800_000_000), old = now.addingTimeInterval(-25 * 3600)
        func close(_ status: SessionStatus = .idle, agent: AgentKind = .claude, conv: String? = "c", pinned: Bool = false,
                   tags: [String] = [], prompt: Bool = true, last: Date? = nil, hours: Int = 24) -> Bool {
            IdleSessionPolicy.shouldClose(running: true, status: status, pinned: pinned, tags: tags, agent: agent, conversationId: conv,
                                          atPrompt: prompt, lastActive: last ?? old, hours: hours, now: now)
        }
        XCTAssertTrue(close())
        XCTAssertFalse(close(last: now.addingTimeInterval(-3600)))     // touched an hour ago
        XCTAssertFalse(close(.running))                                // working
        XCTAssertFalse(close(.needsYou))                               // waiting for you
        XCTAssertFalse(close(pinned: true))
        XCTAssertFalse(close(tags: ["loop:abc"]))                      // loops are never closed
        XCTAssertFalse(close(conv: nil))                               // can't be resumed
        XCTAssertFalse(close(agent: .codex))                           // no Resume for Codex yet
        XCTAssertTrue(close(agent: .shell, conv: nil))                 // a plain terminal at its prompt
        XCTAssertFalse(close(agent: .shell, conv: nil, prompt: false)) // something runs in it
        XCTAssertFalse(close(hours: -1))                               // Never
    }

    /// LAB-1535: the line under a finished terminal says when it closes and where the conversation lives.
    func test_LAB1535_endedLine() {
        XCTAssertEqual(FinishedShellPolicy.endedLine(agent: .claude, minutes: 10),
                       "Claude session ended. This terminal closes in 10 minutes. The conversation stays in All sessions (⌃⌘O), where you can resume it any time.")
        XCTAssertEqual(FinishedShellPolicy.endedLine(agent: .claude, minutes: -1),
                       "Claude session ended. The conversation stays in All sessions (⌃⌘O), where you can resume it any time.")
        XCTAssertFalse(FinishedShellPolicy.endedLine(agent: .codex, minutes: 10).contains("All sessions"))
    }
}
