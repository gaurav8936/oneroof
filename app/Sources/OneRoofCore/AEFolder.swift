import Foundation

/// Where One Roof reads its agentic-engineering material (skills, routing rules, roles, course) from. Nothing is
/// hard-coded: `ONEROOF_AE_PATH` wins, then the folder chosen in Settings, then the copy bundled with the app
/// (`agentic_engineering/` in the app's Resources, or in the source checkout when run from a build folder).
public enum AEFolder {
    public enum Source: String, Sendable { case environment, settings, bundled, missing }

    public struct Resolved: Equatable, Sendable {
        public var path: String
        public var source: Source
        /// "your folder (Settings)", "bundled copy", …, for the Settings and Foundations views.
        public var label: String {
            switch source {
            case .environment: return "ONEROOF_AE_PATH"
            case .settings: return "your folder (Settings)"
            case .bundled: return "bundled copy"
            case .missing: return "not found"
            }
        }
    }

    /// The bundled package: the app's Resources, else the source checkout this file was built from.
    public static var bundled: String? {
        var candidates: [String] = []
        if let r = Bundle.main.resourcePath { candidates.append(r + "/agentic_engineering") }
        // <repo>/agentic_engineering, when built from a source checkout (empty in a release build).
        let repo = AppResources.sourceCheckout
        if !repo.isEmpty { candidates.append(repo + "/agentic_engineering") }
        return candidates.first { isPackage($0) }
    }

    /// A folder counts if it has a skills/ tree.
    public static func isPackage(_ path: String) -> Bool {
        var dir: ObjCBool = false
        return FileManager.default.fileExists(atPath: path + "/skills", isDirectory: &dir) && dir.boolValue
    }

    /// `setting` is the Settings value; "" means "use the bundled copy".
    public static func resolve(setting: String, environment: [String: String] = ProcessInfo.processInfo.environment,
                               bundled: String? = AEFolder.bundled) -> Resolved {
        if let e = environment["ONEROOF_AE_PATH"], !e.isEmpty, isPackage(expand(e)) { return Resolved(path: expand(e), source: .environment) }
        if !setting.isEmpty, isPackage(expand(setting)) { return Resolved(path: expand(setting), source: .settings) }
        if let b = bundled { return Resolved(path: b, source: .bundled) }
        return Resolved(path: setting, source: .missing)
    }

    /// The folder holding routing.json and roles.json: `skills/<any group>/agent-routing` (the bundled layout) or
    /// `.../harness-routing` (older skill libraries).
    public static func routingDir(_ ae: String) -> String? {
        let fm = FileManager.default
        for name in ["agent-routing", "harness-routing"] {
            for group in ((try? fm.contentsOfDirectory(atPath: ae + "/skills")) ?? []).sorted() {
                let d = ae + "/skills/" + group + "/" + name
                if fm.fileExists(atPath: d + "/routing.json") || fm.fileExists(atPath: d + "/roles.json") { return d }
            }
        }
        return nil
    }

    static func expand(_ p: String) -> String { (p as NSString).expandingTildeInPath }
}

public extension AppSettings {
    /// The agentic-engineering folder actually in use (see `AEFolder`).
    var agenticEngineering: AEFolder.Resolved { AEFolder.resolve(setting: agenticEngineeringPath) }
}
