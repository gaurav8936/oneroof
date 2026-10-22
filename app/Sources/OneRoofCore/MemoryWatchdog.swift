import Darwin
import Foundation

/// roofd's memory guard (LAB-310). On 10-21 session holders grew to 2–6 GB each and macOS froze in a jetsam storm
/// (16 GB Mac). Every roofd process (daemon and holder) checks its own footprint now and then: above `warnBytes` it
/// reports once (log + `info`), above `limitBytes` it stops itself before it can take the machine down.
public struct MemoryWatchdog: Sendable {
    public enum Action: Equatable, Sendable {
        case ok
        /// Crossed the warning line (reported once until the footprint falls back under it).
        case warn
        /// At or over the limit: stop.
        case stop
    }

    public let warnBytes: UInt64
    public let limitBytes: UInt64
    public private(set) var warned = false

    public init(warnBytes: UInt64, limitBytes: UInt64) {
        self.limitBytes = max(limitBytes, 1)
        self.warnBytes = min(warnBytes, self.limitBytes)
    }

    public static let mb: UInt64 = 1 << 20
    /// A session holder: its terminal keeps 8 MB of scrollback, so even 1 GB is far past normal.
    public static let holderWarnMB: UInt64 = 1024
    public static let holderLimitMB: UInt64 = 2048
    /// The daemon holds no session state at all (a few MB normally).
    public static let daemonWarnMB: UInt64 = 512
    public static let daemonLimitMB: UInt64 = 2048

    /// Limits from the environment (`<prefix>_MEM_WARN_MB`, `<prefix>_MEM_LIMIT_MB`), else the defaults.
    public static func from(env: [String: String], prefix: String, warnMB: UInt64, limitMB: UInt64) -> MemoryWatchdog {
        let w = env["\(prefix)_MEM_WARN_MB"].flatMap { UInt64($0) } ?? warnMB
        let l = env["\(prefix)_MEM_LIMIT_MB"].flatMap { UInt64($0) } ?? limitMB
        return MemoryWatchdog(warnBytes: w * mb, limitBytes: l * mb)
    }

    public mutating func check(footprint: UInt64) -> Action {
        if footprint >= limitBytes { return .stop }
        if footprint >= warnBytes {
            if warned { return .ok }
            warned = true
            return .warn
        }
        // Hysteresis: warn again only after dropping clearly below the line.
        if footprint < warnBytes - warnBytes / 10 { warned = false }
        return .ok
    }

    /// This process's physical footprint (what Activity Monitor's Memory column and jetsam count, compressed pages
    /// included), or nil when the kernel does not answer.
    public static func footprint() -> UInt64? {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let kr = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return kr == KERN_SUCCESS ? info.phys_footprint : nil
    }

    /// One line for roofd's memory log: when, which process, how much.
    public static func logLine(at date: Date, who: String, footprint: UInt64, action: Action) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        let what = action == .stop ? "over the limit, stopping" : "over the warning line"
        return "\(f.string(from: date)) \(who) pid \(getpid()) footprint \(footprint / mb) MB: \(what)\n"
    }
}
