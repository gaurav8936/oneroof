import AppKit
import Combine
import OneRoofCore

/// LAB-1866 · LAB-1919 · LAB-1941 · LAB-1867 · LAB-1921: what the loops need from you, at the model level, so Needs
/// you, its badge (rail, toolbar row, menu bar, Dock) and the Loops page agree. Loop items are never sessions
/// (LAB-1933): they come from the loop files and the outcome ledger, read every 15 s off the main thread.
final class LoopInboxState: ObservableObject {
    static let shared = LoopInboxState()
    /// Failures, asks and Today (staged outcomes), as Needs you lists them.
    @Published private(set) var items: [LoopInbox.Item] = []
    /// The loop the Loops page should open (from a Needs you item or the dashboard).
    @Published var focus: String?
    /// "Make this a loop" from a session: the editor opens with this draft.
    @Published var draftRequest: Loop?
    /// The last action's result, in plain words (shown on the item's detail).
    @Published var lastResult: [String: String] = [:]
    /// Items being worked on (a harvest can take minutes).
    @Published var busy: Set<String> = []

    let io = DispatchQueue(label: "oneroof.loops.inbox")
    /// LAB-2042 · self-test only (ONEROOF_SELFTEST_INBOX): loop items shown as if a loop had filed them.
    private(set) var selfTestSeed: [LoopInbox.Item] = []
    func seedForSelfTest(_ extra: [LoopInbox.Item]) { selfTestSeed = extra; items += extra.filter { e in !items.contains { $0.id == e.id } } }

    /// The store the inbox reads: Built-in and kit-file loops only for their titles (no repo lookup on this path).
    static func store() -> LoopStore {
        let root = LoopStore.defaultRoot
        return LoopStore(root: root, builtIns: LoopBuiltIns.load(repoPath: Workspace.projectsRoot),
                         fileLoops: LoopFiles.load(folder: root, repoPath: Workspace.projectsRoot))
    }

    static func ledger(_ root: String = LoopStore.defaultRoot) -> LoopLedger? {
        let path = LoopLedger.defaultPath(loopsRoot: root)
        return FileManager.default.fileExists(atPath: path) ? try? LoopLedger(path: path) : nil
    }

    /// Re-read the loops and the ledger; `done` runs on main when the list changed.
    func refresh(_ done: (() -> Void)? = nil) {
        io.async { [weak self] in
            let s = Self.store()
            let loops = s.all()
            let staged = Self.ledger(s.root)?.outcomes(status: "staged", limit: 300) ?? []
            let found = LoopInbox.items(loops: loops, staged: staged)
            DispatchQueue.main.async {
                guard let self else { return }
                let next = found + self.selfTestSeed   // LAB-2042: ONEROOF_SELFTEST_INBOX's loop item (self-test only)
                if self.items != next { self.items = next; done?() }
            }
        }
    }

    // MARK: Actions (each writes through LoopStore / the ledger, then re-reads)

    func runAgain(_ loopId: String, then: @escaping () -> Void = {}) {
        perform(loopId, "Run again", then) { try Self.store().update(loopId) { $0 = LoopController.runNow($0) }; return "Running again: roofd starts it within 30 s." }
    }

    func markSeen(_ loopId: String, then: @escaping () -> Void = {}) {
        perform(loopId, "Mark seen", then) { try Self.store().update(loopId) { $0.failureSeenAt = Date() }; return "Marked seen." }
    }

    /// Approve / apply / dismiss staged outcomes (the same rows `ae loops ledger --decide` writes).
    func decide(_ item: LoopInbox.Item, _ status: String, reason: String? = nil, then: @escaping () -> Void = {}) {
        perform(item.id, status, then) {
            guard let led = Self.ledger() else { throw LoopStoreError("no outcome ledger yet") }
            for id in item.outcomeIds { try led.decide(id, status: status, by: NSUserName(), reason: reason) }
            return status == "rejected" ? "Dismissed" + (reason.map { ": " + $0 } ?? ".") : "Recorded as \(status)."
        }
    }

    /// LAB-1867: approve the loop branch's work, gate it (tests + judge) and open the PR.
    func approveAndOpenPR(_ item: LoopInbox.Item, then: @escaping () -> Void = {}) {
        perform(item.id, "Approve", then) {
            let s = Self.store()
            guard let loop = LoopStore().load(item.loopId) ?? s.load(item.loopId) else { throw LoopStoreError("no loop \(item.loopId)") }
            guard let led = Self.ledger(s.root) else { throw LoopStoreError("no outcome ledger yet") }
            switch LoopHarvest.approveAndOpen(loop: loop, outcomes: item.outcomes, ledger: led, tools: .live()) {
            case .opened(let url, let gate): return "PR opened: \(url) (\(gate.summary))"
            case .refused(let why, let gate): return "No PR: \(why)" + (gate.map { " (\($0.summary))" } ?? "") + " It stays in Today."
            }
        }
    }

    private func perform(_ key: String, _ what: String, _ then: @escaping () -> Void, _ body: @escaping () throws -> String) {
        busy.insert(key)
        io.async { [weak self] in
            let msg: String
            do { msg = try body() } catch { msg = "\(what): \(error)" }
            DispatchQueue.main.async {
                guard let self else { return }
                self.busy.remove(key)
                self.lastResult[key] = msg
                self.refresh(then)
                then()
            }
        }
    }
}

extension AppModel {
    var loopInbox: [LoopInbox.Item] { LoopInboxState.shared.items }

    /// Re-read the loop items and keep every badge in step with them.
    func refreshLoopInbox() {
        LoopInboxState.shared.refresh { [weak self] in
            self?.objectWillChange.send()
            self?.updateDockBadge()
        }
    }

    /// Open a loop on the Loops page.
    func openLoop(_ id: String, in w: WindowState? = nil) {
        LoopInboxState.shared.focus = id
        show(.loops, in: w)
    }

    /// LAB-1921 · "Make this a loop": the session's repo, objective and opening message become a new loop's draft.
    func makeLoop(from item: BoardItem, in w: WindowState? = nil) {
        let s = item.session
        let repo = Workspace.repoRoot(for: s.repoPath) ?? s.repoPath
        var l = Loop(id: "", name: Loop.slug(s.name), repoPath: repo)
        l.goal = s.objective.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? s.name : s.objective
        l.roundPrompt = s.openingMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        l.agent = s.agent.isAgent ? s.agent : .claude
        l.model = s.model
        LoopInboxState.shared.draftRequest = l
        show(.loops, in: w)
    }
}
