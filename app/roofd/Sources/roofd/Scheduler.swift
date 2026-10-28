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
                autoreleasepool { tick() }   // this thread never drains a pool on its own (LAB-310)
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
        // Loops (LAB-677) always run here, whatever Allow scheduled runs says: the app never runs them, so they can
        // never run twice. They run on their own queue (a check can take minutes) and need only a configured roofd.
        LoopEngine.tick(config: config())
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
                if let id = s.runtimeId, live.contains(id) {
                    if case .every = r.schedule {
                        // A loop round on a live session (LAB-254): its message again, once the agent waits.
                        loopRound(r, session: s, holder: id, store: store, now: now)
                    } else {                                   // already running: nothing to start
                        store.recordScheduledRun(session: r.sessionId, at: now, result: "started")
                    }
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
                    store.updateLaunch(s)                     // LAB-1516: launch fields only, never the app's edits
                    store.recordScheduledRun(session: r.sessionId, at: now, result: "started")
                } catch {
                    store.recordScheduledRun(session: r.sessionId, at: now, result: "failed: \(error)")
                }
            }
        }
    }

    /// Send a loop's message to a live session when its agent is at its prompt; otherwise wait (next tick) or, a whole
    /// interval late, give the round up.
    static func loopRound(_ r: ScheduleRecord, session s: Session, holder id: String, store: SessionStore, now: Date) {
        let text = (s.openingMessage.isEmpty ? s.objective : s.openingMessage).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { store.recordScheduledRun(session: r.sessionId, at: now, result: "skipped: no message"); return }
        let info = try? Sock.holderRequest(Paths.session(id), ["op": "info"], timeout: 1)
        switch ScheduleClock.liveRound(r, status: info?["status"] as? String, ready: info?["ready"] as? Bool ?? false, now: now) {
        case .wait:
            return
        case .skip:
            store.recordScheduledRun(session: r.sessionId, at: now, result: "skipped: busy")
        case .send:
            do {
                _ = try Sock.holderRequest(Paths.session(id), ["op": "input", "text": text], timeout: 2)
                Thread.sleep(forTimeInterval: 0.2)           // Enter separately: a submit, not a newline in a paste
                _ = try Sock.holderRequest(Paths.session(id), ["op": "input", "submit": true], timeout: 2)
                store.recordScheduledRun(session: r.sessionId, at: now, result: "sent")
            } catch {
                store.recordScheduledRun(session: r.sessionId, at: now, result: "failed: \(error)")
            }
        }
    }
}