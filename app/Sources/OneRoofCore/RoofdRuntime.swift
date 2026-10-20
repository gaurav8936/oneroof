import Darwin
import Foundation

/// Sessions on roofd, One Roof's own session manager (LAB-ROOFD, T14). Talks to the daemon's control socket
/// (newline-delimited JSON, one request per connection); a terminal surface shows a session by running
/// `roofd attach <id>`. Status is interim until the status engine (LAB-14): the foreground process names the agent,
/// and recent output means working.
public final class RoofdRuntime: SessionRuntime, @unchecked Sendable {
    public let kind = RuntimeKind.roofd
    public var expectedProtocol: Int? { 1 }

    public let roofdPath: String
    public let dir: String
    /// Ghostty's resources (terminfo, shell integration) inside the app bundle, when present.
    let ghosttyResources: String?
    let terminfo: String?
    private let lock = NSLock()
    private var lastSeq: [RuntimeID: (seq: Int, changed: Date)] = [:]
    private var kinds: [RuntimeID: AgentKind] = [:]

    public init(roofdPath: String? = nil, dir: String? = nil, resources: URL? = Bundle.main.resourceURL) {
        self.roofdPath = roofdPath ?? RoofdRuntime.findRoofd()
        self.dir = dir ?? ProcessInfo.processInfo.environment["ROOFD_DIR"]
            ?? (NSHomeDirectory() as NSString).appendingPathComponent("Library/Application Support/One Roof/roofd")
        let g = resources?.appendingPathComponent("ghostty").path
        ghosttyResources = g.flatMap { FileManager.default.fileExists(atPath: $0) ? $0 : nil }
        let t = resources?.appendingPathComponent("terminfo").path
        terminfo = t.flatMap { FileManager.default.fileExists(atPath: $0) ? $0 : nil }
    }

    /// ONEROOF_ROOFD, else next to the app's own binary (Contents/MacOS/roofd), else on PATH.
    public static func findRoofd() -> String {
        if let p = ProcessInfo.processInfo.environment["ONEROOF_ROOFD"], FileManager.default.isExecutableFile(atPath: p) { return p }
        if let exe = Bundle.main.executableURL?.deletingLastPathComponent().appendingPathComponent("roofd").path,
           FileManager.default.isExecutableFile(atPath: exe) { return exe }
        return "roofd"
    }

    // MARK: Transport

    @discardableResult
    func call(_ method: String, _ params: [String: Any] = [:], timeout: Int = 10) throws -> [String: Any] {
        let path = dir + "/roofd.sock"
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw RuntimeError.failed("socket() failed") }
        defer { Darwin.close(fd) }
        var tv = timeval(tv_sec: timeout, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
        setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
        var one: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &one, socklen_t(MemoryLayout<Int32>.size))
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(path.utf8)
        guard bytes.count < MemoryLayout.size(ofValue: addr.sun_path) else { throw RuntimeError.failed("roofd socket path too long") }
        withUnsafeMutableBytes(of: &addr.sun_path) { raw in
            for (i, b) in bytes.enumerated() { raw[i] = b }
            raw[bytes.count] = 0
        }
        let rc = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        guard rc == 0 else { throw RuntimeError.failed("roofd is not running") }
        var data = try JSONSerialization.data(withJSONObject: ["method": method, "params": params])
        data.append(0x0A)
        let ok = data.withUnsafeBytes { raw -> Bool in
            var off = 0
            while off < raw.count {
                let n = write(fd, raw.baseAddress!.advanced(by: off), raw.count - off)
                if n <= 0 { return false }
                off += n
            }
            return true
        }
        guard ok else { throw RuntimeError.failed("roofd write failed") }
        var reply = Data()
        var chunk = [UInt8](repeating: 0, count: 65536)
        while true {
            let n = Darwin.read(fd, &chunk, chunk.count)
            if n <= 0 { break }
            reply.append(chunk, count: n)
            if chunk[n - 1] == 0x0A { break }
        }
        guard let obj = (try? JSONSerialization.jsonObject(with: reply)) as? [String: Any] else {
            throw RuntimeError.failed("roofd reply not understood (\(method))")
        }
        if let e = obj["error"] as? String { throw RuntimeError.failed("roofd: \(e)") }
        return obj
    }

    // MARK: Lifecycle

    public func health() -> RuntimeHealth {
        guard let r = try? call("hello", timeout: 2) else {
            return RuntimeHealth(level: .fail, detail: "roofd not running (\(dir))", fix: "\(roofdPath) daemon")
        }
        let proto = r["proto"] as? Int ?? 0
        let v = "running · \(r["version"] as? String ?? "?") · protocol \(proto) · \(r["sessions"] as? Int ?? 0) sessions"
        return RuntimeHealth(level: proto == 1 ? .ok : .warn, detail: v)
    }

    /// Start the daemon if it is not answering. (P4 registers it with launchd through SMAppService.)
    public func ensureRunning() throws {
        if (try? call("hello", timeout: 2)) != nil { return }
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        var attr: posix_spawnattr_t?
        posix_spawnattr_init(&attr)
        defer { posix_spawnattr_destroy(&attr) }
        posix_spawnattr_setflags(&attr, Int16(POSIX_SPAWN_SETSID | POSIX_SPAWN_CLOEXEC_DEFAULT))
        var actions: posix_spawn_file_actions_t?
        posix_spawn_file_actions_init(&actions)
        defer { posix_spawn_file_actions_destroy(&actions) }
        for fd: Int32 in [0, 1, 2] { posix_spawn_file_actions_addopen(&actions, fd, "/dev/null", fd == 0 ? O_RDONLY : O_WRONLY, 0) }
        var env = ProcessInfo.processInfo.environment
        for k in AccountResolver.accountVariables { env.removeValue(forKey: k) }   // never leak an account into sessions
        env["ROOFD_DIR"] = dir
        let args: [String] = [roofdPath, "daemon"]
        var argv: [UnsafeMutablePointer<CChar>?] = args.map { s -> UnsafeMutablePointer<CChar>? in strdup(s) }
        argv.append(nil)
        var envp: [UnsafeMutablePointer<CChar>?] = env.map { s -> UnsafeMutablePointer<CChar>? in strdup("\(s.key)=\(s.value)") }
        envp.append(nil)
        defer { (argv + envp).forEach { free($0) } }
        var pid: pid_t = 0
        let rc = posix_spawn(&pid, roofdPath, &actions, &attr, argv, envp)
        guard rc == 0 else { throw RuntimeError.failed("could not start roofd at \(roofdPath): \(String(cString: strerror(rc)))") }
        for _ in 0..<40 {
            if (try? call("hello", timeout: 1)) != nil { return }
            usleep(50_000)
        }
        throw RuntimeError.failed("roofd did not start")
    }

    // MARK: Snapshot

    public func snapshot() throws -> RuntimeSnapshot {
        let r = try call("list")
        let list = r["sessions"] as? [[String: Any]] ?? []
        let now = Date()
        var sessions: [RuntimeSessionState] = []
        lock.lock()
        defer { lock.unlock() }
        var seen = Set<RuntimeID>()
        for s in list {
            guard let id = s["id"] as? String, s["exited"] == nil else { continue }
            seen.insert(id)
            let seq = s["seq"] as? Int ?? 0
            if let last = lastSeq[id] { if last.seq != seq { lastSeq[id] = (seq, now) } } else { lastSeq[id] = (seq, .distantPast) }
            let pgid = (s["pgid"] as? Int).map { Int32($0) } ?? 0
            let shellPid = (s["pid"] as? Int).map { Int32($0) } ?? 0
            // The agent is the foreground process: a launched agent, or one typed into a terminal.
            let fg = pgid > 0 && pgid != shellPid ? RoofdRuntime.processName(pgid) : nil
            let detected = fg.flatMap { AgentKind(herdrName: $0) }.flatMap { $0.isAgent ? $0 : nil } ?? kinds[id]
            let busy = now.timeIntervalSince(lastSeq[id]?.changed ?? .distantPast) < 1.5
            let created = (s["created"] as? Double).map { Date(timeIntervalSince1970: $0) } ?? now
            let title = (s["title"] as? String).flatMap { $0.isEmpty ? nil : $0 }
            let cwd = (s["pwd"] as? String).flatMap { RoofdRuntime.pathFromOSC7($0) } ?? s["cwd"] as? String
            if let agent = detected, fg != nil {
                sessions.append(RuntimeSessionState(
                    id: id, isAgent: true, agentName: agent.rawValue, status: busy ? .working : .idle,
                    ready: now.timeIntervalSince(created) > 3, title: title, cwd: cwd, pane: id, seq: seq))
            } else {
                sessions.append(RuntimeSessionState(id: id, isAgent: false, status: .unknown, ready: true, title: title,
                                                    cwd: cwd, pane: id, seq: seq))
            }
        }
        for id in lastSeq.keys where !seen.contains(id) { lastSeq[id] = nil; kinds[id] = nil }
        return RuntimeSnapshot(version: r["version"] as? String ?? "roofd", protocolVersion: 1,
                               sessions: sessions.filter(\.isAgent) + sessions.filter { !$0.isAgent })
    }

    static func processName(_ pid: Int32) -> String? {
        var buf = [CChar](repeating: 0, count: 256)
        guard proc_name(pid, &buf, UInt32(buf.count)) > 0 else { return nil }
        return String(cString: buf)
    }

    static func pathFromOSC7(_ s: String) -> String? {
        guard s.hasPrefix("file://"), let u = URL(string: s) else { return s.hasPrefix("/") ? s : nil }
        return u.path.isEmpty ? nil : u.path
    }

    // MARK: Start

    /// The environment a session starts with: the app's own minus account variables, plus Ghostty's terminal type and
    /// shell integration (prompt marks, cwd, title), plus the launch's own variables (account, etc.).
    func environment(_ spec: LaunchSpec) -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        for k in AccountResolver.accountVariables { env.removeValue(forKey: k) }
        for k in ["GHOSTTY_BIN_DIR", "TERM_PROGRAM", "TERM_PROGRAM_VERSION", "TERM_SESSION_ID", "ROOFD_DIR", "ONEROOF_SESSION"] {
            env.removeValue(forKey: k)
        }
        env["COLORTERM"] = "truecolor"
        if let terminfo {
            env["TERM"] = "xterm-ghostty"
            env["TERMINFO"] = terminfo
        } else {
            env["TERM"] = "xterm-256color"
        }
        if let res = ghosttyResources {
            env["GHOSTTY_RESOURCES_DIR"] = res
            env["GHOSTTY_SHELL_FEATURES"] = "cursor:blink,path,title"
            // zsh: Ghostty's own injection (ZDOTDIR trick), restoring the owner's ZDOTDIR inside.
            if let z = env["ZDOTDIR"] { env["GHOSTTY_ZSH_ZDOTDIR"] = z }
            env["ZDOTDIR"] = res + "/shell-integration/zsh"
        }
        for (k, v) in spec.env { env[k] = v }
        return env
    }

    /// Q2: an agent starts through the owner's login shell and leaves a shell behind when it exits.
    func argv(_ spec: LaunchSpec) -> [String] {
        let shell = "/bin/zsh"
        guard spec.agent.isAgent else { return [shell, "-l", "-i"] }
        let cmd = ([spec.agent.herdrKind] + spec.args).map(RoofdRuntime.shellQuote).joined(separator: " ")
        return [shell, "-l", "-i", "-c", "\(cmd); exec \(shell) -l -i"]
    }

    static func shellQuote(_ s: String) -> String {
        if !s.isEmpty, s.allSatisfy({ $0.isLetter || $0.isNumber || "-_./=:@%+,".contains($0) }) { return s }
        return "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    public func start(_ spec: LaunchSpec) throws -> RuntimeSessionRef {
        try ensureRunning()
        let live = (try? call("list")["sessions"] as? [[String: Any]]) ?? []
        let alive = Set(live.compactMap { s -> String? in s["exited"] == nil ? s["id"] as? String : nil })
        let all = Set(live.compactMap { $0["id"] as? String })
        // An earlier launch that reported an error but started: link it instead of starting a second.
        if spec.adoptOrphan, alive.contains(spec.id), !spec.claimed.contains(spec.id) {
            return RuntimeSessionRef(id: spec.id, adopted: true)
        }
        var name = spec.id
        var n = 1
        while all.contains(name) { n += 1; name = "\(spec.id)-\(n)" }
        _ = try call("create", ["id": name, "label": spec.label, "cwd": spec.cwd, "env": environment(spec),
                                "argv": argv(spec), "cols": 120, "rows": 40])
        if spec.agent.isAgent { lock.lock(); kinds[name] = spec.agent; lock.unlock() }
        if let cmd = spec.command {
            DispatchQueue.global().asyncAfter(deadline: .now() + 1.2) { [weak self] in
                _ = try? self?.call("input", ["id": name, "text": cmd, "submit": true])
            }
        }
        return RuntimeSessionRef(id: name)
    }

    // MARK: Session I/O (pane = session id)

    public func close(_ id: RuntimeID, group: String?) throws { try call("close", ["id": id]) }

    /// Type the text, then press Enter separately, so a TUI sees a submit and not a newline inside a paste.
    public func submit(_ id: RuntimeID, text: String) throws {
        try call("input", ["id": id, "text": text])
        usleep(150_000)
        try call("input", ["id": id, "text": "\r"])
    }

    public func type(pane: String, text: String) throws { try call("input", ["id": pane, "text": text]) }

    public func keys(pane: String, _ keys: [RuntimeKey]) throws {
        let text = keys.map { k -> String in
            switch k { case .escape: return "\u{1b}"; case .enter: return "\r"; case .ctrlC: return "\u{03}" }
        }.joined()
        try call("input", ["id": pane, "text": text])
    }

    public func read(pane: String, lines: Int) throws -> String {
        try call("read", ["id": pane, "lines": lines])["text"] as? String ?? ""
    }

    public func processes(pane: String) throws -> RuntimeProcesses {
        let info = try call("info", ["id": pane])
        let shell = (info["pid"] as? Int).map { Int32($0) }
        guard let pg = info["pgid"] as? Int, pg > 0 else { return RuntimeProcesses(shellPid: shell) }
        var pids = [Int32](repeating: 0, count: 256)
        let n = proc_listpgrppids(pid_t(pg), &pids, Int32(pids.count * MemoryLayout<Int32>.size))
        let fg = pids.prefix(max(0, Int(n))).filter { $0 > 0 }.map { pid in
            RuntimeProcesses.Proc(pid: pid, name: RoofdRuntime.processName(pid), argv: ProcessProbe.args(pid: pid)?.argv ?? [])
        }
        return RuntimeProcesses(shellPid: shell, foreground: fg)
    }

    public func attachCommand(_ id: RuntimeID) -> String {
        "env ROOFD_DIR=\(RoofdRuntime.shellQuote(dir)) \(RoofdRuntime.shellQuote(roofdPath)) attach \(id)"
    }
}
