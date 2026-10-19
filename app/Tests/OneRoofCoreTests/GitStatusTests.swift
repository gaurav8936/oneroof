import XCTest
@testable import OneRoofCore

final class GitStatusTests: XCTestCase {
    func testParsesPorcelainV2() {
        let raw = [
            "1 .M N... 100644 100644 100644 abc abc app/Sources/A.swift",
            "1 A. N... 000000 100644 100644 000 abc app/Tests/B.swift",
            "1 D. N... 100644 000000 000000 abc 000 old file.txt",
            "2 R. N... 100644 100644 100644 abc abc R100 new name.swift", "old name.swift",
            "? scratch/notes.md",
        ].joined(separator: "\0") + "\0"
        let b = GitStatus.parse(raw)
        XCTAssertEqual(b["app/Sources/A.swift"], .modified)
        XCTAssertEqual(b["app/Tests/B.swift"], .added)
        XCTAssertEqual(b["old file.txt"], .deleted)
        XCTAssertEqual(b["new name.swift"], .modified)
        XCTAssertNil(b["old name.swift"])
        XCTAssertEqual(b["scratch/notes.md"], .untracked)
        XCTAssertEqual(GitStatus.folderBadge("app", in: b), .added)
        XCTAssertNil(GitStatus.folderBadge("docs", in: b))
    }
}
