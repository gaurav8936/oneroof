import XCTest
@testable import OneRoofCore

/// LAB-2167: with no ~/Projects the projects folder falls back to home; One Roof must never walk it (macOS would ask
/// for Desktop, Documents and Downloads), and labels name the real folder.
final class HomeFolderNeverListedTests: XCTestCase {
    func test_LAB2167_homeFolderIsNeverListed() throws {
        let home = NSHomeDirectory()
        XCTAssertTrue(Workspace.isHome(home))
        XCTAssertTrue(Workspace.isHome(home + "/"))
        XCTAssertFalse(Workspace.isHome(home + "/Projects"))
        XCTAssertFalse(Workspace.isHome(""))
        XCTAssertEqual(Workspace.listRepos(root: home), [])
        XCTAssertEqual(WorkspaceSearch.repos(root: home), [])
        XCTAssertNil(Trackers.docsFolder(for: "LAB-X", root: home, shared: "/nonexistent"))
    }

    func test_LAB2167_aRealFolderIsStillListed() throws {
        let root = NSTemporaryDirectory() + "lab2167-" + UUID().uuidString
        try FileManager.default.createDirectory(atPath: root + "/labs/app/.git", withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: root) }
        XCTAssertEqual(Workspace.listRepos(root: root).map { ($0 as NSString).lastPathComponent }, ["app"])
    }

    func test_LAB2167_defaultIsProjectsWhenItExists() throws {
        let home = NSTemporaryDirectory() + "lab2167h-" + UUID().uuidString
        try FileManager.default.createDirectory(atPath: home, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: home) }
        XCTAssertEqual(Workspace.defaultProjectsRoot(home: home), home)          // no Projects: home (Setup then asks)
        try FileManager.default.createDirectory(atPath: home + "/Projects", withIntermediateDirectories: true)
        XCTAssertEqual(Workspace.defaultProjectsRoot(home: home), home + "/Projects")
    }
}
