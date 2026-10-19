import Foundation
import OneRoofCore

/// Where One Roof keeps its preferences. Normally the app's own defaults domain; with `--fresh-profile` (or
/// `ONEROOF_FRESH_PROFILE=1`) a separate, emptied suite and a throw-away session store, so the app starts as it would
/// on a new Mac (first-run setup every time, no legacy migration).
enum Prefs {
    static let freshSuite = "io.github.gaurav8936.oneroof.fresh"

    static let freshProfile: Bool = CommandLine.arguments.contains("--fresh-profile")
        || ProcessInfo.processInfo.environment["ONEROOF_FRESH_PROFILE"] == "1"

    static let defaults: UserDefaults = {
        guard freshProfile, let d = UserDefaults(suiteName: freshSuite) else { return .standard }
        d.removePersistentDomain(forName: freshSuite)
        return d
    }()

    /// The session store for a fresh profile (a new file each launch), unless ONEROOF_STORE names one.
    static var freshStorePath: String? {
        guard freshProfile, ProcessInfo.processInfo.environment["ONEROOF_STORE"] == nil else { return nil }
        let dir = NSTemporaryDirectory() + "oneroof-fresh-" + UUID().uuidString.prefix(8)
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        return dir + "/sessions.sqlite"
    }

    /// The saved settings, after a one-time copy from the legacy domain. Self-tests read the copy without saving it.
    static func loadSettings(migrate: Bool = true) -> AppSettings {
        let d = defaults
        // Only the bundled app (which has its own defaults domain) migrates; a bare `swift build` binary does not.
        if migrate, !freshProfile, Bundle.main.bundleIdentifier != nil {
            if SelfTest.isActive {
                if d.data(forKey: "settings") == nil,
                   let v = LegacyMigration.migratedValues(target: d, legacy: LegacyMigration.legacyValues()),
                   let data = v["settings"] as? Data, let st = try? JSONDecoder().decode(AppSettings.self, from: data) {
                    return st
                }
            } else {
                LegacyMigration.run(target: d)
            }
        }
        if let data = d.data(forKey: "settings"), let st = try? JSONDecoder().decode(AppSettings.self, from: data) { return st }
        return AppSettings()
    }
}
