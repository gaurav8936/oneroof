import Darwin
import Foundation
import OneRoofCore

/// The control plane (T14 §3d): create, list, info, read, input, signal, close over newline-delimited JSON on
/// roofd.sock. It holds no session state of its own: every session is a holder process with its own socket, so a
/// daemon crash or upgrade never ends a session (Q1), and a restarted daemon finds the holders by their sockets.
enum Daemon {
    static let proto = 1
    static let version = "0.4.0"
    /// Each holder's last info answer, for a list taken while it is briefly busy.
    nonisolated(unsafe) static var lastInfo: [String: [String: Any]] = [:]
    static let cacheLock = NSLock()
    /// Started by launchd as One Roof's background item (launchd sets XPC_SERVICE_NAME to the job's label).
    static let underLaunchd = ProcessInfo.processInfo.environment["XPC_SERVICE_NAME"] == "io.github.gaurav8936.oneroof.roofd"
    /// This binary's build: its modification time at start. The app compares it with the roofd in its bundle.
    static let build: Double = {
        let attrs = try? FileManager.default.attributesOfItem(atPath: selfPath())
        return ((attrs?[.modificationDate] as? Date) ?? Date(timeIntervalSince1970: 0)).timeIntervalSince1970.rounded()
    }()

    static func run() throws {
        var noCore = rlimit(rlim_cur: 0, rlim_max: 0)
        setrlimit(RLIMIT_CORE, &noCore)
        signal(SIGPIPE, SIG_IGN)
        signal(SIGCHLD, SIG_IGN)   // holders are reparented away; never leave zombies
        try FileManager.default.createDirectory(atPath: Paths.dir, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        // One daemon per folder. A second start waits for the lock instead of exiting: under launchd (KeepAlive) an
        // exit would be restarted in a loop; waiting means it takes over the moment the running one stops (upgrade).
        // Only this lock decides which daemon serves the folder (LAB-310 checked: a second daemon, from launchd or the
        // app, blocks here and never binds the socket). The lock is held for life; the kernel frees it on any exit.
        guard let lockFd = try FileLock.acquire(Paths.dir + "/roofd.lock", wait: true) else { throw RoofdError("lock failed") }
        _ = lockFd
        let fd = try Sock.listen(Paths.control)
        Scheduler.start()
        startWatchdog()
        var flags = fcntl(fd, F_GETFL); flags &= ~O_NONBLOCK; _ = fcntl(fd, F_SETFL, flags)
        while true {
            let c = accept(fd, nil, nil)
            if c < 0 { if errno == EINTR { continue }; break }
            DispatchQueue.global().async { autoreleasepool { serve(c) } }
        }
    }

    /// The memory guard (LAB-310): the daemon keeps no session state, so it is a few MB; far above that something is
    /// wrong and it stops (launchd or the app starts a fresh one; sessions live in their holders and keep running).
    static func startWatchdog() {
        Thread.detachNewThread {
            var dog = MemoryWatchdog.from(env: ProcessInfo.processInfo.environment, prefix: "ROOFD_DAEMON",
                                          warnMB: MemoryWatchdog.daemonWarnMB, limitMB: MemoryWatchdog.daemonLimitMB)
            while true {
                autoreleasepool {
                    guard let f = MemoryWatchdog.footprint() else { return }
                    let action = dog.check(footprint: f)
                    guard action != .ok else { return }
                    MemoryLog.append(MemoryWatchdog.logLine(at: Date(), who: "daemon", footprint: f, action: action))
                    if action == .stop { exit(3) }
                }
                Thread.sleep(forTimeInterval: watchdogInterval)
            }
        }
    }

    /// How often each roofd process looks at its footprint (ROOFD_WATCHDOG_SECONDS for tests).
    static let watchdogInterval = Double(ProcessInfo.processInfo.environment["ROOFD_WATCHDOG_SECONDS"] ?? "") ?? 10

    /// A request is one JSON line; `create` carries an environment, so allow a few MB, never more.
    static let maxRequestBytes = 4 << 20

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
            if buf.count > maxRequestBytes { return }
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
            return ["proto": proto, "version": version, "build": build, "pid": Int(getpid()), "launchd": underLaunchd,
                    "sessions": sessionIds().count, "footprint": Int(MemoryWatchdog.footprint() ?? 0)]
        case "upgrade":
            // The app found a newer roofd: reply, then exit; launchd (or the app) starts the new binary, which takes the
            // lock. Holders are separate processes and keep every session running (Q8).
            DispatchQueue.global().asyncAfter(deadline: .now() + 0.2) { exit(0) }
            return ["exiting": true]
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
            // A holder that is busy for a moment (a heavy repaint) must not vanish from the list: the app would show
            // its session as Exited. Use its last answer while its socket still accepts connections.
            let sessions: [[String: Any]] = sessionIds().compactMap { id in
                if let info = try? Sock.holderRequest(Paths.session(id), ["op": "info"], timeout: 2) {
                    cacheLock.lock(); lastInfo[id] = info; cacheLock.unlock()
                    return info
                }
                cacheLock.lock(); defer { cacheLock.unlock() }
                return lastInfo[id]
            }
            cacheLock.lock()
            let live = Set(sessions.compactMap { $0["id"] as? String })
            for k in lastInfo.keys where !live.contains(k) { lastInfo[k] = nil }
            cacheLock.unlock()
            return ["proto": proto, "version": version, "sessions": sessions]
        case "scheduler":
            // From the app: Settings › Allow scheduled runs, and where its session store is.
            if let enabled = p["enabled"] as? Bool, let store = p["store"] as? String {
                try Scheduler.save(.init(enabled: enabled, store: store, projects: p["projects"] as? String, shared: p["shared"] as? String))
            }
            let c = Scheduler.config()
            return ["enabled": c?.enabled ?? false, "store": c?.store ?? ""]
        case "info", "read", "input", "signal", "close", "seen", "issueDone":
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
        posix_spawnattr_setflags(&attr, Int16(POSIX_SPAWN_SETSID | POSIX_SPAWN_CLOEXEC_DEFAULT | POSIX_SPAWN_SETSIGDEF | POSIX_SPAWN_SETSIGMASK))
        var all = sigset_t(), none = sigset_t()
        sigfillset(&all); sigemptyset(&none)
        posix_spawnattr_setsigdefault(&attr, &all)    // children start with default signal handling
        posix_spawnattr_setsigmask(&attr, &none)
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
