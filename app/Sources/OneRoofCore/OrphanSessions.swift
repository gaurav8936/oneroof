import Foundation

/// LAB-2311 · roofd sessions no One Roof row owns. They came from three places: a relaunch that took `-2` and repointed
/// the row (the old holder and its `exec zsh` stayed), Remove / Delete forever (they closed only a herdr-era group,
/// always nil under roofd) and rows that went away while their shell lived on. Nothing ever closed them: roofd has
/// no idle timeout and the app's close rules work per row. These are the rules that close them.
public enum OrphanSessions {
    /// A shell no row claims is closed after this long untouched (and only at its prompt, which the app asks roofd).
    public static let quiet: TimeInterval = 120

    /// What Remove / Delete forever close in the runtime, by runtime id (not by group: roofd has none). Remove keeps a
    /// live agent running (the archived row still owns it, and ⇧⌘T brings it back); Delete forever ends it too, since
    /// nothing would own it afterwards. Otherwise the shell the agent left, else the row's runtime id (an exited holder
    /// still winding down leaves at once). Nil: the row never ran.
    public static func removeTarget(liveAgent: RuntimeID?, endedShell: RuntimeID?, runtimeId: RuntimeID?, forever: Bool) -> RuntimeID? {
        if let liveAgent { return forever ? liveAgent : nil }
        return endedShell ?? runtimeId
    }

    /// The session a launch replaces: the row's earlier runtime session when nothing runs in it now (a relaunch over an
    /// ended shell, or over an exited holder). Never a live agent, never a first launch.
    public static func replaced(liveAgent: RuntimeID?, runtimeId: RuntimeID?) -> RuntimeID? {
        liveAgent == nil ? runtimeId : nil
    }

    /// `roof-ab12cd34-3` → `roof-ab12cd34`: the name a session was launched under, before roofd made it unique.
    public static func baseName(_ id: RuntimeID) -> RuntimeID {
        guard let dash = id.lastIndex(of: "-"), id[id.index(after: dash)...].allSatisfy(\.isNumber),
              id.index(after: dash) < id.endIndex, id[..<dash].hasPrefix("roof-") else { return id }
        return String(id[..<dash])
    }

    /// The live sessions to sweep: One Roof's own (`roof-…`) plain shells that no stored row claims, untouched for
    /// `quiet`, with no terminal attached, and not a loop round's (loops are LAB-2310's: a round is never closed
    /// here, whatever its suffix). Agents are not swept: Board.merge adopts them as rows, which can be closed.
    /// - Parameter stored: every stored session, archived and loop rounds included (read fresh from the store: roofd
    ///   saves a loop round before it starts it).
    public static func sweep(snapshot: RuntimeSnapshot, stored: [Session], now: Date = Date(), quiet: TimeInterval = quiet) -> [RuntimeID] {
        let claimed = Set(stored.compactMap(\.runtimeId))
        let loops = Set(stored.filter(SessionScope.isLoop).flatMap { s in
            [Session.runtimeName(for: s.id)] + (s.runtimeId.map { [baseName($0)] } ?? [])
        })
        return snapshot.sessions.filter { s in
            guard !s.isAgent, s.id.hasPrefix("roof-"), !claimed.contains(s.id), !s.attached,
                  !loops.contains(baseName(s.id)), let at = s.activeAt else { return false }
            return now.timeIntervalSince(at) >= quiet
        }.map(\.id)
    }
}
