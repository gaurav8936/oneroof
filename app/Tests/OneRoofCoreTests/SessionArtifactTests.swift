import XCTest
@testable import OneRoofCore

/// LAB-513: the Artifacts tab lists this session's own files.
final class SessionArtifactTests: XCTestCase {
    func testMergeKeepsNewestFirstWithoutDuplicates() {
        let t = Date()
        let merged = SessionArtifacts.merge(["/a", "/b"], edits: ["/c": t, "/a": t.addingTimeInterval(5)])
        XCTAssertEqual(merged, ["/a", "/c", "/b"])
        XCTAssertEqual(SessionArtifacts.merge((0..<100).map { "/f\($0)" }, edits: [:]).count, SessionArtifacts.cap)
    }

    func testScreenshotsFromTheOpeningMessage() {
        let o = "Fix this.\nAttached image (read it): /Users/x/Library/Caches/OneRoof/pastes/paste-1.png\nand /tmp/shot two.jpg ignored? /tmp/b.JPG"
        XCTAssertEqual(SessionArtifacts.screenshots(in: o), ["/Users/x/Library/Caches/OneRoof/pastes/paste-1.png", "/tmp/b.JPG"])
    }

    func testListIsTheSessionsOwnWithWholeIdHandoffs() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("arts-\(UUID().uuidString)").path
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: dir) }
        for f in ["2026-10-20_lab-oneroof-bugs_x.txt", "2026-10-21_lab-oneroof-v050_y.txt", "2026-10-21_lab-472_z.txt", "2026-10-22_lab-4720_no.txt"] {
            FileManager.default.createFile(atPath: dir + "/" + f, contents: Data())
        }
        var s = Session(name: "x", agent: .claude, repoPath: "/p", workstream: "LAB-ONEROOF-BUGS",
                        openingMessage: "see /tmp/p.png")
        s.ticket = "LAB-472"
        s.writtenFiles = ["/repo/a.swift", "/repo/gone.swift"]
        let items = SessionArtifacts.list(s, plan: "/plans/p.md", handoffDir: dir, exists: { !$0.contains("gone") })
        XCTAssertEqual(items.map(\.kind), [.plan, .written, .handoff, .handoff, .screenshot])
        XCTAssertEqual(items.filter { $0.kind == .handoff }.map { ($0.path as NSString).lastPathComponent },
                       ["2026-10-21_lab-472_z.txt", "2026-10-20_lab-oneroof-bugs_x.txt"], "not lab-oneroof-v050, not lab-4720")
    }
}
