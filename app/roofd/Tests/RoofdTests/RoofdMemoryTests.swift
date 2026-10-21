import Darwin
import OneRoofCore
import XCTest
@testable import roofd

/// LAB-310 (10-21 jetsam storm): one daemon per folder, one holder per session, bounded buffers, and the memory
/// watchdog, against the built `roofd` binary in throwaway folders.
final class RoofdMemoryTests: XCTestCase {
    var dir = ""
    var daemons: [Process] = []

    var roofd: String {
        Bundle(for: Self.self).bundleURL.deletingLastPathComponent().appendingPathComponent("roofd").path
    }

    override func setUpWithError() throws {
        dir = "/tmp/roofd-mem-\(UUID().uuidString.prefix(6))"
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        setenv("ROOFD_DIR", dir, 1)
    }

    override func tearDown() {
        if let ids = try? Sock.request(Paths.control, ["method": "list"], timeout: 2)["sessions"] as? [[String: Any]] {
            for s in ids { _ = try? Sock.request(Paths.control, ["method": "close", "params": ["id": s["id"] as? String ?? ""]]) }
        }
        for d in daemons where d.isRunning { d.terminate() }
        try? FileManager.default.removeItem(atPath: dir)
    }

    @discardableResult
    func startDaemon(_ env: [String: String] = [:], waitUntilServing: Bool = true) throws -> Process {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: roofd)
        p.arguments = ["daemon"]
        var e = ProcessInfo.processInfo.environment.merging(["ROOFD_DIR": dir, "ROOFD_LINGER": "1"]) { $1 }
        e.removeValue(forKey: "XPC_SERVICE_NAME")
        p.environment = e.merging(env) { $1 }
        try p.run()
        daemons.append(p)
        if waitUntilServing {
            for _ in 0..<60 where (try? hello()) == nil { usleep(50_000) }
        }
        return p
    }

    func hello() throws -> [String: Any] { try Sock.request(Paths.control, ["method": "hello"], timeout: 1) }

    func call(_ m: String, _ p: [String: Any] = [:]) throws -> [String: Any] {
        try Sock.request(Paths.control, ["method": m, "params": p])
    }

    func waitFor(_ seconds: Double, _ cond: () -> Bool) -> Bool {
        let end = Date().addingTimeInterval(seconds)
        while Date() < end { if cond() { return true }; usleep(50_000) }
        return cond()
    }

    var memoryLog: String { (try? String(contentsOfFile: dir + "/roofd-memory.log", encoding: .utf8)) ?? "" }

    // MARK: Single instance

    /// A second daemon for the same folder (launchd's KeepAlive copy next to an app-started one) never serves: it
    /// waits on the lock, and takes over only when the first one is gone.
    func testSecondDaemonWaitsAndTakesOverOnlyWhenTheFirstStops() throws {
        let first = try startDaemon()
        let firstPid = try XCTUnwrap(hello()["pid"] as? Int)
        XCTAssertEqual(Int32(firstPid), first.processIdentifier)
        let second = try startDaemon(waitUntilServing: false)
        usleep(600_000)
        XCTAssertTrue(second.isRunning, "the second daemon waits (an exit would be restarted by launchd in a loop)")
        XCTAssertEqual(try hello()["pid"] as? Int, firstPid, "only the first daemon serves")
        first.terminate()
        first.waitUntilExit()
        XCTAssertTrue(waitFor(5) { (try? self.hello()["pid"] as? Int) == Int(second.processIdentifier) }, "the waiting one takes over")
    }

    /// One holder per session id: a second `roofd session` for a running id exits before starting anything, and the
    /// running session keeps its socket.
    func testSecondHolderForTheSameSessionExitsAtOnce() throws {
        try startDaemon()
        let a = try call("create", ["id": "solo", "cwd": "/tmp", "argv": ["/bin/sh", "-c", "sleep 30"], "env": ["PATH": "/usr/bin:/bin"]])
        let p = Process()
        p.executableURL = URL(fileURLWithPath: roofd)
        p.arguments = ["session", "--spec-stdin"]
        p.environment = ["ROOFD_DIR": dir, "PATH": "/usr/bin:/bin"]
        let stdin = Pipe()
        p.standardInput = stdin
        p.standardError = FileHandle.nullDevice
        try p.run()
        let spec = try JSONSerialization.data(withJSONObject: ["id": "solo", "cwd": "/tmp", "argv": ["/bin/sh", "-c", "echo SECOND; sleep 30"],
                                                               "env": ["PATH": "/usr/bin:/bin"]])
        stdin.fileHandleForWriting.write(spec)
        try stdin.fileHandleForWriting.close()
        XCTAssertTrue(waitFor(5) { !p.isRunning }, "the second holder exits")
        XCTAssertNotEqual(p.terminationStatus, 0)
        let info = try call("info", ["id": "solo"])
        XCTAssertEqual(info["pid"] as? Int, a["pid"] as? Int, "the first holder still owns the session")
        XCTAssertFalse((try call("read", ["id": "solo", "lines": 5])["text"] as? String ?? "").contains("SECOND"))
    }

    // MARK: Bounds

    /// The 10-21 leak: every control reply stayed in an autorelease pool that the holder's loop never drained (a full
    /// `read` kept the whole scrollback text). Hundreds of reads must leave the holder's footprint where it was.
    func testRepeatedReadsDoNotGrowTheHolder() throws {
        try startDaemon(["ROOFD_WATCHDOG_SECONDS": "0.2"])
        _ = try call("create", ["id": "reads", "cwd": "/tmp", "cols": 120, "rows": 40, "env": ["PATH": "/usr/bin:/bin"],
                                "argv": ["/bin/sh", "-c", "i=0; while [ $i -lt 4000 ]; do i=$((i+1)); echo \"line $i abcdefghijklmnopqrstuvwxyz0123456789abcdefghijklmnopqrstuvwxyz0123456789\"; done; sleep 60"]])
        XCTAssertTrue(waitFor(10) { (try? self.call("read", ["id": "reads", "lines": 2])["text"] as? String ?? "")?.contains("line 4000") == true })
        func footprint() throws -> Int {
            usleep(400_000)   // the next watchdog check refreshes it
            return try XCTUnwrap(call("info", ["id": "reads"])["footprint"] as? Int)
        }
        let text = try call("read", ["id": "reads", "lines": 0])["text"] as? String ?? ""
        XCTAssertGreaterThan(text.utf8.count, 200_000, "a scrollback worth leaking")
        let before = try footprint()
        for _ in 0..<300 { _ = try call("read", ["id": "reads", "lines": 0]) }
        let after = try footprint()
        // Leaking, 300 reads of ~360 KB would add ~100 MB.
        XCTAssertLessThan(after - before, 30 << 20, "before \(before >> 20) MB, after \(after >> 20) MB")
    }

    /// A client that announces a frame past the payload limit is dropped instead of being buffered.
    func testOversizedFrameDropsTheClient() throws {
        try startDaemon()
        _ = try call("create", ["id": "big", "cwd": "/tmp", "argv": ["/bin/sh", "-c", "sleep 30"], "env": ["PATH": "/usr/bin:/bin"]])
        guard let fd = Sock.connect(Paths.session("big")) else { return XCTFail("no session socket") }
        defer { close(fd) }
        Sock.writeAll(fd, [Frame.input.rawValue, 0x7f, 0xff, 0xff, 0xff] + [UInt8](repeating: 65, count: 1000))
        var tv = timeval(tv_sec: 3, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
        var b = [UInt8](repeating: 0, count: 64)
        XCTAssertEqual(read(fd, &b, b.count), 0, "the holder closed the connection")
        XCTAssertNotNil(try call("info", ["id": "big"])["pid"], "the session itself is fine")
    }

    /// A program that never reads its input: the holder queues at most 1 MB for it, then refuses more.
    func testInputForAProgramThatDoesNotReadIsBounded() throws {
        try startDaemon()
        _ = try call("create", ["id": "deaf", "cwd": "/tmp", "argv": ["/bin/sh", "-c", "stty raw -echo; sleep 60"], "env": ["PATH": "/usr/bin:/bin"]])
        let chunk = String(repeating: "x", count: 256 * 1024)
        var refused = false
        for _ in 0..<12 {
            do { _ = try call("input", ["id": "deaf", "text": chunk]) } catch {
                refused = "\(error)".contains("not reading")
                break
            }
        }
        XCTAssertTrue(refused, "input is refused once the queue is full")
        XCTAssertNotNil(try call("info", ["id": "deaf"])["pid"])
    }

    // MARK: Watchdog

    /// Over its limit a holder writes the memory log, ends its program and exits: one session ends, the Mac survives.
    func testHolderOverItsLimitEndsTheSession() throws {
        try startDaemon(["ROOFD_SESSION_MEM_LIMIT_MB": "1", "ROOFD_WATCHDOG_SECONDS": "0.2"])
        let marker = "/tmp/roofd-mem-child-\(UUID().uuidString.prefix(6))"
        defer { unlink(marker) }
        _ = try? call("create", ["id": "fat", "cwd": "/tmp", "env": ["PATH": "/usr/bin:/bin"],
                                 "argv": ["/bin/sh", "-c", "echo $$ > \(marker); sleep 60"]])
        XCTAssertTrue(waitFor(5) { !FileManager.default.fileExists(atPath: Paths.session("fat")) }, "the holder is gone")
        XCTAssertTrue(memoryLog.contains("session fat pid"), memoryLog)
        XCTAssertTrue(memoryLog.contains("over the limit, stopping"), memoryLog)
        if let s = try? String(contentsOfFile: marker, encoding: .utf8), let child = pid_t(s.trimmingCharacters(in: .whitespacesAndNewlines)) {
            XCTAssertTrue(waitFor(3) { kill(child, 0) != 0 }, "the session's program was ended too")
        }
    }

    /// Over its warning line a holder logs once and says so in `info`, and keeps running.
    func testHolderOverItsWarningLineReportsAndKeepsRunning() throws {
        try startDaemon(["ROOFD_SESSION_MEM_WARN_MB": "1", "ROOFD_WATCHDOG_SECONDS": "0.2"])
        _ = try call("create", ["id": "warm", "cwd": "/tmp", "argv": ["/bin/sh", "-c", "sleep 30"], "env": ["PATH": "/usr/bin:/bin"]])
        XCTAssertTrue(waitFor(5) { (try? self.call("info", ["id": "warm"])["memoryWarning"] as? Bool) == true })
        usleep(600_000)
        XCTAssertEqual(memoryLog.components(separatedBy: "session warm").count - 1, 1, "logged once: \(memoryLog)")
        XCTAssertNotNil(try call("info", ["id": "warm"])["pid"])
    }

    /// The daemon over its limit exits (launchd or the app start a fresh one; sessions are in their holders).
    func testDaemonOverItsLimitExits() throws {
        let d = try startDaemon(["ROOFD_DAEMON_MEM_LIMIT_MB": "1", "ROOFD_WATCHDOG_SECONDS": "0.2"], waitUntilServing: false)
        XCTAssertTrue(waitFor(5) { !d.isRunning }, "the daemon stopped itself")
        XCTAssertEqual(d.terminationStatus, 3)
        XCTAssertTrue(memoryLog.contains("daemon pid"), memoryLog)
    }
}
