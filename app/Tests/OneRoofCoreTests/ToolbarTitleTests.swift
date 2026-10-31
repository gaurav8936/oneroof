import XCTest
@testable import OneRoofCore

/// LAB-1932 · the toolbar title never draws over the window buttons, the places icon row or the right-hand items, in
/// any place, layout (side, Focus, wide, folded) or width. The live check is the self-test step `barsweep`; these
/// tests pin the geometry it relies on.
final class ToolbarTitleTests: XCTestCase {
    typealias S = V2Layout.BarSpan

    /// Where the title text draws for a slot (item at itemX, its natural width), clamped by the slot.
    private func drawn(_ slot: V2Layout.TitleSlot, itemX: Double, natural: Double) -> S? {
        guard slot.maxWidth > 0 else { return nil }
        let x = itemX + V2Layout.Bar.titleLead + slot.shift
        return S("title", x, x + min(natural, slot.maxWidth))
    }

    func test_LAB1932_overlapGuardFailsOnAnyCrossing() {
        let title = S("title", 100, 200)
        XCTAssertEqual(V2Layout.barOverlaps(title: title, others: [S("places", 91, 289)]), ["places"])
        XCTAssertEqual(V2Layout.barOverlaps(title: title, others: [S("new", 199, 280)]), ["new"])
        XCTAssertEqual(V2Layout.barOverlaps(title: title, others: [S("lights", 8, 60), S("layout", 200, 340)]), [], "touching is not crossing")
        XCTAssertEqual(V2Layout.barOverlaps(title: nil, others: [S("places", 91, 289)]), [], "a hidden title crosses nothing")
        XCTAssertEqual(V2Layout.barOverlaps(title: title, others: [S("placeholder", 150, 151)]), [], "1 pt placeholders are not items")
    }

    /// The owner's screenshot (1.9.33): Needs you with the rail folded. The icon row sits 91…289, the title item after
    /// it, and the centre starts at the window's edge, so LAB-1783's shift alone moved the text back over the icons.
    func test_LAB1932_needsYouFoldedRailTitleStaysRightOfTheIconRow() {
        let places = S("places", 91, 289), right = [S("step", 900, 1000), S("new", 1010, 1090)]
        let itemX = 299.0
        let old = V2Layout.titleShift(itemX: itemX, centreX: 0, lightsEnd: 60)
        XCTAssertFalse(V2Layout.barOverlaps(title: S("title", itemX + 8 + old, itemX + 8 + old + 160), others: [places]).isEmpty,
                       "the 1.9.33 placement crossed the icon row (the bug)")
        let slot = V2Layout.titleSlot(itemX: itemX, centreX: 0, lightsEnd: 60, left: [places], right: right, windowWidth: 1100)
        XCTAssertEqual(V2Layout.barOverlaps(title: drawn(slot, itemX: itemX, natural: 160), others: [places] + right + [S("lights", 8, 60)]), [])
    }

    func test_LAB1932_titleStillLinesUpWithTheCentreWhenThereIsRoom() {
        // LAB-1783 kept: Full step, nothing left of the title but the lights; the text starts 20 pt into the centre.
        let slot = V2Layout.titleSlot(itemX: 281, centreX: 269, lightsEnd: 60, left: [], right: [S("new", 1300, 1386)], windowWidth: 1400)
        XCTAssertEqual(slot.shift, 0)
        XCTAssertEqual(slot.maxWidth, 1300 - 8 - 289)
    }

    func test_LAB1932_rightItemsBoundTheTitleAndNoRoomHidesIt() {
        let slot = V2Layout.titleSlot(itemX: 100, centreX: 269, lightsEnd: 60, left: [], right: [S("layout", 400, 540)], windowWidth: 800)
        XCTAssertEqual(slot.maxWidth, 400 - 8 - 289, "moved right past the column, it ends before Single · Grid · Wall")
        let none = V2Layout.titleSlot(itemX: 300, centreX: 0, lightsEnd: 60, left: [S("places", 91, 289)], right: [S("step", 320, 420)], windowWidth: 600)
        XCTAssertEqual(none.maxWidth, 0, "less than the minimum: hidden, never squeezed over a neighbour")
        let edge = V2Layout.titleSlot(itemX: 100, centreX: 269, lightsEnd: 60, left: [], right: [], windowWidth: 500)
        XCTAssertEqual(edge.maxWidth, 500 - V2Layout.Bar.trailing - 8 - 289, "with everything in », the window's edge bounds it")
    }

    /// Every layout × width × left/right arrangement the toolbar can produce: the placed title crosses nothing.
    func test_LAB1932_sweepNoPlacementEverCrossesANeighbour() {
        let lights = S("lights", 8, 60)
        for width in stride(from: 600.0, through: 1800, by: 25) {
            for placesRow in [false, true] {
                for centreX in [0.0, 52, 66, 160, 269, 303, 420] {
                    let left = placesRow ? [S("places", 91, 289)] : []
                    let itemX = placesRow ? 299.0 : 101
                    for rightCount in 0...3 {
                        var right: [S] = [], x = width - V2Layout.Bar.trailing
                        for (name, w) in [("new", 86.0), ("step", 136), ("layout", 140)].prefix(rightCount) { right.insert(S(name, x - w, x), at: 0); x -= w + 10 }
                        for natural in [30.0, 160, 600] {
                            let slot = V2Layout.titleSlot(itemX: itemX, centreX: centreX, lightsEnd: 60, left: left, right: right, windowWidth: width)
                            let t = drawn(slot, itemX: itemX, natural: natural)
                            XCTAssertEqual(V2Layout.barOverlaps(title: t, others: [lights] + left + right), [],
                                           "w \(width) row \(placesRow) centre \(centreX) right \(rightCount) natural \(natural)")
                            if let t { XCTAssertLessThanOrEqual(t.maxX, width - V2Layout.Bar.trailing) }
                        }
                    }
                }
            }
        }
    }

    func test_LAB1932_needsListWidthClampsAndLeavesTheDetailRoom() {
        XCTAssertEqual(V2Layout.needsListWidth(saved: nil, available: 1400), 340)
        XCTAssertEqual(V2Layout.needsListWidth(saved: 100, available: 1400), 240)
        XCTAssertEqual(V2Layout.needsListWidth(saved: 900, available: 1400), 560)
        XCTAssertEqual(V2Layout.needsListWidth(saved: 500, available: 700), 400, "the detail keeps its 300 pt first")
        XCTAssertEqual(V2Layout.needsListWidth(saved: 500, available: 400), 240, "never below the minimum")
    }
}
