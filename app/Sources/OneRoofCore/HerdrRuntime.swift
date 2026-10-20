import Foundation

/// The herdr calls `HerdrRuntime` needs. `HerdrClient` is the real one; tests pass a fake.
public protocol HerdrTransport: AnyObject, Sendable {
    var herdrPath: String { get }
    func ping() -> Int?
    func ensureServer() throws
    func serverLeaks() -> [String: String]
    func stopServer()
    func snapshot() throws -> HerdrSnapshot
    func createWorkspace(cwd: String, env: [String: String], label: String) throws -> (workspace: String, pane: String)
    func startAgent(name: String, kind: String, paneId: String, args: [String], timeoutMs: Int) throws
    func prompt(agent: String, text: String) throws
    func processInfo(paneId: String) throws -> HerdrProcessInfo
    func closeWorkspace(_ id: String) throws
    func attachCommand(agent: String) -> String
    /// `herdr pane …` on the command line (send-text, send-keys, read, run): exit code and output.
    func paneCommand(_ args: [String], timeout: TimeInterval) -> (Int32, String)
}

extension HerdrClient: HerdrTransport {
    public func paneCommand(_ args: [String], timeout: TimeInterval) -> (Int32, String) {
        Foundations.run(herdrPath, ["pane"] + args, timeout: timeout)
    }
}

/// Sessions on herdr 0.9.x (protocol 22): one herdr workspace per session, agents addressed by name.
public final class HerdrRuntime: SessionRuntime, @unchecked Sendable {
    public let kind = RuntimeKind.herdr
    public var expectedProtocol: Int? { HerdrClient.supportedProtocol }
    public let client: HerdrTransport
    /// Wait between `agent.start` tries while the new pane's shell is still loading.
    let busyRetryDelay: useconds_t
    let typeCommandDelay: TimeInterval

    public init(client: HerdrTransport = HerdrClient(), busyRetryDelay: useconds_t = 500_000, typeCommandDelay: TimeInterval = 1.2) {
        self.client = client
        self.busyRetryDelay = busyRetryDelay
        self.typeCommandDelay = typeCommandDelay
    }

    public var herdrPath: String { client.herdrPath }

    // MARK: Lifecycle

    public func health() -> RuntimeHealth {
        guard let proto = client.ping() else {
            return RuntimeHealth(level: .fail, detail: "server not reachable at ~/.config/herdr/herdr.sock", fix: "herdr server")
        }
        let want = HerdrClient.supportedProtocol
        let v = "running · protocol \(proto)" + (proto == want ? "" : " (One Roof was built for \(want))")
        let leaks = client.serverLeaks()
        if !leaks.isEmpty {
            return RuntimeHealth(level: .warn,
                                 detail: "\(v) · server carries \(leaks.keys.sorted().joined(separator: ", ")): One Roof restarts it when no agents run")
        }
        return RuntimeHealth(level: proto == want ? .ok : .warn, detail: v)
    }

    public func ensureRunning() throws { try client.ensureServer() }

    public func snapshot() throws -> RuntimeSnapshot { Self.convert(try client.snapshot()) }

    /// herdr's agents become agent sessions; panes with a terminal id and no agent become plain shells ("term:<id>").
    public static func convert(_ s: HerdrSnapshot) -> RuntimeSnapshot {
        var sessions = s.agents.map { a in
            RuntimeSessionState(id: a.name, isAgent: true, agentName: a.agent, status: RuntimeStatus(a.agent_status),
                                ready: a.interactive_ready ?? false, title: a.terminal_title_stripped, cwd: a.foreground_cwd ?? a.cwd,
                                pane: a.pane_id, groupId: a.workspace_id, seq: a.revision)
        }
        var seen = Set(sessions.map(\.id))
        for p in s.panes {
            guard let t = p.terminal_id else { continue }
            let id = Session.terminalPrefix + t
            guard seen.insert(id).inserted else { continue }
            sessions.append(RuntimeSessionState(id: id, isAgent: false, status: .unknown, ready: true,
                                                cwd: p.foreground_cwd ?? p.cwd, pane: p.pane_id, groupId: p.workspace_id))
        }
        return RuntimeSnapshot(version: s.version, protocolVersion: s.protocol, sessions: sessions)
    }

    // MARK: Start

    /// Workspace in `spec.cwd` with the account's env → `agent.start` (or a plain shell, linked by its terminal id).
    public func start(_ spec: LaunchSpec) throws -> RuntimeSessionRef {
        var name = spec.id
        var group: String?
        do {
            try client.ensureServer()
            // herdr panes inherit the server's environment. A server started from a Claude2 shell would put
            // every "Claude1" launch on the wrong account: restart it clean if nothing is running, else refuse.
            let leaks = client.serverLeaks()
            if !leaks.isEmpty {
                let liveAgents = (try? client.snapshot().agents.count) ?? 1
                if liveAgents == 0 {
                    client.stopServer()
                    try client.ensureServer()
                } else {
                    throw HerdrClient.Failure.api(code: "herdr_env",
                        message: "herdr was started with \(leaks.keys.sorted().joined(separator: ", ")) set, so agents would start on the wrong account. Close its agents (or run `herdr server stop`) and launch again; One Roof restarts herdr cleanly.")
                }
            }
            // An earlier launch of this session may have started its agent and then reported an error
            // (the agent showed up as "started outside One Roof"). Link that agent instead of starting a second.
            let live = (try? client.snapshot().agents) ?? []
            if spec.adoptOrphan, let orphan = live.first(where: { $0.name == spec.id && !spec.claimed.contains($0.name) }) {
                return RuntimeSessionRef(id: orphan.name, groupId: orphan.workspace_id, adopted: true)
            }
            // herdr names must be unique: roof-<id>, then roof-<id>-2, -3 … on relaunches.
            let taken = Set(live.map(\.name))
            var n = 1
            while taken.contains(name) { n += 1; name = "\(spec.id)-\(n)" }
            // Relaunch: close the previous (now empty) workspace first.
            if let old = spec.previousGroup { try? client.closeWorkspace(old) }
            let (ws, pane) = try client.createWorkspace(cwd: spec.cwd, env: spec.env, label: spec.label)
            group = ws
            // A plain terminal: the shell in the new pane is the session. Link it by its terminal id.
            if !spec.agent.isAgent {
                let p = try client.snapshot().panes.first { $0.pane_id == pane }
                guard let t = p?.terminal_id else { throw HerdrClient.Failure.decode("new pane has no terminal id") }
                name = Session.terminalPrefix + t
                // A terminal opened to run something (a Fix button): type the command once the shell is up.
                if let cmd = spec.command {
                    let c = client
                    DispatchQueue.global().asyncAfter(deadline: .now() + typeCommandDelay) {
                        _ = c.paneCommand(["run", pane, cmd], timeout: 10)
                    }
                }
                return RuntimeSessionRef(id: name, groupId: ws)
            }
            // The new pane's shell may still be loading ~/.zshrc: retry while herdr says the pane is busy.
            var tries = 0
            while true {
                do {
                    try client.startAgent(name: name, kind: spec.agent.herdrKind, paneId: pane, args: spec.args, timeoutMs: 60_000)
                    break
                } catch HerdrClient.Failure.api(let code, _) where code == "agent_not_ready" {
                    break   // started, but waiting on a prompt (e.g. folder trust): it needs the owner
                } catch HerdrClient.Failure.api(let code, _) where code == "agent_pane_busy" && tries < 40 {
                    tries += 1
                    usleep(busyRetryDelay)
                }
            }
            return RuntimeSessionRef(id: name, groupId: ws)
        } catch {
            // herdr can create the agent and still return an error: if it exists, the launch worked.
            if let a = try? client.snapshot().agents.first(where: { $0.name == name }) {
                return RuntimeSessionRef(id: name, groupId: group ?? a.workspace_id)
            }
            throw error
        }
    }

    // MARK: Session I/O

    /// herdr ends a session by closing its workspace; without one there is nothing to close.
    public func close(_ id: RuntimeID, group: String?) throws {
        guard let group else { return }
        try client.closeWorkspace(group)
    }

    public func submit(_ id: RuntimeID, text: String) throws {
        do { try client.prompt(agent: id, text: text) }
        catch HerdrClient.Failure.api(let code, let message) where code == "agent_not_ready" { throw RuntimeError.notReady(message) }
    }

    public func type(pane: String, text: String) throws {
        try paneCall(["send-text", pane, text], timeout: 5)
    }

    public func keys(pane: String, _ keys: [RuntimeKey]) throws {
        for k in keys {
            let name: String
            switch k { case .escape: name = "esc"; case .enter: name = "enter"; case .ctrlC: name = "ctrl-c" }
            try paneCall(["send-keys", pane, name], timeout: 5)
        }
    }

    public func read(pane: String, lines: Int) throws -> String {
        try paneCall(["read", pane, "--source", "recent", "--lines", "\(lines)"], timeout: 4)
    }

    public func processes(pane: String) throws -> RuntimeProcesses {
        let info = try client.processInfo(paneId: pane)
        return RuntimeProcesses(shellPid: info.shell_pid,
                                foreground: (info.foreground_processes ?? []).map { .init(pid: $0.pid, name: $0.name, argv: $0.argv ?? []) })
    }

    public func attachCommand(_ id: RuntimeID) -> String { client.attachCommand(agent: id) }

    @discardableResult
    private func paneCall(_ args: [String], timeout: TimeInterval) throws -> String {
        let (rc, out) = client.paneCommand(args, timeout: timeout)
        guard rc == 0 else { throw RuntimeError.failed("herdr pane \(args.first ?? "") failed (\(rc))") }
        return out
    }
}
