import Foundation

/// Syntax colouring for the editor (S07 §1.5): one shared scanner driven by per-language rules (LexerRules.swift),
/// plus a line-aware Markdown scanner. Returns only the coloured runs, sorted and non-overlapping; any gap is plain.
/// Works on the UTF-16 view so offsets are NSRange-ready and a 5,000-line file lexes in a few milliseconds.
public enum Lexer {
    public static func tokens(_ text: String, language: SourceLanguage) -> [SyntaxToken] {
        let units = Array(text.utf16)
        switch language {
        case .plain: return []
        case .markdown:
            var m = MarkdownScanner(s: units)
            m.run()
            return m.out
        default:
            var sc = Scanner(s: units, r: LexRules.rules(for: language))
            sc.run()
            return sc.out
        }
    }
}

// MARK: - Characters

enum Ch {
    static let tab: UInt16 = 9, nl: UInt16 = 10, cr: UInt16 = 13, space: UInt16 = 32
    static let bang: UInt16 = 33, dq: UInt16 = 34, hash: UInt16 = 35, dollar: UInt16 = 36, sq: UInt16 = 39
    static let lparen: UInt16 = 40, rparen: UInt16 = 41, star: UInt16 = 42, plus: UInt16 = 43, comma: UInt16 = 44
    static let minus: UInt16 = 45, dot: UInt16 = 46, slash: UInt16 = 47, colon: UInt16 = 58, lt: UInt16 = 60
    static let gt: UInt16 = 62, at: UInt16 = 64, lbracket: UInt16 = 91, backslash: UInt16 = 92, rbracket: UInt16 = 93
    static let underscore: UInt16 = 95, backtick: UInt16 = 96, lbrace: UInt16 = 123, rbrace: UInt16 = 125, tilde: UInt16 = 126

    @inline(__always) static func isDigit(_ c: UInt16) -> Bool { c >= 48 && c <= 57 }
    @inline(__always) static func isUpper(_ c: UInt16) -> Bool { c >= 65 && c <= 90 }
    @inline(__always) static func isLetter(_ c: UInt16) -> Bool { (c >= 97 && c <= 122) || isUpper(c) }
    @inline(__always) static func isSpace(_ c: UInt16) -> Bool { c == space || c == tab || c == nl || c == cr || c == 12 }
    @inline(__always) static func isBlank(_ c: UInt16) -> Bool { c == space || c == tab }
    static func units(_ s: String) -> [UInt16] { Array(s.utf16) }
}

// MARK: - Shared scanner

struct Scanner {
    let s: [UInt16]
    let n: Int
    let r: LexRules
    var out: [SyntaxToken] = []

    init(s: [UInt16], r: LexRules) { self.s = s; self.n = s.count; self.r = r; out.reserveCapacity(s.count / 6) }

    /// Append a run, merging it into the previous one when they touch and share a kind.
    mutating func emit(_ loc: Int, _ end: Int, _ kind: TokenKind) {
        guard end > loc, kind != .plain else { return }
        if let last = out.last, last.kind == kind, last.end == loc {
            out[out.count - 1].length = end - last.location
        } else {
            out.append(SyntaxToken(location: loc, length: end - loc, kind: kind))
        }
    }

    @inline(__always) func isIdentStart(_ c: UInt16) -> Bool {
        Ch.isLetter(c) || c == Ch.underscore || c >= 0x80 || (r.dollarInIdentifiers && c == Ch.dollar)
    }
    @inline(__always) func isIdentChar(_ c: UInt16) -> Bool { isIdentStart(c) || Ch.isDigit(c) }

    func matches(_ p: [UInt16], at i: Int) -> Bool {
        guard i + p.count <= n else { return false }
        for k in 0..<p.count where s[i + k] != p[k] { return false }
        return true
    }

    func lineEnd(from i: Int) -> Int {
        var j = i
        while j < n && s[j] != Ch.nl { j += 1 }
        return j
    }

    /// The next non-blank index on the same line (n at end of text).
    func nextNonBlank(_ i: Int) -> Int {
        var j = i
        while j < n && Ch.isBlank(s[j]) { j += 1 }
        return j
    }

    func word(_ a: Int, _ b: Int) -> String { String(decoding: s[a..<b], as: UTF16.self) }

    mutating func run() {
        var i = 0
        var prevWord = ""          // last identifier or keyword ("" after punctuation)
        var prevPunct: UInt16 = 0  // last punctuation character (0 after a word)
        var arrow = false          // the last punctuation was "->"
        var pending: TokenKind?    // the next identifier's kind, set by class/struct/def/func…

        func afterValue(_ p: inout UInt16, _ w: inout String, _ a: inout Bool, _ pend: inout TokenKind?) {
            p = 0; w = ""; a = false; pend = nil
        }

        while i < n {
            let c = s[i]
            if Ch.isSpace(c) { i += 1; continue }

            // Block comments: /* … */ (nested in Swift).
            if let bc = r.blockComments.first(where: { matches($0.open, at: i) }) {
                let end = scanBlockComment(i, bc)
                emit(i, end, .comment)
                i = end
                continue
            }
            // Line comments: # and //. In shell and YAML a '#' only starts a comment at a word boundary.
            if let lc = r.lineComments.first(where: { matches($0, at: i) }) {
                let boundary = i == 0 || Ch.isSpace(s[i - 1])
                if !(r.hashCommentNeedsBoundary && lc == [Ch.hash] && !boundary) {
                    let end = lineEnd(from: i)
                    emit(i, end, .comment)
                    i = end
                    continue
                }
            }
            // Swift raw strings (#"…"#) and directives (#if, #selector).
            if r.swiftExtras && c == Ch.hash {
                var j = i
                while j < n && s[j] == Ch.hash { j += 1 }
                if j < n && s[j] == Ch.dq {
                    let end = scanRawString(i, hashes: j - i)
                    emit(i, end, .string)
                    afterValue(&prevPunct, &prevWord, &arrow, &pending)
                    i = end
                    continue
                }
                if j == i + 1 && j < n && isIdentStart(s[j]) {
                    var k = j + 1
                    while k < n && isIdentChar(s[k]) { k += 1 }
                    emit(i, k, .keyword)
                    i = k
                    continue
                }
            }
            // Strings.
            if r.quotes.contains(c) {
                let end = scanString(i)
                var kind = TokenKind.string
                if let kk = r.keyKind {
                    let k = nextNonBlank(end)
                    if k < n && s[k] == Ch.colon { kind = kk }
                }
                emit(i, end, kind)
                afterValue(&prevPunct, &prevWord, &arrow, &pending)
                i = end
                continue
            }
            // Numbers.
            if Ch.isDigit(c) {
                let end = scanNumber(i)
                emit(i, end, .number)
                afterValue(&prevPunct, &prevWord, &arrow, &pending)
                i = end
                continue
            }
            // Attributes and decorators: @MainActor, @dataclass.
            if r.attributes && c == Ch.at && i + 1 < n && isIdentStart(s[i + 1]) {
                var j = i + 2
                while j < n && (isIdentChar(s[j]) || (s[j] == Ch.dot && j + 1 < n && isIdentStart(s[j + 1]))) { j += 1 }
                emit(i, j, .keyword)
                i = j
                continue
            }
            // Shell variables: $NAME, ${NAME}, $1, $?.
            if r.shellVariables && c == Ch.dollar && i + 1 < n {
                let d = s[i + 1]
                var j = i + 1
                if d == Ch.lbrace {
                    while j < n && s[j] != Ch.rbrace && s[j] != Ch.nl { j += 1 }
                    j = min(j + 1, n)
                } else if isIdentStart(d) {
                    j += 1
                    while j < n && isIdentChar(s[j]) { j += 1 }
                } else if Ch.isDigit(d) || d == Ch.hash || d == 63 /* ? */ || d == Ch.at || d == Ch.star || d == Ch.bang
                            || d == Ch.dollar || d == Ch.minus {
                    j += 1
                }
                if j > i + 1 {
                    emit(i, j, .type)
                    afterValue(&prevPunct, &prevWord, &arrow, &pending)
                    i = j
                    continue
                }
            }
            // Identifiers, keywords, types, function names.
            if isIdentStart(c) {
                var j = i + 1
                while j < n && isIdentChar(s[j]) { j += 1 }
                if r.bareKeys {
                    while j < n && (isIdentChar(s[j]) || s[j] == Ch.minus || s[j] == Ch.dot) { j += 1 }
                }
                // Python string prefixes: r"…", b'…', f"…", rb"…".
                if !r.stringPrefixes.isEmpty && j - i <= 2 && j < n && r.quotes.contains(s[j])
                    && r.stringPrefixes.contains(word(i, j).lowercased()) {
                    let end = scanString(j)
                    emit(i, end, .string)
                    afterValue(&prevPunct, &prevWord, &arrow, &pending)
                    i = end
                    continue
                }
                let w = word(i, j)
                let next = nextNonBlank(j)
                let nextChar: UInt16 = next < n ? s[next] : 0
                var kind = TokenKind.plain
                var newPending: TokenKind?
                if let kk = r.keyKind, r.bareKeys, nextChar == Ch.colon, next + 1 >= n || Ch.isSpace(s[next + 1]) {
                    kind = kk
                } else if r.keywords.contains(w) {
                    kind = .keyword
                    if r.typeIntroducers.contains(w) { newPending = .type }
                    else if r.functionIntroducers.contains(w) { newPending = .function }
                } else if let p = pending {
                    kind = p
                } else if r.builtinTypes.contains(w) {
                    kind = .type
                } else if Ch.isUpper(c) && (r.typeAfterPunct.contains(prevPunct) || (r.arrowTypes && arrow)
                                            || (!prevWord.isEmpty && r.typeAfterWords.contains(prevWord))) {
                    kind = .type
                } else if nextChar == Ch.lparen {
                    kind = Ch.isUpper(c) ? .type : .function
                }
                emit(i, j, kind)
                prevWord = w
                prevPunct = 0
                arrow = false
                pending = newPending
                i = j
                continue
            }
            // Punctuation.
            arrow = c == Ch.gt && i > 0 && s[i - 1] == Ch.minus
            prevPunct = c
            prevWord = ""
            if c != Ch.star { pending = nil }   // function* gen()
            i += 1
        }
    }

    func scanBlockComment(_ i: Int, _ bc: LexRules.Block) -> Int {
        var depth = 1
        var j = i + bc.open.count
        while j < n {
            if matches(bc.close, at: j) {
                depth -= 1
                j += bc.close.count
                if depth == 0 { return j }
                continue
            }
            if r.nestedBlockComments && matches(bc.open, at: j) {
                depth += 1
                j += bc.open.count
                continue
            }
            j += 1
        }
        return n
    }

    /// From an opening quote to just past its close (or the line end for an unterminated single-line string).
    func scanString(_ i: Int) -> Int {
        let q = s[i]
        let raw = r.rawQuotes.contains(q)
        if r.tripleQuotes.contains(q) && i + 2 < n && s[i + 1] == q && s[i + 2] == q {
            var j = i + 3
            while j < n {
                if s[j] == Ch.backslash && !raw { j += 2; continue }
                if s[j] == q && j + 2 < n && s[j + 1] == q && s[j + 2] == q {
                    // """" closes on the last three quotes.
                    var k = j + 3
                    while k < n && s[k] == q { k += 1 }
                    return k
                }
                j += 1
            }
            return n
        }
        let multiline = r.multilineQuotes.contains(q)
        var j = i + 1
        while j < n {
            let c = s[j]
            if c == q { return j + 1 }
            if c == Ch.backslash && !raw {
                if r.swiftExtras && j + 1 < n && s[j + 1] == Ch.lparen {
                    j = skipCode(j + 2, open: Ch.lparen, close: Ch.rparen)
                    continue
                }
                j += 2
                continue
            }
            if q == Ch.backtick && r.templateInterpolation && c == Ch.dollar && j + 1 < n && s[j + 1] == Ch.lbrace {
                j = skipCode(j + 2, open: Ch.lbrace, close: Ch.rbrace)
                continue
            }
            if c == Ch.nl && !multiline { return j }
            j += 1
        }
        return n
    }

    /// Skip an interpolated expression (\( … ) or ${ … }), stepping over strings nested inside it.
    func skipCode(_ from: Int, open: UInt16, close: UInt16) -> Int {
        var depth = 1
        var j = from
        while j < n {
            let c = s[j]
            if r.quotes.contains(c) { j = scanString(j); continue }
            if c == open { depth += 1 }
            else if c == close {
                depth -= 1
                if depth == 0 { return j + 1 }
            } else if c == Ch.nl && open == Ch.lparen { return j }
            j += 1
        }
        return n
    }

    /// Swift raw string: #"…"# (any number of #, single or triple quoted).
    func scanRawString(_ i: Int, hashes: Int) -> Int {
        let triple = i + hashes + 2 < n && s[i + hashes + 1] == Ch.dq && s[i + hashes + 2] == Ch.dq
        var j = i + hashes + (triple ? 3 : 1)
        while j < n {
            if s[j] == Ch.nl && !triple { return j }
            if s[j] == Ch.dq {
                var k = j + 1
                var h = 0
                while k < n && h < hashes && s[k] == Ch.hash { k += 1; h += 1 }
                if h == hashes { return k }
            }
            j += 1
        }
        return n
    }

    func scanNumber(_ i: Int) -> Int {
        let hex = s[i] == 48 && i + 1 < n && (s[i + 1] == 120 || s[i + 1] == 88)
        var j = i + 1
        while j < n {
            let c = s[j]
            if Ch.isDigit(c) || Ch.isLetter(c) || c == Ch.underscore { j += 1; continue }
            if c == Ch.dot && j + 1 < n && Ch.isDigit(s[j + 1]) { j += 1; continue }
            if (c == Ch.plus || c == Ch.minus) && !hex && (s[j - 1] == 101 || s[j - 1] == 69) { j += 1; continue }
            break
        }
        return j
    }
}

// MARK: - Markdown

/// Markdown: ATX headings → keyword, fenced blocks and `code spans` → string, [links](url) → type,
/// <!-- comments --> → comment.
struct MarkdownScanner {
    let s: [UInt16]
    let n: Int
    var out: [SyntaxToken] = []

    init(s: [UInt16]) { self.s = s; self.n = s.count }

    mutating func emit(_ loc: Int, _ end: Int, _ kind: TokenKind) {
        guard end > loc else { return }
        if let last = out.last, last.kind == kind, last.end == loc {
            out[out.count - 1].length = end - last.location
        } else {
            out.append(SyntaxToken(location: loc, length: end - loc, kind: kind))
        }
    }

    func lineEnd(from i: Int) -> Int {
        var j = i
        while j < n && s[j] != Ch.nl { j += 1 }
        return j
    }

    /// Up to three leading spaces, then the first significant index.
    func indentEnd(_ i: Int) -> Int {
        var j = i
        while j < n && j - i < 3 && s[j] == Ch.space { j += 1 }
        return j
    }

    func isFence(_ j: Int) -> Bool {
        guard j + 2 < n else { return false }
        let c = s[j]
        return (c == Ch.backtick || c == Ch.tilde) && s[j + 1] == c && s[j + 2] == c
    }

    /// Heading level (1…6) when a line starts with #… followed by a space or the line end.
    static func headingLevel(_ s: [UInt16], at j: Int) -> Int? {
        var k = j
        while k < s.count && s[k] == Ch.hash && k - j < 7 { k += 1 }
        let level = k - j
        guard level >= 1 && level <= 6 else { return nil }
        guard k == s.count || s[k] == Ch.space || s[k] == Ch.tab || s[k] == Ch.nl else { return nil }
        return level
    }

    mutating func run() {
        var i = 0
        var inFence = false
        while i < n {
            if i == 0 || s[i - 1] == Ch.nl {
                let end = lineEnd(from: i)
                let lineWithBreak = min(end + 1, n)
                let j = indentEnd(i)
                if isFence(j) {
                    inFence.toggle()
                    emit(i, lineWithBreak, .string)
                    i = lineWithBreak
                    continue
                }
                if inFence {
                    emit(i, lineWithBreak, .string)
                    i = lineWithBreak
                    continue
                }
                if Self.headingLevel(s, at: j) != nil {
                    emit(i, end, .keyword)
                    i = end
                    continue
                }
            }
            let c = s[i]
            if c == Ch.lt && i + 3 < n && s[i + 1] == Ch.bang && s[i + 2] == Ch.minus && s[i + 3] == Ch.minus {
                var j = i + 4
                while j < n && !(s[j] == Ch.minus && j + 2 < n && s[j + 1] == Ch.minus && s[j + 2] == Ch.gt) { j += 1 }
                let end = min(j + 3, n)
                emit(i, end, .comment)
                i = end
                continue
            }
            if c == Ch.backtick {
                var k = i
                while k < n && s[k] == Ch.backtick { k += 1 }
                let ticks = k - i
                // Find a closing run of exactly the same length before a blank line.
                var j = k
                var close = -1
                while j < n {
                    if s[j] == Ch.nl && j + 1 < n && s[j + 1] == Ch.nl { break }
                    if s[j] == Ch.backtick {
                        var e = j
                        while e < n && s[e] == Ch.backtick { e += 1 }
                        if e - j == ticks { close = e; break }
                        j = e
                        continue
                    }
                    j += 1
                }
                if close > 0 { emit(i, close, .string); i = close } else { i = k }
                continue
            }
            if c == Ch.lbracket || (c == Ch.bang && i + 1 < n && s[i + 1] == Ch.lbracket) {
                if let end = linkEnd(c == Ch.bang ? i + 1 : i) {
                    emit(i, end, .type)
                    i = end
                    continue
                }
            }
            i += 1
        }
    }

    /// [text](url) on one line: the index just past ')'.
    func linkEnd(_ open: Int) -> Int? {
        var j = open + 1
        while j < n && s[j] != Ch.rbracket && s[j] != Ch.nl { j += 1 }
        guard j + 1 < n, s[j] == Ch.rbracket, s[j + 1] == Ch.lparen else { return nil }
        var k = j + 2
        while k < n && s[k] != Ch.rparen && s[k] != Ch.nl { k += 1 }
        guard k < n, s[k] == Ch.rparen else { return nil }
        return k + 1
    }
}
