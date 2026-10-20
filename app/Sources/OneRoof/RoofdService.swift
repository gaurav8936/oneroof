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

    /// Register on start (idempotent). Returns whether launchd now runs roofd.
    @discardableResult
    static func register() -> Bool {
        guard bundled, ProcessInfo.processInfo.environment["ROOFD_DIR"] == nil else { return false }   // tests use their own
        let s = service
        if s.status != .enabled {
            do { try s.register() } catch { NSLog("One Roof: roofd background item not registered: \(error)") }
        }
        return s.status == .enabled
    }

    /// The Foundations row: is the background item allowed?
    static func check() -> CheckResult {
        guard bundled else {
            return CheckResult(id: "roofd-login", title: "roofd background item", level: .ok,
                               detail: "not part of this build: One Roof starts roofd itself")
        }
        switch service.status {
        case .enabled:
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

    static func openLoginItems() { SMAppService.openSystemSettingsLoginItems() }
}
