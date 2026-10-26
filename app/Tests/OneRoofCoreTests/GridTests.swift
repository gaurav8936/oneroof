import XCTest
@testable import OneRoofCore

final class GridTests: XCTestCase {
    func testGridIsTwoByTwoOrThreeByTwoWithSessionsInOrder() {
        let g = PaneNode.grid(["a", "b", "c"], wide: false)
        XCTAssertEqual(g.leaves.map(\.session), ["a", "b", "c", nil])
        XCTAssertEqual(g.leaves.map(\.id), ["grid-0", "grid-1", "grid-2", "grid-3"])
        let w = PaneNode.grid(["a", "b", "c", "d", "e", "f", "g"], wide: true)
        XCTAssertEqual(w.leaves.count, 6)
        XCTAssertEqual(w.leaves.last?.session, "f")
    }

    func testGridTilesAreEqual() {
        let (panes, _) = PaneNode.grid(Array(repeating: nil, count: 6), wide: true).layout(in: CGRect(x: 0, y: 0, width: 1200, height: 800), gap: 0)
        let widths = Set(panes.values.map { Int($0.width.rounded()) })
        let heights = Set(panes.values.map { Int($0.height.rounded()) })
        XCTAssertEqual(widths, [400])
        XCTAssertEqual(heights, [400])
    }
}
