import Foundation

/// Per-language rules for the shared scanner (Lexer.swift). Small on purpose: keywords, comment and string shapes,
/// and a few context hints for types and function names. No grammar, no LSP (Decision D7).
struct LexRules: Sendable {
    struct Block: Sendable { var open: [UInt16]; var close: [UInt16] }

    var lineComments: [[UInt16]] = []
    /// Shell, YAML: '#' starts a comment only at the start of a word (`$#`, `a#b` are not comments).
    var hashCommentNeedsBoundary = false
    var blockComments: [Block] = []
    var nestedBlockComments = false
    /// Characters that open a string; of those, which have no backslash escapes, which may cross lines, and which
    /// open a multi-line string when tripled.
    var quotes: Set<UInt16> = []
    var rawQuotes: Set<UInt16> = []
    var multilineQuotes: Set<UInt16> = []
    var tripleQuotes: Set<UInt16> = []
    /// ${ … } inside `template literals` (nested strings are skipped).
    var templateInterpolation = false
    /// Swift: \( … ) interpolation, #"raw"# strings and #directives.
    var swiftExtras = false
    /// Python: r"…", b"…", f"…" and combinations.
    var stringPrefixes: Set<String> = []
    var keywords: Set<String> = []
    var builtinTypes: Set<String> = []
    /// Keywords whose next identifier is a type (class Foo) or a function name (def foo).
    var typeIntroducers: Set<String> = []
    var functionIntroducers: Set<String> = []
    /// A Capitalised identifier is a type after these words (extends Foo, as Foo) or punctuation (: Foo, <Foo>).
    var typeAfterWords: Set<String> = []
    var typeAfterPunct: Set<UInt16> = []
    /// … and after "->".
    var arrowTypes = false
    /// @Attribute / @decorator → keyword.
    var attributes = false
    /// $NAME, ${NAME}, $1 → type.
    var shellVariables = false
    var dollarInIdentifiers = false
    /// JSON, YAML: a key (string or, with bareKeys, word) before ':' gets this kind.
    var keyKind: TokenKind?
    var bareKeys = false

    static func rules(for language: SourceLanguage) -> LexRules {
        switch language {
        case .python: return python
        case .swift: return swift
        case .typescript: return typescript
        case .javascript: return javascript
        case .json: return json
        case .yaml: return yaml
        case .shell: return shell
        case .markdown, .plain: return LexRules()
        }
    }

    private static let cBlock = Block(open: Ch.units("/*"), close: Ch.units("*/"))

    static let python: LexRules = {
        var r = LexRules()
        r.lineComments = [Ch.units("#")]
        r.quotes = [Ch.dq, Ch.sq]
        r.tripleQuotes = [Ch.dq, Ch.sq]
        r.stringPrefixes = ["r", "u", "b", "f", "br", "rb", "fr", "rf"]
        r.keywords = ["False", "None", "True", "and", "as", "assert", "async", "await", "break", "class", "continue",
                      "def", "del", "elif", "else", "except", "finally", "for", "from", "global", "if", "import", "in",
                      "is", "lambda", "nonlocal", "not", "or", "pass", "raise", "return", "try", "while", "with",
                      "yield", "match", "case"]
        r.builtinTypes = ["int", "float", "str", "bool", "bytes", "bytearray", "list", "dict", "set", "frozenset",
                          "tuple", "object", "complex", "type"]
        r.typeIntroducers = ["class"]
        r.functionIntroducers = ["def"]
        r.typeAfterPunct = [Ch.colon]
        r.arrowTypes = true
        r.attributes = true
        return r
    }()

    static let swift: LexRules = {
        var r = LexRules()
        r.lineComments = [Ch.units("//")]
        r.blockComments = [cBlock]
        r.nestedBlockComments = true
        r.quotes = [Ch.dq]
        r.tripleQuotes = [Ch.dq]
        r.swiftExtras = true
        r.keywords = ["associatedtype", "class", "deinit", "enum", "extension", "fileprivate", "func", "import", "init",
                      "inout", "internal", "let", "open", "operator", "private", "precedencegroup", "protocol",
                      "public", "rethrows", "static", "struct", "subscript", "typealias", "var", "break", "case",
                      "catch", "continue", "default", "defer", "do", "else", "fallthrough", "for", "guard", "if", "in",
                      "repeat", "return", "throw", "switch", "where", "while", "as", "Any", "await", "false", "is",
                      "nil", "self", "Self", "super", "throws", "true", "try", "async", "actor", "some", "any",
                      "convenience", "dynamic", "final", "indirect", "lazy", "mutating", "nonmutating", "optional",
                      "override", "required", "unowned", "weak", "willSet", "didSet", "nonisolated", "package"]
        r.builtinTypes = ["Int", "Int8", "Int16", "Int32", "Int64", "UInt", "UInt8", "UInt16", "UInt32", "UInt64",
                          "Double", "Float", "CGFloat", "Bool", "String", "Character", "Substring", "Array",
                          "Dictionary", "Set", "Optional", "Result", "Void", "Never", "Error", "Data", "Date", "URL",
                          "UUID", "Range", "ClosedRange", "Equatable", "Hashable", "Codable", "Sendable",
                          "Identifiable", "Comparable"]
        r.typeIntroducers = ["class", "struct", "enum", "protocol", "extension", "actor", "typealias", "associatedtype"]
        r.functionIntroducers = ["func"]
        r.typeAfterWords = ["as", "is"]
        r.typeAfterPunct = [Ch.colon, Ch.lt, Ch.lbracket, Ch.comma]
        r.arrowTypes = true
        r.attributes = true
        return r
    }()

    private static let jsKeywords: Set<String> = [
        "break", "case", "catch", "class", "const", "continue", "debugger", "default", "delete", "do", "else", "export",
        "extends", "finally", "for", "function", "if", "import", "in", "instanceof", "new", "return", "super", "switch",
        "this", "throw", "try", "typeof", "var", "void", "while", "with", "yield", "let", "static", "async", "await",
        "of", "true", "false", "null", "undefined"]

    static let javascript: LexRules = {
        var r = LexRules()
        r.lineComments = [Ch.units("//")]
        r.blockComments = [cBlock]
        r.quotes = [Ch.dq, Ch.sq, Ch.backtick]
        r.multilineQuotes = [Ch.backtick]
        r.templateInterpolation = true
        r.dollarInIdentifiers = true
        r.keywords = jsKeywords
        r.builtinTypes = ["Array", "Promise", "Map", "Set", "Date", "Error", "RegExp", "Object", "JSON", "Math"]
        r.typeIntroducers = ["class"]
        r.functionIntroducers = ["function"]
        r.typeAfterWords = ["extends", "new", "instanceof"]
        r.attributes = true
        return r
    }()

    static let typescript: LexRules = {
        var r = javascript
        r.keywords.formUnion(["as", "implements", "interface", "package", "private", "protected", "public", "type",
                              "enum", "declare", "abstract", "readonly", "keyof", "namespace", "module", "from",
                              "satisfies", "is", "infer"])
        r.builtinTypes.formUnion(["string", "number", "boolean", "any", "unknown", "never", "object", "symbol",
                                  "bigint", "Record", "Partial", "Readonly", "Pick", "Omit"])
        r.typeIntroducers = ["class", "interface", "type", "enum", "namespace"]
        r.typeAfterWords = ["extends", "implements", "new", "instanceof", "as", "keyof", "satisfies", "is"]
        r.typeAfterPunct = [Ch.colon, Ch.lt]
        r.arrowTypes = false
        return r
    }()

    static let json: LexRules = {
        var r = LexRules()
        r.lineComments = [Ch.units("//")]   // JSONC; a real JSON file never has a bare //
        r.blockComments = [cBlock]
        r.quotes = [Ch.dq]
        r.keywords = ["true", "false", "null"]
        r.keyKind = .type
        return r
    }()

    static let yaml: LexRules = {
        var r = LexRules()
        r.lineComments = [Ch.units("#")]
        r.hashCommentNeedsBoundary = true
        r.quotes = [Ch.dq, Ch.sq]
        r.rawQuotes = [Ch.sq]
        r.keywords = ["true", "false", "null", "yes", "no", "on", "off", "True", "False", "Null", "~"]
        r.keyKind = .keyword
        r.bareKeys = true
        return r
    }()

    static let shell: LexRules = {
        var r = LexRules()
        r.lineComments = [Ch.units("#")]
        r.hashCommentNeedsBoundary = true
        r.quotes = [Ch.dq, Ch.sq]
        r.rawQuotes = [Ch.sq]
        r.multilineQuotes = [Ch.dq, Ch.sq]
        r.keywords = ["if", "then", "else", "elif", "fi", "case", "esac", "for", "select", "while", "until", "do", "done",
                      "in", "function", "time", "return", "local", "export", "readonly", "declare", "typeset", "unset",
                      "break", "continue", "exit", "source", "alias"]
        r.functionIntroducers = ["function"]
        r.shellVariables = true
        return r
    }()
}
