import Darwin
import Foundation

// LAB-544: Resources covers the whole Mac, not only One Roof. On 10-22 the Mac was at 14 GB of 16 with 18 GB of swap;
// the biggest single item was One Roof's local model (llama-server, 8.4 GB) left running by a force-quit, which the
// page could not show because it no longer belonged to the app; Chrome's ~6 GB showed as one lump. This groups every
// readable process under the app responsible for it (as Activity Monitor does), names what each Chrome / Electron
// helper is (tab or site, extension, GPU, network …), flags One Roof's leftovers, and says which rows may be quit or
// ended from the page. Pure here; the Darwin reads sit behind `ResourceSource`.

/// One process on the Mac with what it costs now.
public struct MacProc: Equatable, Sendable, Identifiable {
    public var pid: Int32
    public var ppid: Int32
    public var name: String
    public var path: String
    /// What a helper is ("Tab or site", "Extension", "GPU" …), or a One Roof role ("Local model").
    public var kind: String?
    public var footprint: UInt64
    public var cpu: Double?
    /// From the page: may be ended (SIGTERM, then force).
    public var endable: Bool
    public var id: Int32 { pid }
    public init(pid: Int32, ppid: Int32, name: String, path: String, kind: String? = nil, footprint: UInt64, cpu: Double? = nil,
                endable: Bool = false) {
        self.pid = pid; self.ppid = ppid; self.name = name; self.path = path; self.kind = kind
        self.footprint = footprint; self.cpu = cpu; self.endable = endable
    }
}

/// Every process one app is responsible for (its own, its helpers, XPC services it started).
public struct MacAppGroup: Equatable, Sendable, Identifiable {
    /// The app bundle's path, else "name:<process name>".
    public var id: String
    public var name: String
    /// The .app the group is named after, for its icon.
    public var bundlePath: String?
    /// The app's own process (Quit asks it to quit, like the Dock's Quit).
    public var mainPid: Int32?
    public var procs: [MacProc]
    public var isOneRoof: Bool
    /// One Roof processes the running app did not start (a local model left by a force-quit, a stray roofd).
    public var leftovers: [MacProc]
    /// The page may quit this app (not One Roof itself, not the system).
    public var quittable: Bool
    public var footprint: UInt64 { procs.reduce(0) { $0 + $1.footprint } }
    public var cpu: Double { procs.reduce(0) { $0 + ($1.cpu ?? 0) } }
    public init(id: String, name: String, bundlePath: String? = nil, mainPid: Int32? = nil, procs: [MacProc], isOneRoof: Bool = false,
                leftovers: [MacProc] = [], quittable: Bool = false) {
        self.id = id; self.name = name; self.bundlePath = bundlePath; self.mainPid = mainPid; self.procs = procs
        self.isOneRoof = isOneRoof; self.leftovers = leftovers; self.quittable = quittable
    }
}

/// One tick of the whole Mac.
public struct MacBreakdown: Equatable, Sendable {
    public var at: Date
    /// Heaviest first.
    public var groups: [MacAppGroup]
    /// Processes the kernel would not let us read (other users', the system's).
    public var unreadable: Int
    public var mac: MacMemory?
    public var costNanos: UInt64
    public init(at: Date = Date(), groups: [MacAppGroup] = [], unreadable: Int = 0, mac: MacMemory? = nil, costNanos: UInt64 = 0) {
        self.at = at; self.groups = groups; self.unreadable = unreadable; self.mac = mac; self.costNanos = costNanos
    }
    public var counted: UInt64 { groups.reduce(0) { $0 + $1.footprint } }
    /// Memory in use that no readable process accounts for: the system (kernel, WindowServer …), other users, caches.
    public var uncounted: UInt64 { mac.map { $0.used > counted ? $0.used - counted : 0 } ?? 0 }
    public var processCount: Int { groups.reduce(0) { $0 + $1.procs.count } }
    public var leftovers: [MacProc] { groups.flatMap(\.leftovers) }
}

public enum MacResources {
    /// The outermost `.app` in a path: "/Applications/Google Chrome.app/Contents/Frameworks/…/Helper.app/…" →
    /// "/Applications/Google Chrome.app". nil outside any bundle.
    public static func appBundle(_ path: String) -> String? {
        guard let r = path.range(of: ".app/") ?? (path.hasSuffix(".app") ? path.range(of: ".app", options: .backwards) : nil) else { return nil }
        return String(path[..<r.upperBound]).replacingOccurrences(of: ".app/", with: ".app")
    }

    /// "/Applications/Google Chrome.app" → "Google Chrome".
    public static func appName(_ bundle: String) -> String {
        ((bundle as NSString).lastPathComponent as NSString).deletingPathExtension
    }

    /// What a Chromium / Electron helper is, from its command line (Chrome, Slack, Notion, Linear, Codex … all use it).
    public static func helperKind(_ argv: [String]) -> String? {
        func has(_ s: String) -> Bool { argv.contains { $0 == s || $0.hasPrefix(s + "=") } }
        func value(_ k: String) -> String? { argv.lazy.compactMap { $0.hasPrefix(k + "=") ? String($0.dropFirst(k.count + 1)) : nil }.first }
        guard let type = value("--type") else { return nil }
        switch type {
        case "renderer":
            if has("--extension-process") { return "Extension" }
            if has("--top-chrome-webui") || has("--webui-host") { return "Browser window (tabs, toolbar)" }
            return "Tab or site"
        case "gpu-process": return "GPU"
        case "utility":
            let sub = value("--utility-sub-type") ?? ""
            if sub.contains("NetworkService") { return "Network" }
            if sub.contains("StorageService") { return "Storage" }
            if sub.contains("AudioService") { return "Audio" }
            if sub.contains("video_capture") { return "Camera" }
            if sub.contains("unzip") || sub.contains("Unzip") { return "Unzip" }
            if sub.contains("Spellcheck") || sub.contains("spellcheck") { return "Spellcheck" }
            if sub.contains("on_device_model") { return "On-device AI" }
            return "Utility"
        case "zygote": return "Launcher"
        case "crashpad-handler": return "Crash reporter"
        default: return type.prefix(1).uppercased() + type.dropFirst()
        }
    }

    /// One Roof's local model (`LocalModel`): llama-server on One Roof's port.
    public static func isLocalModel(name: String, argv: [String]) -> Bool {
        guard name.hasPrefix("llama-server") || (argv.first.map { ($0 as NSString).lastPathComponent == "llama-server" } ?? false) else { return false }
        guard let i = argv.firstIndex(of: "--port"), i + 1 < argv.count else { return false }
        return argv[i + 1] == String(LocalModel.port)
    }

    /// The model a llama-server runs, from its `-m` / `--model` argument; nil without one.
    public static func modelName(_ argv: [String]) -> String? {
        guard let i = argv.firstIndex(where: { $0 == "-m" || $0 == "--model" }), i + 1 < argv.count else { return nil }
        return LocalModel.name(forPath: argv[i + 1])
    }

    /// Paths whose processes the page never offers to end: the system's own.
    static let systemPrefixes = ["/System/", "/usr/libexec/", "/usr/sbin/", "/sbin/", "/Library/Apple/", "/usr/bin/login"]
    /// Apps that keep the Mac usable; quitting them from here is never offered.
    static let keepApps: Set<String> = ["Finder", "Dock", "SystemUIServer", "ControlCenter", "NotificationCenter", "loginwindow",
                                        "WindowManager", "Spotlight", "WindowServer"]

    public static func isSystem(_ path: String) -> Bool { path.isEmpty || systemPrefixes.contains { path.hasPrefix($0) } }
}

/// Reads the whole Mac once per tick. Not thread safe: one serial queue owns it.
public final class MacSampler {
    let source: ResourceSource
    private var cpu = CPUMeter()
    /// Per pid, read once: path, argv-derived kind, the responsible pid, whether it is One Roof's local model.
    private struct Static {
        var path: String; var name: String; var kind: String?; var responsible: Int32; var localModel: Bool
        /// The local model's name, from its `-m` argument (Qwen3 1.7B, Arch-Router, …).
        var modelName: String?
    }
    private var statics: [Int32: Static] = [:]

    public init(source: ResourceSource = LiveResourceSource()) { self.source = source }

    /// `appPid` = this One Roof; `oneRoofPids` = every process the running One Roof owns (its tree, the daemon, holders
    /// and their sessions); `regularApps` = pids of apps in the Dock (they may be quit).
    public func sample(appPid: Int32 = getpid(), oneRoofPids: Set<Int32> = [], regularApps: Set<Int32> = [], at date: Date = Date()) -> MacBreakdown {
        let t0 = source.nowNanos()
        let table = ProcTable(source.processes())
        let now = source.nowNanos()
        let appBundle = statics[appPid]?.path ?? source.path(appPid) ?? ""
        let oneRoofBundle = MacResources.appBundle(appBundle)

        var byGroup: [String: MacAppGroup] = [:]
        var unreadable = 0
        var seen = Set<Int32>()
        for (pid, e) in table.byPid {
            guard let u = source.usage(pid) else { unreadable += 1; continue }
            seen.insert(pid)
            let st = statics[pid] ?? {
                let path = source.path(pid) ?? ""
                let name = e.name
                // Command lines only where they say something: helpers and llama-server.
                let wantsArgv = name.contains("Helper") || name.hasPrefix("llama-server") || path.contains("Helper")
                let argv = wantsArgv ? (source.argv(pid) ?? []) : []
                let s = Static(path: path, name: source.name(pid) ?? name, kind: MacResources.helperKind(argv), responsible: source.responsible(pid) ?? pid,
                               localModel: MacResources.isLocalModel(name: name, argv: argv), modelName: MacResources.modelName(argv))
                statics[pid] = s
                return s
            }()
            let name = st.name

            // The group: the app bundle of the responsible process, else of the process, else of an ancestor; else
            // the process name. One Roof's local model always goes to One Roof.
            var bundle: String?
            if st.localModel { bundle = oneRoofBundle ?? "/Applications/One Roof.app" }
            if bundle == nil, st.responsible != pid, let rp = statics[st.responsible]?.path ?? source.path(st.responsible) {
                bundle = MacResources.appBundle(rp)
            }
            if bundle == nil { bundle = MacResources.appBundle(st.path) }
            if bundle == nil {
                var p = e.ppid, hops = 0
                while p > 1, hops < 20, let pe = table.byPid[p] {
                    if let b = MacResources.appBundle(statics[p]?.path ?? source.path(p) ?? "") { bundle = b; break }
                    p = pe.ppid; hops += 1
                }
            }
            let key = bundle ?? "name:" + name
            // Any One Roof bundle counts (an older copy such as "One Roof-0.4.6.app" still running its roofd).
            let isOneRoof = bundle != nil && bundle == oneRoofBundle || (bundle.map { MacResources.appName($0).hasPrefix("One Roof") } ?? false)
                || st.localModel || ResourceSampler.isRoofd(e.name)
            let groupKey = isOneRoof ? "·oneroof" : key

            // One Roof's own but not this app's: a local model or roofd left by an earlier run.
            let leftover = isOneRoof && !oneRoofPids.contains(pid) && pid != appPid
                && (st.localModel || ResourceSampler.isRoofd(e.name))
            let kind: String? = st.localModel ? "Local model (\(st.modelName ?? LocalModel.displayName))" + (leftover ? ", left over from an earlier run" : "")
                : ResourceSampler.isRoofd(e.name) && leftover ? "roofd not used by this One Roof" : st.kind
            let endable = pid != appPid && pid > 1 && !MacResources.isSystem(st.path)
                && (!isOneRoof || leftover || st.localModel)
            let proc = MacProc(pid: pid, ppid: e.ppid, name: name, path: st.path, kind: kind, footprint: u.footprint,
                               cpu: cpu.percent(pid: pid, cpuNanos: u.cpuNanos, at: now), endable: endable)

            var g = byGroup[groupKey] ?? MacAppGroup(id: groupKey, name: isOneRoof ? "One Roof" : bundle.map(MacResources.appName) ?? name,
                                                     bundlePath: isOneRoof ? oneRoofBundle : bundle, procs: [], isOneRoof: isOneRoof)
            g.procs.append(proc)
            if leftover { g.leftovers.append(proc) }
            if isOneRoof { g.mainPid = appPid }
            else if regularApps.contains(pid), g.mainPid == nil || bundle.map({ st.path.hasPrefix($0 + "/Contents/MacOS/") }) == true {
                g.mainPid = pid
            }
            byGroup[groupKey] = g
        }
        let groups = byGroup.values.map { g -> MacAppGroup in
            var g = g
            g.procs.sort { ($0.footprint, $1.pid) > ($1.footprint, $0.pid) }
            g.leftovers.sort { $0.footprint > $1.footprint }
            g.quittable = !g.isOneRoof && g.mainPid != nil && !MacResources.keepApps.contains(g.name)
                && !(g.bundlePath.map(MacResources.isSystem) ?? true)
            return g
        }.sorted { a, b in a.footprint != b.footprint ? a.footprint > b.footprint : a.name < b.name }

        cpu.keep(seen)
        statics = statics.filter { seen.contains($0.key) }
        return MacBreakdown(at: date, groups: groups, unreadable: unreadable, mac: source.mac(), costNanos: source.nowNanos() &- t0)
    }
}
