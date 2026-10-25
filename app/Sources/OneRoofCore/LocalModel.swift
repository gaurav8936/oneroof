import Foundation

/// The small on-device model (owner, 2026-10-17: required): Qwen3-1.7B (Apache-2.0, LAB-674; Arch-Router 1.5B up to
/// 0.5.1) run by llama.cpp's `llama-server` on 127.0.0.1. It only sorts a task into a kind (research, design, code,
/// review, test, docs, chore); the router's rules then pick the agent. ~0.13 s per call, offline, free. One Roof starts
/// the server on first use and stops it on quit; a watchdog stops it when One Roof ends any other way (LAB-549).
/// Why this model: docs/decisions/20261023_01_on-device-model-qwen3.md (test set: app/scripts/route-eval).
public final class LocalModel: @unchecked Sendable {
    public static let shared = LocalModel()
    public static let port = 8749
    public static let modelFileName = "Qwen3-1.7B-Q4_K_M.gguf"
    /// LAB-675 · Get the model: the pinned file (Hugging Face revision, size, SHA-256) that was tested (LAB-673). Qwen
    /// publishes Qwen3-1.7B as GGUF only in Q8_0 (1.8 GB, same accuracy); this Q4_K_M is Unsloth's quantisation of the
    /// same weights, Apache-2.0. To switch file, change these three and `modelFileName`, and re-run app/scripts/route-eval.py.
    public static let downloadURL = "https://huggingface.co/unsloth/Qwen3-1.7B-GGUF/resolve/d7f544eead698dbd1f15126ef60b45a1e1933222/Qwen3-1.7B-Q4_K_M.gguf"
    public static let downloadSHA256 = "b139949c5bd74937ad8ed8c8cf3d9ffb1e99c866c823204dc42c0d91fa181897"
    public static let downloadBytes: Int64 = 1_107_409_472
    /// The licence text put next to the downloaded model (bundled as Resources/licenses/Qwen3-LICENSE.txt).
    public static let licenceFileName = "Qwen3-1.7B-LICENSE.txt"
    public static var download: ModelDownload.Spec {
        ModelDownload.Spec(url: URL(string: downloadURL)!, sha256: downloadSHA256, bytes: downloadBytes,
                           fileName: modelFileName, licenceFileName: licenceFileName)
    }
    /// The name people see (Settings, Foundations, Resources).
    public static let displayName = "Qwen3 1.7B"
    /// The model One Roof used up to 0.5.1. Still works if a user points Settings at it, but its licence (DigitalOcean
    /// Community License §4) needs a separate licence for commercial use, so Settings says so.
    public static let legacyFileName = "Arch-Router-1.5B-Q4_K_M.gguf"
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

    /// The name to show for a model file: `displayName` for the default file, else the file name without `.gguf`.
    public static func name(forPath path: String) -> String {
        let file = (path as NSString).lastPathComponent
        if file == modelFileName { return displayName }
        if file.lowercased().hasPrefix("arch-router") { return "Arch-Router" }
        return file.lowercased().hasSuffix(".gguf") ? String(file.dropLast(5)) : file
    }

    /// A note for Settings when the model path still points at Arch-Router (its licence), else nil.
    public static func licenceWarning(path: String) -> String? {
        guard (path as NSString).lastPathComponent.lowercased().hasPrefix("arch-router") else { return nil }
        return "Arch-Router (One Roof's model up to 0.5.1) needs a separate licence from DigitalOcean for commercial use. Get the model downloads \(displayName) (Apache-2.0) and switches to it."
    }

    /// LAB-675: offer Get the model when the model in use is missing or is Arch-Router. (When the pinned file is
    /// already in place, Get the model only checks it and switches to it.)
    public static func offerDownload(modelPath: String, exists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }) -> Bool {
        !exists(modelPath) || licenceWarning(path: modelPath) != nil
    }

    /// The Settings value after Get the model finished: "" (use the downloaded default) when the current one is empty,
    /// missing or Arch-Router; your own other model stays chosen.
    public static func settingAfterDownload(_ setting: String, exists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }) -> String {
        guard !setting.isEmpty else { return "" }
        let p = (setting as NSString).expandingTildeInPath
        return !exists(p) || licenceWarning(path: p) != nil ? "" : setting
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
        let name = Self.name(forPath: modelPath)
        return healthy() ? "\(name) running on 127.0.0.1:\(Self.port)" : "\(name) ready (starts on first use)"
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
            p.executableURL = URL(fileURLWithPath: "/bin/sh")
            p.arguments = Self.watchedArguments(parent: getpid(), command: [bin, "-m", modelPath, "--port", "\(Self.port)",
                                                                           "--host", "127.0.0.1", "-c", "4096", "--log-disable"])
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

    /// LAB-549: a force-quit or crash skips `stop()`, and on 10-22 the server it left grew to 8.4 GB over a day. So the
    /// server runs under a small /bin/sh watchdog: it checks every second that `parent` (this One Roof) is alive and
    /// ends the server when it is not, however the app ended. SIGTERM to the watchdog (`stop()`) ends the server at once.
    /// Arguments for `/bin/sh`: `-c <script> oneroof-local-model <parent> <command…>`.
    public static func watchedArguments(parent: Int32, command: [String], interval: Int = 1) -> [String] {
        let script = """
        parent=$1; shift
        "$@" &
        child=$!
        trap 'kill $child 2>/dev/null; wait $child 2>/dev/null; exit 0' TERM INT HUP
        while kill -0 "$parent" 2>/dev/null && kill -0 "$child" 2>/dev/null; do sleep \(interval) & wait $!; done
        kill $child 2>/dev/null; wait $child 2>/dev/null
        """
        return ["-c", script, "oneroof-local-model", String(parent)] + command
    }

    /// LAB-549: past this footprint the server One Roof started is restarted (the next request starts a fresh one).
    /// Qwen3-1.7B Q4_K_M needs about 1.6 GB with a 4096 context (Arch-Router 1.5B about 1.2 GB); 8.4 GB was seen after a
    /// day.
    public static let restartAbove: UInt64 = 3 << 30

    /// Eight one-line examples for the classifier; none is in the test set (app/scripts/route-eval/tasks.json).
    static let examples = """
    Examples:
    "Add dark mode to the settings window" -> code
    "Fix the login error when the token expires" -> code
    "Figure out how Stripe webhooks retry" -> research
    "Choose a schema for storing invoices before we build it" -> design
    "Review Bob's change to the parser" -> review
    "Write tests for the date formatter" -> test
    "Write a getting-started guide" -> docs
    "Upgrade Node and remove unused packages" -> chore
    """

    /// The classifier's system message: the kinds with their descriptions (from routing.json), three rules and the
    /// examples. Mirrored by app/scripts/route-eval.py; change both together and re-run it.
    public static func systemPrompt(kinds: [String: String]) -> String {
        "Classify a software task by the main work it asks for. Kinds:\n"
            + kinds.sorted { $0.key < $1.key }.map { "- \($0.key): \($0.value)" }.joined(separator: "\n")
            + "\nNew features, UI changes and bug fixes are code. Only pick test when the task is about tests or reproducing a failure. "
            + "Only pick chore for maintenance that changes no behaviour.\n" + examples
            + "\nReply with JSON only: {\"route\": \"<kind>\"}."
    }

    /// A llama-server `/v1/chat/completions` body: the answer is held to `{"route": <one of the kinds>}` by a JSON
    /// schema, and Qwen3's thinking is off (without it the reply is empty within 20 tokens; other models ignore it).
    public static func requestBody(text: String, kinds: [String: String]) -> Data {
        let schema: [String: Any] = ["type": "object", "properties": ["route": ["type": "string", "enum": kinds.keys.sorted()]],
                                     "required": ["route"], "additionalProperties": false]
        let body: [String: Any] = [
            "messages": [["role": "system", "content": systemPrompt(kinds: kinds)], ["role": "user", "content": "Task: " + text]],
            "temperature": 0, "max_tokens": 20,
            "response_format": ["type": "json_schema", "json_schema": ["name": "route", "schema": schema]],
            "chat_template_kwargs": ["enable_thinking": false],
        ]
        return (try? JSONSerialization.data(withJSONObject: body)) ?? Data()
    }

    /// The kind of a task, or nil if the model is unavailable or answers something that is not a kind. Call off the main thread.
    public func classify(_ text: String, kinds: [String: String], modelPath: String = LocalModel.modelPath) -> String? {
        guard ensureRunning(modelPath: modelPath) else { return nil }
        var req = URLRequest(url: URL(string: "http://127.0.0.1:\(Self.port)/v1/chat/completions")!, timeoutInterval: 15)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = Self.requestBody(text: text, kinds: kinds)
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
        if let f = AEFolder.routingFile(agenticEngineering, "routing.json"), let d = FileManager.default.contents(atPath: f),
           let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
           let k = j["kind_descriptions"] as? [String: String], !k.isEmpty { return k }
        return ["research": "Reading, investigating, comparing options", "design": "Designing an approach before building",
                "code": "Writing or changing code", "review": "Reviewing a change", "test": "Writing or running tests",
                "docs": "Writing documentation", "chore": "Housekeeping: upgrades, renames, cleanup"]
    }
}
