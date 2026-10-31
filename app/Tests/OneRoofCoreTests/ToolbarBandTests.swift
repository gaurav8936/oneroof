import XCTest
@testable import OneRoofCore

/// LAB-1938 · the toolbar band takes each column's colour, but the right-hand group (player, Single · Grid · Wall ·
/// Scroll, Focus step, + New) always sits on ONE colour, the centre's. The live check is `barcheck` / `barsweep`
/// ("toolbar group one band"); this pins the rule in every arrangement.
final class ToolbarBandTests: XCTestCase {
    typealias S = V2Layout.BarSpan

    /// The owner's case: Full step at 1400 pt. Rail · column · centre · Plan, the group 994…1386, the Plan from 1131.
    func test_LAB1938_fullStepGroupNoLongerStraddlesThePlanBand() {
        let cols: [(Double, String)] = [(66, "rail"), (269, "column"), (1131, "centre"), (1400, "plan")]
        let group = S("group", 994, 1386)
        XCTAssertEqual(V2Layout.bandColours(under: group, segments: cols), ["centre", "plan"], "1.9.34 painted two colours (the bug)")
        let segs = V2Layout.bandSegments(columns: cols, group: group, groupColour: "centre", windowWidth: 1400)
        XCTAssertEqual(V2Layout.bandColours(under: group, segments: segs), ["centre"])
        XCTAssertEqual(segs.map(\.0), [66, 269, 1400])
        XCTAssertEqual(segs.map(\.1), ["rail", "column", "centre"])
    }

    func test_LAB1938_columnsAwayFromTheGroupKeepTheirColours() {
        // Plan wider than the group needs: its colour starts after the group's far edge.
        let cols: [(Double, String)] = [(66, "rail"), (500, "column"), (900, "centre"), (1700, "plan")]
        let segs = V2Layout.bandSegments(columns: cols, group: S("group", 850, 1100), groupColour: "centre", windowWidth: 1700)
        XCTAssertEqual(segs.map(\.0), [66, 500, 1108, 1700])
        XCTAssertEqual(segs.map(\.1), ["rail", "column", "centre", "plan"])
        // No group (everything in »): the columns as they are.
        let none = V2Layout.bandSegments(columns: cols, group: nil, groupColour: "centre", windowWidth: 1700)
        XCTAssertEqual(none.map(\.0), cols.map(\.0))
    }

    /// Every width × Plan width × group width: the group is on one colour, and every column left of it keeps its edge.
    func test_LAB1938_sweepGroupAlwaysOnOneColour() {
        for width in stride(from: 600.0, through: 1800, by: 50) {
            for plan in [0.0, 28, 240, 300, 420] where width - plan > 400 {
                for groupW in [90.0, 200, 300, 410, 520] where groupW < width - 300 {
                    let cols: [(Double, String)] = [(66, "rail"), (269, "column"), (width - plan, "centre")] + (plan > 0 ? [(width, "plan")] : [])
                    let g = S("group", width - 14 - groupW, width - 14)
                    let segs = V2Layout.bandSegments(columns: cols, group: g, groupColour: "centre", windowWidth: width)
                    XCTAssertEqual(V2Layout.bandColours(under: g, segments: segs), ["centre"], "w \(width) plan \(plan) group \(groupW)")
                    XCTAssertEqual(segs.prefix(2).map(\.0), [66, 269], "columns left of the group keep their edges")
                    XCTAssertEqual(segs.last?.0, width, "the band reaches the window's edge")
                }
            }
        }
    }
}
