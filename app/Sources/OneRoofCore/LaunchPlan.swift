import Foundation

/// How a stored session becomes a `LaunchSpec`: the rules the Launch button follows, shared with roofd's scheduler
/// (Q7), which launches the same way with the app closed.
public enum LaunchPlan {
    public enum Refusal: Error, Equatable, CustomStringConvertible {
        /// Rule zero: agents start only inside ~/Projects.
        case outsideProjects(String)
        public var description: String {
            switch self { case .outsideProjects(let d): return "Agents start only inside ~/Projects. \(d) is outside it." }
        }
    }

    /// - Parameters:
    ///   - stored: every stored session (names another session owns are never adopted).
    ///   - command: a command to type into a plain terminal once its shell is up (a Fix button).
    ///   - deliverOpening: hand the opening message to the runtime (roofd sends it when the agent is ready).
    public static func spec(_ s: Session, stored: [Session], command: String? = nil, deliverOpening: Bool = false) -> Result<LaunchSpec, Refusal> {
        let dir = s.launchDirectory
        guard Workspace.isInsideProjects(dir) else { return .failure(.outsideProjects(dir)) }
        var spec = LaunchSpec(
            id: Session.herdrName(for: s.id), label: s.name, cwd: dir,
            env: AccountResolver.launchEnv(agent: s.agent, account: s.account),
            agent: s.agent, args: s.launchArgs, command: s.agent.isAgent ? nil : command,
            previousGroup: s.runtimeGroup, adoptOrphan: s.agent.isAgent && s.runtimeId == nil,
            claimed: Set(stored.compactMap { $0.id == s.id || $0.id.hasPrefix("herdr:") ? nil : $0.runtimeId }))
        if deliverOpening, s.agent.isAgent, s.openingPending { spec.opening = s.openingMessage }
        return .success(spec)
    }
}
