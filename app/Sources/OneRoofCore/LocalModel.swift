import Foundation

/// The small on-device model (owner, 2026-10-17: required): Arch-Router 1.5B run by llama.cpp's `llama-server` on
/// 127.0.0.1. It only sorts a task into a kind (research, design, code, review, test, docs, chore); the router's rules
/// then pick the agent. ~0.2 s per call, offline, free. One Roof starts the server on first use and stops it on quit.
public final class LocalModel: @unchecked Sendable {
    public static let shared = LocalModel()
    public static let port = 8749
    public static let modelFileName = "Arch-Router-1.5B-Q4_K_M.gguf"
    /// Where a downloaded model goes by default: ~/Library/Application Support/One Roof/models/.
    public static var defaultModelPath: String { Workspace.appSupport + "/models/" + modelFileName }

    nonisolated(unsafe) private static var configured: String?
    private static let configLock = NSLock()
    /// The model file in use: set by the app from Settings (`configure`), else the default path.
    public static var modelPath: String {
        configLock.lock(); defer { configLock.unlock() }
        return configured ?? defaultModelPath
    }
    public static func configure(path: String) { configLock.lock(); configured = path; configLock.unlock() }

    /// `ONEROOF_MODEL` wins, then the Settings value, then `defaultModelPath`.
    public static func resolve(setting: String, environment: [String: String] = ProcessInfo.processInfo.environment) -> String {
        if let e = environment["ONEROOF_MODEL"], !e.isEmpty { return (e as NSString).expandingTildeInPath }
        if !setting.isEmpty { return (setting as NSString).expandingTildeInPath }
        return defaultModelPath
    }

    private var process: Process?
    private let lock = NSLock()

    public var serverBinary: String? {
        ["/opt/homebrew/bin/llama-server", "/usr/local/bin/llama-server"].first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    public func installed(modelPath: String = LocalModel.modelPath) -> Bool {
        serverBinary != nil && FileManager.default.fileExists(atPath: modelPath)
    }

    /// One line for Settings and the startup check.
    public func status(modelPath: String = LocalModel.modelPath) -> String {
        if serverBinary == nil { return "llama.cpp not installed (brew install llama.cpp)" }
        if !FileManager.default.fileExists(atPath: modelPath) {
            return "optional model not found at \(modelPath.replacingOccurrences(of: NSHomeDirectory(), with: "~")) (heuristics are used)"
        }
        return healthy() ? "Arch-Router 1.5B running on 127.0.0.1:\(Self.port)" : "Arch-Router 1.5B ready (starts on first use)"
    }

    public func healthy() -> Bool {
        guard let url = URL(string: "http://127.0.0.1:\(Self.port)/health") else { return false }
        var req = URLRequest(url: url, timeoutInterval: 0.8)
        req.httpMethod = "GET"
        let sem = DispatchSemaphore(value: 0)
        var ok = false
        URLSession.shared.dataTask(with: req) { d, _, _ in
            ok = d.map { String(decoding: $0, as: UTF8.self).contains("ok") } ?? false
            sem.signal()
        }.resume()
        _ = sem.wait(timeout: .now() + 1)
        return ok
    }

    /// Start llama-server if nothing answers on the port; waits up to 20 s for it to load.
    public func ensureRunning(modelPath: String = LocalModel.modelPath) -> Bool {
        if healthy() { return true }
        lock.lock(); defer { lock.unlock() }
        guard let bin = serverBinary, FileManager.default.fileExists(atPath: modelPath) else { return false }
        if process?.isRunning != true {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: bin)
            p.arguments = ["-m", modelPath, "--port", "\(Self.port)", "--host", "127.0.0.1", "-c", "4096", "--log-disable"]
            p.standardOutput = FileHandle.nullDevice
            p.standardError = FileHandle.nullDevice
            do { try p.run() } catch { return false }
            process = p
        }
        for _ in 0..<40 {
            if healthy() { return true }
            usleep(500_000)
        }
        return false
    }

    public func stop() {
        lock.lock(); defer { lock.unlock() }
        process?.terminate()
        process = nil
    }

    static let task = """

    You are a helpful assistant designed to find the best suited route.
    You are provided with route description within <routes></routes> XML tags:
    <routes>
    {routes}
    </routes>
    <conversation>
    {conversation}
    </conversation>

    """
    static let format = """

    Your task is to decide which route is best suit with user intent on the conversation in <conversation></conversation> XML tags.  Follow the instruction:
    1. If the latest intent from user is irrelevant or user intent is full filled, response with other route {"route": "other"}.
    2. You must analyze the route descriptions and find the best match route for user latest intent.
    3. You only response the name of the route that best matches the user's request, use the exact name in the <routes></routes>.
    Based on your analysis, provide your response in the following JSON formats if you decide to match any route:
    {"route": "route_name"}

    """

    /// The kind of a task, or nil if the model is unavailable or answers "other". Call off the main thread.
    public func classify(_ text: String, kinds: [String: String], modelPath: String = LocalModel.modelPath) -> String? {
        guard ensureRunning(modelPath: modelPath) else { return nil }
        let routes = kinds.sorted { $0.key < $1.key }.map { ["name": $0.key, "description": $0.value] }
        guard let routesJSON = try? JSONSerialization.data(withJSONObject: routes),
              let convJSON = try? JSONSerialization.data(withJSONObject: [["role": "user", "content": text]]) else { return nil }
        let prompt = Self.task.replacingOccurrences(of: "{routes}", with: String(decoding: routesJSON, as: UTF8.self))
            .replacingOccurrences(of: "{conversation}", with: String(decoding: convJSON, as: UTF8.self)) + Self.format
        let body: [String: Any] = ["messages": [["role": "user", "content": prompt]], "temperature": 0, "max_tokens": 20]
        var req = URLRequest(url: URL(string: "http://127.0.0.1:\(Self.port)/v1/chat/completions")!, timeoutInterval: 15)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        let sem = DispatchSemaphore(value: 0)
        var answer: String?
        URLSession.shared.dataTask(with: req) { d, _, _ in
            if let d, let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
               let c = (j["choices"] as? [[String: Any]])?.first, let m = c["message"] as? [String: Any] {
                answer = m["content"] as? String
            }
            sem.signal()
        }.resume()
        _ = sem.wait(timeout: .now() + 16)
        return Self.parseRoute(answer, allowed: Set(kinds.keys))
    }

    /// `{"route": "code"}` or `{'route': 'code'}` → "code" (nil for "other" or anything not allowed).
    public static func parseRoute(_ s: String?, allowed: Set<String>) -> String? {
        guard let s, let r = s.range(of: #"route['"]?\s*:\s*['"]([a-z_]+)['"]"#, options: .regularExpression) else { return nil }
        let m = String(s[r])
        guard let q = m.range(of: #"['"]([a-z_]+)['"]$"#, options: .regularExpression) else { return nil }
        let name = m[q].trimmingCharacters(in: CharacterSet(charactersIn: "'\""))
        return allowed.contains(name) ? name : nil
    }
}

public extension RoutingPolicy {
    /// Kind descriptions for the on-device classifier, read in place from routing.json.
    static func kindDescriptions(agenticEngineering: String = AEFolder.resolve(setting: "").path) -> [String: String] {
        if let dir = AEFolder.routingDir(agenticEngineering), let d = FileManager.default.contents(atPath: dir + "/routing.json"),
           let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
           let k = j["kind_descriptions"] as? [String: String], !k.isEmpty { return k }
        return ["research": "Reading, investigating, comparing options", "design": "Designing an approach before building",
                "code": "Writing or changing code", "review": "Reviewing a change", "test": "Writing or running tests",
                "docs": "Writing documentation", "chore": "Housekeeping: upgrades, renames, cleanup"]
    }
}
