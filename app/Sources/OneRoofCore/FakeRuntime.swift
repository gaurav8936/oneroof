import Foundation

/// An in-memory session runtime for tests: sessions start idle and ready, and every call is recorded.
/// Names follow herdr's rules (`<id>`, then `<id>-2`, `-3` …), so stored rows behave as they do on a real runtime.
public final class FakeRuntime: SessionRuntime, @unchecked Sendable {
    public let kind = RuntimeKind.fake
    public let expectedProtocol: Int? = nil

    private let lock = NSLock()
    private var _sessions: [RuntimeSessionState] = []
    private var _submitted: [(id: RuntimeID, text: String)] = []
    private var _typed: [(pane: String, text: String)] = []
    private var _pressed: [(pane: String, keys: [RuntimeKey])] = []
    private var counter = 0

    /// When false, `snapshot` and `start` fail as if the runtime were down.
    public var running = true
    /// Agents that refuse input (`submit` throws `notReady`).
    public var notReady: Set<RuntimeID> = []
    /// What `read` returns per pane.
    public var screen: [String: String] = [:]

    public init(sessions: [RuntimeSessionState] = []) { _sessions = sessions }

    private func locked<T>(_ f: () throws -> T) rethrows -> T { lock.lock(); defer { lock.unlock() }; return try f() }

    public var sessions: [RuntimeSessionState] { locked { _sessions } }
    public var submitted: [(id: RuntimeID, text: String)] { locked { _submitted } }
    public var typed: [(pane: String, text: String)] { locked { _typed } }
    public var pressed: [(pane: String, keys: [RuntimeKey])] { locked { _pressed } }

    /// Change a live session (status, ready, title …) as the agent would.
    public func update(_ id: RuntimeID, _ change: (inout RuntimeSessionState) -> Void) {
        locked { if let i = _sessions.firstIndex(where: { $0.id == id }) { change(&_sessions[i]) } }
    }

    /// The agent process ends on its own.
    public func exit(_ id: RuntimeID) { locked { _sessions.removeAll { $0.id == id } } }

    // MARK: SessionRuntime

    public func health() -> RuntimeHealth {
        running ? RuntimeHealth(level: .ok, detail: "fake · \(sessions.count) sessions")
            : RuntimeHealth(level: .fail, detail: "fake runtime stopped")
    }

    public func ensureRunning() throws { running = true }

    public func snapshot() throws -> RuntimeSnapshot {
        guard running else { throw RuntimeError.failed("fake runtime stopped") }
        return RuntimeSnapshot(version: "fake", sessions: locked { _sessions.filter(\.isAgent) + _sessions.filter { !$0.isAgent } })
    }

    public func start(_ spec: LaunchSpec) throws -> RuntimeSessionRef {
        guard running else { throw RuntimeError.failed("fake runtime stopped") }
        return locked {
            if spec.adoptOrphan, let orphan = _sessions.first(where: { $0.id == spec.id && $0.isAgent && !spec.claimed.contains($0.id) }) {
                return RuntimeSessionRef(id: orphan.id, groupId: orphan.groupId, adopted: true)
            }
            if let old = spec.previousGroup { _sessions.removeAll { $0.groupId == old } }
            counter += 1
            let group = "g\(counter)", pane = "p\(counter)"
            let name: RuntimeID
            if spec.agent.isAgent {
                let taken = Set(_sessions.map(\.id))
                var n = 1, candidate = spec.id
                while taken.contains(candidate) { n += 1; candidate = "\(spec.id)-\(n)" }
                name = candidate
            } else {
                name = Session.terminalPrefix + "t\(counter)"
            }
            _sessions.append(RuntimeSessionState(
                id: name, isAgent: spec.agent.isAgent, agentName: spec.agent.isAgent ? spec.agent.rawValue : nil,
                status: spec.agent.isAgent ? .idle : .unknown, ready: true, title: spec.label, cwd: spec.cwd,
                pane: pane, groupId: group, seq: 0))
            if let cmd = spec.command { _typed.append((pane, cmd + "\n")) }
            return RuntimeSessionRef(id: name, groupId: group)
        }
    }

    public func close(_ id: RuntimeID, group: String?) throws {
        locked { _sessions.removeAll { $0.id == id || (group != nil && $0.groupId == group) } }
    }

    public func submit(_ id: RuntimeID, text: String) throws {
        if notReady.contains(id) { throw RuntimeError.notReady(id) }
        try locked {
            guard let i = _sessions.firstIndex(where: { $0.id == id }) else { throw RuntimeError.failed("no session \(id)") }
            _submitted.append((id, text))
            _sessions[i].status = .working
            _sessions[i].seq = (_sessions[i].seq ?? 0) + 1
        }
    }

    public func type(pane: String, text: String) throws { locked { _typed.append((pane, text)) } }
    public func keys(pane: String, _ keys: [RuntimeKey]) throws { locked { _pressed.append((pane, keys)) } }
    public func read(pane: String, lines: Int) throws -> String {
        let text = screen[pane] ?? ""
        return text.split(separator: "\n", omittingEmptySubsequences: false).suffix(lines).joined(separator: "\n")
    }
    public func processes(pane: String) throws -> RuntimeProcesses { RuntimeProcesses() }
    public func attachCommand(_ id: RuntimeID) -> String { "/usr/bin/true \(id)" }
    public func markSeen(_ id: RuntimeID) { update(id) { if $0.status == .done { $0.status = .idle } } }
}
