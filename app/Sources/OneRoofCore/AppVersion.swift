import Foundation

/// The One Roof version, from the app bundle's Info.plist (LAB-526): CFBundleShortVersionString and CFBundleVersion,
/// the same numbers tools/package-app.sh stamps into the release. The app shows it in every window's toolbar; roofd
/// (which ships in the same bundle, Contents/MacOS/roofd) reads the same Info.plist, so it reports its real version
/// instead of a hard-coded one.
public struct AppVersion: Equatable, Sendable {
    /// "0.4.10"
    public var short: String
    /// "14"
    public var build: String?

    public init(short: String, build: String? = nil) {
        self.short = short; self.build = build
    }

    /// From an Info.plist dictionary; nil without a short version (a bare `swift build` binary).
    public init?(info: [String: Any]?) {
        guard let s = (info?["CFBundleShortVersionString"] as? String)?.trimmingCharacters(in: .whitespaces), !s.isEmpty else { return nil }
        let b = (info?["CFBundleVersion"] as? String)?.trimmingCharacters(in: .whitespaces)
        self.init(short: s, build: b?.isEmpty == false ? b : nil)
    }

    /// This process's bundle (nil when not running from One Roof.app).
    public static var current: AppVersion? { AppVersion(info: Bundle.main.infoDictionary) }

    /// "0.4.10 (14)"
    public var number: String { build.map { "\(short) (\($0))" } ?? short }
    /// "One Roof 0.4.10 (14)"
    public var label: String { "One Roof \(number)" }

    /// The bundle's Info.plist for an executable inside it: `…/One Roof.app/Contents/MacOS/roofd` →
    /// `…/One Roof.app/Contents/Info.plist`. nil when the executable is not in a bundle's Contents/MacOS.
    public static func infoPlistPath(forExecutable path: String) -> String? {
        let macos = (path as NSString).deletingLastPathComponent
        guard (macos as NSString).lastPathComponent == "MacOS" else { return nil }
        let contents = (macos as NSString).deletingLastPathComponent
        guard (contents as NSString).lastPathComponent == "Contents" else { return nil }
        return contents + "/Info.plist"
    }

    /// The version of the bundle an executable lives in.
    public static func forExecutable(_ path: String) -> AppVersion? {
        guard let plist = infoPlistPath(forExecutable: path),
              let data = FileManager.default.contents(atPath: plist),
              let info = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else { return nil }
        return AppVersion(info: info)
    }

    /// Compare dotted numeric versions ("0.4.9" < "0.4.10"); nil when either is not a dotted number ("dev", "roofd").
    public static func compare(_ a: String, _ b: String) -> ComparisonResult? {
        func parts(_ s: String) -> [Int]? {
            let p = s.split(separator: ".").map { Int($0) }
            return p.isEmpty || p.contains(nil) ? nil : p.compactMap { $0 }
        }
        guard let x = parts(a), let y = parts(b) else { return nil }
        for i in 0..<max(x.count, y.count) {
            let l = i < x.count ? x[i] : 0, r = i < y.count ? y[i] : 0
            if l != r { return l < r ? .orderedAscending : .orderedDescending }
        }
        return .orderedSame
    }

    /// The running roofd is older than this app (it is replaced on the app's next start; sessions keep running).
    /// False when either version is unknown, so a dev build never warns.
    public static func daemonIsOlder(_ daemon: String?, than app: String?) -> Bool {
        guard let d = daemon, let a = app else { return false }
        return compare(d, a) == .orderedAscending
    }

    /// The footer's hover text when the running roofd is older than the app; nil when it is not.
    public static func daemonOlderNote(_ daemon: String?, app: String?) -> String? {
        guard daemonIsOlder(daemon, than: app), let d = daemon, let a = app else { return nil }
        return "The running roofd is \(d), older than One Roof \(a). One Roof replaces it when it next starts; "
            + "your sessions keep running."
    }
}
