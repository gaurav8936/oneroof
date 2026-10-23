import XCTest
@testable import OneRoofCore

/// LAB-197: when One Roof shows a desktop notification.
final class NotificationTests: XCTestCase {
    let t0 = Date(timeIntervalSince1970: 1_800_000_000)
    let prefs = NotePrefs()

    func ev(_ k: NoteKind, _ s: String = "s1", detail: String? = nil, duration: TimeInterval? = nil, exit: Int? = nil, at: TimeInterval = 0) -> NoteEvent {
        NoteEvent(kind: k, sessionId: s, sessionName: "Fix login", detail: detail, duration: duration, exitCode: exit, at: t0.addingTimeInterval(at))
    }

    func testNeedsYouUsesTheDecisionTitleAndReplacesByIdentifier() {
        var g = NoteGate()
        let n = g.decide(ev(.needsYou, detail: "Claude wants to run swift test"), prefs: prefs, appActive: false, focusedSession: nil)
        XCTAssertEqual(n?.title, "Fix login needs you")
        XCTAssertEqual(n?.body, "Claude wants to run swift test")
        XCTAssertEqual(n?.identifier, "needsYou-s1")
        XCTAssertEqual(n?.threadIdentifier, "s1")
    }

    func testNothingAboutTheFocusedSessionWhileTheAppIsInFront() {
        var g = NoteGate()
        XCTAssertNil(g.decide(ev(.done), prefs: prefs, appActive: true, focusedSession: "s1"))
        XCTAssertNotNil(g.decide(ev(.done, "s2"), prefs: prefs, appActive: true, focusedSession: "s1"), "another session still notifies")
        XCTAssertNotNil(g.decide(ev(.done, at: 1), prefs: prefs, appActive: false, focusedSession: "s1"), "app in the background: notify")
    }

    func testSwitchesTurnKindsOff() {
        var g = NoteGate()
        let off = NotePrefs(needsYou: false, done: false, longCommands: false)
        for k in NoteKind.allCases {
            XCTAssertNil(g.decide(ev(k, detail: "x", duration: 999), prefs: off, appActive: false, focusedSession: nil), k.rawValue)
        }
    }

    func testRepeatsOfTheSameKindAreDampened() {
        var g = NoteGate(repeatInterval: 20)
        XCTAssertNotNil(g.decide(ev(.done), prefs: prefs, appActive: false, focusedSession: nil))
        XCTAssertNil(g.decide(ev(.done, at: 5), prefs: prefs, appActive: false, focusedSession: nil))
        XCTAssertNotNil(g.decide(ev(.needsYou, at: 5), prefs: prefs, appActive: false, focusedSession: nil), "another kind is fine")
        XCTAssertNotNil(g.decide(ev(.done, at: 25), prefs: prefs, appActive: false, focusedSession: nil))
    }

    func testRateLimitLetsNeedsYouThrough() {
        var g = NoteGate(repeatInterval: 0, perMinute: 2)
        XCTAssertNotNil(g.decide(ev(.done, "a"), prefs: prefs, appActive: false, focusedSession: nil))
        XCTAssertNotNil(g.decide(ev(.done, "b"), prefs: prefs, appActive: false, focusedSession: nil))
        XCTAssertNil(g.decide(ev(.done, "c"), prefs: prefs, appActive: false, focusedSession: nil))
        XCTAssertNotNil(g.decide(ev(.needsYou, "d"), prefs: prefs, appActive: false, focusedSession: nil))
        XCTAssertNotNil(g.decide(ev(.done, "c", at: 61), prefs: prefs, appActive: false, focusedSession: nil), "a minute later")
    }

    func testLongCommandNeedsTheThreshold() {
        var g = NoteGate()
        XCTAssertNil(g.decide(ev(.longCommand, duration: 12), prefs: prefs, appActive: false, focusedSession: nil))
        let n = g.decide(ev(.longCommand, duration: 95, exit: 0), prefs: prefs, appActive: false, focusedSession: nil)
        XCTAssertEqual(n?.title, "Command finished in Fix login")
        XCTAssertEqual(n?.body, "It ran for 1 min.")
        let f = g.decide(ev(.longCommand, "s2", duration: 40, exit: 2), prefs: prefs, appActive: false, focusedSession: nil)
        XCTAssertEqual(f?.title, "Command failed in Fix login (exit 2)")
        var short = NoteGate()
        XCTAssertNotNil(short.decide(ev(.longCommand, duration: 12), prefs: NotePrefs(longCommandSeconds: 10), appActive: false, focusedSession: nil))
    }

    func testTerminalNotificationsPassThroughButIdenticalOnesDoNotRepeat() {
        var g = NoteGate(repeatInterval: 0)
        let e = NoteEvent(kind: .terminal, sessionId: "s1", sessionName: "build", detail: "Build done", title: "make", at: t0)
        XCTAssertEqual(g.decide(e, prefs: prefs, appActive: false, focusedSession: nil)?.title, "build: make")
        var again = e; again.at = t0.addingTimeInterval(30)
        XCTAssertNil(g.decide(again, prefs: prefs, appActive: false, focusedSession: nil))
        var other = again; other.detail = "Tests done"
        XCTAssertNotNil(g.decide(other, prefs: prefs, appActive: false, focusedSession: nil))
        let empty = NoteEvent(kind: .terminal, sessionId: "s1", sessionName: "build", at: t0)
        XCTAssertNil(NoteGate.compose(empty))
        // The agent's own "waiting for input" after One Roof's needs-you note is not repeated.
        XCTAssertNotNil(g.decide(ev(.needsYou, "s9", at: 100), prefs: prefs, appActive: false, focusedSession: nil))
        let cli = NoteEvent(kind: .terminal, sessionId: "s9", sessionName: "x", detail: "Claude is waiting for your input", at: t0.addingTimeInterval(102))
        XCTAssertNil(g.decide(cli, prefs: prefs, appActive: false, focusedSession: nil))
    }

    func testStatusChangesThatAreNews() {
        XCTAssertEqual(NoteSignals.statusChange(from: .running, to: .done), .done)
        XCTAssertEqual(NoteSignals.statusChange(from: .needsYou, to: .done), .done)
        XCTAssertNil(NoteSignals.statusChange(from: nil, to: .done), "the app starting up is not news")
        XCTAssertNil(NoteSignals.statusChange(from: .idle, to: .done))
        XCTAssertNil(NoteSignals.statusChange(from: .running, to: .idle))
    }

    func testDurationsAndOldSettings() throws {
        XCTAssertEqual(NoteGate.duration(45), "45 s")
        XCTAssertEqual(NoteGate.duration(3900), "1 h 5 min")
        let old = try JSONDecoder().decode(AppSettings.self, from: Data(#"{"dockBadge":false}"#.utf8))
        XCTAssertTrue(old.notifyNeedsYou && old.notifyDone && old.notifyLongCommands)
        XCTAssertEqual(old.longCommandSeconds, 30)
        XCTAssertEqual(NotePrefs(old), NotePrefs())
    }
}
