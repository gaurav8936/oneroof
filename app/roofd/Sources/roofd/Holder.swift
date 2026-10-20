import CRoofSpawn
import Darwin
import Foundation
import RoofVT

/// One session: owns the PTY and the child, keeps a headless terminal (RoofVT) for redraw and `read`, and serves
/// attach clients and control requests on its own socket (T14 §3a–§3c). One poll loop, one thread: a client is
/// registered in the same turn as its redraw snapshot, so nothing is lost or doubled across a reattach.
final class Holder {
    struct Spec {
        var id: String
        var label: String
        var cwd: String
        var argv: [String]
        var env: [String: String]
        var cols: UInt16
        var rows: UInt16

        init(json j: [String: Any]) throws {
            guard let id = j["id"] as? String, Paths.validId(id) else { throw RoofdError("bad id") }
            self.id = id
            label = j["label"] as? String ?? id
            cwd = j["cwd"] as? String ?? NSHomeDirectory()
            argv = j["argv"] as? [String] ?? []
            env = j["env"] as? [String: String] ?? [:]
            cols = UInt16(j["cols"] as? Int ?? 120)
            rows = UInt16(j["rows"] as? Int ?? 40)
        }
    }

    final class Client {
        let fd: Int32
        var inbuf: [UInt8] = []
        var out = ByteQueue()
        var attached = false
        var closeAfterFlush = false
        init(_ fd: Int32) { self.fd = fd }
    }

    static let scrollbackBytes = 8 << 20          // Q9: 8 MB in memory, never on disk
    static let clientQueueLimit = 4 << 20
    /// Spike only (M2): measure the forwarding path without the VT parse.
    static let skipVT = ProcessInfo.processInfo.environment["ROOFD_SPIKE_NOVT"] == "1"
    static let lingerSeconds = Double(ProcessInfo.processInfo.environment["ROOFD_LINGER"] ?? "") ?? 600

    let spec: Spec
    let socketPath: String
    var listenFd: Int32 = -1
    var master: Int32 = -1
    var pid: pid_t = -1
    let vt: OpaquePointer
    var clients: [Int32: Client] = [:]
    var seq = 0
    var exitCode: Int32?
    var exitSignal: Int32?
    var exitedAt: Date?
    let created = Date()
    var pendingInput: [UInt8] = []
    /// Every RoofVT call runs on this serial queue: the parse never delays forwarding (T14 §3c hot path), and a
    /// `sync` on it is a barrier: everything read before it has been parsed.
    let vtQ = DispatchQueue(label: "roofd.vt", qos: .userInitiated)
    /// Query replies computed on the VT queue for the loop to type, and whether a terminal is attached.
    private let mailLock = NSLock()
    private var mailReplies: [UInt8] = []
    private var anyAttached = false
    private var wakeR: Int32 = -1, wakeW: Int32 = -1

    init(spec: Spec) throws {
        self.spec = spec
        socketPath = Paths.session(spec.id)
        guard let t = rvt_new(spec.cols, spec.rows, Holder.scrollbackBytes) else { throw RoofdError("rvt_new failed") }
        vt = t
    }

    deinit { let t = vt; vtQ.sync { rvt_free(t) } }

    func start() throws {
        signal(SIGPIPE, SIG_IGN)
        signal(SIGHUP, SIG_IGN)
        var w: [Int32] = [0, 0]
        guard pipe(&w) == 0 else { throw RoofdError("pipe failed") }
        (wakeR, wakeW) = (w[0], w[1])
        Sock.setNonBlocking(wakeR); Sock.setNonBlocking(wakeW)
        listenFd = try Sock.listen(socketPath)
        guard let exe = spec.argv.first else { throw RoofdError("empty argv") }
        let path = exe.hasPrefix("/") ? exe : Holder.which(exe, env: spec.env) ?? exe
        var envList = spec.env.map { "\($0.key)=\($0.value)" }
        envList.append("ONEROOF_SESSION=\(spec.id)")
        envList.append("ONEROOF_ROOFD=\(Paths.control)")
        let args = [path] + spec.argv.dropFirst()
        var m: Int32 = -1
        let p = withCStrings(args) { a in withCStrings(envList) { e in roof_spawn(a, e, spec.cwd, spec.cols, spec.rows, &m) } }
        guard p > 0 else { unlink(socketPath); throw RoofdError("spawn \(path): \(String(cString: strerror(errno)))") }
        pid = p
        master = m
    }

    static func which(_ name: String, env: [String: String]) -> String? {
        let path = env["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin"
        for dir in path.split(separator: ":") {
            let p = "\(dir)/\(name)"
            if FileManager.default.isExecutableFile(atPath: p) { return p }
        }
        return nil
    }

    // MARK: Loop

    func run() {
        var buf = [UInt8](repeating: 0, count: 256 * 1024)
        while true {
            if let at = exitedAt, Date().timeIntervalSince(at) > Holder.lingerSeconds { break }
            var fds: [pollfd] = [pollfd(fd: listenFd, events: Int16(POLLIN), revents: 0),
                                 pollfd(fd: wakeR, events: Int16(POLLIN), revents: 0)]
            if master >= 0 {
                fds.append(pollfd(fd: master, events: Int16(POLLIN) | (pendingInput.isEmpty ? 0 : Int16(POLLOUT)), revents: 0))
            }
            for c in clients.values {
                fds.append(pollfd(fd: c.fd, events: Int16(POLLIN) | (c.out.isEmpty ? 0 : Int16(POLLOUT)), revents: 0))
            }
            let n = poll(&fds, nfds_t(fds.count), 200)
            if n < 0 && errno != EINTR { break }
            reapChild()
            for f in fds where f.revents != 0 {
                if f.fd == listenFd { acceptClients(); continue }
                if f.fd == wakeR { takeMail(&buf); continue }
                if f.fd == master {
                    if f.revents & Int16(POLLOUT) != 0 { flushInput() }
                    if f.revents & Int16(POLLIN | POLLHUP | POLLERR) != 0 { readMaster(&buf) }
                    continue
                }
                guard let c = clients[f.fd] else { continue }
                if f.revents & Int16(POLLOUT) != 0 { flush(c) }
                if f.revents & Int16(POLLIN | POLLHUP | POLLERR) != 0 { readClient(c, &buf) }
            }
        }
        for c in clients.values { close(c.fd) }
        close(listenFd)
        unlink(socketPath)
    }

    private func readMaster(_ buf: inout [UInt8]) {
        // One read per wake-up: draining the PTY first would hold output back from the terminal.
        let k = read(master, &buf, buf.count)
        let n = max(k, 0)
        let gone = k == 0 || (k < 0 && errno != EAGAIN && errno != EINTR)
        if n > 0 {
            // Hot path: forward first (written at once when the client keeps up); the parse runs on vtQ.
            for c in clients.values where c.attached {
                c.out.appendFrame(.output, buf[0..<n])
                flush(c)
            }
            seq += n
            if !Holder.skipVT {
                let bytes = Array(buf[0..<n])
                let t = vt
                vtQ.async { [weak self] in
                    bytes.withUnsafeBufferPointer { rvt_feed(t, $0.baseAddress, $0.count) }
                    let q = rvt_take_queries(t)
                    if q != 0 { self?.queriesSeen(q) }
                }
            }
        }
        if gone {
            // EIO: the child side closed (it exited).
            close(master)
            master = -1
            reapChild(block: true)
        }
    }

    /// On vtQ. Nobody attached: the holder answers DA1 / DSR, so a detached program never hangs (T14 §3c).
    /// With a terminal attached, libghostty answers.
    private func queriesSeen(_ q: UInt32) {
        mailLock.lock()
        let attached = anyAttached
        mailLock.unlock()
        guard !attached else { return }
        var reply = ""
        if q & 1 != 0 { reply += "\u{1b}[?62;22c" }
        if q & 4 != 0 { reply += "\u{1b}[0n" }
        if q & 2 != 0 {
            var x: UInt16 = 0, y: UInt16 = 0
            _ = rvt_cursor(vt, &x, &y)
            reply += "\u{1b}[\(Int(y) + 1);\(Int(x) + 1)R"
        }
        mailLock.lock()
        mailReplies += Array(reply.utf8)
        mailLock.unlock()
        var one: UInt8 = 1
        _ = write(wakeW, &one, 1)
    }

    private func takeMail(_ buf: inout [UInt8]) {
        _ = read(wakeR, &buf, buf.count)
        mailLock.lock()
        let r = mailReplies
        mailReplies = []
        mailLock.unlock()
        pendingInput += r
        flushInput()
    }

    private func setAttached() {
        let a = clients.values.contains { $0.attached }
        mailLock.lock(); anyAttached = a; mailLock.unlock()
    }

    private func flushInput() {
        guard master >= 0, !pendingInput.isEmpty else { return }
        let n = pendingInput.withUnsafeBytes { write(master, $0.baseAddress!, $0.count) }
        if n > 0 { pendingInput.removeFirst(n) }
    }

    private func reapChild(block: Bool = false) {
        guard pid > 0, exitedAt == nil else { return }
        var status: Int32 = 0
        let r = waitpid(pid, &status, block ? 0 : WNOHANG)
        guard r == pid else { return }
        if status & 0x7f == 0 { exitCode = (status >> 8) & 0xff } else { exitSignal = status & 0x7f }
        exitedAt = Date()
        let exit = Wire.encode(.exit, json: ["code": exitCode as Any, "signal": exitSignal as Any, "reason": "exited"])
        for c in clients.values where c.attached { enqueue(c, exit); c.closeAfterFlush = true; flush(c) }
    }

    private func acceptClients() {
        while true {
            let fd = accept(listenFd, nil, nil)
            if fd < 0 { return }
            Sock.setNonBlocking(fd)
            _ = fcntl(fd, F_SETFD, FD_CLOEXEC)
            var one: Int32 = 1
            setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &one, socklen_t(MemoryLayout<Int32>.size))
            clients[fd] = Client(fd)
        }
    }

    private func readClient(_ c: Client, _ buf: inout [UInt8]) {
        let n = read(c.fd, &buf, buf.count)
        if n <= 0 {
            if n < 0 && (errno == EAGAIN || errno == EINTR) { return }
            drop(c)
            return
        }
        c.inbuf += buf[0..<n]
        for (type, payload) in Wire.decode(&c.inbuf) {
            guard clients[c.fd] != nil else { return }
            handle(c, type, payload)
        }
    }

    private func handle(_ c: Client, _ type: Frame?, _ payload: [UInt8]) {
        switch type {
        case .hello:
            let j = Wire.json(payload)
            if clients.values.contains(where: { $0.attached && $0 !== c }) {
                enqueue(c, Wire.encode(.error, json: ["code": "not_primary", "message": "another terminal is showing this session"]))
                c.closeAfterFlush = true
                flush(c)
                return
            }
            if let cols = j["cols"] as? Int, let rows = j["rows"] as? Int, cols > 0, rows > 0 { resize(UInt16(cols), UInt16(rows)) }
            enqueue(c, Wire.encode(.welcome, json: ["proto": 1, "id": spec.id, "pid": Int(pid), "primary": true]))
            if (j["redraw"] as? Bool) ?? true {
                // Barrier: every byte read so far is parsed before the snapshot; the client is registered in this
                // same turn, so the next read goes to it as OUTPUT (nothing lost, nothing doubled).
                let t = vt
                let snapshot: [UInt8] = vtQ.sync {
                    var p: UnsafeMutablePointer<UInt8>?
                    let len = rvt_redraw(t, &p)
                    defer { if let p { rvt_bytes_free(p, len) } }
                    return p.map { Array(UnsafeBufferPointer(start: $0, count: len)) } ?? []
                }
                if !snapshot.isEmpty { enqueue(c, Wire.encodeChunked(.redraw, snapshot)) }
            }
            enqueue(c, Wire.encode(.redrawn, []))
            c.attached = true
            setAttached()
            if exitedAt != nil {
                enqueue(c, Wire.encode(.exit, json: ["code": exitCode as Any, "signal": exitSignal as Any, "reason": "exited"]))
                c.closeAfterFlush = true
            }
            flush(c)
        case .input:
            guard c.attached else { return }
            pendingInput += payload
            flushInput()
        case .resize:
            guard c.attached, payload.count >= 4 else { return }
            resize(UInt16(payload[0]) << 8 | UInt16(payload[1]), UInt16(payload[2]) << 8 | UInt16(payload[3]))
        case .signal:
            guard c.attached, let s = payload.first, master >= 0 else { return }
            let pg = roof_foreground_pgrp(master)
            if pg > 0 { kill(-pg, Int32(s)) }
        case .detach:
            drop(c)
        case .control:
            enqueue(c, Wire.encode(.reply, json: control(Wire.json(payload))))
            c.closeAfterFlush = true
            flush(c)
        default:
            break
        }
    }

    private func resize(_ cols: UInt16, _ rows: UInt16) {
        guard cols > 0, rows > 0 else { return }
        if master >= 0 { _ = roof_set_winsize(master, cols, rows) }
        let t = vt
        vtQ.sync { _ = rvt_resize(t, cols, rows) }
    }

    // MARK: Control (read / info / input / close), T14 §3d

    func info() -> [String: Any] {
        let t = vt
        let (title, pwd, x, y, alt, modes): (String, String, UInt16, UInt16, Bool, [Int]) = vtQ.sync {
            func str(_ f: (UnsafeMutablePointer<UnsafeMutablePointer<UInt8>?>) -> Int) -> String {
                var p: UnsafeMutablePointer<UInt8>?
                let n = f(&p)
                defer { if let p { rvt_bytes_free(p, n) } }
                return p.map { String(decoding: UnsafeBufferPointer(start: $0, count: n), as: UTF8.self) } ?? ""
            }
            let title = str { rvt_title(t, $0) }
            let pwd = str { rvt_pwd(t, $0) }
            var x: UInt16 = 0, y: UInt16 = 0
            let alt = rvt_cursor(t, &x, &y)
            let modes = [1, 25, 1000, 1002, 1003, 1006, 1049, 2004].filter { rvt_mode(t, UInt16($0), false) }
            return (title, pwd, x, y, alt, modes)
        }
        var out: [String: Any] = [
            "x": Int(x), "y": Int(y), "modes": modes,
            "id": spec.id, "label": spec.label, "cwd": spec.cwd, "pid": Int(pid), "seq": seq, "title": title, "pwd": pwd,
            "alt": alt, "attached": clients.values.contains { $0.attached }, "created": created.timeIntervalSince1970,
        ]
        if master >= 0 { out["pgid"] = Int(roof_foreground_pgrp(master)) }
        if let at = exitedAt {
            out["exited"] = at.timeIntervalSince1970
            out["code"] = exitCode as Any
            out["signal"] = exitSignal as Any
        }
        return out
    }

    private func control(_ j: [String: Any]) -> [String: Any] {
        switch j["op"] as? String {
        case "info":
            return info()
        case "read":
            let t = vt, lines = UInt32(j["lines"] as? Int ?? 0)
            let text: String = vtQ.sync {
                var p: UnsafeMutablePointer<UInt8>?
                let len = rvt_text(t, lines, &p)
                defer { if let p { rvt_bytes_free(p, len) } }
                return p.map { String(decoding: UnsafeBufferPointer(start: $0, count: len), as: UTF8.self) } ?? ""
            }
            return ["text": text, "seq": seq]
        case "input":
            guard master >= 0 else { return ["error": "session exited"] }
            var bytes: [UInt8] = []
            if let t = j["text"] as? String { bytes += Array(t.utf8) }
            if let b = j["bytes_b64"] as? String, let d = Data(base64Encoded: b) { bytes += Array(d) }
            if (j["submit"] as? Bool) == true { bytes.append(0x0D) }
            pendingInput += bytes
            flushInput()
            return [:]
        case "signal":
            guard master >= 0 else { return ["error": "session exited"] }
            let pg = roof_foreground_pgrp(master)
            if pg > 0 { kill(-pg, Int32(j["signal"] as? Int ?? Int(SIGINT))) }
            return [:]
        case "close":
            if pid > 0, exitedAt == nil {
                kill(-pid, SIGHUP)
                kill(pid, SIGHUP)
                let grace = Double(j["grace_ms"] as? Int ?? 2000) / 1000
                let pidCopy = pid
                DispatchQueue.global().asyncAfter(deadline: .now() + grace) { kill(-pidCopy, SIGKILL); kill(pidCopy, SIGKILL) }
            }
            return [:]
        default:
            return ["error": "unknown op"]
        }
    }

    // MARK: Client output

    private func enqueue(_ c: Client, _ bytes: [UInt8]) {
        c.out.append(bytes)
    }

    private func flush(_ c: Client) {
        guard c.out.write(to: c.fd) else { drop(c); return }
        if c.out.count > Holder.clientQueueLimit { drop(c); return }   // a slow client reattaches with a redraw
        if c.out.isEmpty && c.closeAfterFlush { drop(c) }
    }

    private func drop(_ c: Client) {
        guard clients.removeValue(forKey: c.fd) != nil else { return }
        close(c.fd)
        if c.attached { setAttached() }
    }
}

/// Run `body` with a NULL-terminated C string array.
func withCStrings<R>(_ strings: [String], _ body: (UnsafePointer<UnsafePointer<CChar>?>) -> R) -> R {
    let ptrs = strings.map { strdup($0) }
    defer { ptrs.forEach { free($0) } }
    var arr: [UnsafePointer<CChar>?] = ptrs.map { UnsafePointer($0) }
    arr.append(nil)
    return arr.withUnsafeBufferPointer { body($0.baseAddress!) }
}
