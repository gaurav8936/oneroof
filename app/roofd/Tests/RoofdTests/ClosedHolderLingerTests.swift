import Darwin
import OneRoofCore
import XCTest
@testable import roofd

/// LAB-2311: a closed session's holder leaves `roofd list` at once, not after the ten-minute linger an exited session
/// keeps. Its own daemon in a temp folder with the default linger (never the owner's roofd).
final class ClosedHolderLingerTests: XCTestCase {
    var dir = ""
    var daemon: Process?

    override func setUpWithError() throws {
        let products = Bundle(for: Self.self).bundleURL.deletingLastPathComponent()
        dir = "/tmp/roofd-linger-\(UUID().uuidString.prefix(6))"
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        setenv("ROOFD_DIR", dir, 1)
        // Never the owner's roofd: every call below goes to this temp folder, or the test does not run.
        guard Paths.dir == dir else { throw XCTSkip("ROOFD_DIR did not take") }
        let p = Process()
        p.executableURL = products.appendingPathComponent("roofd")
        p.arguments = ["daemon"]
        var env = ProcessInfo.processInfo.environment
        env["ROOFD_DIR"] = dir
        env["ROOFD_LINGER"] = nil   // the real ten minutes
        p.environment = env
        try p.run()
        daemon = p
        for _ in 0..<50 where (try? call("hello")) == nil { usleep(50_000) }
    }

    override func tearDown() {
        // Every holder here is closed, so it ends by itself; this daemon goes too.
        if Paths.dir == dir, !dir.isEmpty { for id in ids() { _ = try? call("close", ["id": id]) } }
        daemon?.terminate()
        try? FileManager.default.removeItem(atPath: dir)
    }

    func call(_ m: String, _ p: [String: Any] = [:]) throws -> [String: Any] {
        try Sock.request(Paths.control, ["method": m, "params": p])
    }

    func ids() -> [String] {
        ((try? call("list"))?["sessions"] as? [[String: Any]] ?? []).compactMap { $0["id"] as? String }
    }

    func wait(_ seconds: Double, until: () -> Bool) -> Bool {
        let end = Date().addingTimeInterval(seconds)
        while Date() < end { if until() { return true }; usleep(100_000) }
        return until()
    }

    func test_LAB2311_closedRunningSessionLeavesTheListPromptly() throws {
        _ = try call("create", ["id": "running", "cwd": "/tmp", "env": ["PATH": "/usr/bin:/bin"], "argv": ["/bin/sh", "-c", "sleep 60"]])
        XCTAssertTrue(ids().contains("running"))
        _ = try call("close", ["id": "running"])
        XCTAssertTrue(wait(6) { !ids().contains("running") }, "a closed session's holder stays no more than a moment")
    }

    func test_LAB2311_closingAnExitedSessionEndsItsLinger() throws {
        _ = try call("create", ["id": "ended", "cwd": "/tmp", "env": ["PATH": "/usr/bin:/bin"], "argv": ["/bin/sh", "-c", "exit 0"]])
        let exited = wait(5) {
            ((try? call("info", ["id": "ended"]))?["exited"]) != nil
        }
        XCTAssertTrue(exited, "the program ended")
        usleep(1_500_000)
        XCTAssertTrue(ids().contains("ended"), "without a close, an exited holder lingers (its last screen stays readable)")
        _ = try call("close", ["id": "ended"])
        XCTAssertTrue(wait(4) { !ids().contains("ended") }, "closed: it leaves at once instead of after ten minutes")
    }
}
