import Foundation

/// Where One Roof reads its agentic-engineering material (skills, routing rules, roles, course, the deck) from: the copy
/// bundled with the app (`agentic_engineering/` in the app's Resources, or in the source checkout when run from a build
/// folder). `ONEROOF_AE_PATH` overrides it for development. Since LAB-768 there is no folder choice in Settings.
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
        // LAB-768 (owner, 2026-10-25): One Roof ships the whole Agentic Engineering package and there is no folder choice any
        // more; `setting` is kept for old settings files and ignored. ONEROOF_AE_PATH stays as a developer override.
        if let b = bundled { return Resolved(path: b, source: .bundled) }
        return Resolved(path: setting, source: .missing)
    }

    /// LAB-768 · the Agentic Engineering deck (narrated cards, track pages, catalog, every skill) inside a package:
    /// `<ae>/deck` in the bundled copy; the folder itself when ONEROOF_AE_PATH points straight at the deck's own repository.
    public static func deckRoot(_ ae: String) -> String? {
        let fm = FileManager.default
        for d in [ae + "/deck", ae] where fm.fileExists(atPath: d + "/content/catalog.json") { return d }
        return nil
    }

    /// The deck's narrated cards: `(track, slug, folder)` for every `skills/<track>/<slug>/<slug>.html` under the deck.
    public static func deckCards(_ deck: String) -> [(track: String, slug: String, dir: String)] {
        let fm = FileManager.default
        var out: [(String, String, String)] = []
        for track in ((try? fm.contentsOfDirectory(atPath: deck + "/skills")) ?? []).sorted() where !track.hasPrefix(".") {
            for slug in ((try? fm.contentsOfDirectory(atPath: deck + "/skills/" + track)) ?? []).sorted() {
                let dir = deck + "/skills/" + track + "/" + slug
                if fm.fileExists(atPath: dir + "/" + slug + ".html") { out.append((track, slug, dir)) }
            }
        }
        return out
    }

    /// LAB-768 · your own routing rules: `~/.config/oneroof/agent-routing/<name>` wins over the bundled copy, so the rules stay
    /// editable now that there is no folder choice. `name` is "routing.json" or "roles.json".
    public static func routingFile(_ ae: String, _ name: String, home: String = NSHomeDirectory()) -> String? {
        let mine = home + "/.config/oneroof/agent-routing/" + name
        if FileManager.default.fileExists(atPath: mine) { return mine }
        return routingDir(ae).map { $0 + "/" + name }
    }

    /// The folder holding routing.json and roles.json: `skills/<any group>/agent-routing`.
    public static func routingDir(_ ae: String) -> String? {
        let fm = FileManager.default
        for group in ((try? fm.contentsOfDirectory(atPath: ae + "/skills")) ?? []).sorted() {
            let d = ae + "/skills/" + group + "/agent-routing"
            if fm.fileExists(atPath: d + "/routing.json") || fm.fileExists(atPath: d + "/roles.json") { return d }
        }
        return nil
    }

    static func expand(_ p: String) -> String { (p as NSString).expandingTildeInPath }
}

public extension AppSettings {
    /// The agentic-engineering folder actually in use (see `AEFolder`).
    var agenticEngineering: AEFolder.Resolved { AEFolder.resolve(setting: agenticEngineeringPath) }
}
