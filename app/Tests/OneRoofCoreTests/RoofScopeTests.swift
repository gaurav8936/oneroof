import XCTest
@testable import OneRoofCore

final class RoofScopeTests: XCTestCase {
    private let root = Workspace.projectsRoot
    private func item(_ name: String, repo: String, ws: String?, live: Bool) -> BoardItem {
        let s = Session(name: name, agent: .claude, repoPath: root + "/" + repo, workstream: ws, lifecycle: live ? .running : .planned)
        return BoardItem(id: s.id, session: s, status: live ? .running : .planned, liveAgent: live ? "a-" + name : nil,
                         paneId: nil, workspaceId: nil, detectedAccount: nil, adopted: false, title: nil)
    }

    func testScopeMembershipAndMenu() {
        let items = [item("one", repo: "acme/web", ws: "WS-WEB-12", live: true),
                     item("two", repo: "acme/web", ws: "ws-web-12", live: true),
                     item("planned", repo: "acme/web", ws: "WS-WEB-12", live: false),
                     item("gg", repo: "acme/api", ws: nil, live: true)]
        let repo = RoofScope.repo(root + "/acme/web")
        XCTAssertEqual(repo.sessions(in: items).map(\.session.name), ["one", "two"], "planned rows have no terminal")
        XCTAssertEqual(RoofScope.workstream("WS-WEB-12").sessions(in: items).count, 2, "workstream match ignores case")
        let menu = RoofScope.available(in: items)
        XCTAssertEqual(menu.map(\.count), [1, 2, 2])
        XCTAssertEqual(menu.last?.scope, .workstream("WS-WEB-12"))
        XCTAssertEqual(menu.first?.scope.title, Workspace.repoLabel(for: root + "/acme/api"))
        let data = try! JSONEncoder().encode(repo)
        XCTAssertEqual(try! JSONDecoder().decode(RoofScope.self, from: data), repo)
    }

    func testGrid() throws {
        XCTAssertNil(PaneNode.grid([]))
        XCTAssertEqual(PaneNode.grid(["a"]), .leaf(PaneLeaf(id: "a", session: "a")))
        let five = try XCTUnwrap(PaneNode.grid(["a", "b", "c", "d", "e"]))
        XCTAssertEqual(five.leaves.map(\.session), ["a", "b", "c", "d", "e"])
        let panes = five.layout(in: CGRect(x: 0, y: 0, width: 302, height: 201), gap: 1).panes
        XCTAssertEqual(Set(panes.values.map(\.minY)).count, 2, "two rows")
        XCTAssertEqual(panes.values.filter { $0.minY == 0 }.count, 3, "three columns in the first row")
        XCTAssertEqual(panes["a"]?.width ?? 0, panes["b"]?.width ?? 0, accuracy: 1, "even columns")
        XCTAssertEqual(panes["d"]?.width ?? 0, 150.5, accuracy: 1, "the short row splits its width evenly")
    }
}
