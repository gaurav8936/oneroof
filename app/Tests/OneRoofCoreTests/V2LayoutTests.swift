import XCTest
@testable import OneRoofCore

/// 1.8.1 real-profile audit (LAB-1234): launch step for upgraded windows, the Sessions step kept across places, the
/// selected row past the exited cap, dragged widths, and the test-only profile seed filter.
final class V2LayoutTests: XCTestCase {
    func testSavedStepWins() {
        XCTAssertEqual(V2Layout.initialStep(saved: 2, existedBefore: true), .wide)
        XCTAssertEqual(V2Layout.initialStep(saved: 0, existedBefore: false), .full)
    }

    func testWindowFrom0529OpensAtFullAndNewWindowAtSessions() {
        XCTAssertEqual(V2Layout.initialStep(saved: nil, existedBefore: true), .full)
        XCTAssertEqual(V2Layout.initialStep(saved: nil, existedBefore: false), .sessions)
        XCTAssertEqual(V2Layout.initialStep(saved: 9, existedBefore: false), .sessions)   // junk value: the default
    }

    func testSessionsReturnsToItsLastStepOtherPlacesToTheirDefault() {
        XCTAssertEqual(V2Layout.openingStep(.sessions, sessionsStep: nil), .sessions)
        XCTAssertEqual(V2Layout.openingStep(.sessions, sessionsStep: .full), .full)
        XCTAssertEqual(V2Layout.openingStep(.home, sessionsStep: .wide), .full)
        XCTAssertEqual(V2Layout.openingStep(.machine, sessionsStep: nil), .full)
    }

    func testCappedRowsKeepTheSelectedRow() {
        let rows = (1...20).map { "s\($0)" }
        XCTAssertEqual(V2Layout.cappedRows(rows, cap: 4, id: { $0 }, keep: []), ["s1", "s2", "s3", "s4"])
        XCTAssertEqual(V2Layout.cappedRows(rows, cap: 4, id: { $0 }, keep: ["s15"]), ["s1", "s2", "s3", "s4", "s15"])
        XCTAssertEqual(V2Layout.cappedRows(rows, cap: 4, id: { $0 }, keep: ["s2"]), ["s1", "s2", "s3", "s4"])
        XCTAssertEqual(V2Layout.cappedRows(["a", "b"], cap: 4, id: { $0 }, keep: ["x"]), ["a", "b"])
    }

    func testColumnWidthUsesTheDraggedWidthWithinLimits() {
        XCTAssertEqual(V2Layout.columnWidth(step: .sessions, saved: nil), 280)
        XCTAssertEqual(V2Layout.columnWidth(step: .full, saved: nil), 250)
        XCTAssertEqual(V2Layout.columnWidth(step: .wide, saved: nil), 250)
        XCTAssertEqual(V2Layout.columnWidth(step: .full, saved: 320), 320)
        XCTAssertEqual(V2Layout.columnWidth(step: .sessions, saved: 900), 440)
        XCTAssertEqual(V2Layout.columnWidth(step: .sessions, saved: 120), 200)
        XCTAssertEqual(V2Layout.columnWidth(step: .focus, saved: 320), 52)
    }

    func testPlanWidth() {
        XCTAssertEqual(V2Layout.planWidth(saved: nil), 270)
        XCTAssertEqual(V2Layout.planWidth(saved: 300), 300)
        XCTAssertEqual(V2Layout.planWidth(saved: 100), 240)
        XCTAssertEqual(V2Layout.planWidth(saved: 2000), 520)
    }

    func testSeedFilterDropsAppKitAndRoofdKeys() {
        let kept = SeedFilter.keep(["settings": Data(), "focusStep.A": 3, "NSWindow Frame OneRoofMain": "x",
                                    "NSSplitView Subview Frames OneRoofSplit": ["a"], "roofd.registeredBuild": 1.0, "OneRoofPanes.A": Data()])
        XCTAssertEqual(Set(kept.keys), ["settings", "focusStep.A", "OneRoofPanes.A"])
    }
}
