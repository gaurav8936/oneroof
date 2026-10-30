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
    /// LAB-1620: macOS's spacing (20 pt, 14 pt buttons) puts the zoom button 4 pt inside the 66 pt rail.
    func test_LAB1620_buttonsSitInsideTheRail() {
        let x = V2Layout.trafficLightsStart(rail: 66, gap: 20, button: 14)
        XCTAssertEqual(x, 8)
        XCTAssertLessThanOrEqual(x + 2 * 20 + 14, 66 - 4)
    }
}
