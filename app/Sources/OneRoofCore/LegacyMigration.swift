import Foundation

/// One-time move from the original preferences domain (`com.gaurav8936.oneroof`, the author's first builds) to
/// `io.github.gaurav8936.oneroof`. This is the ONLY file allowed to name the old domain and the old Linear key file.
/// It names no workspace folders (LAB-2140: they were compiled into the public download); the Learn folders and the
/// on-device model are found on disk or set in Settings. Nothing here runs for anyone else (their old domain is
/// empty), and the old domain is only read, never written.
public enum LegacyMigration {
    public static let legacyDomain = "com.gaurav8936.oneroof"
    public static let flagKey = "migratedFromLegacy"
    public static let settingsKey = "settings"

    /// The Linear key file older builds read (still honoured, after LINEAR_API_KEY and ~/.config/oneroof/).
    public static var linearKeyPath: String { NSHomeDirectory() + "/.config/linear-commit-hook/api-key" }

    /// The old domain's keys, read without touching it.
    public static func legacyValues(domain: String = LegacyMigration.legacyDomain) -> [String: Any]? {
        UserDefaults().persistentDomain(forName: domain)
    }

    /// The legacy settings JSON with the values older builds assumed filled in. Pure (file checks injected).
    public static func upgradedSettings(_ data: Data?, home: String = NSHomeDirectory(),
                                        exists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }) -> Data? {
        var s: [String: Any] = data.flatMap { (try? JSONSerialization.jsonObject(with: $0)) as? [String: Any] } ?? [:]
        let projects = home + "/Projects"
        if (s["projectsPath"] as? String ?? "").isEmpty { s["projectsPath"] = projects }
        s["setupDone"] = true
        return try? JSONSerialization.data(withJSONObject: s, options: [.sortedKeys])
    }

    /// Every legacy key, with `settings` upgraded, for a target that has no settings yet. Nil = nothing to migrate.
    public static func migratedValues(target: UserDefaults, legacy: [String: Any]?, home: String = NSHomeDirectory(),
                                      exists: @escaping (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }) -> [String: Any]? {
        guard target.object(forKey: settingsKey) == nil, let legacy, legacy[settingsKey] != nil else { return nil }
        var out = legacy
        let old: Data? = (legacy[settingsKey] as? Data) ?? (legacy[settingsKey] as? String).map { Data($0.utf8) }
        if let up = upgradedSettings(old, home: home, exists: exists) { out[settingsKey] = up }
        return out
    }

    /// Copy the legacy domain into `target` once (when `target` has no settings and the old domain has some), then set
    /// `migratedFromLegacy`. Returns true when it copied.
    @discardableResult
    public static func run(target: UserDefaults, legacy: [String: Any]? = LegacyMigration.legacyValues(),
                           home: String = NSHomeDirectory(),
                           exists: @escaping (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }) -> Bool {
        guard let values = migratedValues(target: target, legacy: legacy, home: home, exists: exists) else { return false }
        for (k, v) in values { target.set(v, forKey: k) }
        target.set(true, forKey: flagKey)
        return true
    }
}
