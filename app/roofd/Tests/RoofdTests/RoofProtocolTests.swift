import Darwin
import OneRoofCore
import XCTest
@testable import roofd

/// LAB-13: the wire protocol and the daemon's promises, against the built `roofd` binary in a temp folder.
final class RoofProtocolTests: XCTestCase {
    var dir = ""
    var daemon: Process?

    var roofd: String {
        // The test bundle sits next to the built products (.build/<conf>/).
        let products = Bundle(for: Self.self).bundleURL.deletingLastPathComponent()
        return products.appendingPathComponent("roofd").path
    }

    override func setUpWithError() throws {
        dir = "/tmp/roofd-test-\(UUID().uuidString.prefix(6))"
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        setenv("ROOFD_DIR", dir, 1)
        let p = Process()
        p.executableURL = URL(fileURLWithPath: roofd)
        p.arguments = ["daemon"]
        // Short linger: finished test sessions must not outlive the test run by ten minutes.
        p.environment = ProcessInfo.processInfo.environment.merging(["ROOFD_DIR": dir, "ROOFD_LINGER": "1"]) { $1 }
        try p.run()
        daemon = p
        for _ in 0..<50 where (try? Sock.request(Paths.control, ["method": "hello"], timeout: 1)) == nil { usleep(50_000) }
    }

    override func tearDown() {
        if let ids = try? Sock.request(Paths.control, ["method": "list"])["sessions"] as? [[String: Any]] {
            for s in ids { _ = try? Sock.request(Paths.control, ["method": "close", "params": ["id": s["id"] as? String ?? ""]]) }
        }
        daemon?.terminate()
        try? FileManager.default.removeItem(atPath: dir)
    }

    func call(_ m: String, _ p: [String: Any] = [:]) throws -> [String: Any] {
        try Sock.request(Paths.control, ["method": m, "params": p])
    }

    // MARK: Framing

    func testFramesRoundTripAndSplitAcrossReads() {
        var buf: [UInt8] = []
        let a = Wire.encode(.output, Array("hello".utf8)), b = Wire.encode(.resize, [0, 80, 0, 24])
        buf += a.prefix(3)
        XCTAssertTrue(Wire.decode(&buf).isEmpty, "a partial header waits")
        buf += a.dropFirst(3) + b.prefix(6)
        let first = Wire.decode(&buf)
        XCTAssertEqual(first.count, 1)
        XCTAssertEqual(first[0].0, .output)
        XCTAssertEqual(String(decoding: first[0].1, as: UTF8.self), "hello")
        buf += b.dropFirst(6)
        XCTAssertEqual(Wire.decode(&buf).first?.1, [0, 80, 0, 24])
        XCTAssertTrue(buf.isEmpty)
    }

    func testLargePayloadsAreChunkedToTheLimit() {
        let big = [UInt8](repeating: 65, count: Wire.maxPayload * 2 + 10)
        var buf = Wire.encodeChunked(.redraw, big)
        let frames = Wire.decode(&buf)
        XCTAssertEqual(frames.count, 3)
        XCTAssertTrue(frames.allSatisfy { $0.1.count <= Wire.maxPayload })
        XCTAssertEqual(frames.reduce(0) { $0 + $1.1.count }, big.count)
    }

    func testByteQueueKeepsOrderAcrossPartialWrites() {
        var q = ByteQueue()
        q.append(Array("abc".utf8)); q.appendFrame(.output, Array("xyz".utf8))
        var fds: [Int32] = [0, 0]
        XCTAssertEqual(pipe(&fds), 0)
        defer { close(fds[0]); close(fds[1]) }
        XCTAssertTrue(q.write(to: fds[1]))
        XCTAssertTrue(q.isEmpty)
        var out = [UInt8](repeating: 0, count: 64)
        let n = read(fds[0], &out, 64)
        XCTAssertEqual(Array(out[0..<3]), Array("abc".utf8))
        XCTAssertEqual(n, 3 + 5 + 3)
    }

    // MARK: Daemon

    func testCreateIsIdempotent() throws {
        let p: [String: Any] = ["id": "same", "cwd": "/tmp", "argv": ["/bin/sh", "-c", "sleep 30"], "env": ["PATH": "/usr/bin:/bin"]]
        let a = try call("create", p), b = try call("create", p)
        XCTAssertEqual(a["pid"] as? Int, b["pid"] as? Int, "the same id again returns the existing session")
        XCTAssertEqual((try call("list")["sessions"] as? [[String: Any]])?.count, 1)
    }

    func testBadIdsAreRefused() {
        XCTAssertThrowsError(try call("create", ["id": "../escape", "argv": ["/bin/sh"]]))
    }

    /// The reattach promise: the snapshot (REDRAW … REDRAWN) comes before any live OUTPUT, and output that arrives
    /// during the attach is neither lost nor doubled.
    func testRedrawComesBeforeLiveOutputWithNothingLostOrDoubled() throws {
        _ = try call("create", ["id": "order", "cwd": "/tmp", "env": ["PATH": "/usr/bin:/bin"],
                                "argv": ["/bin/sh", "-c", "i=0; while [ $i -lt 400 ]; do i=$((i+1)); echo L$i; sleep 0.005; done; sleep 30"]])
        usleep(500_000)   // part of the output happens before the attach
        guard let fd = Sock.connect(Paths.session("order")) else { return XCTFail("no session socket") }
        defer { close(fd) }
        Sock.writeAll(fd, Wire.encode(.hello, json: ["cols": 80, "rows": 24, "redraw": true]))
        var types: [Frame] = [], redraw: [UInt8] = [], live: [UInt8] = [], buf: [UInt8] = []
        var chunk = [UInt8](repeating: 0, count: 65536)
        let deadline = Date().addingTimeInterval(6)
        while Date() < deadline, !String(decoding: live, as: UTF8.self).contains("L400") {
            let n = read(fd, &chunk, chunk.count)
            if n <= 0 { break }
            buf += chunk[0..<n]
            for (t, p) in Wire.decode(&buf) {
                guard let t else { continue }
                if types.last != t { types.append(t) }
                if t == .redraw { redraw += p } else if t == .output { live += p }
            }
        }
        XCTAssertEqual(Array(types.prefix(3)), [.welcome, .redraw, .redrawn])
        XCTAssertFalse(types.dropFirst(3).contains(.redraw), "no snapshot after live output started")
        // Rebuild what the terminal shows from the plain lines: every L1…L400 exactly once.
        // Terminal control sequences are not text: the redraw ends with tab stops (ESC H) and a cursor move, glued to
        // the first live line, so take the line numbers by pattern after removing every escape sequence.
        let text = String(decoding: redraw + live, as: UTF8.self)
            .replacingOccurrences(of: "\u{1b}\\[[0-9;?]*[ -/]*[@-~]", with: "", options: .regularExpression)
            .replacingOccurrences(of: "\u{1b}\\][^\u{07}\u{1b}]*(\u{07}|\u{1b}\\\\)", with: "", options: .regularExpression)
            .replacingOccurrences(of: "\u{1b}[()*+]?[0-9A-Za-z=>]", with: "", options: .regularExpression)
        let re = try NSRegularExpression(pattern: "L(\\d+)")
        let numbers = re.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap {
            Range($0.range(at: 1), in: text).flatMap { Int(text[$0]) }
        }
        let tail = numbers.drop { $0 != numbers.first }
        XCTAssertEqual(Set(numbers.filter { $0 > (numbers.first ?? 1) }).count, numbers.filter { $0 > (numbers.first ?? 1) }.count, "nothing doubled")
        XCTAssertEqual(numbers.last, 400)
        XCTAssertEqual(Array(tail), Array((numbers.first ?? 1)...400), "nothing lost after the first line the redraw kept")
    }

    func testSecondPrimaryIsRefused() throws {
        _ = try call("create", ["id": "one", "cwd": "/tmp", "argv": ["/bin/sh", "-c", "sleep 30"], "env": ["PATH": "/usr/bin:/bin"]])
        guard let a = Sock.connect(Paths.session("one")), let b = Sock.connect(Paths.session("one")) else { return XCTFail() }
        defer { close(a); close(b) }
        Sock.writeAll(a, Wire.encode(.hello, json: ["cols": 80, "rows": 24]))
        usleep(200_000)
        Sock.writeAll(b, Wire.encode(.hello, json: ["cols": 80, "rows": 24]))
        var buf: [UInt8] = [], chunk = [UInt8](repeating: 0, count: 4096)
        var tv = timeval(tv_sec: 2, tv_usec: 0)
        setsockopt(b, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
        while true {
            let n = read(b, &chunk, chunk.count)
            if n <= 0 { break }
            buf += chunk[0..<n]
        }
        let frames = Wire.decode(&buf)
        XCTAssertEqual(frames.first?.0, .error)
        XCTAssertEqual(Wire.json(frames.first?.1 ?? [])["code"] as? String, "not_primary")
    }

    /// Found by the side-by-side run (Codex): a new session must see its size before anything attaches; macOS left
    /// 0x0 when it was set on the master only, and full-screen CLIs drew nothing.
    func testNewSessionSeesItsSizeBeforeAnyAttach() throws {
        _ = try call("create", ["id": "size", "cwd": "/tmp", "cols": 120, "rows": 40, "env": ["PATH": "/usr/bin:/bin"],
                                "argv": ["/bin/sh", "-c", "echo SIZE $(stty size); sleep 20"]])
        usleep(800_000)
        let text = try call("read", ["id": "size", "lines": 3])["text"] as? String ?? ""
        XCTAssertTrue(text.contains("SIZE 40 120"), text)
    }

    /// Nobody attached: the holder answers a CLI's query batch in the order it was sent.
    func testDetachedQueriesAreAnsweredInOrder() throws {
        let script = "/tmp/roofd-q-\(UUID().uuidString.prefix(6)).py"
        try """
        import os, sys, termios, tty, time, select
        fd = sys.stdin.fileno(); old = termios.tcgetattr(fd); tty.setraw(fd)
        os.write(1, b"\\x1b[6n\\x1b]10;?\\x1b\\\\\\x1b]11;?\\x1b\\\\\\x1b[?u\\x1b[c")
        got = b""; t0 = time.time()
        while time.time() - t0 < 3 and not got.endswith(b"c"):
            r, _, _ = select.select([fd], [], [], 0.2)
            if r: got += os.read(fd, 1024)
        termios.tcsetattr(fd, termios.TCSADRAIN, old)
        print("ORDER", "".join(k for k, m in [("C", b"R"), ("F", b"]10;"), ("B", b"]11;"), ("K", b"?0u"), ("D", b"?62")] if m in got), [got.find(m) for m in [b"R", b"]10;", b"]11;", b"?0u", b"?62"]] == sorted([got.find(m) for m in [b"R", b"]10;", b"]11;", b"?0u", b"?62"]]))
        time.sleep(20)
        """.write(toFile: script, atomically: true, encoding: .utf8)
        defer { unlink(script) }
        _ = try call("create", ["id": "q", "cwd": "/tmp", "env": ["PATH": "/usr/bin:/bin"], "argv": ["/usr/bin/python3", script]])
        var text = ""
        for _ in 0..<30 where !text.contains("ORDER") {
            usleep(100_000)
            text = try call("read", ["id": "q", "lines": 3])["text"] as? String ?? ""
        }
        XCTAssertTrue(text.contains("ORDER CFBKD True"), text)
    }

    /// LAB-18 / Q8: after an app update the bundled roofd is newer than the running daemon: the app asks it to upgrade,
    /// the new binary takes over the folder, and sessions keep running in their holders.
    func testUpgradeReplacesTheDaemonAndKeepsSessions() throws {
        _ = try call("create", ["id": "keep", "cwd": "/tmp", "env": ["PATH": "/usr/bin:/bin"], "argv": ["/bin/sh", "-c", "sleep 60"]])
        let oldPid = try call("hello")["pid"] as? Int
        // "The new app's roofd": a copy of the binary with a newer build stamp.
        let newer = dir + "/roofd-new"
        try FileManager.default.copyItem(atPath: roofd, toPath: newer)
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(3600)], ofItemAtPath: newer)
        let rt = RoofdRuntime(roofdPath: newer, dir: dir, resources: nil)
        try rt.ensureRunning()
        let hello = try call("hello")
        XCTAssertNotEqual(hello["pid"] as? Int, oldPid, "a new daemon answers")
        XCTAssertEqual(hello["build"] as? Double, rt.bundledBuild)
        let ids = (try call("list")["sessions"] as? [[String: Any]] ?? []).compactMap { $0["id"] as? String }
        XCTAssertEqual(ids, ["keep"], "the session survived the upgrade")
        if let p = hello["pid"] as? Int { kill(pid_t(p), SIGTERM) }
    }

    /// Where an agent works, from Claude's hook payload (owner 10-20, group by repo).
    func testWorkPathFromHookPayload() {
        XCTAssertEqual(WorkPath.from(hook: ["tool_input": ["file_path": "/p/a/b.swift"]]), "/p/a/b.swift")
        XCTAssertEqual(WorkPath.from(hook: ["cwd": "/p", "tool_input": ["command": "cd labs/x && sed -n 1p f"]]), "/p/labs/x")
        XCTAssertEqual(WorkPath.cdTarget("cd \"/a b\"; ls"), "/a b")
        XCTAssertNil(WorkPath.from(hook: ["tool_input": ["command": "ls -la"]]))
        XCTAssertNil(WorkPath.from(hook: [:]))
    }
}
