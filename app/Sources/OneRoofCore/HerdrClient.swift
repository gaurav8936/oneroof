import Darwin
import Foundation

/// Minimal client for herdr's unix-socket JSON API (protocol 22, herdr 0.9.x).
/// One request per connection: `{"id","method","params"}\n` → one JSON line back.
public final class HerdrClient: @unchecked Sendable {
    public static let supportedProtocol = 22

    public enum Failure: Error, CustomStringConvertible {
        case notRunning(String)
        case io(String)
        case api(code: String, message: String)
        case decode(String)

        public var description: String {
            switch self {
            case .notRunning(let p): return "herdr server is not running (\(p))"
            case .io(let m): return "herdr socket error: \(m)"
            case .api(let c, let m): return "herdr \(c): \(m)"
            case .decode(let m): return "herdr reply not understood: \(m)"
            }
        }
    }

    public let socketPath: String
    public let herdrPath: String

    public init(
        socketPath: String = (NSHomeDirectory() as NSString).appendingPathComponent(".config/herdr/herdr.sock"),
        herdrPath: String? = nil
    ) {
        self.socketPath = socketPath
        self.herdrPath = herdrPath ?? HerdrClient.findHerdr()
    }

    public static func findHerdr() -> String {
        for p in ["/opt/homebrew/bin/herdr", "/usr/local/bin/herdr"] where FileManager.default.isExecutableFile(atPath: p) {
            return p
        }
        return "herdr"
    }

    // MARK: Transport

    /// Send one request, return the decoded `result` object.
    @discardableResult
    public func call(_ method: String, _ params: [String: Any] = [:], timeout: TimeInterval = 10) throws -> [String: Any] {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw Failure.io("socket() failed") }
        defer { close(fd) }

        var tv = timeval(tv_sec: Int(timeout), tv_usec: Int32((timeout - floor(timeout)) * 1_000_000))
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
        setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let pathBytes = Array(socketPath.utf8)
        guard pathBytes.count < MemoryLayout.size(ofValue: addr.sun_path) else { throw Failure.io("socket path too long") }
        withUnsafeMutableBytes(of: &addr.sun_path) { raw in
            for (i, b) in pathBytes.enumerated() { raw[i] = b }
            raw[pathBytes.count] = 0
        }
        let len = socklen_t(MemoryLayout<sockaddr_un>.size)
        let rc = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, len) }
        }
        guard rc == 0 else { throw Failure.notRunning(socketPath) }

        let req: [String: Any] = ["id": "oneroof-\(UUID().uuidString.prefix(8))", "method": method, "params": params]
        var data = try JSONSerialization.data(withJSONObject: req)
        data.append(0x0A)
        try data.withUnsafeBytes { raw in
            var off = 0
            while off < raw.count {
                let n = write(fd, raw.baseAddress!.advanced(by: off), raw.count - off)
                if n <= 0 { throw Failure.io("write failed") }
                off += n
            }
        }

        var reply = Data()
        var chunk = [UInt8](repeating: 0, count: 65536)
        while true {
            let n = read(fd, &chunk, chunk.count)
            if n <= 0 { break }
            reply.append(chunk, count: n)
            if chunk[n - 1] == 0x0A { break }
        }
        guard !reply.isEmpty else { throw Failure.io("empty reply to \(method)") }
        guard let obj = try JSONSerialization.jsonObject(with: reply) as? [String: Any] else {
            throw Failure.decode(String(decoding: reply.prefix(200), as: UTF8.self))
        }
        if let err = obj["error"] as? [String: Any] {
            throw Failure.api(code: err["code"] as? String ?? "error", message: err["message"] as? String ?? "")
        }
        return obj["result"] as? [String: Any] ?? [:]
    }

    // MARK: Server lifecycle

    /// PID of the process serving the socket (LOCAL_PEERPID), or nil.
    public func serverPID() -> Int32? {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return nil }
        defer { close(fd) }
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(socketPath.utf8)
        guard bytes.count < MemoryLayout.size(ofValue: addr.sun_path) else { return nil }
        withUnsafeMutableBytes(of: &addr.sun_path) { raw in
            for (i, b) in bytes.enumerated() { raw[i] = b }
            raw[bytes.count] = 0
        }
        let len = socklen_t(MemoryLayout<sockaddr_un>.size)
        let rc = withUnsafePointer(to: &addr) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, len) } }
        guard rc == 0 else { return nil }
        var pid: pid_t = 0
        var size = socklen_t(MemoryLayout<pid_t>.size)
        guard getsockopt(fd, SOL_LOCAL, LOCAL_PEERPID, &pid, &size) == 0, pid > 0 else { return nil }
        return pid
    }

    /// Account variables the running herdr server would leak into every pane (empty = clean).
    public func serverLeaks() -> [String: String] {
        guard let pid = serverPID(), let args = ProcessProbe.args(pid: pid) else { return [:] }
        var out: [String: String] = [:]
        for k in AccountResolver.accountVariables { if let v = args.env[k] { out[k] = v } }
        return out
    }

    /// Stop the server (all agents end). Only call when no agents are running.
    public func stopServer() {
        _ = try? call("server.stop", [:], timeout: 3)
        for _ in 0..<30 {
            if ping() == nil { return }
            usleep(100_000)
        }
    }

    public func ping() -> Int? {
        guard let r = try? call("ping", [:], timeout: 2) else { return nil }
        return r["protocol"] as? Int
    }

    /// Start `herdr server` detached (it outlives One Roof) if it is not already answering.
    public func ensureServer() throws {
        if ping() != nil { return }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: herdrPath)
        p.arguments = ["server"]
        p.currentDirectoryURL = URL(fileURLWithPath: Workspace.projectsRoot)
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        p.standardInput = FileHandle.nullDevice
        var env = ProcessInfo.processInfo.environment
        for k in AccountResolver.accountVariables { env.removeValue(forKey: k) }
        p.environment = env
        try p.run()
        for _ in 0..<40 {
            if ping() != nil { return }
            usleep(100_000)
        }
        throw Failure.notRunning(socketPath)
    }

    // MARK: Typed calls

    public func snapshot() throws -> HerdrSnapshot {
        let r = try call("session.snapshot")
        let snap = r["snapshot"] as? [String: Any] ?? [:]
        let data = try JSONSerialization.data(withJSONObject: snap)
        do { return try JSONDecoder().decode(HerdrSnapshot.self, from: data) }
        catch { throw Failure.decode("\(error)") }
    }

    /// Create a workspace whose shell starts in `cwd` with `env`; returns (workspace id, root pane id).
    public func createWorkspace(cwd: String, env: [String: String], label: String) throws -> (workspace: String, pane: String) {
        let r = try call("workspace.create", ["cwd": cwd, "env": env, "label": label, "focus": false])
        guard let root = r["root_pane"] as? [String: Any], let pane = root["pane_id"] as? String else {
            throw Failure.decode("workspace.create: no root_pane")
        }
        let ws = root["workspace_id"] as? String ?? (r["workspace"] as? [String: Any])?["workspace_id"] as? String ?? ""
        return (ws, pane)
    }

    public func startAgent(name: String, kind: String, paneId: String, args: [String] = [], timeoutMs: Int = 60_000) throws {
        try call("agent.start", ["name": name, "kind": kind, "pane_id": paneId, "args": args, "timeout_ms": timeoutMs],
                 timeout: TimeInterval(timeoutMs) / 1000 + 5)
    }

    /// Submit text to an agent. Callers send only when herdr reports the agent idle, so we never type into a busy agent.
    public func prompt(agent: String, text: String) throws {
        try call("agent.prompt", ["target": agent, "text": text], timeout: 15)
    }

    public func processInfo(paneId: String) throws -> HerdrProcessInfo {
        let r = try call("pane.process_info", ["pane_id": paneId])
        let info = r["process_info"] as? [String: Any] ?? [:]
        let data = try JSONSerialization.data(withJSONObject: info)
        do { return try JSONDecoder().decode(HerdrProcessInfo.self, from: data) }
        catch { throw Failure.decode("\(error)") }
    }

    public func closeWorkspace(_ id: String) throws {
        try call("workspace.close", ["workspace_id": id])
    }

    public func renameAgent(_ target: String, to name: String) throws {
        try call("agent.rename", ["target": target, "name": name])
    }

    /// The command a terminal surface runs to show an agent: `herdr agent attach <name>`.
    /// A plain terminal ("term:<terminal_id>") attaches to its raw terminal stream instead.
    public func attachCommand(agent: String) -> String {
        if agent.hasPrefix(Session.terminalPrefix) {
            return "\(herdrPath) terminal attach \(agent.dropFirst(Session.terminalPrefix.count))"
        }
        return "\(herdrPath) agent attach \(agent)"
    }
}

// MARK: Snapshot types (only the fields One Roof uses; all optional so herdr can add fields freely)

public struct HerdrSnapshot: Decodable, Sendable {
    public var version: String?
    public var `protocol`: Int?
    public var workspaces: [HerdrWorkspace]
    public var panes: [HerdrPane]
    public var agents: [HerdrAgent]

    enum CodingKeys: String, CodingKey { case version, `protocol`, workspaces, panes, agents }

    public init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        version = try c.decodeIfPresent(String.self, forKey: .version)
        `protocol` = try c.decodeIfPresent(Int.self, forKey: .protocol)
        // Lossy: one entry herdr shapes differently must never hide every session.
        workspaces = (try c.decodeIfPresent([Lossy<HerdrWorkspace>].self, forKey: .workspaces) ?? []).compactMap(\.value)
        panes = (try c.decodeIfPresent([Lossy<HerdrPane>].self, forKey: .panes) ?? []).compactMap(\.value)
        agents = (try c.decodeIfPresent([Lossy<HerdrAgent>].self, forKey: .agents) ?? []).compactMap(\.value)
    }

    public init(workspaces: [HerdrWorkspace] = [], panes: [HerdrPane] = [], agents: [HerdrAgent] = []) {
        self.workspaces = workspaces; self.panes = panes; self.agents = agents
    }
}

/// Decodes one array element, or nil if it does not fit.
struct Lossy<T: Decodable & Sendable>: Decodable, Sendable {
    let value: T?
    init(from d: Decoder) throws { value = try? T(from: d) }
}

public struct HerdrWorkspace: Decodable, Sendable {
    public var workspace_id: String
    public var label: String?
}

public struct HerdrPane: Decodable, Sendable {
    public var pane_id: String
    public var terminal_id: String?
    public var workspace_id: String?
    public var cwd: String?
    public var foreground_cwd: String?
    public var agent_status: String?
}

public struct HerdrAgent: Decodable, Sendable {
    public var name: String
    public var agent: String?
    public var agent_status: String?
    public var cwd: String?
    public var foreground_cwd: String?
    public var pane_id: String
    public var terminal_id: String?
    public var workspace_id: String?
    public var terminal_title_stripped: String?
    public var interactive_ready: Bool?
    /// Bumps when the pane's output changes (v2 caption engine's "new output" signal).
    public var revision: Int?

    public init(name: String, agent: String?, agent_status: String?, cwd: String?, pane_id: String,
                workspace_id: String? = nil, terminal_title_stripped: String? = nil) {
        self.name = name; self.agent = agent; self.agent_status = agent_status; self.cwd = cwd
        self.foreground_cwd = cwd; self.pane_id = pane_id; self.workspace_id = workspace_id
        self.terminal_title_stripped = terminal_title_stripped
    }

    enum CodingKeys: String, CodingKey {
        case name, agent, agent_status, cwd, foreground_cwd, pane_id, terminal_id, workspace_id, terminal_title_stripped, interactive_ready
    }

    /// herdr also reports agents it detected but that were never named (started by typing `claude` in a herdr
    /// pane). Those have no `name`; One Roof addresses them by their terminal ("term:<id>") so one unnamed agent
    /// never breaks the whole snapshot.
    public init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        pane_id = try c.decode(String.self, forKey: .pane_id)
        terminal_id = try c.decodeIfPresent(String.self, forKey: .terminal_id)
        name = try c.decodeIfPresent(String.self, forKey: .name)
            ?? terminal_id.map { Session.terminalPrefix + $0 } ?? "pane:" + pane_id
        agent = try c.decodeIfPresent(String.self, forKey: .agent)
        agent_status = try c.decodeIfPresent(String.self, forKey: .agent_status)
        cwd = try c.decodeIfPresent(String.self, forKey: .cwd)
        foreground_cwd = try c.decodeIfPresent(String.self, forKey: .foreground_cwd)
        workspace_id = try c.decodeIfPresent(String.self, forKey: .workspace_id)
        terminal_title_stripped = try c.decodeIfPresent(String.self, forKey: .terminal_title_stripped)
        interactive_ready = try c.decodeIfPresent(Bool.self, forKey: .interactive_ready)
    }
}

public struct HerdrProcessInfo: Decodable, Sendable {
    public struct Proc: Decodable, Sendable {
        public var pid: Int32
        public var name: String?
        public var argv: [String]?
    }
    public var shell_pid: Int32?
    public var foreground_processes: [Proc]?
}
