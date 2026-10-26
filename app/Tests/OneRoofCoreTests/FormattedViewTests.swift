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
