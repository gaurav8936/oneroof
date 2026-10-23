import Foundation

/// LAB-479: Markdown split into blocks for the centre viewer: headings, paragraphs, nested and task lists, fenced and
/// indented code, block quotes, GitHub tables, rules, images and simple HTML blocks. No Markdown library (stack rule):
/// this is the block structure only; emphasis, inline code and links inside a block are left to Foundation's
/// `AttributedString(markdown:)` in the view.
public indirect enum MarkdownBlock: Equatable, Sendable {
    case heading(level: Int, text: String, anchor: String)
    case paragraph(String)
    case list(ordered: Bool, start: Int, items: [MarkdownListItem])
    case code(language: String, text: String)
    case quote([MarkdownBlock])
    case table(header: [String], alignments: [MarkdownAlignment], rows: [[String]])
    case image(alt: String, source: String)
    case rule
}

public struct MarkdownListItem: Equatable, Sendable {
    /// The item's first paragraph (inline Markdown).
    public var text: String
    /// Task lists: false = "[ ]", true = "[x]", nil = a plain item.
    public var checked: Bool?
    /// Anything under the item: more paragraphs, nested lists, code.
    public var children: [MarkdownBlock]
    public init(text: String, checked: Bool? = nil, children: [MarkdownBlock] = []) {
        self.text = text; self.checked = checked; self.children = children
    }
}

public enum MarkdownAlignment: String, Sendable { case leading, center, trailing }

/// Where a link or image in a Markdown file points, resolved against the file.
public enum MarkdownTarget: Equatable, Sendable {
    /// http(s), mailto and other apps' links: open outside One Roof.
    case web(String)
    /// A local file (absolute, standardized), with an optional heading anchor.
    case file(path: String, anchor: String?)
    /// A heading in this same file.
    case anchor(String)
}

public enum MarkdownDoc {
    // MARK: Entry points

    /// The page without its `---` frontmatter block.
    public static func stripFrontmatter(_ text: String) -> String {
        let t = text.replacingOccurrences(of: "\r\n", with: "\n")
        guard t.hasPrefix("---\n"), let end = t.range(of: "\n---\n", range: t.index(t.startIndex, offsetBy: 3)..<t.endIndex)
            ?? (t.hasSuffix("\n---") ? t.range(of: "\n---", options: .backwards) : nil)
        else { return t }
        return String(t[end.upperBound...].drop(while: { $0 == "\n" }))
    }

    public static func parse(_ text: String) -> [MarkdownBlock] {
        let lines = stripFrontmatter(text).components(separatedBy: "\n").map(expandTabs)
        return parseLines(lines)
    }

    /// GitHub-style heading anchor: lower case, punctuation dropped, spaces to hyphens.
    public static func slug(_ heading: String) -> String {
        var out = ""
        for ch in heading.lowercased() {
            if ch.isLetter || ch.isNumber || ch == "-" || ch == "_" { out.append(ch) } else if ch == " " { out.append("-") }
        }
        return out
    }

    /// Resolve a link or image source written in the Markdown file at `file`.
    public static func resolve(_ href: String, from file: String) -> MarkdownTarget? {
        var h = href.trimmingCharacters(in: .whitespaces)
        if h.hasPrefix("<"), h.hasSuffix(">") { h = String(h.dropFirst().dropLast()) }
        guard !h.isEmpty else { return nil }
        if h.hasPrefix("#") { return .anchor(String(h.dropFirst()).removingPercentEncoding ?? String(h.dropFirst())) }
        if let r = h.range(of: "^[A-Za-z][A-Za-z0-9+.-]*:", options: .regularExpression) {
            let scheme = h[r].dropLast().lowercased()
            guard scheme == "file" else { return .web(h) }
            guard let u = URL(string: h) else { return nil }
            return .file(path: (u.path as NSString).standardizingPath, anchor: u.fragment)
        }
        var anchor: String?
        if let hash = h.firstIndex(of: "#") { anchor = String(h[h.index(after: hash)...]); h = String(h[..<hash]) }
        if let q = h.firstIndex(of: "?") { h = String(h[..<q]) }
        h = h.removingPercentEncoding ?? h
        guard !h.isEmpty else { return anchor.map { .anchor($0) } }
        let path: String
        if h.hasPrefix("~") { path = (h as NSString).expandingTildeInPath }
        else if h.hasPrefix("/") { path = h }
        else { path = ((file as NSString).deletingLastPathComponent as NSString).appendingPathComponent(h) }
        return .file(path: (path as NSString).standardizingPath, anchor: anchor.flatMap { $0.isEmpty ? nil : $0 })
    }

    /// The language name for a code fence's info string ("```swift title=x" → "swift").
    public static func fenceLanguage(_ info: String) -> String {
        String(info.split(separator: " ").first ?? "").trimmingCharacters(in: CharacterSet(charactersIn: "{}.")).lowercased()
    }

    /// The editor's lexer for a fence's language, so code blocks are coloured like the editor ("py" → Python).
    public static func sourceLanguage(fence: String) -> SourceLanguage {
        let ext: [String: String] = ["python": "py", "py": "py", "swift": "swift", "typescript": "ts", "ts": "ts", "tsx": "tsx",
                                     "javascript": "js", "js": "js", "jsx": "jsx", "json": "json", "jsonc": "json", "yaml": "yml",
                                     "yml": "yml", "bash": "sh", "sh": "sh", "shell": "sh", "zsh": "zsh", "console": "sh",
                                     "markdown": "md", "md": "md"]
        return ext[fence.lowercased()].map { SourceLanguage.detect(path: "x." + $0) } ?? .plain
    }

    // MARK: Blocks

    static func parseLines(_ lines: [String]) -> [MarkdownBlock] {
        var out: [MarkdownBlock] = []
        var para: [String] = []
        func flush() {
            guard !para.isEmpty else { return }
            let text = joinParagraph(para)
            para = []
            out.append(soleImage(text) ?? .paragraph(text))
        }

        var i = 0
        while i < lines.count {
            let line = lines[i]
            let t = line.trimmingCharacters(in: .whitespaces)
            let indent = indentWidth(line)
            if t.isEmpty { flush(); i += 1; continue }

            if indent < 4, let fence = fenceOpen(t) {
                flush()
                var body: [String] = []
                i += 1
                while i < lines.count {
                    let c = lines[i].trimmingCharacters(in: .whitespaces)
                    if c.first == fence.char, c.allSatisfy({ $0 == fence.char }), c.count >= fence.count { i += 1; break }
                    body.append(dedent(lines[i], by: indent))
                    i += 1
                }
                out.append(.code(language: fenceLanguage(fence.info), text: body.joined(separator: "\n")))
                continue
            }
            if indent < 4, !para.isEmpty, let level = setextLevel(t) {
                let text = joinParagraph(para)
                para = []
                out.append(.heading(level: level, text: text, anchor: slug(plain(text))))
                i += 1
                continue
            }
            if indent < 4, let h = atxHeading(t) { flush(); out.append(h); i += 1; continue }
            if indent < 4, isRule(t) { flush(); out.append(.rule); i += 1; continue }
            if indent < 4, t.hasPrefix(">") {
                flush()
                var inner: [String] = []
                while i < lines.count {
                    let c = lines[i].trimmingCharacters(in: .whitespaces)
                    guard c.hasPrefix(">") else { break }
                    var rest = c.dropFirst()
                    if rest.first == " " { rest = rest.dropFirst() }
                    inner.append(String(rest))
                    i += 1
                }
                out.append(.quote(parseLines(inner)))
                continue
            }
            if indent < 4, t.contains("|"), i + 1 < lines.count, let aligns = delimiterRow(lines[i + 1]),
               cells(t).count == aligns.count {
                flush()
                let header = cells(t)
                i += 2
                var rows: [[String]] = []
                while i < lines.count {
                    let c = lines[i].trimmingCharacters(in: .whitespaces)
                    guard !c.isEmpty, c.contains("|") else { break }
                    var r = cells(c)
                    if r.count < header.count { r += Array(repeating: "", count: header.count - r.count) }
                    rows.append(Array(r.prefix(header.count)))
                    i += 1
                }
                out.append(.table(header: header, alignments: aligns, rows: rows))
                continue
            }
            if indent < 4, let m = listMarker(line), para.isEmpty || !m.ordered || m.start == 1 {
                flush()
                let (block, next) = parseList(lines, from: i)
                out.append(block)
                i = next
                continue
            }
            if indent >= 4, para.isEmpty {
                var body: [String] = []
                while i < lines.count {
                    let l = lines[i]
                    if l.trimmingCharacters(in: .whitespaces).isEmpty { body.append(""); i += 1; continue }
                    guard indentWidth(l) >= 4 else { break }
                    body.append(dedent(l, by: 4))
                    i += 1
                }
                while body.last == "" { body.removeLast() }
                out.append(.code(language: "", text: body.joined(separator: "\n")))
                continue
            }
            if indent < 4, para.isEmpty, t.hasPrefix("<!--") {
                while i < lines.count, !lines[i].contains("-->") { i += 1 }
                i += 1
                continue
            }
            if indent < 4, para.isEmpty, isHTMLBlockStart(t) {
                var chunk: [String] = []
                while i < lines.count, !lines[i].trimmingCharacters(in: .whitespaces).isEmpty { chunk.append(lines[i]); i += 1 }
                out.append(contentsOf: htmlBlock(chunk.joined(separator: "\n")))
                continue
            }
            para.append(line)
            i += 1
        }
        flush()
        return out
    }

    struct Marker: Equatable {
        var indent: Int
        var ordered: Bool
        var start: Int
        var content: String
        /// Column where the item's text starts; lines indented this far belong to the item.
        var offset: Int
    }

    static func listMarker(_ line: String) -> Marker? {
        let indent = indentWidth(line)
        var rest = Substring(line.dropFirst(indent))
        var ordered = false, start = 1, width = 0
        if let c = rest.first, "-*+".contains(c) {
            width = 1
        } else {
            let digits = rest.prefix { $0.isASCII && $0.isNumber }
            guard (1...9).contains(digits.count), let d = Int(digits) else { return nil }
            let after = rest.dropFirst(digits.count)
            guard let p = after.first, p == "." || p == ")" else { return nil }
            ordered = true; start = d; width = digits.count + 1
        }
        rest = rest.dropFirst(width)
        if !rest.isEmpty, rest.first != " " { return nil }
        let spaces = rest.prefix { $0 == " " }.count
        let content = String(rest.dropFirst(spaces))
        let pad = content.isEmpty ? 1 : (spaces > 4 ? 1 : spaces)
        return Marker(indent: indent, ordered: ordered, start: start, content: content, offset: indent + width + pad)
    }

    static func parseList(_ lines: [String], from start: Int) -> (MarkdownBlock, Int) {
        let first = listMarker(lines[start])!
        var items: [MarkdownListItem] = []
        var i = start
        while i < lines.count, let m = listMarker(lines[i]), m.ordered == first.ordered, m.indent < first.indent + 2,
              !isRule(lines[i].trimmingCharacters(in: .whitespaces)) {
            var body = [m.content]
            i += 1
            var sawBlank = false
            while i < lines.count {
                let l = lines[i]
                let t = l.trimmingCharacters(in: .whitespaces)
                if t.isEmpty { body.append(""); sawBlank = true; i += 1; continue }
                let ind = indentWidth(l)
                if ind >= m.offset { body.append(dedent(l, by: m.offset)); sawBlank = false; i += 1; continue }
                if listMarker(l) != nil {
                    if ind >= m.indent + 2 { body.append(dedent(l, by: ind)); sawBlank = false; i += 1; continue }   // a nested list indented less than the text
                    break
                }
                if !sawBlank && !startsBlock(t) { body.append(t); i += 1; continue }   // lazy continuation
                break
            }
            while body.last == "" { body.removeLast() }
            var blocks = parseLines(body)
            var text = ""
            if case .paragraph(let p)? = blocks.first { text = p; blocks.removeFirst() }
            var checked: Bool?
            for (box, value) in [("[ ] ", false), ("[x] ", true), ("[X] ", true)] where text.hasPrefix(box) {
                checked = value; text = String(text.dropFirst(box.count))
            }
            if checked == nil, ["[ ]", "[x]", "[X]"].contains(text) { checked = text != "[ ]"; text = "" }
            items.append(MarkdownListItem(text: text, checked: checked, children: blocks))
            // A blank line then something that is not the next item ends the list.
            var j = i
            while j < lines.count, lines[j].trimmingCharacters(in: .whitespaces).isEmpty { j += 1 }
            if j > i, j < lines.count, let n = listMarker(lines[j]), n.ordered == first.ordered, n.indent < first.indent + 2 { i = j }
        }
        return (.list(ordered: first.ordered, start: first.start, items: items), i)
    }

    // MARK: Line helpers

    static func expandTabs(_ line: String) -> String {
        guard line.contains("\t") else { return line }
        var out = "", col = 0, leading = true
        for ch in line {
            if ch == "\t" && leading { let n = 4 - col % 4; out += String(repeating: " ", count: n); col += n; continue }
            if ch != " " && ch != "\t" { leading = false }
            out.append(ch); col += 1
        }
        return out
    }

    static func indentWidth(_ line: String) -> Int { line.prefix { $0 == " " }.count }

    static func dedent(_ line: String, by n: Int) -> String { String(line.dropFirst(min(n, indentWidth(line)))) }

    static func fenceOpen(_ t: String) -> (char: Character, count: Int, info: String)? {
        guard let c = t.first, c == "`" || c == "~" else { return nil }
        let run = t.prefix { $0 == c }.count
        guard run >= 3 else { return nil }
        let info = t.dropFirst(run).trimmingCharacters(in: .whitespaces)
        if c == "`", info.contains("`") { return nil }
        return (c, run, info)
    }

    static func setextLevel(_ t: String) -> Int? {
        guard let c = t.first, c == "=" || c == "-", t.allSatisfy({ $0 == c }) else { return nil }
        return c == "=" ? 1 : 2
    }

    static func atxHeading(_ t: String) -> MarkdownBlock? {
        let hashes = t.prefix { $0 == "#" }.count
        guard (1...6).contains(hashes) else { return nil }
        let rest = t.dropFirst(hashes)
        guard rest.isEmpty || rest.first == " " else { return nil }
        var text = rest.trimmingCharacters(in: .whitespaces)
        if let r = text.range(of: "(^|\\s+)#+$", options: .regularExpression) { text = String(text[..<r.lowerBound]) }
        return .heading(level: hashes, text: text, anchor: slug(plain(text)))
    }

    static func isRule(_ t: String) -> Bool {
        let s = t.filter { $0 != " " }
        guard let c = s.first, "-*_".contains(c), s.count >= 3 else { return false }
        return s.allSatisfy { $0 == c }
    }

    static func delimiterRow(_ line: String) -> [MarkdownAlignment]? {
        let t = line.trimmingCharacters(in: .whitespaces)
        guard t.contains("|") || t.contains("-") else { return nil }
        guard t.contains("|") else { return nil }
        var aligns: [MarkdownAlignment] = []
        for cell in cells(t) {
            guard cell.range(of: "^:?-+:?$", options: .regularExpression) != nil else { return nil }
            let l = cell.hasPrefix(":"), r = cell.hasSuffix(":")
            aligns.append(l && r ? .center : r ? .trailing : .leading)
        }
        return aligns.isEmpty ? nil : aligns
    }

    /// A table row's cells (outer pipes optional, `\|` is a literal pipe, pipes inside `code` do not split).
    static func cells(_ row: String) -> [String] {
        var t = row.trimmingCharacters(in: .whitespaces)
        if t.hasPrefix("|") { t.removeFirst() }
        if t.hasSuffix("|"), !t.hasSuffix("\\|") { t.removeLast() }
        var out: [String] = [], cur = "", inCode = false, escaped = false
        for ch in t {
            if escaped { if ch != "|" { cur.append("\\") }; cur.append(ch); escaped = false; continue }
            if ch == "\\" { escaped = true; continue }
            if ch == "`" { inCode.toggle() }
            if ch == "|", !inCode { out.append(cur.trimmingCharacters(in: .whitespaces)); cur = ""; continue }
            cur.append(ch)
        }
        if escaped { cur.append("\\") }
        out.append(cur.trimmingCharacters(in: .whitespaces))
        return out
    }

    static func startsBlock(_ t: String) -> Bool {
        fenceOpen(t) != nil || atxHeading(t) != nil || isRule(t) || t.hasPrefix(">") || listMarker(t) != nil
    }

    static func isHTMLBlockStart(_ t: String) -> Bool {
        t.range(of: "^</?[A-Za-z][A-Za-z0-9-]*(\\s|>|/>|$)", options: .regularExpression) != nil
    }

    /// Paragraph lines joined: a soft break is a space; two trailing spaces or a trailing backslash is a line break.
    static func joinParagraph(_ lines: [String]) -> String {
        var out = ""
        for (n, raw) in lines.enumerated() {
            let l = String(raw.drop { $0 == " " })
            let last = n == lines.count - 1
            if l.hasSuffix("\\"), !last { out += String(l.dropLast()) + "\n"; continue }
            if l.hasSuffix("  "), !last { out += l.trimmingCharacters(in: .whitespaces) + "\n"; continue }
            out += last ? l.trimmingCharacters(in: .whitespaces) : l.trimmingCharacters(in: .whitespaces) + " "
        }
        return out
    }

    /// A paragraph that is only an image (optionally wrapped in a link, like a badge) shows as the image.
    static func soleImage(_ text: String) -> MarkdownBlock? {
        let img = "!\\[([^\\]]*)\\]\\(\\s*<?([^)\\s>]+)>?(?:\\s+[\"'][^\"']*[\"'])?\\s*\\)"
        for pattern in ["^" + img + "$", "^\\[" + img + "\\]\\([^)]*\\)$"] {
            guard let re = try? NSRegularExpression(pattern: pattern),
                  let m = re.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
                  let alt = Range(m.range(at: 1), in: text), let src = Range(m.range(at: 2), in: text) else { continue }
            return .image(alt: String(text[alt]), source: String(text[src]))
        }
        return nil
    }

    /// An HTML block in Markdown: images become images, comments vanish, other tags are dropped and their text kept.
    static func htmlBlock(_ html: String) -> [MarkdownBlock] {
        var out: [MarkdownBlock] = []
        if let re = try? NSRegularExpression(pattern: "<img\\b[^>]*>", options: .caseInsensitive) {
            for m in re.matches(in: html, range: NSRange(html.startIndex..., in: html)) {
                guard let r = Range(m.range, in: html) else { continue }
                let tag = String(html[r])
                if let src = attribute("src", in: tag) { out.append(.image(alt: attribute("alt", in: tag) ?? "", source: src)) }
            }
        }
        let text = html.replacingOccurrences(of: "<!--[\\s\\S]*?-->", with: "", options: .regularExpression)
            .replacingOccurrences(of: "<a\\b[^>]*?href\\s*=\\s*[\"']([^\"']*)[\"'][^>]*>([\\s\\S]*?)</a>", with: "[$2]($1)",
                                  options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: "<br\\s*/?>", with: "\n", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\[\\s*\\]\\([^)]*\\)", with: "", options: .regularExpression)   // a link that only wrapped an image
            .replacingOccurrences(of: "[ \\t]+", with: " ", options: .regularExpression)
            .replacingOccurrences(of: " *\n *", with: "\n", options: .regularExpression)
            .replacingOccurrences(of: "&amp;", with: "&").replacingOccurrences(of: "&nbsp;", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return out }
        if let r = html.range(of: "^\\s*<h([1-6])\\b", options: [.regularExpression, .caseInsensitive]),
           let level = Int(String(html[r].last { $0.isNumber } ?? "2")) {
            out.append(.heading(level: level, text: text, anchor: slug(plain(text))))
        } else {
            out.append(.paragraph(text))
        }
        return out
    }

    static func attribute(_ name: String, in tag: String) -> String? {
        guard let re = try? NSRegularExpression(pattern: "\\b\(name)\\s*=\\s*(?:\"([^\"]*)\"|'([^']*)'|([^\\s>]+))", options: .caseInsensitive),
              let m = re.firstMatch(in: tag, range: NSRange(tag.startIndex..., in: tag)) else { return nil }
        for g in 1...3 { if let r = Range(m.range(at: g), in: tag) { return String(tag[r]) } }
        return nil
    }

    /// Inline Markdown reduced to its words (for anchors).
    static func plain(_ text: String) -> String {
        text.replacingOccurrences(of: "!?\\[([^\\]]*)\\]\\([^)]*\\)", with: "$1", options: .regularExpression)
            .replacingOccurrences(of: "[`*_~]", with: "", options: .regularExpression)
    }
}
