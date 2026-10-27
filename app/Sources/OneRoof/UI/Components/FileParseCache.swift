import Foundation

/// LAB-1332 · a file read and parsed once, again only when its modification time or size changes. For readers whose
/// view bodies read and parse a file on every redraw (Learn posts, Release notes).
enum FileParseCache {
    private struct Entry { let stamp: String; let value: Any }
    nonisolated(unsafe) private static var entries: [String: Entry] = [:]

    static func value<T>(_ path: String, kind: String, parse: (String) -> T) -> T {
        let a = try? FileManager.default.attributesOfItem(atPath: path)
        let stamp = "\((a?[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0)·\((a?[.size] as? NSNumber)?.intValue ?? -1)"
        let key = kind + "\u{1}" + path
        if let e = entries[key], e.stamp == stamp, let v = e.value as? T { return v }
        let v = parse((try? String(contentsOfFile: path, encoding: .utf8)) ?? "")
        if entries.count > 64 { entries.removeAll() }
        entries[key] = Entry(stamp: stamp, value: v)
        return v
    }
}
