import Foundation

/// One symbol in the Inspector's Outline tab (S07 §1.8).
public struct OutlineItem: Equatable, Sendable {
    public var name: String
    public var kind: Kind
    /// 1-based.
    public var line: Int
    /// Nesting: 0 for top level in code (a method inside a class is 1); the heading level (1…6) in Markdown.
    public var depth: Int

    public enum Kind: String, Sendable { case function, type, constant, section }

    public init(name: String, kind: Kind, line: Int, depth: Int) {
        self.name = name; self.kind = kind; self.line = line; self.depth = depth
    }
}

/// Symbols from a line scan, with strings and comments masked by the lexer so `def x` in a docstring or a heading
/// inside a code fence never shows up.
public enum Outline {
    public static func items(_ text: String, language: SourceLanguage) -> [OutlineItem] {
        switch language {
        case .plain, .json: return []
        default: break
        }
        let units = Array(text.utf16)
        var mask = Mask(tokens: Lexer.tokens(text, language: language).filter { $0.kind == .string || $0.kind == .comment })
        var out: [OutlineItem] = []
        var pyStack: [Int] = []   // Python: indents of the open def/class blocks
        var braceDepth = 0        // Swift, TS/JS: unmasked { } depth at the start of the line
        var lineNo = 0
        var start = 0
        let n = units.count
        while start <= n {
            var end = start
            while end < n && units[end] != Ch.nl { end += 1 }
            lineNo += 1
            var first = start
            while first < end && Ch.isBlank(units[first]) { first += 1 }
            if first < end && !mask.covers(first) {
                let indent = indentWidth(units[start..<first])
                let line = String(decoding: units[first..<end], as: UTF16.self)
                switch language {
                case .python:
                    if let (name, kind) = python(line, topLevel: indent == 0) {
                        if kind == .constant {
                            out.append(OutlineItem(name: name, kind: kind, line: lineNo, depth: 0))
                        } else {
                            while let last = pyStack.last, last >= indent { pyStack.removeLast() }
                            out.append(OutlineItem(name: name, kind: kind, line: lineNo, depth: pyStack.count))
                            pyStack.append(indent)
                        }
                    }
                case .swift:
                    if let (name, kind) = swift(line, topLevel: braceDepth == 0) {
                        out.append(OutlineItem(name: name, kind: kind, line: lineNo, depth: braceDepth))
                    }
                case .typescript, .javascript:
                    if let (name, kind) = script(line, topLevel: braceDepth == 0) {
                        out.append(OutlineItem(name: name, kind: kind, line: lineNo, depth: braceDepth))
                    }
                case .markdown:
                    if let level = MarkdownScanner.headingLevel(units, at: first), first - start <= 3 {
                        var name = line.drop(while: { $0 == "#" }).trimmingCharacters(in: .whitespaces)
                        while name.hasSuffix("#") { name.removeLast() }
                        name = name.trimmingCharacters(in: .whitespaces)
                        if !name.isEmpty { out.append(OutlineItem(name: name, kind: .section, line: lineNo, depth: level)) }
                    }
                case .shell:
                    if let name = shell(line) { out.append(OutlineItem(name: name, kind: .function, line: lineNo, depth: 0)) }
                case .yaml:
                    if indent == 0, let name = yamlKey(line) {
                        out.append(OutlineItem(name: name, kind: .section, line: lineNo, depth: 0))
                    }
                case .plain, .json:
                    break
                }
            }
            if language == .swift || language == .typescript || language == .javascript {
                for k in first..<end where !mask.covers(k) {
                    if units[k] == Ch.lbrace { braceDepth += 1 } else if units[k] == Ch.rbrace { braceDepth = max(0, braceDepth - 1) }
                }
            }
            start = end + 1
        }
        return out
    }

    // MARK: Per language

    static func python(_ line: String, topLevel: Bool) -> (String, OutlineItem.Kind)? {
        var rest = Substring(line)
        if rest.hasPrefix("async ") { rest = rest.dropFirst(6).drop(while: { $0 == " " }) }
        if rest.hasPrefix("def ") { return identifier(rest.dropFirst(4)).map { ($0, .function) } }
        if rest.hasPrefix("class ") { return identifier(rest.dropFirst(6)).map { ($0, .type) } }
        guard topLevel, let name = identifier(rest), isUpperSnake(name) else { return nil }
        // NAME = …  or  NAME: Final = …  (not ==)
        var after = rest.dropFirst(name.count).drop(while: { $0 == " " })
        if after.hasPrefix(":") { after = after.drop(while: { $0 != "=" }) }
        guard after.hasPrefix("="), !after.hasPrefix("==") else { return nil }
        return (name, .constant)
    }

    private static let swiftModifiers: Set<String> = [
        "public", "private", "fileprivate", "internal", "open", "package", "static", "final", "override", "mutating",
        "nonmutating", "nonisolated", "indirect", "convenience", "required", "lazy", "weak", "unowned", "dynamic",
        "optional", "isolated"]

    static func swift(_ line: String, topLevel: Bool) -> (String, OutlineItem.Kind)? {
        var words = Substring(line)
        // Strip attributes (@MainActor, @available(…)) and modifiers (public, private(set), static, class func…).
        while true {
            words = words.drop(while: { $0 == " " || $0 == "\t" })
            if words.hasPrefix("@") {
                var w = words.dropFirst().drop(while: { $0.isLetter || $0.isNumber || $0 == "_" || $0 == "." })
                if w.hasPrefix("(") , let close = w.firstIndex(of: ")") { w = w[w.index(after: close)...] }
                words = w
                continue
            }
            guard let w = identifier(words) else { return nil }
            var after = words.dropFirst(w.count)
            if swiftModifiers.contains(w) {
                if after.hasPrefix("("), let close = after.firstIndex(of: ")") { after = after[after.index(after: close)...] }
                words = after
                continue
            }
            if w == "class", let nextWord = identifier(after.drop(while: { $0 == " " })), ["func", "var", "let"].contains(nextWord) {
                words = after
                continue
            }
            let rest = after.drop(while: { $0 == " " })
            switch w {
            case "func":
                let name = rest.prefix(while: { $0 != "(" && $0 != "<" && $0 != " " })
                return name.isEmpty ? nil : (String(name), .function)
            case "init":
                return after.hasPrefix("(") || after.hasPrefix("?(") || after.hasPrefix("<") ? ("init", .function) : nil
            case "struct", "class", "enum", "protocol", "actor", "typealias":
                return identifier(rest).map { ($0, .type) }
            case "extension":
                let name = rest.prefix(while: { $0.isLetter || $0.isNumber || $0 == "_" || $0 == "." })
                return name.isEmpty ? nil : (String(name), .type)
            case "let":
                guard topLevel else { return nil }
                return identifier(rest).map { ($0, .constant) }
            default:
                return nil
            }
        }
    }

    static func script(_ line: String, topLevel: Bool) -> (String, OutlineItem.Kind)? {
        var words = Substring(line)
        while let w = identifier(words), ["export", "default", "declare", "async", "abstract"].contains(w) {
            words = words.dropFirst(w.count).drop(while: { $0 == " " })
        }
        guard let w = identifier(words) else { return nil }
        var rest = words.dropFirst(w.count)
        switch w {
        case "function":
            if rest.hasPrefix("*") { rest = rest.dropFirst() }
            return identifier(rest.drop(while: { $0 == " " })).map { ($0, .function) }
        case "class", "interface", "enum", "namespace":
            return identifier(rest.drop(while: { $0 == " " })).map { ($0, .type) }
        case "type":
            guard let name = identifier(rest.drop(while: { $0 == " " })) else { return nil }
            return (name, .type)
        case "const":
            guard topLevel, let name = identifier(rest.drop(while: { $0 == " " })) else { return nil }
            guard let eq = rest.firstIndex(of: "=") else { return (name, .constant) }
            let value = rest[rest.index(after: eq)...].drop(while: { $0 == " " })
            let isFunction = value.hasPrefix("(") || value.hasPrefix("async") || value.hasPrefix("function")
                || value.contains("=>")
            return (name, isFunction ? .function : .constant)
        default:
            return nil
        }
    }

    static func shell(_ line: String) -> String? {
        if line.hasPrefix("function ") {
            let name = line.dropFirst(9).drop(while: { $0 == " " }).prefix(while: { !" ({".contains($0) })
            return name.isEmpty ? nil : String(name)
        }
        let name = line.prefix(while: { $0.isLetter || $0.isNumber || $0 == "_" || $0 == "-" || $0 == ":" || $0 == "." })
        guard !name.isEmpty else { return nil }
        let rest = line.dropFirst(name.count).drop(while: { $0 == " " })
        return rest.hasPrefix("()") ? String(name) : nil
    }

    static func yamlKey(_ line: String) -> String? {
        guard let colon = line.firstIndex(of: ":"), !line.hasPrefix("-") else { return nil }
        let after = line.index(after: colon)
        guard after == line.endIndex || line[after] == " " else { return nil }
        let key = line[..<colon].trimmingCharacters(in: CharacterSet(charactersIn: "\"' "))
        return key.isEmpty ? nil : key
    }

    // MARK: Helpers

    /// A leading identifier ([A-Za-z_][A-Za-z0-9_$]*), or nil.
    static func identifier(_ s: Substring) -> String? {
        guard let f = s.first, f.isLetter || f == "_" || f == "$" else { return nil }
        return String(s.prefix(while: { $0.isLetter || $0.isNumber || $0 == "_" || $0 == "$" }))
    }

    static func isUpperSnake(_ s: String) -> Bool {
        guard let f = s.first, f.isUppercase else { return false }
        return s.allSatisfy { $0.isUppercase || $0.isNumber || $0 == "_" }
    }

    static func indentWidth(_ s: ArraySlice<UInt16>) -> Int {
        s.reduce(0) { $0 + ($1 == Ch.tab ? 4 : 1) }
    }
}

/// Answers "is this offset inside a string or comment?" for increasing offsets in O(1) amortised.
struct Mask {
    let tokens: [SyntaxToken]
    var k = 0
    init(tokens: [SyntaxToken]) { self.tokens = tokens }

    mutating func covers(_ offset: Int) -> Bool {
        while k < tokens.count && tokens[k].end <= offset { k += 1 }
        return k < tokens.count && tokens[k].location <= offset
    }
}
