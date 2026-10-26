import XCTest
@testable import OneRoofCore

final class GridTests: XCTestCase {
    func testGridIsAlwaysTwoColumnsWithOneRowPerTwoSessions() {
        let g = PaneNode.grid(["a", "b", "c"], columns: 2)
        XCTAssertEqual(g.leaves.map(\.session), ["a", "b", "c", nil])
        XCTAssertEqual(g.leaves.map(\.id), ["grid-0", "grid-1", "grid-2", "grid-3"])
        let seven = PaneNode.grid(["a", "b", "c", "d", "e", "f", "g"], columns: 2)
        XCTAssertEqual(seven.leaves.count, 8)
        XCTAssertEqual(seven.leaves.map(\.session), ["a", "b", "c", "d", "e", "f", "g", nil])
        // nothing live: one row of two empty tiles to pick into
        XCTAssertEqual(PaneNode.grid([], columns: 2).leaves.map(\.session), [nil, nil])
        XCTAssertEqual(PaneNode.grid(["a"], columns: 2).leaves.map(\.session), ["a", nil])
        // every live session gets a tile (no cap at four or six)
        XCTAssertEqual(PaneNode.grid((0..<11).map { "s\($0)" }, columns: 2).leaves.compactMap(\.session).count, 11)
    }

    func testGridTilesAreEqualAndTwoAcross() {
        let (panes, _) = PaneNode.grid(Array(repeating: nil, count: 6), columns: 2).layout(in: CGRect(x: 0, y: 0, width: 1200, height: 900), gap: 0)
        XCTAssertEqual(Set(panes.values.map { Int($0.width.rounded()) }), [600])
        XCTAssertEqual(Set(panes.values.map { Int($0.height.rounded()) }), [300])
        XCTAssertEqual(Set(panes.values.map { Int($0.minX) }), [0, 600])
    }

    func testGridKeepsReadingOrderForFocusMoves() {
        let g = PaneNode.grid(["a", "b", "c", "d", "e"], columns: 2)
        XCTAssertEqual(g.neighbor(of: "grid-0", .right), "grid-1")
        XCTAssertEqual(g.neighbor(of: "grid-1", .down), "grid-3")
        XCTAssertEqual(g.neighbor(of: "grid-3", .down), "grid-5")
        XCTAssertEqual(g.neighbor(of: "grid-4", .up), "grid-2")
        XCTAssertNil(g.neighbor(of: "grid-4", .down))
    }

    func testGridRowsAndScrollingHeight() {
        XCTAssertEqual(GridMetrics.rows(sessions: 0), 1)
        XCTAssertEqual(GridMetrics.rows(sessions: 1), 1)
        XCTAssertEqual(GridMetrics.rows(sessions: 2), 1)
        XCTAssertEqual(GridMetrics.rows(sessions: 3), 2)
        XCTAssertEqual(GridMetrics.rows(sessions: 9), 5)
        // two rows fit an 800 pt area: no scrolling
        XCTAssertEqual(GridMetrics.contentHeight(rows: 2, viewport: 800, minTile: 330, gap: 2), 800)
        // four rows do not: 4 × 330 + 3 gaps, and the area scrolls
        XCTAssertEqual(GridMetrics.contentHeight(rows: 4, viewport: 800, minTile: 330, gap: 2), 1326)
    }

    func testScrollOffsetBringsATileIntoView() {
        let visible = CGRect(x: 0, y: 300, width: 1000, height: 600)
        XCTAssertEqual(GridMetrics.scrollOffset(showing: CGRect(x: 0, y: 400, width: 500, height: 330), visible: visible), 300)   // already in view
        XCTAssertEqual(GridMetrics.scrollOffset(showing: CGRect(x: 0, y: 0, width: 500, height: 330), visible: visible), 0)       // above
        XCTAssertEqual(GridMetrics.scrollOffset(showing: CGRect(x: 0, y: 800, width: 500, height: 330), visible: visible), 530)   // below
    }
}
