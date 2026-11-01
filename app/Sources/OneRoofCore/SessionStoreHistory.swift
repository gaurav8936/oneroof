import Foundation

// LAB-2046 · LAB-2048: the store layer History and the action log share. Additive and idempotent, run on every open
// without raising the store version: an older One Roof (1.9.x) still opens the file (LAB-1517 refuses a newer
// version), ignoring the new table, columns and indexes.

extension SessionStore {
    /// The columns 2.0.0 adds to `decisions` (LAB-2048).
    static let decisionExtraColumns = ["choices_json", "screen_json", "chosen", "session_name"]

    func ensureHistorySchema() throws {
        try exec("""
            CREATE TABLE IF NOT EXISTS history_sessions (session_id TEXT PRIMARY KEY, name TEXT NOT NULL, agent TEXT, account TEXT, is_loop INTEGER NOT NULL DEFAULT 0, first_at REAL, last_at REAL);
            CREATE TABLE IF NOT EXISTS history_events (id TEXT PRIMARY KEY, at REAL NOT NULL, session_id TEXT NOT NULL, kind TEXT NOT NULL, text TEXT NOT NULL);
            CREATE INDEX IF NOT EXISTS history_events_at ON history_events(at);
            CREATE INDEX IF NOT EXISTS feed_at ON feed(at);
            CREATE INDEX IF NOT EXISTS decisions_asked ON decisions(asked_at);
            CREATE INDEX IF NOT EXISTS decisions_answered ON decisions(answered_at);
            CREATE INDEX IF NOT EXISTS chapters_ended ON chapters(ended);
            """)
        let have = Set(query("PRAGMA table_info(decisions)", []) { $0.text(1) })
        for c in Self.decisionExtraColumns where !have.contains(c) { try exec("ALTER TABLE decisions ADD COLUMN \(c) TEXT") }
    }

    /// The indexes on a table (tests: the migration made them).
    public func indexNames(_ table: String) -> Set<String> {
        Set(query("SELECT name FROM sqlite_master WHERE type='index' AND tbl_name=?", [.text(table)]) { $0.text(0) })
    }
    public func columnNames(_ table: String) -> Set<String> {
        Set(query("PRAGMA table_info(\(table))", []) { $0.text(1) })
    }

    // MARK: History sessions (names kept after a session is deleted)

    /// Writes or refreshes a session's name, agent and account; keeps the first time it was seen and moves the last.
    public func saveHistorySession(_ s: HistorySession) {
        run("""
            INSERT INTO history_sessions(session_id,name,agent,account,is_loop,first_at,last_at) VALUES(?,?,?,?,?,?,?)
            ON CONFLICT(session_id) DO UPDATE SET name=excluded.name, agent=excluded.agent, account=excluded.account, is_loop=excluded.is_loop,
              first_at=COALESCE(MIN(history_sessions.first_at, excluded.first_at), history_sessions.first_at, excluded.first_at),
              last_at=COALESCE(MAX(history_sessions.last_at, excluded.last_at), history_sessions.last_at, excluded.last_at)
            """,
            [.text(s.id), .text(s.name), .text(s.agent.rawValue), .text(s.account), .int(s.isLoop ? 1 : 0),
             .real(s.firstAt?.timeIntervalSince1970), .real(s.lastAt?.timeIntervalSince1970)])
    }

    /// Moves a session's last-seen time only (it closed).
    public func touchHistorySession(_ id: String, lastAt: Date) {
        run("UPDATE history_sessions SET last_at=MAX(COALESCE(last_at, 0), ?) WHERE session_id=?", [.real(lastAt.timeIntervalSince1970), .text(id)])
    }

    public func historySessions() -> [String: HistorySession] {
        let rows = query("SELECT session_id,name,agent,account,is_loop,first_at,last_at FROM history_sessions", []) { r -> HistorySession? in
            guard let id = r.text(0), let name = r.text(1) else { return nil }
            return HistorySession(id: id, name: name, agent: r.text(2).flatMap(AgentKind.init(rawValue:)) ?? .claude, account: r.text(3),
                                  isLoop: r.int(4) == 1, firstAt: r.date(5), lastAt: r.date(6))
        }
        return Dictionary(rows.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
    }

    // MARK: Handover events

    /// Records a handover moment once (a stable id: seeing it again writes nothing).
    @discardableResult
    public func appendHistory(_ e: HistoryEvent) -> Bool {
        let before = query("SELECT 1 FROM history_events WHERE id=?", [.text(e.id)]) { $0.int(0) }.isEmpty
        run("INSERT OR IGNORE INTO history_events(id,at,session_id,kind,text) VALUES(?,?,?,?,?)",
            [.text(e.id), .real(e.at.timeIntervalSince1970), .text(e.sessionId), .text(e.kind.rawValue), .text(e.text)])
        return before
    }

    public func historyEvents(from: Date, to: Date) -> [HistoryEvent] {
        query("SELECT id,at,session_id,kind,text FROM history_events WHERE at >= ? AND at < ? ORDER BY at", [.real(from.timeIntervalSince1970), .real(to.timeIntervalSince1970)]) { r in
            guard let id = r.text(0), let at = r.date(1), let s = r.text(2), let k = r.text(3).flatMap(ScrollEntry.Kind.init(rawValue:)), let t = r.text(4) else { return nil }
            return HistoryEvent(id: id, at: at, sessionId: s, kind: k, text: t)
        }
    }

    /// Feed events in [from, to), oldest first (the `feed_at` index).
    public func feed(from: Date, to: Date) -> [FeedEvent] {
        query("SELECT id,at,session_id,kind,text,chapter FROM feed WHERE at >= ? AND at < ? ORDER BY at", [.real(from.timeIntervalSince1970), .real(to.timeIntervalSince1970)]) { r in
            guard let id = r.text(0).flatMap(UUID.init(uuidString:)), let at = r.date(1), let s = r.text(2),
                  let k = r.text(3).flatMap(FeedKind.init(rawValue:)), let text = r.text(4) else { return nil }
            return FeedEvent(id: id, at: at, sessionId: s, kind: k, text: text, chapter: r.int(5))
        }
    }

    /// Asks put to you in [from, to), oldest first (the `decisions_asked` index).
    public func decisions(askedFrom from: Date, to: Date) -> [Decision] {
        decisionRows("WHERE asked_at >= ? AND asked_at < ? ORDER BY asked_at", [.real(from.timeIntervalSince1970), .real(to.timeIntervalSince1970)]).map(\.0)
    }

    /// History's moments in [from, to) from the store, oldest first. `live` overlays what the app holds in memory
    /// (open asks, the newest feed events, finished steps of live sessions); `isLoop` says which sessions are loop rounds.
    public func historyEntries(from: Date, to: Date, live: (feed: [FeedEvent], chapters: [String: [Chapter]], decisions: [Decision]) = ([], [:], []),
                               isLoop: (String) -> Bool?) -> [ScrollEntry] {
        var feedById: [UUID: FeedEvent] = [:]
        for e in feed(from: from, to: to) { feedById[e.id] = e }
        for e in live.feed where e.at >= from && e.at < to { feedById[e.id] = e }
        var decById: [UUID: Decision] = [:]
        for d in decisions(askedFrom: from, to: to) { decById[d.id] = d }
        for d in live.decisions where d.askedAt >= from && d.askedAt < to { decById[d.id] = d }
        return HistoryFeed.entries(feed: Array(feedById.values), chapters: live.chapters, decisions: Array(decById.values),
                                   events: historyEvents(from: from, to: to), isLoop: isLoop)
    }

    // MARK: Action log (LAB-2048)

    /// Answered asks in the query's date range (by answer time), newest first, with the stored session names,
    /// filtered by session, answer and text. `limit` pages (200 by default).
    public func actionLog(_ q: ActionLogQuery, now: Date = Date(), names: [String: String] = [:], limit: Int = ActionLog.pageSize, offset: Int = 0) -> [ActionLogRow] {
        let b = q.range.bounds(now: now)
        var clause = "WHERE answer IS NOT NULL AND answered_at >= ? AND answered_at < ?"
        var args: [Value] = [.real(b.from.timeIntervalSince1970), .real(b.to.timeIntervalSince1970)]
        if !q.sessions.isEmpty {
            clause += " AND session_id IN (" + Array(repeating: "?", count: q.sessions.count).joined(separator: ",") + ")"
            args += q.sessions.sorted().map { .text($0) }
        }
        clause += " ORDER BY answered_at DESC, id"
        let remembered = historySessions()
        let rows = decisionRows(clause, args).map { d, stored in
            ActionLogRow(decision: d, sessionName: names[d.sessionId] ?? stored ?? remembered[d.sessionId]?.name, closed: names[d.sessionId] == nil)
        }
        return Array(q.apply(rows).dropFirst(offset).prefix(limit))
    }

    /// Every rule, newest first.
    public func decisionRulesNewestFirst() -> [DecisionRule] { decisionRules().sorted { $0.createdAt > $1.createdAt } }
}
