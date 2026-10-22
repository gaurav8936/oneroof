import Foundation

/// LAB-516: what launchd says about roofd's job (`launchctl print gui/<uid>/<label>`). After switching from an ad-hoc
/// dev build to a Developer ID release, SMAppService reported the item as enabled while launchd kept the old job: it
/// "needs LWCR update" and exits 78 (EX_CONFIG) on every respawn, or (after a bootout) has no job at all. The app trusted
/// the enabled flag and never repaired it.
public struct LaunchdJob: Equatable, Sendable {
    public var state: String?
    public var lastExit: Int?
    public var runs: Int?
    public var needsLWCR: Bool

    /// Parse `launchctl print` output; nil when launchd has no such job.
    public static func parse(_ text: String) -> LaunchdJob? {
        guard !text.isEmpty, !text.contains("Could not find service") else { return nil }
        func value(_ key: String) -> String? {
            for line in text.split(separator: "\n") {
                let t = line.trimmingCharacters(in: .whitespaces)
                if t.hasPrefix(key + " = ") { return String(t.dropFirst(key.count + 3)) }
            }
            return nil
        }
        let exit = value("last exit code").flatMap { v -> Int? in
            if v.hasPrefix("(never") { return nil }
            return Int(v.split(separator: ":").first.map { $0.trimmingCharacters(in: .whitespaces) } ?? "")
        }
        return LaunchdJob(state: value("state"), lastExit: exit, runs: value("runs").flatMap { Int($0) },
                          needsLWCR: text.localizedCaseInsensitiveContains("needs LWCR update"))
    }

    /// Running and not stuck on a stale code identity.
    public var healthy: Bool { state == "running" && !needsLWCR }

    /// Broken for good (not just starting): repair rather than wait.
    public var stuck: Bool { needsLWCR || lastExit == 78 }
}
