import Darwin
import Foundation

// Sockets and framing shared by roofd's daemon, holders and attach client (T14 §3c, §3d).

enum Frame: UInt8 {
    // client → session
    case hello = 1, input = 2, resize = 3, signal = 4, detach = 5, control = 6
    // session → client
    case welcome = 0x81, redraw = 0x82, redrawn = 0x83, output = 0x84, exit = 0x85, error = 0x86, reply = 0x87
}

enum Wire {
    static let maxPayload = 1 << 20

    static func encode(_ type: Frame, _ payload: [UInt8]) -> [UInt8] {
        let n = UInt32(payload.count)
        return [type.rawValue, UInt8(n >> 24), UInt8((n >> 16) & 0xff), UInt8((n >> 8) & 0xff), UInt8(n & 0xff)] + payload
    }

    static func encode(_ type: Frame, json: [String: Any]) -> [UInt8] {
        encode(type, [UInt8]((try? JSONSerialization.data(withJSONObject: json)) ?? Data("{}".utf8)))
    }

    /// Frames split to the 1 MiB payload limit (a redraw can be larger).
    static func encodeChunked(_ type: Frame, _ payload: [UInt8]) -> [UInt8] {
        var out: [UInt8] = []
        var i = 0
        repeat {
            let end = min(i + maxPayload, payload.count)
            out += encode(type, Array(payload[i..<end]))
            i = end
        } while i < payload.count
        return out
    }

    /// Pull complete frames off the front of `buf`.
    static func decode(_ buf: inout [UInt8]) -> [(Frame?, [UInt8])] {
        var frames: [(Frame?, [UInt8])] = []
        var off = 0
        while buf.count - off >= 5 {
            let n = Int(buf[off + 1]) << 24 | Int(buf[off + 2]) << 16 | Int(buf[off + 3]) << 8 | Int(buf[off + 4])
            guard buf.count - off - 5 >= n else { break }
            frames.append((Frame(rawValue: buf[off]), Array(buf[(off + 5)..<(off + 5 + n)])))
            off += 5 + n
        }
        if off > 0 { buf.removeFirst(off) }
        return frames
    }

    /// The frame at the front of `buf` claims more than the payload limit: no well-behaved peer sends that, and
    /// waiting for it would let one connection grow the buffer without bound (LAB-310).
    static func oversized(_ buf: [UInt8]) -> Bool {
        guard buf.count >= 5 else { return false }
        let n = Int(buf[1]) << 24 | Int(buf[2]) << 16 | Int(buf[3]) << 8 | Int(buf[4])
        return n > maxPayload
    }

    static func json(_ bytes: [UInt8]) -> [String: Any] {
        (try? JSONSerialization.jsonObject(with: Data(bytes))) as? [String: Any] ?? [:]
    }
}

/// A FIFO of bytes with a moving head: appends at the end, consumes from the front without shifting every time.
struct ByteQueue {
    private(set) var storage: [UInt8] = []
    private var head = 0
    var count: Int { storage.count - head }
    var isEmpty: Bool { count == 0 }

    mutating func append<C: Collection>(_ bytes: C) where C.Element == UInt8 { storage.append(contentsOf: bytes) }

    mutating func appendFrame<C: Collection>(_ type: Frame, _ payload: C) where C.Element == UInt8 {
        let n = UInt32(payload.count)
        storage.append(contentsOf: [type.rawValue, UInt8(n >> 24), UInt8((n >> 16) & 0xff), UInt8((n >> 8) & 0xff), UInt8(n & 0xff)])
        storage.append(contentsOf: payload)
    }

    /// Write as much as the fd takes; returns false on a hard error.
    mutating func write(to fd: Int32) -> Bool {
        while count > 0 {
            let n = storage.withUnsafeBytes { Darwin.write(fd, $0.baseAddress!.advanced(by: head), count) }
            if n > 0 { head += n; continue }
            if n < 0 && (errno == EAGAIN || errno == EINTR) { break }
            return false
        }
        if head == storage.count { storage.removeAll(keepingCapacity: true); head = 0 }
        else if head > 1 << 20 && head > storage.count / 2 { storage.removeFirst(head); head = 0 }
        return true
    }
}

enum Sock {
    static func address(_ path: String) -> sockaddr_un? {
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(path.utf8)
        guard bytes.count < MemoryLayout.size(ofValue: addr.sun_path) else { return nil }
        withUnsafeMutableBytes(of: &addr.sun_path) { raw in
            for (i, b) in bytes.enumerated() { raw[i] = b }
            raw[bytes.count] = 0
        }
        return addr
    }

    static func listen(_ path: String) throws -> Int32 {
        unlink(path)
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0, var addr = address(path) else { throw RoofdError("socket \(path)") }
        let rc = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        guard rc == 0, Darwin.listen(fd, 16) == 0 else { close(fd); throw RoofdError("bind \(path): \(String(cString: strerror(errno)))") }
        chmod(path, 0o600)
        setNonBlocking(fd)
        _ = fcntl(fd, F_SETFD, FD_CLOEXEC)
        return fd
    }

    static func connect(_ path: String) -> Int32? {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0, var addr = address(path) else { return nil }
        let rc = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        guard rc == 0 else { close(fd); return nil }
        _ = fcntl(fd, F_SETFD, FD_CLOEXEC)
        var one: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &one, socklen_t(MemoryLayout<Int32>.size))
        return fd
    }

    static func setNonBlocking(_ fd: Int32) { _ = fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) | O_NONBLOCK) }

    /// Blocking write of everything (retries EAGAIN on non-blocking fds).
    @discardableResult
    static func writeAll(_ fd: Int32, _ bytes: [UInt8]) -> Bool {
        var off = 0
        while off < bytes.count {
            let n = bytes.withUnsafeBytes { write(fd, $0.baseAddress!.advanced(by: off), bytes.count - off) }
            if n > 0 { off += n; continue }
            if n < 0 && (errno == EAGAIN || errno == EINTR) { usleep(500); continue }
            return false
        }
        return true
    }

    /// One newline-terminated JSON request, one reply (the control protocol).
    static func request(_ path: String, _ req: [String: Any], timeout: Int32 = 5) throws -> [String: Any] {
        guard let fd = connect(path) else { throw RoofdError("roofd not running (\(path))") }
        defer { close(fd) }
        var tv = timeval(tv_sec: Int(timeout), tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
        var data = [UInt8](try JSONSerialization.data(withJSONObject: req))
        data.append(0x0A)
        guard writeAll(fd, data) else { throw RoofdError("write failed") }
        var reply: [UInt8] = []
        var chunk = [UInt8](repeating: 0, count: 65536)
        while true {
            let n = read(fd, &chunk, chunk.count)
            if n <= 0 { break }
            reply += chunk[0..<n]
            if reply.last == 0x0A { break }
        }
        guard let obj = (try? JSONSerialization.jsonObject(with: Data(reply))) as? [String: Any] else { throw RoofdError("bad reply") }
        if let e = obj["error"] as? String { throw RoofdError(e) }
        return obj
    }

    /// A control message to a session holder: one CONTROL frame, one REPLY frame.
    static func holderRequest(_ path: String, _ req: [String: Any], timeout: Int32 = 5) throws -> [String: Any] {
        guard let fd = connect(path) else { throw RoofdError("session not running (\(path))") }
        defer { close(fd) }
        var tv = timeval(tv_sec: Int(timeout), tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
        guard writeAll(fd, Wire.encode(.control, json: req)) else { throw RoofdError("write failed") }
        var buf: [UInt8] = []
        var chunk = [UInt8](repeating: 0, count: 65536)
        while true {
            let n = read(fd, &chunk, chunk.count)
            if n <= 0 { throw RoofdError("no reply from session") }
            buf += chunk[0..<n]
            for (type, payload) in Wire.decode(&buf) where type == .reply {
                let obj = Wire.json(payload)
                if let e = obj["error"] as? String { throw RoofdError(e) }
                return obj
            }
        }
    }
}

struct RoofdError: Error, CustomStringConvertible {
    let description: String
    init(_ d: String) { description = d }
}

enum Paths {
    /// ROOFD_DIR, else ~/Library/Application Support/One Roof/roofd.
    static var dir: String {
        if let d = ProcessInfo.processInfo.environment["ROOFD_DIR"], !d.isEmpty { return d }
        return (NSHomeDirectory() as NSString).appendingPathComponent("Library/Application Support/One Roof/roofd")
    }
    static var control: String { dir + "/roofd.sock" }
    static func session(_ id: String) -> String { dir + "/\(id).sock" }

    static func validId(_ id: String) -> Bool {
        !id.isEmpty && id.count <= 40 && id.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }
    }
}

/// An exclusive lock on a file in the roofd folder, held until the process exits (the kernel drops it then, even on a
/// crash or kill -9). `wait` blocks until it is free; otherwise nil when another process holds it.
enum FileLock {
    static func acquire(_ path: String, wait: Bool) throws -> Int32? {
        while true {
            let fd = open(path, O_CREAT | O_RDWR | O_CLOEXEC, 0o600)
            guard fd >= 0 else { throw RoofdError("cannot open the lock file \(path)") }
            var rc: Int32
            repeat { rc = flock(fd, LOCK_EX | (wait ? 0 : LOCK_NB)) } while rc != 0 && errno == EINTR
            if rc != 0 {
                let e = errno
                close(fd)
                if e == EWOULDBLOCK { return nil }
                throw RoofdError("lock \(path): \(String(cString: strerror(e)))")
            }
            // The file may have been replaced while we waited: then the lock is on a file nobody else sees. Retry.
            var a = stat(), b = stat()
            if fstat(fd, &a) == 0, stat(path, &b) == 0, a.st_ino == b.st_ino, a.st_dev == b.st_dev { return fd }
            close(fd)
        }
    }
}

/// roofd-memory.log in the roofd folder: what the memory watchdog saw (LAB-310). Kept small.
enum MemoryLog {
    static var path: String { Paths.dir + "/roofd-memory.log" }
    static let maxBytes = 256 * 1024

    static func append(_ line: String) {
        if let a = try? FileManager.default.attributesOfItem(atPath: path), (a[.size] as? Int ?? 0) > maxBytes {
            unlink(path)
        }
        let fd = open(path, O_WRONLY | O_CREAT | O_APPEND | O_CLOEXEC, 0o600)
        guard fd >= 0 else { return }
        Sock.writeAll(fd, Array(line.utf8))
        close(fd)
    }
}
