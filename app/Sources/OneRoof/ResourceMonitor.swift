import AppKit
import Foundation
import OneRoofCore

/// Resources (LAB-493): samples One Roof's own processes every 3 s on a background queue and publishes the snapshot
/// and ten minutes of history on the main thread. Always on, so the history is there when the owner opens the view
/// (LAB-310: holders grew to 5+ GB and froze the Mac; the point is to see it coming). A tick costs about a millisecond.
final class ResourceMonitor: ObservableObject {
    @Published private(set) var snapshot = ResourceSnapshot()
    @Published private(set) var history = ResourceHistory()
    /// LAB-544: every app on the Mac, sampled only while a Resources page is on screen (about 10 ms a tick).
    @Published private(set) var mac: MacBreakdown?
    private let macSampler = MacSampler()
    private var macWatchers = 0

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
        let wantsMac = macWatchers > 0
        let regular = wantsMac ? Set(NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular }.map(\.processIdentifier)) : []
        queue.async { [weak self] in
            guard let self else { return }
            if let roofd, self.daemonPid == nil || Date().timeIntervalSince(self.daemonAsked) > 30 {
                self.daemonAsked = Date()
                self.daemonPid = roofd.daemonPid()
            }
            let snap = self.sampler.sample(ResourceTargets(appPid: getpid(), daemonPid: self.daemonPid, sessions: sessions))
            let mac = wantsMac ? self.macSampler.sample(appPid: getpid(), oneRoofPids: Set(snap.allProcs.map(\.pid)), regularApps: regular) : nil
            // LAB-549: the local model this One Roof started has grown past its cap: restart it on next use.
            if let big = snap.app.first(where: { $0.ppid != 1 && $0.name.hasPrefix("llama-server") && $0.footprint > LocalModel.restartAbove }) {
                NSLog("One Roof: local model pid \(big.pid) uses \(big.footprint >> 20) MB, restarting it")
                DispatchQueue.global(qos: .utility).async { LocalModel.shared.stop() }
            }
            DispatchQueue.main.async {
                self.snapshot = snap
                self.history.record(snap)
                if wantsMac { self.mac = SelfTestMacFixture.breakdown ?? mac }   // LAB-853 self-test data
            }
        }
    }

    /// A Resources page appeared or went away: the whole-Mac sample runs while at least one is showing.
    func watchMac(_ on: Bool) {
        macWatchers = max(0, macWatchers + (on ? 1 : -1))
        if on && macWatchers == 1 { tick() }
        if macWatchers == 0 { mac = nil }
    }

    // MARK: Quit and end (LAB-544)

    /// Ask an app to quit, as the Dock's Quit does (it may ask to save); `force` = Force Quit. nil = sent.
    func quit(_ g: MacAppGroup, force: Bool) -> String? {
        guard g.quittable, let pid = g.mainPid, let app = NSRunningApplication(processIdentifier: pid) else {
            return "\(g.name) can't be quit from here."
        }
        let ok = force ? app.forceTerminate() : app.terminate()
        soon()
        return ok ? nil : "\(g.name) did not accept Quit. Try Force quit."
    }

    /// End one process: SIGTERM (it may tidy up), or SIGKILL with `force`. nil = sent.
    func end(_ p: MacProc, force: Bool) -> String? {
        guard p.endable, p.pid > 1, p.pid != getpid() else { return "\(p.name) can't be ended from here." }
        if kill(p.pid, force ? SIGKILL : SIGTERM) == 0 { soon(); return nil }
        switch errno {
        case ESRCH: soon(); return nil
        case EPERM: return "macOS does not allow One Roof to end \(p.name) (pid \(p.pid))."
        default: return "Could not end \(p.name): \(String(cString: strerror(errno)))."
        }
    }

    /// Show the result of a quit soon, not at the next 3 s tick.
    private func soon() { DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in self?.tick() } }

    /// At launch: a local model (llama-server on One Roof's port) that no process owns any more was left by a
    /// force-quit or crash; it keeps its memory and grows (8.4 GB on 10-22). One Roof starts a fresh one when needed.
    static func stopLeftoverLocalModel() {
        DispatchQueue.global(qos: .utility).async {
            let src = LiveResourceSource()
            for p in src.processes() where p.ppid == 1 && p.name.hasPrefix("llama-server") {
                if let argv = src.argv(p.pid), MacResources.isLocalModel(name: p.name, argv: argv) { kill(p.pid, SIGTERM) }
            }
        }
    }

    /// The live usage of a board row's session, when it runs (also after its agent exited while the shell lives on).
    func usage(_ item: BoardItem) -> SessionUsage? { item.resourceKey.flatMap { snapshot.sessions[$0] } }
}
