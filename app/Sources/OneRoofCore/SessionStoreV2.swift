import Foundation
import SQLite3

// The v2 tables (DATA_MODEL §2), added to sessions.sqlite by numbered, idempotent migrations (PRAGMA user_version).
// Everything is additive: v0.1's sessions and objectives tables are untouched.

/// A main window (DATA_MODEL `Workspace`; named so it doesn't clash with the `Workspace` path helpers).
public struct RoofWorkspace: Codable, Equatable, Identifiable, Sendable {
    /// The "Main" window the first migration creates and puts every v0.1 session in.
    public static let mainId = UUID(uuidString: "6D41494E-0000-4000-8000-000000000001")!

    public var id: UUID
    public var name: String
    public var colour: String?
    public var order: Int
    /// The window's layout, as JSON the app owns.
    public var layout: String?

    public init(id: UUID = UUID(), name: String, colour: String? = nil, order: Int = 0, layout: String? = nil) {
        self.id = id; self.name = name; self.colour = colour; self.order = order; self.layout = layout
    }
}

/// A comment on a changed line in Review changes, sent to the agent or kept as a note.
public struct ReviewComment: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var sessionId: String
    public var path: String
    public var line: Int
    public var text: String
    public var sentAt: Date?
    public var savedAsNote: Bool

    public init(id: UUID = UUID(), sessionId: String, path: String, line: Int, text: String, sentAt: Date? = nil, savedAsNote: Bool = false) {
        self.id = id; self.sessionId = sessionId; self.path = path; self.line = line; self.text = text; self.sentAt = sentAt; self.savedAsNote = savedAsNote
    }
}

extension SessionStore {
    /// Numbered migrations; index + 1 is the user_version after it runs. Append only, never edit a shipped one.
    static let migrations: [String] = [
        // 1 · v2 tables
        """
        CREATE TABLE IF NOT EXISTS workspaces (id TEXT PRIMARY KEY, name TEXT NOT NULL, colour TEXT, ord INTEGER NOT NULL DEFAULT 0, layout TEXT);
        CREATE TABLE IF NOT EXISTS session_workspace (session_id TEXT PRIMARY KEY, workspace_id TEXT NOT NULL);
        CREATE TABLE IF NOT EXISTS captions (session_id TEXT PRIMARY KEY, text TEXT NOT NULL, step INTEGER, steps INTEGER, now TEXT, updated_at REAL NOT NULL, source TEXT NOT NULL);
        CREATE TABLE IF NOT EXISTS chapters (session_id TEXT NOT NULL, idx INTEGER NOT NULL, title TEXT, summary TEXT, tool_calls INTEGER, started REAL, ended REAL, sb_from INTEGER, sb_to INTEGER, PRIMARY KEY(session_id, idx));
        CREATE TABLE IF NOT EXISTS feed (id TEXT PRIMARY KEY, at REAL NOT NULL, session_id TEXT NOT NULL, kind TEXT NOT NULL, text TEXT NOT NULL, chapter INTEGER);
        CREATE INDEX IF NOT EXISTS feed_at ON feed(at);
        CREATE TABLE IF NOT EXISTS decisions (id TEXT PRIMARY KEY, session_id TEXT NOT NULL, kind TEXT NOT NULL, command TEXT, plan_id TEXT, why TEXT, why_source TEXT, touches TEXT, risk TEXT, if_no TEXT, where_txt TEXT, asked_at REAL NOT NULL, answered_at REAL, answer TEXT, agent TEXT, path TEXT, pattern TEXT, repo TEXT, why_missing INTEGER NOT NULL DEFAULT 0, reply TEXT);
        CREATE INDEX IF NOT EXISTS decisions_pattern ON decisions(pattern, repo, asked_at);
        CREATE TABLE IF NOT EXISTS decision_rules (id TEXT PRIMARY KEY, pattern TEXT NOT NULL, repo TEXT NOT NULL, created_at REAL NOT NULL);
        CREATE TABLE IF NOT EXISTS subagents (id TEXT PRIMARY KEY, parent_id TEXT, session_id TEXT NOT NULL, name TEXT, model TEXT, asked TEXT, caption TEXT, tokens INTEGER, started REAL, ended REAL, status TEXT, inferred INTEGER NOT NULL DEFAULT 0);
        CREATE TABLE IF NOT EXISTS file_claims (path TEXT PRIMARY KEY, session_id TEXT NOT NULL, step INTEGER, since REAL NOT NULL);
        CREATE TABLE IF NOT EXISTS attributions (path TEXT NOT NULL, line_from INTEGER NOT NULL, line_to INTEGER NOT NULL, session_id TEXT, author TEXT NOT NULL, at REAL NOT NULL);
        CREATE TABLE IF NOT EXISTS schedules (session_id TEXT PRIMARY KEY, kind TEXT NOT NULL, hour INTEGER, minute INTEGER, last_run REAL, last_result TEXT, armed_at REAL);
        CREATE TABLE IF NOT EXISTS review_comments (id TEXT PRIMARY KEY, session_id TEXT NOT NULL, path TEXT NOT NULL, line INTEGER NOT NULL, text TEXT NOT NULL, sent_at REAL, saved_as_note INTEGER NOT NULL DEFAULT 0);
        INSERT INTO workspaces(id, name, ord) SELECT '\(RoofWorkspace.mainId.uuidString)', 'Main', 0 WHERE NOT EXISTS (SELECT 1 FROM workspaces);
        INSERT OR IGNORE INTO session_workspace(session_id, workspace_id) SELECT id, '\(RoofWorkspace.mainId.uuidString)' FROM sessions;
        """,
    ]

    /// LAB-1517: the refusal an older app gives a newer store.
    static func newerStore(_ found: Int, known: Int) -> NSError {
        NSError(domain: "SessionStore", code: 2, userInfo: [NSLocalizedDescriptionKey:
            "This session store was written by a newer One Roof (store version \(found), this app knows \(known)). Quit this copy and open One Roof from Applications."])
    }

    public var schemaVersion: Int {
        query("PRAGMA user_version", []) { $0.int(0) }.first ?? 0
    }

    /// Runs every migration newer than the file's user_version, each in its own transaction.
    func migrate() throws {
        let current = schemaVersion
        // LAB-1517: a store written by a newer One Roof is not opened by an older one (an old copy launched from
        // Spotlight or a release folder would read and write tables it does not know). Nothing is written.
        if current > Self.migrations.count { throw Self.newerStore(current, known: Self.migrations.count) }
        for (i, sql) in Self.migrations.enumerated() where i + 1 > current {
            try exec("BEGIN")
            do {
                try exec(sql)
                try exec("PRAGMA user_version = \(i + 1)")
                try exec("COMMIT")
            } catch {
                try? exec("ROLLBACK")
                throw error
            }
        }
    }

    // MARK: Statement helpers

    enum Value { case text(String?), int(Int?), real(Double?) }

    struct Row {
        let stmt: OpaquePointer?
        func text(_ i: Int32) -> String? { sqlite3_column_type(stmt, i) == SQLITE_NULL ? nil : sqlite3_column_text(stmt, i).map { String(cString: $0) } }
        func int(_ i: Int32) -> Int? { sqlite3_column_type(stmt, i) == SQLITE_NULL ? nil : Int(sqlite3_column_int64(stmt, i)) }
        func real(_ i: Int32) -> Double? { sqlite3_column_type(stmt, i) == SQLITE_NULL ? nil : sqlite3_column_double(stmt, i) }
        func date(_ i: Int32) -> Date? { real(i).map { Date(timeIntervalSince1970: $0) } }
    }

    private func bind(_ stmt: OpaquePointer?, _ args: [Value]) {
        for (i, a) in args.enumerated() {
            let idx = Int32(i + 1)
            switch a {
            case .text(let s?): sqlite3_bind_text(stmt, idx, s, -1, SQLITE_TRANSIENT)
            case .int(let n?): sqlite3_bind_int64(stmt, idx, Int64(n))
            case .real(let d?): sqlite3_bind_double(stmt, idx, d)
            default: sqlite3_bind_null(stmt, idx)
            }
        }
    }

    @discardableResult
    func run(_ sql: String, _ args: [Value]) -> Bool {
        lock.lock(); defer { lock.unlock() }
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return false }
        defer { sqlite3_finalize(stmt) }
        bind(stmt, args)
        return sqlite3_step(stmt) == SQLITE_DONE
    }

    func query<T>(_ sql: String, _ args: [Value], _ map: (Row) -> T?) -> [T] {
        lock.lock(); defer { lock.unlock() }
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }
        bind(stmt, args)
        var out: [T] = []
        while sqlite3_step(stmt) == SQLITE_ROW { if let v = map(Row(stmt: stmt)) { out.append(v) } }
        return out
    }

    private static func t(_ d: Date?) -> Value { .real(d?.timeIntervalSince1970) }

    // MARK: Workspaces (windows)

    public func allWorkspaces() -> [RoofWorkspace] {
        query("SELECT id, name, colour, ord, layout FROM workspaces ORDER BY ord, name", []) { r in
            guard let id = r.text(0).flatMap(UUID.init(uuidString:)), let name = r.text(1) else { return nil }
            return RoofWorkspace(id: id, name: name, colour: r.text(2), order: r.int(3) ?? 0, layout: r.text(4))
        }
    }

    public func save(_ w: RoofWorkspace) {
        run("INSERT INTO workspaces(id,name,colour,ord,layout) VALUES(?,?,?,?,?) ON CONFLICT(id) DO UPDATE SET name=excluded.name, colour=excluded.colour, ord=excluded.ord, layout=excluded.layout",
            [.text(w.id.uuidString), .text(w.name), .text(w.colour), .int(w.order), .text(w.layout)])
    }

    /// Deletes a window; its sessions go back to Main. Main itself can't be deleted.
    public func deleteWorkspace(id: UUID) {
        guard id != RoofWorkspace.mainId else { return }
        run("UPDATE session_workspace SET workspace_id=? WHERE workspace_id=?", [.text(RoofWorkspace.mainId.uuidString), .text(id.uuidString)])
        run("DELETE FROM workspaces WHERE id=?", [.text(id.uuidString)])
    }

    /// The window a session lives in (Main when it has never been moved).
    public func workspaceId(forSession id: String) -> UUID {
        query("SELECT workspace_id FROM session_workspace WHERE session_id=?", [.text(id)]) { $0.text(0).flatMap(UUID.init(uuidString:)) }.first
            ?? RoofWorkspace.mainId
    }

    public func move(session id: String, to workspace: UUID) {
        run("INSERT INTO session_workspace(session_id, workspace_id) VALUES(?,?) ON CONFLICT(session_id) DO UPDATE SET workspace_id=excluded.workspace_id",
            [.text(id), .text(workspace.uuidString)])
    }

    public func sessionWorkspaces() -> [String: UUID] {
        Dictionary(query("SELECT session_id, workspace_id FROM session_workspace", []) { r -> (String, UUID)? in
            guard let s = r.text(0), let w = r.text(1).flatMap(UUID.init(uuidString:)) else { return nil }
            return (s, w)
        }, uniquingKeysWith: { a, _ in a })
    }

    // MARK: Captions (latest only)

    public func saveCaption(_ c: Caption, session id: String) {
        run("INSERT INTO captions(session_id,text,step,steps,now,updated_at,source) VALUES(?,?,?,?,?,?,?) ON CONFLICT(session_id) DO UPDATE SET text=excluded.text, step=excluded.step, steps=excluded.steps, now=excluded.now, updated_at=excluded.updated_at, source=excluded.source",
            [.text(id), .text(c.text), .int(c.step), .int(c.steps), .text(c.now), Self.t(c.updatedAt), .text(c.source.rawValue)])
    }

    public func caption(session id: String) -> Caption? { captions(where: "WHERE session_id=?", [.text(id)])[id] }

    public func allCaptions() -> [String: Caption] { captions(where: "", []) }

    private func captions(where clause: String, _ args: [Value]) -> [String: Caption] {
        let rows = query("SELECT session_id,text,step,steps,now,updated_at,source FROM captions \(clause)", args) { r -> (String, Caption)? in
            guard let s = r.text(0), let text = r.text(1) else { return nil }
            return (s, Caption(text: text, step: r.int(2), steps: r.int(3), now: r.text(4), updatedAt: r.date(5) ?? Date(),
                               source: r.text(6).flatMap(CaptionSource.init(rawValue:)) ?? .heuristic))
        }
        return Dictionary(rows, uniquingKeysWith: { a, _ in a })
    }

    // MARK: Feed (7 days)

    public func append(_ e: FeedEvent) {
        run("INSERT OR IGNORE INTO feed(id,at,session_id,kind,text,chapter) VALUES(?,?,?,?,?,?)",
            [.text(e.id.uuidString), Self.t(e.at), .text(e.sessionId), .text(e.kind.rawValue), .text(e.text), .int(e.chapter)])
    }

    /// Newest first.
    public func recentFeed(limit: Int = FeedBuffer.capacity, since: Date? = nil) -> [FeedEvent] {
        query("SELECT id,at,session_id,kind,text,chapter FROM feed WHERE at >= ? ORDER BY at DESC LIMIT ?",
              [.real(since?.timeIntervalSince1970 ?? 0), .int(limit)]) { r in
            guard let id = r.text(0).flatMap(UUID.init(uuidString:)), let at = r.date(1), let s = r.text(2),
                  let k = r.text(3).flatMap(FeedKind.init(rawValue:)), let text = r.text(4) else { return nil }
            return FeedEvent(id: id, at: at, sessionId: s, kind: k, text: text, chapter: r.int(5))
        }
    }

    /// Drops feed events older than `days` (7 by default).
    public func pruneFeed(now: Date = Date(), days: Int = 7) {
        run("DELETE FROM feed WHERE at < ?", [.real(now.addingTimeInterval(-Double(days) * 86_400).timeIntervalSince1970)])
    }

    // MARK: Decisions

    public func save(_ d: Decision) {
        run("""
            INSERT INTO decisions(id,session_id,kind,command,plan_id,why,why_source,touches,risk,if_no,where_txt,asked_at,answered_at,answer,agent,path,pattern,repo,why_missing,reply)
            VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)
            ON CONFLICT(id) DO UPDATE SET kind=excluded.kind, command=excluded.command, plan_id=excluded.plan_id, why=excluded.why, why_source=excluded.why_source,
              touches=excluded.touches, risk=excluded.risk, if_no=excluded.if_no, where_txt=excluded.where_txt, answered_at=excluded.answered_at,
              answer=excluded.answer, path=excluded.path, pattern=excluded.pattern, repo=excluded.repo, why_missing=excluded.why_missing, reply=excluded.reply
            """,
            [.text(d.id.uuidString), .text(d.sessionId), .text(d.kind.rawValue), .text(d.command), .text(d.planId?.uuidString), .text(d.why),
             .text(d.whySource.rawValue), .text(d.touches), .text(d.risk.rawValue), .text(d.ifNo), .text(d.where_), Self.t(d.askedAt),
             Self.t(d.answeredAt), .text(d.answer?.rawValue), .text(d.agent.rawValue), .text(d.path), .text(d.pattern), .text(d.repo),
             .int(d.whyMissing ? 1 : 0), .text(d.replyText)])
    }

    /// Records an answer with the time (every answer is written).
    public func answer(decision id: UUID, _ a: Answer, reply: String? = nil, at: Date = Date()) {
        run("UPDATE decisions SET answer=?, answered_at=?, reply=? WHERE id=?", [.text(a.rawValue), Self.t(at), .text(reply), .text(id.uuidString)])
    }

    private static let decisionColumns = "id,session_id,kind,command,plan_id,why,why_source,touches,risk,if_no,where_txt,asked_at,answered_at,answer,agent,path,pattern,repo,why_missing,reply"

    private func decisions(_ clause: String, _ args: [Value]) -> [Decision] {
        query("SELECT \(Self.decisionColumns) FROM decisions \(clause)", args) { r in
            guard let id = r.text(0).flatMap(UUID.init(uuidString:)), let s = r.text(1),
                  let kind = r.text(2).flatMap(DecisionKind.init(rawValue:)), let asked = r.date(11) else { return nil }
            return Decision(id: id, sessionId: s, agent: r.text(14).flatMap(AgentKind.init(rawValue:)) ?? .claude, kind: kind,
                            command: r.text(3), path: r.text(15), planId: r.text(4).flatMap(UUID.init(uuidString:)), why: r.text(5) ?? "",
                            whySource: r.text(6).flatMap(CaptionSource.init(rawValue:)) ?? .heuristic, whyMissing: r.int(18) == 1,
                            touches: r.text(7) ?? "", risk: r.text(8).flatMap(Risk.init(rawValue:)) ?? .high, ifNo: r.text(9) ?? "",
                            where_: r.text(10) ?? "", pattern: r.text(16) ?? "", repo: r.text(17) ?? "", askedAt: asked,
                            answeredAt: r.date(12), answer: r.text(13).flatMap(Answer.init(rawValue:)), replyText: r.text(19))
        }
    }

    /// Unanswered decisions, oldest first (the longest-waiting agent first), with history filled in.
    public func openDecisions(now: Date = Date()) -> [Decision] {
        decisions("WHERE answer IS NULL ORDER BY asked_at", []).map { d in
            var d = d; d.history = decisionHistory(pattern: d.pattern, repo: d.repo, now: now); return d
        }
    }

    public func decision(id: UUID) -> Decision? { decisions("WHERE id=?", [.text(id.uuidString)]).first }

    /// Decisions asked since `date`, newest first (history list, "Earlier today · n decided").
    public func decisions(since date: Date) -> [Decision] {
        decisions("WHERE asked_at >= ? ORDER BY asked_at DESC", [.real(date.timeIntervalSince1970)])
    }

    /// Same pattern in the same repo over the last 7 days; suggests a rule after 3 allows and no denies.
    public func decisionHistory(pattern: String, repo: String, now: Date = Date()) -> DecisionHistory {
        let counts = query("""
            SELECT SUM(CASE WHEN answer IN ('allowOnce','always') THEN 1 ELSE 0 END), SUM(CASE WHEN answer IN ('deny','reply') THEN 1 ELSE 0 END)
            FROM decisions WHERE pattern=? AND repo=? AND asked_at >= ? AND answer IS NOT NULL
            """, [.text(pattern), .text(repo), .real(now.addingTimeInterval(-7 * 86_400).timeIntervalSince1970)]) { ($0.int(0) ?? 0, $0.int(1) ?? 0) }.first ?? (0, 0)
        return DecisionHistory(similarAllowed: counts.0, similarDenied: counts.1,
                               ruleSuggestion: counts.0 >= 3 && counts.1 == 0 ? "Always allow \(pattern) in \(repo)" : nil)
    }

    public func save(_ rule: DecisionRule) {
        run("INSERT OR REPLACE INTO decision_rules(id,pattern,repo,created_at) VALUES(?,?,?,?)",
            [.text(rule.id.uuidString), .text(rule.pattern), .text(rule.repo), Self.t(rule.createdAt)])
    }

    public func decisionRules() -> [DecisionRule] {
        query("SELECT id,pattern,repo,created_at FROM decision_rules ORDER BY created_at", []) { r in
            guard let id = r.text(0).flatMap(UUID.init(uuidString:)), let p = r.text(1), let repo = r.text(2) else { return nil }
            return DecisionRule(id: id, pattern: p, repo: repo, createdAt: r.date(3) ?? Date())
        }
    }

    public func deleteRule(id: UUID) { run("DELETE FROM decision_rules WHERE id=?", [.text(id.uuidString)]) }

    // MARK: Review comments

    public func save(_ c: ReviewComment) {
        run("INSERT OR REPLACE INTO review_comments(id,session_id,path,line,text,sent_at,saved_as_note) VALUES(?,?,?,?,?,?,?)",
            [.text(c.id.uuidString), .text(c.sessionId), .text(c.path), .int(c.line), .text(c.text), Self.t(c.sentAt), .int(c.savedAsNote ? 1 : 0)])
    }

    public func reviewComments(session id: String) -> [ReviewComment] {
        query("SELECT id,session_id,path,line,text,sent_at,saved_as_note FROM review_comments WHERE session_id=? ORDER BY path, line", [.text(id)]) { r in
            guard let cid = r.text(0).flatMap(UUID.init(uuidString:)), let s = r.text(1), let p = r.text(2), let text = r.text(4) else { return nil }
            return ReviewComment(id: cid, sessionId: s, path: p, line: r.int(3) ?? 0, text: text, sentAt: r.date(5), savedAsNote: r.int(6) == 1)
        }
    }

    public func deleteReviewComment(id: UUID) { run("DELETE FROM review_comments WHERE id=?", [.text(id.uuidString)]) }

    // MARK: Schedules

    public func save(_ s: ScheduleRecord) {
        let time = s.schedule.stored
        run("INSERT OR REPLACE INTO schedules(session_id,kind,hour,minute,last_run,last_result,armed_at) VALUES(?,?,?,?,?,?,?)",
            [.text(s.sessionId), .text(s.schedule.kind), .int(time.hour), .int(time.minute), Self.t(s.lastRun), .text(s.lastResult), Self.t(s.armedAt)])
    }

    public func schedules() -> [ScheduleRecord] {
        query("SELECT session_id,kind,hour,minute,last_run,last_result,armed_at FROM schedules ORDER BY session_id", []) { r in
            guard let s = r.text(0), let k = r.text(1), let sch = Schedule(kind: k, hour: r.int(2), minute: r.int(3)) else { return nil }
            return ScheduleRecord(sessionId: s, schedule: sch, armedAt: r.date(6) ?? Date(timeIntervalSince1970: 0), lastRun: r.date(4), lastResult: r.text(5))
        }
    }

    public func schedule(session id: String) -> ScheduleRecord? { schedules().first { $0.sessionId == id } }

    public func recordScheduledRun(session id: String, at: Date = Date(), result: String) {
        run("UPDATE schedules SET last_run=?, last_result=? WHERE session_id=?", [Self.t(at), .text(result), .text(id)])
    }

    public func deleteSchedule(session id: String) { run("DELETE FROM schedules WHERE session_id=?", [.text(id)]) }
}
