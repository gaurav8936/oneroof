import Foundation
import OneRoofCore

/// Loops (I12 slice 1, LAB-677): the engine that runs them, in roofd, with One Roof open or closed. Called from the
/// scheduler's 30 s tick. Loops always run here (never in the app, so the two never both run one), and only in the
/// roofd the app has configured (scheduler.json names the store and folders; a test daemon has none and runs nothing).
///
/// Each loop works in its own worktree `<repo>/.worktrees/loop-<name>` on branch `loop/<name>` (LoopWorktree), made
/// before the first check and never skipped: no check or round runs before it exists. Never in the live checkout;
/// nothing is pushed or merged. Each round is a session launched exactly as the scheduler launches one (LaunchPlan +
/// RoofdRuntime.start) with the round prompt as its opening message. When the round's agent is back at its prompt the
/// engine runs the check, appends the round to rounds.jsonl and lets LoopController decide: another round, wait, done
/// or stop. A round that needs you makes the loop "needs you" (Decisions shows the session's prompt as usual).
enum LoopEngine {
    private static let queue = DispatchQueue(label: "roofd.loops")
    private static let lock = NSLock()
    nonisolated(unsafe) private static var busy = false
    /// The roofd binary rounds are started with (tests point it at the built binary; in the daemon it is itself).
    nonisolated(unsafe) static var roofdPath: String?

    /// One pass over every loop, off the scheduler thread (a check can take minutes); skipped while one still runs.
    static func tick(config: Scheduler.Config?) {
        guard let c = config else { return }
        lock.lock()
        if busy { lock.unlock(); return }
        busy = true
        lock.unlock()
        queue.async {
            autoreleasepool { pass(c) }
            lock.lock(); busy = false; lock.unlock()
        }
    }

    static func pass(_ c: Scheduler.Config) {
        if let p = c.projects { Workspace.configure(root: p, shared: c.shared) }
        let store = LoopStore()
        let ids = ((try? FileManager.default.contentsOfDirectory(atPath: store.root)) ?? []).filter(Loop.validId)
        guard !ids.isEmpty else { return }
        let sessions = try? SessionStore(path: c.store)
        for id in ids.sorted() { step(id, store: store, sessions: sessions, again: true) }
    }

    /// The round session as its holder reports it. No answer from a socket that still accepts connections = busy for
    /// a moment, not gone.
    static func probe(_ runtimeId: String, now: Date) -> LoopRoundStatus {
        let path = Paths.session(runtimeId)
        if let info = try? Sock.holderRequest(path, ["op": "info"], timeout: 2) { return LoopRoundStatus.from(info: info, now: now) }
        if let fd = Sock.connect(path) { close(fd); return .working }
        return .gone
    }

    static func step(_ id: String, store: LoopStore, sessions: SessionStore?, again: Bool) {
        let now = Date()
        guard let loop = store.load(id) else { return }
        let rounds = store.rounds(id)
        let status: LoopRoundStatus = loop.run?.active.map { probe($0.runtimeId, now: now) } ?? .none
        let decision = LoopController.next(loop, rounds: rounds, now: now, round: status)
        switch decision {
        case .wait, .needsYou:
            _ = try? store.update(id) { $0 = LoopController.settle($0, decision) }

        case .runCheck:
            var l = loop
            if l.run == nil {
                guard let begun = try? store.update(id, { $0 = LoopController.begin($0, now: now) }) else { return }
                l = begun
            }
            // A check whose exit code cannot be read would "pass" every time: stop rather than guess.
            guard Foundations.childExitCodesReadable else {
                end(id, store: store, outcome: .stop("Stopped: " + LoopCheck.unreadableExitCodes), runId: l.run?.id)
                return
            }
            // The worktree comes first: the check, and every round, run only inside it (never before it exists).
            let wt: String
            do { wt = try LoopWorktree.ensure(repo: l.repoPath, id: l.id) } catch {
                end(id, store: store, outcome: .stop("Could not make the loop's worktree: \(error)"), runId: l.run?.id)
                return
            }
            let result = LoopCheck.run(l.check, in: wt, timeout: l.checkTimeout)
            var line: LoopRound?
            _ = try? store.update(id) { cur in
                guard cur.run?.id == l.run?.id else { return }       // stopped while the check ran: drop the result
                let (next, ln) = LoopController.checked(cur, result: result, now: Date())
                cur = next; line = ln
            }
            if let line { try? store.append(line, to: id) }
            if again, line != nil { step(id, store: store, sessions: sessions, again: false) }   // decide now, not in 30 s

        case .startRound(let n):
            startRound(loop, n: n, rounds: rounds, store: store, sessions: sessions)

        case .done, .stop:
            end(id, store: store, outcome: decision, runId: loop.run?.id)
        }
    }

    /// End the run: state done / failed and a line saying what was tried.
    static func end(_ id: String, store: LoopStore, outcome: LoopDecision, runId: String?) {
        let rounds = store.rounds(id)
        var line: LoopRound?
        _ = try? store.update(id) { cur in
            guard cur.run?.id == runId else { return }
            let (next, ln) = LoopController.ended(cur, rounds: rounds, outcome: outcome, now: Date())
            cur = next; line = ln
        }
        if let line { try? store.append(line, to: id) }
    }

    static func startRound(_ loop: Loop, n: Int, rounds: [LoopRound], store: LoopStore, sessions: SessionStore?) {
        let now = Date()
        // The owner may have paused or stopped it a moment ago.
        guard let fresh = store.load(loop.id), fresh.run?.id == loop.run?.id, fresh.state != .paused, fresh.run != nil else { return }
        let wt: String
        do { wt = try LoopWorktree.ensure(repo: fresh.repoPath, id: fresh.id) } catch {
            end(fresh.id, store: store, outcome: .stop("Could not make the loop's worktree: \(error)"), runId: fresh.run?.id)
            return
        }
        // Never a round outside the worktree: if it is not there now (removed a moment ago), stop and say so.
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: wt, isDirectory: &isDir), isDir.boolValue else {
            end(fresh.id, store: store, outcome: .stop("Stopped before round \(n): the loop's worktree \(wt) is not there"), runId: fresh.run?.id)
            return
        }
        // The last round's session is done with: close it unless someone is looking at it or it asks something.
        if let prev = rounds.last(where: { $0.runId == fresh.run?.id && $0.kind == .round })?.sessionId {
            closeIfIdle(Session.runtimeName(for: prev))
        }
        var s = Session(name: "\(fresh.name) · round \(n)", agent: fresh.agent, account: fresh.account, repoPath: wt,
                        objective: fresh.goal, openingMessage: LoopPrompt.render(fresh, round: n, rounds: rounds),
                        tags: ["loop:\(fresh.id)"], lifecycle: .idle, startInRepo: true, model: fresh.model)
        let stored = sessions?.all() ?? []
        guard case .success(let spec) = LaunchPlan.spec(s, stored: stored, deliverOpening: true) else {
            end(fresh.id, store: store, outcome: .stop("Refused: the loop's worktree \(wt) is outside the projects folder"), runId: fresh.run?.id)
            return
        }
        // Saved before it starts, so the app finds the row when the session appears (not a stray to adopt).
        s.runtimeId = spec.id
        s.launchedAt = now
        s.openingSent = true                                     // the holder delivers it
        sessions?.save(s)
        do {
            let ref = try RoofdRuntime(roofdPath: roofdPath ?? Daemon.selfPath(), dir: Paths.dir).start(spec)
            if ref.id != spec.id || ref.groupId != nil {
                s.runtimeId = ref.id; s.runtimeGroup = ref.groupId
                sessions?.save(s)
            }
            _ = try? store.update(fresh.id) { $0 = LoopController.started($0, n: n, sessionId: s.id, runtimeId: ref.id, now: now) }
        } catch {
            sessions?.delete(id: s.id)
            end(fresh.id, store: store, outcome: .stop("Round \(n) could not start: \(error)"), runId: fresh.run?.id)
        }
    }

    static func closeIfIdle(_ runtimeId: String) {
        let path = Paths.session(runtimeId)
        guard let info = try? Sock.holderRequest(path, ["op": "info"], timeout: 1), info["exited"] == nil else { return }
        guard (info["attached"] as? Bool) != true, (info["status"] as? String) != "blocked" else { return }
        _ = try? Sock.holderRequest(path, ["op": "close"], timeout: 2)
    }
}
