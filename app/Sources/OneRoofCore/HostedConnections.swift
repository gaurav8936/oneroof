import Foundation
import CryptoKit

/// Hosted inference is independent of the CLI agent. Endpoints are never free-form credential destinations.
public enum HostedProvider: String, Codable, CaseIterable, Identifiable, Sendable {
    case together, fireworks, openrouter
    public var id: String { rawValue }
    public var displayName: String {
        switch self { case .together: return "Together AI"; case .fireworks: return "Fireworks"; case .openrouter: return "OpenRouter" }
    }
    public var baseURL: String {
        switch self {
        case .together: return "https://api.together.ai/v1"
        case .fireworks: return "https://api.fireworks.ai/inference/v1"
        case .openrouter: return "https://openrouter.ai/api/v1"
        }
    }
    /// The default model for a new connection: the first verified one.
    public var testedModel: String { verifiedModels.first?.id ?? "" }

    /// LAB-1930 · open-weight coding models this provider serves, each checked with BOTH OpenCode and Goose through the
    /// supervised hosted session (a reply, one real tool call, then a follow-up the agent must answer from memory).
    /// Commercial (closed-weight) models are deliberately absent. Prices are USD per million tokens as listed on the
    /// verified date: Together and OpenRouter from their live catalogues, Fireworks from its model pages.
    public var verifiedModels: [HostedModel] { HostedModel.verified.filter { $0.provider == self } }

    public func verifiedModel(_ id: String) -> HostedModel? { verifiedModels.first { $0.id == id } }
}

/// One verified model × provider row (LAB-1930). The kit carries the same rows (ae/hostedmodels.py); a test keeps them equal.
public struct HostedModel: Equatable, Identifiable, Sendable {
    public let provider: HostedProvider
    public let id: String
    public let displayName: String
    public let inputPerMillion: Double
    public let outputPerMillion: Double
    public let verified: String
    public let priceSource: String

    public var priceLabel: String {
        func usd(_ v: Double) -> String { v < 0.1 ? String(format: "$%.3f", v) : String(format: "$%.2f", v) }
        return "\(usd(inputPerMillion)) / \(usd(outputPerMillion)) per M"
    }

    // MODEL-LIST-BEGIN (the table in docs/help/hosted-agents.md; keep in step with the kit's ae/hostedmodels.py)
    public static let verified: [HostedModel] = [
        HostedModel(provider: .together, id: "zai-org/GLM-5.3-Flash", displayName: "GLM-5.3-Flash", inputPerMillion: 0.15, outputPerMillion: 0.5, verified: "2026-10-31",
                    priceSource: "https://api.together.ai/v1/models"),
        HostedModel(provider: .together, id: "deepseek-ai/DeepSeek-V4.1-Flash", displayName: "DeepSeek V4.1 Flash", inputPerMillion: 0.3, outputPerMillion: 1.2, verified: "2026-10-31",
                    priceSource: "https://api.together.ai/v1/models"),
        HostedModel(provider: .together, id: "openai/gpt-oss-120b", displayName: "gpt-oss-120b", inputPerMillion: 0.15, outputPerMillion: 0.6, verified: "2026-10-31",
                    priceSource: "https://api.together.ai/v1/models"),
        HostedModel(provider: .together, id: "MiniMaxAI/MiniMax-M3", displayName: "MiniMax M3", inputPerMillion: 0.3, outputPerMillion: 1.2, verified: "2026-10-31",
                    priceSource: "https://api.together.ai/v1/models"),
        HostedModel(provider: .fireworks, id: "accounts/fireworks/models/glm-5p3-flash", displayName: "GLM-5.3-Flash", inputPerMillion: 0.15, outputPerMillion: 0.5, verified: "2026-10-31",
                    priceSource: "https://fireworks.ai/models/fireworks/glm-5p3-flash"),
        HostedModel(provider: .fireworks, id: "accounts/fireworks/models/gpt-oss-120b", displayName: "gpt-oss-120b", inputPerMillion: 0.15, outputPerMillion: 0.6, verified: "2026-10-31",
                    priceSource: "https://fireworks.ai/models/fireworks/gpt-oss-120b"),
        HostedModel(provider: .fireworks, id: "accounts/fireworks/models/minimax-m3", displayName: "MiniMax M3", inputPerMillion: 0.3, outputPerMillion: 1.2, verified: "2026-10-31",
                    priceSource: "https://fireworks.ai/models/fireworks/minimax-m3"),
        HostedModel(provider: .openrouter, id: "z-ai/glm-5.3-flash", displayName: "GLM-5.3-Flash", inputPerMillion: 0.0163, outputPerMillion: 0.1479, verified: "2026-10-31",
                    priceSource: "https://openrouter.ai/api/v1/models"),
        HostedModel(provider: .openrouter, id: "qwen/qwen3-coder-next", displayName: "Qwen3-Coder-Next", inputPerMillion: 0.12, outputPerMillion: 0.8, verified: "2026-10-31",
                    priceSource: "https://openrouter.ai/api/v1/models"),
        HostedModel(provider: .openrouter, id: "moonshotai/kimi-k2.7-code", displayName: "Kimi K2.7 Code", inputPerMillion: 0.6, outputPerMillion: 3.5, verified: "2026-10-31",
                    priceSource: "https://openrouter.ai/api/v1/models"),
        HostedModel(provider: .openrouter, id: "deepseek/deepseek-v4.1-flash", displayName: "DeepSeek V4.1 Flash", inputPerMillion: 0.045, outputPerMillion: 0.5, verified: "2026-10-31",
                    priceSource: "https://openrouter.ai/api/v1/models"),
        HostedModel(provider: .openrouter, id: "openai/gpt-oss-120b", displayName: "gpt-oss-120b", inputPerMillion: 0.15, outputPerMillion: 0.6, verified: "2026-10-31",
                    priceSource: "https://openrouter.ai/api/v1/models"),
        HostedModel(provider: .openrouter, id: "mistralai/devstral-2512", displayName: "Devstral 2 (2512)", inputPerMillion: 0.4, outputPerMillion: 2, verified: "2026-10-31",
                    priceSource: "https://openrouter.ai/api/v1/models"),
        HostedModel(provider: .openrouter, id: "minimax/minimax-m3", displayName: "MiniMax M3", inputPerMillion: 0.3, outputPerMillion: 1.2, verified: "2026-10-31",
                    priceSource: "https://openrouter.ai/api/v1/models"),
    ]
    // MODEL-LIST-END
}

/// References and explicit limits only. There is deliberately no API-key value property.
public struct HostedConnection: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var name: String
    public var provider: HostedProvider
    public var model: String
    public var keyFile: String
    public var inputPerMillion: Double
    public var outputPerMillion: Double
    public var priceChecked: String
    public var priceSource: String?
    public var sessionBudgetUSD: Double
    public var sharedBudgetUSD: Double
    public var maxRequests: Int
    public var maxOutputTokens: Int
    public var maxRequestBytes: Int
    public var maxTurns: Int

    public init(id: String = UUID().uuidString, name: String, provider: HostedProvider,
                model: String, keyFile: String) {
        self.id = id; self.name = name; self.provider = provider; self.model = model; self.keyFile = keyFile
        inputPerMillion = 0; outputPerMillion = 0; priceChecked = ""; priceSource = nil
        sessionBudgetUSD = 1; sharedBudgetUSD = 10
        maxRequests = 80; maxOutputTokens = 8192; maxRequestBytes = 180000; maxTurns = 12
    }

    /// Models a session on this connection may use: its own model first, then its provider's verified list (LAB-1930).
    public var sessionModels: [String] {
        [model] + provider.verifiedModels.map(\.id).filter { $0 != model }
    }

    /// This connection with `id` chosen for one session: same key reference, ceilings and shared ledger, that verified
    /// model's prices. The connection's own price check (today) still gates paid work. Nil for a model the provider's
    /// verified list does not hold.
    public func choosing(model id: String?) -> HostedConnection? {
        guard let id, !id.isEmpty else { return nil }
        if id == model { return self }
        guard let m = provider.verifiedModel(id) else { return nil }
        var c = self
        c.model = m.id; c.inputPerMillion = m.inputPerMillion; c.outputPerMillion = m.outputPerMillion; c.priceSource = m.priceSource
        return c
    }

    public static func today(_ now: Date = Date()) -> String {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.calendar = Calendar(identifier: .gregorian)
        f.timeZone = .current; f.dateFormat = "yyyy-MM-dd"
        return f.string(from: now)
    }

    public func configurationErrors(now: Date = Date()) -> [String] {
        var errors: [String] = []
        if UUID(uuidString: id) == nil { errors.append("Connection identity is invalid; create a new connection.") }
        if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { errors.append("Name this hosted connection.") }
        if model.isEmpty || !model.contains("/") || model.contains(where: { $0.isWhitespace }) { errors.append("Choose an exact provider-specific model ID.") }
        if !keyFile.hasPrefix("/") && !keyFile.hasPrefix("~/") { errors.append("Choose an external credential file; never paste a key value.") }
        if !inputPerMillion.isFinite || !outputPerMillion.isFinite || inputPerMillion <= 0 || outputPerMillion <= 0 {
            errors.append("Enter verified positive input/output prices per million tokens.")
        }
        if priceChecked != Self.today(now) { errors.append("Verify this model's prices today before starting paid work.") }
        if !sessionBudgetUSD.isFinite || !sharedBudgetUSD.isFinite || sessionBudgetUSD <= 0 || sharedBudgetUSD <= 0 || sessionBudgetUSD > sharedBudgetUSD {
            errors.append("Set positive session/shared reservation ceilings, with the session no larger than the shared ceiling.")
        }
        if min(maxRequests, maxOutputTokens, maxRequestBytes, maxTurns) <= 0 { errors.append("Request, output, context and turn limits must be positive.") }
        return errors
    }
}

public extension Array where Element == HostedConnection {
    /// The saved connection `id` with the session's model chosen (LAB-1930); nil when either is unknown.
    func resolved(id: String?, model: String?) -> HostedConnection? {
        first(where: { $0.id == id })?.choosing(model: model)
    }
}

/// The runtime installation is shared by connections; every launched session gets its own managed home.
public struct HostedRuntimeConfiguration: Codable, Equatable, Sendable {
    public var pythonExecutable: String
    public var kitDirectory: String
    public var nativeExecutables: [String: String]
    public var storageDirectory: String
    public var baseConfigPath: String?
    public var timeoutSeconds: Double

    public init(pythonExecutable: String, kitDirectory: String, nativeExecutables: [String: String], storageDirectory: String,
                baseConfigPath: String? = nil, timeoutSeconds: Double = 3600) {
        self.pythonExecutable = pythonExecutable; self.kitDirectory = kitDirectory
        self.nativeExecutables = nativeExecutables; self.storageDirectory = storageDirectory
        self.baseConfigPath = baseConfigPath; self.timeoutSeconds = timeoutSeconds
    }
}

public enum HostedSetupError: Error, CustomStringConvertible {
    case invalid([String])
    case failed(String)
    public var description: String {
        switch self { case .invalid(let errors): return errors.joined(separator: " "); case .failed(let message): return message }
    }
}

/// A pure private-file/argv plan; applying it is an explicit, off-main-thread setup operation.
public struct HostedPreparationPlan: @unchecked Sendable {
    public let connectionID: String
    public let agent: AgentKind
    public let model: String
    public let provider: HostedProvider
    public let runDirectory: String
    public let homeDirectory: String
    public let profilePath: String
    public let configPath: String
    public let recordPath: String
    public let executable: String
    public let arguments: [String]
    public let environment: [String: String]
    public let profile: [String: Any]
    public let kitConfig: [String: Any]
}

/// LAB-1931 · what New session needs before a hosted (OpenCode/Goose) session can start: a runtime, a valid saved
/// connection and a supported start. Where it starts is not a condition: ~/Projects or any repository, as for every
/// other agent (the runtime and credential checks happen in `HostedPreparation.plan`).
public enum HostedSheetRules {
    public static func blockedReason(hasRuntime: Bool, connection: HostedConnection?, startSupported: Bool,
                                     repo: String, now: Date = Date()) -> String? {
        if !hasRuntime { return "Configure the hosted runtime in Settings › Seats & accounts" }
        guard let c = connection else { return "Choose a saved hosted connection" }
        if let error = c.configurationErrors(now: now).first { return error }
        if !startSupported { return "Hosted sessions support Now, Next or On demand" }
        return nil
    }
}

public enum HostedPreparation {
    static func fullPath(_ path: String) -> String {
        URL(fileURLWithPath: Workspace.expand(path)).standardizedFileURL.resolvingSymlinksInPath().path
    }

    /// LAB-1931 · the session starts at the whole workspace (~/Projects), as any other agent may.
    static func isWorkspaceRoot(_ root: String, workspace: String = Workspace.projectsRoot) -> Bool {
        fullPath(root) == fullPath(workspace)
    }

    static func inside(_ path: String, _ root: String) -> Bool { path == root || path.hasPrefix(root + "/") }

    public static func plan(connection c: HostedConnection, runtime r: HostedRuntimeConfiguration,
                            agent: AgentKind, repo: String, sharedDocs: String, now: Date = Date(),
                            workspace: String = Workspace.projectsRoot) throws -> HostedPreparationPlan {
        var errors = c.configurationErrors(now: now)
        if !agent.isHosted { errors.append("Choose OpenCode or Goose for a hosted connection.") }
        guard let native = r.nativeExecutables[agent.rawValue], native.hasPrefix("/") else {
            throw HostedSetupError.invalid(errors + ["Choose the pinned native executable for \(agent.displayName)."])
        }
        if !r.pythonExecutable.hasPrefix("/") || !r.kitDirectory.hasPrefix("/") || !r.storageDirectory.hasPrefix("/") {
            errors.append("Runtime Python, kit and private storage paths must be absolute.")
        }
        if !r.timeoutSeconds.isFinite || r.timeoutSeconds <= 0 { errors.append("Set a finite positive session duration.") }
        let root = fullPath(repo), storage = fullPath(r.storageDirectory), credential = fullPath(c.keyFile)
        // LAB-1931: at the workspace root (~/Projects) the runtime, private files and credential may sit inside the
        // session's root, as they do for every other agent. The kit's guard then keeps them off limits: no tool reads
        // the credential or the private files (protected_read), no tool edits the kit, Python or native agent
        // (protected_write). A specific repository that holds them is still refused: use a worktree for the kit.
        let atWorkspace = isWorkspaceRoot(root, workspace: workspace)
        var protectedRead: [String] = [], protectedWrite: [String] = []
        if inside(storage, root) {
            if atWorkspace { protectedRead.append(storage) } else { errors.append("Private launch files must be outside the agent's repository.") }
        }
        for trusted in [native, r.pythonExecutable, r.kitDirectory] {
            let path = fullPath(trusted)
            guard inside(path, root) else { continue }
            if atWorkspace { if !protectedWrite.contains(path) { protectedWrite.append(path) } }
            else { errors.append("Keep the native executable, Python and kit outside this session's repository; use a worktree when editing the kit.") }
        }
        if inside(credential, root) {
            if atWorkspace { protectedRead.append(credential) } else { errors.append("Keep the provider credential outside the agent's repository.") }
        }
        if !errors.isEmpty { throw HostedSetupError.invalid(errors) }
        let connectionDir = storage + "/connections/" + c.id
        let run = connectionDir + "/runs/" + UUID().uuidString
        let home = run + "/home", profilePath = run + "/hosted.json", configPath = run + "/ae.config.json"
        let record = run + "/usage.json", docs = fullPath(sharedDocs)
        let profile: [String: Any] = ["provider": c.provider.rawValue, "model": c.model, "key_file": credential,
            "input_per_million": c.inputPerMillion, "output_per_million": c.outputPerMillion, "price_checked": c.priceChecked,
            "budget_usd": c.sessionBudgetUSD, "shared_budget_usd": c.sharedBudgetUSD, "ledger": run + "/phase-ledger.json",
            "shared_ledger": connectionDir + "/aggregate-ledger.json", "max_requests": c.maxRequests,
            "max_output_tokens": c.maxOutputTokens, "max_request_bytes": c.maxRequestBytes, "max_turns": c.maxTurns]
        var agents: [String: Any] = [:]
        for name in ["claude", "codex", "gemini", "kimi", "antigravity", "opencode", "goose"] {
            agents[name] = ["enabled": name == agent.rawValue, "bin": native]
        }
        var permissions: [String: Any] = ["interactive_review": true, "read_roots": [docs], "write_roots": [docs + "/next-session-handoff"]]
        if !protectedRead.isEmpty { permissions["protected_read"] = protectedRead }
        if !protectedWrite.isEmpty { permissions["protected_write"] = protectedWrite }
        let config: [String: Any] = ["version": 1, "scope": "user", "install": "link", "profile": "standard", "packs": ["kit"],
            "workspace": ["root": root, "read_first": docs + "/READ-FIRST.md", "docs": "docs", "handoffs": docs + "/next-session-handoff"],
            "agents": agents, "rules": ["user": true],
            "permissions": permissions,
            "tracker": ["adapter": "none"], "notifier": ["adapter": "none"], "knowledge": ["adapter": "none"],
            "journal": ["root": run + "/journal", "commit": false], "hosts": ["oneroof": true],
            "loops": ["scheduler": "none", "enabled": [String]()]]
        // Workspace configuration is never blindly included. An optional reviewed
        // source contributes MCP definitions only through the supervisor setup helper.
        let args = ["-m", "ae.hostedsession", "--agent", agent.rawValue, "--binary", native, "--home", home,
                    "--cwd", root, "--profile", profilePath, "--record", record, "--timeout", String(r.timeoutSeconds)]
        let env = ["PYTHONPATH": fullPath(r.kitDirectory)]
        return HostedPreparationPlan(connectionID: c.id, agent: agent, model: c.model, provider: c.provider,
            runDirectory: run, homeDirectory: home, profilePath: profilePath, configPath: configPath,
            recordPath: record, executable: r.pythonExecutable, arguments: args, environment: env, profile: profile, kitConfig: config)
    }
}

/// Saved session metadata contains references only, never provider credentials or local bridge tokens.
public struct HostedPreparedLaunch: Codable, Equatable, Sendable {
    public var connectionID: String
    public var agent: AgentKind
    public var provider: HostedProvider
    public var model: String
    public var executable: String
    public var arguments: [String]
    public var environment: [String: String]
    public var homeDirectory: String
    public var profilePath: String
    public var recordPath: String
    public var preparedAt: Date
    public var nativeVersion: String?
    public var profileSHA256: String
}

public extension HostedPreparation {
    typealias Runner = (String, [String], String, [String: String]) -> (Int32, String)

    static func safeEnvironment(_ extra: [String: String]) -> [String: String] {
        let allowed = Set(["PATH", "LANG", "LC_ALL", "TMPDIR", "TERM", "USER", "SHELL", "SSL_CERT_FILE", "SSL_CERT_DIR"])
        var env = ProcessInfo.processInfo.environment.filter { allowed.contains($0.key) }
        if env["PATH"] == nil { env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin" }
        if env["USER"] == nil { env["USER"] = NSUserName() }
        for (key, value) in extra where key == "PYTHONPATH" { env[key] = value }
        return env
    }

    /// Run on a background queue. It writes scoped private files, installs only the selected home,
    /// and requests local readiness from the Python supervisor without an inference call.
    static func apply(_ p: HostedPreparationPlan, baseMCP: String? = nil, run: Runner? = nil) throws -> HostedPreparedLaunch {
        let fm = FileManager.default
        guard fm.isExecutableFile(atPath: p.executable),
              fm.fileExists(atPath: p.environment["PYTHONPATH", default: ""] + "/ae/hostedsession.py") else {
            throw HostedSetupError.failed("Install Python 3.11+ with PyYAML and select a kit containing the hosted-session launcher.")
        }
        guard let key = p.profile["key_file"] as? String, fm.isReadableFile(atPath: key) else {
            throw HostedSetupError.failed("The external credential file is missing or unreadable. Choose its reference in Settings.")
        }
        guard Foundations.childExitCodesReadable else {
            throw HostedSetupError.failed("Child process exit codes are unavailable; hosted setup cannot be verified safely.")
        }
        try fm.createDirectory(atPath: p.runDirectory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try fm.createDirectory(atPath: p.homeDirectory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        for (path, object) in [(p.profilePath, p.profile), (p.configPath, p.kitConfig)] {
            let data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
            try data.write(to: URL(fileURLWithPath: path), options: .atomic)
            try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: path)
        }
        var args = p.arguments + ["--prepare", "--config", p.configPath]
        if let baseMCP, !baseMCP.isEmpty { args += ["--base-mcp", fullPath(baseMCP)] }
        let runner: Runner = run ?? { exe, args, cwd, env in Foundations.run(exe, args, cwd: cwd, timeout: 45, environment: env) }
        guard let index = p.arguments.firstIndex(of: "--cwd"), p.arguments.indices.contains(index + 1) else {
            throw HostedSetupError.failed("The hosted launch workspace is missing.")
        }
        let result = runner(p.executable, args, p.arguments[index + 1], safeEnvironment(p.environment))
        // Never surface arbitrary helper output: plugins/binaries could print private data.
        guard result.0 == 0, let raw = result.1.split(separator: "\n").last,
              let object = try? JSONSerialization.jsonObject(with: Data(raw.utf8)) as? [String: Any],
              object["ready"] as? Bool == true, object["agent"] as? String == p.agent.rawValue,
              object["provider"] as? String == p.provider.rawValue, object["model"] as? String == p.model else {
            throw HostedSetupError.failed("Hosted setup did not verify the guard, pinned agent and remaining reservation budget. Check the runtime installation, current prices and connection limits.")
        }
        return HostedPreparedLaunch(connectionID: p.connectionID, agent: p.agent, provider: p.provider, model: p.model,
            executable: p.executable, arguments: p.arguments, environment: p.environment, homeDirectory: p.homeDirectory,
            profilePath: p.profilePath, recordPath: p.recordPath, preparedAt: Date(), nativeVersion: object["version"] as? String,
            profileSHA256: SHA256.hash(data: try Data(contentsOf: URL(fileURLWithPath: p.profilePath))).map { String(format: "%02x", $0) }.joined())
    }
}

public extension HostedPreparation {
    /// Catalogue access updates rates only. It does not imply authenticated inference or a billing balance.
    static func refreshPrices(connection c: HostedConnection, runtime r: HostedRuntimeConfiguration,
                              repo: String, run: Runner? = nil) throws -> HostedConnection {
        let fm = FileManager.default
        guard UUID(uuidString: c.id) != nil, !c.model.isEmpty,
              fm.isExecutableFile(atPath: r.pythonExecutable),
              fm.fileExists(atPath: r.kitDirectory + "/ae/hostedsession.py"),
              fm.isReadableFile(atPath: fullPath(c.keyFile)) else {
            throw HostedSetupError.failed("Choose a runtime, exact model and readable external credential reference before checking prices.")
        }
        let root = fullPath(repo), credential = fullPath(c.keyFile)
        guard credential != root, !credential.hasPrefix(root + "/") else {
            throw HostedSetupError.failed("Keep the credential outside the agent workspace.")
        }
        let dir = fullPath(r.storageDirectory) + "/connections/" + c.id + "/catalog/" + UUID().uuidString
        try fm.createDirectory(atPath: dir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let path = dir + "/catalog.json"
        let profile = ["provider": c.provider.rawValue, "model": c.model, "key_file": credential]
        try JSONSerialization.data(withJSONObject: profile).write(to: URL(fileURLWithPath: path), options: .atomic)
        try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: path)
        let args = ["-m", "ae.hostedsession", "--agent", "opencode", "--binary", r.pythonExecutable,
                    "--home", dir + "/home", "--cwd", root, "--profile", path, "--refresh-prices"]
        let runner: Runner = run ?? { exe, args, cwd, env in Foundations.run(exe, args, cwd: cwd, timeout: 35, environment: env) }
        let result = runner(r.pythonExecutable, args, root, safeEnvironment(["PYTHONPATH": r.kitDirectory]))
        guard result.0 == 0, let line = result.1.split(separator: "\n").last,
              let obj = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
              obj["provider"] as? String == c.provider.rawValue, obj["model"] as? String == c.model,
              obj["price_checked"] as? String == HostedConnection.today(),
              obj["unit"] as? String == "USD per million tokens",
              let incoming = obj["input_per_million"] as? Double, let outgoing = obj["output_per_million"] as? Double,
              incoming.isFinite, outgoing.isFinite, incoming > 0, outgoing > 0 else {
            throw HostedSetupError.failed("Verified catalogue prices are unavailable. Check the provider's model page and enter today's verified rates manually; no old price was marked fresh.")
        }
        var updated = c
        updated.inputPerMillion = incoming; updated.outputPerMillion = outgoing
        updated.priceChecked = HostedConnection.today(); updated.priceSource = c.provider.baseURL + "/models"
        return updated
    }
}

public extension HostedPreparedLaunch {
    /// Stored argv is data, never a free-form command. Recheck its complete shape at every relaunch.
    func matches(repo: String, workspace: String = Workspace.projectsRoot) -> Bool {
        let flags = ["--agent", "--binary", "--home", "--cwd", "--profile", "--record", "--timeout"]
        guard arguments.count == 2 + flags.count * 2,
              Array(arguments.prefix(2)) == ["-m", "ae.hostedsession"],
              executable.hasPrefix("/"), environment.count == 1,
              let kit = environment["PYTHONPATH"], kit.hasPrefix("/") else { return false }
        var values: [String: String] = [:]
        for (i, flag) in flags.enumerated() {
            guard arguments[2 + i * 2] == flag else { return false }
            values[flag] = arguments[3 + i * 2]
        }
        guard values["--agent"] == agent.rawValue, values["--home"] == homeDirectory,
              values["--profile"] == profilePath, values["--record"] == recordPath,
              let cwd = values["--cwd"], HostedPreparation.fullPath(cwd) == HostedPreparation.fullPath(repo),
              let timeout = Double(values["--timeout"] ?? ""), timeout.isFinite, timeout > 0,
              let native = values["--binary"], native.hasPrefix("/") else { return false }
        let root = HostedPreparation.fullPath(repo)
        // LAB-1931: at the workspace root these may sit inside it; the kit's launch check then requires its guard to
        // protect them, and refuses otherwise.
        if HostedPreparation.isWorkspaceRoot(root, workspace: workspace) { return true }
        return [executable, kit, native, homeDirectory, profilePath, recordPath].allSatisfy {
            let p = HostedPreparation.fullPath($0)
            return p != root && !p.hasPrefix(root + "/")
        }
    }
}

/// Small read-only usage view. Reservations are estimates; provider billing is never inferred.
public struct HostedSessionUsage: Equatable, Sendable {
    public var requests: Int
    public var reservedUSD: Double
    public var ceilingUSD: Double
    public var reportedTokens: Int?

    public static func read(_ launch: HostedPreparedLaunch) -> HostedSessionUsage? {
        func object(_ path: String) -> [String: Any]? {
            guard let a = try? FileManager.default.attributesOfItem(atPath: path),
                  (a[.size] as? NSNumber)?.intValue ?? Int.max < 1_048_576,
                  let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else { return nil }
            return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        }
        guard let profile = object(launch.profilePath), profile["model"] as? String == launch.model,
              let cap = profile["budget_usd"] as? Double, let ledger = profile["ledger"] as? String else { return nil }
        let counters = object(ledger)
        if FileManager.default.fileExists(atPath: ledger), counters == nil { return nil }
        guard cap.isFinite, cap > 0 else { return nil }
        let record = object(launch.recordPath)
        let rows = record?["requests"] as? [[String: Any]] ?? []
        let totals = rows.compactMap { ($0["usage"] as? [String: Any])?["total_tokens"] as? Int }.filter { $0 >= 0 }
        var total = 0, overflow = false
        for n in totals { let sum = total.addingReportingOverflow(n); total = sum.partialValue; overflow = overflow || sum.overflow }
        return HostedSessionUsage(requests: counters?["requests"] as? Int ?? 0,
            reservedUSD: counters?["reserved_usd"] as? Double ?? 0, ceilingUSD: cap,
            reportedTokens: totals.isEmpty || overflow ? nil : total)
    }
}

public extension HostedPreparedLaunch {
    /// Refresh a managed phase when the owner verifies new rates or changes connection/runtime settings.
    /// The stable connection aggregate ledger still enforces the retained shared ceiling.
    func isCurrent(connection c: HostedConnection, runtime r: HostedRuntimeConfiguration) -> Bool {
        guard connectionID == c.id, provider == c.provider, model == c.model,
              executable == r.pythonExecutable, environment["PYTHONPATH"] == HostedPreparation.fullPath(r.kitDirectory),
              let binary = r.nativeExecutables[agent.rawValue],
              arguments.contains(binary), arguments.last == String(r.timeoutSeconds),
              let attributes = try? FileManager.default.attributesOfItem(atPath: profilePath),
              let size = attributes[.size] as? NSNumber, size.intValue < 65_536,
              let data = try? Data(contentsOf: URL(fileURLWithPath: profilePath)),
              let profile = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              profile["key_file"] as? String == HostedPreparation.fullPath(c.keyFile),
              profile["price_checked"] as? String == c.priceChecked,
              c.priceChecked == HostedConnection.today() else { return false }
        let expected: [String: Double] = ["input_per_million": c.inputPerMillion, "output_per_million": c.outputPerMillion,
            "budget_usd": c.sessionBudgetUSD, "shared_budget_usd": c.sharedBudgetUSD, "max_requests": Double(c.maxRequests),
            "max_output_tokens": Double(c.maxOutputTokens), "max_request_bytes": Double(c.maxRequestBytes), "max_turns": Double(c.maxTurns)]
        return expected.allSatisfy { (profile[$0.key] as? Double) == $0.value }
    }
}
