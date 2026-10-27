import Foundation

/// LAB-1331 · the end of a growing file (an agent's transcript), read incrementally: the first call reads the last
/// `bytes`; later calls read only what was appended since, and keep a window of the largest size asked for. A file that
/// shrank or was replaced (another inode) is read again from its end. Thread-safe; windows unused for 2 minutes are freed.
public final class TailReader: @unchecked Sendable {
    public static let shared = TailReader()

    private struct Window { var inode: UInt64; var end: UInt64; var keep: Int; var data: Data; var used: Date }
    private let lock = NSLock()
    private var windows: [String: Window] = [:]
    /// Bytes read from disk so far (tests).
    public private(set) var bytesRead = 0

    public init() {}

    public func tail(_ path: String, bytes: Int, now: Date = Date()) -> Data? {
        guard let a = try? FileManager.default.attributesOfItem(atPath: path) else { return nil }
        let size = (a[.size] as? NSNumber)?.uint64Value ?? 0
        let inode = (a[.systemFileNumber] as? NSNumber)?.uint64Value ?? 0
        lock.lock(); defer { lock.unlock() }
        for (p, w) in windows where now.timeIntervalSince(w.used) > 120 { windows[p] = nil }
        if var w = windows[path], w.inode == inode, size >= w.end, bytes <= w.keep || w.data.count < w.keep {
            if size > w.end {
                guard let more = read(path, from: w.end, count: Int(size - w.end)) else { return nil }
                w.data.append(more); w.end = size
                if w.data.count > w.keep { w.data = w.data.suffix(w.keep) }
            }
            w.keep = max(w.keep, bytes); w.used = now
            windows[path] = w
            return w.data.suffix(bytes)
        }
        let from = size > UInt64(bytes) ? size - UInt64(bytes) : 0
        guard let d = read(path, from: from, count: Int(size - from)) else { return nil }
        windows[path] = Window(inode: inode, end: from + UInt64(d.count), keep: bytes, data: Data(d), used: now)
        return d
    }

    private func read(_ path: String, from: UInt64, count: Int) -> Data? {
        guard let h = FileHandle(forReadingAtPath: path) else { return nil }
        defer { try? h.close() }
        try? h.seek(toOffset: from)
        let d = (try? h.read(upToCount: count)) ?? Data()
        bytesRead += d.count
        return d
    }
}
