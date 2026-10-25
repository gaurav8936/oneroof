import XCTest
@testable import OneRoofCore

/// LAB-799: files open as tabs beside the terminals, never in place of them.
final class CentreTabsTests: XCTestCase {
    // Every file opened gets one tab, in the order opened; opening it again does not add a second.
    func testOpeningAFileAddsOneTab() {
        var tabs = CentreTabs.opening("/a.md", in: [])
        tabs = CentreTabs.opening("/b.png", in: tabs)
        tabs = CentreTabs.opening("/a.md", in: tabs)
        XCTAssertEqual(tabs, ["/a.md", "/b.png"])
    }

    // Search and Review changes are views, not files: no tab.
    func testSpecialViewsGetNoTab() {
        XCTAssertEqual(CentreTabs.opening("search:", in: ["/a.md"], isFile: false), ["/a.md"])
    }

    // Closing the last file brings the terminals back.
    func testClosingTheLastFileShowsTheTerminals() {
        XCTAssertNil(CentreTabs.showing(afterClosing: "/a.md", in: ["/a.md"], showing: "/a.md"))
    }

    // Closing the file in front shows its right neighbour, else its left one.
    func testClosingTheFrontFileShowsANeighbour() {
        let tabs = ["/a", "/b", "/c"]
        XCTAssertEqual(CentreTabs.showing(afterClosing: "/b", in: tabs, showing: "/b"), "/c")
        XCTAssertEqual(CentreTabs.showing(afterClosing: "/c", in: tabs, showing: "/c"), "/b")
    }

    // Closing a tab in the background leaves the view alone, including the terminals.
    func testClosingABackgroundTabKeepsTheView() {
        XCTAssertEqual(CentreTabs.showing(afterClosing: "/a", in: ["/a", "/b"], showing: "/b"), "/b")
        XCTAssertNil(CentreTabs.showing(afterClosing: "/a", in: ["/a", "/b"], showing: nil))
    }
}
