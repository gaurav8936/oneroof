import Foundation
import SQLite3

/// The outcome ledger (LAB-1917): one SQLite file of every loop run and everything it produced, shared with the
/// Agentic Engineering kit (`ae loops ledger`, schema v1, `kit/loops/README.md`). It lives next to the loops:
/// `<shared>/loops/ledger.sqlite`. roofd writes a `runs` row when a One Roof loop run ends (engine `roofd`, id
/// `roofd-<loop>-<runId>`, the same key the kit's journal import uses) and a `commit` outcome for each commit the run
/// left on the loop's branch (staged: it waits for harvest into a PR, never pushed). The Loops dashboard reads it.
/// The journal and rounds.jsonl stay the raw log; nothing here deletes a row.
public final class LoopLedger {
    public static let schemaVersion = 1
    public let path: String
    private var db: OpaquePointer?

    public static func defaultPath(loopsRoot: String = LoopStore().root) -> String {
        (loopsRoot as NSString).appendingPathComponent("ledger.sqlite")
    }

    static let schema = """
    CREATE TABLE IF NOT EXISTS meta(key TEXT PRIMARY KEY, value TEXT);
    CREATE TABLE IF NOT EXISTS runs(id TEXT PRIMARY KEY, loop TEXT NOT NULL,
      engine TEXT NOT NULL CHECK(engine IN ('ae', 'roofd')),
      mode TEXT NOT NULL DEFAULT 'live' CHECK(mode IN ('live', 'shadow', 'dry')),
      started TEXT NOT NULL, ended TEXT, result TEXT, cost_usd REAL, summary TEXT, journal_ref TEXT);
    CREATE INDEX IF NOT EXISTS runs_loop ON runs(loop, started);
    CREATE TABLE IF NOT EXISTS outcomes(id INTEGER PRIMARY KEY AUTOINCREMENT, run_id TEXT NOT NULL REFERENCES runs(id),
      loop TEXT NOT NULL,
      kind TEXT NOT NULL CHECK(kind IN ('report', 'slack', 'issue', 'pr', 'commit', 'proposal', 'file', 'promotion')),
      link TEXT, title TEXT,
      status TEXT NOT NULL DEFAULT 'staged' CHECK(status IN ('staged', 'approved', 'rejected', 'applied', 'merged', 'expired')),
      decided_by TEXT, decided_at TEXT, created TEXT NOT NULL, detail TEXT);
    CREATE INDEX IF NOT EXISTS outcomes_loop ON outcomes(loop, created);
    CREATE INDEX IF NOT EXISTS outcomes_status ON outcomes(status);
    INSERT OR IGNORE INTO meta(key, value) VALUES('schema_version', '1');
    """

    public init(path: String = LoopLedger.defaultPath()) throws {
        self.path = path
        try FileManager.default.createDirectory(atPath: (path as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
        guard sqlite3_open(path, &db) == SQLITE_OK else { throw LoopStoreError("could not open the ledger at \(path)") }
        sqlite3_busy_timeout(db, 5000)
        try exec("PRAGMA journal_mode=WAL")
        try exec(Self.schema)
    }

    deinit { sqlite3_close(db) }

    private func exec(_ sql: String) throws {
        var err: UnsafeMutablePointer<CChar>?
        guard sqlite3_exec(db, sql, nil, nil, &err) == SQLITE_OK else {
            let m = err.map { String(cString: $0) } ?? "?"
            sqlite3_free(err)
            throw LoopStoreError("ledger: \(m)")
        }
    }

    private let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    private func run(_ sql: String, _ args: [Any?]) throws {
        var st: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &st, nil) == SQLITE_OK else { throw LoopStoreError("ledger: \(String(cString: sqlite3_errmsg(db)))") }
        defer { sqlite3_finalize(st) }
        for (i, a) in args.enumerated() {
            let n = Int32(i + 1)
            switch a {
            case let s as String: sqlite3_bind_text(st, n, s, -1, transient)
            case let d as Double: sqlite3_bind_double(st, n, d)
            case let v as Int: sqlite3_bind_int64(st, n, Int64(v))
            default: sqlite3_bind_null(st, n)
            }
        }
        guard sqlite3_step(st) == SQLITE_DONE else { throw LoopStoreError("ledger: \(String(cString: sqlite3_errmsg(db)))") }
    }

    private func rows(_ sql: String, _ args: [String] = []) -> [[String: String]] {
        var st: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &st, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(st) }
        for (i, a) in args.enumerated() { sqlite3_bind_text(st, Int32(i + 1), a, -1, transient) }
        var out: [[String: String]] = []
        while sqlite3_step(st) == SQLITE_ROW {
            var r: [String: String] = [:]
            for c in 0..<sqlite3_column_count(st) {
                let name = String(cString: sqlite3_column_name(st, c))
                if let t = sqlite3_column_text(st, c) { r[name] = String(cString: t) }
            }
            out.append(r)
        }
        return out
    }

    static func iso(_ d: Date) -> String {
        let f = ISO8601DateFormatter()
        f.timeZone = .current
        f.formatOptions = [.withInternetDateTime]
        return f.string(from: d)
    }

    /// One finished One Roof run (id `roofd-<loop>-<runId>`); replaces the row if it was written before.
    public func recordRun(loop: String, runId: String, started: Date, ended: Date, result: String, summary: String) throws {
        let id = "roofd-\(loop)-\(runId)"
        try run("""
            INSERT INTO runs(id, loop, engine, mode, started, ended, result, cost_usd, summary, journal_ref)
            VALUES(?, ?, 'roofd', 'live', ?, ?, ?, NULL, ?, ?)
            ON CONFLICT(id) DO UPDATE SET ended=excluded.ended, result=excluded.result, summary=excluded.summary
            """, [id, loop, Self.iso(started), Self.iso(ended), result, String(summary.prefix(300)), "\(loop)/rounds.jsonl"])
    }

    public func addOutcome(loop: String, runId: String, kind: String, title: String, link: String, status: String = "staged") throws {
        try run("INSERT INTO outcomes(run_id, loop, kind, link, title, status, created, detail) VALUES(?, ?, ?, ?, ?, ?, ?, '{}')",
                ["roofd-\(loop)-\(runId)", loop, kind, link, String(title.prefix(300)), status, Self.iso(Date())])
    }

    /// Per loop, what the dashboard shows (the same fields as `ae loops ledger --json`).
    public struct LoopSummary: Equatable, Sendable {
        public var loop: String
        public var runs: Int
        public var lastResult: String
        public var lastStarted: String
        public var lastMode: String
        public var engine: String
        public var streak: Int
        public var costUSD: Double
        public var outcomes: [String: Int]
        public var staged: Int
    }

    public func summary() -> [LoopSummary] {
        var out: [LoopSummary] = []
        for l in rows("SELECT DISTINCT loop FROM runs ORDER BY loop").compactMap({ $0["loop"] }) {
            let rs = rows("SELECT result, started, mode, engine FROM runs WHERE loop=? ORDER BY started DESC LIMIT 500", [l])
            let last = rs.first ?? [:]
            let streak = rs.prefix(while: { $0["result"] == last["result"] }).count
            var kinds: [String: Int] = [:]
            for r in rows("SELECT kind, COUNT(*) AS n FROM outcomes WHERE loop=? GROUP BY kind", [l]) {
                kinds[r["kind"] ?? "?"] = Int(r["n"] ?? "0") ?? 0
            }
            let staged = Int(rows("SELECT COUNT(*) AS n FROM outcomes WHERE loop=? AND status='staged'", [l]).first?["n"] ?? "0") ?? 0
            let cost = Double(rows("SELECT COALESCE(SUM(cost_usd), 0) AS c FROM runs WHERE loop=?", [l]).first?["c"] ?? "0") ?? 0
            out.append(LoopSummary(loop: l, runs: rs.count, lastResult: last["result"] ?? "", lastStarted: last["started"] ?? "",
                                   lastMode: last["mode"] ?? "", engine: last["engine"] ?? "", streak: streak, costUSD: cost,
                                   outcomes: kinds, staged: staged))
        }
        return out
    }

    /// Staged outcomes, newest first: what the morning view asks you about.
    public func staged(limit: Int = 100) -> [[String: String]] {
        rows("SELECT id, loop, kind, title, link, created FROM outcomes WHERE status='staged' ORDER BY created DESC LIMIT \(max(1, limit))")
    }

    // MARK: LAB-1919 · LAB-1941: outcomes one by one, and your decisions

    /// The statuses a decision may set (the kit's `ae loops ledger --decide`; `staged` is where every outcome starts).
    public static let decisions = ["approved", "rejected", "applied", "merged", "expired"]

    /// One row of `outcomes`, typed.
    public struct Outcome: Identifiable, Equatable, Sendable {
        public var id: Int
        public var runId: String
        public var loop: String
        public var kind: String
        public var link: String
        public var title: String
        public var status: String
        public var decidedBy: String?
        public var decidedAt: String?
        public var created: String
        /// The JSON detail, as text ("{}" when empty).
        public var detail: String

        /// A field of the JSON detail (`reason`, `branch`, `gate`, `pr` …), as text.
        public func detailValue(_ key: String) -> String? {
            guard let d = detail.data(using: .utf8), let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
                  let v = o[key] else { return nil }
            if let s = v as? String { return s }
            if let n = v as? NSNumber { return n.stringValue }
            return (try? JSONSerialization.data(withJSONObject: v)).flatMap { String(data: $0, encoding: .utf8) }
        }

        /// What `link` points at: `commit:<sha>@<branch>`, `branch:<branch>`, a URL, a file, or an issue key.
        public var target: LinkTarget { LinkTarget(link) }
    }

    public enum LinkTarget: Equatable, Sendable {
        case commit(sha: String, branch: String)
        case branch(String)
        case url(String)
        case file(String)
        case key(String)
        case none

        public init(_ link: String) {
            let l = link.trimmingCharacters(in: .whitespaces)
            if l.isEmpty { self = .none; return }
            if l.hasPrefix("commit:") {
                let rest = String(l.dropFirst(7))
                let parts = rest.split(separator: "@", maxSplits: 1).map(String.init)
                self = .commit(sha: parts.first ?? "", branch: parts.count > 1 ? parts[1] : ""); return
            }
            if l.hasPrefix("branch:") { self = .branch(String(l.dropFirst(7))); return }
            if l.hasPrefix("http://") || l.hasPrefix("https://") { self = .url(l); return }
            if l.hasPrefix("/") || l.hasPrefix("~") || l.hasPrefix("file:") { self = .file(l.hasPrefix("file:") ? String(l.dropFirst(5)) : l); return }
            self = .key(l)
        }
    }

    static func outcome(_ r: [String: String]) -> Outcome {
        Outcome(id: Int(r["id"] ?? "0") ?? 0, runId: r["run_id"] ?? "", loop: r["loop"] ?? "", kind: r["kind"] ?? "",
                link: r["link"] ?? "", title: r["title"] ?? "", status: r["status"] ?? "staged", decidedBy: r["decided_by"],
                decidedAt: r["decided_at"], created: r["created"] ?? "", detail: r["detail"] ?? "{}")
    }

    /// Outcomes, newest first, optionally of one loop and/or one status (the kit's `Ledger.outcomes`).
    public func outcomes(loop: String? = nil, status: String? = nil, limit: Int = 200) -> [Outcome] {
        var w: [String] = [], a: [String] = []
        if let loop { w.append("loop=?"); a.append(loop) }
        if let status { w.append("status=?"); a.append(status) }
        let q = "SELECT * FROM outcomes" + (w.isEmpty ? "" : " WHERE " + w.joined(separator: " AND ")) + " ORDER BY created DESC, id DESC LIMIT \(max(1, limit))"
        return rows(q, a).map(Self.outcome)
    }

    public func outcome(_ id: Int) -> Outcome? {
        rows("SELECT * FROM outcomes WHERE id=?", [String(id)]).first.map(Self.outcome)
    }

    /// Record a decision on an outcome (approved · rejected · applied · merged · expired), by whom and when, with an
    /// optional reason in its detail. The same row `ae loops ledger --decide <id> <status>` writes.
    @discardableResult
    public func decide(_ id: Int, status: String, by: String = NSUserName(), reason: String? = nil) throws -> Outcome {
        guard Self.decisions.contains(status) else {
            throw LoopStoreError("status must be one of \(Self.decisions.joined(separator: ", "))")
        }
        guard outcome(id) != nil else { throw LoopStoreError("no outcome \(id)") }
        try run("UPDATE outcomes SET status=?, decided_by=?, decided_at=? WHERE id=?", [status, by, Self.iso(Date()), id])
        if let reason, !reason.trimmingCharacters(in: .whitespaces).isEmpty { try setDetail(id, "reason", reason) }
        return outcome(id)!
    }

    /// The status alone (no decider): harvest puts a failed gate back to `staged`.
    func setStatus(_ id: Int, _ status: String) throws {
        try run("UPDATE outcomes SET status=?, decided_by=NULL, decided_at=NULL WHERE id=?", [status, id])
    }

    /// Set one key of an outcome's JSON detail (kept as JSON text, merged with what is there).
    public func setDetail(_ id: Int, _ key: String, _ value: String) throws {
        guard let o = outcome(id) else { throw LoopStoreError("no outcome \(id)") }
        var obj = (o.detail.data(using: .utf8).flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }) ?? [:]
        obj[key] = value
        let data = try JSONSerialization.data(withJSONObject: obj, options: [.sortedKeys])
        try run("UPDATE outcomes SET detail=? WHERE id=?", [String(data: data, encoding: .utf8) ?? "{}", id])
    }

    /// Add an outcome with a JSON detail; returns its id.
    @discardableResult
    public func add(loop: String, runId: String, kind: String, title: String, link: String, status: String = "staged",
                    detail: [String: String] = [:]) throws -> Int {
        let d = (try? JSONSerialization.data(withJSONObject: detail, options: [.sortedKeys])).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
        try run("INSERT INTO outcomes(run_id, loop, kind, link, title, status, created, detail) VALUES(?, ?, ?, ?, ?, ?, ?, ?)",
                [runId, loop, kind, link, String(title.prefix(300)), status, Self.iso(Date()), d])
        return Int(rows("SELECT last_insert_rowid() AS n").first?["n"] ?? "0") ?? 0
    }

    /// A run row (any engine), for the drill-down.
    public struct Run: Equatable, Sendable {
        public var id: String, loop: String, engine: String, mode: String, started: String, ended: String, result: String
        public var cost: Double?
        public var summary: String
    }

    public func runs(loop: String, limit: Int = 50) -> [Run] {
        rows("SELECT * FROM runs WHERE loop=? ORDER BY started DESC LIMIT \(max(1, limit))", [loop]).map {
            Run(id: $0["id"] ?? "", loop: $0["loop"] ?? "", engine: $0["engine"] ?? "", mode: $0["mode"] ?? "",
                started: $0["started"] ?? "", ended: $0["ended"] ?? "", result: $0["result"] ?? "",
                cost: $0["cost_usd"].flatMap(Double.init), summary: $0["summary"] ?? "")
        }
    }
}

/// LAB-1848: one message when a One Roof loop run stops on a limit or fails, through the kit's notifier (the
/// `notifier.command` of the Agentic Engineering kit config, Slack in this workspace), opening with the kit's
/// `loops.project` code. No command configured = nothing is sent (the Loops page still shows it).
public enum LoopAlert {
    /// `~/.config/ae/config.yaml` (or $AE_CONFIG): notifier.command and loops.project, read with a line reader
    /// (the kit owns the file; One Roof only reads these two keys).
    public static func settings(configPath: String? = nil) -> (command: String?, project: String) {
        let env = ProcessInfo.processInfo.environment
        let path = configPath ?? env["AE_CONFIG"] ?? (NSHomeDirectory() + "/.config/ae/config.yaml")
        guard let text = try? String(contentsOfFile: (path as NSString).expandingTildeInPath, encoding: .utf8) else { return (nil, "LOOPS") }
        var section = "", command: String?, project = "LOOPS"
        for raw in text.components(separatedBy: "\n") {
            let line = raw.components(separatedBy: " #").first ?? raw
            if let c = line.first, c != " ", c != "#" { section = String(line.prefix(while: { $0 != ":" })) }
            let t = line.trimmingCharacters(in: .whitespaces)
            func value(_ key: String) -> String? {
                guard t.hasPrefix(key + ":") else { return nil }
                let v = t.dropFirst(key.count + 1).trimmingCharacters(in: .whitespaces)
                return v.trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            }
            if section == "notifier", let v = value("command"), !v.isEmpty { command = v }
            if section == "loops", let v = value("project"), !v.isEmpty { project = v }
        }
        return (command, project)
    }

    public static func message(loop: Loop, reason: String, project: String) -> String {
        "\(project) · loop \(loop.id) stopped: \(reason)"
    }

    /// Send it (the command gets the message as its last argument). Returns whether a command ran and exited 0.
    @discardableResult
    public static func send(loop: Loop, reason: String, configPath: String? = nil) -> Bool {
        // Tests never message the owner: only an explicit config is used under XCTest.
        if configPath == nil, ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
            || NSClassFromString("XCTestCase") != nil { return false }
        let s = settings(configPath: configPath)
        guard let cmd = s.command else { return false }
        var parts = cmd.split(separator: " ").map(String.init)
        guard !parts.isEmpty else { return false }
        parts[0] = (parts[0] as NSString).expandingTildeInPath
        let p = Process()
        p.executableURL = URL(fileURLWithPath: parts[0])
        p.arguments = Array(parts.dropFirst()) + [message(loop: loop, reason: reason, project: s.project)]
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { return false }
        p.waitUntilExit()
        return p.terminationStatus == 0
    }
}
