import XCTest
@testable import OneRoofCore

/// LAB-606: the attach client says hello only once its terminal size has settled.
final class TerminalSizeTests: XCTestCase {
    func testSettlesOnlyAfterTheSizeStopsChanging() {
        var s = SizeSettle(needed: 3)
        XCTAssertFalse(s.read(cols: 50, rows: 17), "the surface's default size")
        XCTAssertFalse(s.read(cols: 120, rows: 40), "laid out in its pane")
        XCTAssertFalse(s.read(cols: 120, rows: 40))
        XCTAssertTrue(s.read(cols: 120, rows: 40))
        XCTAssertEqual(s.cols, 120); XCTAssertEqual(s.rows, 40)
    }

    func testZeroSizeNeverSettles() {
        var s = SizeSettle(needed: 2)
        XCTAssertFalse(s.read(cols: 0, rows: 0))
        XCTAssertFalse(s.read(cols: 0, rows: 0))
    }
}

/// LAB-657: Wrap for reading shows the terminal's text tidied for a word-wrapping view.
final class ReadingTextTests: XCTestCase {
    func testTidiesTerminalText() {
        let raw = "\n\nbuilding   \r\nwarning: a long line that the terminal wrapped at the edge\n\n\n\n185 |   code\n\n  \n"
        XCTAssertEqual(ReadingText.prepare(raw), "building\nwarning: a long line that the terminal wrapped at the edge\n\n185 |   code")
    }

    func testKeepsTheLastLines() {
        let raw = (1...10).map(String.init).joined(separator: "\n")
        XCTAssertEqual(ReadingText.prepare(raw, maxLines: 3), "8\n9\n10")
    }
}
