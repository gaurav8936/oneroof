import Foundation
import OneRoofCore

/// Tonight / Nightly with the app closed (owner Q7, LAB-23): every 30 s the daemon reads the schedules in One Roof's
/// session store and launches what is due exactly as the Launch button does (LaunchPlan), with the opening message
/// delivered by the session's holder. Off unless the app turned it on (Settings › Allow scheduled runs); with it off,
/// the app runs schedules itself while it is open, so the two never both fire.
enum Scheduler {
    struct Config: Codable {
        var enabled: Bool
        var store: String
        var projects: String?
        var shared: String?
    }

    static var configPath: String { Paths.dir + "/scheduler.json" }

    static func config() -> Config? {
        guard let d = FileManager.default.contents(atPath: configPath) else { return nil }
        return try? JSONDecoder().decode(Config.self, from: d)
    }

    static func save(_ c: Config) throws {
        let d = try JSONEncoder().encode(c)
        let tmp = configPath + ".tmp"
        FileManager.default.createFile(atPath: tmp, contents: d, attributes: [.posixPermissions: 0o600])
        guard rename(tmp, configPath) == 0 else { throw RoofdError("could not save scheduler config") }
    }

    static func start() {
        Thread.detachNewThread {
            while true {
                tick()
                Thread.sleep(forTimeInterval: 30)
            }
        }
    }

    /// Sessions running in roofd now (not exited).
    static func alive() -> Set<String> {
        Set(Daemon.sessionIds().filter { id in
            guard let info = try? Sock.holderRequest(Paths.session(id), ["op": "info"], timeout: 1) else { return false }
            return info["exited"] == nil
        })
    }

    static func tick(now: Date = Date()) {
        guard let c = config(), c.enabled, let store = try? SessionStore(path: c.store) else { return }
        if let p = c.projects { Workspace.configure(root: p, shared: c.shared) }
        let records = store.schedules()
        guard !records.isEmpty else { return }
        let all = store.all()
        let live = alive()
        for r in records {
            switch ScheduleClock.action(r, now: now) {
            case .nothing:
                continue
            case .missed:
                store.recordScheduledRun(session: r.sessionId, at: now, result: "missed")
            case .run:
                guard var s = all.first(where: { $0.id == r.sessionId }) else { continue }
                if let id = s.runtimeId, live.contains(id) {   // already running: nothing to start
                    store.recordScheduledRun(session: r.sessionId, at: now, result: "started")
                    continue
                }
                guard case .success(let spec) = LaunchPlan.spec(s, stored: all, deliverOpening: true) else {
                    store.recordScheduledRun(session: r.sessionId, at: now, result: "refused: outside ~/Projects")
                    continue
                }
                do {
                    let ref = try RoofdRuntime(roofdPath: Daemon.selfPath(), dir: Paths.dir).start(spec)
                    s.runtimeId = ref.id
                    s.runtimeGroup = ref.groupId
                    s.launchedAt = now
                    s.openingSent = true                      // the holder delivers it
                    if s.lifecycle != .doNotUse { s.lifecycle = .idle }
                    store.save(s)
                    store.recordScheduledRun(session: r.sessionId, at: now, result: "started")
                } catch {
                    store.recordScheduledRun(session: r.sessionId, at: now, result: "failed: \(error)")
                }
            }
        }
    }
}
