import CryptoKit
import Foundation

/// LAB-675 · Get the model: download the pinned on-device model (`LocalModel.download`), check its size and SHA-256
/// while it streams, and only then move it into place, with its licence next to it. A stopped or failed download keeps
/// its `.part` file, and the next start continues from there (HTTP Range) when the server allows it.
/// Pure parts (paths, space, text, states, hashing) are in `ModelDownload`; `ModelDownloader` does the network.
public enum ModelDownload {
    /// What to download: one pinned file.
    public struct Spec: Equatable, Sendable {
        public var url: URL
        public var sha256: String
        public var bytes: Int64
        public var fileName: String
        public var licenceFileName: String
        public init(url: URL, sha256: String, bytes: Int64, fileName: String, licenceFileName: String) {
            self.url = url; self.sha256 = sha256.lowercased(); self.bytes = bytes; self.fileName = fileName
            self.licenceFileName = licenceFileName
        }
    }

    // MARK: Paths

    /// Where the file is written while it downloads.
    public static func partPath(_ destination: String) -> String { destination + ".part" }
    /// The licence text goes next to the model.
    public static func licencePath(_ destination: String, licenceFileName: String) -> String {
        ((destination as NSString).deletingLastPathComponent as NSString).appendingPathComponent(licenceFileName)
    }

    // MARK: Space

    /// Head room kept free beyond the file itself.
    public static let spareBytes: Int64 = 256 << 20
    /// Bytes still to write (a `.part` already holds `partBytes`) plus the head room.
    public static func bytesNeeded(total: Int64, partBytes: Int64) -> Int64 { max(0, total - max(0, partBytes)) + spareBytes }
    public static func hasRoom(free: Int64, total: Int64, partBytes: Int64) -> Bool { free >= bytesNeeded(total: total, partBytes: partBytes) }

    /// Free space for the folder (or its nearest existing parent), as macOS reports it for important data.
    public static func freeBytes(at folder: String) -> Int64? {
        var dir = folder
        while !FileManager.default.fileExists(atPath: dir), dir != "/" { dir = (dir as NSString).deletingLastPathComponent }
        let v = try? URL(fileURLWithPath: dir).resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey, .volumeAvailableCapacityKey])
        if let n = v?.volumeAvailableCapacityForImportantUsage, n > 0 { return n }
        return v?.volumeAvailableCapacity.map(Int64.init)
    }

    // MARK: Text

    /// "1.1 GB", "412 MB", "800 KB".
    public static func size(_ bytes: Int64) -> String {
        let b = Double(max(0, bytes))
        if b >= 1e9 { return String(format: "%.1f GB", b / 1e9) }
        if b >= 1e6 { return String(format: "%.0f MB", b / 1e6) }
        return String(format: "%.0f KB", b / 1e3)
    }

    /// "412 MB of 1.1 GB · 37% · 18 MB/s · about 38 s left" (speed and time only once known).
    public static func progressText(received: Int64, total: Int64, bytesPerSecond: Double?) -> String {
        var s = "\(size(received)) of \(size(total))"
        if total > 0 { s += " · \(Int((Double(received) / Double(total) * 100).rounded(.down)))%" }
        if let r = bytesPerSecond, r > 0 {
            s += " · \(size(Int64(r)))/s"
            let left = Double(max(0, total - received)) / r
            s += left < 60 ? " · about \(max(1, Int(left.rounded()))) s left" : " · about \(Int((left / 60).rounded(.up))) min left"
        }
        return s
    }

    // MARK: States

    public enum State: Equatable, Sendable {
        case idle
        case downloading(received: Int64, total: Int64, bytesPerSecond: Double?)
        case verifying
        case done(path: String)
        case failed(String)
        case cancelled(received: Int64)

        public var isBusy: Bool {
            switch self { case .downloading, .verifying: return true; default: return false }
        }
        /// One line for Settings and Foundations.
        public var text: String {
            switch self {
            case .idle: return ""
            case let .downloading(r, t, bps): return "Downloading · " + ModelDownload.progressText(received: r, total: t, bytesPerSecond: bps)
            case .verifying: return "Checking the file (SHA-256)…"
            case .done: return "Downloaded and checked. One Roof uses it from the next task it sorts."
            case let .failed(why): return "Download failed: \(why)"
            case let .cancelled(r): return r > 0 ? "Stopped at \(ModelDownload.size(r)). Get the model again to continue." : "Stopped."
            }
        }
        public var fraction: Double? {
            if case let .downloading(r, t, _) = self, t > 0 { return min(1, Double(r) / Double(t)) }
            return nil
        }
    }

    public enum Event: Equatable, Sendable {
        case start(alreadyHave: Int64, total: Int64)
        case progress(received: Int64, bytesPerSecond: Double?)
        case finishedBytes
        case verified(path: String)
        case mismatch(String)
        case error(String)
        case cancel
        case reset
    }

    /// The download's state machine. Events that make no sense in a state leave it unchanged (a late progress
    /// callback after Cancel, a second Start while one runs).
    public static func next(_ s: State, _ e: Event) -> State {
        switch (s, e) {
        case let (_, .start(have, total)) where !s.isBusy: return .downloading(received: have, total: total, bytesPerSecond: nil)
        case let (.downloading(_, total, _), .progress(r, bps)): return .downloading(received: r, total: total, bytesPerSecond: bps)
        case (.downloading, .finishedBytes): return .verifying
        case let (.verifying, .verified(path)): return .done(path: path)
        case let (.verifying, .mismatch(why)), let (.downloading, .mismatch(why)): return .failed(why)
        case let (.downloading, .error(why)), let (.verifying, .error(why)), let (.idle, .error(why)): return .failed(why)
        case let (.downloading(r, _, _), .cancel): return .cancelled(received: r)
        case (.verifying, .cancel): return .cancelled(received: 0)
        case (_, .reset) where !s.isBusy: return .idle
        default: return s
        }
    }

    // MARK: Hashing

    /// SHA-256 over chunks as they arrive.
    public struct Hasher {
        private var h = SHA256()
        public init() {}
        public mutating func update(_ d: Data) { h.update(data: d) }
        public func hex() -> String { h.finalize().map { String(format: "%02x", $0) }.joined() }
    }

    /// Feed a file already on disk (a `.part` being continued, or a check) into `hasher`, 4 MB at a time.
    /// Returns the bytes read, or nil when it cannot be read.
    public static func hash(fileAt path: String, into hasher: inout Hasher) -> Int64? {
        guard let fh = FileHandle(forReadingAtPath: path) else { return nil }
        defer { try? fh.close() }
        var n: Int64 = 0
        while true {
            let ok: Bool = autoreleasepool {
                guard let d = try? fh.read(upToCount: 4 << 20), !d.isEmpty else { return false }
                hasher.update(d); n += Int64(d.count); return true
            }
            if !ok { break }
        }
        return n
    }

    public static func sha256(fileAt path: String) -> String? {
        var h = Hasher()
        return hash(fileAt: path, into: &h) == nil ? nil : h.hex()
    }

    /// Why a finished download is not the pinned file, or nil when it is.
    public static func verificationError(bytes: Int64, sha256: String, spec: Spec) -> String? {
        if bytes != spec.bytes { return "the file is \(size(bytes)), expected \(size(spec.bytes))" }
        if sha256.lowercased() != spec.sha256 { return "the SHA-256 does not match the pinned file" }
        return nil
    }

    /// Move the checked `.part` into place (replacing an older file of that name) and put the licence next to it.
    public static func install(part: String, destination: String, licenceSource: String?, licenceFileName: String) throws {
        let fm = FileManager.default
        let dest = URL(fileURLWithPath: destination)
        if fm.fileExists(atPath: destination) {
            _ = try fm.replaceItemAt(dest, withItemAt: URL(fileURLWithPath: part))
        } else {
            try fm.moveItem(atPath: part, toPath: destination)
        }
        if let src = licenceSource, fm.fileExists(atPath: src) {
            let lic = licencePath(destination, licenceFileName: licenceFileName)
            try? fm.removeItem(atPath: lic)
            try fm.copyItem(atPath: src, toPath: lic)
        }
    }
}

/// The network half of Get the model. One download at a time; `onState` is called on the main queue.
public final class ModelDownloader: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    public let spec: ModelDownload.Spec
    public let destination: String
    /// The licence text to copy next to the model (bundled in the app).
    public let licenceSource: String?
    public var onState: ((ModelDownload.State) -> Void)?
    public private(set) var state: ModelDownload.State = .idle

    private let queue = OperationQueue()
    private var session: URLSession?
    private var task: URLSessionDataTask?
    private var file: FileHandle?
    private var hasher = ModelDownload.Hasher()
    private var received: Int64 = 0
    private var startedAt = Date()
    private var startBytes: Int64 = 0
    private var lastReport = Date.distantPast
    private var cancelled = false

    public init(spec: ModelDownload.Spec, destination: String, licenceSource: String?) {
        self.spec = spec; self.destination = destination; self.licenceSource = licenceSource
        queue.maxConcurrentOperationCount = 1
        super.init()
    }

    private var part: String { ModelDownload.partPath(destination) }
    private static func fileSize(_ path: String) -> Int64? {
        ((try? FileManager.default.attributesOfItem(atPath: path))?[.size] as? NSNumber)?.int64Value
    }

    private func send(_ e: ModelDownload.Event) {
        let s = ModelDownload.next(state, e)
        state = s
        let cb = onState
        DispatchQueue.main.async { cb?(s) }
    }

    /// Start, or continue a `.part` left by an earlier try.
    public func start() {
        queue.addOperation { [self] in
            guard !state.isBusy else { return }
            let fm = FileManager.default
            let dir = (destination as NSString).deletingLastPathComponent
            do { try fm.createDirectory(atPath: dir, withIntermediateDirectories: true) } catch {
                send(.reset); send(.error("cannot create \(dir): \(error.localizedDescription)")); return
            }
            // Already in place (an earlier download): check it instead of downloading again.
            if Self.fileSize(destination) == spec.bytes {
                send(.reset); send(.start(alreadyHave: spec.bytes, total: spec.bytes)); send(.finishedBytes)
                if ModelDownload.sha256(fileAt: destination) == spec.sha256 {
                    if let src = licenceSource {
                        let lic = ModelDownload.licencePath(destination, licenceFileName: spec.licenceFileName)
                        if !fm.fileExists(atPath: lic) { try? fm.copyItem(atPath: src, toPath: lic) }
                    }
                    send(.verified(path: destination)); return
                }
                state = .idle  // not the pinned file: download it again (it is replaced once the new one checks out)
            }
            var have = Self.fileSize(part) ?? 0
            if have > spec.bytes { try? fm.removeItem(atPath: part); have = 0 }
            if let free = ModelDownload.freeBytes(at: dir), !ModelDownload.hasRoom(free: free, total: spec.bytes, partBytes: have) {
                send(.reset)
                send(.error("not enough free disk space: needs \(ModelDownload.size(ModelDownload.bytesNeeded(total: spec.bytes, partBytes: have))), \(ModelDownload.size(free)) free"))
                return
            }
            hasher = ModelDownload.Hasher()
            if have > 0, ModelDownload.hash(fileAt: part, into: &hasher) != have { hasher = ModelDownload.Hasher(); try? fm.removeItem(atPath: part); have = 0 }
            if !fm.fileExists(atPath: part) { fm.createFile(atPath: part, contents: nil) }
            guard let fh = FileHandle(forWritingAtPath: part) else { send(.reset); send(.error("cannot write \(part)")); return }
            _ = try? fh.seekToEnd()
            file = fh
            received = have; startBytes = have; startedAt = Date(); cancelled = false
            send(.reset)
            send(.start(alreadyHave: have, total: spec.bytes))
            if have == spec.bytes { finish(); return }
            var req = URLRequest(url: spec.url, timeoutInterval: 60)
            if have > 0 { req.setValue("bytes=\(have)-", forHTTPHeaderField: "Range") }
            let cfg = URLSessionConfiguration.ephemeral
            cfg.timeoutIntervalForResource = 6 * 3600
            let s = URLSession(configuration: cfg, delegate: self, delegateQueue: queue)
            session = s
            task = s.dataTask(with: req)
            task?.resume()
        }
    }

    /// Stop; the `.part` stays so the next start continues.
    public func cancel() {
        queue.addOperation { [self] in
            guard state.isBusy else { return }
            cancelled = true
            task?.cancel()
            closeFile()
            send(.cancel)
            session?.invalidateAndCancel(); session = nil
        }
    }

    private func closeFile() { try? file?.close(); file = nil }

    // MARK: URLSession (on `queue`)

    public func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                           newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        // Keep the Range header across Hugging Face's redirect to its CDN.
        var r = request
        if let range = task.originalRequest?.value(forHTTPHeaderField: "Range") { r.setValue(range, forHTTPHeaderField: "Range") }
        completionHandler(r)
    }

    public func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
                           completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        // A file:// URL (tests) has no status code.
        guard let http = response as? HTTPURLResponse else { completionHandler(.allow); return }
        let code = http.statusCode
        if code == 200, received > 0 {
            // The server ignored Range: start over.
            try? file?.truncate(atOffset: 0); try? file?.seek(toOffset: 0); received = 0; startBytes = 0; hasher = ModelDownload.Hasher()
        } else if code != 200 && code != 206 {
            completionHandler(.cancel)
            closeFile()
            send(.error("the server answered HTTP \(code)"))
            return
        }
        completionHandler(.allow)
    }

    public func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        guard !cancelled, let fh = file else { return }
        do { try fh.write(contentsOf: data) } catch {
            dataTask.cancel(); closeFile(); send(.error("cannot write the file: \(error.localizedDescription)")); return
        }
        hasher.update(data)
        received += Int64(data.count)
        let now = Date()
        if now.timeIntervalSince(lastReport) >= 0.25 {
            lastReport = now
            let secs = now.timeIntervalSince(startedAt)
            let bps = secs > 1 ? Double(received - startBytes) / secs : nil
            send(.progress(received: received, bytesPerSecond: bps))
        }
    }

    public func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        defer { session.finishTasksAndInvalidate(); if self.session === session { self.session = nil } }
        guard !cancelled, state.isBusy else { return }
        if let error {
            closeFile()
            send(.error(error.localizedDescription + (received > 0 ? " (Get the model again to continue)" : "")))
            return
        }
        send(.progress(received: received, bytesPerSecond: nil))
        finish()
    }

    private func finish() {
        closeFile()
        send(.finishedBytes)
        let hex = hasher.hex()
        if let why = ModelDownload.verificationError(bytes: received, sha256: hex, spec: spec) {
            try? FileManager.default.removeItem(atPath: part)
            send(.mismatch(why + "; the partial file was deleted"))
            return
        }
        do {
            try ModelDownload.install(part: part, destination: destination, licenceSource: licenceSource, licenceFileName: spec.licenceFileName)
            send(.verified(path: destination))
        } catch {
            send(.error("cannot move the file into place: \(error.localizedDescription)"))
        }
    }
}
