import XCTest
@testable import OneRoofCore

/// LAB-520: a stray toolbar double-click must not shrink a window stretched to fill the screen.
final class WindowZoomTests: XCTestCase {
    let screen = CGRect(x: 0, y: 0, width: 1728, height: 1080)

    func testDoubleClickNeverShrinksAFullWindow() {
        let full = CGRect(x: 0, y: 0, width: 1728, height: 1075)
        let small = CGRect(x: 100, y: 300, width: 1100, height: 700)
        XCTAssertFalse(WindowZoom.allow(current: full, to: small, visible: screen, fromTitleBarDoubleClick: true))
        XCTAssertTrue(WindowZoom.allow(current: full, to: small, visible: screen, fromTitleBarDoubleClick: false), "Window › Zoom still works")
        XCTAssertTrue(WindowZoom.allow(current: small, to: full, visible: screen, fromTitleBarDoubleClick: true), "growing is fine")
        XCTAssertTrue(WindowZoom.allow(current: full, to: small, visible: nil, fromTitleBarDoubleClick: true))
    }
}
