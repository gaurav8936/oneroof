import XCTest
@testable import OneRoofCore

final class PickerSearchTests: XCTestCase {
    /// LAB-1559: every word, any order, any case; an empty query keeps every row.
    func test_LAB1559_everyWordAnyOrderAnyCase() {
        let row = "LAB-ONEROOF-BUGS · One Roof bug fixes"
        XCTAssertTrue(PickerSearch.matches("", row))
        XCTAssertTrue(PickerSearch.matches("bugs oneroof", row))
        XCTAssertTrue(PickerSearch.matches("ROOF  fixes", row))
        XCTAssertFalse(PickerSearch.matches("energy", row))
        let rows = ["LAB-AE · Agentic Engineering", "LAB-ENERGYLAB-LAYERING · Regulatory layering", "LAB-ONEROOF-BUGS · One Roof bug fixes"]
        XCTAssertEqual(PickerSearch.filter(rows, query: "lab energy", text: { $0 }), ["LAB-ENERGYLAB-LAYERING · Regulatory layering"])
    }

    /// LAB-1571: Active only = In Progress projects; started issues (In Progress, In Review).
    func test_LAB1571_activeOnly() {
        XCTAssertTrue(ActiveFilter.project("started"))
        for st in ["planned", "backlog", "paused", "completed", "canceled"] { XCTAssertFalse(ActiveFilter.project(st), st) }
        XCTAssertTrue(ActiveFilter.issue("started"))
        for st in ["backlog", "unstarted", "triage", "completed", "canceled"] { XCTAssertFalse(ActiveFilter.issue(st), st) }
    }
}

final class TrafficLightTests: XCTestCase {
    /// LAB-1620 / LAB-1783: macOS's spacing (20 pt, 14 pt buttons) centred in the 66 pt rail: 6 pt each side.
    func test_LAB1620_buttonsSitInsideTheRail() {
        let x = V2Layout.trafficLightsStart(rail: 66, gap: 20, button: 14)
        XCTAssertEqual(x, 6)
        XCTAssertEqual(66 - (x + 2 * 20 + 14), x)
    }

    /// LAB-1783: the Focus lane is as wide as the rail, so the buttons sit inside it too.
    func test_LAB1783_focusLaneHoldsTheButtons() {
        XCTAssertEqual(V2Layout.focusLane, V2Layout.railWidth)
        XCTAssertEqual(V2Layout.columnWidth(step: .focus, saved: 320), V2Layout.railWidth)
    }
}
