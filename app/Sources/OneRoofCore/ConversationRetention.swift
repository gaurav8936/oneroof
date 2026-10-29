import Foundation

/// LAB-1533 · how long agents keep their conversations on this Mac. Resume needs those files, and Claude Code deletes
/// its own after 30 days by default (`cleanupPeriodDays` in its settings.json, checked when Claude starts). One setting
/// in One Roof, applied to every Claude account. Codex (~/.codex/sessions) and Kimi (~/.kimi-code/sessions) have no
/// such limit to set: they keep their conversations until they are deleted.
public enum ConversationRetention {
    public static let claudeDefault = 30
    /// "Forever": Claude takes a number of days, so forever is a hundred years.
    public static let forever = 36_500
    public static let key = "cleanupPeriodDays"

    /// nil = not set: Claude's own default (30 days).
    public static let choices: [(days: Int?, label: String)] = [
        (nil, "Claude's default: 30 days"), (90, "90 days"), (365, "1 year"), (forever, "Forever"),
    ]

    public static func label(_ days: Int?) -> String {
        choices.first { $0.days == days }?.label ?? (days.map { "\($0) days" } ?? choices[0].label)
    }

    /// Days kept: nil (the default) counts as 30.
    public static func effective(_ days: Int?) -> Int { days ?? claudeDefault }

    /// Lowering the limit lets Claude delete older conversations the next time it starts (not undoable).
    public static func deletes(from old: Int?, to new: Int?) -> Bool { effective(new) < effective(old) }

    /// Every Claude settings file on this Mac (~/.claude and each ~/.claude-* account folder), symlinks resolved to the
    /// real file and de-duplicated: on the owner's Mac every account's settings.json links to ~/.claude/settings.json.
    public static func settingsFiles(home: String = NSHomeDirectory()) -> [String] {
        let fm = FileManager.default
        let names = (try? fm.contentsOfDirectory(atPath: home)) ?? []
        var seen = Set<String>(), out: [String] = []
        for n in names.sorted() where n == ".claude" || n.hasPrefix(".claude-") {
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: home + "/" + n, isDirectory: &isDir), isDir.boolValue else { continue }
            let real = ((home + "/" + n + "/settings.json") as NSString).resolvingSymlinksInPath
            if seen.insert(real).inserted { out.append(real) }
        }
        return out
    }

    /// What Claude is set to now (the first settings file that says); nil = its default.
    public static func current(home: String = NSHomeDirectory()) -> Int? {
        for f in settingsFiles(home: home) {
            if let o = read(f), let d = o[key] as? Int { return d }
        }
        return nil
    }

    /// Set (or, with nil, remove) the limit in every Claude settings file, keeping every other key, written to the real
    /// file so links stay links. Returns the files written.
    @discardableResult
    public static func apply(_ days: Int?, home: String = NSHomeDirectory()) throws -> [String] {
        var written: [String] = []
        for f in settingsFiles(home: home) {
            var o = read(f) ?? [:]
            if let days { o[key] = days } else { o.removeValue(forKey: key) }
            let data = try JSONSerialization.data(withJSONObject: o, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
            try FileManager.default.createDirectory(atPath: (f as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
            try data.write(to: URL(fileURLWithPath: f), options: .atomic)
            written.append(f)
        }
        return written
    }

    static func read(_ path: String) -> [String: Any]? {
        guard let d = FileManager.default.contents(atPath: path), !d.isEmpty else { return nil }
        return (try? JSONSerialization.jsonObject(with: d)) as? [String: Any]
    }
}
