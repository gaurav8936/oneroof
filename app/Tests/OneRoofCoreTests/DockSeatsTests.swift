import XCTest
@testable import OneRoofCore

/// LAB-1998 · the bottom bar shows every agent set up on this Mac (was a fixed C1 · C2 · CX · KM · GM), minus the ones
/// hidden in Settings › Seats & accounts; one list for the dock, its compact line and the rail.
final class DockSeatsTests: XCTestCase {
    let all = DockSeats.Facts(claudeAccounts: ["Claude1", "Claude2"], installed: [.claude, .codex, .gemini, .kimi, .agy],
                              hostedReady: [.opencode, .goose])

    func test_newAgentsAppear_inOneOrder() {
        XCTAssertEqual(DockSeats.shown(all, hidden: []).map(\.mono), ["C1", "C2", "CX", "GM", "KM", "AG", "OC", "GS"])
    }

    func test_onlyWhatIsSetUp() {
        let f = DockSeats.Facts(claudeAccounts: ["Claude1"], installed: [.claude, .codex], hostedReady: [])
        XCTAssertEqual(DockSeats.shown(f, hidden: []), [.claude1, .codex])
    }

    func test_usageMeansSetUp_evenWhenTheCLIWasNotFound() {
        let f = DockSeats.Facts(claudeAccounts: ["Claude1"], installed: [.claude], hostedReady: [])
        XCTAssertEqual(DockSeats.shown(f, hidden: [], usageSeats: ["Kimi"]), [.claude1, .kimi])
    }

    func test_hiddenInSettings_leavesTheBar_andComesBack() {
        XCTAssertFalse(DockSeats.shown(all, hidden: ["gemini", "goose"]).contains(.gemini))
        XCTAssertFalse(DockSeats.shown(all, hidden: ["gemini", "goose"]).contains(.goose))
        XCTAssertEqual(DockSeats.shown(all, hidden: []).count, 8)
    }

    func test_hostedAgentsNeedTheRuntimeAndAConnection() {
        var s = AppSettings()
        XCTAssertEqual(DockSeats.facts(settings: s, home: "/nonexistent").hostedReady, [])
        s.hostedRuntime = HostedRuntimeConfiguration(pythonExecutable: "/usr/bin/python3", kitDirectory: "/tmp",
                                                     nativeExecutables: ["opencode": "/bin/sh"], storageDirectory: "/tmp")
        XCTAssertEqual(DockSeats.facts(settings: s, home: "/nonexistent").hostedReady, [], "no saved connection yet")
    }

    func test_usageNames_matchTheUsageFeed() {
        XCTAssertEqual(DockSeats.usageName(.claude2), "Claude2")
        XCTAssertNil(DockSeats.usageName(.antigravity))
    }

    func test_settingsDecode_withoutDockHidden_isEmpty() throws {
        let d = try JSONEncoder().encode(AppSettings())
        var j = try JSONSerialization.jsonObject(with: d) as! [String: Any]
        j.removeValue(forKey: "dockHidden")
        let back = try JSONDecoder().decode(AppSettings.self, from: JSONSerialization.data(withJSONObject: j))
        XCTAssertEqual(back.dockHidden, [])
    }
}
