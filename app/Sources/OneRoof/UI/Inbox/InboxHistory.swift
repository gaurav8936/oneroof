import Foundation
import OneRoofCore

/// LAB-2352 · today's handled Inbox rows: settled in place while you stay on the Inbox, folded into Done today after.
/// Kept in UserDefaults for the day (a restart keeps today's list); the self-test never writes it.
@MainActor final class InboxHistory: ObservableObject {
    static let shared = InboxHistory()
    static let key = "inbox.doneToday.v1"

    @Published private(set) var rows: [InboxDone] = []

    private init() {
        guard !SelfTest.isActive, let data = UserDefaults.standard.data(forKey: Self.key),
              let saved = try? JSONDecoder().decode([InboxDone].self, from: data) else { return }
        rows = InboxSettle.fold(InboxSettle.today(saved), leaving: true)   // nothing is "in place" after a restart
    }

    /// Rows still in place (the list shows them where they were).
    var inPlace: [InboxDone] { rows.filter { !$0.folded } }
    /// Done today (newest first).
    var done: [InboxDone] { InboxSettle.today(rows).filter(\.folded) }

    func settle(_ d: InboxDone) { set(InboxSettle.add(d, to: rows)) }
    /// You left the Inbox: every settled row folds into Done today.
    func foldAll() { if rows.contains(where: { !$0.folded }) { set(InboxSettle.fold(rows, leaving: true)) } }
    /// Rows settled 10 minutes ago fold (and yesterday's drop) while you stay on the Inbox.
    func tick(now: Date = Date()) {
        let next = InboxSettle.fold(InboxSettle.today(rows, now: now), now: now, leaving: false)
        if next != rows { set(next) }
    }
    /// A row that came back (an Undo, a re-filed item) is no longer settled.
    func revive(_ ids: Set<String>) { if rows.contains(where: { ids.contains($0.id) && !$0.folded }) { set(rows.filter { !(ids.contains($0.id) && !$0.folded) }) } }

    private func set(_ next: [InboxDone]) {
        rows = next
        guard !SelfTest.isActive, let data = try? JSONEncoder().encode(next) else { return }
        UserDefaults.standard.set(data, forKey: Self.key)
    }
}
