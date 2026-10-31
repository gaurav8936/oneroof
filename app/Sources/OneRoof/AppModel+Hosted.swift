import Foundation
import OneRoofCore

extension AppModel {
    /// Installation and native version probes never block the window's main thread.
    func prepareHostedLaunch(_ session: Session, foundationsChecked: Bool) {
        guard !busy.contains(session.id) else { return }
        guard let runtime = settings.hostedRuntime,
              let id = session.hostedConnectionID,
              let connection = settings.hostedConnections.first(where: { $0.id == id }) else {
            lastError = "Choose a hosted connection in Settings › Seats & accounts, then select it for this session."
            return
        }
        guard session.agentArgs.isEmpty, (session.permissionMode ?? .manual) == .manual,
              session.model == connection.model else {
            lastError = "Hosted sessions use the connection's exact model, Manual permissions and no extra CLI arguments."
            return
        }
        let shared = Workspace.expand(settings.sharedFolder) + "/docs"
        busy.insert(session.id)
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let result = Result { () throws -> HostedPreparedLaunch in
                let plan = try HostedPreparation.plan(connection: connection, runtime: runtime,
                    agent: session.agent, repo: session.repoPath, sharedDocs: shared)
                return try HostedPreparation.apply(plan, baseMCP: runtime.baseConfigPath)
            }
            DispatchQueue.main.async {
                guard let self else { return }
                self.busy.remove(session.id)
                guard var current = self.item(session.id)?.session,
                      current.agent == session.agent, current.repoPath == session.repoPath,
                      current.hostedConnectionID == connection.id, current.model == connection.model,
                      self.settings.hostedRuntime == runtime,
                      self.settings.hostedConnections.first(where: { $0.id == connection.id }) == connection else { return }
                switch result {
                case .failure(let error): self.lastError = String(describing: error)
                case .success(let prepared):
                    current.hostedLaunch = prepared
                    self.save(current)
                    if let item = self.item(current.id) { self.launch(item, foundationsChecked: true) }
                }
            }
        }
    }
}
