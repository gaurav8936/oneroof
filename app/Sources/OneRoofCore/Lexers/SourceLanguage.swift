import Foundation

/// The languages the editor colours, outlines and runs. Decision D7: no LSP, so everything here is a small
/// hand-written lexer per language; anything else opens as plain text.
public enum SourceLanguage: String, Sendable {
    case python, swift, typescript, javascript, json, yaml, markdown, shell, plain

    /// The language for a file, by extension only (no shebang sniffing; the editor has the path before the bytes).
    public static func detect(path: String) -> SourceLanguage {
        switch (path as NSString).pathExtension.lowercased() {
        case "py", "pyi", "pyw": return .python
        case "swift": return .swift
        case "ts", "tsx", "mts", "cts": return .typescript
        case "js", "mjs", "cjs", "jsx": return .javascript
        case "json", "jsonc": return .json
        case "yml", "yaml": return .yaml
        case "md", "markdown": return .markdown
        case "sh", "zsh", "bash": return .shell
        default: return .plain
        }
    }
}

/// What a run of source text is, for colouring (ThemeTokens.syntax).
public enum TokenKind: String, Sendable, CaseIterable {
    case keyword, string, comment, type, function, number, plain
}

/// One coloured run. Offsets are UTF-16 (NSString / NSRange units) so the app applies them to NSTextStorage as-is.
public struct SyntaxToken: Equatable, Sendable {
    public var location: Int
    public var length: Int
    public var kind: TokenKind
    public init(location: Int, length: Int, kind: TokenKind) { self.location = location; self.length = length; self.kind = kind }
    public var end: Int { location + length }
}
