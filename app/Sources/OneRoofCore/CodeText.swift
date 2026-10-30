import Foundation

// LAB-1628 · "show code as code": every place Learn shows code or a SKILL.md uses one dark code panel (CodePanel in the
// app). This file holds its testable parts: a Markdown file's `---` front-matter split from its body (the front-matter
// shows as YAML in the panel, the body is rendered as Markdown below it), the language a file or fence is coloured as,
// and the preview cut for a long file.

public enum CodeText {
    /// A Markdown text's front-matter (the YAML between the opening `---` and the next `---`, without the fences) and
    /// the body after it. No front-matter: nil and the whole text.
    public static func split(_ text: String) -> (front: String?, body: String) {
        let t = text.replacingOccurrences(of: "\r\n", with: "\n")
        let lines = t.components(separatedBy: "\n")
        guard lines.first?.trimmingCharacters(in: .whitespaces) == "---",
              let end = lines.dropFirst().firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == "---" }) else { return (nil, t) }
        let front = lines[1..<end].joined(separator: "\n")
        var body = Array(lines[(end + 1)...])
        while body.first?.trimmingCharacters(in: .whitespaces).isEmpty == true { body.removeFirst() }
        return (front, body.joined(separator: "\n"))
    }

    /// The language a file is coloured as, by extension (`SourceLanguage.detect`); HTML and plain text stay plain.
    public static func language(path: String) -> SourceLanguage { SourceLanguage.detect(path: path) }

    /// The language a fenced block is coloured as (```yaml, ```sh, ```swift …).
    public static func language(fence: String) -> SourceLanguage { MarkdownDoc.sourceLanguage(fence: fence) }

    /// The panel's label for a language ("yaml", "shell" …; "text" for plain).
    public static func label(_ l: SourceLanguage) -> String { l == .plain ? "text" : l.rawValue }

    /// At most `maxLines` lines of `text` for a preview, and whether it was cut.
    public static func preview(_ text: String, maxLines: Int = 400) -> (text: String, cut: Bool) {
        var n = 0
        var idx = text.startIndex
        while let r = text[idx...].firstIndex(of: "\n") {
            n += 1
            if n == maxLines { return (String(text[..<r]), text.index(after: r) < text.endIndex) }
            idx = text.index(after: r)
        }
        return (text, false)
    }
}
