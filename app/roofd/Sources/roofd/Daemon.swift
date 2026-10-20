import Darwin
import Foundation

/// The control plane (T14 §3d): create, list, info, read, input, signal, close over newline-delimited JSON on
/// roofd.sock. It holds no session state of its own: every session is a holder process with its own socket, so a
/// daemon crash or upgrade never ends a session (Q1), and a restarted daemon finds the holders by their sockets.
enum Daemon {
    static let proto = 1
    static let version = "0.1.0-spike"

    static func run() throws {
        signal(SIGPIPE, SIG_IGN)
        signal(SIGCHLD, SIG_IGN)   // holders are reparented away; never leave zombies
        try FileManager.default.createDirectory(atPath: Paths.dir, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        // One daemon per folder: two starts at once (the app's start and a launch) must not take each other's socket.
        let lockFd = open(Paths.dir + "/roofd.lock", O_CREAT | O_RDWR | O_CLOEXEC, 0o600)
        guard lockFd >= 0, flock(lockFd, LOCK_EX | LOCK_NB) == 0 else { return }   // held for the daemon's life
        let fd = try Sock.listen(Paths.control)
        var flags = fcntl(fd, F_GETFL); flags &= ~O_NONBLOCK; _ = fcntl(fd, F_SETFL, flags)
        while true {
            let c = accept(fd, nil, nil)
            if c < 0 { if errno == EINTR { continue }; break }
            DispatchQueue.global().async { serve(c) }
        }
    }

    private static func serve(_ fd: Int32) {
        defer { close(fd) }
        var one: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &one, socklen_t(MemoryLayout<Int32>.size))
        var buf: [UInt8] = []
        var chunk = [UInt8](repeating: 0, count: 65536)
        while !buf.contains(0x0A) {
            let n = read(fd, &chunk, chunk.count)
            if n <= 0 { return }
            buf += chunk[0..<n]
        }
        let req = (try? JSONSerialization.jsonObject(with: Data(buf.prefix { $0 != 0x0A }))) as? [String: Any] ?? [:]
        var reply: [String: Any]
        do { reply = try handle(req["method"] as? String ?? "", req["params"] as? [String: Any] ?? [:]) }
        catch { reply = ["error": "\(error)"] }
        var data = [UInt8]((try? JSONSerialization.data(withJSONObject: reply)) ?? Data("{}".utf8))
        data.append(0x0A)
        Sock.writeAll(fd, data)
    }

    static func handle(_ method: String, _ p: [String: Any]) throws -> [String: Any] {
        switch method {
        case "hello":
            return ["proto": proto, "version": version, "sessions": sessionIds().count]
        case "create":
            guard let id = p["id"] as? String, Paths.validId(id) else { throw RoofdError("bad id") }
            if let existing = try? Sock.holderRequest(Paths.session(id), ["op": "info"]) { return existing }   // idempotent
            try spawnHolder(p)
            for _ in 0..<60 {
                if let info = try? Sock.holderRequest(Paths.session(id), ["op": "info"], timeout: 1) { return info }
                usleep(50_000)
            }
            throw RoofdError("session \(id) did not start")
        case "list":
            return ["proto": proto, "version": version,
                    "sessions": sessionIds().compactMap { try? Sock.holderRequest(Paths.session($0), ["op": "info"], timeout: 1) }]
        case "info", "read", "input", "signal", "close":
            guard let id = p["id"] as? String, Paths.validId(id) else { throw RoofdError("bad id") }
            var r = p
            r["op"] = method
            return try Sock.holderRequest(Paths.session(id), r)
        default:
            throw RoofdError("unknown method \(method)")
        }
    }

    /// Sessions are the holder sockets in the roofd folder; stale sockets (nobody listening) are removed.
    static func sessionIds() -> [String] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: Paths.dir)) ?? []
        return names.filter { $0.hasSuffix(".sock") && $0 != "roofd.sock" }.map { String($0.dropLast(5)) }.filter { id in
            if let fd = Sock.connect(Paths.session(id)) { close(fd); return true }
            unlink(Paths.session(id))
            return false
        }.sorted()
    }

    /// `roofd session` in its own session (setsid), detached from the daemon. The spec (with the session's
    /// environment, which can hold keys) goes over a pipe on the holder's stdin, never on its command line,
    /// where `ps` would show it to every user.
    private static func spawnHolder(_ p: [String: Any]) throws {
        let spec = [UInt8](try JSONSerialization.data(withJSONObject: p))
        let exe = selfPath()
        var pipeFds: [Int32] = [0, 0]
        guard pipe(&pipeFds) == 0 else { throw RoofdError("pipe failed") }
        var attr: posix_spawnattr_t?
        posix_spawnattr_init(&attr)
        defer { posix_spawnattr_destroy(&attr) }
        posix_spawnattr_setflags(&attr, Int16(POSIX_SPAWN_SETSID | POSIX_SPAWN_CLOEXEC_DEFAULT))
        var actions: posix_spawn_file_actions_t?
        posix_spawn_file_actions_init(&actions)
        defer { posix_spawn_file_actions_destroy(&actions) }
        posix_spawn_file_actions_adddup2(&actions, pipeFds[0], 0)
        posix_spawn_file_actions_addopen(&actions, 1, "/dev/null", O_WRONLY, 0)
        posix_spawn_file_actions_addopen(&actions, 2, "/dev/null", O_WRONLY, 0)
        var env = ProcessInfo.processInfo.environment.map { "\($0.key)=\($0.value)" }
        env.append("ROOFD_DIR=\(Paths.dir)")
        let strings: [String] = [exe, "session", "--spec-stdin"]
        var argv: [UnsafeMutablePointer<CChar>?] = strings.map { s -> UnsafeMutablePointer<CChar>? in strdup(s) }
        argv.append(nil)
        var envp: [UnsafeMutablePointer<CChar>?] = env.map { s -> UnsafeMutablePointer<CChar>? in strdup(s) }
        envp.append(nil)
        defer { (argv + envp).forEach { free($0) } }
        var pid: pid_t = 0
        let rc = posix_spawn(&pid, exe, &actions, &attr, argv, envp)
        close(pipeFds[0])
        defer { close(pipeFds[1]) }
        guard rc == 0 else { throw RoofdError("spawn holder: \(String(cString: strerror(rc)))") }
        guard Sock.writeAll(pipeFds[1], spec) else { throw RoofdError("could not hand the spec to the holder") }
    }

    static func selfPath() -> String {
        var size: UInt32 = 4096
        var buf = [CChar](repeating: 0, count: Int(size))
        guard _NSGetExecutablePath(&buf, &size) == 0 else { return CommandLine.arguments[0] }
        return URL(fileURLWithPath: String(cString: buf)).resolvingSymlinksInPath().path
    }
}
