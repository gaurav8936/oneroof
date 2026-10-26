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
        if let seed = seedValues { for (k, v) in seed { d.set(v, forKey: k) } }
        return d
    }()

    /// Test only (1.8.1 real-profile audit): ONEROOF_PROFILE_SEED=<plist> imports an exported defaults domain into the
    /// emptied fresh suite, so a self-test starts with someone's real settings and window state. Honoured only with a
    /// fresh profile: it can never write the app's own defaults domain.
    static let seedValues: [String: Any]? = {
        guard freshProfile, let path = ProcessInfo.processInfo.environment["ONEROOF_PROFILE_SEED"],
              let data = FileManager.default.contents(atPath: path),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else { return nil }
        return SeedFilter.keep(plist)
    }()

    /// A seeded run reads the saved per-window state (step, layout, place, panes, first launch) that self-tests
    /// otherwise ignore; it still never saves anything.
    static var seeded: Bool { seedValues != nil }

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
                   let data = v["settings"] as? Data, var st = try? JSONDecoder().decode(AppSettings.self, from: data) {
                    st.ui2 = ProcessInfo.processInfo.environment["ONEROOF_SELFTEST_UI2"] == "1"   // same rule as below
                    return st
                }
            } else {
                LegacyMigration.run(target: d)
            }
        }
        var st = AppSettings()
        if let data = d.data(forKey: "settings"), let saved = try? JSONDecoder().decode(AppSettings.self, from: data) { st = saved }
        // P6: ONEROOF_SELFTEST_UI2=1 turns the v2 window setting on (the window itself arrives in 1.1.0); ONEROOF_SELFTEST_LOOK=<skyStudio|mintGarden|…> picks a look.
        let env = ProcessInfo.processInfo.environment
        // Self-tests keep testing the classic window unless they ask for the new one (ONEROOF_SELFTEST_UI2=1).
        if SelfTest.isActive { st.ui2 = env["ONEROOF_SELFTEST_UI2"] == "1" }
        if let v = env["ONEROOF_SELFTEST_LOOK"], let l = Look(rawValue: v) { st.look = l }
        return st
    }
}
