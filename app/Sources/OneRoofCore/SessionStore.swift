import Foundation
import SQLite3

/// Planned and launched sessions, kept in one SQLite file:
/// ~/Library/Application Support/One Roof/sessions.sqlite. roofd is the source of truth for what is running.
public final class SessionStore: @unchecked Sendable {
    // Internal (not private) so the v2 tables in SessionStoreV2.swift can share the connection and lock.
    var db: OpaquePointer?
    let lock = NSLock()
    public let path: String

    public static var defaultPath: String {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("One Roof", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base.appendingPathComponent("sessions.sqlite").path
    }

    public init(path: String = SessionStore.defaultPath) throws {
        self.path = path
        guard sqlite3_open(path, &db) == SQLITE_OK else {
            throw NSError(domain: "SessionStore", code: 1, userInfo: [NSLocalizedDescriptionKey: "cannot open \(path)"])
        }
        sqlite3_busy_timeout(db, 3000)   // roofd's scheduler writes to the same file (WAL)
        try exec("PRAGMA journal_mode=WAL")
        try exec("CREATE TABLE IF NOT EXISTS sessions (id TEXT PRIMARY KEY, json TEXT NOT NULL, updated REAL NOT NULL)")
        try exec("CREATE TABLE IF NOT EXISTS objectives (id TEXT PRIMARY KEY, json TEXT NOT NULL, updated REAL NOT NULL)")
        try migrate()
    }

    deinit { sqlite3_close(db) }

    func exec(_ sql: String) throws {
        var err: UnsafeMutablePointer<CChar>?
        if sqlite3_exec(db, sql, nil, nil, &err) != SQLITE_OK {
            let msg = err.map { String(cString: $0) } ?? "sqlite error"
            sqlite3_free(err)
            throw NSError(domain: "SessionStore", code: 2, userInfo: [NSLocalizedDescriptionKey: msg])
        }
    }

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601; return e
    }()
    private static let decoder: JSONDecoder = {
        let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601; return d
    }()
    let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    public func all() -> [Session] {
        lock.lock(); defer { lock.unlock() }
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT json FROM sessions ORDER BY updated", -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }
        var out: [Session] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            guard let c = sqlite3_column_text(stmt, 0) else { continue }
            let json = String(cString: c)
            if let s = try? Self.decoder.decode(Session.self, from: Data(json.utf8)) { out.append(s) }
        }
        return out
    }

    public func save(_ s: Session) {
        lock.lock(); defer { lock.unlock() }
        guard let data = try? Self.encoder.encode(s) else { return }
        let json = String(decoding: data, as: UTF8.self)
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, "INSERT INTO sessions(id,json,updated) VALUES(?,?,?) ON CONFLICT(id) DO UPDATE SET json=excluded.json, updated=excluded.updated", -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, s.id, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 2, json, -1, SQLITE_TRANSIENT)
        sqlite3_bind_double(stmt, 3, Date().timeIntervalSince1970)
        sqlite3_step(stmt)
    }

    /// LAB-1516 · the app's save: keeps a newer launch already on disk (roofd's Scheduler or Loops started the session
    /// after the app last read it). Read and write happen in one transaction. Returns what was written.
    @discardableResult
    public func saveKeepingNewerLaunch(_ s: Session) -> Session {
        lock.lock()
        sqlite3_exec(db, "BEGIN IMMEDIATE", nil, nil, nil)
        let out = Session.keepingNewerLaunch(app: s, disk: rowLocked(s.id))
        lock.unlock()
        save(out)
        lock.lock(); sqlite3_exec(db, "COMMIT", nil, nil, nil); lock.unlock()
        return out
    }

    /// LAB-1516 · roofd's write when it starts a session: only the launch fields, read and written in one transaction,
    /// so the app's edits to the same row (name, notes, issues…) are never overwritten. A row that is not there yet is
    /// inserted whole (a brand-new loop round).
    public func updateLaunch(_ s: Session) {
        lock.lock()
        sqlite3_exec(db, "BEGIN IMMEDIATE", nil, nil, nil)
        var row = rowLocked(s.id) ?? s
        row.copyLaunch(from: s)
        lock.unlock()
        save(row)
        lock.lock(); sqlite3_exec(db, "COMMIT", nil, nil, nil); lock.unlock()
    }

    /// One row by id (the caller holds `lock`).
    private func rowLocked(_ id: String) -> Session? {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT json FROM sessions WHERE id=?", -1, &stmt, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, id, -1, SQLITE_TRANSIENT)
        guard sqlite3_step(stmt) == SQLITE_ROW, let c = sqlite3_column_text(stmt, 0) else { return nil }
        return try? Self.decoder.decode(Session.self, from: Data(String(cString: c).utf8))
    }

    public func delete(id: String) {
        lock.lock(); defer { lock.unlock() }
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, "DELETE FROM sessions WHERE id=?", -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, id, -1, SQLITE_TRANSIENT)
        sqlite3_step(stmt)
    }

    // MARK: Objectives

    public func allObjectives() -> [Objective] {
        lock.lock(); defer { lock.unlock() }
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT json FROM objectives ORDER BY updated", -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }
        var out: [Objective] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            guard let c = sqlite3_column_text(stmt, 0) else { continue }
            if let o = try? Self.decoder.decode(Objective.self, from: Data(String(cString: c).utf8)) { out.append(o) }
        }
        return out
    }

    public func save(_ o: Objective) {
        lock.lock(); defer { lock.unlock() }
        guard let data = try? Self.encoder.encode(o) else { return }
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, "INSERT INTO objectives(id,json,updated) VALUES(?,?,?) ON CONFLICT(id) DO UPDATE SET json=excluded.json, updated=excluded.updated", -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, o.id, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 2, String(decoding: data, as: UTF8.self), -1, SQLITE_TRANSIENT)
        sqlite3_bind_double(stmt, 3, Date().timeIntervalSince1970)
        sqlite3_step(stmt)
    }

    public func deleteObjective(id: String) {
        lock.lock(); defer { lock.unlock() }
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, "DELETE FROM objectives WHERE id=?", -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, id, -1, SQLITE_TRANSIENT)
        sqlite3_step(stmt)
    }
}
