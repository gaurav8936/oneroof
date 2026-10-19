import XCTest
@testable import OneRoofCore

final class WorkspaceSearchTests: XCTestCase {
    func testFindsReposAndSearchesTrackedUntrackedButNotIgnored() throws {
        let root = NSTemporaryDirectory() + "oneroof-search-\(UUID().uuidString)"
        let fm = FileManager.default
        defer { try? fm.removeItem(atPath: root) }
        let repo = root + "/labs/kit", data = root + "/labs/web-data", top = root + "/_common"
        for d in [repo, data, top] { try fm.createDirectory(atPath: d, withIntermediateDirectories: true) }
        for r in [repo, top, data] { _ = Foundations.run(GitDiff.git, ["-C", r, "init", "-q"]) }
        try "let Needle = 1\nother\n".write(toFile: repo + "/a.swift", atomically: true, encoding: .utf8)
        try "needle in untracked\n".write(toFile: repo + "/b.md", atomically: true, encoding: .utf8)
        try "ignored.txt\n".write(toFile: repo + "/.gitignore", atomically: true, encoding: .utf8)
        try "needle ignored\n".write(toFile: repo + "/ignored.txt", atomically: true, encoding: .utf8)
        _ = Foundations.run(GitDiff.git, ["-C", repo, "add", "a.swift"])

        let repos = WorkspaceSearch.repos(root: root)
        XCTAssertEqual(repos, [top, repo], "data folders are skipped")

        let hits = WorkspaceSearch.search("needle", repos: repos)
        XCTAssertEqual(Set(hits.map { ($0.path as NSString).lastPathComponent }), ["a.swift", "b.md"])
        XCTAssertEqual(hits.first { $0.path.hasSuffix("a.swift") }?.line, 1)
        XCTAssertEqual(hits.first { $0.path.hasSuffix("a.swift") }?.text, "let Needle = 1")
        XCTAssertEqual(WorkspaceSearch.search("Needle", repos: repos, caseSensitive: true).count, 1)
        XCTAssertTrue(WorkspaceSearch.search("n", repos: repos).isEmpty, "one letter is too short")
    }
}

final class RoofLinkTests: XCTestCase {
    func testParseLinksAndRefuseUnsafeOnes() {
        let root = Workspace.projectsRoot
        func p(_ s: String) -> RoofLink? { RoofLink.parse(URL(string: s)!) }
        XCTAssertEqual(p("oneroof://session/abc-123"), .session("abc-123"))
        XCTAssertEqual(p("oneroof://objective/xyz"), .objective("xyz"))
        XCTAssertEqual(p("oneroof://view/board"), .view("board", query: nil))
        XCTAssertEqual(p("oneroof://view/search?q=PaneTree"), .view("search", query: "PaneTree"))
        XCTAssertNil(p("oneroof://view/settings"))
        XCTAssertEqual(p("oneroof://open?path=\(root)/_common/README.md&line=12"), .file(root + "/_common/README.md", line: 12))
        XCTAssertNil(p("oneroof://open?path=/etc/passwd"), "outside ~/Projects")
        XCTAssertNil(p("oneroof://open?path=\(root)/../.ssh/id_rsa"), "no escaping with ..")
        XCTAssertEqual(p("oneroof://new?agent=kimi&repo=\(root)/acme/web&name=Docs"),
                       .plan(agent: .kimi, repo: root + "/acme/web", name: "Docs", message: ""))
        XCTAssertNil(p("oneroof://new?repo=/tmp"))
        XCTAssertNil(p("https://example.com/session/x"))
        XCTAssertEqual(RoofLink.link(session: "s1"), "oneroof://session/s1")
    }
}
