import Foundation
import OneRoofCore
import ServiceManagement

/// roofd as One Roof's background item (Q13, LAB-18): the launchd agent inside the app
/// (Contents/Library/LaunchAgents/io.github.gaurav8936.oneroof.roofd.plist), registered with SMAppService, so roofd
/// starts at login, is restarted if it stops, and runs the same binary the app ships.
enum RoofdService {
    static let plistName = "io.github.gaurav8936.oneroof.roofd.plist"

    static var service: SMAppService { SMAppService.agent(plistName: plistName) }

    /// The agent ships in this bundle (a full build; `swift run` and tests have none).
    static var bundled: Bool {
        Bundle.main.bundleURL.appendingPathComponent("Contents/Library/LaunchAgents/\(plistName)").path
            .withCString { access($0, R_OK) == 0 }
    }

    /// The bundled roofd's build (modification time). macOS records the binary's code identity when the item is
    /// registered; after a rebuild with a new signature (every ad-hoc dev build) launchd refuses to start it
    /// ("needs LWCR update", exit 78) until the item is registered again.
    static var bundledBuild: Double? {
        let path = Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS/roofd").path
        return ((try? FileManager.default.attributesOfItem(atPath: path))?[.modificationDate] as? Date)?.timeIntervalSince1970.rounded()
    }
    static let registeredKey = "roofd.registeredBuild"

    /// Register on start (idempotent); register again when the bundled roofd changed since the last registration.
    /// Returns whether launchd now runs roofd.
    @discardableResult
    static func register() -> Bool {
        guard bundled, !SelfTest.isActive, !Prefs.freshProfile,
              ProcessInfo.processInfo.environment["ROOFD_DIR"] == nil else { return false }   // tests use their own
        let s = service
        let build = bundledBuild ?? 0
        if s.status == .enabled, Prefs.defaults.double(forKey: registeredKey) != build {
            // A new roofd binary: drop the old registration (launchd stops its daemon; the holders, in their own
            // sessions, keep every agent running) and register the new one.
            let done = DispatchSemaphore(value: 0)
            s.unregister { _ in done.signal() }
            _ = done.wait(timeout: .now() + 5)
        }
        if s.status != .enabled {
            do { try s.register() } catch { NSLog("One Roof: roofd background item not registered: \(error)") }
        }
        if s.status == .enabled { Prefs.defaults.set(build, forKey: registeredKey) }
        // LAB-516: "enabled" is only the Login Items record. Check what launchd actually does; a job stuck on the old
        // build's code identity (needs LWCR update, exit 78) or missing altogether is repaired once: unregister, boot
        // the job out, register again (what fixed it by hand).
        if s.status == .enabled, !repairedThisLaunch, !launchdHealthy(wait: 3) {
            repairedThisLaunch = true   // once per launch: register() runs every 30 s
            NSLog("One Roof: roofd's launchd job is \(job().map { "stuck (state \($0.state ?? "?"), last exit \($0.lastExit.map(String.init) ?? "none"))" } ?? "missing"); registering it again")
            repair()
        }
        return s.status == .enabled && launchdHealthy(wait: 0)
    }

    private static var repairedThisLaunch = false

    static var label: String { (plistName as NSString).deletingPathExtension }

    /// launchd's view of the job, nil when it has none.
    static func job() -> LaunchdJob? {
        LaunchdJob.parse(run("/bin/launchctl", ["print", "gui/\(getuid())/\(label)"]))
    }

    /// Running and not stuck, waiting up to `wait` seconds for a job that is still starting.
    static func launchdHealthy(wait: TimeInterval) -> Bool {
        let until = Date().addingTimeInterval(wait)
        while true {
            let j = job()
            if j?.healthy == true { return true }
            if j?.stuck == true || Date() >= until { return false }
            Thread.sleep(forTimeInterval: 0.3)
        }
    }

    private static func repair() {
        let s = service
        let done = DispatchSemaphore(value: 0)
        s.unregister { _ in done.signal() }
        _ = done.wait(timeout: .now() + 5)
        _ = run("/bin/launchctl", ["bootout", "gui/\(getuid())/\(label)"])
        do { try s.register() } catch { NSLog("One Roof: roofd background item not registered again: \(error)") }
        if s.status == .enabled { Prefs.defaults.set(bundledBuild ?? 0, forKey: registeredKey) }
        NSLog("One Roof: roofd launchd job after repair: \(launchdHealthy(wait: 3) ? "running" : "still not running; One Roof starts roofd itself")")
    }

    private static func run(_ exe: String, _ args: [String]) -> String {
        let p = Process(), pipe = Pipe()
        p.executableURL = URL(fileURLWithPath: exe)
        p.arguments = args
        p.standardOutput = pipe; p.standardError = pipe
        guard (try? p.run()) != nil else { return "" }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return String(data: data, encoding: .utf8) ?? ""
    }

    /// The Foundations row: is the background item allowed?
    static func check() -> CheckResult {
        guard bundled else {
            return CheckResult(id: "roofd-login", title: "roofd background item", level: .ok,
                               detail: "not part of this build: One Roof starts roofd itself")
        }
        switch service.status {
        case .enabled:
            // LAB-516: enabled in Login Items is not enough; say so when launchd is not actually running it.
            if let j = job(), j.stuck {
                return CheckResult(id: "roofd-login", title: "roofd background item", level: .warn,
                                   detail: "registered, but launchd can't start it (old build's signature); reopen One Roof to repair it")
            }
            return CheckResult(id: "roofd-login", title: "roofd background item", level: .ok, detail: "on: roofd starts at login")
        case .requiresApproval:
            return CheckResult(id: "roofd-login", title: "roofd background item", level: .warn,
                               detail: "waiting for approval in System Settings › General › Login Items; until then One Roof starts roofd itself",
                               fix: "open 'x-apple.systempreferences:com.apple.LoginItems-Settings.extension'")
        case .notRegistered, .notFound:
            return CheckResult(id: "roofd-login", title: "roofd background item", level: .warn,
                               detail: "not registered: One Roof starts roofd itself (it stops at logout); reopen One Roof to register")
        @unknown default:
            return CheckResult(id: "roofd-login", title: "roofd background item", level: .warn, detail: "unknown state")
        }
    }

    /// The background item is on (launchd runs roofd).
    static var enabled: Bool { bundled && ProcessInfo.processInfo.environment["ROOFD_DIR"] == nil && service.status == .enabled }

    static func openLoginItems() { SMAppService.openSystemSettingsLoginItems() }
}
