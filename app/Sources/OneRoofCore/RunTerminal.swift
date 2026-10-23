import Foundation

// Right-click › Run in Terminal (LAB-598). Select a command an agent printed, and One Roof types it into a plain
// terminal next to that agent, WITHOUT pressing Return: you read it, then press Return yourself (human in the loop).
// One reusable run terminal per agent session; it starts in the agent's repo and is tagged with its parent.

public enum RunTerminal {
    /// Prompt marks people copy along with a command ("$ swift test", "❯ git status").
    static let prompts = ["$ ", "❯ ", "% ", "➜ ", "λ ", "› "]
    /// A line ending like this goes on in the next line (the shell would join them too).
    static let joiners = ["&&", "||", "|", "\\"]
    /// A line ending like this opens a block: the next, indented line is its body, not a wrapped tail.
    static let openers = ["{", "(", "then", "do", "else", "in"]

    /// The command in a selection: prompt marks stripped, common indentation removed, lines an agent's screen wrapped
    /// joined back together, blank edges dropped. Several real lines stay several lines.
    public static func clean(_ selection: String) -> String {
        var text = selection.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        text = text.replacingOccurrences(of: "\t", with: "    ")
        text = String(text.unicodeScalars.filter { $0 == "\n" || $0.value >= 0x20 && $0.value != 0x7F }.map(Character.init))
        // An agent's box borders ("│ swift test │") come along with a selection inside a TUI frame.
        let borders: Set<Character> = ["│", "┃", "║", "╎", "▌"]
        var lines = text.components(separatedBy: "\n").map { raw -> String in
            var l = Substring(raw)
            if let f = l.first(where: { $0 != " " }), borders.contains(f), let i = l.firstIndex(of: f) { l = l[l.index(after: i)...] }
            while let last = l.last, last == " " || borders.contains(last) { l = l.dropLast() }
            return String(l)
        }
        while lines.first?.isEmpty == true { lines.removeFirst() }
        while lines.last?.isEmpty == true { lines.removeLast() }
        guard !lines.isEmpty else { return "" }
        // Common indentation off, then prompt marks.
        let indent = lines.filter { !$0.isEmpty }.map { $0.prefix(while: { $0 == " " }).count }.min() ?? 0
        lines = lines.map { String($0.dropFirst(min(indent, $0.prefix(while: { $0 == " " }).count))) }
        lines = lines.map(stripPrompt)
        // Join wrapped lines: a deeper-indented line after a line that does not open a block, or after a joiner.
        let base = lines.first.map { $0.prefix(while: { $0 == " " }).count } ?? 0
        var out: [String] = []
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard let prev = out.last else { out.append(trimmed); continue }
            let deeper = line.prefix(while: { $0 == " " }).count > base
            let p = prev.trimmingCharacters(in: .whitespaces)
            let endsJoiner = joiners.contains { p.hasSuffix($0) } && !p.hasSuffix("\\")
            let startsJoiner = ["&&", "||", "|"].contains { trimmed.hasPrefix($0) }
            let opens = openers.contains { p == $0 || p.hasSuffix(" " + $0) || p.hasSuffix(";" + $0) || (($0 == "{" || $0 == "(") && p.hasSuffix($0)) }
            if !trimmed.isEmpty, endsJoiner || startsJoiner || (deeper && !opens && !p.hasSuffix("\\")) {
                out[out.count - 1] = p + " " + trimmed
            } else if deeper {
                out.append(String(repeating: " ", count: 2) + trimmed)   // a block's body keeps a modest indent
            } else {
                out.append(trimmed)
            }
        }
        return out.joined(separator: "\n")
    }

    static func stripPrompt(_ line: String) -> String {
        let lead = line.prefix(while: { $0 == " " })
        let rest = line.dropFirst(lead.count)
        guard let p = prompts.first(where: { rest.hasPrefix($0) }) else { return line }
        return String(lead) + rest.dropFirst(p.count).drop(while: { $0 == " " })
    }

    /// What to type: never a newline the shell would run. A one-line command goes in as is; several lines go in as
    /// one bracketed paste (zsh, which every One Roof terminal runs, puts it in the line editor and waits for Return),
    /// or, for a shell without bracketed paste, joined with "; " on one line.
    public static func typed(_ command: String, bracketedPaste: Bool = true) -> String {
        let lines = command.components(separatedBy: "\n").filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        guard lines.count > 1 else { return lines.first ?? "" }
        if bracketedPaste { return "\u{1B}[200~" + lines.joined(separator: "\n") + "\u{1B}[201~" }
        var out = ""
        for l in lines {
            let t = l.trimmingCharacters(in: .whitespaces)
            if out.isEmpty { out = t; continue }
            if out.hasSuffix("\\") { out = String(out.dropLast()).trimmingCharacters(in: .whitespaces) + " " + t }
            else if joiners.contains(where: { out.hasSuffix($0) }) || openers.contains(where: { out.hasSuffix($0) }) { out += " " + t }
            else { out += "; " + t }
        }
        return out
    }

    /// A session that could be a run terminal.
    public struct Candidate: Equatable, Sendable {
        public var id: String
        public var parentSessionId: String?
        public var alive: Bool
        public var createdAt: Date
        public init(id: String, parentSessionId: String?, alive: Bool, createdAt: Date) {
            self.id = id; self.parentSessionId = parentSessionId; self.alive = alive; self.createdAt = createdAt
        }
    }

    public enum Target: Equatable, Sendable {
        /// Type into this live run terminal and bring its window forward.
        case reuse(String)
        /// Start a new one.
        case create
    }

    /// One run terminal per parent: the newest live one is reused; none alive → a new one.
    public static func target(parent: String, among sessions: [Candidate]) -> Target {
        let mine = sessions.filter { $0.parentSessionId == parent && $0.alive }.sorted { $0.createdAt > $1.createdAt }
        return mine.first.map { .reuse($0.id) } ?? .create
    }

    /// The run terminal's name: "Run · Fix login".
    public static func name(parent: String) -> String { "Run · \(parent)" }

    /// Rows with each run terminal placed right after its parent (when the parent is in the list), keeping the order.
    public static func nest(_ rows: [BoardItem]) -> [BoardItem] {
        let ids = Set(rows.map(\.id))
        let children = Dictionary(grouping: rows.filter { $0.session.parentSessionId.map(ids.contains) ?? false },
                                  by: { $0.session.parentSessionId ?? "" })
        guard !children.isEmpty else { return rows }
        var out: [BoardItem] = []
        for r in rows where !(r.session.parentSessionId.map(ids.contains) ?? false) {
            out.append(r)
            out.append(contentsOf: children[r.id] ?? [])
        }
        // A child whose parent is itself a child (never made, but never lose a row).
        let placed = Set(out.map(\.id))
        out.append(contentsOf: rows.filter { !placed.contains($0.id) })
        return out
    }
}
