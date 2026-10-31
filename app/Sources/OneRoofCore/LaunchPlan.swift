import Foundation
import CryptoKit

/// How a stored session becomes a `LaunchSpec`: the rules the Launch button follows, shared with roofd's scheduler
/// (Q7), which launches the same way with the app closed.
public enum LaunchPlan {
    public enum Refusal: Error, Equatable, CustomStringConvertible {
        /// Rule zero: agents start only inside ~/Projects.
        case outsideProjects(String)
        case hostedSetupRequired
        public var description: String {
            switch self {
            case .outsideProjects(let d): return "Agents start only inside ~/Projects. \(d) is outside it."
            case .hostedSetupRequired: return "Set up a guarded hosted connection before launching this agent."
            }
        }
    }

    /// - Parameters:
    ///   - stored: every stored session (names another session owns are never adopted).
    ///   - command: a command to type into a plain terminal once its shell is up (a Fix button).
    ///   - deliverOpening: hand the opening message to the runtime (roofd sends it when the agent is ready).
    public static func spec(_ s: Session, stored: [Session], command: String? = nil, deliverOpening: Bool = false) -> Result<LaunchSpec, Refusal> {
        let dir = s.agent.isHosted ? Workspace.expand(s.repoPath) : s.launchDirectory
        guard Workspace.isInsideProjects(dir) else { return .failure(.outsideProjects(dir)) }
        if s.agent.isHosted {
            guard let h = s.hostedLaunch, h.agent == s.agent, h.connectionID == s.hostedConnectionID,
                  h.model == s.model, h.matches(repo: dir), s.agentArgs.isEmpty, (s.permissionMode ?? .manual) == .manual,
                  h.executable.hasPrefix("/"), h.arguments.first == "-m",
                  h.arguments.dropFirst().first == "ae.hostedsession",
                  let cwd = h.arguments.firstIndex(of: "--cwd"), h.arguments.indices.contains(cwd + 1),
                  HostedPreparation.fullPath(h.arguments[cwd + 1]) == HostedPreparation.fullPath(dir),
                  let attributes = try? FileManager.default.attributesOfItem(atPath: h.profilePath),
                  let size = attributes[.size] as? NSNumber, size.intValue < 65_536,
                  let data = try? Data(contentsOf: URL(fileURLWithPath: h.profilePath)),
                  SHA256.hash(data: data).map({ String(format: "%02x", $0) }).joined() == h.profileSHA256,
                  let profile = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  profile["price_checked"] as? String == HostedConnection.today(),
                  profile["provider"] as? String == h.provider.rawValue,
                  profile["model"] as? String == h.model else { return .failure(.hostedSetupRequired) }
            var spec = LaunchSpec(id: Session.runtimeName(for: s.id), label: s.name, cwd: dir,
                env: h.environment, agent: s.agent, args: h.arguments, previousGroup: s.runtimeGroup,
                adoptOrphan: s.runtimeId == nil,
                claimed: Set(stored.compactMap { $0.id == s.id ? nil : $0.runtimeId }))
            spec.executableOverride = h.executable
            if deliverOpening, !s.openingMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { spec.opening = s.openingMessage }
            return .success(spec)
        }
        var spec = LaunchSpec(
            id: Session.runtimeName(for: s.id), label: s.name, cwd: dir,
            env: AccountResolver.launchEnv(agent: s.agent, account: s.account),
            agent: s.agent, args: s.launchArgs, command: s.agent.isAgent ? nil : command,
            previousGroup: s.runtimeGroup, adoptOrphan: s.agent.isAgent && s.runtimeId == nil,
            claimed: Set(stored.compactMap { $0.id == s.id || $0.id.hasPrefix(Session.adoptedPrefix) ? nil : $0.runtimeId }))
        // Every launch and relaunch sends the opening message (herdr-era behaviour: a relaunch started over). An agent
        // that is merely re-linked (adoptOrphan) never gets it twice: roofd returns before creating anything.
        let opening = s.openingMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        if deliverOpening, s.agent.isAgent, !opening.isEmpty { spec.opening = s.openingMessage }
        return .success(spec)
    }
}
