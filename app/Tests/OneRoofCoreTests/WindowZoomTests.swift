import XCTest
@testable import OneRoofCore

/// LAB-520 / LAB-596 / LAB-653: the window's frame changes only when the owner changes it.
final class WindowZoomTests: XCTestCase {
    let screen = CGRect(x: 0, y: 0, width: 1728, height: 1080)

    func testDoubleClickNeverShrinksAFullWindow() {
        let full = CGRect(x: 0, y: 0, width: 1728, height: 1075)
        let small = CGRect(x: 100, y: 300, width: 1100, height: 700)
        XCTAssertFalse(WindowZoom.allow(current: full, to: small, visible: screen, fromTitleBarDoubleClick: true))
        XCTAssertTrue(WindowZoom.allow(current: full, to: small, visible: screen, fromTitleBarDoubleClick: false), "Window › Zoom still works")
        XCTAssertTrue(WindowZoom.allow(current: small, to: full, visible: screen, fromTitleBarDoubleClick: true), "growing is fine")
    }

    /// LAB-653: a window on the right half of the screen is not "full", and a double-click shrank it to an older frame.
    func testDoubleClickNeverShrinksAHalfScreenWindow() {
        let rightHalf = CGRect(x: 864, y: 0, width: 864, height: 1075)
        let older = CGRect(x: 200, y: 300, width: 700, height: 600)
        XCTAssertFalse(WindowZoom.allow(current: rightHalf, to: older, visible: screen, fromTitleBarDoubleClick: true))
        XCTAssertFalse(WindowZoom.allow(current: rightHalf, to: older, visible: nil, fromTitleBarDoubleClick: true))
    }

    func testQuickClicksOnToolbarControlsAreNotADoubleClick() {
        let tabs = CGRect(x: 85, y: 10, width: 518, height: 30)
        XCTAssertEqual(WindowZoom.toolbarClickCount(2, at: CGPoint(x: 300, y: 20), controls: [tabs]), 1)
        XCTAssertEqual(WindowZoom.toolbarClickCount(2, at: CGPoint(x: 800, y: 20), controls: [tabs]), 2, "empty toolbar space")
        XCTAssertEqual(WindowZoom.toolbarClickCount(1, at: CGPoint(x: 300, y: 20), controls: [tabs]), 1)
    }

    /// LAB-596: every panel open still fits the smallest window, so AppKit never grows the window to make room.
    func testAllPanelsFitTheSmallestWindow() {
        XCTAssertLessThanOrEqual(PanelMinimums.allOpen, PanelMinimums.windowWidth)
    }
}

/// LAB-651 / LAB-714: the Sessions panel is a rail only while it is narrow.
final class SessionsRailTests: XCTestCase {
    func testRailOnlyWhenNarrow() {
        XCTAssertTrue(SessionsRail.shows(width: PanelMinimums.sessionsRail))
        XCTAssertFalse(SessionsRail.shows(width: PanelMinimums.sessions), "the full panel's minimum shows the list")
        XCTAssertFalse(SessionsRail.shows(width: 640), "dragged wide while the Editor is open: the full list")
        XCTAssertFalse(SessionsRail.shows(width: 0), "not laid out yet: the full list, never a stuck rail")
    }
}

/// LAB-715: the panel toggles are the last toolbar item to overflow.
final class ToolbarSlotTests: XCTestCase {
    func testPanelTogglesStayLongest() {
        for s in ToolbarSlot.allCases where s != .panels { XCTAssertGreaterThan(ToolbarSlot.panels.keepRank, s.keepRank, s.rawValue) }
        XCTAssertLessThan(ToolbarSlot.workspace.keepRank, ToolbarSlot.switcher.keepRank)
        XCTAssertLessThan(ToolbarSlot.search.keepRank, ToolbarSlot.workspace.keepRank)
    }
}
