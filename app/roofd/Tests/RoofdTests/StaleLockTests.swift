import Darwin
import XCTest
@testable import roofd

/// LAB-1518: the daemon sweeps lock and socket files that no session holds any more; a live session's are kept.
final class StaleLockTests: XCTestCase {
    func test_LAB1518_staleLocksGoLiveOnesStay() throws {
        let dir = "/tmp/roofd-locks-\(UUID().uuidString.prefix(6))"
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: dir) }
        for f in ["roof-dead.lock", "roof-dead.sock", "roof-gone-2.lock", "roofd.lock", "roof-live.sock"] {
            FileManager.default.createFile(atPath: "\(dir)/\(f)", contents: nil)
        }
        let live = try XCTUnwrap(try FileLock.acquire("\(dir)/roof-live.lock", wait: false))   // a running holder
        defer { close(live) }
        XCTAssertEqual(Daemon.sweepStaleSessionFiles(in: dir), 2)
        let left = Set(try FileManager.default.contentsOfDirectory(atPath: dir))
        XCTAssertEqual(left, ["roof-live.lock", "roof-live.sock", "roofd.lock"])
    }
}
