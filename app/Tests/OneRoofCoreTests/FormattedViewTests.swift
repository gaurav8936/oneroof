import XCTest
@testable import OneRoofCore

/// LAB-1286: the Table view's detectors (pipe tables, box tables), logical-line rejoin, transcript → items.
final class TerminalFormatTests: XCTestCase {
    func testPipeTableFoundBetweenText() {
        let raw = """
        Here are the results:
        | Name | Count | Note |
        |:-----|------:|:----:|
        | a    | 1     | x    |
        | b    | 22    |
        done.
        """
        let items = TerminalFormat.items(raw)
        XCTAssertEqual(items, [
            .text("Here are the results:"),
            .table(header: ["Name", "Count", "Note"], alignments: [.leading, .trailing, .center], rows: [["a", "1", "x"], ["b", "22", ""]]),
            .text("done."),
        ])
    }

    /// LAB-1299 (owner, 1.9.3): a box table printed right before the same table as Markdown. The bottom frame must
    /// end the box table; the Markdown lines are a table of their own, and no rows are merged.
    func testBoxTableThenMarkdownTableStaySeparate() {
        let raw = """
        ┌──────────┬─────────┬────────┐
        │ ID       │ Repo    │ Tests  │
        ├──────────┼─────────┼────────┤
        │ LAB-1280 │ oneroof │ 666    │
        │ LAB-1281 │ labs-ae │ 588    │
        │ LAB-1282 │ roofd   │ 437    │
        └──────────┴─────────┴────────┘
        | ID | Repo | Tests |
        |---|:---:|---:|
        | LAB-1280 | oneroof | 666 |
        | LAB-1281 | labs-ae | 588 |
        """
        XCTAssertEqual(TerminalFormat.items(raw), [
            .table(header: ["ID", "Repo", "Tests"], alignments: [.leading, .leading, .leading],
                   rows: [["LAB-1280", "oneroof", "666"], ["LAB-1281", "labs-ae", "588"], ["LAB-1282", "roofd", "437"]]),
            .table(header: ["ID", "Repo", "Tests"], alignments: [.leading, .center, .trailing],
                   rows: [["LAB-1280", "oneroof", "666"], ["LAB-1281", "labs-ae", "588"]]),
        ])
    }

    /// LAB-1299: the owner's 15-column sample (box form, then Markdown form) gives two 15 × 10 tables.
    func testOwnerFifteenColumnSample() throws {
        let h = ["ID", "Repo", "Branch", "Version", "Status", "Owner", "Tests", "Pass %", "Build s", "Size MB", "Notarized",
                 "Channel", "Released", "Lane", "Notes"]
        let rows = (0..<10).map { i in h.map { "\($0.prefix(3))\(i)" } }
        let w = h.indices.map { c in max(h[c].count, rows.map { $0[c].count }.max()!) }
        func rule(_ l: String, _ m: String, _ r: String) -> String {
            let parts: [String] = w.map { String(repeating: "─", count: $0 + 2) }
            return l + parts.joined(separator: m) + r
        }
        func row(_ cs: [String]) -> String {
            var parts: [String] = []
            for (i, c) in cs.enumerated() { parts.append(" " + c.padding(toLength: w[i], withPad: " ", startingAt: 0) + " ") }
            return "│" + parts.joined(separator: "│") + "│"
        }
        var box: [String] = [rule("┌", "┬", "┐"), row(h), rule("├", "┼", "┤")]
        box += rows.map(row)
        box.append(rule("└", "┴", "┘"))
        let mdHead: String = "| " + h.joined(separator: " | ") + " |"
        let mdRule: String = "|" + Array(repeating: "---", count: 15).joined(separator: "|") + "|"
        let mdRows: [String] = rows.map { (r: [String]) -> String in "| " + r.joined(separator: " | ") + " |" }
        var lines: [String] = ["Release summary."]
        lines += box
        lines += [mdHead, mdRule]
        lines += mdRows
        lines.append("% ")
        let items = TerminalFormat.items(lines.joined(separator: "\n"))
        let tables = items.compactMap { item -> ([String], [[String]])? in
            if case .table(let hd, _, let rs) = item { return (hd, rs) } else { return nil }
        }
        XCTAssertEqual(tables.count, 2)
        for t in tables {
            XCTAssertEqual(t.0, h)
            XCTAssertEqual(t.1, rows)
        }
    }

    /// An ASCII grid table (psql) ends at its last rule when a Markdown table follows.
    func testAsciiGridTableThenMarkdownTableStaySeparate() {
        let raw = "+----+----+\n| a  | b  |\n+----+----+\n| 1  | 2  |\n+----+----+\n| x | y |\n|---|---|\n| 3 | 4 |"
        XCTAssertEqual(TerminalFormat.items(raw), [
            .table(header: ["a", "b"], alignments: [.leading, .leading], rows: [["1", "2"]]),
            .table(header: ["x", "y"], alignments: [.leading, .leading], rows: [["3", "4"]]),
        ])
    }

    func testPipeLikeTextWithoutSeparatorStaysText() {
        XCTAssertEqual(TerminalFormat.items("grep a | sort | uniq\nnext"), [.text("grep a | sort | uniq\nnext")])
    }

    func testBoxTableWithRuleBetweenEveryRowMergesWrappedCells() {
        // How Claude Code draws a table in a narrow terminal: cells wrapped inside the box, a rule between rows.
        let raw = """
        ┌──────┬──────────────┐
        │ Key  │ What         │
        ├──────┼──────────────┤
        │ ⌘D   │ Split the    │
        │      │ pane right   │
        ├──────┼──────────────┤
        │ ⌘R   │ Raw stream   │
        └──────┴──────────────┘
        """
        XCTAssertEqual(TerminalFormat.items(raw), [
            .table(header: ["Key", "What"], alignments: [.leading, .leading],
                   rows: [["⌘D", "Split the pane right"], ["⌘R", "Raw stream"]]),
        ])
    }

    func testBoxTableWithHeaderRuleOnlyKeepsOneRowPerLine() {
        let raw = """
        ╔═══╦═══╗
        ║ a ║ b ║
        ╠═══╬═══╣
        ║ 1 ║ 2 ║
        ║ 3 ║ 4 ║
        ╚═══╩═══╝
        """
        XCTAssertEqual(TerminalFormat.items(raw), [
            .table(header: ["a", "b"], alignments: [.leading, .leading], rows: [["1", "2"], ["3", "4"]]),
        ])
    }

    func testAsciiGridTable() {
        let raw = "+----+-----+\n| id | name|\n+----+-----+\n| 1  | x   |\n+----+-----+\n(1 row)"
        let items = TerminalFormat.items(raw)
        XCTAssertEqual(items.first, .table(header: ["id", "name"], alignments: [.leading, .leading], rows: [["1", "x"]]))
        XCTAssertEqual(items.last, .text("(1 row)"))
    }

    func testOneColumnFrameStaysText() {
        let raw = "╭──────────────╮\n│ Welcome back │\n╰──────────────╯"
        XCTAssertEqual(TerminalFormat.items(raw), [.text(raw)])
    }

    func testBoxCellsKeepAsciiPipeInsideBoxCell() {
        XCTAssertEqual(TerminalFormat.boxCells("│ a | b │ c │"), ["a | b", "c"])
    }

    func testRuleDetection() {
        XCTAssertTrue(TerminalFormat.isBoxRule("├────┼────┤"))
        XCTAssertTrue(TerminalFormat.isBoxRule("+---+---+"))
        XCTAssertFalse(TerminalFormat.isBoxRule("---"))        // a Markdown rule, not a table
        XCTAssertFalse(TerminalFormat.isBoxRule("│ │"))
    }

    func testRejoinSoftWrappedRows() {
        // A 10-column terminal: rows exactly 10 wide continue on the next row.
        let rows = ["0123456789", "abcdef", "short", "0123456789", "0123456789", "x", ""]
        XCTAssertEqual(TerminalFormat.rejoin(rows, columns: 10), ["0123456789abcdef", "short", "01234567890123456789x", ""])
    }

    func testItemsRejoinBeforeFindingTables() {
        // A wide pipe table soft-wrapped at 12 columns is found again once its rows are rejoined.
        let logical = ["| a | b | c |", "|---|---|---|", "| 1 | 2 | 3 |"]
        let wrapped = logical.flatMap { l -> [String] in
            var out: [String] = []; var s = Substring(l)
            while s.count > 12 { out.append(String(s.prefix(12))); s = s.dropFirst(12) }
            out.append(String(s)); return out
        }
        XCTAssertEqual(TerminalFormat.items(wrapped.joined(separator: "\n"), columns: 12),
                       [.table(header: ["a", "b", "c"], alignments: [.leading, .leading, .leading], rows: [["1", "2", "3"]])])
    }
}

final class TranscriptFormatTests: XCTestCase {
    static let fixture = """
    {"type":"summary","summary":"x"}
    {"type":"user","message":{"role":"user","content":"Show me the table"},"uuid":"1"}
    {"type":"assistant","message":{"role":"assistant","content":[{"type":"thinking","thinking":"hmm"},{"type":"text","text":"Here it is:\\n\\n| A | B |\\n|---|---|\\n| 1 | 2 |"}]}}
    {"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","name":"Bash","input":{"command":"swift test\\n--parallel"}}]}}
    {"type":"user","message":{"role":"user","content":[{"type":"tool_result","content":"ok"}]}}
    {"type":"user","isMeta":true,"message":{"role":"user","content":"meta"}}
    {"type":"assistant","isSidechain":true,"message":{"role":"assistant","content":[{"type":"text","text":"subagent"}]}}
    {"type":"user","message":{"role":"user","content":"<command-name>/clear</command-name>"}}
    {"type":"user","message":{"role":"user","content":"<system-reminder>x</system-reminder>"}}
    {"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","name":"Edit","input":{"file_path":"/a/b.swift","old_string":"x"}}]}}
    {"type":"assistant","message":{"role":"ass
    """

    func testTranscriptToItems() {
        let items = TranscriptFormat.items(jsonl: Self.fixture)
        XCTAssertEqual(items, [
            .prompt("Show me the table"),
            .reply([.paragraph("Here it is:"), .table(header: ["A", "B"], alignments: [.leading, .leading], rows: [["1", "2"]])]),
            .tool("Ran: swift test …"),
            .tool("Command: /clear"),
            .tool("Edited: /a/b.swift"),
        ])
    }

    func testLimitKeepsNewest() {
        let items = TranscriptFormat.items(jsonl: Self.fixture, limit: 2)
        XCTAssertEqual(items, [.tool("Command: /clear"), .tool("Edited: /a/b.swift")])
    }

    func testToolLinesAreCompact() {
        XCTAssertEqual(TranscriptFormat.toolLine(name: "Bash", input: ["command": String(repeating: "x", count: 300)]).count, "Ran: ".count + 160)
        XCTAssertEqual(TranscriptFormat.toolLine(name: "TodoWrite", input: ["todos": []]), "Updated the to-do list")
        XCTAssertEqual(TranscriptFormat.toolLine(name: "mcp__x__y", input: ["q": "hello"]), "Used mcp__x__y: hello")
    }
}
