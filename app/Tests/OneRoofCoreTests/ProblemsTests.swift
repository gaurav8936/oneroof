import XCTest
@testable import OneRoofCore

/// S07 §1.8 Problems tab: ruff / swiftlint / tsc output, lint commands and the ruff quick fix.
final class ProblemsTests: XCTestCase {
    func testParseRuff() {
        let json = """
        [
          {"cell": null, "code": "F401", "end_location": {"column": 10, "row": 1},
           "filename": "/repo/app/main.py", "fix": {"applicability": "safe", "edits": [], "message": "Remove unused import: `os`"},
           "location": {"column": 8, "row": 1}, "message": "`os` imported but unused", "noqa_row": 1,
           "url": "https://docs.astral.sh/ruff/rules/unused-import"},
          {"cell": null, "code": "F821", "end_location": {"column": 9, "row": 14},
           "filename": "/repo/app/main.py", "fix": null, "location": {"column": 5, "row": 14},
           "message": "Undefined name `undefined_thing`", "noqa_row": 14, "url": null},
          {"cell": null, "code": null, "end_location": {"column": 1, "row": 20},
           "filename": "/repo/app/broken.py", "fix": null, "location": {"column": 12, "row": 19},
           "message": "SyntaxError: Expected ':', found newline", "noqa_row": null, "url": null}
        ]
        """
        let p = Problems.parseRuff(json: json)
        XCTAssertEqual(p.count, 3)
        XCTAssertEqual(p[0], Problem(path: "/repo/app/main.py", line: 1, column: 8, severity: .warning, code: "F401",
                                     message: "`os` imported but unused", tool: "ruff"))
        XCTAssertEqual(p[1].severity, .error)
        XCTAssertEqual(p[1].code, "F821")
        XCTAssertEqual(p[2].severity, .error)
        XCTAssertNil(p[2].code)
        XCTAssertEqual(p[2].line, 19)
        XCTAssertTrue(Problems.parseRuff(json: "[]").isEmpty)
        XCTAssertTrue(Problems.parseRuff(json: "not json").isEmpty)
    }

    func testParseSwiftlint() {
        let json = """
        [
          {"character": null, "file": "/repo/Sources/App/Model.swift", "line": 120,
           "reason": "Line should be 120 characters or less; currently it has 134 characters",
           "rule_id": "line_length", "severity": "Warning", "type": "Line Length"},
          {"character": 13, "file": "/repo/Sources/App/Model.swift", "line": 8,
           "reason": "Force casts should be avoided", "rule_id": "force_cast", "severity": "Error", "type": "Force Cast"}
        ]
        """
        let p = Problems.parseSwiftlint(json: json)
        XCTAssertEqual(p, [
            Problem(path: "/repo/Sources/App/Model.swift", line: 120, column: nil, severity: .warning, code: "line_length",
                    message: "Line should be 120 characters or less; currently it has 134 characters", tool: "swiftlint"),
            Problem(path: "/repo/Sources/App/Model.swift", line: 8, column: 13, severity: .error, code: "force_cast",
                    message: "Force casts should be avoided", tool: "swiftlint"),
        ])
    }

    func testParseTsc() {
        let text = """
        src/store.ts(12,5): error TS2322: Type 'string' is not assignable to type 'number'.
        src/components/List (copy).tsx(3,22): error TS2345: Argument of type '{ id: string; }' is not assignable to parameter of type 'Props'.
          Property 'name' is missing in type '{ id: string; }' but required in type 'Props'.
        error TS5023: Unknown compiler option 'foo'.
        src/old.ts(40,1): warning TS6133: 'x' is declared but its value is never read.

        Found 3 errors in 2 files.
        """
        let p = Problems.parseTsc(text: text)
        XCTAssertEqual(p.count, 3)
        XCTAssertEqual(p[0], Problem(path: "src/store.ts", line: 12, column: 5, severity: .error, code: "TS2322",
                                     message: "Type 'string' is not assignable to type 'number'.", tool: "tsc"))
        XCTAssertEqual(p[1].path, "src/components/List (copy).tsx")
        XCTAssertEqual(p[1].line, 3)
        XCTAssertEqual(p[1].column, 22)
        XCTAssertTrue(p[1].message.hasSuffix("\nProperty 'name' is missing in type '{ id: string; }' but required in type 'Props'."))
        XCTAssertEqual(p[2].severity, .warning)
        XCTAssertEqual(p[2].code, "TS6133")
    }

    func testCommandsAndQuickFix() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("oneroof-problems-\(UUID().uuidString)").path
        defer { try? FileManager.default.removeItem(atPath: root) }
        try FileManager.default.createDirectory(atPath: root, withIntermediateDirectories: true)

        let py = root + "/app/main.py"
        XCTAssertEqual(Problems.command(for: py, repoRoot: root)?.tool, "ruff")
        XCTAssertEqual(Problems.command(for: py, repoRoot: root)?.argv,
                       ["/usr/bin/env", "ruff", "check", "--output-format", "json", py])
        XCTAssertEqual(Problems.command(for: root + "/A.swift", repoRoot: root)?.argv,
                       ["/usr/bin/env", "swiftlint", "lint", "--quiet", "--reporter", "json", root + "/A.swift"])
        XCTAssertEqual(Problems.command(for: root + "/a.ts", repoRoot: root)?.argv,
                       ["/usr/bin/env", "npx", "--no", "tsc", "--noEmit", "--pretty", "false", root + "/a.ts"])
        XCTAssertNil(Problems.command(for: root + "/README.md", repoRoot: root))
        XCTAssertNil(Problems.command(for: root + "/a.js", repoRoot: root))

        let finding = Problem(path: py, line: 1, column: 8, severity: .warning, code: "F401", message: "", tool: "ruff")
        XCTAssertEqual(Problems.quickFix(for: finding, repoRoot: root), ["ruff", "check", "--fix", "--select", "F401", py])
        var syntax = finding
        syntax.code = nil
        XCTAssertNil(Problems.quickFix(for: syntax, repoRoot: root))
        var lint = finding
        lint.tool = "swiftlint"
        XCTAssertNil(Problems.quickFix(for: lint, repoRoot: root))

        // Repo-local tools win: .venv/bin/ruff, node_modules/.bin/tsc + tsconfig.json.
        let ruff = root + "/.venv/bin/ruff"
        let tsc = root + "/node_modules/.bin/tsc"
        for tool in [ruff, tsc] {
            try FileManager.default.createDirectory(atPath: (tool as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
            FileManager.default.createFile(atPath: tool, contents: Data("#!/bin/sh\n".utf8), attributes: [.posixPermissions: 0o755])
        }
        FileManager.default.createFile(atPath: root + "/tsconfig.json", contents: Data("{}".utf8))
        XCTAssertEqual(Problems.command(for: py, repoRoot: root)?.argv, [ruff, "check", "--output-format", "json", py])
        XCTAssertEqual(Problems.quickFix(for: finding, repoRoot: root)?.first, ruff)
        XCTAssertEqual(Problems.command(for: root + "/a.ts", repoRoot: root)?.argv,
                       [tsc, "--noEmit", "--pretty", "false", "-p", root + "/tsconfig.json"])
    }
}
