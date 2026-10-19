import XCTest
@testable import OneRoofCore

final class PaneTreeTests: XCTestCase {
    func testSplitRemoveSetAndNeighbors() throws {
        let a = PaneLeaf(id: "a", session: "s1")
        var t = PaneNode.leaf(a)
        t = t.splitting("a", sideBySide: true, new: PaneLeaf(id: "b"))      // a | b
        t = t.splitting("b", sideBySide: false, new: PaneLeaf(id: "c"))     // a | (b / c)
        XCTAssertEqual(t.leaves.map(\.id), ["a", "b", "c"])
        XCTAssertNil(t.leaf("b")?.session)
        t = t.setting("c", session: "s2")
        XCTAssertEqual(t.leafShowing("s2")?.id, "c")

        XCTAssertEqual(t.neighbor(of: "a", .right), "b", "both touch a; a tie goes to the top one")
        XCTAssertEqual(t.neighbor(of: "b", .down), "c")
        XCTAssertEqual(t.neighbor(of: "c", .up), "b")
        XCTAssertEqual(t.neighbor(of: "c", .left), "a")
        XCTAssertNil(t.neighbor(of: "a", .left))

        let (panes, dividers) = t.layout(in: CGRect(x: 0, y: 0, width: 201, height: 101), gap: 1)
        XCTAssertEqual(panes["a"], CGRect(x: 0, y: 0, width: 100, height: 101))
        XCTAssertEqual(panes["b"], CGRect(x: 101, y: 0, width: 100, height: 50))
        XCTAssertEqual(panes["c"], CGRect(x: 101, y: 51, width: 100, height: 50))
        XCTAssertEqual(dividers.count, 2)
        XCTAssertEqual(dividers.first { $0.sideBySide }?.path, [])
        XCTAssertEqual(dividers.first { !$0.sideBySide }?.path, [true])

        let wide = t.settingRatio(at: [], 0.95)
        guard case .split(_, let r, _, _) = wide else { return XCTFail() }
        XCTAssertEqual(r, 0.9, "clamped")
        guard case .split(_, let r2, _, _) = wide.evened() else { return XCTFail() }
        XCTAssertEqual(r2, 0.5)

        t = try XCTUnwrap(t.removing("b"))                                    // a | c
        XCTAssertEqual(t.leaves.map(\.id), ["a", "c"])
        t = try XCTUnwrap(t.removing("a"))
        XCTAssertEqual(t, .leaf(PaneLeaf(id: "c", session: "s2")))
        XCTAssertNil(t.removing("c"))

        let back = try JSONDecoder().decode(PaneNode.self, from: JSONEncoder().encode(wide))
        XCTAssertEqual(back, wide)
    }
}


final class ShortcutTests: XCTestCase {
    func testDisplayAndParseRoundTrip() {
        let s = Shortcut(key: "D", command: true, shift: true)
        XCTAssertEqual(s.display, "⇧⌘D")
        XCTAssertEqual(Shortcut("⇧⌘D"), s)
        XCTAssertEqual(Shortcut("⌘⇧D"), s, "modifier order does not matter")
        XCTAssertEqual(Shortcut("⌃`")?.display, "⌃`")
        XCTAssertEqual(Shortcut("⌘⌥←"), Shortcut(key: "←", command: true, option: true))
        XCTAssertNil(Shortcut("⌘"))
        XCTAssertFalse(Shortcut(key: "d", shift: true).isUsableGlobally)
        XCTAssertTrue(Shortcut(key: "`", control: true).isUsableGlobally)
    }
}
