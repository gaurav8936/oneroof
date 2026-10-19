import Foundation

/// One finding in the Inspector's Problems tab (S07 §1.8), from ruff, swiftlint or tsc.
public struct Problem: Equatable, Sendable {
    public var path: String
    /// 1-based.
    public var line: Int
    /// 1-based, when the tool gives one.
    public var column: Int?
    public var severity: Severity
    /// Rule id: F401, line_length, TS2322.
    public var code: String?
    public var message: String
    /// "ruff", "swiftlint" or "tsc".
    public var tool: String

    public enum Severity: String, Sendable { case error, warning, info }

    public init(path: String, line: Int, column: Int?, severity: Severity, code: String?, message: String, tool: String) {
        self.path = path; self.line = line; self.column = column; self.severity = severity
        self.code = code; self.message = message; self.tool = tool
    }
}

/// Parsers for the three linters' machine output, plus which command to run for a file. No LSP (Decision D7): the
/// app runs the command after a save and shows what comes back.
public enum Problems {
    // MARK: Parsers

    /// `ruff check --output-format json`: an array of {code, message, filename, location {row, column}}. Ruff has no
    /// severity, so syntax errors (code null) and the always-fatal families (E9, F63, F7, F82) read as errors and
    /// everything else as warnings.
    public static func parseRuff(json: String) -> [Problem] {
        jsonArray(json).compactMap { o in
            guard let file = o["filename"] as? String,
                  let loc = o["location"] as? [String: Any], let row = int(loc["row"]) else { return nil }
            let code = o["code"] as? String
            let fatal = code.map { c in ["E9", "F63", "F7", "F82"].contains { c.hasPrefix($0) } } ?? true
            return Problem(path: file, line: row, column: int(loc["column"]), severity: fatal ? .error : .warning,
                           code: code, message: o["message"] as? String ?? "", tool: "ruff")
        }
    }

    /// `swiftlint lint --reporter json`: an array of {file, line, character, severity "Warning"/"Error", rule_id, reason}.
    public static func parseSwiftlint(json: String) -> [Problem] {
        jsonArray(json).compactMap { o in
            guard let file = o["file"] as? String, let line = int(o["line"]) else { return nil }
            let sev = (o["severity"] as? String ?? "").lowercased()
            return Problem(path: file, line: line, column: int(o["character"]),
                           severity: sev == "error" ? .error : (sev == "warning" ? .warning : .info),
                           code: o["rule_id"] as? String, message: o["reason"] as? String ?? "", tool: "swiftlint")
        }
    }

    /// `tsc --noEmit --pretty false`: `path(line,col): error TS2322: message`, with indented continuation lines folded
    /// into the message. Lines without a location (global config errors) are skipped.
    public static func parseTsc(text: String) -> [Problem] {
        var out: [Problem] = []
        for raw in text.split(omittingEmptySubsequences: true, whereSeparator: \.isNewline) {
            let line = String(raw)
            if line.hasPrefix(" "), !out.isEmpty {
                out[out.count - 1].message += "\n" + line.trimmingCharacters(in: .whitespaces)
                continue
            }
            guard let p = tscLine(line) else { continue }
            out.append(p)
        }
        return out
    }

    static func tscLine(_ line: String) -> Problem? {
        // path(12,5): error TS2322: Type 'string' is not assignable to type 'number'.
        guard let marker = line.range(of: "): "),
              let open = line[..<marker.lowerBound].lastIndex(of: "(") else { return nil }
        let nums = line[line.index(after: open)..<marker.lowerBound].split(separator: ",")
        guard nums.count == 2, let row = Int(nums[0]), let col = Int(nums[1]) else { return nil }
        let rest = line[marker.upperBound...]
        guard let colon = rest.range(of: ": ") else { return nil }
        let head = rest[..<colon.lowerBound].split(separator: " ")   // "error TS2322"
        guard let sevWord = head.first else { return nil }
        let severity: Problem.Severity
        switch sevWord {
        case "error": severity = .error
        case "warning": severity = .warning
        case "message", "suggestion": severity = .info
        default: return nil
        }
        return Problem(path: String(line[..<open]), line: row, column: col, severity: severity,
                       code: head.count > 1 ? String(head[1]) : nil,
                       message: String(rest[colon.upperBound...]), tool: "tsc")
    }

    // MARK: Commands

    /// The lint command for a file: ruff for Python (the repo's .venv/bin/ruff, else ruff on PATH), swiftlint for
    /// Swift, tsc for TypeScript (the repo's node_modules/.bin/tsc, else npx). nil when no linter applies.
    public static func command(for path: String, repoRoot: String) -> (tool: String, argv: [String])? {
        let fm = FileManager.default
        switch SourceLanguage.detect(path: path) {
        case .python:
            let ruff = ruffPath(repoRoot: repoRoot, fileManager: fm).map { [$0] } ?? ["/usr/bin/env", "ruff"]
            return ("ruff", ruff + ["check", "--output-format", "json", path])
        case .swift:
            return ("swiftlint", ["/usr/bin/env", "swiftlint", "lint", "--quiet", "--reporter", "json", path])
        case .typescript:
            let local = (repoRoot as NSString).appendingPathComponent("node_modules/.bin/tsc")
            let tsc = fm.isExecutableFile(atPath: local) ? [local] : ["/usr/bin/env", "npx", "--no", "tsc"]
            let project = (repoRoot as NSString).appendingPathComponent("tsconfig.json")
            let target = fm.fileExists(atPath: project) ? ["-p", project] : [path]
            return ("tsc", tsc + ["--noEmit", "--pretty", "false"] + target)
        default:
            return nil
        }
    }

    /// "Quick fix" for a ruff finding: re-run ruff with --fix for that one rule on that file. nil for other tools
    /// and for syntax errors (no rule to select). argv[0] is the repo's .venv ruff when present, else "ruff".
    public static func quickFix(for p: Problem, repoRoot: String) -> [String]? {
        guard p.tool == "ruff", let code = p.code, !code.isEmpty else { return nil }
        let ruff = ruffPath(repoRoot: repoRoot, fileManager: .default) ?? "ruff"
        return [ruff, "check", "--fix", "--select", code, p.path]
    }

    static func ruffPath(repoRoot: String, fileManager fm: FileManager) -> String? {
        let venv = (repoRoot as NSString).appendingPathComponent(".venv/bin/ruff")
        return fm.isExecutableFile(atPath: venv) ? venv : nil
    }

    // MARK: JSON helpers

    static func jsonArray(_ json: String) -> [[String: Any]] {
        guard let data = json.data(using: .utf8),
              let any = try? JSONSerialization.jsonObject(with: data) else { return [] }
        return any as? [[String: Any]] ?? []
    }

    static func int(_ v: Any?) -> Int? {
        if let i = v as? Int { return i }
        if let d = v as? Double { return Int(d) }
        return nil
    }
}
