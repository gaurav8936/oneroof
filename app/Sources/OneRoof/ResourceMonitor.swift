import Foundation
import OneRoofCore

/// Resources (LAB-493): samples One Roof's own processes every 3 s on a background queue and publishes the snapshot
/// and ten minutes of history on the main thread. Always on, so the history is there when the owner opens the view
/// (LAB-310: holders grew to 5+ GB and froze the Mac; the point is to see it coming). A tick costs about a millisecond.
final class ResourceMonitor: ObservableObject {
    @Published private(set) var snapshot = ResourceSnapshot()
    @Published private(set) var history = ResourceHistory()

    private let queue = DispatchQueue(label: "oneroof.resources", qos: .utility)
    private let sampler = ResourceSampler()
    private var timer: Timer?
    private weak var model: AppModel?
    /// The daemon's pid from `hello`, asked again every 30 s (on `queue`); between asks the sampler checks it is still
    /// a roofd and otherwise finds the daemon as the holders' parent.
    private var daemonPid: Int32?
    private var daemonAsked = Date.distantPast

    func start(model: AppModel) {
        self.model = model
        tick()
        timer = Timer.scheduledTimer(withTimeInterval: ResourceHistory.interval, repeats: true) { [weak self] _ in self?.tick() }
        timer?.tolerance = 0.3
    }

    /// Collect the targets on the main thread (cheap), sample on the queue, publish back on main.
    private func tick() {
        guard let model else { return }
        let sessions = model.lastSnapshotSessions.values.map {
            ResourceTargets.Session(runtimeId: $0.id, pid: $0.pid, memoryWarning: $0.memoryWarning)
        }
        let roofd = model.runtime as? RoofdRuntime
        queue.async { [weak self] in
            guard let self else { return }
            if let roofd, self.daemonPid == nil || Date().timeIntervalSince(self.daemonAsked) > 30 {
                self.daemonAsked = Date()
                self.daemonPid = roofd.daemonPid()
            }
            let snap = self.sampler.sample(ResourceTargets(appPid: getpid(), daemonPid: self.daemonPid, sessions: sessions))
            DispatchQueue.main.async {
                self.snapshot = snap
                self.history.record(snap)
            }
        }
    }

    /// The live usage of a board row's session, when it runs.
    func usage(_ item: BoardItem) -> SessionUsage? { item.liveAgent.flatMap { snapshot.sessions[$0] } }
}
