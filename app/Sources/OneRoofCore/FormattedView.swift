import Foundation

/// LAB-1286 (1.9.3): what a terminal pane shows in its **Table** view (it replaced Wrap, LAB-657): the session's output
/// formatted, prose wrapping to the pane, every table a real table. Two sources:
///
/// - a Claude session's transcript (`TranscriptFormat`): each prompt and each reply's original Markdown, before the
///   terminal hard-wrapped it, with one compact line per tool call;
/// - any other terminal's text (`TerminalFormat`): its logical lines, with Markdown pipe tables and box-drawing tables
///   found and turned into tables; everything else stays monospace text that wraps.
public enum FormattedItem: Equatable, Sendable {
    /// The owner's prompt (Markdown).
    case prompt(String)
    /// One reply of the agent, as Markdown blocks.
    case reply([MarkdownBlock])
    /// One compact line for a tool call ("Ran: swift test").
    case tool(String)
    /// A run of terminal text (monospace, wraps at the pane's width).
    case text(String)
    /// A table found in terminal text.
    case table(header: [String], alignments: [MarkdownAlignment], rows: [[String]])
}

// MARK: Terminal text

public enum TerminalFormat {
    /// The terminal's text as items: tables found, the rest kept as text runs. `columns` (the terminal's width in
    /// cells) rejoins rows the terminal soft-wrapped; pass nil when the text is already logical lines (libghostty's
    /// `read_text` joins soft-wrapped rows itself, checked in 1.9.3).
    public static func items(_ raw: String, columns: Int? = nil, maxLines: Int = 5000) -> [FormattedItem] {
        var lines = raw.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n")
        // Table rows first (they know where a row ends), then the remaining text rows cut at the terminal's width.
        lines = rejoinTableRows(lines)
        if let columns, columns > 0 { lines = rejoin(lines, columns: columns, skipTableRows: true) }
        let tidy = ReadingText.prepare(lines.joined(separator: "\n"), maxLines: maxLines)
        return blocks(tidy.isEmpty ? [] : tidy.components(separatedBy: "\n"))
    }

    /// Physical terminal rows back to logical lines: a row exactly `columns` wide was cut by the terminal's edge and
    /// continues on the next row. A row that ends early (or an empty row) ends its line.
    /// `skipTableRows`: a row that starts a table line (a bar, a frame corner) is left to `rejoinTableRows`, which knows
    /// where a table row ends; a table exactly as wide as the terminal would otherwise swallow the row under it.
    public static func rejoin(_ rows: [String], columns: Int, skipTableRows: Bool = false) -> [String] {
        guard columns > 0 else { return rows }
        var out: [String] = []
        var cur = ""
        var open = false
        for r in rows {
            if open { cur += r } else { cur = r }
            let tableRow = skipTableRows && !open && cur.drop(while: { $0 == " " }).first.map { "|+".contains($0) || isBoxChar($0) } == true
            open = !tableRow && r.count >= columns
            if !open { out.append(cur); cur = "" }
        }
        if open { out.append(cur) }
        return out
    }

    /// Table rows cut into screen rows, glued back (LAB-1299 follow-up). A live terminal's text arrives as the rows it
    /// shows: a row wider than the pane is cut at the edge, and after One Roof reattaches to roofd a second time at the
    /// width roofd drew it. A box-drawing line is whole once it is as wide as its table's top frame (or, for the frame
    /// itself, once it reaches its right corner); a Markdown row once it ends with `|` and the next piece is not the
    /// rest of it (a piece that does not start with `|` but has one in it). Anything that never completes is left as it
    /// was, so ordinary text with a bar in it is untouched.
    public static func rejoinTableRows(_ lines: [String], maxPieces: Int = 24) -> [String] {
        var out: [String] = []
        var boxWidth = 0
        var i = 0
        func trimmed(_ s: String) -> String { s.trimmingCharacters(in: .whitespaces) }
        while i < lines.count {
            let first = trimmed(lines[i])
            guard let f = first.first else { out.append(lines[i]); i += 1; continue }
            if "┌╭┏╔".contains(f) || ((boxVerticals.contains(f) || "├└┣┗╠╚╞╘".contains(f)) && boxWidth > 0) {
                // Box line: gather pieces until it is whole (only leading blanks dropped: a piece's trailing padding
                // is part of the row's width).
                var acc = String(lines[i].drop(while: { $0 == " " }))
                var j = i + 1
                func whole(_ t: String) -> Bool {
                    if "┌╭┏╔".contains(t.first!) { return t.last.map { "┐╮┓╗".contains($0) } ?? false }
                    return t.count >= boxWidth
                }
                while !whole(acc), j < lines.count, j - i < maxPieces {
                    let n = lines[j]
                    if trimmed(n).isEmpty { break }
                    acc += n
                    j += 1
                }
                if whole(acc) {
                    if "┌╭┏╔".contains(f) { boxWidth = acc.count }
                    if isBottomFrame(acc) && !boxVerticals.contains(f) && !"├┣╠╞".contains(f) { boxWidth = 0 }
                    out.append(acc); i = j; continue
                }
                out.append(lines[i]); i += 1; continue
            }
            if f == "|" {
                var acc = String(lines[i].drop(while: { $0 == " " }))
                var j = i + 1
                var done = false
                while j < lines.count, j - i < maxPieces {
                    let n = trimmed(lines[j])
                    if n.isEmpty { break }
                    if trimmed(acc).hasSuffix("|") {
                        // The rest of this row: does not start a row of its own, and ends where a row ends.
                        // (a middle piece of a long row has a bar inside it; text after the table has none).
                        if !n.hasPrefix("|"), n.contains("|") { acc += lines[j]; j += 1; continue }
                        done = true; break
                    }
                    acc += lines[j]; j += 1
                }
                if !done, trimmed(acc).hasSuffix("|") { done = true }
                if done, j > i + 1 { out.append(trimmed(acc)); i = j; continue }
                out.append(lines[i]); i += 1; continue
            }
            out.append(lines[i]); i += 1
        }
        return out
    }

    /// Lines → items: pipe tables and box tables become `.table`, runs of other lines `.text`.
    static func blocks(_ lines: [String]) -> [FormattedItem] {
        var out: [FormattedItem] = []
        var run: [String] = []
        func flush() {
            while run.last?.trimmingCharacters(in: .whitespaces).isEmpty == true { run.removeLast() }
            while run.first?.trimmingCharacters(in: .whitespaces).isEmpty == true { run.removeFirst() }
            if !run.isEmpty { out.append(.text(run.joined(separator: "\n"))) }
            run = []
        }
        var i = 0
        while i < lines.count {
            if let (t, next) = pipeTable(lines, at: i) ?? boxTable(lines, at: i) {
                flush(); out.append(t); i = next; continue
            }
            run.append(lines[i]); i += 1
        }
        flush()
        return out
    }

    // MARK: Pipe tables

    /// A Markdown pipe table starting at `i`: a row with `|`, then a `|---|` separator with the same number of
    /// cells, then rows while lines carry a `|`.
    public static func pipeTable(_ lines: [String], at i: Int) -> (FormattedItem, Int)? {
        guard i + 1 < lines.count else { return nil }
        let head = lines[i].trimmingCharacters(in: .whitespaces)
        guard head.contains("|"), !isBoxRow(head), let aligns = MarkdownDoc.delimiterRow(lines[i + 1]) else { return nil }
        let header = MarkdownDoc.cells(head)
        guard header.count == aligns.count, header.count >= 2 else { return nil }
        var rows: [[String]] = []
        var j = i + 2
        while j < lines.count {
            let c = lines[j].trimmingCharacters(in: .whitespaces)
            guard !c.isEmpty, c.contains("|") else { break }
            var r = MarkdownDoc.cells(c)
            if r.count < header.count { r += Array(repeating: "", count: header.count - r.count) }
            rows.append(Array(r.prefix(header.count)))
            j += 1
        }
        return (.table(header: header, alignments: aligns, rows: rows), j)
    }

    // MARK: Box-drawing tables

    /// Vertical bars that separate cells in a box table (light, heavy, double, dashed).
    static let boxVerticals: Set<Character> = ["│", "┃", "║", "╎", "╏", "┆", "┇", "┊", "┋"]

    static func isBoxChar(_ c: Character) -> Bool {
        guard let s = c.unicodeScalars.first, c.unicodeScalars.count == 1 else { return false }
        return (0x2500...0x257F).contains(s.value)
    }

    /// A frame or rule line: only box-drawing characters (U+2500–U+257F), or an ASCII grid rule `+----+----+`.
    public static func isBoxRule(_ line: String) -> Bool {
        let t = line.trimmingCharacters(in: .whitespaces)
        guard t.count >= 3 else { return false }
        if t.allSatisfy({ isBoxChar($0) || $0 == " " }) {
            // At least one horizontal stroke, and not a lone column of bars.
            return t.contains { isBoxChar($0) && !boxVerticals.contains($0) }
        }
        return t.hasPrefix("+") && t.hasSuffix("+") && t.contains("-") && t.allSatisfy { "+-=: ".contains($0) }
    }

    /// A content row: starts and ends with a vertical bar (box │ or ASCII |).
    public static func isBoxRow(_ line: String) -> Bool {
        let t = line.trimmingCharacters(in: .whitespaces)
        guard t.count >= 2, let f = t.first, let l = t.last else { return false }
        return boxVerticals.contains(f) && boxVerticals.contains(l)
    }

    static func isAsciiRow(_ line: String) -> Bool {
        let t = line.trimmingCharacters(in: .whitespaces)
        return t.count >= 2 && t.hasPrefix("|") && t.hasSuffix("|")
    }

    /// The cells of one content row: split at the vertical bars (box bars only when the row uses them, so a `|` inside
    /// a box cell stays text).
    public static func boxCells(_ line: String) -> [String] {
        let t = line.trimmingCharacters(in: .whitespaces)
        let box = t.first.map { boxVerticals.contains($0) } ?? false
        var cells: [String] = []
        var cur = ""
        for ch in t {
            if box ? boxVerticals.contains(ch) : ch == "|" { cells.append(cur); cur = "" } else { cur.append(ch) }
        }
        cells.append(cur)
        // Drop what is outside the outer bars.
        if cells.count >= 2 { cells.removeFirst(); cells.removeLast() }
        return cells.map { $0.trimmingCharacters(in: .whitespaces) }
    }

    /// A box-drawing (or ASCII `+---+`) table starting at `i`: a run of rule and content lines with at least one
    /// rule, one content row, and two or more columns (a one-column frame, such as an agent's welcome box, stays text).
    /// Rows the program wrapped inside their cells are merged when the table draws a rule between every row.
    public static func boxTable(_ lines: [String], at i: Int) -> (FormattedItem, Int)? {
        guard i < lines.count, isBoxRule(lines[i]) || isBoxRow(lines[i]) || isAsciiTableStart(lines, i) else { return nil }
        var j = i
        var kinds: [(rule: Bool, line: String)] = []
        // LAB-1299: a box-drawing table takes only box-drawing lines (never ASCII `|` rows) and ends at its bottom
        // frame; an ASCII grid ends where a Markdown table starts. Otherwise a table printed right after this one was
        // swallowed, its rule counted as an interior separator, and every group of rows merged into one row.
        let ascii = isAsciiTableStart(lines, i)
        while j < lines.count {
            let l = lines[j]
            if isBoxRule(l) {
                kinds.append((true, l))
                j += 1
                if !ascii, isBottomFrame(l) { break }
                continue
            }
            if pipeTable(lines, at: j) != nil { break }
            if isBoxRow(l) || (ascii && isAsciiRow(l) && kinds.contains(where: { $0.rule })) { kinds.append((false, l)) }
            else { break }
            j += 1
        }
        guard kinds.contains(where: { $0.rule }), kinds.contains(where: { !$0.rule }) else { return nil }
        // Content groups between rules (the outer frame lines only close groups).
        var groups: [[[String]]] = []
        var cur: [[String]] = []
        var interior = 0
        var seenContent = false
        for (k, entry) in kinds.enumerated() {
            if entry.rule {
                if !cur.isEmpty { groups.append(cur); cur = [] }
                // A rule with content on both sides is a separator inside the table.
                if seenContent, kinds[(k + 1)...].contains(where: { !$0.rule }) { interior += 1 }
            } else {
                seenContent = true
                cur.append(boxCells(entry.line))
            }
        }
        if !cur.isEmpty { groups.append(cur) }
        let width = groups.flatMap { $0 }.map(\.count).max() ?? 0
        guard width >= 2 else { return nil }
        func pad(_ r: [String]) -> [String] { r.count < width ? r + Array(repeating: "", count: width - r.count) : r }
        func merge(_ g: [[String]]) -> [String] {
            (0..<width).map { c in g.map { pad($0)[c] }.filter { !$0.isEmpty }.joined(separator: " ") }
        }
        var header: [String]
        var rows: [[String]] = []
        if interior >= 1, let first = groups.first {
            header = merge(first)
            let body = groups.dropFirst()
            if interior >= 2 { rows = body.map(merge) } else { rows = body.flatMap { $0 }.map(pad) }
        } else {
            let all = groups.flatMap { $0 }.map(pad)
            header = all.first ?? []
            rows = Array(all.dropFirst())
        }
        if header.isEmpty { header = Array(repeating: "", count: width) }
        return (.table(header: header, alignments: Array(repeating: .leading, count: width), rows: rows), j)
    }

    /// The closing frame of a box-drawing table: a rule carrying a bottom corner or a bottom tee (└ ┴ ┘ and the heavy,
    /// double and rounded forms).
    static func isBottomFrame(_ line: String) -> Bool {
        line.contains { "└┘┴╰╯┗┛┻╚╝╩".contains($0) }
    }

    /// `+---+` followed by an ASCII `| a | b |` row (psql, MySQL, prettytable).
    static func isAsciiTableStart(_ lines: [String], _ i: Int) -> Bool {
        i + 1 < lines.count && isBoxRule(lines[i]) && isAsciiRow(lines[i + 1])
    }
}

// MARK: Claude transcript

public enum TranscriptFormat {
    /// A Claude transcript (JSONL, possibly the tail of a long file: a cut first line is skipped) as items, oldest
    /// first, the last `limit` kept. Side chains (subagents), meta lines, tool results and thinking are left out.
    public static func items(jsonl: String, limit: Int = 400) -> [FormattedItem] {
        var out: [FormattedItem] = []
        for line in jsonl.split(separator: "\n", omittingEmptySubsequences: true) {
            guard let d = line.data(using: .utf8),
                  let obj = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any] else { continue }
            out += items(entry: obj)
        }
        return out.count > limit ? Array(out.suffix(limit)) : out
    }

    static func items(entry obj: [String: Any]) -> [FormattedItem] {
        guard let type = obj["type"] as? String, type == "user" || type == "assistant" else { return [] }
        if obj["isSidechain"] as? Bool == true || obj["isMeta"] as? Bool == true || obj["isCompactSummary"] as? Bool == true { return [] }
        guard let msg = obj["message"] as? [String: Any] else { return [] }
        var out: [FormattedItem] = []
        if type == "user" {
            if let s = msg["content"] as? String { out += prompt(s) }
            else if let parts = msg["content"] as? [[String: Any]] {
                for p in parts where p["type"] as? String == "text" { out += prompt(p["text"] as? String ?? "") }
                if parts.contains(where: { $0["type"] as? String == "image" }) { out.append(.tool("Attached an image")) }
            }
            return out
        }
        let parts = (msg["content"] as? [[String: Any]]) ?? ((msg["content"] as? String).map { [["type": "text", "text": $0]] } ?? [])
        for p in parts {
            switch p["type"] as? String {
            case "text":
                let text = (p["text"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                if !text.isEmpty { out.append(.reply(MarkdownDoc.parse(text))) }
            case "tool_use":
                out.append(.tool(toolLine(name: p["name"] as? String ?? "tool", input: p["input"] as? [String: Any] ?? [:])))
            default: continue   // thinking, redacted thinking
            }
        }
        return out
    }

    /// A user line: the prompt, or one line for a slash command; harness notes are left out.
    static func prompt(_ raw: String) -> [FormattedItem] {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return [] }
        if let r = s.range(of: "<command-name>"), let e = s.range(of: "</command-name>", range: r.upperBound..<s.endIndex) {
            return [.tool("Command: " + s[r.upperBound..<e.lowerBound].trimmingCharacters(in: .whitespaces))]
        }
        for skip in ["<local-command-", "<system-reminder>", "<command-message>", "Caveat: The messages below", "<task-notification>"]
        where s.hasPrefix(skip) { return [] }
        if s.hasPrefix("[Request interrupted") { return [.tool("Interrupted")] }
        return [.prompt(s)]
    }

    /// One compact line for a tool call, never a dump of its input.
    public static func toolLine(name: String, input: [String: Any]) -> String {
        func str(_ k: String) -> String? {
            (input[k] as? String).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.flatMap { $0.isEmpty ? nil : $0 }
        }
        func short(_ s: String, _ n: Int = 160) -> String {
            let first = s.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: true).first.map(String.init) ?? s
            let more = first.count < s.count
            return first.count > n ? String(first.prefix(n - 1)) + "…" : first + (more ? " …" : "")
        }
        switch name {
        case "Bash": return "Ran: " + short(str("command") ?? "a command")
        case "Read": return "Read: " + short(str("file_path") ?? "a file")
        case "Edit", "MultiEdit", "NotebookEdit": return "Edited: " + short(str("file_path") ?? str("notebook_path") ?? "a file")
        case "Write": return "Wrote: " + short(str("file_path") ?? "a file")
        case "Grep", "Glob": return "Searched: " + short(str("pattern") ?? "files")
        case "Task", "Agent": return "Started a subagent: " + short(str("description") ?? str("subagent_type") ?? "task")
        case "WebFetch": return "Fetched: " + short(str("url") ?? "a page")
        case "WebSearch": return "Searched the web: " + short(str("query") ?? "")
        case "TodoWrite": return "Updated the to-do list"
        default:
            let first = input.keys.sorted().lazy.compactMap { str($0) }.first
            return "Used \(name)" + (first.map { ": " + short($0, 100) } ?? "")
        }
    }
}
