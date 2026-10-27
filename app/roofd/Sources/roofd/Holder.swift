import CRoofSpawn
import Darwin
import Foundation
import OneRoofCore
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
        /// The agent launched (nil = a plain shell) and its opening message, which the holder delivers (T14, Q7).
        var kind: AgentKind?
        var opening: String?

        init(json j: [String: Any]) throws {
            guard let id = j["id"] as? String, Paths.validId(id) else { throw RoofdError("bad id") }
            self.id = id
            label = j["label"] as? String ?? id
            cwd = j["cwd"] as? String ?? NSHomeDirectory()
            argv = j["argv"] as? [String] ?? []
            env = j["env"] as? [String: String] ?? [:]
            cols = UInt16(j["cols"] as? Int ?? 120)
            rows = UInt16(j["rows"] as? Int ?? 40)
            kind = (j["kind"] as? String).flatMap(AgentKind.init(rawValue:)).flatMap { $0.isAgent ? $0 : nil }
            opening = (j["opening"] as? String).flatMap { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0 }
        }
    }

    final class Client {
        let fd: Int32
        var inbuf: [UInt8] = []
        var out = ByteQueue()
        /// Bytes of the attach redraw still queued: they don't count against `clientQueueLimit` (LAB-1365).
        var redrawLeft = 0
        var attached = false
        var closeAfterFlush = false
        init(_ fd: Int32) { self.fd = fd }
    }

    static let scrollbackBytes = 8 << 20          // Q9: 8 MB in memory, never on disk
    static let clientQueueLimit = 4 << 20
    /// Bytes waiting for the program to read its input (LAB-310): a program that stops reading must not make the
    /// holder buffer every keystroke and query reply forever. Past this, new input is refused.
    static let inputQueueLimit = 1 << 20
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
    /// ROOFD_TRACE_INPUT=<file>: log every byte sent to the program, with where it came from (debugging only).
    static let traceFile = ProcessInfo.processInfo.environment["ROOFD_TRACE_INPUT"]
    static func trace(_ tag: String, _ b: [UInt8]) {
        guard let f = traceFile else { return }
        let line = String(format: "%.3f ", Date().timeIntervalSince1970) + tag + " " + b.map { $0 >= 32 && $0 < 127 ? String(UnicodeScalar($0)) : String(format: "\\x%02x", $0) }.joined() + "\n"
        if let h = FileHandle(forWritingAtPath: f) { h.seekToEndOfFile(); h.write(Data(line.utf8)); h.closeFile() }
        else { FileManager.default.createFile(atPath: f, contents: Data(line.utf8)) }
    }
    /// Agent status (T14 §3f, Q4): evaluated here so it is right with the app closed.
    var engine = StatusEngine()
    var agent: AgentKind?
    var lastOutput: Date?
    var lastEval = Date.distantPast
    var screenSeq = -1
    var screen = ""
    var contentKey = ""
    /// Where the agent last worked (from its hooks): a file or folder, absolute.
    var workPath = ""
    /// LAB-518: issue updates the agent asked for (`roofd issue`), until the app answers; answers wait for the asker.
    var issueQueue: [[String: Any]] = []
    var issueAnswers: [Int: String] = [:]
    var issueSeq = 0
    /// Process group leader of the agent last seen in the foreground (kept while it lives).
    var agentLeader: pid_t = 0
    var contentChangedAt: Date?
    /// Opening message delivery: pending → sent (verifying) → done / failed.
    var openingState = "none"
    var idleSince: Date?
    var openingSentAt: Date?
    var openingTries = 0
    var enterAt: Date?
    /// Every RoofVT call runs on this serial queue: the parse never delays forwarding (T14 §3c hot path), and a
    /// `sync` on it is a barrier: everything read before it has been parsed.
    let vtQ = DispatchQueue(label: "roofd.vt", qos: .userInitiated)
    /// Query replies computed on the VT queue for the loop to type, and whether a terminal is attached.
    private let mailLock = NSLock()
    private var mailReplies: [UInt8] = []
    private var anyAttached = false
    private var wakeR: Int32 = -1, wakeW: Int32 = -1
    /// The memory guard (LAB-310): warn over 1 GB, end the session over 2 GB (ROOFD_SESSION_MEM_WARN_MB / _LIMIT_MB).
    var watchdog = MemoryWatchdog.from(env: ProcessInfo.processInfo.environment, prefix: "ROOFD_SESSION",
                                       warnMB: MemoryWatchdog.holderWarnMB, limitMB: MemoryWatchdog.holderLimitMB)
    var lastMemoryCheck = Date.distantPast
    var footprint: UInt64 = 0

    init(spec: Spec) throws {
        self.spec = spec
        socketPath = Paths.session(spec.id)
        guard let t = rvt_new(spec.cols, spec.rows, Holder.scrollbackBytes) else { throw RoofdError("rvt_new failed") }
        vt = t
    }

    deinit { let t = vt; vtQ.sync { rvt_free(t) } }

    func start() throws {
        var noCore = rlimit(rlim_cur: 0, rlim_max: 0)
        setrlimit(RLIMIT_CORE, &noCore)    // a crash never writes terminal content into a core file
        signal(SIGPIPE, SIG_IGN)
        signal(SIGHUP, SIG_IGN)
        var w: [Int32] = [0, 0]
        guard pipe(&w) == 0 else { throw RoofdError("pipe failed") }
        (wakeR, wakeW) = (w[0], w[1])
        Sock.setNonBlocking(wakeR); Sock.setNonBlocking(wakeW)
        // One holder per session id (LAB-310): two creates racing for the same id must not leave a second holder
        // whose socket replaced the first one's (that one would run on, unreachable, until the Mac ran out of memory).
        guard try FileLock.acquire(Paths.dir + "/\(spec.id).lock", wait: false) != nil else {
            throw RoofdError("session \(spec.id) is already running")
        }
        listenFd = try Sock.listen(socketPath)
        guard let exe = spec.argv.first else { throw RoofdError("empty argv") }
        let path = exe.hasPrefix("/") ? exe : Holder.which(exe, env: spec.env) ?? exe
        // LAB-529: replace, never append: an inherited copy listed first would win.
        var env = spec.env
        env["ONEROOF_SESSION"] = spec.id
        env["ONEROOF_ROOFD"] = Paths.control
        env["ONEROOF_ROOFD_BIN"] = Daemon.selfPath()   // what agent hooks call: `$ONEROOF_ROOFD_BIN report claude`
        let envList = env.map { "\($0.key)=\($0.value)" }
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
        // Every turn in its own autorelease pool (LAB-310). Foundation autoreleases objects (JSONSerialization for
        // each control request, NSString bridging), and this thread never returns to a run loop that would drain
        // them: without the pool a holder kept ~5 KB per `info` request forever, several GB per session in a day.
        while autoreleasepool(invoking: { turn(&buf) }) {}
        for c in clients.values { close(c.fd) }
        close(listenFd)
        unlink(socketPath)
        unlink(Paths.dir + "/\(spec.id).lock")   // still held: a holder that opens it now retries (FileLock)
    }

    /// One poll turn; false ends the holder.
    private func turn(_ buf: inout [UInt8]) -> Bool {
        if let at = exitedAt, Date().timeIntervalSince(at) > Holder.lingerSeconds { return false }
        var fds: [pollfd] = [pollfd(fd: listenFd, events: Int16(POLLIN), revents: 0),
                             pollfd(fd: wakeR, events: Int16(POLLIN), revents: 0)]
        if master >= 0 {
            fds.append(pollfd(fd: master, events: Int16(POLLIN) | (pendingInput.isEmpty ? 0 : Int16(POLLOUT)), revents: 0))
        }
        for c in clients.values {
            fds.append(pollfd(fd: c.fd, events: Int16(POLLIN) | (c.out.isEmpty ? 0 : Int16(POLLOUT)), revents: 0))
        }
        // LAB-1322: an idle session process woke 10.5 times a second (a 200 ms poll and a 250 ms status check, with
        // nothing to do). While output flows it still checks every 250 ms; after 2 s of quiet, once a second. Input,
        // output, clients and mail wake it at once either way (they are in the poll set).
        let busy = lastOutput.map { Date().timeIntervalSince($0) < 2 } ?? false
        let n = poll(&fds, nfds_t(fds.count), busy ? 200 : 1000)
        if n < 0 && errno != EINTR { return false }
        reapChild()
        if Date().timeIntervalSince(lastEval) >= (busy ? 0.25 : 0.95) { evaluateStatus() }
        if Date().timeIntervalSince(lastMemoryCheck) >= Daemon.watchdogInterval, !checkMemory() { return false }
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
        return true
    }

    /// LAB-1324: the most one wake-up reads from the PTY before forwarding.
    static let readBatch = 64 * 1024

    private func readMaster(_ buf: inout [UInt8]) {
        // LAB-1324: read what the PTY holds now, up to 64 KB, then forward and parse it once. A PTY read returns a few
        // KB; one read per wake-up meant a poll, a read and a parse dispatch per few KB, and under heavy output those
        // syscalls and worker-thread wake-ups were most of a holder's CPU (the parse itself a few percent). The PTY is
        // non-blocking, so the extra reads stop at once when it is empty; forwarding waits microseconds, not frames.
        let k = read(master, &buf, buf.count)
        var n = max(k, 0)
        var gone = k == 0 || (k < 0 && errno != EAGAIN && errno != EINTR)
        while n > 0, n < Holder.readBatch, !gone {
            let more = buf.withUnsafeMutableBytes { read(master, $0.baseAddress! + n, min($0.count, Holder.readBatch) - n) }
            if more > 0 { n += more; continue }
            gone = more == 0 || (errno != EAGAIN && errno != EINTR)
            break
        }
        if n > 0 {
            // Hot path: forward first (written at once when the client keeps up); the parse runs on vtQ.
            for c in clients.values where c.attached {
                c.out.appendFrame(.output, buf[0..<n])
                flush(c)
            }
            seq += n
            lastOutput = Date()
            if !Holder.skipVT {
                // LAB-1324: one parse block at a time, fed everything read since it last ran. A block per read (a PTY
                // read is a few KB) woke a GCD worker hundreds of times a second under heavy output: that churn, not
                // the parse, was most of a busy holder's CPU. Order is kept: bytes join `vtPending` in read order, and
                // a drain is always queued ahead of any later vtQ.sync (snapshot, resize, screen), which so sees them.
                vtLock.lock()
                vtPending.append(contentsOf: buf[0..<n])
                let schedule = !vtScheduled
                vtScheduled = true
                vtLock.unlock()
                if schedule { vtQ.async { [weak self] in self?.drainVT() } }
            }
        }
        if gone {
            // EIO: the child side closed (it exited).
            close(master)
            master = -1
            reapChild(block: true)
        }
    }

    /// LAB-1324 · bytes read but not yet parsed, and whether a drain is queued (both under vtLock).
    private let vtLock = NSLock()
    private var vtPending: [UInt8] = []
    private var vtScheduled = false

    /// On vtQ: parse everything pending, until nothing is left.
    private func drainVT() {
        let t = vt
        while true {
            vtLock.lock()
            if vtPending.isEmpty { vtScheduled = false; vtLock.unlock(); return }
            let bytes = vtPending
            vtPending.removeAll(keepingCapacity: true)
            vtLock.unlock()
            bytes.withUnsafeBufferPointer { rvt_feed(t, $0.baseAddress, $0.count) }
            var codes = [UInt8](repeating: 0, count: 32)
            let n = rvt_take_query_list(t, &codes, codes.count)
            if n > 0 { queriesSeen(Array(codes.prefix(n))) }
        }
    }

    /// On vtQ. Nobody attached: the holder answers the program's terminal queries itself, in the order they were
    /// sent, so a detached program never hangs (T14 §3c). Full-screen CLIs (Codex) send a batch ending in DA1 and
    /// draw nothing until every answer arrives. With a terminal attached, libghostty answers.
    private func queriesSeen(_ codes: [UInt8]) {
        mailLock.lock()
        let attached = anyAttached
        mailLock.unlock()
        // Left to the attached terminal (traced: LAB-223 looks for queries nobody answered).
        guard !attached else { Holder.trace("query-left-to-attached", codes); return }
        var reply = ""
        for c in codes {
            switch c {
            case 1: reply += "\u{1b}[?62;22c"                                   // DA1: VT220 + ANSI colour
            case 2:
                var x: UInt16 = 0, y: UInt16 = 0
                _ = rvt_cursor(vt, &x, &y)
                reply += "\u{1b}[\(Int(y) + 1);\(Int(x) + 1)R"                // cursor position
            case 3: reply += "\u{1b}[0n"                                        // operating status: OK
            case 4: reply += "\u{1b}]10;rgb:\(Holder.foreground)\u{1b}\\"     // foreground colour
            case 5: reply += "\u{1b}]11;rgb:\(Holder.background)\u{1b}\\"     // background colour
            case 6: reply += "\u{1b}[?0u"                                       // kitty keyboard: no flags
            default: break
            }
        }
        guard !reply.isEmpty else { return }
        mailLock.lock()
        mailReplies += Array(reply.utf8)
        mailLock.unlock()
        var one: UInt8 = 1
        _ = write(wakeW, &one, 1)
    }

    /// The theme colours a detached session reports (Midnight); the attached terminal answers with its own.
    static let foreground = "e6e6/e9e9/efef"
    static let background = "1c1c/2020/2828"

    /// LAB-310: false when the holder is over its memory limit and has ended the session.
    func checkMemory() -> Bool {
        lastMemoryCheck = Date()
        guard let f = MemoryWatchdog.footprint() else { return true }
        footprint = f
        let action = watchdog.check(footprint: f)
        guard action != .ok else { return true }
        MemoryLog.append(MemoryWatchdog.logLine(at: Date(), who: "session \(spec.id)", footprint: f, action: action))
        guard action == .stop else { return true }
        // Over the limit: a frozen Mac loses every session, this ends one. Hang up the program (its whole process
        // group), tell an attached terminal why, and exit; the holder's memory goes back to the system.
        if pid > 0, exitedAt == nil {
            kill(-pid, SIGHUP); kill(pid, SIGHUP)
            usleep(300_000)
            kill(-pid, SIGKILL); kill(pid, SIGKILL)
        }
        let bye = Wire.encode(.exit, json: ["code": exitCode as Any, "signal": exitSignal as Any, "reason": "memory",
                                            "footprint": Int(f)])
        for c in clients.values where c.attached { enqueue(c, bye); _ = c.out.write(to: c.fd) }
        return false
    }

    /// Queue bytes for the program; false (nothing queued) when it has stopped reading and the queue is full.
    @discardableResult
    private func queueInput(_ bytes: [UInt8]) -> Bool {
        guard pendingInput.count + bytes.count <= Holder.inputQueueLimit else { return false }
        pendingInput.append(contentsOf: bytes)
        return true
    }

    private func takeMail(_ buf: inout [UInt8]) {
        _ = read(wakeR, &buf, buf.count)
        mailLock.lock()
        let r = mailReplies
        mailReplies = []
        mailLock.unlock()
        queueInput(r)
        Holder.trace("query", r)
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
        if Wire.oversized(c.inbuf) { drop(c); return }   // LAB-310: never wait for a frame past the limit
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
                if !snapshot.isEmpty {
                    let frames = Wire.encodeChunked(.redraw, snapshot)
                    enqueue(c, frames)
                    c.redrawLeft = c.out.count
                }
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
            engine.input(at: Date())
            queueInput(payload)
            Holder.trace("attach", payload)
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

    // MARK: Status

    /// Who is in the foreground, and what the screen says once output has paused.
    func evaluateStatus() {
        let now = Date()
        lastEval = now
        var fg: AgentKind?
        if master >= 0, exitedAt == nil {
            let pg = roof_foreground_pgrp(master)
            if pg > 0, pg != pid {
                var name = [CChar](repeating: 0, count: 256)
                let pname = proc_name(pg, &name, UInt32(name.count)) > 0 ? String(cString: name) : nil
                fg = StatusEngine.agentKind(processName: pname, argv: ProcessProbe.args(pid: pg)?.argv ?? [])
                if fg != nil {
                    agentLeader = pg
                } else if let a = agent, agentLeader > 0, kill(agentLeader, 0) == 0 {
                    // A helper the agent started holds the foreground for a moment (an MCP server, a tool run): the
                    // agent is still alive and the shell is not back, so it is still that agent's session.
                    fg = a
                }
            }
            if fg == nil { agentLeader = 0 }
        }
        if fg != agent {
            // A new agent in the foreground: it may have drawn everything before it was seen, so read the screen now
            // and count that as its last change (otherwise a CLI that then goes quiet never becomes ready).
            screenSeq = -1
            contentKey = ""
            contentChangedAt = nil
        }
        agent = fg
        if fg != nil, seq != screenSeq || contentChangedAt == nil {
            screenSeq = seq
            let t = vt
            screen = vtQ.sync {
                var p: UnsafeMutablePointer<UInt8>?
                let len = rvt_text(t, 40, &p)
                defer { if let p { rvt_bytes_free(p, len) } }
                return p.map { String(decoding: UnsafeBufferPointer(start: $0, count: len), as: UTF8.self) } ?? ""
            }
            // Activity = the screen's content changed, not just bytes: an idle CLI repaints its status bar (usage,
            // clock, update notice) at the bottom, which must not read as working.
            let key = StatusEngine.contentKey(screen)
            if key != contentKey || contentChangedAt == nil { contentKey = key; contentChangedAt = contentChangedAt == nil ? (lastOutput ?? now) : now }
        }
        engine.evaluate(.init(now: now, agent: fg, lastOutput: fg == nil ? lastOutput : contentChangedAt, screen: screen))
        deliverOpening(now: now)
    }

    /// The app's opening-message rules (OpeningGate): only into a ready, idle agent after its settle time; marked sent
    /// at once; if the agent has not started working within 45 s, sent once more; then given up on.
    func deliverOpening(now: Date) {
        if let at = enterAt, now >= at {
            enterAt = nil
            queueInput([0x0D])
            Holder.trace("enter", [0x0D])
            flushInput()
        }
        guard let text = spec.opening, let kind = spec.kind, master >= 0, exitedAt == nil else { return }
        if openingState == "none" { openingState = "pending" }
        switch openingState {
        case "pending":
            if engine.ready, engine.status == .idle, agent != nil {
                if idleSince == nil { idleSince = now }
            } else {
                idleSince = nil
            }
            guard let since = idleSince, now.timeIntervalSince(since) >= OpeningGate.settle(kind) else { return }
            queueInput(Array(text.utf8))
            Holder.trace("opening", Array(text.utf8))
            flushInput()
            enterAt = now.addingTimeInterval(0.15)   // Enter separately: a submit, not a newline inside a paste
            engine.input(at: now)
            openingSentAt = now
            openingTries += 1
            openingState = "sent"
        case "sent":
            if engine.status.started { openingState = "done"; return }
            guard let at = openingSentAt, now.timeIntervalSince(at) >= 45 else { return }
            if openingTries < 2 { openingState = "pending"; idleSince = now } else { openingState = "failed" }
        default:
            return
        }
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
            "status": exitedAt == nil ? engine.status.rawValue : "unknown", "ready": engine.ready && exitedAt == nil,
            "agent": agent?.rawValue as Any, "opening": openingState,
            "x": Int(x), "y": Int(y), "modes": modes,
            "id": spec.id, "label": spec.label, "cwd": spec.cwd, "pid": Int(pid), "seq": seq, "title": title, "pwd": pwd, "work": workPath,
            "alt": alt, "attached": clients.values.contains { $0.attached }, "created": created.timeIntervalSince1970,
            // When the session last did something (LAB-258): an agent's screen content changing (not a status-bar
            // repaint), or a shell's output. The holder outlives the app, so a restarted app shows the real age.
            "active": ((agent != nil ? contentChangedAt : nil) ?? lastOutput ?? created).timeIntervalSince1970,
            // LAB-310: the holder's own memory, and whether it is past the warning line (the app can show it).
            "footprint": Int(footprint), "memoryWarning": watchdog.warned,
            "issues": issueQueue,
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
            guard queueInput(bytes) else { return ["error": "the program is not reading its input"] }
            engine.input(at: Date())
            Holder.trace("input-op", bytes)
            flushInput()
            return [:]
        case "report":
            // `roofd report <agent>` from an agent hook (Claude): the strongest status signal.
            engine.hook(j["event"] as? String ?? "", message: j["message"] as? String, at: Date())
            if let p = j["path"] as? String, p.hasPrefix("/") { workPath = p }
            evaluateStatus()
            return [:]
        case "seen":
            engine.seen()
            return [:]
        case "signal":
            guard master >= 0 else { return ["error": "session exited"] }
            let pg = roof_foreground_pgrp(master)
            if pg > 0 { kill(-pg, Int32(j["signal"] as? Int ?? Int(SIGINT))) }
            return [:]
        case "issue":
            // From `roofd issue` inside the session (LAB-518). The app checks the key and state against the session.
            guard let key = j["key"] as? String, !key.isEmpty else { return ["error": "no issue key"] }
            issueSeq += 1
            var r: [String: Any] = ["seq": issueSeq, "key": key]
            if let st = j["state"] as? String, !st.isEmpty { r["state"] = st }
            if let c = j["comment"] as? String, !c.isEmpty { r["comment"] = String(c.prefix(20_000)) }
            issueQueue.append(r)
            if issueQueue.count > 50 { issueQueue.removeFirst(issueQueue.count - 50) }
            return ["seq": issueSeq]
        case "issueStatus":
            guard let n = j["seq"] as? Int else { return ["error": "no seq"] }
            // A refusal is "refused", not "error": an "error" reply makes the asker's call throw.
            if let a = issueAnswers.removeValue(forKey: n) { return a.isEmpty ? ["done": true] : ["done": true, "refused": a] }
            return ["done": false]
        case "issueDone":
            guard let n = j["seq"] as? Int else { return ["error": "no seq"] }
            issueQueue.removeAll { ($0["seq"] as? Int) == n }
            issueAnswers[n] = j["error"] as? String ?? ""
            if issueAnswers.count > 50, let oldest = issueAnswers.keys.min() { issueAnswers[oldest] = nil }
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
        // LAB-1365: the redraw of a long session is often over the limit by itself (an SGR per coloured cell), and
        // since 1.9.10 terminals re-attach whenever they are shown again: dropping the client mid-redraw left the
        // terminal with part of its history, or none. The redraw is sent once and bounded by the scrollback, so it
        // is exempt; only what queues behind it (live output) counts.
        c.redrawLeft = min(c.redrawLeft, c.out.count)
        if c.out.count - c.redrawLeft > Holder.clientQueueLimit { drop(c); return }   // a slow client reattaches with a redraw
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
