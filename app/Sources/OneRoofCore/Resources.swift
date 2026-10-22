import Darwin
import Foundation

// Resources (LAB-493): what One Roof itself costs, per session and overall. On 10-21 roofd session holders grew to
// 5+ GB each and froze a 16 GB Mac (LAB-310); this lets the owner see that coming. Pure aggregation here (process
// trees, CPU deltas, grouping, history, headroom); the Darwin reads sit behind `ResourceSource` so tests run on
// synthetic process tables.

// MARK: Process table

/// One process as the kernel lists it.
public struct ProcEntry: Equatable, Sendable {
    public var pid: Int32
    public var ppid: Int32
    public var name: String
    public init(pid: Int32, ppid: Int32, name: String) { self.pid = pid; self.ppid = ppid; self.name = name }
}

/// Every process on the Mac with a parent → children map (one `KERN_PROC_ALL` read per tick).
public struct ProcTable: Sendable {
    public let byPid: [Int32: ProcEntry]
    public let children: [Int32: [Int32]]

    public init(_ entries: [ProcEntry]) {
        var by: [Int32: ProcEntry] = [:]
        var kids: [Int32: [Int32]] = [:]
        for e in entries where e.pid > 0 {
            by[e.pid] = e
            if e.ppid != e.pid { kids[e.ppid, default: []].append(e.pid) }
        }
        byPid = by
        children = kids.mapValues { $0.sorted() }
    }

    /// `root` and all its descendants, depth first (parents before children, children by pid), with their depth.
    /// Stops at any pid in `excluding` (a subtree counted elsewhere, e.g. the daemon under an app that started it).
    public func tree(_ root: Int32, excluding: Set<Int32> = []) -> [(pid: Int32, depth: Int)] {
        guard byPid[root] != nil else { return [] }
        var out: [(pid: Int32, depth: Int)] = []
        var seen = Set<Int32>()
        func walk(_ p: Int32, _ d: Int) {
            guard seen.insert(p).inserted else { return }
            out.append((p, d))
            for c in children[p] ?? [] where !excluding.contains(c) { walk(c, d + 1) }
        }
        walk(root, 0)
        return out
    }
}

// MARK: Readings

/// What the kernel says about one process: footprint (Activity Monitor's Memory column, what jetsam counts) and
/// total CPU time so far.
public struct RawUsage: Equatable, Sendable {
    public var footprint: UInt64
    public var cpuNanos: UInt64
    public init(footprint: UInt64, cpuNanos: UInt64) { self.footprint = footprint; self.cpuNanos = cpuNanos }
}

/// The Mac's memory as Activity Monitor shows it.
public struct MacMemory: Equatable, Sendable {
    public enum Pressure: String, Sendable { case normal, warn, critical }
    public var total: UInt64
    /// App memory + wired + compressed (Activity Monitor's "Memory Used").
    public var used: UInt64
    public var swapUsed: UInt64
    public var pressure: Pressure
    public init(total: UInt64, used: UInt64, swapUsed: UInt64, pressure: Pressure) {
        self.total = total; self.used = used; self.swapUsed = swapUsed; self.pressure = pressure
    }

    /// `kern.memorystatus_vm_pressure_level`: 1 normal, 2 warn, 4 critical (the DISPATCH_MEMORYPRESSURE_* values).
    public static func pressure(level: Int) -> Pressure {
        switch level {
        case 4...: return .critical
        case 2, 3: return .warn
        default: return .normal
        }
    }

    public var label: String {
        switch pressure {
        case .normal: return "normal"
        case .warn: return "under pressure"
        case .critical: return "critical"
        }
    }
}

/// Where readings come from (the Darwin calls in `LiveResourceSource`; tests pass a fake).
public protocol ResourceSource: AnyObject {
    func processes() -> [ProcEntry]
    func usage(_ pid: Int32) -> RawUsage?
    /// A process's environment (nil when it cannot be read): a holder's own watchdog lines.
    func environment(_ pid: Int32) -> [String: String]?
    /// A fuller name than `ProcEntry.name` (which the kernel cuts at 16 characters).
    func name(_ pid: Int32) -> String?
    func mac() -> MacMemory?
    /// When a process started (uptime of the app, the daemon and holders).
    func startTime(_ pid: Int32) -> Date?
    /// Monotonic clock, nanoseconds.
    func nowNanos() -> UInt64
}

// MARK: CPU

/// CPU % between two samples of one process: delta CPU time / delta wall time × 100 (can pass 100 with several
/// threads busy, like Activity Monitor). Remembers the last sample per pid.
public struct CPUMeter: Sendable {
    private var last: [Int32: (cpu: UInt64, at: UInt64)] = [:]
    public init() {}

    /// nil on the first sample of a pid (no delta yet); 0 when the counter went backwards (the pid was reused).
    public mutating func percent(pid: Int32, cpuNanos: UInt64, at: UInt64) -> Double? {
        defer { last[pid] = (cpuNanos, at) }
        guard let prev = last[pid], at > prev.at else { return nil }
        guard cpuNanos >= prev.cpu else { return 0 }
        return Double(cpuNanos - prev.cpu) / Double(at - prev.at) * 100
    }

    /// Forget pids that are gone.
    public mutating func keep(_ pids: Set<Int32>) { last = last.filter { pids.contains($0.key) } }
    public var tracked: Int { last.count }
}

// MARK: Snapshot

public enum ProcRole: String, Sendable { case app, daemon, holder, agent, child }

/// One process in a group, with what it costs now.
public struct ProcUsage: Equatable, Sendable, Identifiable {
    public var pid: Int32
    public var ppid: Int32
    public var name: String
    public var depth: Int
    public var role: ProcRole
    public var footprint: UInt64
    /// nil until the second sample.
    public var cpu: Double?
    /// Set for the app, the daemon and holders.
    public var started: Date?
    public var id: Int32 { pid }
    public init(pid: Int32, ppid: Int32, name: String, depth: Int, role: ProcRole, footprint: UInt64, cpu: Double?, started: Date? = nil) {
        self.pid = pid; self.ppid = ppid; self.name = name; self.depth = depth; self.role = role
        self.footprint = footprint; self.cpu = cpu; self.started = started
    }
}

/// The watchdog's lines for a holder or the daemon, and where a footprint sits against them.
public struct Headroom: Equatable, Sendable {
    public enum Level: Int, Sendable, Comparable {
        case ok, warn, nearLimit
        public static func < (a: Level, b: Level) -> Bool { a.rawValue < b.rawValue }
    }
    public var warnBytes: UInt64
    public var limitBytes: UInt64
    public init(warnBytes: UInt64, limitBytes: UInt64) {
        let d = MemoryWatchdog(warnBytes: warnBytes, limitBytes: limitBytes)
        self.warnBytes = d.warnBytes; self.limitBytes = d.limitBytes
    }

    public static let holderDefault = Headroom(warnBytes: MemoryWatchdog.holderWarnMB * MemoryWatchdog.mb,
                                               limitBytes: MemoryWatchdog.holderLimitMB * MemoryWatchdog.mb)
    public static let daemonDefault = Headroom(warnBytes: MemoryWatchdog.daemonWarnMB * MemoryWatchdog.mb,
                                               limitBytes: MemoryWatchdog.daemonLimitMB * MemoryWatchdog.mb)

    /// The lines a roofd process actually runs with: its environment's overrides (`ROOFD_SESSION_MEM_WARN_MB` …),
    /// read the same way roofd reads them, else the defaults.
    public static func holder(env: [String: String]?) -> Headroom {
        guard let env else { return holderDefault }
        let d = MemoryWatchdog.from(env: env, prefix: "ROOFD_SESSION", warnMB: MemoryWatchdog.holderWarnMB, limitMB: MemoryWatchdog.holderLimitMB)
        return Headroom(warnBytes: d.warnBytes, limitBytes: d.limitBytes)
    }
    public static func daemon(env: [String: String]?) -> Headroom {
        guard let env else { return daemonDefault }
        let d = MemoryWatchdog.from(env: env, prefix: "ROOFD_DAEMON", warnMB: MemoryWatchdog.daemonWarnMB, limitMB: MemoryWatchdog.daemonLimitMB)
        return Headroom(warnBytes: d.warnBytes, limitBytes: d.limitBytes)
    }

    /// "Near the limit" = the last 10% before roofd ends the process.
    public func level(_ footprint: UInt64) -> Level {
        if footprint >= limitBytes - limitBytes / 10 { return .nearLimit }
        if footprint >= warnBytes { return .warn }
        return .ok
    }

    /// 0…1 of the way to the limit.
    public func fraction(_ footprint: UInt64) -> Double { min(1, Double(footprint) / Double(max(limitBytes, 1))) }
    /// What is left before the limit.
    public func left(_ footprint: UInt64) -> UInt64 { limitBytes > footprint ? limitBytes - footprint : 0 }
}

/// One session's cost: its holder (`roofd session`) and every process under it (the agent, shells, MCP servers …).
public struct SessionUsage: Equatable, Sendable {
    public var runtimeId: String
    public var holderPid: Int32?
    public var procs: [ProcUsage]
    public var headroom: Headroom
    /// roofd's own flag from `info` (LAB-310): the holder crossed its warning line.
    public var memoryWarning: Bool
    public init(runtimeId: String, holderPid: Int32?, procs: [ProcUsage], headroom: Headroom = .holderDefault, memoryWarning: Bool = false) {
        self.runtimeId = runtimeId; self.holderPid = holderPid; self.procs = procs; self.headroom = headroom; self.memoryWarning = memoryWarning
    }
    public var footprint: UInt64 { procs.reduce(0) { $0 + $1.footprint } }
    public var cpu: Double { procs.reduce(0) { $0 + ($1.cpu ?? 0) } }
    /// The holder alone: what roofd's watchdog measures against its lines.
    public var holderFootprint: UInt64 { procs.first { $0.role == .holder }?.footprint ?? 0 }
    public var level: Headroom.Level { holderPid == nil ? .ok : max(headroom.level(holderFootprint), memoryWarning ? .warn : .ok) }
}

/// One tick of everything One Roof runs.
public struct ResourceSnapshot: Equatable, Sendable {
    public var at: Date
    /// The app and what it started (terminal `roofd attach` processes, the local model …), daemon and holders excluded.
    public var app: [ProcUsage]
    public var daemon: ProcUsage?
    public var daemonHeadroom: Headroom
    /// By runtime id.
    public var sessions: [String: SessionUsage]
    /// Holders under the daemon that no live session claims (an exited session's holder still winding down).
    public var unclaimed: [SessionUsage]
    public var mac: MacMemory?
    /// How long this tick took to read, nanoseconds.
    public var costNanos: UInt64

    public init(at: Date = Date(), app: [ProcUsage] = [], daemon: ProcUsage? = nil, daemonHeadroom: Headroom = .daemonDefault,
                sessions: [String: SessionUsage] = [:], unclaimed: [SessionUsage] = [], mac: MacMemory? = nil, costNanos: UInt64 = 0) {
        self.at = at; self.app = app; self.daemon = daemon; self.daemonHeadroom = daemonHeadroom; self.sessions = sessions
        self.unclaimed = unclaimed; self.mac = mac; self.costNanos = costNanos
    }

    /// Every process counted once.
    public var allProcs: [ProcUsage] {
        var seen = Set<Int32>()
        var out: [ProcUsage] = []
        for p in app + (daemon.map { [$0] } ?? []) + sessions.values.flatMap(\.procs) + unclaimed.flatMap(\.procs) where seen.insert(p.pid).inserted {
            out.append(p)
        }
        return out
    }
    public var footprint: UInt64 { allProcs.reduce(0) { $0 + $1.footprint } }
    public var cpu: Double { allProcs.reduce(0) { $0 + ($1.cpu ?? 0) } }
    public var processCount: Int { allProcs.count }
    public var appFootprint: UInt64 { app.reduce(0) { $0 + $1.footprint } }
    public var appCPU: Double { app.reduce(0) { $0 + ($1.cpu ?? 0) } }
}

// MARK: Sampler

/// What to sample this tick: the app, the daemon, and each live session's process (roofd's `info` pid: the shell or
/// agent the holder started; its parent is the holder).
public struct ResourceTargets: Equatable, Sendable {
    public struct Session: Equatable, Sendable {
        public var runtimeId: String
        public var pid: Int32?
        public var memoryWarning: Bool
        public init(runtimeId: String, pid: Int32?, memoryWarning: Bool = false) {
            self.runtimeId = runtimeId; self.pid = pid; self.memoryWarning = memoryWarning
        }
    }
    public var appPid: Int32
    public var daemonPid: Int32?
    public var sessions: [Session]
    public init(appPid: Int32 = getpid(), daemonPid: Int32? = nil, sessions: [Session] = []) {
        self.appPid = appPid; self.daemonPid = daemonPid; self.sessions = sessions
    }
}

/// Reads One Roof's process trees once per tick. Not thread safe: one serial queue owns it.
public final class ResourceSampler {
    let source: ResourceSource
    private var cpu = CPUMeter()
    private var names: [Int32: String] = [:]
    private var starts: [Int32: Date] = [:]
    private var holderLimits: [Int32: Headroom] = [:]
    private var daemonLimits: (pid: Int32, h: Headroom)?

    /// Agent CLIs by process name, for the "agent" role (claude runs as node or claude, codex as codex or node …).
    static let agentNames: Set<String> = ["claude", "codex", "kimi", "agy", "gemini", "node", "aider", "opencode", "goose", "cursor-agent"]

    public init(source: ResourceSource = LiveResourceSource()) { self.source = source }

    static func isRoofd(_ name: String) -> Bool { name.hasPrefix("roofd") }

    public func sample(_ targets: ResourceTargets, at date: Date = Date()) -> ResourceSnapshot {
        let t0 = source.nowNanos()
        let table = ProcTable(source.processes())
        let now = source.nowNanos()

        // Holders: the parent of each session's process, when it is a roofd. A process that is itself a roofd (an
        // older daemon reporting the holder's own pid) counts as the holder.
        var holderOf: [String: Int32] = [:]
        for s in targets.sessions {
            guard let pid = s.pid, let e = table.byPid[pid] else { continue }
            if Self.isRoofd(e.name) { holderOf[s.runtimeId] = pid; continue }
            if let parent = table.byPid[e.ppid], Self.isRoofd(parent.name) { holderOf[s.runtimeId] = e.ppid }
        }
        // The daemon: what it said in `hello`, else the parent most holders share.
        var daemonPid = targets.daemonPid.flatMap { p in table.byPid[p].map { Self.isRoofd($0.name) } == true ? p : nil }
        if daemonPid == nil {
            let parents = holderOf.values.compactMap { table.byPid[$0]?.ppid }.filter { p in table.byPid[p].map { Self.isRoofd($0.name) } ?? false }
            daemonPid = Dictionary(parents.map { ($0, 1) }, uniquingKeysWith: +).max { $0.value < $1.value }?.key
        }
        let claimed = Set(holderOf.values)
        // Other roofd children of the daemon (not `attach` clients, which belong to the app): unclaimed holders.
        let unclaimedHolders = daemonPid.map { d in (table.children[d] ?? []).filter { p in
            !claimed.contains(p) && (table.byPid[p].map { Self.isRoofd($0.name) } ?? false)
        } } ?? []
        let allHolders = claimed.union(unclaimedHolders)

        var seen = Set<Int32>()
        func usage(_ pid: Int32, depth: Int, role: ProcRole) -> ProcUsage? {
            guard let e = table.byPid[pid], let u = source.usage(pid) else { return nil }
            seen.insert(pid)
            let name = names[pid] ?? source.name(pid) ?? e.name
            names[pid] = name
            var started: Date?
            if [.app, .daemon, .holder].contains(role) {
                started = starts[pid] ?? source.startTime(pid)
                starts[pid] = started
            }
            return ProcUsage(pid: pid, ppid: e.ppid, name: name, depth: depth, role: role, footprint: u.footprint,
                             cpu: cpu.percent(pid: pid, cpuNanos: u.cpuNanos, at: now), started: started)
        }
        func group(_ root: Int32, rootRole: ProcRole, excluding: Set<Int32>) -> [ProcUsage] {
            table.tree(root, excluding: excluding).compactMap { node in
                let role: ProcRole = node.pid == root ? rootRole
                    : Self.agentNames.contains((table.byPid[node.pid]?.name ?? "").lowercased()) ? .agent : .child
                return usage(node.pid, depth: node.depth, role: role)
            }
        }
        func limits(_ holder: Int32) -> Headroom {
            if let h = holderLimits[holder] { return h }
            let h = Headroom.holder(env: source.environment(holder))
            holderLimits[holder] = h
            return h
        }

        var snap = ResourceSnapshot(at: date)
        snap.app = group(targets.appPid, rootRole: .app, excluding: allHolders.union(daemonPid.map { [$0] } ?? []))
        if let d = daemonPid {
            snap.daemon = usage(d, depth: 0, role: .daemon)
            if daemonLimits?.pid != d { daemonLimits = (d, Headroom.daemon(env: source.environment(d))) }
            snap.daemonHeadroom = daemonLimits?.h ?? .daemonDefault
        }
        for s in targets.sessions {
            if let h = holderOf[s.runtimeId] {
                snap.sessions[s.runtimeId] = SessionUsage(runtimeId: s.runtimeId, holderPid: h,
                                                          procs: group(h, rootRole: .holder, excluding: allHolders.subtracting([h])),
                                                          headroom: limits(h), memoryWarning: s.memoryWarning)
            } else if let pid = s.pid, table.byPid[pid] != nil {
                // The holder could not be told apart (not a roofd parent): count the session's own tree.
                snap.sessions[s.runtimeId] = SessionUsage(runtimeId: s.runtimeId, holderPid: nil,
                                                          procs: group(pid, rootRole: .child, excluding: allHolders),
                                                          memoryWarning: s.memoryWarning)
            }
        }
        snap.unclaimed = unclaimedHolders.map { h in
            SessionUsage(runtimeId: "pid \(h)", holderPid: h, procs: group(h, rootRole: .holder, excluding: allHolders.subtracting([h])),
                         headroom: limits(h))
        }
        snap.mac = source.mac()
        cpu.keep(seen)
        names = names.filter { seen.contains($0.key) }
        starts = starts.filter { seen.contains($0.key) }
        holderLimits = holderLimits.filter { seen.contains($0.key) }
        snap.costNanos = source.nowNanos() &- t0
        return snap
    }
}

// MARK: History

/// A fixed-size ring: the newest `capacity` values, oldest first.
public struct RingBuffer<T: Sendable>: Sendable {
    public let capacity: Int
    private var storage: [T] = []
    private var head = 0
    public init(capacity: Int) { self.capacity = max(1, capacity) }

    public mutating func append(_ v: T) {
        if storage.count < capacity { storage.append(v); return }
        storage[head] = v
        head = (head + 1) % capacity
    }
    public var values: [T] { Array(storage[head...] + storage[..<head]) }
    public var count: Int { storage.count }
    public var last: T? { storage.isEmpty ? nil : storage[(head + storage.count - 1) % storage.count] }
}

/// One point of a sparkline.
public struct ResourcePoint: Equatable, Sendable {
    public var at: Date
    public var footprint: UInt64
    public var cpu: Double
    public init(at: Date, footprint: UInt64, cpu: Double) { self.at = at; self.footprint = footprint; self.cpu = cpu }
}

/// Ten minutes of points (200 × 3 s) for the totals and each session; a session gone for ten minutes is dropped.
public struct ResourceHistory: Sendable {
    public static let interval: TimeInterval = 3
    public static let window: TimeInterval = 600
    public static var capacity: Int { Int(window / interval) }
    public static let totalKey = "·total"

    private var series: [String: RingBuffer<ResourcePoint>] = [:]
    private var lastSeen: [String: Date] = [:]
    public init() {}

    public mutating func record(_ key: String, _ p: ResourcePoint) {
        series[key, default: RingBuffer(capacity: Self.capacity)].append(p)
        lastSeen[key] = p.at
    }

    public mutating func record(_ s: ResourceSnapshot) {
        record(Self.totalKey, ResourcePoint(at: s.at, footprint: s.footprint, cpu: s.cpu))
        for (id, u) in s.sessions { record(id, ResourcePoint(at: s.at, footprint: u.footprint, cpu: u.cpu)) }
        prune(now: s.at)
    }

    public mutating func prune(now: Date) {
        for (k, t) in lastSeen where now.timeIntervalSince(t) > Self.window {
            series[k] = nil; lastSeen[k] = nil
        }
    }

    public func points(_ key: String) -> [ResourcePoint] { series[key]?.values ?? [] }
    public var keys: Set<String> { Set(series.keys) }
}

// MARK: Grouping (the Resources view)

/// A row of the Resources view before it is drawn.
public struct ResourceRow: Equatable, Sendable, Identifiable {
    public var id: String
    public var name: String
    /// The window it sits in; nil = no open window ("Other").
    public var windowId: String?
    public var usage: SessionUsage
    public init(id: String, name: String, windowId: String?, usage: SessionUsage) {
        self.id = id; self.name = name; self.windowId = windowId; self.usage = usage
    }
}

public struct ResourceWindowGroup: Equatable, Sendable, Identifiable {
    public var id: String
    public var name: String
    public var rows: [ResourceRow]
    public var footprint: UInt64 { rows.reduce(0) { $0 + $1.usage.footprint } }
    public var cpu: Double { rows.reduce(0) { $0 + $1.usage.cpu } }
}

public enum ResourceSort: String, CaseIterable, Sendable { case heaviest, name }

public enum ResourceBoard {
    public static let otherId = "·other"

    /// Rows by window, in window order, then "Other". Heaviest first (memory, then CPU, then name) or by name.
    public static func group(_ rows: [ResourceRow], windows: [(id: String, name: String)], sort: ResourceSort) -> [ResourceWindowGroup] {
        func ordered(_ r: [ResourceRow]) -> [ResourceRow] {
            r.sorted { a, b in
                if sort == .heaviest {
                    if a.usage.footprint != b.usage.footprint { return a.usage.footprint > b.usage.footprint }
                    if a.usage.cpu != b.usage.cpu { return a.usage.cpu > b.usage.cpu }
                }
                let c = a.name.localizedStandardCompare(b.name)
                return c == .orderedSame ? a.id < b.id : c == .orderedAscending
            }
        }
        let open = Set(windows.map(\.id))
        var out = windows.map { w in ResourceWindowGroup(id: w.id, name: w.name, rows: ordered(rows.filter { $0.windowId == w.id })) }
            .filter { !$0.rows.isEmpty }
        let other = rows.filter { $0.windowId.map { !open.contains($0) } ?? true }
        if !other.isEmpty { out.append(ResourceWindowGroup(id: otherId, name: "Other", rows: ordered(other))) }
        return out
    }

    /// Running sessions as rows. Each board row claims the roofd session it owns (`resourceKey`) and sits in the
    /// window `window` gives it (nil = Other); roofd sessions no row claims go to Other under `title` or their id.
    public static func rows(items: [BoardItem], sessions: [RuntimeID: SessionUsage],
                            window: (BoardItem) -> String?, title: (RuntimeID) -> String?) -> [ResourceRow] {
        var out: [ResourceRow] = []
        var claimed = Set<RuntimeID>()
        for i in items {
            guard let rid = i.resourceKey, !claimed.contains(rid), let u = sessions[rid] else { continue }
            claimed.insert(rid)
            out.append(ResourceRow(id: i.id, name: i.session.name, windowId: window(i), usage: u))
        }
        for (rid, u) in sessions where !claimed.contains(rid) {
            let t = title(rid) ?? ""
            out.append(ResourceRow(id: "runtime:" + rid, name: t.isEmpty ? rid : t, windowId: nil, usage: u))
        }
        return out
    }
}

extension BoardItem {
    /// The roofd session this row owns for Resources: its live agent or, once the agent has exited while its shell
    /// lives on (LAB-517), the session's own runtime id. That shell still holds memory, and it is still this session.
    public var resourceKey: RuntimeID? { liveAgent ?? session.runtimeId }
}

// MARK: Formatting

public enum ResourceFormat {
    /// "312 MB", "1.4 GB" (binary units, like Activity Monitor).
    public static func bytes(_ b: UInt64) -> String {
        let mb = Double(b) / 1_048_576
        if mb >= 1024 { return String(format: mb >= 10240 ? "%.0f GB" : "%.1f GB", mb / 1024) }
        if mb >= 10 { return String(format: "%.0f MB", mb) }
        return String(format: "%.1f MB", mb)
    }

    /// "4%", "0.3%", "112%"; "–" before the second sample.
    public static func cpu(_ c: Double?) -> String {
        guard let c else { return "–" }
        if c < 0.05 { return "0%" }
        if c < 10 { return String(format: "%.1f%%", c) }
        return String(format: "%.0f%%", c)
    }

    /// "3d 4h", "2h 5m", "12m", "40s".
    public static func uptime(_ s: TimeInterval) -> String {
        let n = max(0, Int(s))
        if n >= 86400 { return "\(n / 86400)d \(n % 86400 / 3600)h" }
        if n >= 3600 { return "\(n / 3600)h \(n % 3600 / 60)m" }
        if n >= 60 { return "\(n / 60)m" }
        return "\(n)s"
    }
}

// MARK: Darwin

/// The real readings: `KERN_PROC_ALL`, `proc_pid_rusage`, `host_statistics64`, `vm.swapusage`,
/// `kern.memorystatus_vm_pressure_level`. All read-only; a process that cannot be read is skipped.
public final class LiveResourceSource: ResourceSource {
    private let timebase: (numer: UInt64, denom: UInt64) = {
        var tb = mach_timebase_info_data_t()
        mach_timebase_info(&tb)
        return (UInt64(max(tb.numer, 1)), UInt64(max(tb.denom, 1)))
    }()
    private var buffer: [kinfo_proc] = []

    public init() {}

    public func processes() -> [ProcEntry] {
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_ALL, 0]
        for _ in 0..<3 {
            var size = 0
            guard sysctl(&mib, 4, nil, &size, nil, 0) == 0, size > 0 else { return [] }
            let n = size / MemoryLayout<kinfo_proc>.stride + 32
            if buffer.count < n { buffer = [kinfo_proc](repeating: kinfo_proc(), count: n) }
            size = buffer.count * MemoryLayout<kinfo_proc>.stride
            let rc = buffer.withUnsafeMutableBufferPointer { sysctl(&mib, 4, $0.baseAddress, &size, nil, 0) }
            if rc != 0 { if errno == ENOMEM { buffer = []; continue }; return [] }
            let count = size / MemoryLayout<kinfo_proc>.stride
            var out: [ProcEntry] = []
            out.reserveCapacity(count)
            for i in 0..<count {
                var p = buffer[i]
                let name = withUnsafePointer(to: &p.kp_proc.p_comm) {
                    $0.withMemoryRebound(to: CChar.self, capacity: Int(MAXCOMLEN) + 1) { String(cString: $0) }
                }
                out.append(ProcEntry(pid: p.kp_proc.p_pid, ppid: p.kp_eproc.e_ppid, name: name))
            }
            return out
        }
        return []
    }

    public func usage(_ pid: Int32) -> RawUsage? {
        var info = rusage_info_v4()
        let rc = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { proc_pid_rusage(pid, RUSAGE_INFO_V4, $0) }
        }
        guard rc == 0 else { return nil }
        let ticks = info.ri_user_time &+ info.ri_system_time
        return RawUsage(footprint: info.ri_phys_footprint, cpuNanos: ticks / timebase.denom * timebase.numer + ticks % timebase.denom * timebase.numer / timebase.denom)
    }

    public func environment(_ pid: Int32) -> [String: String]? {
        guard let a = ProcessProbe.args(pid: pid), !a.env.isEmpty else { return nil }
        return a.env
    }

    public func name(_ pid: Int32) -> String? {
        var buf = [CChar](repeating: 0, count: 256)
        guard proc_name(pid, &buf, UInt32(buf.count)) > 0 else { return nil }
        return String(cString: buf)
    }

    public func mac() -> MacMemory? {
        func sysctlValue<T>(_ name: String, _ v: inout T) -> Bool {
            var size = MemoryLayout<T>.size
            return sysctlbyname(name, &v, &size, nil, 0) == 0
        }
        var total: UInt64 = 0
        guard sysctlValue("hw.memsize", &total) else { return nil }
        var page: Int64 = 0
        if !sysctlValue("hw.pagesize", &page) || page <= 0 { page = 16384 }
        var stats = vm_statistics64_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        let kr = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count) }
        }
        var used: UInt64 = 0
        if kr == KERN_SUCCESS {
            let app = UInt64(stats.internal_page_count) &- min(UInt64(stats.purgeable_count), UInt64(stats.internal_page_count))
            used = (app + UInt64(stats.wire_count) + UInt64(stats.compressor_page_count)) * UInt64(page)
        }
        var swap = xsw_usage()
        let swapUsed: UInt64 = sysctlValue("vm.swapusage", &swap) ? swap.xsu_used : 0
        var level: Int32 = 1
        _ = sysctlValue("kern.memorystatus_vm_pressure_level", &level)
        return MacMemory(total: total, used: min(used, total), swapUsed: swapUsed, pressure: MacMemory.pressure(level: Int(level)))
    }

    public func nowNanos() -> UInt64 { DispatchTime.now().uptimeNanoseconds }

    public func startTime(_ pid: Int32) -> Date? { Self.startTime(pid) }

    /// When a process started.
    public static func startTime(_ pid: Int32) -> Date? {
        var info = proc_bsdinfo()
        let n = proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, Int32(MemoryLayout<proc_bsdinfo>.size))
        guard n == Int32(MemoryLayout<proc_bsdinfo>.size) else { return nil }
        return Date(timeIntervalSince1970: TimeInterval(info.pbi_start_tvsec) + TimeInterval(info.pbi_start_tvusec) / 1e6)
    }
}
